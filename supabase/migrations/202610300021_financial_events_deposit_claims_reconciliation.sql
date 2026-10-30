begin;

-- The deposit position is per booking and payer, not an account wallet. A
-- security-definer RPC scopes every result to auth.uid(); the view is dropped
-- because a normal view can inadvertently inherit broad owner privileges.
drop view if exists public.deposit_positions;
create or replace function public.get_my_deposit_positions()
returns table(
  deposit_id uuid, booking_id uuid, status public.deposit_status,
  amount_paise bigint, locked_paise bigint, available_for_release_paise bigint,
  currency char(3), provider_reference text
)
language sql stable security definer
set search_path = pg_catalog, public
as $$
  select d.id,d.booking_id,d.status,d.amount_paise,
    case when d.status in ('held_by_provider','claim_hold_pending','claim_hold','release_pending','refund_pending','partially_applied')
      then greatest(d.amount_paise-coalesce((
        select sum(case when dl.event_type in ('released','amount_applied') then dl.amount_paise else 0 end)
        from public.deposit_ledger dl where dl.deposit_id=d.id
      ),0),0)::bigint else 0::bigint end,
    case when d.status in ('held_by_provider','partially_applied') and b.status='completed'
      and not exists(select 1 from public.disputes x where x.booking_id=b.id and x.status<>'closed')
      and not exists(select 1 from public.deposit_claims x where x.deposit_id=d.id and x.status not in ('rejected','closed'))
      and not exists(select 1 from public.bookings active
        where (active.reader_id=d.payer_id or active.owner_id=d.payer_id)
          and active.status::text in ('owner_accepted','payment_pending','confirmed','collection_pending','active','return_pending','disputed'))
      then greatest(d.amount_paise-coalesce((
        select sum(case when dl.event_type in ('released','amount_applied') then dl.amount_paise else 0 end)
        from public.deposit_ledger dl where dl.deposit_id=d.id
      ),0),0)::bigint else 0::bigint end,
    d.currency,d.provider_reference
  from public.deposits d
  join public.bookings b on b.id=d.booking_id
  where d.payer_id=auth.uid()
  order by d.created_at desc;
$$;
revoke all on function public.get_my_deposit_positions() from public,anon;
grant execute on function public.get_my_deposit_positions() to authenticated;

-- The amount/custody calculation is not invented. A trusted finance operation
-- may configure a per-booking deposit only after a live provider deposit model
-- and separate legal/accounting approvals are on record.
create or replace function public.configure_booking_deposit(
  p_booking_id uuid,p_provider text,p_amount_paise bigint,p_policy_version text,p_custody_descriptor text
) returns uuid
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_booking public.bookings%rowtype; v_approval public.payment_provider_approvals%rowtype;
  v_deposit uuid; v_actor uuid:=auth.uid();
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then
    if not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
      and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance approval required'; end if;
  end if;
  if p_amount_paise is null or p_amount_paise<=0 or length(btrim(coalesce(p_policy_version,'')))<3
    or length(btrim(coalesce(p_custody_descriptor,'')))<10 then
    raise exception 'Approved deposit amount, policy version and custody disclosure are required';
  end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.status not in ('owner_accepted','payment_pending','confirmed') then
    raise exception 'Deposit can only be configured before collection';
  end if;
  if exists(select 1 from public.deposits where booking_id=p_booking_id) then raise exception 'A deposit record already exists'; end if;
  select * into v_approval from public.payment_provider_approvals
    where provider_code=p_provider and enabled_for_rent and enabled_for_deposits
      and marketplace_model='peer_to_peer_physical_book_rental'
      and supports_deposit_hold and supports_deposit_release
      and supports_deposit_dispute_hold and supports_deposit_application
      and length(btrim(coalesce(legal_approval_reference,'')))>=5
      and length(btrim(coalesce(accounting_approval_reference,'')))>=5
      and (expires_at is null or expires_at>now());
  if not found then raise exception 'Separate written provider, legal and accounting deposit approvals are required'; end if;
  insert into public.deposits(booking_id,payer_id,provider,amount_paise,status,custody_descriptor,
    legal_approval_reference,policy_version,feature_enabled_at_creation)
  values(p_booking_id,v_booking.reader_id,p_provider,p_amount_paise,'collection_pending',
    left(p_custody_descriptor,500),v_approval.legal_approval_reference,p_policy_version,true)
  returning id into v_deposit;
  update public.bookings set deposit_required_paise=p_amount_paise,
    policy_snapshot=policy_snapshot||jsonb_build_object('deposit_policy_version',p_policy_version,'deposit_required_paise',p_amount_paise)
    where id=p_booking_id;
  insert into public.deposit_ledger(deposit_id,event_type,amount_paise,idempotency_key,metadata)
  values(v_deposit,'collection_requested',p_amount_paise,'deposit-collection:'||v_deposit::text,
    jsonb_build_object('policy_version',p_policy_version,'provider_approval_id',v_approval.id));
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
  values('deposit',v_deposit,'deposit_collection_requested',
    jsonb_build_object('deposit_id',v_deposit,'amount_paise',p_amount_paise,'provider',p_provider),
    'deposit-collection-outbox:'||v_deposit::text) on conflict(idempotency_key) do nothing;
  return v_deposit;
end;
$$;
revoke all on function public.configure_booking_deposit(uuid,text,bigint,text,text) from public,anon;
grant execute on function public.configure_booking_deposit(uuid,text,bigint,text,text) to authenticated,service_role;

-- Prevent a rent-only checkout from silently bypassing a configured deposit.
create or replace function public.begin_booking_payment(
  p_booking_id uuid,p_provider text,p_idempotency_key text,p_merchant_reference text
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_booking public.bookings%rowtype; v_item public.rental_items%rowtype; v_copy public.book_copies%rowtype;
  v_cfg public.booking_workflow_configuration%rowtype; v_provider public.payment_provider_approvals%rowtype;
  v_payment uuid; v_amount bigint; v_expires timestamptz; v_active_payment public.payments%rowtype;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if length(coalesce(p_idempotency_key,''))<16 or length(coalesce(p_merchant_reference,''))<8 then raise exception 'Payment idempotency and merchant references are required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.status not in ('owner_accepted','payment_pending') then raise exception 'Only Owner-accepted bookings can proceed to payment'; end if;
  if v_booking.deposit_required_paise>0 then
    if not exists(select 1 from public.deposits d where d.booking_id=v_booking.id and d.feature_enabled_at_creation and d.status='held_by_provider') then
      raise exception 'A configured provider-backed deposit instruction is required before rent checkout';
    end if;
  end if;
  select * into v_cfg from public.booking_workflow_configuration where id=true and is_active;
  if not found or v_cfg.payment_hold_seconds is null or v_cfg.rental_duration_mode is null
    or v_cfg.tax_policy_version is null or v_cfg.cancellation_policy_version is null
    or v_cfg.tax_approval_reference is null or v_booking.tax_calculated_at is null
    or v_booking.payment_policy_version is distinct from v_cfg.tax_policy_version then
    raise exception 'Approved booking, tax and cancellation policy plus per-booking tax calculation are required before checkout';
  end if;
  select * into v_provider from public.payment_provider_approvals
    where provider_code=p_provider and enabled_for_rent
      and marketplace_model='peer_to_peer_physical_book_rental'
      and (expires_at is null or expires_at>now());
  if not found then raise exception 'No provider is approved for the ShelfShare peer-to-peer rental model'; end if;
  select * into v_active_payment from public.payments
    where booking_id=v_booking.id and provider=p_provider and status in ('created','pending','authorized')
    order by created_at desc limit 1 for update;
  if found then return v_active_payment.id; end if;
  if exists(select 1 from public.payments where idempotency_key=p_idempotency_key) then
    select id into v_payment from public.payments where idempotency_key=p_idempotency_key;
    return v_payment;
  end if;
  select * into v_item from public.rental_items where booking_id=p_booking_id limit 1;
  select * into v_copy from public.book_copies where id=v_item.book_copy_id for update;
  perform private.assert_booking_request_identity(v_booking.reader_id,v_copy,v_booking.requested_handover_location_id);
  if not exists(select 1 from public.provider_vendor_accounts x
    where x.provider_approval_id=v_provider.id and x.user_id=v_copy.owner_id and x.kyc_status='verified') then
    raise exception 'Owner has not completed provider vendor onboarding and KYC';
  end if;
  update public.copy_reservations set status='expired'
    where book_copy_id=v_copy.id and status='hold' and expires_at<=now();
  if exists(select 1 from public.book_availability_blocks x where x.book_copy_id=v_copy.id and x.blocked_period&&v_item.reserved_period)
    or exists(select 1 from public.copy_reservations x where x.book_copy_id=v_copy.id and x.status in ('hold','confirmed','in_use')
      and x.reserved_period&&v_item.reserved_period and (x.status<>'hold' or x.expires_at is null or x.expires_at>now())) then
    raise exception 'Copy is no longer available; request a new date range';
  end if;
  v_amount:=v_booking.rent_subtotal_paise+v_booking.tax_paise;
  if v_amount<=0 then raise exception 'Invalid payment amount'; end if;
  v_expires:=now()+make_interval(secs=>v_cfg.payment_hold_seconds);
  insert into public.copy_reservations(rental_item_id,booking_id,book_copy_id,reserved_period,status,expires_at)
    values(v_item.id,v_booking.id,v_item.book_copy_id,v_item.reserved_period,'hold',v_expires);
  insert into public.payments(booking_id,payer_id,provider,idempotency_key,amount_paise,currency,status,merchant_reference)
    values(v_booking.id,v_booking.reader_id,p_provider,p_idempotency_key,v_amount,'INR','created',p_merchant_reference)
    returning id into v_payment;
  update public.bookings set status='payment_pending' where id=v_booking.id;
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('booking',v_booking.id,'payment_intent_requested',
      jsonb_build_object('payment_id',v_payment,'provider',p_provider,'amount_paise',v_amount,'currency','INR','merchant_reference',p_merchant_reference),
      'payment-intent:'||p_idempotency_key) on conflict(idempotency_key) do nothing;
  insert into public.booking_audit_events(booking_id,event_type,from_status,to_status,metadata,idempotency_key)
    values(v_booking.id,'payment_attempt_created','owner_accepted','payment_pending',
      jsonb_build_object('payment_id',v_payment,'amount_paise',v_amount,'hold_expires_at',v_expires),
      'payment-attempt:'||p_idempotency_key) on conflict(idempotency_key) do nothing;
  return v_payment;
end;
$$;
revoke all on function public.begin_booking_payment(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.begin_booking_payment(uuid,text,text,text) to service_role;

-- Tax must be calculated under a CA-approved policy before checkout. This
-- function accepts only a result from a trusted server-side tax integration.
create or replace function public.record_booking_tax_calculation(
  p_booking_id uuid,p_tax_paise bigint,p_policy_version text
) returns void language plpgsql security definer
set search_path = pg_catalog, public
as $
declare v_booking public.bookings%rowtype; v_cfg public.booking_workflow_configuration%rowtype;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted tax service required'; end if;
  if p_tax_paise is null or p_tax_paise<0 or length(btrim(coalesce(p_policy_version,'')))<3 then
    raise exception 'Tax result and approved policy version are required';
  end if;
  select * into v_cfg from public.booking_workflow_configuration where id=true and is_active;
  if not found or v_cfg.tax_policy_version is distinct from p_policy_version
    or v_cfg.tax_approval_reference is null or v_cfg.tax_approved_by is null or v_cfg.tax_approved_at is null then
    raise exception 'No matching CA-approved tax policy is active';
  end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.status<>'owner_accepted' or v_booking.tax_calculated_at is not null then
    raise exception 'Tax can only be calculated once before checkout';
  end if;
  if exists(select 1 from public.payments where booking_id=p_booking_id) then
    raise exception 'Tax cannot be changed after a payment attempt exists';
  end if;
  update public.bookings set tax_paise=p_tax_paise,payment_policy_version=p_policy_version,tax_calculated_at=now()
    where id=p_booking_id;
  insert into public.booking_audit_events(booking_id,event_type,metadata,idempotency_key)
    values(p_booking_id,'tax_calculated',
      jsonb_build_object('tax_paise',p_tax_paise,'policy_version',p_policy_version),
      'booking-tax:'||p_booking_id::text);
end;
$;
revoke all on function public.record_booking_tax_calculation(uuid,bigint,text) from public,anon,authenticated;
grant execute on function public.record_booking_tax_calculation(uuid,bigint,text) to service_role;

-- Final owner payable is calculated only after a finance reviewer has checked
-- tax withholding and provider fees. This is not a provider settlement or a
-- representation that the marketplace has received money.
create or replace function public.record_owner_settlement_calculation(
  p_actor_id uuid,p_earning_id uuid,p_tax_withheld_paise bigint,p_provider_fee_paise bigint,
  p_adjustment_paise bigint,p_policy_version text
) returns bigint language plpgsql security definer
set search_path = pg_catalog, public
as $
declare v_earning public.owner_earnings%rowtype; v_net bigint;
begin
  if not exists(select 1 from public.user_roles r where r.user_id=p_actor_id and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance settlement approval required'; end if;
  if p_tax_withheld_paise is null or p_tax_withheld_paise<0
    or p_provider_fee_paise is null or p_provider_fee_paise<0
    or p_adjustment_paise is null
    or length(btrim(coalesce(p_policy_version,'')))<5 then
    raise exception 'Tax, provider fee, adjustment and approved settlement policy are required';
  end if;
  select * into v_earning from public.owner_earnings where id=p_earning_id for update;
  if not found or v_earning.status<>'eligible' then raise exception 'Owner earning is not awaiting settlement calculation'; end if;
  if not exists(select 1 from public.payment_provider_approvals a
    join public.bookings b on b.id=v_earning.booking_id
    join public.payments p on p.booking_id=b.id and p.provider=a.provider_code
    where a.enabled_for_rent and a.marketplace_model='peer_to_peer_physical_book_rental'
      and a.accounting_approval_reference is not null and a.legal_approval_reference is not null
      and (a.expires_at is null or a.expires_at>now())) then
    raise exception 'Approved provider and accounting controls are required for settlement calculation';
  end if;
  if p_tax_withheld_paise+p_provider_fee_paise>v_earning.gross_rent_paise-v_earning.commission_paise then
    raise exception 'Tax and provider fees exceed the amount payable after commission';
  end if;
  v_net:=v_earning.gross_rent_paise-v_earning.commission_paise-p_tax_withheld_paise-p_provider_fee_paise+p_adjustment_paise;
  if v_net<0 then raise exception 'Final owner payable cannot be negative'; end if;
  update public.owner_earnings set tax_withheld_paise=p_tax_withheld_paise,provider_fee_paise=p_provider_fee_paise,
    adjustment_paise=p_adjustment_paise,net_payable_paise=v_net,settlement_calculated_at=now(),
    settlement_policy_version=p_policy_version,settlement_approved_by=p_actor_id
    where id=p_earning_id;
  return v_net;
end;
$;
revoke all on function public.record_owner_settlement_calculation(uuid,uuid,bigint,bigint,bigint,text) from public,anon,authenticated;
grant execute on function public.record_owner_settlement_calculation(uuid,uuid,bigint,bigint,bigint,text) to service_role;

-- Provider event updates are the only route to a terminal refund/payout/deposit status.
create or replace function public.apply_verified_refund_event(
  p_provider text,p_event_id text,p_refund_id uuid,p_event_type text,p_provider_refund_id text,
  p_amount_paise bigint,p_currency char(3),p_payload_sha256 text
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_refund public.refunds%rowtype; v_payment public.payments%rowtype; v_sum bigint; v_count bigint;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_event_id is null or p_payload_sha256 is null or p_payload_sha256 !~ '^[a-f0-9]{64}
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256,provider_payment_reference)
    values((select payment_id from public.refunds where id=p_refund_id),p_provider,p_event_id,p_event_type,true,p_payload_sha256,p_provider_refund_id)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_refund from public.refunds where id=p_refund_id and provider=p_provider for update;
  if not found or v_refund.amount_paise<>p_amount_paise or p_currency<>'INR' then
    update public.payment_events set processing_status='dead_letter',processing_error_code='refund_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','refund_reference_or_amount_mismatch');
  end if;
  if v_refund.provider_refund_id is not null and p_provider_refund_id is not null and v_refund.provider_refund_id<>p_provider_refund_id then
    update public.payment_events set processing_status='dead_letter',processing_error_code='refund_provider_id_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','refund_provider_id_mismatch');
  end if;
  if p_event_type in ('refund.succeeded','refund.processed') then
    update public.refunds set status='succeeded',provider_refund_id=coalesce(provider_refund_id,p_provider_refund_id),completed_at=coalesce(completed_at,now())
      where id=p_refund_id;
  elsif p_event_type in ('refund.failed','refund.rejected') then
    update public.refunds set status='failed',provider_refund_id=coalesce(provider_refund_id,p_provider_refund_id)
      where id=p_refund_id;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_refund_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  select * into v_payment from public.payments where id=v_refund.payment_id for update;
  select coalesce(sum(amount_paise),0),count(*) filter(where status='succeeded')
    into v_sum,v_count from public.refunds where payment_id=v_payment.id;
  if v_count>0 then
    update public.payments set status=case when v_sum>=amount_paise then 'refunded'::public.payment_status else 'partially_refunded'::public.payment_status end
      where id=v_payment.id;
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'refund_status',(select status from public.refunds where id=p_refund_id));
end;
$$;
revoke all on function public.apply_verified_refund_event(text,text,uuid,text,text,bigint,char,text) from public,anon,authenticated;
grant execute on function public.apply_verified_refund_event(text,text,uuid,text,text,bigint,char,text) to service_role;

create or replace function public.apply_verified_payout_event(
  p_provider text,p_event_id text,p_payout_id uuid,p_event_type text,p_provider_transfer_id text,
  p_amount_paise bigint,p_currency char(3),p_payload_sha256 text
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_payout public.payouts%rowtype; v_count bigint;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_event_id is null or p_payload_sha256 is null or p_payload_sha256 !~ '^[a-f0-9]{64}
      join public.payouts z on z.owner_earning_id=e.id where z.id=p_payout_id limit 1),
      p_provider,p_event_id,p_event_type,true,p_payload_sha256)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_payout from public.payouts where id=p_payout_id and provider=p_provider for update;
  if not found or v_payout.amount_paise<>p_amount_paise or p_currency<>'INR'
    or (v_payout.provider_transfer_id is not null and p_provider_transfer_id is not null and v_payout.provider_transfer_id<>p_provider_transfer_id) then
    update public.payment_events set processing_status='dead_letter',processing_error_code='payout_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','payout_reference_or_amount_mismatch');
  end if;
  if p_event_type in ('transfer.succeeded','payout.succeeded','settlement.completed') then
    update public.payouts set status='paid',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),settled_at=coalesce(settled_at,now())
      where id=p_payout_id;
    update public.owner_earnings set status='paid' where id=v_payout.owner_earning_id;
  elsif p_event_type in ('transfer.failed','payout.failed') then
    update public.payouts set status='failed',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),failure_code=p_event_type
      where id=p_payout_id;
    -- Retry requires a fresh payout attempt after finance has checked canonical provider state.
    update public.owner_earnings set status='eligible' where id=v_payout.owner_earning_id;
  elsif p_event_type in ('transfer.reversed','payout.reversed') then
    update public.payouts set status='reversed',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),failure_code=p_event_type
      where id=p_payout_id;
    update public.owner_earnings set status='reconciliation_required' where id=v_payout.owner_earning_id;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_payout_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'payout_status',(select status from public.payouts where id=p_payout_id));
end;
$$;
revoke all on function public.apply_verified_payout_event(text,text,uuid,text,text,bigint,char,text) from public,anon,authenticated;
grant execute on function public.apply_verified_payout_event(text,text,uuid,text,text,bigint,char,text) to service_role;

create or replace function public.apply_verified_deposit_event(
  p_provider text,p_event_id text,p_deposit_id uuid,p_event_type text,p_provider_reference text,
  p_amount_paise bigint,p_currency char(3),p_payload_sha256 text,p_claim_id uuid default null
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_deposit public.deposits%rowtype; v_claim public.deposit_claims%rowtype; v_count bigint; v_ledger_key text;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_event_id is null or p_payload_sha256 is null or p_payload_sha256 !~ '^[a-f0-9]{64}
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256,provider_payment_reference)
    values(null,p_provider,p_event_id,p_event_type,true,p_payload_sha256,p_provider_reference)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_deposit from public.deposits where id=p_deposit_id and provider=p_provider for update;
  if not found or v_deposit.amount_paise<>p_amount_paise or p_currency<>'INR'
    or (v_deposit.provider_reference is not null and p_provider_reference is not null and v_deposit.provider_reference<>p_provider_reference) then
    update public.payment_events set processing_status='dead_letter',processing_error_code='deposit_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','deposit_reference_or_amount_mismatch');
  end if;
  v_ledger_key:='deposit-provider-event:'||p_provider||':'||p_event_id;
  if p_event_type in ('deposit.held','deposit.collected','deposit.authorized') then
    if not v_deposit.feature_enabled_at_creation then raise exception 'Deposit feature was not enabled at booking creation'; end if;
    update public.deposits set status='held_by_provider',provider_reference=coalesce(provider_reference,p_provider_reference)
      where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'provider_held',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.released','deposit.refunded') then
    if v_deposit.status not in ('release_pending','refund_pending','held_by_provider','claim_hold','partially_applied') then
      raise exception 'Deposit is not in a releasable provider-confirmed state';
    end if;
    select coalesce(sum(amount_paise),0) into v_count from public.deposit_ledger
      where deposit_id=p_deposit_id and event_type in ('released','amount_applied');
    if p_amount_paise<>greatest(v_deposit.amount_paise-v_count,0) then
      raise exception 'Provider release amount does not match the remaining confirmed deposit amount';
    end if;
    update public.deposits set status='released',provider_reference=coalesce(provider_reference,p_provider_reference)
      where id=p_deposit_id;
    update public.deposit_release_requests set status='released',processed_at=coalesce(processed_at,now())
      where deposit_id=p_deposit_id and status in ('requested','approved','processing','reconciliation_required');
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'released',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.claim_held','deposit.dispute_hold') then
    if v_deposit.status not in ('held_by_provider','claim_hold_pending') then raise exception 'Only a provider-held deposit may be claim-held'; end if;
    select * into v_claim from public.deposit_claims where id=p_claim_id and deposit_id=p_deposit_id for update;
    if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise is null
      or p_amount_paise<>v_claim.decision_amount_paise then
      raise exception 'Provider claim hold must match a reasoned approved claim amount';
    end if;
    update public.deposits set status='claim_hold' where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'claim_held',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.amount_applied','deposit.claim_applied') then
    select * into v_claim from public.deposit_claims where id=p_claim_id and deposit_id=p_deposit_id for update;
    if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise is null
      or p_amount_paise<=0 or p_amount_paise>v_claim.decision_amount_paise then
      raise exception 'Provider deposit application exceeds the approved, reasoned claim';
    end if;
    if not exists(select 1 from public.payment_provider_approvals x where x.provider_code=p_provider
      and x.enabled_for_deposits and x.supports_deposit_application and x.legal_approval_reference is not null) then
      raise exception 'Provider and legal permission for deposit application is not enabled';
    end if;
    select coalesce(sum(amount_paise),0)+p_amount_paise into v_count from public.deposit_ledger
      where deposit_id=p_deposit_id and event_type in ('released','amount_applied');
    update public.deposits set status=case when v_count>=v_deposit.amount_paise
      then 'released'::public.deposit_status else 'partially_applied'::public.deposit_status end where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key,metadata)
      values(p_deposit_id,'amount_applied',p_amount_paise,p_provider_reference,v_ledger_key,jsonb_build_object('claim_id',p_claim_id))
      on conflict(idempotency_key) do nothing;
    update public.deposit_claims set status='closed' where id=p_claim_id;
  elsif p_event_type in ('deposit.failed','deposit.rejected') then
    update public.deposits set status=case when v_deposit.status='collection_pending' then 'failed'::public.deposit_status else 'reconciliation_required'::public.deposit_status end
      where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'failed',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_deposit_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'deposit_status',(select status from public.deposits where id=p_deposit_id));
end;
$$;
revoke all on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid) from public,anon,authenticated;
grant execute on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid) to service_role;

create or replace function public.submit_deposit_claim(
  p_deposit_id uuid,p_amount_paise bigint,p_reason_code text,p_description text
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_deposit public.deposits%rowtype; v_booking public.bookings%rowtype; v_claim uuid;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if p_amount_paise<=0 or length(btrim(coalesce(p_reason_code,'')))<3
    or length(btrim(coalesce(p_description,'')))<20 then raise exception 'A reason, evidence description and requested amount are required'; end if;
  select * into v_deposit from public.deposits where id=p_deposit_id for update;
  if not found or not v_deposit.feature_enabled_at_creation or v_deposit.status not in ('held_by_provider','claim_hold') then
    raise exception 'No provider-confirmed deposit is available for a claim';
  end if;
  select * into v_booking from public.bookings where id=v_deposit.booking_id for update;
  if v_booking.owner_id<>v_actor or v_booking.status not in ('completed','disputed') then
    raise exception 'Only the lending owner may submit a post-return deposit claim';
  end if;
  if p_amount_paise>v_deposit.amount_paise then raise exception 'Claim cannot exceed the provider-confirmed deposit amount'; end if;
  if exists(select 1 from public.deposit_claims x where x.deposit_id=p_deposit_id and x.status not in ('rejected','closed')) then
    raise exception 'An active deposit claim already exists';
  end if;
  insert into public.deposit_claims(deposit_id,booking_id,claimant_id,against_user_id,amount_requested_paise,reason_code,description)
    values(p_deposit_id,v_booking.id,v_actor,v_booking.reader_id,p_amount_paise,left(p_reason_code,80),left(p_description,3000))
    returning id into v_claim;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(v_booking.id,v_actor,'deposit_claim_submitted',jsonb_build_object('claim_id',v_claim,'amount_paise',p_amount_paise),'deposit-claim:'||v_claim::text);
  insert into public.notifications(user_id,channel,template_key,payload)
    values(v_booking.reader_id,'in_app','deposit.claim_submitted',jsonb_build_object('booking_id',v_booking.id,'claim_id',v_claim));
  return v_claim;
end;
$$;
revoke all on function public.submit_deposit_claim(uuid,bigint,text,text) from public,anon;
grant execute on function public.submit_deposit_claim(uuid,bigint,text,text) to authenticated;

create or replace function public.decide_deposit_claim(
  p_claim_id uuid,p_decision text,p_amount_paise bigint,p_reason text
) returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.deposit_claims%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance reviewer permission required'; end if;
  if p_decision not in ('approve','reject') or length(btrim(coalesce(p_reason,'')))<10 then
    raise exception 'Select a valid decision and provide a reason';
  end if;
  select * into v_claim from public.deposit_claims where id=p_claim_id for update;
  if not found or v_claim.status not in ('submitted','under_review','needs_response') then raise exception 'Deposit claim is not reviewable'; end if;
  if p_decision='approve' then
    if p_amount_paise is null or p_amount_paise<=0 or p_amount_paise>v_claim.amount_requested_paise then
      raise exception 'Approved amount must be positive and no greater than the requested claim';
    end if;
    update public.deposit_claims set status='approved',decision_amount_paise=p_amount_paise,
      decision_reason=left(p_reason,2000),decided_by=v_actor,decided_at=now() where id=p_claim_id;
  else
    if p_amount_paise is not null and p_amount_paise<>0 then raise exception 'A rejected claim cannot apply an amount'; end if;
    update public.deposit_claims set status='rejected',decision_amount_paise=0,
      decision_reason=left(p_reason,2000),decided_by=v_actor,decided_at=now() where id=p_claim_id;
  end if;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(v_claim.booking_id,v_actor,'deposit_claim_decided',
      jsonb_build_object('claim_id',p_claim_id,'decision',p_decision,'amount_paise',coalesce(p_amount_paise,0),'reason',left(p_reason,2000)),
      'deposit-claim-decision:'||p_claim_id::text);
end;
$$;
revoke all on function public.decide_deposit_claim(uuid,text,bigint,text) from public,anon;
grant execute on function public.decide_deposit_claim(uuid,text,bigint,text) to authenticated;

create or replace function public.request_deposit_claim_application(p_claim_id uuid,p_idempotency_key text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.deposit_claims%rowtype; v_deposit public.deposits%rowtype; v_request uuid; v_provider public.payment_provider_approvals%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance reviewer permission required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 then raise exception 'Idempotency key required'; end if;
  select id into v_request from public.outbox_events where idempotency_key='deposit-claim-application:'||p_idempotency_key;
  if v_request is not null then return v_request; end if;
  select * into v_claim from public.deposit_claims where id=p_claim_id for update;
  if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise is null or v_claim.decision_amount_paise<=0 then
    raise exception 'A reasoned, approved positive claim is required';
  end if;
  select * into v_deposit from public.deposits where id=v_claim.deposit_id for update;
  if v_deposit.status not in ('held_by_provider','claim_hold') then raise exception 'Deposit is not in an eligible provider state'; end if;
  select * into v_provider from public.payment_provider_approvals where provider_code=v_deposit.provider
    and enabled_for_deposits and supports_deposit_application and supports_deposit_dispute_hold
    and legal_approval_reference is not null and (expires_at is null or expires_at>now());
  if not found then raise exception 'Provider and legal approval for deposit application is not active'; end if;
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('deposit',v_deposit.id,'deposit_claim_application_requested',
      jsonb_build_object('deposit_id',v_deposit.id,'claim_id',p_claim_id,'amount_paise',v_claim.decision_amount_paise),
      'deposit-claim-application:'||p_idempotency_key)
    returning id into v_request;
  update public.deposits set status='claim_hold_pending' where id=v_deposit.id;
  insert into public.deposit_ledger(deposit_id,event_type,amount_paise,idempotency_key,metadata)
    values(v_deposit.id,'claim_hold_requested',v_claim.decision_amount_paise,'deposit-claim-hold:'||p_idempotency_key,
      jsonb_build_object('claim_id',p_claim_id));
  return v_request;
end;
$$;
revoke all on function public.request_deposit_claim_application(uuid,text) from public,anon;
grant execute on function public.request_deposit_claim_application(uuid,text) to authenticated;

-- Reconciliation payloads are provider-derived, inserted by a trusted adapter.
-- They are evidence for the finance queue, not an automatic cash adjustment.
create or replace function public.record_provider_reconciliation(
  p_provider text,p_report_reference text,p_period_start timestamptz,p_period_end timestamptz,p_records jsonb
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_run uuid; v_record jsonb; v_type text; v_internal text; v_provider_ref text;
  v_expected bigint; v_actual bigint; v_currency char(3); v_status text; v_matched integer:=0; v_unmatched integer:=0;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_period_start is null or p_period_end is null or p_period_end<=p_period_start
    or p_records is null or jsonb_typeof(p_records)<>'array' or jsonb_array_length(p_records)>10000 then
    raise exception 'Invalid provider reconciliation period or records';
  end if;
  if not exists(select 1 from public.payment_provider_approvals where provider_code=p_provider
    and supports_reconciliation and (expires_at is null or expires_at>now())) then
    raise exception 'Provider reconciliation is not approved';
  end if;
  insert into public.payment_reconciliation_runs(provider,report_reference,period_start,period_end,status)
    values(p_provider,left(p_report_reference,200),p_period_start,p_period_end,'started') returning id into v_run;
  for v_record in select value from jsonb_array_elements(p_records) loop
    v_type:=v_record->>'recordType';
    v_internal:=nullif(v_record->>'internalReference','');
    v_provider_ref:=nullif(v_record->>'providerReference','');
    v_expected:=nullif(v_record->>'expectedAmountPaise','')::bigint;
    v_actual:=nullif(v_record->>'amountPaise','')::bigint;
    v_currency:=coalesce(v_record->>'currency','INR')::char(3);
    v_status:=nullif(v_record->>'status','');
    if v_type not in ('payment','refund','payout','deposit','chargeback','settlement') or v_currency<>'INR' then
      raise exception 'Unsupported reconciliation record type or currency';
    end if;
    if v_type='payment' and v_provider_ref is not null then
      select p.id::text,p.amount_paise into v_internal,v_expected from public.payments p
        where p.provider=p_provider and (p.provider_payment_id=v_provider_ref or p.merchant_reference=v_provider_ref) limit 1;
    elsif v_type='refund' and v_provider_ref is not null then
      select r.id::text,r.amount_paise into v_internal,v_expected from public.refunds r
        where r.provider=p_provider and r.provider_refund_id=v_provider_ref limit 1;
    elsif v_type='payout' and v_provider_ref is not null then
      select t.id::text,t.amount_paise into v_internal,v_expected from public.payouts t
        where t.provider=p_provider and t.provider_transfer_id=v_provider_ref limit 1;
    elsif v_type='deposit' and v_provider_ref is not null then
      select d.id::text,d.amount_paise into v_internal,v_expected from public.deposits d
        where d.provider=p_provider and d.provider_reference=v_provider_ref limit 1;
    end if;
    insert into public.payment_reconciliation_items(run_id,record_type,internal_reference,provider_reference,
      expected_amount_paise,provider_amount_paise,currency,match_status,details)
    values(v_run,v_type,v_internal,v_provider_ref,v_expected,v_actual,v_currency,
      case when v_internal is null then 'missing_internal'
        when v_actual is null then 'missing_provider'
        when v_expected is distinct from v_actual then 'amount_mismatch'
        else 'manual_review' end,
      jsonb_build_object('provider_status',v_status,'source','provider_adapter'));
    if v_internal is not null and v_actual is not null and v_expected=v_actual then v_matched:=v_matched+1;
    else v_unmatched:=v_unmatched+1; end if;
  end loop;
  update public.payment_reconciliation_runs set matched_count=v_matched,unmatched_count=v_unmatched,
    status=case when v_unmatched=0 then 'completed' else 'partial' end,completed_at=now() where id=v_run;
  return v_run;
end;
$$;
revoke all on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) to service_role;

-- Persist the provider's external refund/transfer references without asserting
-- completion. Only apply_verified_* event RPCs can set terminal success states.
create or replace function public.attach_refund_provider_reference(p_refund_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.refunds set provider_refund_id=p_provider_reference,status='pending'
    where id=p_refund_id and status in ('requested','pending');
  if not found then raise exception 'Refund is not attachable'; end if;
end;
$$;
revoke all on function public.attach_refund_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_refund_provider_reference(uuid,text) to service_role;

create or replace function public.attach_payout_provider_reference(p_payout_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.payouts set provider_transfer_id=p_provider_reference,status='processing',initiated_at=coalesce(initiated_at,now())
    where id=p_payout_id and status in ('pending','processing');
  if not found then raise exception 'Payout is not attachable'; end if;
end;
$$;
revoke all on function public.attach_payout_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_payout_provider_reference(uuid,text) to service_role;

create or replace function public.attach_deposit_provider_reference(p_deposit_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.deposits set provider_reference=p_provider_reference
    where id=p_deposit_id and feature_enabled_at_creation and status='collection_pending';
  if not found then raise exception 'Deposit collection is not attachable'; end if;
end;
$$;
revoke all on function public.attach_deposit_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_deposit_provider_reference(uuid,text) to service_role;

-- Deposit ledger rows cannot be edited/deleted after insertion.
create or replace function private.reject_deposit_ledger_mutation()
returns trigger language plpgsql set search_path = pg_catalog
as $$ begin raise exception 'Deposit ledger is append-only'; end; $$;
drop trigger if exists deposit_ledger_append_only on public.deposit_ledger;
create trigger deposit_ledger_append_only before update or delete on public.deposit_ledger
for each row execute function private.reject_deposit_ledger_mutation();

-- A booking with no active provider-backed deposit must not show a deposit as
-- paid/held; a database row is only a workflow record, not proof of custody.
revoke all on public.payment_disputes,public.deposit_claims,public.payment_reconciliation_runs,
  public.payment_reconciliation_items from anon,authenticated;
alter table public.payment_disputes enable row level security;
alter table public.deposit_claims enable row level security;
alter table public.payment_reconciliation_runs enable row level security;
alter table public.payment_reconciliation_items enable row level security;

commit;
 then raise exception 'Invalid verified refund event'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256,provider_payment_reference)
    values((select payment_id from public.refunds where id=p_refund_id),p_provider,p_event_id,p_event_type,true,p_payload_sha256,p_provider_refund_id)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_refund from public.refunds where id=p_refund_id and provider=p_provider for update;
  if not found or v_refund.amount_paise<>p_amount_paise or p_currency<>'INR' then
    update public.payment_events set processing_status='dead_letter',processing_error_code='refund_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','refund_reference_or_amount_mismatch');
  end if;
  if v_refund.provider_refund_id is not null and p_provider_refund_id is not null and v_refund.provider_refund_id<>p_provider_refund_id then
    update public.payment_events set processing_status='dead_letter',processing_error_code='refund_provider_id_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','refund_provider_id_mismatch');
  end if;
  if p_event_type in ('refund.succeeded','refund.processed') then
    update public.refunds set status='succeeded',provider_refund_id=coalesce(provider_refund_id,p_provider_refund_id),completed_at=coalesce(completed_at,now())
      where id=p_refund_id;
  elsif p_event_type in ('refund.failed','refund.rejected') then
    update public.refunds set status='failed',provider_refund_id=coalesce(provider_refund_id,p_provider_refund_id)
      where id=p_refund_id;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_refund_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  select * into v_payment from public.payments where id=v_refund.payment_id for update;
  select coalesce(sum(amount_paise),0),count(*) filter(where status='succeeded')
    into v_sum,v_count from public.refunds where payment_id=v_payment.id;
  if v_count>0 then
    update public.payments set status=case when v_sum>=amount_paise then 'refunded'::public.payment_status else 'partially_refunded'::public.payment_status end
      where id=v_payment.id;
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'refund_status',(select status from public.refunds where id=p_refund_id));
end;
$$;
revoke all on function public.apply_verified_refund_event(text,text,uuid,text,text,bigint,char,text) from public,anon,authenticated;
grant execute on function public.apply_verified_refund_event(text,text,uuid,text,text,bigint,char,text) to service_role;

create or replace function public.apply_verified_payout_event(
  p_provider text,p_event_id text,p_payout_id uuid,p_event_type text,p_provider_transfer_id text,
  p_amount_paise bigint,p_currency char(3),p_payload_sha256 text
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_payout public.payouts%rowtype; v_count bigint;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256)
    values((select p.id from public.payments p join public.owner_earnings e on e.booking_id=p.booking_id
      join public.payouts z on z.owner_earning_id=e.id where z.id=p_payout_id limit 1),
      p_provider,p_event_id,p_event_type,true,p_payload_sha256)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_payout from public.payouts where id=p_payout_id and provider=p_provider for update;
  if not found or v_payout.amount_paise<>p_amount_paise or p_currency<>'INR'
    or (v_payout.provider_transfer_id is not null and p_provider_transfer_id is not null and v_payout.provider_transfer_id<>p_provider_transfer_id) then
    update public.payment_events set processing_status='dead_letter',processing_error_code='payout_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','payout_reference_or_amount_mismatch');
  end if;
  if p_event_type in ('transfer.succeeded','payout.succeeded','settlement.completed') then
    update public.payouts set status='paid',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),settled_at=coalesce(settled_at,now())
      where id=p_payout_id;
    update public.owner_earnings set status='paid' where id=v_payout.owner_earning_id;
  elsif p_event_type in ('transfer.failed','payout.failed') then
    update public.payouts set status='failed',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),failure_code=p_event_type
      where id=p_payout_id;
    -- Retry requires a fresh payout attempt after finance has checked canonical provider state.
    update public.owner_earnings set status='eligible' where id=v_payout.owner_earning_id;
  elsif p_event_type in ('transfer.reversed','payout.reversed') then
    update public.payouts set status='reversed',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),failure_code=p_event_type
      where id=p_payout_id;
    update public.owner_earnings set status='reconciliation_required' where id=v_payout.owner_earning_id;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_payout_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'payout_status',(select status from public.payouts where id=p_payout_id));
end;
$$;
revoke all on function public.apply_verified_payout_event(text,text,uuid,text,text,bigint,char,text) from public,anon,authenticated;
grant execute on function public.apply_verified_payout_event(text,text,uuid,text,text,bigint,char,text) to service_role;

create or replace function public.apply_verified_deposit_event(
  p_provider text,p_event_id text,p_deposit_id uuid,p_event_type text,p_provider_reference text,
  p_amount_paise bigint,p_currency char(3),p_payload_sha256 text,p_claim_id uuid default null
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_deposit public.deposits%rowtype; v_claim public.deposit_claims%rowtype; v_count bigint; v_ledger_key text;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_payload_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'Invalid verified deposit event'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256,provider_payment_reference)
    values(null,p_provider,p_event_id,p_event_type,true,p_payload_sha256,p_provider_reference)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_deposit from public.deposits where id=p_deposit_id and provider=p_provider for update;
  if not found or v_deposit.amount_paise<>p_amount_paise or p_currency<>'INR'
    or (v_deposit.provider_reference is not null and p_provider_reference is not null and v_deposit.provider_reference<>p_provider_reference) then
    update public.payment_events set processing_status='dead_letter',processing_error_code='deposit_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','deposit_reference_or_amount_mismatch');
  end if;
  v_ledger_key:='deposit-provider-event:'||p_provider||':'||p_event_id;
  if p_event_type in ('deposit.held','deposit.collected','deposit.authorized') then
    if not v_deposit.feature_enabled_at_creation then raise exception 'Deposit feature was not enabled at booking creation'; end if;
    update public.deposits set status='held_by_provider',provider_reference=coalesce(provider_reference,p_provider_reference)
      where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'provider_held',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.released','deposit.refunded') then
    if v_deposit.status not in ('release_pending','refund_pending','held_by_provider','claim_hold') then
      raise exception 'Deposit is not in a releasable provider-confirmed state';
    end if;
    update public.deposits set status='released',provider_reference=coalesce(provider_reference,p_provider_reference)
      where id=p_deposit_id;
    update public.deposit_release_requests set status='released',processed_at=coalesce(processed_at,now())
      where deposit_id=p_deposit_id and status in ('requested','approved','processing','reconciliation_required');
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'released',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.claim_held','deposit.dispute_hold') then
    if v_deposit.status<>'held_by_provider' then raise exception 'Only a provider-held deposit may be claim-held'; end if;
    update public.deposits set status='claim_hold' where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'claim_held',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.amount_applied','deposit.claim_applied') then
    select * into v_claim from public.deposit_claims where id=p_claim_id and deposit_id=p_deposit_id for update;
    if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise is null
      or p_amount_paise<=0 or p_amount_paise>v_claim.decision_amount_paise then
      raise exception 'Provider deposit application exceeds the approved, reasoned claim';
    end if;
    if not exists(select 1 from public.payment_provider_approvals x where x.provider_code=p_provider
      and x.enabled_for_deposits and x.supports_deposit_application and x.legal_approval_reference is not null) then
      raise exception 'Provider and legal permission for deposit application is not enabled';
    end if;
    update public.deposits set status='partially_applied' where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key,metadata)
      values(p_deposit_id,'amount_applied',p_amount_paise,p_provider_reference,v_ledger_key,jsonb_build_object('claim_id',p_claim_id))
      on conflict(idempotency_key) do nothing;
    update public.deposit_claims set status='closed' where id=p_claim_id;
  elsif p_event_type in ('deposit.failed','deposit.rejected') then
    update public.deposits set status=case when v_deposit.status='collection_pending' then 'failed'::public.deposit_status else 'reconciliation_required'::public.deposit_status end
      where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'failed',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_deposit_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'deposit_status',(select status from public.deposits where id=p_deposit_id));
end;
$$;
revoke all on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid) from public,anon,authenticated;
grant execute on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid) to service_role;

create or replace function public.submit_deposit_claim(
  p_deposit_id uuid,p_amount_paise bigint,p_reason_code text,p_description text
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_deposit public.deposits%rowtype; v_booking public.bookings%rowtype; v_claim uuid;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if p_amount_paise<=0 or length(btrim(coalesce(p_reason_code,'')))<3
    or length(btrim(coalesce(p_description,'')))<20 then raise exception 'A reason, evidence description and requested amount are required'; end if;
  select * into v_deposit from public.deposits where id=p_deposit_id for update;
  if not found or not v_deposit.feature_enabled_at_creation or v_deposit.status not in ('held_by_provider','claim_hold') then
    raise exception 'No provider-confirmed deposit is available for a claim';
  end if;
  select * into v_booking from public.bookings where id=v_deposit.booking_id for update;
  if v_booking.owner_id<>v_actor or v_booking.status not in ('completed','disputed') then
    raise exception 'Only the lending owner may submit a post-return deposit claim';
  end if;
  if p_amount_paise>v_deposit.amount_paise then raise exception 'Claim cannot exceed the provider-confirmed deposit amount'; end if;
  if exists(select 1 from public.deposit_claims x where x.deposit_id=p_deposit_id and x.status not in ('rejected','closed')) then
    raise exception 'An active deposit claim already exists';
  end if;
  insert into public.deposit_claims(deposit_id,booking_id,claimant_id,against_user_id,amount_requested_paise,reason_code,description)
    values(p_deposit_id,v_booking.id,v_actor,v_booking.reader_id,p_amount_paise,left(p_reason_code,80),left(p_description,3000))
    returning id into v_claim;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(v_booking.id,v_actor,'deposit_claim_submitted',jsonb_build_object('claim_id',v_claim,'amount_paise',p_amount_paise),'deposit-claim:'||v_claim::text);
  insert into public.notifications(user_id,channel,template_key,payload)
    values(v_booking.reader_id,'in_app','deposit.claim_submitted',jsonb_build_object('booking_id',v_booking.id,'claim_id',v_claim));
  return v_claim;
end;
$$;
revoke all on function public.submit_deposit_claim(uuid,bigint,text,text) from public,anon;
grant execute on function public.submit_deposit_claim(uuid,bigint,text,text) to authenticated;

create or replace function public.decide_deposit_claim(
  p_claim_id uuid,p_decision text,p_amount_paise bigint,p_reason text
) returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.deposit_claims%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance reviewer permission required'; end if;
  if p_decision not in ('approve','reject') or length(btrim(coalesce(p_reason,'')))<10 then
    raise exception 'Select a valid decision and provide a reason';
  end if;
  select * into v_claim from public.deposit_claims where id=p_claim_id for update;
  if not found or v_claim.status not in ('submitted','under_review','needs_response') then raise exception 'Deposit claim is not reviewable'; end if;
  if p_decision='approve' then
    if p_amount_paise is null or p_amount_paise<=0 or p_amount_paise>v_claim.amount_requested_paise then
      raise exception 'Approved amount must be positive and no greater than the requested claim';
    end if;
    update public.deposit_claims set status='approved',decision_amount_paise=p_amount_paise,
      decision_reason=left(p_reason,2000),decided_by=v_actor,decided_at=now() where id=p_claim_id;
  else
    if p_amount_paise not in (0,null) then raise exception 'A rejected claim cannot apply an amount'; end if;
    update public.deposit_claims set status='rejected',decision_amount_paise=0,
      decision_reason=left(p_reason,2000),decided_by=v_actor,decided_at=now() where id=p_claim_id;
  end if;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(v_claim.booking_id,v_actor,'deposit_claim_decided',
      jsonb_build_object('claim_id',p_claim_id,'decision',p_decision,'amount_paise',coalesce(p_amount_paise,0),'reason',left(p_reason,2000)),
      'deposit-claim-decision:'||p_claim_id::text);
end;
$$;
revoke all on function public.decide_deposit_claim(uuid,text,bigint,text) from public,anon;
grant execute on function public.decide_deposit_claim(uuid,text,bigint,text) to authenticated;

create or replace function public.request_deposit_claim_application(p_claim_id uuid,p_idempotency_key text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.deposit_claims%rowtype; v_deposit public.deposits%rowtype; v_request uuid; v_provider public.payment_provider_approvals%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance reviewer permission required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 then raise exception 'Idempotency key required'; end if;
  select id into v_request from public.outbox_events where idempotency_key='deposit-claim-application:'||p_idempotency_key;
  if v_request is not null then return v_request; end if;
  select * into v_claim from public.deposit_claims where id=p_claim_id for update;
  if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise is null or v_claim.decision_amount_paise<=0 then
    raise exception 'A reasoned, approved positive claim is required';
  end if;
  select * into v_deposit from public.deposits where id=v_claim.deposit_id for update;
  if v_deposit.status not in ('held_by_provider','claim_hold') then raise exception 'Deposit is not in an eligible provider state'; end if;
  select * into v_provider from public.payment_provider_approvals where provider_code=v_deposit.provider
    and enabled_for_deposits and supports_deposit_application and supports_deposit_dispute_hold
    and legal_approval_reference is not null and (expires_at is null or expires_at>now());
  if not found then raise exception 'Provider and legal approval for deposit application is not active'; end if;
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('deposit',v_deposit.id,'deposit_claim_application_requested',
      jsonb_build_object('deposit_id',v_deposit.id,'claim_id',p_claim_id,'amount_paise',v_claim.decision_amount_paise),
      'deposit-claim-application:'||p_idempotency_key)
    returning id into v_request;
  update public.deposits set status='claim_hold_pending' where id=v_deposit.id;
  insert into public.deposit_ledger(deposit_id,event_type,amount_paise,idempotency_key,metadata)
    values(v_deposit.id,'claim_hold_requested',v_claim.decision_amount_paise,'deposit-claim-hold:'||p_idempotency_key,
      jsonb_build_object('claim_id',p_claim_id));
  return v_request;
end;
$$;
revoke all on function public.request_deposit_claim_application(uuid,text) from public,anon;
grant execute on function public.request_deposit_claim_application(uuid,text) to authenticated;

-- Reconciliation payloads are provider-derived, inserted by a trusted adapter.
-- They are evidence for the finance queue, not an automatic cash adjustment.
create or replace function public.record_provider_reconciliation(
  p_provider text,p_report_reference text,p_period_start timestamptz,p_period_end timestamptz,p_records jsonb
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_run uuid; v_record jsonb; v_type text; v_internal text; v_provider_ref text;
  v_expected bigint; v_actual bigint; v_currency char(3); v_status text; v_matched integer:=0; v_unmatched integer:=0;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_period_end<=p_period_start or jsonb_typeof(p_records)<>'array' or jsonb_array_length(p_records)>10000 then
    raise exception 'Invalid provider reconciliation period or records';
  end if;
  if not exists(select 1 from public.payment_provider_approvals where provider_code=p_provider
    and supports_reconciliation and (expires_at is null or expires_at>now())) then
    raise exception 'Provider reconciliation is not approved';
  end if;
  insert into public.payment_reconciliation_runs(provider,report_reference,period_start,period_end,status)
    values(p_provider,left(p_report_reference,200),p_period_start,p_period_end,'started') returning id into v_run;
  for v_record in select value from jsonb_array_elements(p_records) loop
    v_type:=v_record->>'recordType';
    v_internal:=nullif(v_record->>'internalReference','');
    v_provider_ref:=nullif(v_record->>'providerReference','');
    v_expected:=nullif(v_record->>'expectedAmountPaise','')::bigint;
    v_actual:=nullif(v_record->>'amountPaise','')::bigint;
    v_currency:=coalesce(v_record->>'currency','INR')::char(3);
    v_status:=nullif(v_record->>'status','');
    if v_type not in ('payment','refund','payout','deposit','chargeback','settlement') or v_currency<>'INR' then
      raise exception 'Unsupported reconciliation record type or currency';
    end if;
    if v_type='payment' and v_provider_ref is not null then
      select p.id::text,p.amount_paise into v_internal,v_expected from public.payments p
        where p.provider=p_provider and (p.provider_payment_id=v_provider_ref or p.merchant_reference=v_provider_ref) limit 1;
    elsif v_type='refund' and v_provider_ref is not null then
      select r.id::text,r.amount_paise into v_internal,v_expected from public.refunds r
        where r.provider=p_provider and r.provider_refund_id=v_provider_ref limit 1;
    elsif v_type='payout' and v_provider_ref is not null then
      select t.id::text,t.amount_paise into v_internal,v_expected from public.payouts t
        where t.provider=p_provider and t.provider_transfer_id=v_provider_ref limit 1;
    elsif v_type='deposit' and v_provider_ref is not null then
      select d.id::text,d.amount_paise into v_internal,v_expected from public.deposits d
        where d.provider=p_provider and d.provider_reference=v_provider_ref limit 1;
    end if;
    insert into public.payment_reconciliation_items(run_id,record_type,internal_reference,provider_reference,
      expected_amount_paise,provider_amount_paise,currency,match_status,details)
    values(v_run,v_type,v_internal,v_provider_ref,v_expected,v_actual,v_currency,
      case when v_internal is null then 'missing_internal'
        when v_actual is null then 'missing_provider'
        when v_expected is distinct from v_actual then 'amount_mismatch'
        else 'manual_review' end,
      jsonb_build_object('provider_status',v_status,'source','provider_adapter'));
    if v_internal is not null and v_actual is not null and v_expected=v_actual then v_matched:=v_matched+1;
    else v_unmatched:=v_unmatched+1; end if;
  end loop;
  update public.payment_reconciliation_runs set matched_count=v_matched,unmatched_count=v_unmatched,
    status=case when v_unmatched=0 then 'completed' else 'partial' end,completed_at=now() where id=v_run;
  return v_run;
end;
$$;
revoke all on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) to service_role;

-- Persist the provider's external refund/transfer references without asserting
-- completion. Only apply_verified_* event RPCs can set terminal success states.
create or replace function public.attach_refund_provider_reference(p_refund_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.refunds set provider_refund_id=p_provider_reference,status='pending'
    where id=p_refund_id and status in ('requested','pending');
  if not found then raise exception 'Refund is not attachable'; end if;
end;
$$;
revoke all on function public.attach_refund_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_refund_provider_reference(uuid,text) to service_role;

create or replace function public.attach_payout_provider_reference(p_payout_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.payouts set provider_transfer_id=p_provider_reference,status='processing',initiated_at=coalesce(initiated_at,now())
    where id=p_payout_id and status in ('pending','processing');
  if not found then raise exception 'Payout is not attachable'; end if;
end;
$$;
revoke all on function public.attach_payout_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_payout_provider_reference(uuid,text) to service_role;

create or replace function public.attach_deposit_provider_reference(p_deposit_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.deposits set provider_reference=p_provider_reference
    where id=p_deposit_id and feature_enabled_at_creation and status='collection_pending';
  if not found then raise exception 'Deposit collection is not attachable'; end if;
end;
$$;
revoke all on function public.attach_deposit_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_deposit_provider_reference(uuid,text) to service_role;

-- Deposit ledger rows cannot be edited/deleted after insertion.
create or replace function private.reject_deposit_ledger_mutation()
returns trigger language plpgsql set search_path = pg_catalog
as $$ begin raise exception 'Deposit ledger is append-only'; end; $$;
drop trigger if exists deposit_ledger_append_only on public.deposit_ledger;
create trigger deposit_ledger_append_only before update or delete on public.deposit_ledger
for each row execute function private.reject_deposit_ledger_mutation();

-- A booking with no active provider-backed deposit must not show a deposit as
-- paid/held; a database row is only a workflow record, not proof of custody.
revoke all on public.payment_disputes,public.deposit_claims,public.payment_reconciliation_runs,
  public.payment_reconciliation_items from anon,authenticated;
alter table public.payment_disputes enable row level security;
alter table public.deposit_claims enable row level security;
alter table public.payment_reconciliation_runs enable row level security;
alter table public.payment_reconciliation_items enable row level security;

commit;
 then raise exception 'Invalid verified payout event'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256)
    values((select p.id from public.payments p join public.owner_earnings e on e.booking_id=p.booking_id
      join public.payouts z on z.owner_earning_id=e.id where z.id=p_payout_id limit 1),
      p_provider,p_event_id,p_event_type,true,p_payload_sha256)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_payout from public.payouts where id=p_payout_id and provider=p_provider for update;
  if not found or v_payout.amount_paise<>p_amount_paise or p_currency<>'INR'
    or (v_payout.provider_transfer_id is not null and p_provider_transfer_id is not null and v_payout.provider_transfer_id<>p_provider_transfer_id) then
    update public.payment_events set processing_status='dead_letter',processing_error_code='payout_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','payout_reference_or_amount_mismatch');
  end if;
  if p_event_type in ('transfer.succeeded','payout.succeeded','settlement.completed') then
    update public.payouts set status='paid',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),settled_at=coalesce(settled_at,now())
      where id=p_payout_id;
    update public.owner_earnings set status='paid' where id=v_payout.owner_earning_id;
  elsif p_event_type in ('transfer.failed','payout.failed') then
    update public.payouts set status='failed',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),failure_code=p_event_type
      where id=p_payout_id;
    -- Retry requires a fresh payout attempt after finance has checked canonical provider state.
    update public.owner_earnings set status='eligible' where id=v_payout.owner_earning_id;
  elsif p_event_type in ('transfer.reversed','payout.reversed') then
    update public.payouts set status='reversed',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),failure_code=p_event_type
      where id=p_payout_id;
    update public.owner_earnings set status='reconciliation_required' where id=v_payout.owner_earning_id;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_payout_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'payout_status',(select status from public.payouts where id=p_payout_id));
end;
$$;
revoke all on function public.apply_verified_payout_event(text,text,uuid,text,text,bigint,char,text) from public,anon,authenticated;
grant execute on function public.apply_verified_payout_event(text,text,uuid,text,text,bigint,char,text) to service_role;

create or replace function public.apply_verified_deposit_event(
  p_provider text,p_event_id text,p_deposit_id uuid,p_event_type text,p_provider_reference text,
  p_amount_paise bigint,p_currency char(3),p_payload_sha256 text,p_claim_id uuid default null
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_deposit public.deposits%rowtype; v_claim public.deposit_claims%rowtype; v_count bigint; v_ledger_key text;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_payload_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'Invalid verified deposit event'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256,provider_payment_reference)
    values(null,p_provider,p_event_id,p_event_type,true,p_payload_sha256,p_provider_reference)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_deposit from public.deposits where id=p_deposit_id and provider=p_provider for update;
  if not found or v_deposit.amount_paise<>p_amount_paise or p_currency<>'INR'
    or (v_deposit.provider_reference is not null and p_provider_reference is not null and v_deposit.provider_reference<>p_provider_reference) then
    update public.payment_events set processing_status='dead_letter',processing_error_code='deposit_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','deposit_reference_or_amount_mismatch');
  end if;
  v_ledger_key:='deposit-provider-event:'||p_provider||':'||p_event_id;
  if p_event_type in ('deposit.held','deposit.collected','deposit.authorized') then
    if not v_deposit.feature_enabled_at_creation then raise exception 'Deposit feature was not enabled at booking creation'; end if;
    update public.deposits set status='held_by_provider',provider_reference=coalesce(provider_reference,p_provider_reference)
      where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'provider_held',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.released','deposit.refunded') then
    if v_deposit.status not in ('release_pending','refund_pending','held_by_provider','claim_hold') then
      raise exception 'Deposit is not in a releasable provider-confirmed state';
    end if;
    update public.deposits set status='released',provider_reference=coalesce(provider_reference,p_provider_reference)
      where id=p_deposit_id;
    update public.deposit_release_requests set status='released',processed_at=coalesce(processed_at,now())
      where deposit_id=p_deposit_id and status in ('requested','approved','processing','reconciliation_required');
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'released',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.claim_held','deposit.dispute_hold') then
    if v_deposit.status<>'held_by_provider' then raise exception 'Only a provider-held deposit may be claim-held'; end if;
    update public.deposits set status='claim_hold' where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'claim_held',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.amount_applied','deposit.claim_applied') then
    select * into v_claim from public.deposit_claims where id=p_claim_id and deposit_id=p_deposit_id for update;
    if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise is null
      or p_amount_paise<=0 or p_amount_paise>v_claim.decision_amount_paise then
      raise exception 'Provider deposit application exceeds the approved, reasoned claim';
    end if;
    if not exists(select 1 from public.payment_provider_approvals x where x.provider_code=p_provider
      and x.enabled_for_deposits and x.supports_deposit_application and x.legal_approval_reference is not null) then
      raise exception 'Provider and legal permission for deposit application is not enabled';
    end if;
    update public.deposits set status='partially_applied' where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key,metadata)
      values(p_deposit_id,'amount_applied',p_amount_paise,p_provider_reference,v_ledger_key,jsonb_build_object('claim_id',p_claim_id))
      on conflict(idempotency_key) do nothing;
    update public.deposit_claims set status='closed' where id=p_claim_id;
  elsif p_event_type in ('deposit.failed','deposit.rejected') then
    update public.deposits set status=case when v_deposit.status='collection_pending' then 'failed'::public.deposit_status else 'reconciliation_required'::public.deposit_status end
      where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'failed',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_deposit_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'deposit_status',(select status from public.deposits where id=p_deposit_id));
end;
$$;
revoke all on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid) from public,anon,authenticated;
grant execute on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid) to service_role;

create or replace function public.submit_deposit_claim(
  p_deposit_id uuid,p_amount_paise bigint,p_reason_code text,p_description text
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_deposit public.deposits%rowtype; v_booking public.bookings%rowtype; v_claim uuid;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if p_amount_paise<=0 or length(btrim(coalesce(p_reason_code,'')))<3
    or length(btrim(coalesce(p_description,'')))<20 then raise exception 'A reason, evidence description and requested amount are required'; end if;
  select * into v_deposit from public.deposits where id=p_deposit_id for update;
  if not found or not v_deposit.feature_enabled_at_creation or v_deposit.status not in ('held_by_provider','claim_hold') then
    raise exception 'No provider-confirmed deposit is available for a claim';
  end if;
  select * into v_booking from public.bookings where id=v_deposit.booking_id for update;
  if v_booking.owner_id<>v_actor or v_booking.status not in ('completed','disputed') then
    raise exception 'Only the lending owner may submit a post-return deposit claim';
  end if;
  if p_amount_paise>v_deposit.amount_paise then raise exception 'Claim cannot exceed the provider-confirmed deposit amount'; end if;
  if exists(select 1 from public.deposit_claims x where x.deposit_id=p_deposit_id and x.status not in ('rejected','closed')) then
    raise exception 'An active deposit claim already exists';
  end if;
  insert into public.deposit_claims(deposit_id,booking_id,claimant_id,against_user_id,amount_requested_paise,reason_code,description)
    values(p_deposit_id,v_booking.id,v_actor,v_booking.reader_id,p_amount_paise,left(p_reason_code,80),left(p_description,3000))
    returning id into v_claim;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(v_booking.id,v_actor,'deposit_claim_submitted',jsonb_build_object('claim_id',v_claim,'amount_paise',p_amount_paise),'deposit-claim:'||v_claim::text);
  insert into public.notifications(user_id,channel,template_key,payload)
    values(v_booking.reader_id,'in_app','deposit.claim_submitted',jsonb_build_object('booking_id',v_booking.id,'claim_id',v_claim));
  return v_claim;
end;
$$;
revoke all on function public.submit_deposit_claim(uuid,bigint,text,text) from public,anon;
grant execute on function public.submit_deposit_claim(uuid,bigint,text,text) to authenticated;

create or replace function public.decide_deposit_claim(
  p_claim_id uuid,p_decision text,p_amount_paise bigint,p_reason text
) returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.deposit_claims%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance reviewer permission required'; end if;
  if p_decision not in ('approve','reject') or length(btrim(coalesce(p_reason,'')))<10 then
    raise exception 'Select a valid decision and provide a reason';
  end if;
  select * into v_claim from public.deposit_claims where id=p_claim_id for update;
  if not found or v_claim.status not in ('submitted','under_review','needs_response') then raise exception 'Deposit claim is not reviewable'; end if;
  if p_decision='approve' then
    if p_amount_paise is null or p_amount_paise<=0 or p_amount_paise>v_claim.amount_requested_paise then
      raise exception 'Approved amount must be positive and no greater than the requested claim';
    end if;
    update public.deposit_claims set status='approved',decision_amount_paise=p_amount_paise,
      decision_reason=left(p_reason,2000),decided_by=v_actor,decided_at=now() where id=p_claim_id;
  else
    if p_amount_paise not in (0,null) then raise exception 'A rejected claim cannot apply an amount'; end if;
    update public.deposit_claims set status='rejected',decision_amount_paise=0,
      decision_reason=left(p_reason,2000),decided_by=v_actor,decided_at=now() where id=p_claim_id;
  end if;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(v_claim.booking_id,v_actor,'deposit_claim_decided',
      jsonb_build_object('claim_id',p_claim_id,'decision',p_decision,'amount_paise',coalesce(p_amount_paise,0),'reason',left(p_reason,2000)),
      'deposit-claim-decision:'||p_claim_id::text);
end;
$$;
revoke all on function public.decide_deposit_claim(uuid,text,bigint,text) from public,anon;
grant execute on function public.decide_deposit_claim(uuid,text,bigint,text) to authenticated;

create or replace function public.request_deposit_claim_application(p_claim_id uuid,p_idempotency_key text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.deposit_claims%rowtype; v_deposit public.deposits%rowtype; v_request uuid; v_provider public.payment_provider_approvals%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance reviewer permission required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 then raise exception 'Idempotency key required'; end if;
  select id into v_request from public.outbox_events where idempotency_key='deposit-claim-application:'||p_idempotency_key;
  if v_request is not null then return v_request; end if;
  select * into v_claim from public.deposit_claims where id=p_claim_id for update;
  if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise is null or v_claim.decision_amount_paise<=0 then
    raise exception 'A reasoned, approved positive claim is required';
  end if;
  select * into v_deposit from public.deposits where id=v_claim.deposit_id for update;
  if v_deposit.status not in ('held_by_provider','claim_hold') then raise exception 'Deposit is not in an eligible provider state'; end if;
  select * into v_provider from public.payment_provider_approvals where provider_code=v_deposit.provider
    and enabled_for_deposits and supports_deposit_application and supports_deposit_dispute_hold
    and legal_approval_reference is not null and (expires_at is null or expires_at>now());
  if not found then raise exception 'Provider and legal approval for deposit application is not active'; end if;
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('deposit',v_deposit.id,'deposit_claim_application_requested',
      jsonb_build_object('deposit_id',v_deposit.id,'claim_id',p_claim_id,'amount_paise',v_claim.decision_amount_paise),
      'deposit-claim-application:'||p_idempotency_key)
    returning id into v_request;
  update public.deposits set status='claim_hold_pending' where id=v_deposit.id;
  insert into public.deposit_ledger(deposit_id,event_type,amount_paise,idempotency_key,metadata)
    values(v_deposit.id,'claim_hold_requested',v_claim.decision_amount_paise,'deposit-claim-hold:'||p_idempotency_key,
      jsonb_build_object('claim_id',p_claim_id));
  return v_request;
end;
$$;
revoke all on function public.request_deposit_claim_application(uuid,text) from public,anon;
grant execute on function public.request_deposit_claim_application(uuid,text) to authenticated;

-- Reconciliation payloads are provider-derived, inserted by a trusted adapter.
-- They are evidence for the finance queue, not an automatic cash adjustment.
create or replace function public.record_provider_reconciliation(
  p_provider text,p_report_reference text,p_period_start timestamptz,p_period_end timestamptz,p_records jsonb
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_run uuid; v_record jsonb; v_type text; v_internal text; v_provider_ref text;
  v_expected bigint; v_actual bigint; v_currency char(3); v_status text; v_matched integer:=0; v_unmatched integer:=0;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_period_end<=p_period_start or jsonb_typeof(p_records)<>'array' or jsonb_array_length(p_records)>10000 then
    raise exception 'Invalid provider reconciliation period or records';
  end if;
  if not exists(select 1 from public.payment_provider_approvals where provider_code=p_provider
    and supports_reconciliation and (expires_at is null or expires_at>now())) then
    raise exception 'Provider reconciliation is not approved';
  end if;
  insert into public.payment_reconciliation_runs(provider,report_reference,period_start,period_end,status)
    values(p_provider,left(p_report_reference,200),p_period_start,p_period_end,'started') returning id into v_run;
  for v_record in select value from jsonb_array_elements(p_records) loop
    v_type:=v_record->>'recordType';
    v_internal:=nullif(v_record->>'internalReference','');
    v_provider_ref:=nullif(v_record->>'providerReference','');
    v_expected:=nullif(v_record->>'expectedAmountPaise','')::bigint;
    v_actual:=nullif(v_record->>'amountPaise','')::bigint;
    v_currency:=coalesce(v_record->>'currency','INR')::char(3);
    v_status:=nullif(v_record->>'status','');
    if v_type not in ('payment','refund','payout','deposit','chargeback','settlement') or v_currency<>'INR' then
      raise exception 'Unsupported reconciliation record type or currency';
    end if;
    if v_type='payment' and v_provider_ref is not null then
      select p.id::text,p.amount_paise into v_internal,v_expected from public.payments p
        where p.provider=p_provider and (p.provider_payment_id=v_provider_ref or p.merchant_reference=v_provider_ref) limit 1;
    elsif v_type='refund' and v_provider_ref is not null then
      select r.id::text,r.amount_paise into v_internal,v_expected from public.refunds r
        where r.provider=p_provider and r.provider_refund_id=v_provider_ref limit 1;
    elsif v_type='payout' and v_provider_ref is not null then
      select t.id::text,t.amount_paise into v_internal,v_expected from public.payouts t
        where t.provider=p_provider and t.provider_transfer_id=v_provider_ref limit 1;
    elsif v_type='deposit' and v_provider_ref is not null then
      select d.id::text,d.amount_paise into v_internal,v_expected from public.deposits d
        where d.provider=p_provider and d.provider_reference=v_provider_ref limit 1;
    end if;
    insert into public.payment_reconciliation_items(run_id,record_type,internal_reference,provider_reference,
      expected_amount_paise,provider_amount_paise,currency,match_status,details)
    values(v_run,v_type,v_internal,v_provider_ref,v_expected,v_actual,v_currency,
      case when v_internal is null then 'missing_internal'
        when v_actual is null then 'missing_provider'
        when v_expected is distinct from v_actual then 'amount_mismatch'
        else 'manual_review' end,
      jsonb_build_object('provider_status',v_status,'source','provider_adapter'));
    if v_internal is not null and v_actual is not null and v_expected=v_actual then v_matched:=v_matched+1;
    else v_unmatched:=v_unmatched+1; end if;
  end loop;
  update public.payment_reconciliation_runs set matched_count=v_matched,unmatched_count=v_unmatched,
    status=case when v_unmatched=0 then 'completed' else 'partial' end,completed_at=now() where id=v_run;
  return v_run;
end;
$$;
revoke all on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) to service_role;

-- Persist the provider's external refund/transfer references without asserting
-- completion. Only apply_verified_* event RPCs can set terminal success states.
create or replace function public.attach_refund_provider_reference(p_refund_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.refunds set provider_refund_id=p_provider_reference,status='pending'
    where id=p_refund_id and status in ('requested','pending');
  if not found then raise exception 'Refund is not attachable'; end if;
end;
$$;
revoke all on function public.attach_refund_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_refund_provider_reference(uuid,text) to service_role;

create or replace function public.attach_payout_provider_reference(p_payout_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.payouts set provider_transfer_id=p_provider_reference,status='processing',initiated_at=coalesce(initiated_at,now())
    where id=p_payout_id and status in ('pending','processing');
  if not found then raise exception 'Payout is not attachable'; end if;
end;
$$;
revoke all on function public.attach_payout_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_payout_provider_reference(uuid,text) to service_role;

create or replace function public.attach_deposit_provider_reference(p_deposit_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.deposits set provider_reference=p_provider_reference
    where id=p_deposit_id and feature_enabled_at_creation and status='collection_pending';
  if not found then raise exception 'Deposit collection is not attachable'; end if;
end;
$$;
revoke all on function public.attach_deposit_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_deposit_provider_reference(uuid,text) to service_role;

-- Deposit ledger rows cannot be edited/deleted after insertion.
create or replace function private.reject_deposit_ledger_mutation()
returns trigger language plpgsql set search_path = pg_catalog
as $$ begin raise exception 'Deposit ledger is append-only'; end; $$;
drop trigger if exists deposit_ledger_append_only on public.deposit_ledger;
create trigger deposit_ledger_append_only before update or delete on public.deposit_ledger
for each row execute function private.reject_deposit_ledger_mutation();

-- A booking with no active provider-backed deposit must not show a deposit as
-- paid/held; a database row is only a workflow record, not proof of custody.
revoke all on public.payment_disputes,public.deposit_claims,public.payment_reconciliation_runs,
  public.payment_reconciliation_items from anon,authenticated;
alter table public.payment_disputes enable row level security;
alter table public.deposit_claims enable row level security;
alter table public.payment_reconciliation_runs enable row level security;
alter table public.payment_reconciliation_items enable row level security;

commit;
 then raise exception 'Invalid verified refund event'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256,provider_payment_reference)
    values((select payment_id from public.refunds where id=p_refund_id),p_provider,p_event_id,p_event_type,true,p_payload_sha256,p_provider_refund_id)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_refund from public.refunds where id=p_refund_id and provider=p_provider for update;
  if not found or v_refund.amount_paise<>p_amount_paise or p_currency<>'INR' then
    update public.payment_events set processing_status='dead_letter',processing_error_code='refund_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','refund_reference_or_amount_mismatch');
  end if;
  if v_refund.provider_refund_id is not null and p_provider_refund_id is not null and v_refund.provider_refund_id<>p_provider_refund_id then
    update public.payment_events set processing_status='dead_letter',processing_error_code='refund_provider_id_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','refund_provider_id_mismatch');
  end if;
  if p_event_type in ('refund.succeeded','refund.processed') then
    update public.refunds set status='succeeded',provider_refund_id=coalesce(provider_refund_id,p_provider_refund_id),completed_at=coalesce(completed_at,now())
      where id=p_refund_id;
  elsif p_event_type in ('refund.failed','refund.rejected') then
    update public.refunds set status='failed',provider_refund_id=coalesce(provider_refund_id,p_provider_refund_id)
      where id=p_refund_id;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_refund_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  select * into v_payment from public.payments where id=v_refund.payment_id for update;
  select coalesce(sum(amount_paise),0),count(*) filter(where status='succeeded')
    into v_sum,v_count from public.refunds where payment_id=v_payment.id;
  if v_count>0 then
    update public.payments set status=case when v_sum>=amount_paise then 'refunded'::public.payment_status else 'partially_refunded'::public.payment_status end
      where id=v_payment.id;
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'refund_status',(select status from public.refunds where id=p_refund_id));
end;
$$;
revoke all on function public.apply_verified_refund_event(text,text,uuid,text,text,bigint,char,text) from public,anon,authenticated;
grant execute on function public.apply_verified_refund_event(text,text,uuid,text,text,bigint,char,text) to service_role;

create or replace function public.apply_verified_payout_event(
  p_provider text,p_event_id text,p_payout_id uuid,p_event_type text,p_provider_transfer_id text,
  p_amount_paise bigint,p_currency char(3),p_payload_sha256 text
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_payout public.payouts%rowtype; v_count bigint;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256)
    values((select p.id from public.payments p join public.owner_earnings e on e.booking_id=p.booking_id
      join public.payouts z on z.owner_earning_id=e.id where z.id=p_payout_id limit 1),
      p_provider,p_event_id,p_event_type,true,p_payload_sha256)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_payout from public.payouts where id=p_payout_id and provider=p_provider for update;
  if not found or v_payout.amount_paise<>p_amount_paise or p_currency<>'INR'
    or (v_payout.provider_transfer_id is not null and p_provider_transfer_id is not null and v_payout.provider_transfer_id<>p_provider_transfer_id) then
    update public.payment_events set processing_status='dead_letter',processing_error_code='payout_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','payout_reference_or_amount_mismatch');
  end if;
  if p_event_type in ('transfer.succeeded','payout.succeeded','settlement.completed') then
    update public.payouts set status='paid',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),settled_at=coalesce(settled_at,now())
      where id=p_payout_id;
    update public.owner_earnings set status='paid' where id=v_payout.owner_earning_id;
  elsif p_event_type in ('transfer.failed','payout.failed') then
    update public.payouts set status='failed',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),failure_code=p_event_type
      where id=p_payout_id;
    -- Retry requires a fresh payout attempt after finance has checked canonical provider state.
    update public.owner_earnings set status='eligible' where id=v_payout.owner_earning_id;
  elsif p_event_type in ('transfer.reversed','payout.reversed') then
    update public.payouts set status='reversed',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),failure_code=p_event_type
      where id=p_payout_id;
    update public.owner_earnings set status='reconciliation_required' where id=v_payout.owner_earning_id;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_payout_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'payout_status',(select status from public.payouts where id=p_payout_id));
end;
$$;
revoke all on function public.apply_verified_payout_event(text,text,uuid,text,text,bigint,char,text) from public,anon,authenticated;
grant execute on function public.apply_verified_payout_event(text,text,uuid,text,text,bigint,char,text) to service_role;

create or replace function public.apply_verified_deposit_event(
  p_provider text,p_event_id text,p_deposit_id uuid,p_event_type text,p_provider_reference text,
  p_amount_paise bigint,p_currency char(3),p_payload_sha256 text,p_claim_id uuid default null
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_deposit public.deposits%rowtype; v_claim public.deposit_claims%rowtype; v_count bigint; v_ledger_key text;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_payload_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'Invalid verified deposit event'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256,provider_payment_reference)
    values(null,p_provider,p_event_id,p_event_type,true,p_payload_sha256,p_provider_reference)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_deposit from public.deposits where id=p_deposit_id and provider=p_provider for update;
  if not found or v_deposit.amount_paise<>p_amount_paise or p_currency<>'INR'
    or (v_deposit.provider_reference is not null and p_provider_reference is not null and v_deposit.provider_reference<>p_provider_reference) then
    update public.payment_events set processing_status='dead_letter',processing_error_code='deposit_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','deposit_reference_or_amount_mismatch');
  end if;
  v_ledger_key:='deposit-provider-event:'||p_provider||':'||p_event_id;
  if p_event_type in ('deposit.held','deposit.collected','deposit.authorized') then
    if not v_deposit.feature_enabled_at_creation then raise exception 'Deposit feature was not enabled at booking creation'; end if;
    update public.deposits set status='held_by_provider',provider_reference=coalesce(provider_reference,p_provider_reference)
      where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'provider_held',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.released','deposit.refunded') then
    if v_deposit.status not in ('release_pending','refund_pending','held_by_provider','claim_hold') then
      raise exception 'Deposit is not in a releasable provider-confirmed state';
    end if;
    update public.deposits set status='released',provider_reference=coalesce(provider_reference,p_provider_reference)
      where id=p_deposit_id;
    update public.deposit_release_requests set status='released',processed_at=coalesce(processed_at,now())
      where deposit_id=p_deposit_id and status in ('requested','approved','processing','reconciliation_required');
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'released',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.claim_held','deposit.dispute_hold') then
    if v_deposit.status<>'held_by_provider' then raise exception 'Only a provider-held deposit may be claim-held'; end if;
    update public.deposits set status='claim_hold' where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'claim_held',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.amount_applied','deposit.claim_applied') then
    select * into v_claim from public.deposit_claims where id=p_claim_id and deposit_id=p_deposit_id for update;
    if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise is null
      or p_amount_paise<=0 or p_amount_paise>v_claim.decision_amount_paise then
      raise exception 'Provider deposit application exceeds the approved, reasoned claim';
    end if;
    if not exists(select 1 from public.payment_provider_approvals x where x.provider_code=p_provider
      and x.enabled_for_deposits and x.supports_deposit_application and x.legal_approval_reference is not null) then
      raise exception 'Provider and legal permission for deposit application is not enabled';
    end if;
    update public.deposits set status='partially_applied' where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key,metadata)
      values(p_deposit_id,'amount_applied',p_amount_paise,p_provider_reference,v_ledger_key,jsonb_build_object('claim_id',p_claim_id))
      on conflict(idempotency_key) do nothing;
    update public.deposit_claims set status='closed' where id=p_claim_id;
  elsif p_event_type in ('deposit.failed','deposit.rejected') then
    update public.deposits set status=case when v_deposit.status='collection_pending' then 'failed'::public.deposit_status else 'reconciliation_required'::public.deposit_status end
      where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'failed',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_deposit_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'deposit_status',(select status from public.deposits where id=p_deposit_id));
end;
$$;
revoke all on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid) from public,anon,authenticated;
grant execute on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid) to service_role;

create or replace function public.submit_deposit_claim(
  p_deposit_id uuid,p_amount_paise bigint,p_reason_code text,p_description text
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_deposit public.deposits%rowtype; v_booking public.bookings%rowtype; v_claim uuid;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if p_amount_paise<=0 or length(btrim(coalesce(p_reason_code,'')))<3
    or length(btrim(coalesce(p_description,'')))<20 then raise exception 'A reason, evidence description and requested amount are required'; end if;
  select * into v_deposit from public.deposits where id=p_deposit_id for update;
  if not found or not v_deposit.feature_enabled_at_creation or v_deposit.status not in ('held_by_provider','claim_hold') then
    raise exception 'No provider-confirmed deposit is available for a claim';
  end if;
  select * into v_booking from public.bookings where id=v_deposit.booking_id for update;
  if v_booking.owner_id<>v_actor or v_booking.status not in ('completed','disputed') then
    raise exception 'Only the lending owner may submit a post-return deposit claim';
  end if;
  if p_amount_paise>v_deposit.amount_paise then raise exception 'Claim cannot exceed the provider-confirmed deposit amount'; end if;
  if exists(select 1 from public.deposit_claims x where x.deposit_id=p_deposit_id and x.status not in ('rejected','closed')) then
    raise exception 'An active deposit claim already exists';
  end if;
  insert into public.deposit_claims(deposit_id,booking_id,claimant_id,against_user_id,amount_requested_paise,reason_code,description)
    values(p_deposit_id,v_booking.id,v_actor,v_booking.reader_id,p_amount_paise,left(p_reason_code,80),left(p_description,3000))
    returning id into v_claim;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(v_booking.id,v_actor,'deposit_claim_submitted',jsonb_build_object('claim_id',v_claim,'amount_paise',p_amount_paise),'deposit-claim:'||v_claim::text);
  insert into public.notifications(user_id,channel,template_key,payload)
    values(v_booking.reader_id,'in_app','deposit.claim_submitted',jsonb_build_object('booking_id',v_booking.id,'claim_id',v_claim));
  return v_claim;
end;
$$;
revoke all on function public.submit_deposit_claim(uuid,bigint,text,text) from public,anon;
grant execute on function public.submit_deposit_claim(uuid,bigint,text,text) to authenticated;

create or replace function public.decide_deposit_claim(
  p_claim_id uuid,p_decision text,p_amount_paise bigint,p_reason text
) returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.deposit_claims%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance reviewer permission required'; end if;
  if p_decision not in ('approve','reject') or length(btrim(coalesce(p_reason,'')))<10 then
    raise exception 'Select a valid decision and provide a reason';
  end if;
  select * into v_claim from public.deposit_claims where id=p_claim_id for update;
  if not found or v_claim.status not in ('submitted','under_review','needs_response') then raise exception 'Deposit claim is not reviewable'; end if;
  if p_decision='approve' then
    if p_amount_paise is null or p_amount_paise<=0 or p_amount_paise>v_claim.amount_requested_paise then
      raise exception 'Approved amount must be positive and no greater than the requested claim';
    end if;
    update public.deposit_claims set status='approved',decision_amount_paise=p_amount_paise,
      decision_reason=left(p_reason,2000),decided_by=v_actor,decided_at=now() where id=p_claim_id;
  else
    if p_amount_paise not in (0,null) then raise exception 'A rejected claim cannot apply an amount'; end if;
    update public.deposit_claims set status='rejected',decision_amount_paise=0,
      decision_reason=left(p_reason,2000),decided_by=v_actor,decided_at=now() where id=p_claim_id;
  end if;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(v_claim.booking_id,v_actor,'deposit_claim_decided',
      jsonb_build_object('claim_id',p_claim_id,'decision',p_decision,'amount_paise',coalesce(p_amount_paise,0),'reason',left(p_reason,2000)),
      'deposit-claim-decision:'||p_claim_id::text);
end;
$$;
revoke all on function public.decide_deposit_claim(uuid,text,bigint,text) from public,anon;
grant execute on function public.decide_deposit_claim(uuid,text,bigint,text) to authenticated;

create or replace function public.request_deposit_claim_application(p_claim_id uuid,p_idempotency_key text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.deposit_claims%rowtype; v_deposit public.deposits%rowtype; v_request uuid; v_provider public.payment_provider_approvals%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance reviewer permission required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 then raise exception 'Idempotency key required'; end if;
  select id into v_request from public.outbox_events where idempotency_key='deposit-claim-application:'||p_idempotency_key;
  if v_request is not null then return v_request; end if;
  select * into v_claim from public.deposit_claims where id=p_claim_id for update;
  if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise is null or v_claim.decision_amount_paise<=0 then
    raise exception 'A reasoned, approved positive claim is required';
  end if;
  select * into v_deposit from public.deposits where id=v_claim.deposit_id for update;
  if v_deposit.status not in ('held_by_provider','claim_hold') then raise exception 'Deposit is not in an eligible provider state'; end if;
  select * into v_provider from public.payment_provider_approvals where provider_code=v_deposit.provider
    and enabled_for_deposits and supports_deposit_application and supports_deposit_dispute_hold
    and legal_approval_reference is not null and (expires_at is null or expires_at>now());
  if not found then raise exception 'Provider and legal approval for deposit application is not active'; end if;
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('deposit',v_deposit.id,'deposit_claim_application_requested',
      jsonb_build_object('deposit_id',v_deposit.id,'claim_id',p_claim_id,'amount_paise',v_claim.decision_amount_paise),
      'deposit-claim-application:'||p_idempotency_key)
    returning id into v_request;
  update public.deposits set status='claim_hold_pending' where id=v_deposit.id;
  insert into public.deposit_ledger(deposit_id,event_type,amount_paise,idempotency_key,metadata)
    values(v_deposit.id,'claim_hold_requested',v_claim.decision_amount_paise,'deposit-claim-hold:'||p_idempotency_key,
      jsonb_build_object('claim_id',p_claim_id));
  return v_request;
end;
$$;
revoke all on function public.request_deposit_claim_application(uuid,text) from public,anon;
grant execute on function public.request_deposit_claim_application(uuid,text) to authenticated;

-- Reconciliation payloads are provider-derived, inserted by a trusted adapter.
-- They are evidence for the finance queue, not an automatic cash adjustment.
create or replace function public.record_provider_reconciliation(
  p_provider text,p_report_reference text,p_period_start timestamptz,p_period_end timestamptz,p_records jsonb
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_run uuid; v_record jsonb; v_type text; v_internal text; v_provider_ref text;
  v_expected bigint; v_actual bigint; v_currency char(3); v_status text; v_matched integer:=0; v_unmatched integer:=0;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_period_end<=p_period_start or jsonb_typeof(p_records)<>'array' or jsonb_array_length(p_records)>10000 then
    raise exception 'Invalid provider reconciliation period or records';
  end if;
  if not exists(select 1 from public.payment_provider_approvals where provider_code=p_provider
    and supports_reconciliation and (expires_at is null or expires_at>now())) then
    raise exception 'Provider reconciliation is not approved';
  end if;
  insert into public.payment_reconciliation_runs(provider,report_reference,period_start,period_end,status)
    values(p_provider,left(p_report_reference,200),p_period_start,p_period_end,'started') returning id into v_run;
  for v_record in select value from jsonb_array_elements(p_records) loop
    v_type:=v_record->>'recordType';
    v_internal:=nullif(v_record->>'internalReference','');
    v_provider_ref:=nullif(v_record->>'providerReference','');
    v_expected:=nullif(v_record->>'expectedAmountPaise','')::bigint;
    v_actual:=nullif(v_record->>'amountPaise','')::bigint;
    v_currency:=coalesce(v_record->>'currency','INR')::char(3);
    v_status:=nullif(v_record->>'status','');
    if v_type not in ('payment','refund','payout','deposit','chargeback','settlement') or v_currency<>'INR' then
      raise exception 'Unsupported reconciliation record type or currency';
    end if;
    if v_type='payment' and v_provider_ref is not null then
      select p.id::text,p.amount_paise into v_internal,v_expected from public.payments p
        where p.provider=p_provider and (p.provider_payment_id=v_provider_ref or p.merchant_reference=v_provider_ref) limit 1;
    elsif v_type='refund' and v_provider_ref is not null then
      select r.id::text,r.amount_paise into v_internal,v_expected from public.refunds r
        where r.provider=p_provider and r.provider_refund_id=v_provider_ref limit 1;
    elsif v_type='payout' and v_provider_ref is not null then
      select t.id::text,t.amount_paise into v_internal,v_expected from public.payouts t
        where t.provider=p_provider and t.provider_transfer_id=v_provider_ref limit 1;
    elsif v_type='deposit' and v_provider_ref is not null then
      select d.id::text,d.amount_paise into v_internal,v_expected from public.deposits d
        where d.provider=p_provider and d.provider_reference=v_provider_ref limit 1;
    end if;
    insert into public.payment_reconciliation_items(run_id,record_type,internal_reference,provider_reference,
      expected_amount_paise,provider_amount_paise,currency,match_status,details)
    values(v_run,v_type,v_internal,v_provider_ref,v_expected,v_actual,v_currency,
      case when v_internal is null then 'missing_internal'
        when v_actual is null then 'missing_provider'
        when v_expected is distinct from v_actual then 'amount_mismatch'
        else 'manual_review' end,
      jsonb_build_object('provider_status',v_status,'source','provider_adapter'));
    if v_internal is not null and v_actual is not null and v_expected=v_actual then v_matched:=v_matched+1;
    else v_unmatched:=v_unmatched+1; end if;
  end loop;
  update public.payment_reconciliation_runs set matched_count=v_matched,unmatched_count=v_unmatched,
    status=case when v_unmatched=0 then 'completed' else 'partial' end,completed_at=now() where id=v_run;
  return v_run;
end;
$$;
revoke all on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) to service_role;

-- Persist the provider's external refund/transfer references without asserting
-- completion. Only apply_verified_* event RPCs can set terminal success states.
create or replace function public.attach_refund_provider_reference(p_refund_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.refunds set provider_refund_id=p_provider_reference,status='pending'
    where id=p_refund_id and status in ('requested','pending');
  if not found then raise exception 'Refund is not attachable'; end if;
end;
$$;
revoke all on function public.attach_refund_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_refund_provider_reference(uuid,text) to service_role;

create or replace function public.attach_payout_provider_reference(p_payout_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.payouts set provider_transfer_id=p_provider_reference,status='processing',initiated_at=coalesce(initiated_at,now())
    where id=p_payout_id and status in ('pending','processing');
  if not found then raise exception 'Payout is not attachable'; end if;
end;
$$;
revoke all on function public.attach_payout_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_payout_provider_reference(uuid,text) to service_role;

create or replace function public.attach_deposit_provider_reference(p_deposit_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.deposits set provider_reference=p_provider_reference
    where id=p_deposit_id and feature_enabled_at_creation and status='collection_pending';
  if not found then raise exception 'Deposit collection is not attachable'; end if;
end;
$$;
revoke all on function public.attach_deposit_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_deposit_provider_reference(uuid,text) to service_role;

-- Deposit ledger rows cannot be edited/deleted after insertion.
create or replace function private.reject_deposit_ledger_mutation()
returns trigger language plpgsql set search_path = pg_catalog
as $$ begin raise exception 'Deposit ledger is append-only'; end; $$;
drop trigger if exists deposit_ledger_append_only on public.deposit_ledger;
create trigger deposit_ledger_append_only before update or delete on public.deposit_ledger
for each row execute function private.reject_deposit_ledger_mutation();

-- A booking with no active provider-backed deposit must not show a deposit as
-- paid/held; a database row is only a workflow record, not proof of custody.
revoke all on public.payment_disputes,public.deposit_claims,public.payment_reconciliation_runs,
  public.payment_reconciliation_items from anon,authenticated;
alter table public.payment_disputes enable row level security;
alter table public.deposit_claims enable row level security;
alter table public.payment_reconciliation_runs enable row level security;
alter table public.payment_reconciliation_items enable row level security;

commit;
 then raise exception 'Invalid verified deposit event'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256,provider_payment_reference)
    values(null,p_provider,p_event_id,p_event_type,true,p_payload_sha256,p_provider_reference)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_deposit from public.deposits where id=p_deposit_id and provider=p_provider for update;
  if not found or v_deposit.amount_paise<>p_amount_paise or p_currency<>'INR'
    or (v_deposit.provider_reference is not null and p_provider_reference is not null and v_deposit.provider_reference<>p_provider_reference) then
    update public.payment_events set processing_status='dead_letter',processing_error_code='deposit_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','deposit_reference_or_amount_mismatch');
  end if;
  v_ledger_key:='deposit-provider-event:'||p_provider||':'||p_event_id;
  if p_event_type in ('deposit.held','deposit.collected','deposit.authorized') then
    if not v_deposit.feature_enabled_at_creation then raise exception 'Deposit feature was not enabled at booking creation'; end if;
    update public.deposits set status='held_by_provider',provider_reference=coalesce(provider_reference,p_provider_reference)
      where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'provider_held',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.released','deposit.refunded') then
    if v_deposit.status not in ('release_pending','refund_pending','held_by_provider','claim_hold') then
      raise exception 'Deposit is not in a releasable provider-confirmed state';
    end if;
    update public.deposits set status='released',provider_reference=coalesce(provider_reference,p_provider_reference)
      where id=p_deposit_id;
    update public.deposit_release_requests set status='released',processed_at=coalesce(processed_at,now())
      where deposit_id=p_deposit_id and status in ('requested','approved','processing','reconciliation_required');
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'released',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.claim_held','deposit.dispute_hold') then
    if v_deposit.status<>'held_by_provider' then raise exception 'Only a provider-held deposit may be claim-held'; end if;
    update public.deposits set status='claim_hold' where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'claim_held',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.amount_applied','deposit.claim_applied') then
    select * into v_claim from public.deposit_claims where id=p_claim_id and deposit_id=p_deposit_id for update;
    if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise is null
      or p_amount_paise<=0 or p_amount_paise>v_claim.decision_amount_paise then
      raise exception 'Provider deposit application exceeds the approved, reasoned claim';
    end if;
    if not exists(select 1 from public.payment_provider_approvals x where x.provider_code=p_provider
      and x.enabled_for_deposits and x.supports_deposit_application and x.legal_approval_reference is not null) then
      raise exception 'Provider and legal permission for deposit application is not enabled';
    end if;
    update public.deposits set status='partially_applied' where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key,metadata)
      values(p_deposit_id,'amount_applied',p_amount_paise,p_provider_reference,v_ledger_key,jsonb_build_object('claim_id',p_claim_id))
      on conflict(idempotency_key) do nothing;
    update public.deposit_claims set status='closed' where id=p_claim_id;
  elsif p_event_type in ('deposit.failed','deposit.rejected') then
    update public.deposits set status=case when v_deposit.status='collection_pending' then 'failed'::public.deposit_status else 'reconciliation_required'::public.deposit_status end
      where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'failed',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_deposit_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'deposit_status',(select status from public.deposits where id=p_deposit_id));
end;
$$;
revoke all on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid) from public,anon,authenticated;
grant execute on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid) to service_role;

create or replace function public.submit_deposit_claim(
  p_deposit_id uuid,p_amount_paise bigint,p_reason_code text,p_description text
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_deposit public.deposits%rowtype; v_booking public.bookings%rowtype; v_claim uuid;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if p_amount_paise<=0 or length(btrim(coalesce(p_reason_code,'')))<3
    or length(btrim(coalesce(p_description,'')))<20 then raise exception 'A reason, evidence description and requested amount are required'; end if;
  select * into v_deposit from public.deposits where id=p_deposit_id for update;
  if not found or not v_deposit.feature_enabled_at_creation or v_deposit.status not in ('held_by_provider','claim_hold') then
    raise exception 'No provider-confirmed deposit is available for a claim';
  end if;
  select * into v_booking from public.bookings where id=v_deposit.booking_id for update;
  if v_booking.owner_id<>v_actor or v_booking.status not in ('completed','disputed') then
    raise exception 'Only the lending owner may submit a post-return deposit claim';
  end if;
  if p_amount_paise>v_deposit.amount_paise then raise exception 'Claim cannot exceed the provider-confirmed deposit amount'; end if;
  if exists(select 1 from public.deposit_claims x where x.deposit_id=p_deposit_id and x.status not in ('rejected','closed')) then
    raise exception 'An active deposit claim already exists';
  end if;
  insert into public.deposit_claims(deposit_id,booking_id,claimant_id,against_user_id,amount_requested_paise,reason_code,description)
    values(p_deposit_id,v_booking.id,v_actor,v_booking.reader_id,p_amount_paise,left(p_reason_code,80),left(p_description,3000))
    returning id into v_claim;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(v_booking.id,v_actor,'deposit_claim_submitted',jsonb_build_object('claim_id',v_claim,'amount_paise',p_amount_paise),'deposit-claim:'||v_claim::text);
  insert into public.notifications(user_id,channel,template_key,payload)
    values(v_booking.reader_id,'in_app','deposit.claim_submitted',jsonb_build_object('booking_id',v_booking.id,'claim_id',v_claim));
  return v_claim;
end;
$$;
revoke all on function public.submit_deposit_claim(uuid,bigint,text,text) from public,anon;
grant execute on function public.submit_deposit_claim(uuid,bigint,text,text) to authenticated;

create or replace function public.decide_deposit_claim(
  p_claim_id uuid,p_decision text,p_amount_paise bigint,p_reason text
) returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.deposit_claims%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance reviewer permission required'; end if;
  if p_decision not in ('approve','reject') or length(btrim(coalesce(p_reason,'')))<10 then
    raise exception 'Select a valid decision and provide a reason';
  end if;
  select * into v_claim from public.deposit_claims where id=p_claim_id for update;
  if not found or v_claim.status not in ('submitted','under_review','needs_response') then raise exception 'Deposit claim is not reviewable'; end if;
  if p_decision='approve' then
    if p_amount_paise is null or p_amount_paise<=0 or p_amount_paise>v_claim.amount_requested_paise then
      raise exception 'Approved amount must be positive and no greater than the requested claim';
    end if;
    update public.deposit_claims set status='approved',decision_amount_paise=p_amount_paise,
      decision_reason=left(p_reason,2000),decided_by=v_actor,decided_at=now() where id=p_claim_id;
  else
    if p_amount_paise not in (0,null) then raise exception 'A rejected claim cannot apply an amount'; end if;
    update public.deposit_claims set status='rejected',decision_amount_paise=0,
      decision_reason=left(p_reason,2000),decided_by=v_actor,decided_at=now() where id=p_claim_id;
  end if;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(v_claim.booking_id,v_actor,'deposit_claim_decided',
      jsonb_build_object('claim_id',p_claim_id,'decision',p_decision,'amount_paise',coalesce(p_amount_paise,0),'reason',left(p_reason,2000)),
      'deposit-claim-decision:'||p_claim_id::text);
end;
$$;
revoke all on function public.decide_deposit_claim(uuid,text,bigint,text) from public,anon;
grant execute on function public.decide_deposit_claim(uuid,text,bigint,text) to authenticated;

create or replace function public.request_deposit_claim_application(p_claim_id uuid,p_idempotency_key text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.deposit_claims%rowtype; v_deposit public.deposits%rowtype; v_request uuid; v_provider public.payment_provider_approvals%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance reviewer permission required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 then raise exception 'Idempotency key required'; end if;
  select id into v_request from public.outbox_events where idempotency_key='deposit-claim-application:'||p_idempotency_key;
  if v_request is not null then return v_request; end if;
  select * into v_claim from public.deposit_claims where id=p_claim_id for update;
  if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise is null or v_claim.decision_amount_paise<=0 then
    raise exception 'A reasoned, approved positive claim is required';
  end if;
  select * into v_deposit from public.deposits where id=v_claim.deposit_id for update;
  if v_deposit.status not in ('held_by_provider','claim_hold') then raise exception 'Deposit is not in an eligible provider state'; end if;
  select * into v_provider from public.payment_provider_approvals where provider_code=v_deposit.provider
    and enabled_for_deposits and supports_deposit_application and supports_deposit_dispute_hold
    and legal_approval_reference is not null and (expires_at is null or expires_at>now());
  if not found then raise exception 'Provider and legal approval for deposit application is not active'; end if;
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('deposit',v_deposit.id,'deposit_claim_application_requested',
      jsonb_build_object('deposit_id',v_deposit.id,'claim_id',p_claim_id,'amount_paise',v_claim.decision_amount_paise),
      'deposit-claim-application:'||p_idempotency_key)
    returning id into v_request;
  update public.deposits set status='claim_hold_pending' where id=v_deposit.id;
  insert into public.deposit_ledger(deposit_id,event_type,amount_paise,idempotency_key,metadata)
    values(v_deposit.id,'claim_hold_requested',v_claim.decision_amount_paise,'deposit-claim-hold:'||p_idempotency_key,
      jsonb_build_object('claim_id',p_claim_id));
  return v_request;
end;
$$;
revoke all on function public.request_deposit_claim_application(uuid,text) from public,anon;
grant execute on function public.request_deposit_claim_application(uuid,text) to authenticated;

-- Reconciliation payloads are provider-derived, inserted by a trusted adapter.
-- They are evidence for the finance queue, not an automatic cash adjustment.
create or replace function public.record_provider_reconciliation(
  p_provider text,p_report_reference text,p_period_start timestamptz,p_period_end timestamptz,p_records jsonb
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_run uuid; v_record jsonb; v_type text; v_internal text; v_provider_ref text;
  v_expected bigint; v_actual bigint; v_currency char(3); v_status text; v_matched integer:=0; v_unmatched integer:=0;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_period_end<=p_period_start or jsonb_typeof(p_records)<>'array' or jsonb_array_length(p_records)>10000 then
    raise exception 'Invalid provider reconciliation period or records';
  end if;
  if not exists(select 1 from public.payment_provider_approvals where provider_code=p_provider
    and supports_reconciliation and (expires_at is null or expires_at>now())) then
    raise exception 'Provider reconciliation is not approved';
  end if;
  insert into public.payment_reconciliation_runs(provider,report_reference,period_start,period_end,status)
    values(p_provider,left(p_report_reference,200),p_period_start,p_period_end,'started') returning id into v_run;
  for v_record in select value from jsonb_array_elements(p_records) loop
    v_type:=v_record->>'recordType';
    v_internal:=nullif(v_record->>'internalReference','');
    v_provider_ref:=nullif(v_record->>'providerReference','');
    v_expected:=nullif(v_record->>'expectedAmountPaise','')::bigint;
    v_actual:=nullif(v_record->>'amountPaise','')::bigint;
    v_currency:=coalesce(v_record->>'currency','INR')::char(3);
    v_status:=nullif(v_record->>'status','');
    if v_type not in ('payment','refund','payout','deposit','chargeback','settlement') or v_currency<>'INR' then
      raise exception 'Unsupported reconciliation record type or currency';
    end if;
    if v_type='payment' and v_provider_ref is not null then
      select p.id::text,p.amount_paise into v_internal,v_expected from public.payments p
        where p.provider=p_provider and (p.provider_payment_id=v_provider_ref or p.merchant_reference=v_provider_ref) limit 1;
    elsif v_type='refund' and v_provider_ref is not null then
      select r.id::text,r.amount_paise into v_internal,v_expected from public.refunds r
        where r.provider=p_provider and r.provider_refund_id=v_provider_ref limit 1;
    elsif v_type='payout' and v_provider_ref is not null then
      select t.id::text,t.amount_paise into v_internal,v_expected from public.payouts t
        where t.provider=p_provider and t.provider_transfer_id=v_provider_ref limit 1;
    elsif v_type='deposit' and v_provider_ref is not null then
      select d.id::text,d.amount_paise into v_internal,v_expected from public.deposits d
        where d.provider=p_provider and d.provider_reference=v_provider_ref limit 1;
    end if;
    insert into public.payment_reconciliation_items(run_id,record_type,internal_reference,provider_reference,
      expected_amount_paise,provider_amount_paise,currency,match_status,details)
    values(v_run,v_type,v_internal,v_provider_ref,v_expected,v_actual,v_currency,
      case when v_internal is null then 'missing_internal'
        when v_actual is null then 'missing_provider'
        when v_expected is distinct from v_actual then 'amount_mismatch'
        else 'manual_review' end,
      jsonb_build_object('provider_status',v_status,'source','provider_adapter'));
    if v_internal is not null and v_actual is not null and v_expected=v_actual then v_matched:=v_matched+1;
    else v_unmatched:=v_unmatched+1; end if;
  end loop;
  update public.payment_reconciliation_runs set matched_count=v_matched,unmatched_count=v_unmatched,
    status=case when v_unmatched=0 then 'completed' else 'partial' end,completed_at=now() where id=v_run;
  return v_run;
end;
$$;
revoke all on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) to service_role;

-- Persist the provider's external refund/transfer references without asserting
-- completion. Only apply_verified_* event RPCs can set terminal success states.
create or replace function public.attach_refund_provider_reference(p_refund_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.refunds set provider_refund_id=p_provider_reference,status='pending'
    where id=p_refund_id and status in ('requested','pending');
  if not found then raise exception 'Refund is not attachable'; end if;
end;
$$;
revoke all on function public.attach_refund_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_refund_provider_reference(uuid,text) to service_role;

create or replace function public.attach_payout_provider_reference(p_payout_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.payouts set provider_transfer_id=p_provider_reference,status='processing',initiated_at=coalesce(initiated_at,now())
    where id=p_payout_id and status in ('pending','processing');
  if not found then raise exception 'Payout is not attachable'; end if;
end;
$$;
revoke all on function public.attach_payout_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_payout_provider_reference(uuid,text) to service_role;

create or replace function public.attach_deposit_provider_reference(p_deposit_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.deposits set provider_reference=p_provider_reference
    where id=p_deposit_id and feature_enabled_at_creation and status='collection_pending';
  if not found then raise exception 'Deposit collection is not attachable'; end if;
end;
$$;
revoke all on function public.attach_deposit_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_deposit_provider_reference(uuid,text) to service_role;

-- Deposit ledger rows cannot be edited/deleted after insertion.
create or replace function private.reject_deposit_ledger_mutation()
returns trigger language plpgsql set search_path = pg_catalog
as $$ begin raise exception 'Deposit ledger is append-only'; end; $$;
drop trigger if exists deposit_ledger_append_only on public.deposit_ledger;
create trigger deposit_ledger_append_only before update or delete on public.deposit_ledger
for each row execute function private.reject_deposit_ledger_mutation();

-- A booking with no active provider-backed deposit must not show a deposit as
-- paid/held; a database row is only a workflow record, not proof of custody.
revoke all on public.payment_disputes,public.deposit_claims,public.payment_reconciliation_runs,
  public.payment_reconciliation_items from anon,authenticated;
alter table public.payment_disputes enable row level security;
alter table public.deposit_claims enable row level security;
alter table public.payment_reconciliation_runs enable row level security;
alter table public.payment_reconciliation_items enable row level security;

commit;
 then raise exception 'Invalid verified refund event'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256,provider_payment_reference)
    values((select payment_id from public.refunds where id=p_refund_id),p_provider,p_event_id,p_event_type,true,p_payload_sha256,p_provider_refund_id)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_refund from public.refunds where id=p_refund_id and provider=p_provider for update;
  if not found or v_refund.amount_paise<>p_amount_paise or p_currency<>'INR' then
    update public.payment_events set processing_status='dead_letter',processing_error_code='refund_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','refund_reference_or_amount_mismatch');
  end if;
  if v_refund.provider_refund_id is not null and p_provider_refund_id is not null and v_refund.provider_refund_id<>p_provider_refund_id then
    update public.payment_events set processing_status='dead_letter',processing_error_code='refund_provider_id_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','refund_provider_id_mismatch');
  end if;
  if p_event_type in ('refund.succeeded','refund.processed') then
    update public.refunds set status='succeeded',provider_refund_id=coalesce(provider_refund_id,p_provider_refund_id),completed_at=coalesce(completed_at,now())
      where id=p_refund_id;
  elsif p_event_type in ('refund.failed','refund.rejected') then
    update public.refunds set status='failed',provider_refund_id=coalesce(provider_refund_id,p_provider_refund_id)
      where id=p_refund_id;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_refund_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  select * into v_payment from public.payments where id=v_refund.payment_id for update;
  select coalesce(sum(amount_paise),0),count(*) filter(where status='succeeded')
    into v_sum,v_count from public.refunds where payment_id=v_payment.id;
  if v_count>0 then
    update public.payments set status=case when v_sum>=amount_paise then 'refunded'::public.payment_status else 'partially_refunded'::public.payment_status end
      where id=v_payment.id;
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'refund_status',(select status from public.refunds where id=p_refund_id));
end;
$$;
revoke all on function public.apply_verified_refund_event(text,text,uuid,text,text,bigint,char,text) from public,anon,authenticated;
grant execute on function public.apply_verified_refund_event(text,text,uuid,text,text,bigint,char,text) to service_role;

create or replace function public.apply_verified_payout_event(
  p_provider text,p_event_id text,p_payout_id uuid,p_event_type text,p_provider_transfer_id text,
  p_amount_paise bigint,p_currency char(3),p_payload_sha256 text
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_payout public.payouts%rowtype; v_count bigint;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256)
    values((select p.id from public.payments p join public.owner_earnings e on e.booking_id=p.booking_id
      join public.payouts z on z.owner_earning_id=e.id where z.id=p_payout_id limit 1),
      p_provider,p_event_id,p_event_type,true,p_payload_sha256)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_payout from public.payouts where id=p_payout_id and provider=p_provider for update;
  if not found or v_payout.amount_paise<>p_amount_paise or p_currency<>'INR'
    or (v_payout.provider_transfer_id is not null and p_provider_transfer_id is not null and v_payout.provider_transfer_id<>p_provider_transfer_id) then
    update public.payment_events set processing_status='dead_letter',processing_error_code='payout_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','payout_reference_or_amount_mismatch');
  end if;
  if p_event_type in ('transfer.succeeded','payout.succeeded','settlement.completed') then
    update public.payouts set status='paid',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),settled_at=coalesce(settled_at,now())
      where id=p_payout_id;
    update public.owner_earnings set status='paid' where id=v_payout.owner_earning_id;
  elsif p_event_type in ('transfer.failed','payout.failed') then
    update public.payouts set status='failed',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),failure_code=p_event_type
      where id=p_payout_id;
    -- Retry requires a fresh payout attempt after finance has checked canonical provider state.
    update public.owner_earnings set status='eligible' where id=v_payout.owner_earning_id;
  elsif p_event_type in ('transfer.reversed','payout.reversed') then
    update public.payouts set status='reversed',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),failure_code=p_event_type
      where id=p_payout_id;
    update public.owner_earnings set status='reconciliation_required' where id=v_payout.owner_earning_id;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_payout_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'payout_status',(select status from public.payouts where id=p_payout_id));
end;
$$;
revoke all on function public.apply_verified_payout_event(text,text,uuid,text,text,bigint,char,text) from public,anon,authenticated;
grant execute on function public.apply_verified_payout_event(text,text,uuid,text,text,bigint,char,text) to service_role;

create or replace function public.apply_verified_deposit_event(
  p_provider text,p_event_id text,p_deposit_id uuid,p_event_type text,p_provider_reference text,
  p_amount_paise bigint,p_currency char(3),p_payload_sha256 text,p_claim_id uuid default null
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_deposit public.deposits%rowtype; v_claim public.deposit_claims%rowtype; v_count bigint; v_ledger_key text;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_payload_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'Invalid verified deposit event'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256,provider_payment_reference)
    values(null,p_provider,p_event_id,p_event_type,true,p_payload_sha256,p_provider_reference)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_deposit from public.deposits where id=p_deposit_id and provider=p_provider for update;
  if not found or v_deposit.amount_paise<>p_amount_paise or p_currency<>'INR'
    or (v_deposit.provider_reference is not null and p_provider_reference is not null and v_deposit.provider_reference<>p_provider_reference) then
    update public.payment_events set processing_status='dead_letter',processing_error_code='deposit_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','deposit_reference_or_amount_mismatch');
  end if;
  v_ledger_key:='deposit-provider-event:'||p_provider||':'||p_event_id;
  if p_event_type in ('deposit.held','deposit.collected','deposit.authorized') then
    if not v_deposit.feature_enabled_at_creation then raise exception 'Deposit feature was not enabled at booking creation'; end if;
    update public.deposits set status='held_by_provider',provider_reference=coalesce(provider_reference,p_provider_reference)
      where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'provider_held',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.released','deposit.refunded') then
    if v_deposit.status not in ('release_pending','refund_pending','held_by_provider','claim_hold') then
      raise exception 'Deposit is not in a releasable provider-confirmed state';
    end if;
    update public.deposits set status='released',provider_reference=coalesce(provider_reference,p_provider_reference)
      where id=p_deposit_id;
    update public.deposit_release_requests set status='released',processed_at=coalesce(processed_at,now())
      where deposit_id=p_deposit_id and status in ('requested','approved','processing','reconciliation_required');
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'released',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.claim_held','deposit.dispute_hold') then
    if v_deposit.status<>'held_by_provider' then raise exception 'Only a provider-held deposit may be claim-held'; end if;
    update public.deposits set status='claim_hold' where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'claim_held',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.amount_applied','deposit.claim_applied') then
    select * into v_claim from public.deposit_claims where id=p_claim_id and deposit_id=p_deposit_id for update;
    if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise is null
      or p_amount_paise<=0 or p_amount_paise>v_claim.decision_amount_paise then
      raise exception 'Provider deposit application exceeds the approved, reasoned claim';
    end if;
    if not exists(select 1 from public.payment_provider_approvals x where x.provider_code=p_provider
      and x.enabled_for_deposits and x.supports_deposit_application and x.legal_approval_reference is not null) then
      raise exception 'Provider and legal permission for deposit application is not enabled';
    end if;
    update public.deposits set status='partially_applied' where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key,metadata)
      values(p_deposit_id,'amount_applied',p_amount_paise,p_provider_reference,v_ledger_key,jsonb_build_object('claim_id',p_claim_id))
      on conflict(idempotency_key) do nothing;
    update public.deposit_claims set status='closed' where id=p_claim_id;
  elsif p_event_type in ('deposit.failed','deposit.rejected') then
    update public.deposits set status=case when v_deposit.status='collection_pending' then 'failed'::public.deposit_status else 'reconciliation_required'::public.deposit_status end
      where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'failed',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_deposit_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'deposit_status',(select status from public.deposits where id=p_deposit_id));
end;
$$;
revoke all on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid) from public,anon,authenticated;
grant execute on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid) to service_role;

create or replace function public.submit_deposit_claim(
  p_deposit_id uuid,p_amount_paise bigint,p_reason_code text,p_description text
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_deposit public.deposits%rowtype; v_booking public.bookings%rowtype; v_claim uuid;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if p_amount_paise<=0 or length(btrim(coalesce(p_reason_code,'')))<3
    or length(btrim(coalesce(p_description,'')))<20 then raise exception 'A reason, evidence description and requested amount are required'; end if;
  select * into v_deposit from public.deposits where id=p_deposit_id for update;
  if not found or not v_deposit.feature_enabled_at_creation or v_deposit.status not in ('held_by_provider','claim_hold') then
    raise exception 'No provider-confirmed deposit is available for a claim';
  end if;
  select * into v_booking from public.bookings where id=v_deposit.booking_id for update;
  if v_booking.owner_id<>v_actor or v_booking.status not in ('completed','disputed') then
    raise exception 'Only the lending owner may submit a post-return deposit claim';
  end if;
  if p_amount_paise>v_deposit.amount_paise then raise exception 'Claim cannot exceed the provider-confirmed deposit amount'; end if;
  if exists(select 1 from public.deposit_claims x where x.deposit_id=p_deposit_id and x.status not in ('rejected','closed')) then
    raise exception 'An active deposit claim already exists';
  end if;
  insert into public.deposit_claims(deposit_id,booking_id,claimant_id,against_user_id,amount_requested_paise,reason_code,description)
    values(p_deposit_id,v_booking.id,v_actor,v_booking.reader_id,p_amount_paise,left(p_reason_code,80),left(p_description,3000))
    returning id into v_claim;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(v_booking.id,v_actor,'deposit_claim_submitted',jsonb_build_object('claim_id',v_claim,'amount_paise',p_amount_paise),'deposit-claim:'||v_claim::text);
  insert into public.notifications(user_id,channel,template_key,payload)
    values(v_booking.reader_id,'in_app','deposit.claim_submitted',jsonb_build_object('booking_id',v_booking.id,'claim_id',v_claim));
  return v_claim;
end;
$$;
revoke all on function public.submit_deposit_claim(uuid,bigint,text,text) from public,anon;
grant execute on function public.submit_deposit_claim(uuid,bigint,text,text) to authenticated;

create or replace function public.decide_deposit_claim(
  p_claim_id uuid,p_decision text,p_amount_paise bigint,p_reason text
) returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.deposit_claims%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance reviewer permission required'; end if;
  if p_decision not in ('approve','reject') or length(btrim(coalesce(p_reason,'')))<10 then
    raise exception 'Select a valid decision and provide a reason';
  end if;
  select * into v_claim from public.deposit_claims where id=p_claim_id for update;
  if not found or v_claim.status not in ('submitted','under_review','needs_response') then raise exception 'Deposit claim is not reviewable'; end if;
  if p_decision='approve' then
    if p_amount_paise is null or p_amount_paise<=0 or p_amount_paise>v_claim.amount_requested_paise then
      raise exception 'Approved amount must be positive and no greater than the requested claim';
    end if;
    update public.deposit_claims set status='approved',decision_amount_paise=p_amount_paise,
      decision_reason=left(p_reason,2000),decided_by=v_actor,decided_at=now() where id=p_claim_id;
  else
    if p_amount_paise not in (0,null) then raise exception 'A rejected claim cannot apply an amount'; end if;
    update public.deposit_claims set status='rejected',decision_amount_paise=0,
      decision_reason=left(p_reason,2000),decided_by=v_actor,decided_at=now() where id=p_claim_id;
  end if;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(v_claim.booking_id,v_actor,'deposit_claim_decided',
      jsonb_build_object('claim_id',p_claim_id,'decision',p_decision,'amount_paise',coalesce(p_amount_paise,0),'reason',left(p_reason,2000)),
      'deposit-claim-decision:'||p_claim_id::text);
end;
$$;
revoke all on function public.decide_deposit_claim(uuid,text,bigint,text) from public,anon;
grant execute on function public.decide_deposit_claim(uuid,text,bigint,text) to authenticated;

create or replace function public.request_deposit_claim_application(p_claim_id uuid,p_idempotency_key text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.deposit_claims%rowtype; v_deposit public.deposits%rowtype; v_request uuid; v_provider public.payment_provider_approvals%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance reviewer permission required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 then raise exception 'Idempotency key required'; end if;
  select id into v_request from public.outbox_events where idempotency_key='deposit-claim-application:'||p_idempotency_key;
  if v_request is not null then return v_request; end if;
  select * into v_claim from public.deposit_claims where id=p_claim_id for update;
  if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise is null or v_claim.decision_amount_paise<=0 then
    raise exception 'A reasoned, approved positive claim is required';
  end if;
  select * into v_deposit from public.deposits where id=v_claim.deposit_id for update;
  if v_deposit.status not in ('held_by_provider','claim_hold') then raise exception 'Deposit is not in an eligible provider state'; end if;
  select * into v_provider from public.payment_provider_approvals where provider_code=v_deposit.provider
    and enabled_for_deposits and supports_deposit_application and supports_deposit_dispute_hold
    and legal_approval_reference is not null and (expires_at is null or expires_at>now());
  if not found then raise exception 'Provider and legal approval for deposit application is not active'; end if;
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('deposit',v_deposit.id,'deposit_claim_application_requested',
      jsonb_build_object('deposit_id',v_deposit.id,'claim_id',p_claim_id,'amount_paise',v_claim.decision_amount_paise),
      'deposit-claim-application:'||p_idempotency_key)
    returning id into v_request;
  update public.deposits set status='claim_hold_pending' where id=v_deposit.id;
  insert into public.deposit_ledger(deposit_id,event_type,amount_paise,idempotency_key,metadata)
    values(v_deposit.id,'claim_hold_requested',v_claim.decision_amount_paise,'deposit-claim-hold:'||p_idempotency_key,
      jsonb_build_object('claim_id',p_claim_id));
  return v_request;
end;
$$;
revoke all on function public.request_deposit_claim_application(uuid,text) from public,anon;
grant execute on function public.request_deposit_claim_application(uuid,text) to authenticated;

-- Reconciliation payloads are provider-derived, inserted by a trusted adapter.
-- They are evidence for the finance queue, not an automatic cash adjustment.
create or replace function public.record_provider_reconciliation(
  p_provider text,p_report_reference text,p_period_start timestamptz,p_period_end timestamptz,p_records jsonb
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_run uuid; v_record jsonb; v_type text; v_internal text; v_provider_ref text;
  v_expected bigint; v_actual bigint; v_currency char(3); v_status text; v_matched integer:=0; v_unmatched integer:=0;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_period_end<=p_period_start or jsonb_typeof(p_records)<>'array' or jsonb_array_length(p_records)>10000 then
    raise exception 'Invalid provider reconciliation period or records';
  end if;
  if not exists(select 1 from public.payment_provider_approvals where provider_code=p_provider
    and supports_reconciliation and (expires_at is null or expires_at>now())) then
    raise exception 'Provider reconciliation is not approved';
  end if;
  insert into public.payment_reconciliation_runs(provider,report_reference,period_start,period_end,status)
    values(p_provider,left(p_report_reference,200),p_period_start,p_period_end,'started') returning id into v_run;
  for v_record in select value from jsonb_array_elements(p_records) loop
    v_type:=v_record->>'recordType';
    v_internal:=nullif(v_record->>'internalReference','');
    v_provider_ref:=nullif(v_record->>'providerReference','');
    v_expected:=nullif(v_record->>'expectedAmountPaise','')::bigint;
    v_actual:=nullif(v_record->>'amountPaise','')::bigint;
    v_currency:=coalesce(v_record->>'currency','INR')::char(3);
    v_status:=nullif(v_record->>'status','');
    if v_type not in ('payment','refund','payout','deposit','chargeback','settlement') or v_currency<>'INR' then
      raise exception 'Unsupported reconciliation record type or currency';
    end if;
    if v_type='payment' and v_provider_ref is not null then
      select p.id::text,p.amount_paise into v_internal,v_expected from public.payments p
        where p.provider=p_provider and (p.provider_payment_id=v_provider_ref or p.merchant_reference=v_provider_ref) limit 1;
    elsif v_type='refund' and v_provider_ref is not null then
      select r.id::text,r.amount_paise into v_internal,v_expected from public.refunds r
        where r.provider=p_provider and r.provider_refund_id=v_provider_ref limit 1;
    elsif v_type='payout' and v_provider_ref is not null then
      select t.id::text,t.amount_paise into v_internal,v_expected from public.payouts t
        where t.provider=p_provider and t.provider_transfer_id=v_provider_ref limit 1;
    elsif v_type='deposit' and v_provider_ref is not null then
      select d.id::text,d.amount_paise into v_internal,v_expected from public.deposits d
        where d.provider=p_provider and d.provider_reference=v_provider_ref limit 1;
    end if;
    insert into public.payment_reconciliation_items(run_id,record_type,internal_reference,provider_reference,
      expected_amount_paise,provider_amount_paise,currency,match_status,details)
    values(v_run,v_type,v_internal,v_provider_ref,v_expected,v_actual,v_currency,
      case when v_internal is null then 'missing_internal'
        when v_actual is null then 'missing_provider'
        when v_expected is distinct from v_actual then 'amount_mismatch'
        else 'manual_review' end,
      jsonb_build_object('provider_status',v_status,'source','provider_adapter'));
    if v_internal is not null and v_actual is not null and v_expected=v_actual then v_matched:=v_matched+1;
    else v_unmatched:=v_unmatched+1; end if;
  end loop;
  update public.payment_reconciliation_runs set matched_count=v_matched,unmatched_count=v_unmatched,
    status=case when v_unmatched=0 then 'completed' else 'partial' end,completed_at=now() where id=v_run;
  return v_run;
end;
$$;
revoke all on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) to service_role;

-- Persist the provider's external refund/transfer references without asserting
-- completion. Only apply_verified_* event RPCs can set terminal success states.
create or replace function public.attach_refund_provider_reference(p_refund_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.refunds set provider_refund_id=p_provider_reference,status='pending'
    where id=p_refund_id and status in ('requested','pending');
  if not found then raise exception 'Refund is not attachable'; end if;
end;
$$;
revoke all on function public.attach_refund_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_refund_provider_reference(uuid,text) to service_role;

create or replace function public.attach_payout_provider_reference(p_payout_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.payouts set provider_transfer_id=p_provider_reference,status='processing',initiated_at=coalesce(initiated_at,now())
    where id=p_payout_id and status in ('pending','processing');
  if not found then raise exception 'Payout is not attachable'; end if;
end;
$$;
revoke all on function public.attach_payout_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_payout_provider_reference(uuid,text) to service_role;

create or replace function public.attach_deposit_provider_reference(p_deposit_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.deposits set provider_reference=p_provider_reference
    where id=p_deposit_id and feature_enabled_at_creation and status='collection_pending';
  if not found then raise exception 'Deposit collection is not attachable'; end if;
end;
$$;
revoke all on function public.attach_deposit_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_deposit_provider_reference(uuid,text) to service_role;

-- Deposit ledger rows cannot be edited/deleted after insertion.
create or replace function private.reject_deposit_ledger_mutation()
returns trigger language plpgsql set search_path = pg_catalog
as $$ begin raise exception 'Deposit ledger is append-only'; end; $$;
drop trigger if exists deposit_ledger_append_only on public.deposit_ledger;
create trigger deposit_ledger_append_only before update or delete on public.deposit_ledger
for each row execute function private.reject_deposit_ledger_mutation();

-- A booking with no active provider-backed deposit must not show a deposit as
-- paid/held; a database row is only a workflow record, not proof of custody.
revoke all on public.payment_disputes,public.deposit_claims,public.payment_reconciliation_runs,
  public.payment_reconciliation_items from anon,authenticated;
alter table public.payment_disputes enable row level security;
alter table public.deposit_claims enable row level security;
alter table public.payment_reconciliation_runs enable row level security;
alter table public.payment_reconciliation_items enable row level security;

commit;
 then raise exception 'Invalid verified payout event'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256)
    values((select p.id from public.payments p join public.owner_earnings e on e.booking_id=p.booking_id
      join public.payouts z on z.owner_earning_id=e.id where z.id=p_payout_id limit 1),
      p_provider,p_event_id,p_event_type,true,p_payload_sha256)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_payout from public.payouts where id=p_payout_id and provider=p_provider for update;
  if not found or v_payout.amount_paise<>p_amount_paise or p_currency<>'INR'
    or (v_payout.provider_transfer_id is not null and p_provider_transfer_id is not null and v_payout.provider_transfer_id<>p_provider_transfer_id) then
    update public.payment_events set processing_status='dead_letter',processing_error_code='payout_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','payout_reference_or_amount_mismatch');
  end if;
  if p_event_type in ('transfer.succeeded','payout.succeeded','settlement.completed') then
    update public.payouts set status='paid',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),settled_at=coalesce(settled_at,now())
      where id=p_payout_id;
    update public.owner_earnings set status='paid' where id=v_payout.owner_earning_id;
  elsif p_event_type in ('transfer.failed','payout.failed') then
    update public.payouts set status='failed',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),failure_code=p_event_type
      where id=p_payout_id;
    -- Retry requires a fresh payout attempt after finance has checked canonical provider state.
    update public.owner_earnings set status='eligible' where id=v_payout.owner_earning_id;
  elsif p_event_type in ('transfer.reversed','payout.reversed') then
    update public.payouts set status='reversed',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),failure_code=p_event_type
      where id=p_payout_id;
    update public.owner_earnings set status='reconciliation_required' where id=v_payout.owner_earning_id;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_payout_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'payout_status',(select status from public.payouts where id=p_payout_id));
end;
$$;
revoke all on function public.apply_verified_payout_event(text,text,uuid,text,text,bigint,char,text) from public,anon,authenticated;
grant execute on function public.apply_verified_payout_event(text,text,uuid,text,text,bigint,char,text) to service_role;

create or replace function public.apply_verified_deposit_event(
  p_provider text,p_event_id text,p_deposit_id uuid,p_event_type text,p_provider_reference text,
  p_amount_paise bigint,p_currency char(3),p_payload_sha256 text,p_claim_id uuid default null
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_deposit public.deposits%rowtype; v_claim public.deposit_claims%rowtype; v_count bigint; v_ledger_key text;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_payload_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'Invalid verified deposit event'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256,provider_payment_reference)
    values(null,p_provider,p_event_id,p_event_type,true,p_payload_sha256,p_provider_reference)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_deposit from public.deposits where id=p_deposit_id and provider=p_provider for update;
  if not found or v_deposit.amount_paise<>p_amount_paise or p_currency<>'INR'
    or (v_deposit.provider_reference is not null and p_provider_reference is not null and v_deposit.provider_reference<>p_provider_reference) then
    update public.payment_events set processing_status='dead_letter',processing_error_code='deposit_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','deposit_reference_or_amount_mismatch');
  end if;
  v_ledger_key:='deposit-provider-event:'||p_provider||':'||p_event_id;
  if p_event_type in ('deposit.held','deposit.collected','deposit.authorized') then
    if not v_deposit.feature_enabled_at_creation then raise exception 'Deposit feature was not enabled at booking creation'; end if;
    update public.deposits set status='held_by_provider',provider_reference=coalesce(provider_reference,p_provider_reference)
      where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'provider_held',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.released','deposit.refunded') then
    if v_deposit.status not in ('release_pending','refund_pending','held_by_provider','claim_hold') then
      raise exception 'Deposit is not in a releasable provider-confirmed state';
    end if;
    update public.deposits set status='released',provider_reference=coalesce(provider_reference,p_provider_reference)
      where id=p_deposit_id;
    update public.deposit_release_requests set status='released',processed_at=coalesce(processed_at,now())
      where deposit_id=p_deposit_id and status in ('requested','approved','processing','reconciliation_required');
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'released',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.claim_held','deposit.dispute_hold') then
    if v_deposit.status<>'held_by_provider' then raise exception 'Only a provider-held deposit may be claim-held'; end if;
    update public.deposits set status='claim_hold' where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'claim_held',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.amount_applied','deposit.claim_applied') then
    select * into v_claim from public.deposit_claims where id=p_claim_id and deposit_id=p_deposit_id for update;
    if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise is null
      or p_amount_paise<=0 or p_amount_paise>v_claim.decision_amount_paise then
      raise exception 'Provider deposit application exceeds the approved, reasoned claim';
    end if;
    if not exists(select 1 from public.payment_provider_approvals x where x.provider_code=p_provider
      and x.enabled_for_deposits and x.supports_deposit_application and x.legal_approval_reference is not null) then
      raise exception 'Provider and legal permission for deposit application is not enabled';
    end if;
    update public.deposits set status='partially_applied' where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key,metadata)
      values(p_deposit_id,'amount_applied',p_amount_paise,p_provider_reference,v_ledger_key,jsonb_build_object('claim_id',p_claim_id))
      on conflict(idempotency_key) do nothing;
    update public.deposit_claims set status='closed' where id=p_claim_id;
  elsif p_event_type in ('deposit.failed','deposit.rejected') then
    update public.deposits set status=case when v_deposit.status='collection_pending' then 'failed'::public.deposit_status else 'reconciliation_required'::public.deposit_status end
      where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'failed',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_deposit_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'deposit_status',(select status from public.deposits where id=p_deposit_id));
end;
$$;
revoke all on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid) from public,anon,authenticated;
grant execute on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid) to service_role;

create or replace function public.submit_deposit_claim(
  p_deposit_id uuid,p_amount_paise bigint,p_reason_code text,p_description text
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_deposit public.deposits%rowtype; v_booking public.bookings%rowtype; v_claim uuid;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if p_amount_paise<=0 or length(btrim(coalesce(p_reason_code,'')))<3
    or length(btrim(coalesce(p_description,'')))<20 then raise exception 'A reason, evidence description and requested amount are required'; end if;
  select * into v_deposit from public.deposits where id=p_deposit_id for update;
  if not found or not v_deposit.feature_enabled_at_creation or v_deposit.status not in ('held_by_provider','claim_hold') then
    raise exception 'No provider-confirmed deposit is available for a claim';
  end if;
  select * into v_booking from public.bookings where id=v_deposit.booking_id for update;
  if v_booking.owner_id<>v_actor or v_booking.status not in ('completed','disputed') then
    raise exception 'Only the lending owner may submit a post-return deposit claim';
  end if;
  if p_amount_paise>v_deposit.amount_paise then raise exception 'Claim cannot exceed the provider-confirmed deposit amount'; end if;
  if exists(select 1 from public.deposit_claims x where x.deposit_id=p_deposit_id and x.status not in ('rejected','closed')) then
    raise exception 'An active deposit claim already exists';
  end if;
  insert into public.deposit_claims(deposit_id,booking_id,claimant_id,against_user_id,amount_requested_paise,reason_code,description)
    values(p_deposit_id,v_booking.id,v_actor,v_booking.reader_id,p_amount_paise,left(p_reason_code,80),left(p_description,3000))
    returning id into v_claim;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(v_booking.id,v_actor,'deposit_claim_submitted',jsonb_build_object('claim_id',v_claim,'amount_paise',p_amount_paise),'deposit-claim:'||v_claim::text);
  insert into public.notifications(user_id,channel,template_key,payload)
    values(v_booking.reader_id,'in_app','deposit.claim_submitted',jsonb_build_object('booking_id',v_booking.id,'claim_id',v_claim));
  return v_claim;
end;
$$;
revoke all on function public.submit_deposit_claim(uuid,bigint,text,text) from public,anon;
grant execute on function public.submit_deposit_claim(uuid,bigint,text,text) to authenticated;

create or replace function public.decide_deposit_claim(
  p_claim_id uuid,p_decision text,p_amount_paise bigint,p_reason text
) returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.deposit_claims%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance reviewer permission required'; end if;
  if p_decision not in ('approve','reject') or length(btrim(coalesce(p_reason,'')))<10 then
    raise exception 'Select a valid decision and provide a reason';
  end if;
  select * into v_claim from public.deposit_claims where id=p_claim_id for update;
  if not found or v_claim.status not in ('submitted','under_review','needs_response') then raise exception 'Deposit claim is not reviewable'; end if;
  if p_decision='approve' then
    if p_amount_paise is null or p_amount_paise<=0 or p_amount_paise>v_claim.amount_requested_paise then
      raise exception 'Approved amount must be positive and no greater than the requested claim';
    end if;
    update public.deposit_claims set status='approved',decision_amount_paise=p_amount_paise,
      decision_reason=left(p_reason,2000),decided_by=v_actor,decided_at=now() where id=p_claim_id;
  else
    if p_amount_paise not in (0,null) then raise exception 'A rejected claim cannot apply an amount'; end if;
    update public.deposit_claims set status='rejected',decision_amount_paise=0,
      decision_reason=left(p_reason,2000),decided_by=v_actor,decided_at=now() where id=p_claim_id;
  end if;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(v_claim.booking_id,v_actor,'deposit_claim_decided',
      jsonb_build_object('claim_id',p_claim_id,'decision',p_decision,'amount_paise',coalesce(p_amount_paise,0),'reason',left(p_reason,2000)),
      'deposit-claim-decision:'||p_claim_id::text);
end;
$$;
revoke all on function public.decide_deposit_claim(uuid,text,bigint,text) from public,anon;
grant execute on function public.decide_deposit_claim(uuid,text,bigint,text) to authenticated;

create or replace function public.request_deposit_claim_application(p_claim_id uuid,p_idempotency_key text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.deposit_claims%rowtype; v_deposit public.deposits%rowtype; v_request uuid; v_provider public.payment_provider_approvals%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance reviewer permission required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 then raise exception 'Idempotency key required'; end if;
  select id into v_request from public.outbox_events where idempotency_key='deposit-claim-application:'||p_idempotency_key;
  if v_request is not null then return v_request; end if;
  select * into v_claim from public.deposit_claims where id=p_claim_id for update;
  if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise is null or v_claim.decision_amount_paise<=0 then
    raise exception 'A reasoned, approved positive claim is required';
  end if;
  select * into v_deposit from public.deposits where id=v_claim.deposit_id for update;
  if v_deposit.status not in ('held_by_provider','claim_hold') then raise exception 'Deposit is not in an eligible provider state'; end if;
  select * into v_provider from public.payment_provider_approvals where provider_code=v_deposit.provider
    and enabled_for_deposits and supports_deposit_application and supports_deposit_dispute_hold
    and legal_approval_reference is not null and (expires_at is null or expires_at>now());
  if not found then raise exception 'Provider and legal approval for deposit application is not active'; end if;
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('deposit',v_deposit.id,'deposit_claim_application_requested',
      jsonb_build_object('deposit_id',v_deposit.id,'claim_id',p_claim_id,'amount_paise',v_claim.decision_amount_paise),
      'deposit-claim-application:'||p_idempotency_key)
    returning id into v_request;
  update public.deposits set status='claim_hold_pending' where id=v_deposit.id;
  insert into public.deposit_ledger(deposit_id,event_type,amount_paise,idempotency_key,metadata)
    values(v_deposit.id,'claim_hold_requested',v_claim.decision_amount_paise,'deposit-claim-hold:'||p_idempotency_key,
      jsonb_build_object('claim_id',p_claim_id));
  return v_request;
end;
$$;
revoke all on function public.request_deposit_claim_application(uuid,text) from public,anon;
grant execute on function public.request_deposit_claim_application(uuid,text) to authenticated;

-- Reconciliation payloads are provider-derived, inserted by a trusted adapter.
-- They are evidence for the finance queue, not an automatic cash adjustment.
create or replace function public.record_provider_reconciliation(
  p_provider text,p_report_reference text,p_period_start timestamptz,p_period_end timestamptz,p_records jsonb
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_run uuid; v_record jsonb; v_type text; v_internal text; v_provider_ref text;
  v_expected bigint; v_actual bigint; v_currency char(3); v_status text; v_matched integer:=0; v_unmatched integer:=0;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_period_end<=p_period_start or jsonb_typeof(p_records)<>'array' or jsonb_array_length(p_records)>10000 then
    raise exception 'Invalid provider reconciliation period or records';
  end if;
  if not exists(select 1 from public.payment_provider_approvals where provider_code=p_provider
    and supports_reconciliation and (expires_at is null or expires_at>now())) then
    raise exception 'Provider reconciliation is not approved';
  end if;
  insert into public.payment_reconciliation_runs(provider,report_reference,period_start,period_end,status)
    values(p_provider,left(p_report_reference,200),p_period_start,p_period_end,'started') returning id into v_run;
  for v_record in select value from jsonb_array_elements(p_records) loop
    v_type:=v_record->>'recordType';
    v_internal:=nullif(v_record->>'internalReference','');
    v_provider_ref:=nullif(v_record->>'providerReference','');
    v_expected:=nullif(v_record->>'expectedAmountPaise','')::bigint;
    v_actual:=nullif(v_record->>'amountPaise','')::bigint;
    v_currency:=coalesce(v_record->>'currency','INR')::char(3);
    v_status:=nullif(v_record->>'status','');
    if v_type not in ('payment','refund','payout','deposit','chargeback','settlement') or v_currency<>'INR' then
      raise exception 'Unsupported reconciliation record type or currency';
    end if;
    if v_type='payment' and v_provider_ref is not null then
      select p.id::text,p.amount_paise into v_internal,v_expected from public.payments p
        where p.provider=p_provider and (p.provider_payment_id=v_provider_ref or p.merchant_reference=v_provider_ref) limit 1;
    elsif v_type='refund' and v_provider_ref is not null then
      select r.id::text,r.amount_paise into v_internal,v_expected from public.refunds r
        where r.provider=p_provider and r.provider_refund_id=v_provider_ref limit 1;
    elsif v_type='payout' and v_provider_ref is not null then
      select t.id::text,t.amount_paise into v_internal,v_expected from public.payouts t
        where t.provider=p_provider and t.provider_transfer_id=v_provider_ref limit 1;
    elsif v_type='deposit' and v_provider_ref is not null then
      select d.id::text,d.amount_paise into v_internal,v_expected from public.deposits d
        where d.provider=p_provider and d.provider_reference=v_provider_ref limit 1;
    end if;
    insert into public.payment_reconciliation_items(run_id,record_type,internal_reference,provider_reference,
      expected_amount_paise,provider_amount_paise,currency,match_status,details)
    values(v_run,v_type,v_internal,v_provider_ref,v_expected,v_actual,v_currency,
      case when v_internal is null then 'missing_internal'
        when v_actual is null then 'missing_provider'
        when v_expected is distinct from v_actual then 'amount_mismatch'
        else 'manual_review' end,
      jsonb_build_object('provider_status',v_status,'source','provider_adapter'));
    if v_internal is not null and v_actual is not null and v_expected=v_actual then v_matched:=v_matched+1;
    else v_unmatched:=v_unmatched+1; end if;
  end loop;
  update public.payment_reconciliation_runs set matched_count=v_matched,unmatched_count=v_unmatched,
    status=case when v_unmatched=0 then 'completed' else 'partial' end,completed_at=now() where id=v_run;
  return v_run;
end;
$$;
revoke all on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) to service_role;

-- Persist the provider's external refund/transfer references without asserting
-- completion. Only apply_verified_* event RPCs can set terminal success states.
create or replace function public.attach_refund_provider_reference(p_refund_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.refunds set provider_refund_id=p_provider_reference,status='pending'
    where id=p_refund_id and status in ('requested','pending');
  if not found then raise exception 'Refund is not attachable'; end if;
end;
$$;
revoke all on function public.attach_refund_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_refund_provider_reference(uuid,text) to service_role;

create or replace function public.attach_payout_provider_reference(p_payout_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.payouts set provider_transfer_id=p_provider_reference,status='processing',initiated_at=coalesce(initiated_at,now())
    where id=p_payout_id and status in ('pending','processing');
  if not found then raise exception 'Payout is not attachable'; end if;
end;
$$;
revoke all on function public.attach_payout_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_payout_provider_reference(uuid,text) to service_role;

create or replace function public.attach_deposit_provider_reference(p_deposit_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.deposits set provider_reference=p_provider_reference
    where id=p_deposit_id and feature_enabled_at_creation and status='collection_pending';
  if not found then raise exception 'Deposit collection is not attachable'; end if;
end;
$$;
revoke all on function public.attach_deposit_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_deposit_provider_reference(uuid,text) to service_role;

-- Deposit ledger rows cannot be edited/deleted after insertion.
create or replace function private.reject_deposit_ledger_mutation()
returns trigger language plpgsql set search_path = pg_catalog
as $$ begin raise exception 'Deposit ledger is append-only'; end; $$;
drop trigger if exists deposit_ledger_append_only on public.deposit_ledger;
create trigger deposit_ledger_append_only before update or delete on public.deposit_ledger
for each row execute function private.reject_deposit_ledger_mutation();

-- A booking with no active provider-backed deposit must not show a deposit as
-- paid/held; a database row is only a workflow record, not proof of custody.
revoke all on public.payment_disputes,public.deposit_claims,public.payment_reconciliation_runs,
  public.payment_reconciliation_items from anon,authenticated;
alter table public.payment_disputes enable row level security;
alter table public.deposit_claims enable row level security;
alter table public.payment_reconciliation_runs enable row level security;
alter table public.payment_reconciliation_items enable row level security;

commit;
 then raise exception 'Invalid verified refund event'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256,provider_payment_reference)
    values((select payment_id from public.refunds where id=p_refund_id),p_provider,p_event_id,p_event_type,true,p_payload_sha256,p_provider_refund_id)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_refund from public.refunds where id=p_refund_id and provider=p_provider for update;
  if not found or v_refund.amount_paise<>p_amount_paise or p_currency<>'INR' then
    update public.payment_events set processing_status='dead_letter',processing_error_code='refund_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','refund_reference_or_amount_mismatch');
  end if;
  if v_refund.provider_refund_id is not null and p_provider_refund_id is not null and v_refund.provider_refund_id<>p_provider_refund_id then
    update public.payment_events set processing_status='dead_letter',processing_error_code='refund_provider_id_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','refund_provider_id_mismatch');
  end if;
  if p_event_type in ('refund.succeeded','refund.processed') then
    update public.refunds set status='succeeded',provider_refund_id=coalesce(provider_refund_id,p_provider_refund_id),completed_at=coalesce(completed_at,now())
      where id=p_refund_id;
  elsif p_event_type in ('refund.failed','refund.rejected') then
    update public.refunds set status='failed',provider_refund_id=coalesce(provider_refund_id,p_provider_refund_id)
      where id=p_refund_id;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_refund_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  select * into v_payment from public.payments where id=v_refund.payment_id for update;
  select coalesce(sum(amount_paise),0),count(*) filter(where status='succeeded')
    into v_sum,v_count from public.refunds where payment_id=v_payment.id;
  if v_count>0 then
    update public.payments set status=case when v_sum>=amount_paise then 'refunded'::public.payment_status else 'partially_refunded'::public.payment_status end
      where id=v_payment.id;
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'refund_status',(select status from public.refunds where id=p_refund_id));
end;
$$;
revoke all on function public.apply_verified_refund_event(text,text,uuid,text,text,bigint,char,text) from public,anon,authenticated;
grant execute on function public.apply_verified_refund_event(text,text,uuid,text,text,bigint,char,text) to service_role;

create or replace function public.apply_verified_payout_event(
  p_provider text,p_event_id text,p_payout_id uuid,p_event_type text,p_provider_transfer_id text,
  p_amount_paise bigint,p_currency char(3),p_payload_sha256 text
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_payout public.payouts%rowtype; v_count bigint;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256)
    values((select p.id from public.payments p join public.owner_earnings e on e.booking_id=p.booking_id
      join public.payouts z on z.owner_earning_id=e.id where z.id=p_payout_id limit 1),
      p_provider,p_event_id,p_event_type,true,p_payload_sha256)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_payout from public.payouts where id=p_payout_id and provider=p_provider for update;
  if not found or v_payout.amount_paise<>p_amount_paise or p_currency<>'INR'
    or (v_payout.provider_transfer_id is not null and p_provider_transfer_id is not null and v_payout.provider_transfer_id<>p_provider_transfer_id) then
    update public.payment_events set processing_status='dead_letter',processing_error_code='payout_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','payout_reference_or_amount_mismatch');
  end if;
  if p_event_type in ('transfer.succeeded','payout.succeeded','settlement.completed') then
    update public.payouts set status='paid',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),settled_at=coalesce(settled_at,now())
      where id=p_payout_id;
    update public.owner_earnings set status='paid' where id=v_payout.owner_earning_id;
  elsif p_event_type in ('transfer.failed','payout.failed') then
    update public.payouts set status='failed',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),failure_code=p_event_type
      where id=p_payout_id;
    -- Retry requires a fresh payout attempt after finance has checked canonical provider state.
    update public.owner_earnings set status='eligible' where id=v_payout.owner_earning_id;
  elsif p_event_type in ('transfer.reversed','payout.reversed') then
    update public.payouts set status='reversed',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),failure_code=p_event_type
      where id=p_payout_id;
    update public.owner_earnings set status='reconciliation_required' where id=v_payout.owner_earning_id;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_payout_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'payout_status',(select status from public.payouts where id=p_payout_id));
end;
$$;
revoke all on function public.apply_verified_payout_event(text,text,uuid,text,text,bigint,char,text) from public,anon,authenticated;
grant execute on function public.apply_verified_payout_event(text,text,uuid,text,text,bigint,char,text) to service_role;

create or replace function public.apply_verified_deposit_event(
  p_provider text,p_event_id text,p_deposit_id uuid,p_event_type text,p_provider_reference text,
  p_amount_paise bigint,p_currency char(3),p_payload_sha256 text,p_claim_id uuid default null
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_deposit public.deposits%rowtype; v_claim public.deposit_claims%rowtype; v_count bigint; v_ledger_key text;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_payload_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'Invalid verified deposit event'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256,provider_payment_reference)
    values(null,p_provider,p_event_id,p_event_type,true,p_payload_sha256,p_provider_reference)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_deposit from public.deposits where id=p_deposit_id and provider=p_provider for update;
  if not found or v_deposit.amount_paise<>p_amount_paise or p_currency<>'INR'
    or (v_deposit.provider_reference is not null and p_provider_reference is not null and v_deposit.provider_reference<>p_provider_reference) then
    update public.payment_events set processing_status='dead_letter',processing_error_code='deposit_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','deposit_reference_or_amount_mismatch');
  end if;
  v_ledger_key:='deposit-provider-event:'||p_provider||':'||p_event_id;
  if p_event_type in ('deposit.held','deposit.collected','deposit.authorized') then
    if not v_deposit.feature_enabled_at_creation then raise exception 'Deposit feature was not enabled at booking creation'; end if;
    update public.deposits set status='held_by_provider',provider_reference=coalesce(provider_reference,p_provider_reference)
      where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'provider_held',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.released','deposit.refunded') then
    if v_deposit.status not in ('release_pending','refund_pending','held_by_provider','claim_hold') then
      raise exception 'Deposit is not in a releasable provider-confirmed state';
    end if;
    update public.deposits set status='released',provider_reference=coalesce(provider_reference,p_provider_reference)
      where id=p_deposit_id;
    update public.deposit_release_requests set status='released',processed_at=coalesce(processed_at,now())
      where deposit_id=p_deposit_id and status in ('requested','approved','processing','reconciliation_required');
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'released',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.claim_held','deposit.dispute_hold') then
    if v_deposit.status<>'held_by_provider' then raise exception 'Only a provider-held deposit may be claim-held'; end if;
    update public.deposits set status='claim_hold' where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'claim_held',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.amount_applied','deposit.claim_applied') then
    select * into v_claim from public.deposit_claims where id=p_claim_id and deposit_id=p_deposit_id for update;
    if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise is null
      or p_amount_paise<=0 or p_amount_paise>v_claim.decision_amount_paise then
      raise exception 'Provider deposit application exceeds the approved, reasoned claim';
    end if;
    if not exists(select 1 from public.payment_provider_approvals x where x.provider_code=p_provider
      and x.enabled_for_deposits and x.supports_deposit_application and x.legal_approval_reference is not null) then
      raise exception 'Provider and legal permission for deposit application is not enabled';
    end if;
    update public.deposits set status='partially_applied' where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key,metadata)
      values(p_deposit_id,'amount_applied',p_amount_paise,p_provider_reference,v_ledger_key,jsonb_build_object('claim_id',p_claim_id))
      on conflict(idempotency_key) do nothing;
    update public.deposit_claims set status='closed' where id=p_claim_id;
  elsif p_event_type in ('deposit.failed','deposit.rejected') then
    update public.deposits set status=case when v_deposit.status='collection_pending' then 'failed'::public.deposit_status else 'reconciliation_required'::public.deposit_status end
      where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'failed',p_amount_paise,p_provider_reference,v_ledger_key) on conflict(idempotency_key) do nothing;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_deposit_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'deposit_status',(select status from public.deposits where id=p_deposit_id));
end;
$$;
revoke all on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid) from public,anon,authenticated;
grant execute on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid) to service_role;

create or replace function public.submit_deposit_claim(
  p_deposit_id uuid,p_amount_paise bigint,p_reason_code text,p_description text
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_deposit public.deposits%rowtype; v_booking public.bookings%rowtype; v_claim uuid;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if p_amount_paise<=0 or length(btrim(coalesce(p_reason_code,'')))<3
    or length(btrim(coalesce(p_description,'')))<20 then raise exception 'A reason, evidence description and requested amount are required'; end if;
  select * into v_deposit from public.deposits where id=p_deposit_id for update;
  if not found or not v_deposit.feature_enabled_at_creation or v_deposit.status not in ('held_by_provider','claim_hold') then
    raise exception 'No provider-confirmed deposit is available for a claim';
  end if;
  select * into v_booking from public.bookings where id=v_deposit.booking_id for update;
  if v_booking.owner_id<>v_actor or v_booking.status not in ('completed','disputed') then
    raise exception 'Only the lending owner may submit a post-return deposit claim';
  end if;
  if p_amount_paise>v_deposit.amount_paise then raise exception 'Claim cannot exceed the provider-confirmed deposit amount'; end if;
  if exists(select 1 from public.deposit_claims x where x.deposit_id=p_deposit_id and x.status not in ('rejected','closed')) then
    raise exception 'An active deposit claim already exists';
  end if;
  insert into public.deposit_claims(deposit_id,booking_id,claimant_id,against_user_id,amount_requested_paise,reason_code,description)
    values(p_deposit_id,v_booking.id,v_actor,v_booking.reader_id,p_amount_paise,left(p_reason_code,80),left(p_description,3000))
    returning id into v_claim;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(v_booking.id,v_actor,'deposit_claim_submitted',jsonb_build_object('claim_id',v_claim,'amount_paise',p_amount_paise),'deposit-claim:'||v_claim::text);
  insert into public.notifications(user_id,channel,template_key,payload)
    values(v_booking.reader_id,'in_app','deposit.claim_submitted',jsonb_build_object('booking_id',v_booking.id,'claim_id',v_claim));
  return v_claim;
end;
$$;
revoke all on function public.submit_deposit_claim(uuid,bigint,text,text) from public,anon;
grant execute on function public.submit_deposit_claim(uuid,bigint,text,text) to authenticated;

create or replace function public.decide_deposit_claim(
  p_claim_id uuid,p_decision text,p_amount_paise bigint,p_reason text
) returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.deposit_claims%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance reviewer permission required'; end if;
  if p_decision not in ('approve','reject') or length(btrim(coalesce(p_reason,'')))<10 then
    raise exception 'Select a valid decision and provide a reason';
  end if;
  select * into v_claim from public.deposit_claims where id=p_claim_id for update;
  if not found or v_claim.status not in ('submitted','under_review','needs_response') then raise exception 'Deposit claim is not reviewable'; end if;
  if p_decision='approve' then
    if p_amount_paise is null or p_amount_paise<=0 or p_amount_paise>v_claim.amount_requested_paise then
      raise exception 'Approved amount must be positive and no greater than the requested claim';
    end if;
    update public.deposit_claims set status='approved',decision_amount_paise=p_amount_paise,
      decision_reason=left(p_reason,2000),decided_by=v_actor,decided_at=now() where id=p_claim_id;
  else
    if p_amount_paise not in (0,null) then raise exception 'A rejected claim cannot apply an amount'; end if;
    update public.deposit_claims set status='rejected',decision_amount_paise=0,
      decision_reason=left(p_reason,2000),decided_by=v_actor,decided_at=now() where id=p_claim_id;
  end if;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(v_claim.booking_id,v_actor,'deposit_claim_decided',
      jsonb_build_object('claim_id',p_claim_id,'decision',p_decision,'amount_paise',coalesce(p_amount_paise,0),'reason',left(p_reason,2000)),
      'deposit-claim-decision:'||p_claim_id::text);
end;
$$;
revoke all on function public.decide_deposit_claim(uuid,text,bigint,text) from public,anon;
grant execute on function public.decide_deposit_claim(uuid,text,bigint,text) to authenticated;

create or replace function public.request_deposit_claim_application(p_claim_id uuid,p_idempotency_key text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.deposit_claims%rowtype; v_deposit public.deposits%rowtype; v_request uuid; v_provider public.payment_provider_approvals%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance reviewer permission required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 then raise exception 'Idempotency key required'; end if;
  select id into v_request from public.outbox_events where idempotency_key='deposit-claim-application:'||p_idempotency_key;
  if v_request is not null then return v_request; end if;
  select * into v_claim from public.deposit_claims where id=p_claim_id for update;
  if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise is null or v_claim.decision_amount_paise<=0 then
    raise exception 'A reasoned, approved positive claim is required';
  end if;
  select * into v_deposit from public.deposits where id=v_claim.deposit_id for update;
  if v_deposit.status not in ('held_by_provider','claim_hold') then raise exception 'Deposit is not in an eligible provider state'; end if;
  select * into v_provider from public.payment_provider_approvals where provider_code=v_deposit.provider
    and enabled_for_deposits and supports_deposit_application and supports_deposit_dispute_hold
    and legal_approval_reference is not null and (expires_at is null or expires_at>now());
  if not found then raise exception 'Provider and legal approval for deposit application is not active'; end if;
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('deposit',v_deposit.id,'deposit_claim_application_requested',
      jsonb_build_object('deposit_id',v_deposit.id,'claim_id',p_claim_id,'amount_paise',v_claim.decision_amount_paise),
      'deposit-claim-application:'||p_idempotency_key)
    returning id into v_request;
  update public.deposits set status='claim_hold_pending' where id=v_deposit.id;
  insert into public.deposit_ledger(deposit_id,event_type,amount_paise,idempotency_key,metadata)
    values(v_deposit.id,'claim_hold_requested',v_claim.decision_amount_paise,'deposit-claim-hold:'||p_idempotency_key,
      jsonb_build_object('claim_id',p_claim_id));
  return v_request;
end;
$$;
revoke all on function public.request_deposit_claim_application(uuid,text) from public,anon;
grant execute on function public.request_deposit_claim_application(uuid,text) to authenticated;

-- Reconciliation payloads are provider-derived, inserted by a trusted adapter.
-- They are evidence for the finance queue, not an automatic cash adjustment.
create or replace function public.record_provider_reconciliation(
  p_provider text,p_report_reference text,p_period_start timestamptz,p_period_end timestamptz,p_records jsonb
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_run uuid; v_record jsonb; v_type text; v_internal text; v_provider_ref text;
  v_expected bigint; v_actual bigint; v_currency char(3); v_status text; v_matched integer:=0; v_unmatched integer:=0;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_period_end<=p_period_start or jsonb_typeof(p_records)<>'array' or jsonb_array_length(p_records)>10000 then
    raise exception 'Invalid provider reconciliation period or records';
  end if;
  if not exists(select 1 from public.payment_provider_approvals where provider_code=p_provider
    and supports_reconciliation and (expires_at is null or expires_at>now())) then
    raise exception 'Provider reconciliation is not approved';
  end if;
  insert into public.payment_reconciliation_runs(provider,report_reference,period_start,period_end,status)
    values(p_provider,left(p_report_reference,200),p_period_start,p_period_end,'started') returning id into v_run;
  for v_record in select value from jsonb_array_elements(p_records) loop
    v_type:=v_record->>'recordType';
    v_internal:=nullif(v_record->>'internalReference','');
    v_provider_ref:=nullif(v_record->>'providerReference','');
    v_expected:=nullif(v_record->>'expectedAmountPaise','')::bigint;
    v_actual:=nullif(v_record->>'amountPaise','')::bigint;
    v_currency:=coalesce(v_record->>'currency','INR')::char(3);
    v_status:=nullif(v_record->>'status','');
    if v_type not in ('payment','refund','payout','deposit','chargeback','settlement') or v_currency<>'INR' then
      raise exception 'Unsupported reconciliation record type or currency';
    end if;
    if v_type='payment' and v_provider_ref is not null then
      select p.id::text,p.amount_paise into v_internal,v_expected from public.payments p
        where p.provider=p_provider and (p.provider_payment_id=v_provider_ref or p.merchant_reference=v_provider_ref) limit 1;
    elsif v_type='refund' and v_provider_ref is not null then
      select r.id::text,r.amount_paise into v_internal,v_expected from public.refunds r
        where r.provider=p_provider and r.provider_refund_id=v_provider_ref limit 1;
    elsif v_type='payout' and v_provider_ref is not null then
      select t.id::text,t.amount_paise into v_internal,v_expected from public.payouts t
        where t.provider=p_provider and t.provider_transfer_id=v_provider_ref limit 1;
    elsif v_type='deposit' and v_provider_ref is not null then
      select d.id::text,d.amount_paise into v_internal,v_expected from public.deposits d
        where d.provider=p_provider and d.provider_reference=v_provider_ref limit 1;
    end if;
    insert into public.payment_reconciliation_items(run_id,record_type,internal_reference,provider_reference,
      expected_amount_paise,provider_amount_paise,currency,match_status,details)
    values(v_run,v_type,v_internal,v_provider_ref,v_expected,v_actual,v_currency,
      case when v_internal is null then 'missing_internal'
        when v_actual is null then 'missing_provider'
        when v_expected is distinct from v_actual then 'amount_mismatch'
        else 'manual_review' end,
      jsonb_build_object('provider_status',v_status,'source','provider_adapter'));
    if v_internal is not null and v_actual is not null and v_expected=v_actual then v_matched:=v_matched+1;
    else v_unmatched:=v_unmatched+1; end if;
  end loop;
  update public.payment_reconciliation_runs set matched_count=v_matched,unmatched_count=v_unmatched,
    status=case when v_unmatched=0 then 'completed' else 'partial' end,completed_at=now() where id=v_run;
  return v_run;
end;
$$;
revoke all on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) to service_role;

-- Persist the provider's external refund/transfer references without asserting
-- completion. Only apply_verified_* event RPCs can set terminal success states.
create or replace function public.attach_refund_provider_reference(p_refund_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.refunds set provider_refund_id=p_provider_reference,status='pending'
    where id=p_refund_id and status in ('requested','pending');
  if not found then raise exception 'Refund is not attachable'; end if;
end;
$$;
revoke all on function public.attach_refund_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_refund_provider_reference(uuid,text) to service_role;

create or replace function public.attach_payout_provider_reference(p_payout_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.payouts set provider_transfer_id=p_provider_reference,status='processing',initiated_at=coalesce(initiated_at,now())
    where id=p_payout_id and status in ('pending','processing');
  if not found then raise exception 'Payout is not attachable'; end if;
end;
$$;
revoke all on function public.attach_payout_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_payout_provider_reference(uuid,text) to service_role;

create or replace function public.attach_deposit_provider_reference(p_deposit_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.deposits set provider_reference=p_provider_reference
    where id=p_deposit_id and feature_enabled_at_creation and status='collection_pending';
  if not found then raise exception 'Deposit collection is not attachable'; end if;
end;
$$;
revoke all on function public.attach_deposit_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_deposit_provider_reference(uuid,text) to service_role;

-- Deposit ledger rows cannot be edited/deleted after insertion.
create or replace function private.reject_deposit_ledger_mutation()
returns trigger language plpgsql set search_path = pg_catalog
as $$ begin raise exception 'Deposit ledger is append-only'; end; $$;
drop trigger if exists deposit_ledger_append_only on public.deposit_ledger;
create trigger deposit_ledger_append_only before update or delete on public.deposit_ledger
for each row execute function private.reject_deposit_ledger_mutation();

-- A booking with no active provider-backed deposit must not show a deposit as
-- paid/held; a database row is only a workflow record, not proof of custody.
revoke all on public.payment_disputes,public.deposit_claims,public.payment_reconciliation_runs,
  public.payment_reconciliation_items from anon,authenticated;
alter table public.payment_disputes enable row level security;
alter table public.deposit_claims enable row level security;
alter table public.payment_reconciliation_runs enable row level security;
alter table public.payment_reconciliation_items enable row level security;

commit;

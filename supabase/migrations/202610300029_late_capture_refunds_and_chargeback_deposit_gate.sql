begin;

-- Chargebacks block provider deposit release even if the rental dispute itself is closed.
create or replace function public.get_my_deposit_positions()
returns table(deposit_id uuid,booking_id uuid,status public.deposit_status,amount_paise bigint,
  locked_paise bigint,available_for_release_paise bigint,currency char(3),provider_reference text)
language sql stable security definer
set search_path=pg_catalog,public
as $$
  select d.id,d.booking_id,d.status,d.amount_paise,
    case when d.provider_reference is not null and d.status in ('held_by_provider','claim_hold_pending','claim_hold','release_pending','refund_pending','partially_applied')
      then greatest(d.amount_paise-coalesce((select sum(l.amount_paise) from public.deposit_ledger l
        where l.deposit_id=d.id and l.event_type in ('released','amount_applied')),0),0)::bigint
      else 0::bigint end,
    case when d.provider_reference is not null and d.status in ('held_by_provider','partially_applied','claim_hold') and b.status='completed'
      and exists(select 1 from public.booking_workflow_configuration c where c.id=true
        and c.deposit_claim_window_seconds is not null
        and b.completed_at+make_interval(secs=>c.deposit_claim_window_seconds)<=now())
      and not exists(select 1 from public.disputes x where x.booking_id=b.id and x.status<>'closed')
      and not exists(select 1 from public.payment_disputes x where x.booking_id=b.id and x.status not in ('won','closed'))
      and not exists(select 1 from public.deposit_claims x where x.deposit_id=d.id and x.status not in ('rejected','closed'))
      and not exists(select 1 from public.bookings active
        where (active.reader_id=d.payer_id or active.owner_id=d.payer_id)
          and active.status::text in ('owner_accepted','payment_pending','confirmed','collection_pending','active','return_pending','disputed'))
      then greatest(d.amount_paise-coalesce((select sum(l.amount_paise) from public.deposit_ledger l
        where l.deposit_id=d.id and l.event_type in ('released','amount_applied')),0),0)::bigint
      else 0::bigint end,
    d.currency,d.provider_reference
  from public.deposits d join public.bookings b on b.id=d.booking_id
  where d.payer_id=auth.uid()
  order by d.created_at desc;
$$;
revoke all on function public.get_my_deposit_positions() from public,anon;
grant execute on function public.get_my_deposit_positions() to authenticated;

create or replace function public.request_deposit_release(p_deposit_id uuid,p_idempotency_key text)
returns uuid language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_user uuid:=auth.uid(); v_deposit public.deposits%rowtype; v_booking public.bookings%rowtype;
  v_request uuid; v_provider public.payment_provider_approvals%rowtype; v_released bigint; v_remaining bigint; v_window integer;
  v_existing public.deposit_release_requests%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 or length(p_idempotency_key)>128 then raise exception 'Valid idempotency key required'; end if;
  select * into v_deposit from public.deposits where id=p_deposit_id;
  if not found or v_deposit.payer_id<>v_user or not v_deposit.feature_enabled_at_creation
    or v_deposit.provider_reference is null then raise exception 'Provider-confirmed deposit not found'; end if;
  select * into v_booking from public.bookings where id=v_deposit.booking_id;
  if not found or v_user not in (v_booking.reader_id,v_booking.owner_id) then raise exception 'Deposit booking not found'; end if;
  perform private.lock_marketplace_members(v_booking.reader_id,v_booking.owner_id);
  select * into v_booking from public.bookings where id=v_deposit.booking_id for update;
  select * into v_deposit from public.deposits where id=p_deposit_id for update;
  if not found or v_deposit.payer_id<>v_user or not v_deposit.feature_enabled_at_creation
    or v_deposit.provider_reference is null then raise exception 'Provider-confirmed deposit not found'; end if;
  select * into v_existing from public.deposit_release_requests where idempotency_key=p_idempotency_key;
  if found then
    if v_existing.deposit_id<>v_deposit.id or v_existing.requested_by<>v_user then
      raise exception 'Deposit release idempotency key was already used for another request';
    end if;
    return v_existing.id;
  end if;
  if v_deposit.status not in ('held_by_provider','partially_applied','claim_hold') then raise exception 'Deposit is not releasable'; end if;
  select deposit_claim_window_seconds into v_window from public.booking_workflow_configuration where id=true and is_active;
  if v_booking.status<>'completed' or v_booking.completed_at is null or v_window is null
    or v_booking.completed_at+make_interval(secs=>v_window)>now() then raise exception 'Return closure or approved claim window is incomplete'; end if;
  if exists(select 1 from public.disputes x where x.booking_id=v_booking.id and x.status<>'closed')
    or exists(select 1 from public.payment_disputes x where x.booking_id=v_booking.id and x.status not in ('won','closed'))
    or exists(select 1 from public.deposit_claims x where x.deposit_id=v_deposit.id and x.status not in ('rejected','closed')) then raise exception 'Open dispute or claim blocks release'; end if;
  if exists(select 1 from public.bookings x
    where (x.reader_id=v_user or x.owner_id=v_user)
      and (
        x.status::text in ('owner_accepted','payment_pending','confirmed','collection_pending','active','return_pending','disputed')
        or (x.status='requested' and exists(
          select 1 from public.copy_reservations r where r.booking_id=x.id and r.status='hold' and r.expires_at>now()
        ))
      )
  ) then raise exception 'Deposit release is blocked while this member has an active or pending rental'; end if;
  select p.* into v_provider from public.payment_provider_approvals p
    where p.provider_code=v_deposit.provider and p.enabled_for_deposits and p.supports_deposit_release
      and p.legal_approval_reference is not null and p.accounting_approval_reference is not null
      and (p.expires_at is null or p.expires_at>now());
  if not found then raise exception 'Approved provider deposit release is unavailable'; end if;
  select coalesce(sum(l.amount_paise),0) into v_released from public.deposit_ledger l
    where l.deposit_id=v_deposit.id and l.event_type in ('released','amount_applied');
  v_remaining:=greatest(v_deposit.amount_paise-v_released,0);
  if v_remaining<=0 then raise exception 'No provider-confirmed deposit funds remain'; end if;
  insert into public.deposit_release_requests(deposit_id,requested_by,amount_paise,idempotency_key)
    values(v_deposit.id,v_user,v_remaining,p_idempotency_key) returning id into v_request;
  update public.deposits set status='release_pending' where id=v_deposit.id;
  insert into public.deposit_ledger(deposit_id,event_type,amount_paise,idempotency_key,metadata)
    values(v_deposit.id,'release_requested',v_remaining,'deposit-release:'||p_idempotency_key,jsonb_build_object('request_id',v_request));
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('deposit',v_deposit.id,'deposit_release_requested',jsonb_build_object('request_id',v_request,'amount_paise',v_remaining),
      'deposit-release-outbox:'||p_idempotency_key) on conflict(idempotency_key) do nothing;
  return v_request;
end;
$$;
revoke all on function public.request_deposit_release(uuid,text) from public,anon;
grant execute on function public.request_deposit_release(uuid,text) to authenticated;

-- Late/duplicate captures after the inventory hold is lost create a finance-audited,
-- idempotent full refund request. No browser action or frontend status can create it.
create or replace function public.queue_captured_payment_refund(
  p_payment_id uuid,p_reason_code text,p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare
  v_payment public.payments%rowtype;
  v_refund uuid;
  v_prior bigint;
  v_remaining bigint;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then
    raise exception 'Trusted backend required';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 or length(p_idempotency_key)>180
    or length(btrim(coalesce(p_reason_code,'')))<4 then
    raise exception 'Refund idempotency key and reason are required';
  end if;
  select * into v_payment from public.payments where id=p_payment_id for update;
  if not found or v_payment.captured_at is null then
    raise exception 'Only a provider-captured payment may be automatically refunded';
  end if;
  select id into v_refund from public.refunds where idempotency_key=p_idempotency_key;
  if v_refund is not null then return v_refund; end if;
  select coalesce(sum(amount_paise),0) into v_prior from public.refunds
    where payment_id=p_payment_id and status in ('requested','pending','succeeded','reconciliation_required');
  v_remaining:=greatest(v_payment.amount_paise-v_prior,0);
  if v_remaining=0 then return null; end if;
  insert into public.refunds(booking_id,payment_id,requested_by,provider,idempotency_key,amount_paise,reason_code)
    values(v_payment.booking_id,p_payment_id,null,v_payment.provider,p_idempotency_key,v_remaining,left(p_reason_code,100))
    returning id into v_refund;
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('refund',v_refund,'refund_requested',
      jsonb_build_object('refund_id',v_refund,'payment_id',p_payment_id,'amount_paise',v_remaining,
        'provider',v_payment.provider,'reason_code',left(p_reason_code,100)),
      'refund-outbox:'||p_idempotency_key)
    on conflict(idempotency_key) do nothing;
  return v_refund;
end;
$$;
revoke all on function public.queue_captured_payment_refund(uuid,text,text) from public,anon,authenticated;
grant execute on function public.queue_captured_payment_refund(uuid,text,text) to service_role;

commit;

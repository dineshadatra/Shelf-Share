
begin;

create or replace function public.open_booking_dispute(
  p_booking_id uuid,p_reason_code text,p_description text
) returns uuid
language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare
  v_actor uuid:=auth.uid(); v_booking public.bookings%rowtype; v_id uuid;
  v_against uuid; v_policy text; v_deposit public.deposits%rowtype;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if length(btrim(coalesce(p_reason_code,'')))<3 or length(btrim(coalesce(p_reason_code,'')))>80
    or length(btrim(coalesce(p_description,'')))<20 then
    raise exception 'A dispute reason and a detailed description are required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_actor not in (v_booking.reader_id,v_booking.owner_id) then
    raise exception 'Only a booking participant may open a dispute'; end if;
  if v_booking.status not in ('confirmed','collection_pending','active','return_pending','completed','disputed') then
    raise exception 'This booking state is not eligible for a rental dispute'; end if;
  if exists(select 1 from public.disputes d where d.booking_id=p_booking_id and d.status<>'closed') then
    raise exception 'An open dispute already exists for this booking'; end if;
  v_against:=case when v_actor=v_booking.reader_id then v_booking.owner_id else v_booking.reader_id end;
  v_policy:=coalesce(v_booking.policy_snapshot->>'cancellation_policy_version','unconfigured');
  insert into public.disputes(booking_id,opened_by,against_user_id,reason_code,description,status,policy_version)
    values(p_booking_id,v_actor,v_against,left(p_reason_code,80),left(p_description,4000),'open',v_policy)
    returning id into v_id;
  update public.bookings set status='disputed' where id=p_booking_id;
  update public.owner_earnings set status='reconciliation_required'
    where booking_id=p_booking_id and status in ('pending','eligible','processing');
  insert into public.booking_audit_events(booking_id,actor_id,event_type,from_status,to_status,metadata,idempotency_key)
    values(p_booking_id,v_actor,'rental_dispute_opened',v_booking.status,'disputed',
      jsonb_build_object('dispute_id',v_id,'reason_code',p_reason_code),'rental-dispute:'||v_id::text);
  insert into public.notifications(user_id,channel,template_key,payload)
    values(v_against,'in_app','booking.dispute_opened',jsonb_build_object('booking_id',p_booking_id,'dispute_id',v_id));
  select * into v_deposit from public.deposits where booking_id=p_booking_id for update;
  if found and v_deposit.feature_enabled_at_creation and v_deposit.status='held_by_provider' then
    insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
      values('deposit',v_deposit.id,'deposit_dispute_hold_requested',
        jsonb_build_object('deposit_id',v_deposit.id,'booking_id',p_booking_id,'dispute_id',v_id,
          'amount_paise',v_deposit.amount_paise,'provider',v_deposit.provider),
        'deposit-dispute-hold:'||v_id::text) on conflict(idempotency_key) do nothing;
    update public.deposits set status='claim_hold_pending' where id=v_deposit.id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,idempotency_key,metadata)
      values(v_deposit.id,'claim_hold_requested',v_deposit.amount_paise,'deposit-dispute-hold-ledger:'||v_id::text,
        jsonb_build_object('dispute_id',v_id));
  end if;
  return v_id;
end;
$$;
revoke all on function public.open_booking_dispute(uuid,text,text) from public,anon;
grant execute on function public.open_booking_dispute(uuid,text,text) to authenticated;

create or replace function public.apply_verified_deposit_event(
  p_provider text,p_event_id text,p_deposit_id uuid,p_event_type text,p_provider_reference text,
  p_amount_paise bigint,p_currency char(3),p_payload_sha256 text,p_claim_id uuid default null
) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_deposit public.deposits%rowtype; v_claim public.deposit_claims%rowtype; v_count bigint; v_inserted bigint; v_key text;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_event_id is null or p_provider_reference is null or length(p_provider_reference)<3
    or p_payload_sha256 is null or p_payload_sha256 !~ '^[a-f0-9]{64}
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256,provider_payment_reference)
    values(null,p_provider,p_event_id,p_event_type,true,p_payload_sha256,p_provider_reference) on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_inserted=row_count;
  if v_inserted=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_deposit from public.deposits where id=p_deposit_id and provider=p_provider for update;
  if not found or v_deposit.amount_paise<>p_amount_paise or p_currency<>'INR'
    or (v_deposit.provider_reference is not null and p_provider_reference is not null and v_deposit.provider_reference<>p_provider_reference) then
    update public.payment_events set processing_status='dead_letter',processing_error_code='deposit_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','deposit_reference_or_amount_mismatch');
  end if;
  v_key:='deposit-provider-event:'||p_provider||':'||p_event_id;
  if p_event_type in ('deposit.held','deposit.collected','deposit.authorized') then
    if not v_deposit.feature_enabled_at_creation then raise exception 'Deposit feature was not approved when created'; end if;
    update public.deposits set status='held_by_provider',provider_reference=coalesce(provider_reference,p_provider_reference) where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'provider_held',p_amount_paise,p_provider_reference,v_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.released','deposit.refunded') then
    if v_deposit.status not in ('release_pending','refund_pending','held_by_provider','claim_hold','partially_applied') then raise exception 'Deposit is not releasable'; end if;
    select coalesce(sum(amount_paise),0) into v_count from public.deposit_ledger
      where deposit_id=p_deposit_id and event_type in ('released','amount_applied');
    if p_amount_paise<>greatest(v_deposit.amount_paise-v_count,0) then raise exception 'Provider release amount does not match remaining deposit'; end if;
    update public.deposits set status='released',provider_reference=coalesce(provider_reference,p_provider_reference) where id=p_deposit_id;
    update public.deposit_release_requests set status='released',processed_at=coalesce(processed_at,now())
      where deposit_id=p_deposit_id and status in ('requested','approved','processing','reconciliation_required');
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'released',p_amount_paise,p_provider_reference,v_key) on conflict(idempotency_key) do nothing;
  elsif p_event_type='deposit.dispute_hold' then
    if v_deposit.status not in ('held_by_provider','claim_hold_pending') or p_amount_paise<>v_deposit.amount_paise then
      raise exception 'Dispute hold must cover the exact provider-confirmed deposit amount'; end if;
    if not exists(select 1 from public.disputes d where d.booking_id=v_deposit.booking_id and d.status<>'closed') then
      raise exception 'An open rental dispute is required before provider deposit hold'; end if;
    if not exists(select 1 from public.payment_provider_approvals a where a.provider_code=p_provider
      and a.enabled_for_deposits and a.supports_deposit_dispute_hold and a.legal_approval_reference is not null) then
      raise exception 'Provider and legal approval for deposit dispute holds is not active'; end if;
    update public.deposits set status='claim_hold' where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key,metadata)
      values(p_deposit_id,'claim_held',p_amount_paise,p_provider_reference,v_key,
        jsonb_build_object('hold_reason','rental_dispute')) on conflict(idempotency_key) do nothing;
  elsif p_event_type='deposit.claim_held' then
    if v_deposit.status not in ('held_by_provider','claim_hold_pending') then raise exception 'Deposit cannot be claim-held'; end if;
    select * into v_claim from public.deposit_claims where id=p_claim_id and deposit_id=p_deposit_id for update;
    if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise<>p_amount_paise then raise exception 'Claim hold must match approved amount'; end if;
    update public.deposits set status='claim_hold' where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key,metadata)
      values(p_deposit_id,'claim_held',p_amount_paise,p_provider_reference,v_key,
        jsonb_build_object('claim_id',p_claim_id)) on conflict(idempotency_key) do nothing;
  elsif p_event_type in ('deposit.amount_applied','deposit.claim_applied') then
    select * into v_claim from public.deposit_claims where id=p_claim_id and deposit_id=p_deposit_id for update;
    if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise is null
      or p_amount_paise<=0 or p_amount_paise>v_claim.decision_amount_paise then raise exception 'Deposit application exceeds the approved claim'; end if;
    if not exists(select 1 from public.payment_provider_approvals x where x.provider_code=p_provider
      and x.enabled_for_deposits and x.supports_deposit_application and x.legal_approval_reference is not null) then
      raise exception 'Provider/legal permission for deposit application is not active'; end if;
    select coalesce(sum(amount_paise),0)+p_amount_paise into v_count from public.deposit_ledger
      where deposit_id=p_deposit_id and event_type in ('released','amount_applied');
    update public.deposits set status=case when v_count>=v_deposit.amount_paise then 'released'::public.deposit_status
      else 'partially_applied'::public.deposit_status end where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key,metadata)
      values(p_deposit_id,'amount_applied',p_amount_paise,p_provider_reference,v_key,jsonb_build_object('claim_id',p_claim_id))
      on conflict(idempotency_key) do nothing;
    update public.deposit_claims set status='closed' where id=p_claim_id;
  elsif p_event_type in ('deposit.failed','deposit.rejected') then
    update public.deposits set status=case when v_deposit.status='collection_pending' then 'failed'::public.deposit_status
      else 'reconciliation_required'::public.deposit_status end where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'failed',p_amount_paise,p_provider_reference,v_key) on conflict(idempotency_key) do nothing;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_deposit_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  update public.payment_events set processing_status='processed',processed_at=now() where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'deposit_status',(select status from public.deposits where id=p_deposit_id));
end;
$$;
revoke all on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid)
  from public,anon,authenticated;
grant execute on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid)
  to service_role;

commit;

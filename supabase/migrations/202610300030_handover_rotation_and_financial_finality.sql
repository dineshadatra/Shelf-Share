begin;

-- Handover QR rotation is allowed only before a counterparty consumes the token.
-- Collection sessions can be reissued from COLLECTION_PENDING after a previous
-- short-lived token expires; payment still requires provider-captured status.
create or replace function public.create_handover_session_secure(
  p_booking_id uuid,p_handover_type text,p_actor_id uuid,p_qr_token_hash text,p_otp_hash text,p_expires_at timestamptz
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_booking public.bookings%rowtype; v_item public.rental_items%rowtype; v_location public.handover_locations%rowtype; v_session uuid;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_handover_type not in ('collection','return') or p_qr_token_hash !~ '^[a-f0-9]{64}$'
    or p_otp_hash !~ '^[a-f0-9]{64}$' or p_expires_at<=now() or p_expires_at>now()+interval '15 minutes' then
    raise exception 'Invalid one-time handover token or expiry'; end if;
  select * into v_booking from public.bookings where id=p_booking_id;
  if not found or p_actor_id not in (v_booking.reader_id,v_booking.owner_id) then raise exception 'Booking participant required'; end if;
  perform private.lock_marketplace_members(v_booking.reader_id,v_booking.owner_id);
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or p_actor_id not in (v_booking.reader_id,v_booking.owner_id) then raise exception 'Booking participant required'; end if;
  if p_handover_type='collection' then
    if v_booking.status not in ('confirmed','collection_pending')
      or not exists(select 1 from public.payments p where p.booking_id=p_booking_id and p.status='captured') then
      raise exception 'Collection requires provider-confirmed payment'; end if;
  else
    if v_booking.status not in ('active','return_pending') then raise exception 'Return is not ready for handover'; end if;
  end if;
  select * into v_item from public.rental_items where booking_id=p_booking_id limit 1;
  select * into v_location from public.handover_locations where id=v_item.handover_location_id and status='active' and city_id=v_booking.city_id;
  if not found then raise exception 'Approved public handover location is unavailable'; end if;
  if exists(select 1 from public.handover_sessions s where s.booking_id=p_booking_id and s.handover_type=p_handover_type
    and s.status in ('created','awaiting_counterparty') and s.expires_at>now() and s.initiator_id<>p_actor_id) then
    raise exception 'The other participant already has an active QR session'; end if;
  if exists(select 1 from public.handover_sessions s where s.booking_id=p_booking_id and s.handover_type=p_handover_type
    and s.status in ('created','awaiting_counterparty') and s.expires_at>now()
    and s.initiator_id=p_actor_id and s.qr_consumed_at is not null) then
    raise exception 'This QR was already consumed; complete your side confirmation instead of rotating it'; end if;
  update public.handover_sessions s set status='cancelled'
    where s.booking_id=p_booking_id and s.handover_type=p_handover_type
      and s.status in ('created','awaiting_counterparty') and s.expires_at>now()
      and s.initiator_id=p_actor_id and s.qr_consumed_at is null;
  insert into public.handover_sessions(booking_id,rental_item_id,handover_type,handover_location_id,initiator_id,
    qr_token_hash,otp_hash,expires_at,status)
  values(p_booking_id,v_item.id,p_handover_type,v_location.id,p_actor_id,p_qr_token_hash,p_otp_hash,p_expires_at,'created')
  returning id into v_session;
  insert into public.handover_events(handover_session_id,actor_id,event_type,event_payload)
    values(v_session,p_actor_id,'session_created',jsonb_build_object('type',p_handover_type,'expires_at',p_expires_at));
  update public.bookings set status=case when p_handover_type='collection' then 'collection_pending' else 'return_pending' end
    where id=p_booking_id;
  return v_session;
end;
$$;
revoke all on function public.create_handover_session_secure(uuid,text,uuid,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.create_handover_session_secure(uuid,text,uuid,text,text,timestamptz) to service_role;

-- Tax must be final before payment intent creation and cannot be mutated after
-- a provider attempt is recorded. Settlement components must be fully specified.
create or replace function public.record_booking_tax_calculation(
  p_actor_id uuid,p_booking_id uuid,p_tax_paise bigint,p_policy_version text,p_calculation_reference text
) returns void language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_booking public.bookings%rowtype; v_cfg public.booking_workflow_configuration%rowtype;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' and not exists(
    select 1 from public.user_roles r where r.user_id=p_actor_id and r.revoked_at is null and r.role in ('finance_operator','admin','super_admin')
  ) then raise exception 'Finance permission required'; end if;
  if p_tax_paise is null or p_tax_paise<0 or length(btrim(coalesce(p_policy_version,'')))<3
    or length(btrim(coalesce(p_calculation_reference,'')))<5 then
    raise exception 'A versioned, approved tax calculation is required'; end if;
  select * into v_cfg from public.booking_workflow_configuration where id=true and is_active for update;
  if not found or v_cfg.tax_policy_version<>p_policy_version or v_cfg.tax_approval_reference is null then
    raise exception 'Tax policy is not approved or no longer current'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.status<>'owner_accepted'
    or exists(select 1 from public.payments p where p.booking_id=p_booking_id) then
    raise exception 'Tax must be finalised before payment initiation'; end if;
  -- Platform commission is withheld from Owner rent proceeds; it is not an additional Reader checkout line.
  update public.bookings set tax_paise=p_tax_paise,total_due_paise=rent_subtotal_paise+p_tax_paise,
    tax_calculated_at=now(),payment_policy_version=p_policy_version,
    policy_snapshot=policy_snapshot||jsonb_build_object('tax_policy_version',p_policy_version,'tax_calculation_reference',p_calculation_reference)
    where id=p_booking_id;
end;
$$;
revoke all on function public.record_booking_tax_calculation(uuid,uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.record_booking_tax_calculation(uuid,uuid,bigint,text,text) to service_role;

create or replace function public.record_owner_settlement_calculation(
  p_actor_id uuid,p_earning_id uuid,p_tax_withheld_paise bigint,p_provider_fee_paise bigint,p_adjustment_paise bigint,
  p_net_payable_paise bigint,p_policy_version text
) returns void language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_earning public.owner_earnings%rowtype; v_expected bigint;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' and not exists(
    select 1 from public.user_roles r where r.user_id=p_actor_id and r.revoked_at is null and r.role in ('finance_operator','admin','super_admin')
  ) then raise exception 'Finance permission required'; end if;
  if p_tax_withheld_paise is null or p_provider_fee_paise is null or p_adjustment_paise is null
    or p_net_payable_paise is null or least(p_tax_withheld_paise,p_provider_fee_paise)<0
    or length(btrim(coalesce(p_policy_version,'')))<3 then
    raise exception 'A versioned settlement calculation is required'; end if;
  select * into v_earning from public.owner_earnings where id=p_earning_id for update;
  if not found or v_earning.status not in ('eligible','pending') then raise exception 'Owner earning is not eligible for calculation'; end if;
  v_expected:=v_earning.gross_rent_paise-v_earning.commission_paise-p_tax_withheld_paise-p_provider_fee_paise+p_adjustment_paise;
  if v_expected<0 or p_net_payable_paise<>v_expected then raise exception 'Settlement calculation does not balance to the approved components'; end if;
  update public.owner_earnings set tax_withheld_paise=p_tax_withheld_paise,provider_fee_paise=p_provider_fee_paise,
    adjustment_paise=p_adjustment_paise,net_payable_paise=p_net_payable_paise,
    settlement_calculated_at=now(),settlement_policy_version=p_policy_version,settlement_approved_by=p_actor_id,status='eligible'
    where id=p_earning_id;
end;
$$;
revoke all on function public.record_owner_settlement_calculation(uuid,uuid,bigint,bigint,bigint,bigint,text) from public,anon,authenticated;
grant execute on function public.record_owner_settlement_calculation(uuid,uuid,bigint,bigint,bigint,bigint,text) to service_role;

commit;

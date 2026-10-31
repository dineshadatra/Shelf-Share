begin;

-- Shared participant locks serialize new requests/acceptance, return completion,
-- dispute creation, owner settlement and deposit release without a pooled wallet.
create or replace function private.lock_marketplace_members(p_user_a uuid,p_user_b uuid)
returns void language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_locked integer;
begin
  if p_user_a is null or p_user_b is null or p_user_a=p_user_b then
    raise exception 'Two distinct marketplace participants are required';
  end if;
  perform p.id from public.profiles p
    where p.id in (p_user_a,p_user_b)
    order by p.id
    for update;
  get diagnostics v_locked=row_count;
  if v_locked<>2 then raise exception 'Both marketplace participant profiles are required'; end if;
end;
$$;
revoke all on function private.lock_marketplace_members(uuid,uuid) from public,anon,authenticated;

create or replace function public.request_book_booking(
  p_copy_id uuid,p_handover_location_id uuid,p_start_at timestamptz,p_end_at timestamptz,
  p_duration_days integer,p_message text,p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare
  v_reader uuid:=auth.uid(); v_copy public.book_copies%rowtype; v_price public.book_pricing%rowtype;
  v_cfg public.booking_workflow_configuration%rowtype; v_booking uuid; v_item uuid; v_existing uuid;
  v_rent bigint; v_commission bigint; v_reserved tstzrange; v_expiry timestamptz; v_city_day_count integer;
begin
  if v_reader is null then raise exception 'Authentication required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 or length(p_idempotency_key)>128 then
    raise exception 'A valid booking idempotency key is required'; end if;
  select id into v_existing from public.bookings where reader_id=v_reader and request_idempotency_key=p_idempotency_key;
  if v_existing is not null then return v_existing; end if;
  if p_start_at is null or p_end_at is null or p_start_at<=now() or p_end_at<=p_start_at then raise exception 'Choose a valid future rental interval'; end if;
  if p_duration_days not in (3,7,15,30) and not(p_duration_days between 1 and 90) then raise exception 'Rental duration is unsupported'; end if;
  select * into v_cfg from public.booking_workflow_configuration where id=true and is_active;
  if not found or v_cfg.request_hold_seconds is null or v_cfg.rental_duration_mode is null then
    raise exception 'Approved booking timing, hold and duration policy is not configured'; end if;
  if v_cfg.rental_duration_mode='elapsed_24h' then
    if abs(extract(epoch from (p_end_at-p_start_at))-p_duration_days*86400)>1 then
      raise exception 'The selected dates do not match the rental duration'; end if;
  else
    v_city_day_count:=(p_end_at at time zone 'Asia/Kolkata')::date-(p_start_at at time zone 'Asia/Kolkata')::date;
    if v_city_day_count<>p_duration_days or (p_start_at at time zone 'Asia/Kolkata')::time<>'00:00:00'
      or (p_end_at at time zone 'Asia/Kolkata')::time<>'00:00:00' then
      raise exception 'Choose whole local calendar days matching the rental duration'; end if;
  end if;
  select * into v_copy from public.book_copies where id=p_copy_id;
  if not found then raise exception 'This physical copy was not found'; end if;
  perform private.lock_marketplace_members(v_reader,v_copy.owner_id);
  select * into v_copy from public.book_copies where id=p_copy_id for update;
  if not found or v_copy.listing_status<>'approved' or not v_copy.is_available_for_rent then
    raise exception 'This physical copy is not available for booking'; end if;
  if v_copy.owner_id=v_reader then raise exception 'You cannot book your own copy'; end if;
  perform private.assert_booking_request_identity(v_reader,v_copy,p_handover_location_id);
  select * into v_price from public.book_pricing where book_copy_id=p_copy_id
    and effective_from<=now() and (effective_until is null or effective_until>now())
    order by effective_from desc limit 1;
  if not found then raise exception 'No active rental price is configured'; end if;
  if p_duration_days=3 then v_rent:=v_price.rental_3d_paise;
  elsif p_duration_days=7 then v_rent:=v_price.rental_7d_paise;
  elsif p_duration_days=15 then v_rent:=v_price.rental_15d_paise;
  elsif p_duration_days=30 then v_rent:=v_price.rental_30d_paise;
  else
    if v_price.custom_daily_paise is null or v_price.min_custom_days is null
      or p_duration_days<v_price.min_custom_days or p_duration_days>v_price.max_custom_days then
      raise exception 'Custom rental duration is not enabled for this copy'; end if;
    v_rent:=v_price.custom_daily_paise*p_duration_days;
  end if;
  if v_rent is null or v_rent<=0 then raise exception 'The selected rental price is not configured'; end if;
  v_commission:=floor(v_rent::numeric*0.10+0.5)::bigint;
  v_reserved:=tstzrange(p_start_at-v_cfg.buffer_before,p_end_at+v_cfg.buffer_after,'[)');
  update public.copy_reservations set status='expired'
    where book_copy_id=p_copy_id and status='hold' and expires_at is not null and expires_at<=now();
  if exists(select 1 from public.book_availability_blocks b where b.book_copy_id=p_copy_id and b.blocked_period&&v_reserved)
    or exists(select 1 from public.copy_reservations r where r.book_copy_id=p_copy_id and r.status in ('hold','confirmed','in_use')
      and r.reserved_period&&v_reserved and (r.status<>'hold' or r.expires_at is null or r.expires_at>now())) then
    raise exception 'This copy is unavailable for the selected dates'; end if;
  v_expiry:=now()+make_interval(secs=>v_cfg.request_hold_seconds);
  insert into public.bookings(
    booking_number,reader_id,owner_id,city_id,status,requested_start_at,requested_end_at,policy_snapshot,
    rent_subtotal_paise,platform_fee_paise,tax_paise,deposit_required_paise,total_due_paise,
    requested_copy_id,requested_handover_location_id,requested_duration_days,request_idempotency_key,
    request_message,commission_policy_version
  ) values(
    'SS-'||upper(substr(encode(extensions.gen_random_bytes(8),'hex'),1,12)),
    v_reader,v_copy.owner_id,v_copy.city_id,'requested',p_start_at,p_end_at,
    jsonb_build_object('pricing',to_jsonb(v_price),'rent_paise',v_rent,'commission_rate_bps',1000,
      'commission_paise',v_commission,'commission_policy_version','commission_10pct_v1',
      'deposit_status','blocked_until_provider_legal_approval','tax_status','pending_approved_calculation'),
    v_rent,v_commission,0,0,v_rent,p_copy_id,p_handover_location_id,p_duration_days,p_idempotency_key,
    left(nullif(btrim(p_message),''),500),'commission_10pct_v1'
  ) returning id into v_booking;
  insert into public.rental_items(booking_id,book_copy_id,city_id,pricing_snapshot,rental_fee_paise,
    buffer_before,buffer_after,reserved_period,duration_days,handover_location_id)
  values(v_booking,p_copy_id,v_copy.city_id,to_jsonb(v_price),v_rent,v_cfg.buffer_before,v_cfg.buffer_after,
    v_reserved,p_duration_days,p_handover_location_id) returning id into v_item;
  insert into public.copy_reservations(rental_item_id,booking_id,book_copy_id,reserved_period,status,expires_at)
  values(v_item,v_booking,p_copy_id,v_reserved,'hold',v_expiry);
  insert into public.booking_audit_events(booking_id,actor_id,event_type,to_status,metadata,idempotency_key)
  values(v_booking,v_reader,'booking_requested','requested',
    jsonb_build_object('copy_id',p_copy_id,'duration_days',p_duration_days,'rent_paise',v_rent,
      'commission_paise',v_commission,'request_hold_expires_at',v_expiry),
    'booking-request:'||p_idempotency_key);
  insert into public.notifications(user_id,channel,template_key,payload)
  values(v_copy.owner_id,'in_app','booking.requested',
    jsonb_build_object('booking_id',v_booking,'copy_id',p_copy_id,'start_at',p_start_at,'end_at',p_end_at));
  return v_booking;
exception when exclusion_violation then
  raise exception 'This physical copy was reserved by another booking request';
end;
$$;
revoke all on function public.request_book_booking(uuid,uuid,timestamptz,timestamptz,integer,text,text) from public,anon;
grant execute on function public.request_book_booking(uuid,uuid,timestamptz,timestamptz,integer,text,text) to authenticated;

create or replace function public.accept_book_booking_request(p_booking_id uuid)
returns void language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_actor uuid:=auth.uid(); v_booking public.bookings%rowtype; v_item public.rental_items%rowtype;
  v_copy public.book_copies%rowtype; v_reservation public.copy_reservations%rowtype; v_doc public.legal_documents%rowtype;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id;
  if not found or v_booking.owner_id<>v_actor then raise exception 'Booking request not found'; end if;
  perform private.lock_marketplace_members(v_booking.reader_id,v_booking.owner_id);
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.owner_id<>v_actor or v_booking.status<>'requested' then
    raise exception 'Booking request not found or no longer awaiting Owner action'; end if;
  select * into v_item from public.rental_items where booking_id=p_booking_id limit 1;
  select * into v_copy from public.book_copies where id=v_booking.requested_copy_id for update;
  if not found or v_copy.owner_id<>v_actor or v_copy.listing_status<>'approved' or not v_copy.is_available_for_rent then
    raise exception 'The physical copy is no longer eligible for booking'; end if;
  select * into v_reservation from public.copy_reservations where booking_id=p_booking_id for update;
  if not found or v_reservation.status<>'hold' or v_reservation.expires_at<=now() then
    update public.copy_reservations set status='expired' where booking_id=p_booking_id and status='hold';
    update public.bookings set status='expired',cancellation_reason_code='request_hold_expired' where id=p_booking_id;
    raise exception 'The booking request hold has expired'; end if;
  perform private.assert_booking_request_identity(v_booking.reader_id,v_copy,v_booking.requested_handover_location_id);
  if exists(select 1 from public.book_availability_blocks b where b.book_copy_id=v_copy.id and b.blocked_period&&v_item.reserved_period) then
    raise exception 'The requested interval is no longer available'; end if;
  select * into v_doc from public.legal_documents d where d.document_type='rental_agreement' and d.is_published
    and d.effective_from<=now() and (d.effective_until is null or d.effective_until>now())
    order by d.effective_from desc limit 1;
  if not found then raise exception 'Current legal-approved rental agreement is not published'; end if;
  insert into public.rental_agreements(booking_id,user_id,legal_document_id,document_version,document_sha256,accepted_at)
    values(p_booking_id,v_actor,v_doc.id,v_doc.version,v_doc.sha256,now())
    on conflict(booking_id,user_id,document_version) do nothing;
  update public.bookings set status='owner_accepted',accepted_at=now(),
    policy_snapshot=policy_snapshot||jsonb_build_object('rental_agreement_version',v_doc.version,'rental_agreement_sha256',v_doc.sha256)
    where id=p_booking_id;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,from_status,to_status,metadata,idempotency_key)
  values(p_booking_id,v_actor,'owner_accepted','requested','owner_accepted',
    jsonb_build_object('rental_agreement_version',v_doc.version),'booking-accepted:'||p_booking_id::text);
  insert into public.notifications(user_id,channel,template_key,payload)
  values(v_booking.reader_id,'in_app','booking.owner_accepted',jsonb_build_object('booking_id',p_booking_id));
end;
$$;
revoke all on function public.accept_book_booking_request(uuid) from public,anon;
grant execute on function public.accept_book_booking_request(uuid) to authenticated;

create or replace function private.complete_handover_if_ready(p_session_id uuid)
returns boolean language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_session public.handover_sessions%rowtype; v_booking public.bookings%rowtype;
  v_cfg public.booking_workflow_configuration%rowtype; v_owner_photos integer; v_reader_photos integer; v_due timestamptz;
begin
  select * into v_session from public.handover_sessions where id=p_session_id for update;
  if not found or v_session.status='completed' then return false; end if;
  if v_session.expires_at<=now() or v_session.qr_consumed_at is null or v_session.owner_confirmed_at is null
    or v_session.reader_confirmed_at is null or v_session.owner_condition_confirmed_at is null
    or v_session.reader_condition_confirmed_at is null then return false; end if;
  select * into v_booking from public.bookings where id=v_session.booking_id;
  if not found then return false; end if;
  perform private.lock_marketplace_members(v_booking.reader_id,v_booking.owner_id);
  select * into v_booking from public.bookings where id=v_session.booking_id for update;
  select count(*) filter(where submitted_by=v_booking.owner_id),count(*) filter(where submitted_by=v_booking.reader_id)
    into v_owner_photos,v_reader_photos from public.rental_condition_photos where handover_session_id=p_session_id;
  if v_owner_photos<1 or v_reader_photos<1 then return false; end if;
  if v_session.handover_type='collection' then
    select * into v_cfg from public.booking_workflow_configuration where id=true and is_active and rental_duration_mode is not null;
    if not found then raise exception 'Approved rental-day convention is required'; end if;
    if v_cfg.rental_duration_mode='elapsed_24h' then v_due:=now()+make_interval(days=>v_booking.requested_duration_days);
    else v_due:=(((now() at time zone 'Asia/Kolkata')::date+v_booking.requested_duration_days)::timestamp at time zone 'Asia/Kolkata'); end if;
    update public.bookings set status='active',rental_start_at=now(),rental_due_at=v_due where id=v_booking.id;
    update public.copy_reservations set status='in_use',expires_at=null where booking_id=v_booking.id;
    insert into public.owner_earnings(booking_id,owner_id,gross_rent_paise,commission_paise,tax_withheld_paise,provider_fee_paise,
      net_payable_paise,status,eligible_at)
    values(v_booking.id,v_booking.owner_id,v_booking.rent_subtotal_paise,v_booking.platform_fee_paise,0,0,
      greatest(v_booking.rent_subtotal_paise-v_booking.platform_fee_paise,0),'eligible',now())
    on conflict(booking_id) do nothing;
  else
    update public.bookings set status='completed',completed_at=now() where id=v_booking.id;
    update public.copy_reservations set status='released',expires_at=null where booking_id=v_booking.id and status='in_use';
  end if;
  update public.handover_sessions set status='completed',completed_at=now() where id=p_session_id;
  insert into public.handover_events(handover_session_id,event_type,event_payload)
    values(p_session_id,'handover_completed',jsonb_build_object('booking_id',v_booking.id,'type',v_session.handover_type));
  insert into public.booking_audit_events(booking_id,event_type,from_status,to_status,metadata,idempotency_key)
    values(v_booking.id,'handover_completed',v_booking.status,
      case when v_session.handover_type='collection' then 'active'::public.booking_status else 'completed'::public.booking_status end,
      jsonb_build_object('session_id',p_session_id,'owner_photo_count',v_owner_photos,'reader_photo_count',v_reader_photos),
      'handover-complete:'||p_session_id::text);
  return true;
end;
$$;
revoke all on function private.complete_handover_if_ready(uuid) from public,anon,authenticated;

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
  select * into v_booking from public.bookings where id=p_booking_id;
  if not found or v_actor not in (v_booking.reader_id,v_booking.owner_id) then
    raise exception 'Only a booking participant may open a dispute'; end if;
  perform private.lock_marketplace_members(v_booking.reader_id,v_booking.owner_id);
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_actor not in (v_booking.reader_id,v_booking.owner_id) then
    raise exception 'Only a booking participant may open a dispute'; end if;
  if v_booking.status not in ('confirmed','collection_pending','active','return_pending','completed','disputed') then
    raise exception 'This booking state is not eligible for a rental dispute'; end if;
  if exists(select 1 from public.disputes d where d.booking_id=p_booking_id and d.status<>'closed') then
    raise exception 'An open dispute already exists for this booking'; end if;
  v_against:=case when v_actor=v_booking.reader_id then v_booking.owner_id else v_booking.reader_id end;
  v_policy:=coalesce(v_booking.policy_snapshot->>'cancellation_policy_version','unconfigured');
  insert into public.disputes(booking_id,opened_by,against_user_id,reason_code,description,status,policy_version,booking_status_before_dispute)
    values(p_booking_id,v_actor,v_against,left(p_reason_code,80),left(p_description,4000),'open',v_policy,v_booking.status)
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

create or replace function public.create_owner_payout_request(p_earning_id uuid,p_provider text,p_idempotency_key text)
returns uuid language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_user uuid:=auth.uid(); v_earning public.owner_earnings%rowtype;
  v_approval public.payment_provider_approvals%rowtype; v_vendor public.provider_vendor_accounts%rowtype; v_payout uuid;
  v_booking public.bookings%rowtype; v_existing public.payouts%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 or length(p_idempotency_key)>128 then raise exception 'Payout idempotency key required'; end if;
  select * into v_existing from public.payouts where idempotency_key=p_idempotency_key;
  if found then
    if v_existing.owner_id<>v_user or v_existing.owner_earning_id<>p_earning_id or v_existing.provider<>p_provider then
      raise exception 'Payout idempotency key was already used for another request';
    end if;
    return v_existing.id;
  end if;
  select * into v_earning from public.owner_earnings where id=p_earning_id and owner_id=v_user;
  if not found then raise exception 'Owner earning not found'; end if;
  select * into v_booking from public.bookings where id=v_earning.booking_id;
  if not found or v_booking.owner_id<>v_user then raise exception 'Owner booking not found'; end if;
  perform private.lock_marketplace_members(v_booking.reader_id,v_booking.owner_id);
  select * into v_booking from public.bookings where id=v_earning.booking_id for update;
  select * into v_earning from public.owner_earnings where id=p_earning_id and owner_id=v_user for update;
  if not found or v_earning.status<>'eligible' or v_earning.settlement_calculated_at is null
    or v_earning.settlement_policy_version is null or v_earning.settlement_approved_by is null then
    raise exception 'Owner earning requires verified collection and an approved final settlement calculation'; end if;
  if exists(select 1 from public.disputes d where d.booking_id=v_booking.id and d.status<>'closed')
    or exists(select 1 from public.payment_disputes d where d.booking_id=v_booking.id and d.status not in ('won','closed')) then
    raise exception 'Open rental or payment dispute blocks owner settlement'; end if;
  select * into v_approval from public.payment_provider_approvals where provider_code=p_provider and enabled_for_rent
    and marketplace_model='peer_to_peer_physical_book_rental' and supports_vendor_onboarding and supports_split_settlement
    and supports_delayed_transfer and supports_reconciliation and legal_approval_reference is not null
    and accounting_approval_reference is not null and (expires_at is null or expires_at>now());
  if not found then raise exception 'Approved marketplace settlement provider is unavailable'; end if;
  select * into v_vendor from public.provider_vendor_accounts where provider_approval_id=v_approval.id
    and user_id=v_user and kyc_status='verified';
  if not found then raise exception 'Owner marketplace onboarding and KYC are not complete'; end if;
  if exists(select 1 from public.payment_disputes d where d.booking_id=v_earning.booking_id and d.status not in ('won','closed')) then
    raise exception 'Open payment dispute blocks owner settlement'; end if;
  if exists(select 1 from public.payouts p where p.owner_earning_id=p_earning_id
    and p.status in ('pending','eligible','processing','reconciliation_required')) then raise exception 'Settlement is already in progress'; end if;
  insert into public.payouts(owner_earning_id,owner_id,provider,idempotency_key,amount_paise,status)
    values(p_earning_id,v_user,p_provider,p_idempotency_key,v_earning.net_payable_paise,'pending') returning id into v_payout;
  update public.owner_earnings set status='processing' where id=p_earning_id;
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('payout',v_payout,'owner_payout_requested',
      jsonb_build_object('payout_id',v_payout,'provider',p_provider,'provider_vendor_reference',v_vendor.provider_vendor_reference),
      'owner-payout:'||p_idempotency_key) on conflict(idempotency_key) do nothing;
  return v_payout;
end;
$$;
revoke all on function public.create_owner_payout_request(uuid,text,text) from public,anon;
grant execute on function public.create_owner_payout_request(uuid,text,text) to authenticated;

commit;

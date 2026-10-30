begin;

-- Owner approval is explicit and precedes payment. The payment attempt is still
-- the only operation that creates a reservation hold.
alter type public.booking_status add value if not exists 'owner_accepted';

alter table public.bookings
  add column if not exists requested_copy_id uuid references public.book_copies(id) on delete restrict,
  add column if not exists requested_handover_location_id uuid references public.handover_locations(id) on delete restrict,
  add column if not exists requested_duration_days integer,
  add column if not exists request_idempotency_key text,
  add column if not exists accepted_at timestamptz,
  add column if not exists declined_at timestamptz,
  add column if not exists request_message text,
  add column if not exists payment_policy_version text,
  add column if not exists commission_policy_version text;
create unique index if not exists bookings_request_idempotency_uq
  on public.bookings(reader_id, request_idempotency_key)
  where request_idempotency_key is not null;
create index if not exists bookings_requested_copy_idx
  on public.bookings(requested_copy_id, status, requested_start_at);

alter table public.rental_items
  add column if not exists duration_days integer,
  add column if not exists handover_location_id uuid references public.handover_locations(id) on delete restrict;

alter table public.payments
  add column if not exists merchant_reference text,
  add column if not exists provider_status text,
  add column if not exists last_provider_event_at timestamptz;
create unique index if not exists payments_merchant_reference_uq
  on public.payments(merchant_reference) where merchant_reference is not null;

alter table public.payment_events
  add column if not exists payload_sha256 text,
  add column if not exists provider_payment_reference text;
alter table public.payment_events
  drop constraint if exists payment_events_payload_sha256_check;
alter table public.payment_events
  add constraint payment_events_payload_sha256_check
  check (payload_sha256 is null or payload_sha256 ~ '^[a-f0-9]{64}$');

alter table public.handover_sessions
  add column if not exists qr_consumed_at timestamptz,
  add column if not exists qr_consumed_by uuid references auth.users(id) on delete restrict,
  add column if not exists owner_confirmed_at timestamptz,
  add column if not exists reader_confirmed_at timestamptz,
  add column if not exists owner_condition_confirmed_at timestamptz,
  add column if not exists reader_condition_confirmed_at timestamptz,
  add column if not exists otp_attempts integer not null default 0 check (otp_attempts between 0 and 10),
  add column if not exists otp_locked_until timestamptz;
alter table public.rental_condition_photos
  add column if not exists handover_session_id uuid references public.handover_sessions(id) on delete restrict;

create table if not exists public.booking_workflow_configuration (
  id boolean primary key default true check (id),
  is_active boolean not null default false,
  buffer_before interval not null default interval '0',
  buffer_after interval not null default interval '0',
  payment_hold_seconds integer,
  handover_ttl_seconds integer not null default 300,
  rental_duration_mode text check (rental_duration_mode in ('elapsed_24h','calendar_day')),
  configuration_version text not null,
  tax_policy_version text,
  cancellation_policy_version text,
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  updated_at timestamptz not null default now(),
  check (buffer_before >= interval '0' and buffer_after >= interval '0'),
  check (payment_hold_seconds is null or payment_hold_seconds between 60 and 3600),
  check (handover_ttl_seconds between 60 and 900),
  check (not is_active or (approved_by is not null and approved_at is not null))
);
alter table public.booking_workflow_configuration enable row level security;

-- Written provider, legal and accounting approvals are separate gates. No row is
-- seeded here, so production collection, transfer and deposit custody stay OFF.
create table if not exists public.payment_provider_approvals (
  id uuid primary key default gen_random_uuid(),
  provider_code text not null,
  product_code text not null,
  marketplace_model text not null default 'peer_to_peer_physical_book_rental',
  enabled_for_rent boolean not null default false,
  enabled_for_deposits boolean not null default false,
  supports_vendor_onboarding boolean not null default false,
  supports_split_settlement boolean not null default false,
  supports_delayed_transfer boolean not null default false,
  supports_refunds boolean not null default false,
  supports_chargebacks boolean not null default false,
  supports_signed_webhooks boolean not null default false,
  supports_reconciliation boolean not null default false,
  supports_deposit_hold boolean not null default false,
  supports_deposit_release boolean not null default false,
  supports_deposit_dispute_hold boolean not null default false,
  supports_deposit_application boolean not null default false,
  marketplace_approval_reference text,
  provider_approval_reference text,
  legal_approval_reference text,
  accounting_approval_reference text,
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  check (not enabled_for_rent or (
    supports_vendor_onboarding and supports_split_settlement and supports_delayed_transfer
    and supports_refunds and supports_chargebacks and supports_signed_webhooks
    and supports_reconciliation and length(btrim(coalesce(provider_approval_reference,''))) >= 5
    and length(btrim(coalesce(marketplace_approval_reference,''))) >= 5
    and length(btrim(coalesce(legal_approval_reference,''))) >= 5
    and length(btrim(coalesce(accounting_approval_reference,''))) >= 5
    and approved_by is not null and approved_at is not null
  )),
  check (not enabled_for_deposits or (
    enabled_for_rent and supports_deposit_hold and supports_deposit_release
    and supports_deposit_dispute_hold and supports_deposit_application
  ))
);
create unique index if not exists payment_provider_one_enabled_rent_uq
  on public.payment_provider_approvals(enabled_for_rent) where enabled_for_rent;
create unique index if not exists payment_provider_one_enabled_deposit_uq
  on public.payment_provider_approvals(enabled_for_deposits) where enabled_for_deposits;
alter table public.payment_provider_approvals enable row level security;

create table if not exists public.provider_vendor_accounts (
  id uuid primary key default gen_random_uuid(),
  provider_approval_id uuid not null references public.payment_provider_approvals(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  provider_vendor_reference text not null,
  kyc_status text not null check (kyc_status in ('pending','verified','rejected','suspended')),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  unique (provider_approval_id, user_id),
  unique (provider_approval_id, provider_vendor_reference),
  check ((kyc_status <> 'verified') or verified_at is not null)
);
alter table public.provider_vendor_accounts enable row level security;

create table if not exists public.booking_audit_events (
  id bigint generated always as identity primary key,
  booking_id uuid not null references public.bookings(id) on delete restrict,
  actor_id uuid references auth.users(id) on delete restrict,
  event_type text not null,
  from_status public.booking_status,
  to_status public.booking_status,
  reason_code text,
  metadata jsonb not null default '{}'::jsonb,
  idempotency_key text not null unique,
  created_at timestamptz not null default now()
);
create index if not exists booking_audit_events_booking_idx
  on public.booking_audit_events(booking_id, created_at desc);

create table if not exists public.payment_disputes (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments(id) on delete restrict,
  booking_id uuid not null references public.bookings(id) on delete restrict,
  provider text not null,
  provider_dispute_reference text not null,
  amount_paise bigint not null check (amount_paise > 0),
  reason_code text not null,
  status text not null default 'open' check (status in ('open','evidence_due','under_review','won','lost','closed','reconciliation_required')),
  response_due_at timestamptz,
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  unique (provider, provider_dispute_reference)
);
alter table public.payment_disputes enable row level security;

create table if not exists public.deposit_claims (
  id uuid primary key default gen_random_uuid(),
  deposit_id uuid not null references public.deposits(id) on delete restrict,
  booking_id uuid not null references public.bookings(id) on delete restrict,
  claimant_id uuid not null references auth.users(id) on delete restrict,
  against_user_id uuid not null references auth.users(id) on delete restrict,
  amount_requested_paise bigint not null check (amount_requested_paise > 0),
  reason_code text not null,
  description text not null,
  status text not null default 'submitted' check (status in ('submitted','under_review','needs_response','approved','rejected','appealed','closed')),
  decision_amount_paise bigint check (decision_amount_paise is null or decision_amount_paise >= 0),
  decision_reason text,
  decided_by uuid references auth.users(id) on delete restrict,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  check (claimant_id <> against_user_id),
  check (decision_amount_paise is null or decision_amount_paise <= amount_requested_paise)
);
alter table public.deposit_claims enable row level security;

create table if not exists public.payment_reconciliation_runs (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  report_reference text,
  period_start timestamptz not null,
  period_end timestamptz not null,
  status text not null default 'started' check (status in ('started','completed','partial','failed')),
  matched_count integer not null default 0,
  unmatched_count integer not null default 0,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  check (period_end > period_start)
);
create table if not exists public.payment_reconciliation_items (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.payment_reconciliation_runs(id) on delete restrict,
  record_type text not null check (record_type in ('payment','refund','payout','deposit','chargeback','settlement')),
  internal_reference text,
  provider_reference text,
  expected_amount_paise bigint,
  provider_amount_paise bigint,
  currency char(3) not null default 'INR' check (currency = 'INR'),
  match_status text not null check (match_status in ('matched','amount_mismatch','missing_internal','missing_provider','status_mismatch','manual_review')),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.payment_reconciliation_runs enable row level security;
alter table public.payment_reconciliation_items enable row level security;

create table if not exists public.booking_incidents (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete restrict,
  reported_by uuid not null references auth.users(id) on delete restrict,
  incident_type text not null check (incident_type in ('owner_no_show','reader_no_show','venue_unavailable','safety_issue','other')),
  description text not null,
  status text not null default 'open' check (status in ('open','investigating','resolved','closed')),
  resolution_code text,
  resolved_by uuid references auth.users(id) on delete restrict,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.booking_incidents enable row level security;

-- There is deliberately no account-level deposit wallet. This view exposes only
-- provider-confirmed per-booking balances and never treats a DB row as custody.
create or replace view public.deposit_positions
with (security_invoker = true) as
select d.id as deposit_id, d.booking_id, d.payer_id, d.currency, d.status,
  case when d.status in ('held_by_provider','claim_hold_pending','claim_hold','release_pending','refund_pending','partially_applied')
       then greatest(d.amount_paise - coalesce((
         select sum(case when dl.event_type in ('released','amount_applied') then dl.amount_paise else 0 end)
         from public.deposit_ledger dl where dl.deposit_id=d.id
       ),0),0) else 0 end::bigint as locked_paise,
  case when d.status='held_by_provider'
       and b.status='completed'
       and not exists (select 1 from public.disputes x where x.booking_id=b.id and x.status<>'closed')
       and not exists (select 1 from public.deposit_claims x where x.deposit_id=d.id and x.status not in ('rejected','closed'))
       and not exists (
         select 1 from public.bookings active
         where (active.reader_id=d.payer_id or active.owner_id=d.payer_id)
           and active.status in ('owner_accepted','payment_pending','confirmed','collection_pending','active','return_pending','disputed')
       )
       then greatest(d.amount_paise - coalesce((
         select sum(case when dl.event_type in ('released','amount_applied') then dl.amount_paise else 0 end)
         from public.deposit_ledger dl where dl.deposit_id=d.id
       ),0),0) else 0 end::bigint as available_for_release_paise
from public.deposits d join public.bookings b on b.id=d.booking_id;

-- Append-only audit controls.
create or replace function private.reject_booking_financial_audit_mutation()
returns trigger language plpgsql set search_path = pg_catalog, public
as $$ begin raise exception 'Financial and workflow audit records are append-only'; end; $$;
create trigger booking_audit_append_only before update or delete on public.booking_audit_events
for each row execute function private.reject_booking_financial_audit_mutation();

create or replace function private.assert_booking_request_identity(
  p_reader uuid, p_copy public.book_copies, p_location uuid
) returns void language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_reader public.profiles%rowtype; v_owner public.profiles%rowtype; v_verification public.user_verifications%rowtype;
begin
  select * into v_reader from public.profiles where id=p_reader;
  select * into v_owner from public.profiles where id=p_copy.owner_id;
  if v_reader.id is null or v_owner.id is null then raise exception 'Both member profiles are required'; end if;
  if v_reader.account_status<>'active' or v_owner.account_status<>'active' then raise exception 'A participant account is not active'; end if;
  if v_reader.preferred_city_id is null or v_reader.preferred_city_id<>p_copy.city_id then
    raise exception 'Cross-city rentals are not permitted; set your current city to the listing city first';
  end if;
  if not exists(select 1 from public.cities c where c.id=p_copy.city_id and c.is_active and c.status='active' and c.country_code='IN') then
    raise exception 'The listing city is not enabled for rentals';
  end if;
  if not exists(select 1 from public.user_verifications v where v.user_id=p_reader and v.status='verified' and v.age_eligible is true and v.phone_verified_at is not null)
     or not exists(select 1 from public.user_verifications v where v.user_id=p_copy.owner_id and v.status='verified' and v.age_eligible is true and v.phone_verified_at is not null) then
    raise exception 'Reader and Owner must both be verified, age eligible and phone verified';
  end if;
  if not exists(select 1 from public.handover_locations h where h.id=p_location and h.status='active' and h.city_id=p_copy.city_id) then
    raise exception 'Choose an approved public handover point in the same city';
  end if;
end;
$$;
revoke all on function private.assert_booking_request_identity(uuid, public.book_copies, uuid) from public, anon, authenticated;

-- User creates a request, not a reservation. Owner acceptance is explicit; the
-- inventory lock is taken atomically when the approved provider payment attempt starts.
create or replace function public.request_book_booking(
  p_copy_id uuid, p_handover_location_id uuid, p_start_at timestamptz,
  p_end_at timestamptz, p_duration_days integer, p_message text, p_idempotency_key text
) returns uuid
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_reader uuid := auth.uid();
  v_copy public.book_copies%rowtype;
  v_price public.book_pricing%rowtype;
  v_booking uuid;
  v_item uuid;
  v_rent bigint;
  v_commission bigint;
  v_reserved tstzrange;
  v_before interval := interval '0';
  v_after interval := interval '0';
  v_existing uuid;
begin
  if v_reader is null then raise exception 'Authentication required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 or length(p_idempotency_key)>128 then
    raise exception 'A valid idempotency key is required';
  end if;
  select id into v_existing from public.bookings
    where reader_id=v_reader and request_idempotency_key=p_idempotency_key;
  if v_existing is not null then return v_existing; end if;
  if p_start_at<=now() or p_end_at<=p_start_at then raise exception 'Choose a future, valid rental interval'; end if;
  if p_duration_days not in (3,7,15,30) and not (p_duration_days between 1 and 90) then
    raise exception 'Rental duration is outside the supported range';
  end if;
  select * into v_copy from public.book_copies where id=p_copy_id for update;
  if not found or v_copy.listing_status<>'approved' or not v_copy.is_available_for_rent then raise exception 'This physical copy is not available for booking'; end if;
  if v_copy.owner_id=v_reader then raise exception 'You cannot book your own copy'; end if;
  perform private.assert_booking_request_identity(v_reader,v_copy,p_handover_location_id);
  select * into v_price from public.book_pricing
    where book_copy_id=p_copy_id and effective_from<=now()
      and (effective_until is null or effective_until>now())
    order by effective_from desc limit 1;
  if not found then raise exception 'No active rental price is configured'; end if;
  if p_duration_days=3 then v_rent:=v_price.rental_3d_paise;
  elsif p_duration_days=7 then v_rent:=v_price.rental_7d_paise;
  elsif p_duration_days=15 then v_rent:=v_price.rental_15d_paise;
  elsif p_duration_days=30 then v_rent:=v_price.rental_30d_paise;
  else
    if v_price.custom_daily_paise is null or v_price.min_custom_days is null
      or p_duration_days<v_price.min_custom_days or p_duration_days>v_price.max_custom_days then
      raise exception 'Custom rental duration is not enabled for this copy';
    end if;
    v_rent:=v_price.custom_daily_paise*p_duration_days;
  end if;
  if v_rent is null or v_rent<=0 then raise exception 'The selected rental price is not configured'; end if;
  v_commission:=floor((v_rent::numeric*1000/10000)+0.5)::bigint;
  v_reserved:=tstzrange(p_start_at-v_before,p_end_at+v_after,'[)');
  if exists(select 1 from public.book_availability_blocks x where x.book_copy_id=p_copy_id and x.blocked_period&&v_reserved)
     or exists(select 1 from public.copy_reservations x where x.book_copy_id=p_copy_id and x.status in ('hold','confirmed','in_use')
       and x.reserved_period&&v_reserved and (x.status<>'hold' or x.expires_at is null or x.expires_at>now())) then
    raise exception 'This copy is unavailable for the selected dates';
  end if;
  insert into public.bookings(
    booking_number,reader_id,owner_id,city_id,status,requested_start_at,requested_end_at,
    policy_snapshot,rent_subtotal_paise,platform_fee_paise,tax_paise,deposit_required_paise,total_due_paise,
    requested_copy_id,requested_handover_location_id,requested_duration_days,request_idempotency_key,
    request_message,commission_policy_version
  ) values (
    'SS-'||upper(substr(encode(extensions.gen_random_bytes(8),'hex'),1,12)),
    v_reader,v_copy.owner_id,v_copy.city_id,'requested',p_start_at,p_end_at,
    jsonb_build_object('pricing',to_jsonb(v_price),'rent_paise',v_rent,'commission_rate_bps',1000,
      'commission_paise',v_commission,'commission_policy_version','commission_10pct_v1',
      'deposit_status','blocked_pending_provider_legal_approval','tax_status','pending_ca_configuration'),
    v_rent,v_commission,0,0,v_rent,
    p_copy_id,p_handover_location_id,p_duration_days,p_idempotency_key,
    left(nullif(btrim(p_message),''),500),'commission_10pct_v1'
  ) returning id into v_booking;
  insert into public.rental_items(
    booking_id,book_copy_id,city_id,pricing_snapshot,rental_fee_paise,
    buffer_before,buffer_after,reserved_period,duration_days,handover_location_id
  ) values (
    v_booking,p_copy_id,v_copy.city_id,to_jsonb(v_price),v_rent,v_before,v_after,v_reserved,p_duration_days,p_handover_location_id
  ) returning id into v_item;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,to_status,metadata,idempotency_key)
  values(v_booking,v_reader,'booking_requested','requested',
    jsonb_build_object('copy_id',p_copy_id,'duration_days',p_duration_days,'rental_fee_paise',v_rent,'commission_paise',v_commission),
    'booking-request:'||p_idempotency_key);
  insert into public.notifications(user_id,channel,template_key,payload)
  values(v_copy.owner_id,'in_app','booking.requested',
    jsonb_build_object('booking_id',v_booking,'copy_id',p_copy_id,'start_at',p_start_at,'end_at',p_end_at));
  return v_booking;
end;
$$;
revoke all on function public.request_book_booking(uuid,uuid,timestamptz,timestamptz,integer,text,text) from public, anon;
grant execute on function public.request_book_booking(uuid,uuid,timestamptz,timestamptz,integer,text,text) to authenticated;

create or replace function public.accept_book_booking_request(p_booking_id uuid)
returns void language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_actor uuid:=auth.uid(); v_booking public.bookings%rowtype; v_item public.rental_items%rowtype; v_copy public.book_copies%rowtype;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.owner_id<>v_actor then raise exception 'Booking request not found'; end if;
  if v_booking.status<>'requested' then raise exception 'Booking request is no longer awaiting Owner action'; end if;
  select * into v_item from public.rental_items where booking_id=p_booking_id limit 1;
  select * into v_copy from public.book_copies where id=v_booking.requested_copy_id for update;
  if not found or v_copy.owner_id<>v_actor or v_copy.listing_status<>'approved' or not v_copy.is_available_for_rent then
    raise exception 'This copy is no longer eligible for a booking';
  end if;
  perform private.assert_booking_request_identity(v_booking.reader_id,v_copy,v_booking.requested_handover_location_id);
  if exists(select 1 from public.book_availability_blocks x where x.book_copy_id=v_copy.id and x.blocked_period&&v_item.reserved_period)
     or exists(select 1 from public.copy_reservations x where x.book_copy_id=v_copy.id and x.status in ('hold','confirmed','in_use')
       and x.reserved_period&&v_item.reserved_period and (x.status<>'hold' or x.expires_at is null or x.expires_at>now())) then
    raise exception 'The requested interval is no longer available';
  end if;
  update public.bookings set status='owner_accepted',accepted_at=now()
    where id=p_booking_id;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,from_status,to_status,metadata,idempotency_key)
  values(p_booking_id,v_actor,'owner_accepted','requested','owner_accepted','{}'::jsonb,'booking-accepted:'||p_booking_id::text);
  insert into public.notifications(user_id,channel,template_key,payload)
  values(v_booking.reader_id,'in_app','booking.owner_accepted',
    jsonb_build_object('booking_id',p_booking_id,'payment_available',false));
end;
$$;
revoke all on function public.accept_book_booking_request(uuid) from public, anon;
grant execute on function public.accept_book_booking_request(uuid) to authenticated;

create or replace function public.decline_book_booking_request(p_booking_id uuid,p_reason text)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_booking public.bookings%rowtype;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if length(btrim(coalesce(p_reason,'')))<5 then raise exception 'A decline reason is required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.owner_id<>v_actor or v_booking.status<>'requested' then raise exception 'Booking request not found or no longer pending'; end if;
  update public.bookings set status='cancelled',declined_at=now(),cancellation_reason_code='owner_declined'
    where id=p_booking_id;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,from_status,to_status,reason_code,idempotency_key)
  values(p_booking_id,v_actor,'owner_declined','requested','cancelled',left(p_reason,100),'booking-declined:'||p_booking_id::text);
  insert into public.notifications(user_id,channel,template_key,payload)
  values(v_booking.reader_id,'in_app','booking.owner_declined',jsonb_build_object('booking_id',p_booking_id,'reason',left(p_reason,300)));
end;
$$;
revoke all on function public.decline_book_booking_request(uuid,text) from public, anon;
grant execute on function public.decline_book_booking_request(uuid,text) to authenticated;

-- Trusted backend only. This function atomically creates the payment row and the
-- expiring inventory hold. The provider network call happens after commit.
create or replace function public.begin_booking_payment(
  p_booking_id uuid,p_provider text,p_idempotency_key text,p_merchant_reference text
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_booking public.bookings%rowtype; v_item public.rental_items%rowtype; v_copy public.book_copies%rowtype;
  v_cfg public.booking_workflow_configuration%rowtype; v_provider public.payment_provider_approvals%rowtype;
  v_payment uuid; v_amount bigint; v_expires timestamptz;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if length(coalesce(p_idempotency_key,''))<16 or length(coalesce(p_merchant_reference,''))<8 then raise exception 'Payment idempotency and merchant references are required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.status<>'owner_accepted' then raise exception 'Only Owner-accepted bookings can proceed to payment'; end if;
  select * into v_cfg from public.booking_workflow_configuration where id=true and is_active;
  if not found or v_cfg.payment_hold_seconds is null or v_cfg.rental_duration_mode is null
    or v_cfg.tax_policy_version is null or v_cfg.cancellation_policy_version is null then
    raise exception 'Booking, tax and cancellation policies must be approved before checkout is enabled';
  end if;
  select * into v_provider from public.payment_provider_approvals
    where provider_code=p_provider and enabled_for_rent and (expires_at is null or expires_at>now());
  if not found then raise exception 'No provider is approved for the ShelfShare marketplace rental model'; end if;
  if exists(select 1 from public.payments where idempotency_key=p_idempotency_key) then
    select id into v_payment from public.payments where idempotency_key=p_idempotency_key;
    return v_payment;
  end if;
  select * into v_item from public.rental_items where booking_id=p_booking_id limit 1;
  select * into v_copy from public.book_copies where id=v_item.book_copy_id for update;
  perform private.assert_booking_request_identity(v_booking.reader_id,v_copy,v_booking.requested_handover_location_id);
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
     'payment-intent:'||p_idempotency_key);
  insert into public.booking_audit_events(booking_id,event_type,from_status,to_status,metadata,idempotency_key)
   values(v_booking.id,'payment_attempt_created','owner_accepted','payment_pending',
     jsonb_build_object('payment_id',v_payment,'amount_paise',v_amount,'hold_expires_at',v_expires),
     'payment-attempt:'||p_idempotency_key);
  return v_payment;
end;
$$;
revoke all on function public.begin_booking_payment(uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.begin_booking_payment(uuid,text,text,text) to service_role;

-- Provider webhooks call this only after raw-body signature verification by the
-- registered provider adapter. Amount, currency, merchant reference and event ID
-- are revalidated here; browser redirects cannot call this function.
create or replace function public.apply_verified_payment_event(
  p_provider text,p_event_id text,p_payment_id uuid,p_event_type text,
  p_amount_paise bigint,p_currency char(3),p_provider_payment_id text,
  p_payload_sha256 text,p_provider_dispute_reference text default null
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_payment public.payments%rowtype; v_booking public.bookings%rowtype; v_item public.rental_items%rowtype;
  v_reservation public.copy_reservations%rowtype; v_inserted bigint; v_provider_dispute uuid;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_event_id is null or length(p_event_id)>200 or p_payload_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'Invalid verified webhook envelope'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256,provider_payment_reference)
   values(p_payment_id,p_provider,p_event_id,p_event_type,true,p_payload_sha256,p_provider_payment_id)
   on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted=0 then return jsonb_build_object('duplicate',true,'processed',true); end if;
  select * into v_payment from public.payments where id=p_payment_id and provider=p_provider for update;
  if not found then
    update public.payment_events set processing_status='rejected',processing_error_code='unknown_payment',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','unknown_payment');
  end if;
  if p_amount_paise is distinct from v_payment.amount_paise or p_currency<>'INR'
     or (v_payment.provider_payment_id is not null and p_provider_payment_id is not null and v_payment.provider_payment_id<>p_provider_payment_id) then
    update public.payments set status='reconciliation_required',provider_status='amount_or_reference_mismatch'
      where id=v_payment.id;
    update public.payment_events set processing_status='dead_letter',processing_error_code='amount_or_reference_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','amount_or_reference_mismatch');
  end if;
  select * into v_booking from public.bookings where id=v_payment.booking_id for update;
  select * into v_item from public.rental_items where booking_id=v_booking.id limit 1;
  select * into v_reservation from public.copy_reservations where booking_id=v_booking.id for update;

  if p_event_type in ('payment.captured','payment.succeeded','order.paid') then
    if v_payment.status='captured' then
      update public.payment_events set processing_status='processed',processed_at=now()
       where provider=p_provider and provider_event_id=p_event_id;
      return jsonb_build_object('duplicate_capture',true,'captured',true);
    end if;
    if v_reservation.id is null then
      update public.payments set status='reconciliation_required',provider_status='captured_without_reservation'
        where id=v_payment.id;
      update public.bookings set status='disputed',cancellation_reason_code='captured_without_reservation'
        where id=v_booking.id;
      insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
        values('payment',v_payment.id,'refund_after_unreserved_capture',
          jsonb_build_object('payment_id',v_payment.id,'booking_id',v_booking.id,'reason','captured_without_reservation'),
          'late-capture-refund:'||v_payment.id::text) on conflict(idempotency_key) do nothing;
    else
      update public.copy_reservations set status='expired'
       where id=v_reservation.id and status='hold' and expires_at<=now();
      select * into v_reservation from public.copy_reservations where id=v_reservation.id;
      if v_reservation.status='expired' then
        update public.copy_reservations set status='hold',expires_at=now()+interval '2 minutes'
          where id=v_reservation.id;
      end if;
      begin
        update public.copy_reservations set status='confirmed',expires_at=null where id=v_reservation.id;
        update public.payments set status='captured',captured_at=coalesce(captured_at,now()),
          provider_payment_id=coalesce(provider_payment_id,p_provider_payment_id),provider_status=p_event_type,last_provider_event_at=now()
          where id=v_payment.id;
        update public.bookings set status='confirmed' where id=v_booking.id;
        insert into public.commission_ledger(booking_id,payment_id,commission_rate_bps,rent_basis_paise,commission_paise,policy_version)
          values(v_booking.id,v_payment.id,1000,v_booking.rent_subtotal_paise,v_booking.platform_fee_paise,
            coalesce(v_booking.commission_policy_version,'commission_10pct_v1'))
          on conflict(booking_id,policy_version) do nothing;
      exception when exclusion_violation then
        update public.payments set status='reconciliation_required',provider_status='captured_inventory_conflict',
          captured_at=coalesce(captured_at,now()),provider_payment_id=coalesce(provider_payment_id,p_provider_payment_id)
          where id=v_payment.id;
        update public.bookings set status='disputed',cancellation_reason_code='captured_inventory_conflict'
          where id=v_booking.id;
        insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
          values('payment',v_payment.id,'refund_after_inventory_conflict',
            jsonb_build_object('payment_id',v_payment.id,'booking_id',v_booking.id,'reason','captured_inventory_conflict'),
            'inventory-conflict-refund:'||v_payment.id::text) on conflict(idempotency_key) do nothing;
      end;
    end if;
  elsif p_event_type in ('payment.failed','payment.cancelled','order.failed') then
    if v_payment.status not in ('captured','partially_refunded','refunded') then
      update public.payments set status='failed',failure_code=p_event_type,provider_status=p_event_type,last_provider_event_at=now()
        where id=v_payment.id;
      update public.copy_reservations set status='released' where id=v_reservation.id and status='hold';
      update public.bookings set status='cancelled',cancellation_reason_code='payment_failed' where id=v_booking.id;
    end if;
  elsif p_event_type in ('chargeback.opened','dispute.opened','payment.disputed') then
    if p_provider_dispute_reference is null then raise exception 'Provider dispute reference is required'; end if;
    insert into public.payment_disputes(payment_id,booking_id,provider,provider_dispute_reference,amount_paise,reason_code)
      values(v_payment.id,v_booking.id,p_provider,p_provider_dispute_reference,p_amount_paise,p_event_type)
      on conflict(provider,provider_dispute_reference) do nothing;
    update public.payments set status='reconciliation_required',provider_status=p_event_type,last_provider_event_at=now()
      where id=v_payment.id;
    update public.bookings set status='disputed' where id=v_booking.id;
    update public.owner_earnings set status='reconciliation_required'
      where booking_id=v_booking.id and status in ('eligible','pending');
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_event_type',processed_at=now()
     where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
   where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'payment_status',(select status from public.payments where id=v_payment.id),
    'booking_status',(select status from public.bookings where id=v_booking.id));
end;
$$;
revoke all on function public.apply_verified_payment_event(text,text,uuid,text,bigint,char,text,text,text) from public, anon, authenticated;
grant execute on function public.apply_verified_payment_event(text,text,uuid,text,bigint,char,text,text,text) to service_role;

-- Refunds are amount-bounded, finance-authorised requests. No cancellation or
-- no-show formula is inferred; an approved policy must determine the amount.
create or replace function public.create_finance_refund(
  p_actor_id uuid,p_payment_id uuid,p_amount_paise bigint,p_reason_code text,p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_payment public.payments%rowtype; v_refund uuid; v_prior bigint; v_provider public.payment_provider_approvals%rowtype;
begin
  if not exists(select 1 from public.user_roles r where r.user_id=p_actor_id and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance approval required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 or length(btrim(coalesce(p_reason_code,'')))<4 then
    raise exception 'Refund idempotency key and reason are required';
  end if;
  select id into v_refund from public.refunds where idempotency_key=p_idempotency_key;
  if v_refund is not null then return v_refund; end if;
  select * into v_payment from public.payments where id=p_payment_id for update;
  if not found or v_payment.status not in ('captured','partially_refunded') then raise exception 'Only captured payments can be refunded'; end if;
  select * into v_provider from public.payment_provider_approvals
    where provider_code=v_payment.provider and enabled_for_rent and supports_refunds and (expires_at is null or expires_at>now());
  if not found then raise exception 'Approved provider refund capability is unavailable'; end if;
  select coalesce(sum(amount_paise),0) into v_prior from public.refunds
    where payment_id=p_payment_id and status in ('requested','pending','succeeded','reconciliation_required');
  if p_amount_paise<=0 or p_amount_paise+v_prior>v_payment.amount_paise then raise exception 'Refund exceeds the unrefunded captured amount'; end if;
  insert into public.refunds(booking_id,payment_id,requested_by,provider,idempotency_key,amount_paise,reason_code)
    values(v_payment.booking_id,p_payment_id,p_actor_id,v_payment.provider,p_idempotency_key,p_amount_paise,p_reason_code)
    returning id into v_refund;
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('refund',v_refund,'refund_requested',jsonb_build_object('refund_id',v_refund,'payment_id',p_payment_id,'amount_paise',p_amount_paise),
      'refund-outbox:'||p_idempotency_key) on conflict(idempotency_key) do nothing;
  return v_refund;
end;
$$;
revoke all on function public.create_finance_refund(uuid,uuid,bigint,text,text) from public, anon, authenticated;
grant execute on function public.create_finance_refund(uuid,uuid,bigint,text,text) to service_role;

-- Deposit release is a per-booking provider instruction, not a withdrawal from a
-- pooled wallet. No release can occur while this member has any active rental or claim.
create or replace function public.request_deposit_release(p_deposit_id uuid, p_idempotency_key text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_user uuid:=auth.uid(); v_deposit public.deposits%rowtype; v_booking public.bookings%rowtype;
  v_provider public.payment_provider_approvals%rowtype; v_request uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 then raise exception 'Valid idempotency key required'; end if;
  select * into v_deposit from public.deposits where id=p_deposit_id for update;
  if not found or v_deposit.payer_id<>v_user then raise exception 'Deposit not found'; end if;
  select id into v_request from public.deposit_release_requests where idempotency_key=p_idempotency_key;
  if v_request is not null then return v_request; end if;
  if not v_deposit.feature_enabled_at_creation or v_deposit.status<>'held_by_provider' then
    raise exception 'Deposit is not eligible for release under an approved provider arrangement';
  end if;
  select * into v_booking from public.bookings where id=v_deposit.booking_id for update;
  if v_booking.status<>'completed' then raise exception 'Booking is not closed'; end if;
  if exists(select 1 from public.disputes x where x.booking_id=v_booking.id and x.status<>'closed')
    or exists(select 1 from public.deposit_claims x where x.deposit_id=v_deposit.id and x.status not in ('rejected','closed')) then
    raise exception 'An open dispute or deposit claim blocks release';
  end if;
  if exists(select 1 from public.bookings x where (x.reader_id=v_user or x.owner_id=v_user)
    and x.status in ('owner_accepted','payment_pending','confirmed','collection_pending','active','return_pending','disputed')) then
    raise exception 'Deposit release is blocked while this member has any active rental';
  end if;
  select p.* into v_provider from public.payment_provider_approvals p
    join public.payments pay on pay.provider=p.provider_code
    where pay.booking_id=v_booking.id and p.enabled_for_deposits and p.supports_deposit_release
      and p.supports_deposit_hold and p.supports_deposit_dispute_hold
      and p.legal_approval_reference is not null and p.accounting_approval_reference is not null
      and (p.expires_at is null or p.expires_at>now())
    limit 1;
  if not found then raise exception 'No approved provider/legal deposit release arrangement is enabled'; end if;
  insert into public.deposit_release_requests(deposit_id,requested_by,amount_paise,idempotency_key)
    values(v_deposit.id,v_user,v_deposit.amount_paise,p_idempotency_key) returning id into v_request;
  update public.deposits set status='release_pending' where id=v_deposit.id;
  insert into public.deposit_ledger(deposit_id,event_type,amount_paise,idempotency_key,metadata)
    values(v_deposit.id,'release_requested',v_deposit.amount_paise,'deposit-release:'||p_idempotency_key,
      jsonb_build_object('release_request_id',v_request));
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('deposit',v_deposit.id,'deposit_release_requested',jsonb_build_object('release_request_id',v_request),
      'deposit-release-outbox:'||p_idempotency_key) on conflict(idempotency_key) do nothing;
  return v_request;
end;
$$;
revoke all on function public.request_deposit_release(uuid,text) from public, anon;
grant execute on function public.request_deposit_release(uuid,text) to authenticated;

create or replace function public.create_handover_session_secure(
  p_booking_id uuid,p_handover_type text,p_actor_id uuid,p_qr_token_hash text,p_otp_hash text,p_expires_at timestamptz
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_booking public.bookings%rowtype; v_item public.rental_items%rowtype; v_location public.handover_locations%rowtype; v_session uuid;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_handover_type not in ('collection','return') or p_qr_token_hash !~ '^[a-f0-9]{64}$'
    or p_otp_hash !~ '^[a-f0-9]{64}$' or p_expires_at<=now() or p_expires_at>now()+interval '15 minutes' then
    raise exception 'Invalid one-time handover credentials or expiry';
  end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or p_actor_id not in (v_booking.reader_id,v_booking.owner_id) then raise exception 'Booking participant required'; end if;
  if p_handover_type='collection' then
    if v_booking.status<>'confirmed' or not exists(select 1 from public.payments p where p.booking_id=p_booking_id and p.status='captured') then
      raise exception 'Collection can start only after provider-confirmed payment';
    end if;
  else
    if v_booking.status not in ('active','return_pending') then raise exception 'Return is not available in this booking state'; end if;
  end if;
  select * into v_item from public.rental_items where booking_id=p_booking_id limit 1;
  select * into v_location from public.handover_locations where id=v_item.handover_location_id and status='active' and city_id=v_booking.city_id;
  if not found then raise exception 'Approved public handover location is unavailable'; end if;
  if exists(select 1 from public.handover_sessions s where s.booking_id=p_booking_id and s.handover_type=p_handover_type
    and s.status in ('created','awaiting_counterparty') and s.expires_at>now()) then
    raise exception 'A valid handover session already exists';
  end if;
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
revoke all on function public.create_handover_session_secure(uuid,text,uuid,text,text,timestamptz) from public, anon, authenticated;
grant execute on function public.create_handover_session_secure(uuid,text,uuid,text,text,timestamptz) to service_role;

create or replace function public.register_handover_condition_photo(
  p_session_id uuid,p_actor_id uuid,p_object_key text,p_sha256 text,p_caption text
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_session public.handover_sessions%rowtype; v_photo uuid;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  select * into v_session from public.handover_sessions where id=p_session_id for update;
  if not found or p_actor_id not in (
    select reader_id from public.bookings where id=v_session.booking_id
    union select owner_id from public.bookings where id=v_session.booking_id
  ) then raise exception 'Booking participant required'; end if;
  if v_session.status not in ('created','awaiting_counterparty') or v_session.expires_at<=now() then raise exception 'Handover session expired'; end if;
  if p_object_key not like p_actor_id::text||'/'||v_session.booking_id::text||'/'||p_session_id::text||'/%' then
    raise exception 'Condition photo must be stored in the actor and booking scoped private path';
  end if;
  if p_sha256 is not null and p_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'Invalid photo digest'; end if;
  insert into public.rental_condition_photos(booking_id,rental_item_id,submitted_by,evidence_kind,object_key,content_sha256,caption,captured_at,handover_session_id)
    values(v_session.booking_id,v_session.rental_item_id,p_actor_id,
      case when v_session.handover_type='collection' then 'collection'::public.evidence_kind else 'return'::public.evidence_kind end,
      p_object_key,p_sha256,left(coalesce(p_caption,''),300),now(),p_session_id)
    returning id into v_photo;
  insert into public.handover_events(handover_session_id,actor_id,event_type,event_payload)
    values(p_session_id,p_actor_id,'condition_photo_added',jsonb_build_object('photo_id',v_photo,'sha256',p_sha256));
  return v_photo;
end;
$$;
revoke all on function public.register_handover_condition_photo(uuid,uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.register_handover_condition_photo(uuid,uuid,text,text,text) to service_role;

create or replace function private.complete_handover_if_ready(p_session_id uuid)
returns boolean language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_session public.handover_sessions%rowtype; v_booking public.bookings%rowtype; v_cfg public.booking_workflow_configuration%rowtype;
  v_owner_photos integer; v_reader_photos integer; v_due timestamptz;
begin
  select * into v_session from public.handover_sessions where id=p_session_id for update;
  if not found or v_session.status='completed' then return false; end if;
  if v_session.expires_at<=now() or v_session.qr_consumed_at is null
    or v_session.owner_confirmed_at is null or v_session.reader_confirmed_at is null
    or v_session.owner_condition_confirmed_at is null or v_session.reader_condition_confirmed_at is null then return false; end if;
  select * into v_booking from public.bookings where id=v_session.booking_id for update;
  select count(*) filter(where submitted_by=v_booking.owner_id),count(*) filter(where submitted_by=v_booking.reader_id)
    into v_owner_photos,v_reader_photos
    from public.rental_condition_photos where handover_session_id=p_session_id;
  if v_owner_photos<1 or v_reader_photos<1 then return false; end if;
  if v_session.handover_type='collection' then
    select * into v_cfg from public.booking_workflow_configuration where id=true and is_active and rental_duration_mode is not null;
    if not found then raise exception 'Approved rental-day convention is required before activating a rental'; end if;
    if v_cfg.rental_duration_mode='elapsed_24h' then
      v_due:=now()+make_interval(days=>v_booking.requested_duration_days);
    else
      v_due:=(((now() at time zone 'Asia/Kolkata')::date+v_booking.requested_duration_days)::timestamp at time zone 'Asia/Kolkata');
    end if;
    update public.bookings set status='active',rental_start_at=now(),rental_due_at=v_due where id=v_booking.id;
    update public.copy_reservations set status='in_use',expires_at=null where booking_id=v_booking.id;
    insert into public.owner_earnings(booking_id,owner_id,gross_rent_paise,commission_paise,tax_withheld_paise,provider_fee_paise,net_payable_paise,status,eligible_at)
      values(v_booking.id,v_booking.owner_id,v_booking.rent_subtotal_paise,v_booking.platform_fee_paise,0,0,
        greatest(v_booking.rent_subtotal_paise-v_booking.platform_fee_paise,0),'eligible',now())
      on conflict(booking_id) do nothing;
  else
    update public.bookings set status='completed',completed_at=now() where id=v_booking.id;
    update public.copy_reservations set status='released',expires_at=null where booking_id=v_booking.id and status='in_use';
  end if;
  update public.handover_sessions set status='completed',completed_at=now() where id=p_session_id;
  insert into public.handover_events(handover_session_id,actor_id,event_type,event_payload)
    values(p_session_id,null,'handover_completed',jsonb_build_object('booking_id',v_booking.id,'type',v_session.handover_type));
  insert into public.booking_audit_events(booking_id,event_type,from_status,to_status,metadata,idempotency_key)
    values(v_booking.id,'handover_completed',v_booking.status,
      case when v_session.handover_type='collection' then 'active'::public.booking_status else 'completed'::public.booking_status end,
      jsonb_build_object('session_id',p_session_id,'owner_photo_count',v_owner_photos,'reader_photo_count',v_reader_photos),
      'handover-complete:'||p_session_id::text);
  return true;
end;
$$;
revoke all on function private.complete_handover_if_ready(uuid) from public, anon, authenticated;

create or replace function public.confirm_handover_qr_or_otp(
  p_session_id uuid,p_actor_id uuid,p_token_hash text,p_otp_hash text,p_condition_acknowledged boolean
) returns boolean language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_session public.handover_sessions%rowtype; v_booking public.bookings%rowtype; v_is_owner boolean; v_valid boolean:=false; v_complete boolean;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  select * into v_session from public.handover_sessions where id=p_session_id for update;
  if not found or v_session.status not in ('created','awaiting_counterparty') or v_session.completed_at is not null then raise exception 'Handover session is not active'; end if;
  if v_session.expires_at<=now() then update public.handover_sessions set status='expired' where id=p_session_id; raise exception 'Handover QR/OTP expired'; end if;
  select * into v_booking from public.bookings where id=v_session.booking_id;
  if p_actor_id=v_session.initiator_id or p_actor_id not in (v_booking.reader_id,v_booking.owner_id) then raise exception 'The other authenticated party must scan or enter the fallback OTP'; end if;
  if v_session.otp_locked_until is not null and v_session.otp_locked_until>now() then raise exception 'OTP fallback temporarily locked'; end if;
  v_valid:=(p_token_hash is not null and p_token_hash=v_session.qr_token_hash)
    or (p_otp_hash is not null and p_otp_hash=v_session.otp_hash);
  if not v_valid then
    update public.handover_sessions set otp_attempts=otp_attempts+1,
      otp_locked_until=case when otp_attempts+1>=5 then now()+interval '15 minutes' else otp_locked_until end
      where id=p_session_id;
    insert into public.handover_events(handover_session_id,actor_id,event_type,event_payload)
      values(p_session_id,p_actor_id,'verification_failed',jsonb_build_object('attempts',least(v_session.otp_attempts+1,5)));
    raise exception 'QR token or OTP is invalid';
  end if;
  if v_session.qr_consumed_at is not null then raise exception 'This one-time handover token has already been used'; end if;
  if not coalesce(p_condition_acknowledged,false) then raise exception 'Confirm the initial condition evidence before continuing'; end if;
  update public.handover_sessions set qr_consumed_at=now(),qr_consumed_by=p_actor_id,status='awaiting_counterparty',
    owner_confirmed_at=case when p_actor_id=v_booking.owner_id then now() else owner_confirmed_at end,
    reader_confirmed_at=case when p_actor_id=v_booking.reader_id then now() else reader_confirmed_at end,
    owner_condition_confirmed_at=case when p_actor_id=v_booking.owner_id then now() else owner_condition_confirmed_at end,
    reader_condition_confirmed_at=case when p_actor_id=v_booking.reader_id then now() else reader_condition_confirmed_at end
    where id=p_session_id;
  insert into public.handover_events(handover_session_id,actor_id,event_type,event_payload)
    values(p_session_id,p_actor_id,case when p_token_hash is not null then 'qr_consumed' else 'otp_fallback_used' end,
      jsonb_build_object('condition_acknowledged',true));
  v_complete:=private.complete_handover_if_ready(p_session_id);
  return v_complete;
end;
$$;
revoke all on function public.confirm_handover_qr_or_otp(uuid,uuid,text,text,boolean) from public, anon, authenticated;
grant execute on function public.confirm_handover_qr_or_otp(uuid,uuid,text,text,boolean) to service_role;

create or replace function public.confirm_handover_initiator(
  p_session_id uuid,p_actor_id uuid,p_condition_acknowledged boolean
) returns boolean language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_session public.handover_sessions%rowtype; v_booking public.bookings%rowtype;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  select * into v_session from public.handover_sessions where id=p_session_id for update;
  if not found or v_session.expires_at<=now() or v_session.qr_consumed_at is null then raise exception 'A valid counterparty QR/OTP verification is required first'; end if;
  if v_session.status='completed' then return true; end if;
  if p_actor_id<>v_session.initiator_id or not coalesce(p_condition_acknowledged,false) then
    raise exception 'Only the initiating party may confirm its own side and condition';
  end if;
  select * into v_booking from public.bookings where id=v_session.booking_id;
  update public.handover_sessions set
    owner_confirmed_at=case when p_actor_id=v_booking.owner_id then now() else owner_confirmed_at end,
    reader_confirmed_at=case when p_actor_id=v_booking.reader_id then now() else reader_confirmed_at end,
    owner_condition_confirmed_at=case when p_actor_id=v_booking.owner_id then now() else owner_condition_confirmed_at end,
    reader_condition_confirmed_at=case when p_actor_id=v_booking.reader_id then now() else reader_condition_confirmed_at end
    where id=p_session_id;
  insert into public.handover_events(handover_session_id,actor_id,event_type,event_payload)
    values(p_session_id,p_actor_id,'initiator_confirmed',jsonb_build_object('condition_acknowledged',true));
  return private.complete_handover_if_ready(p_session_id);
end;
$$;
revoke all on function public.confirm_handover_initiator(uuid,uuid,boolean) from public, anon, authenticated;
grant execute on function public.confirm_handover_initiator(uuid,uuid,boolean) to service_role;

create or replace function public.get_my_booking_workspace()
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare v_user uuid:=auth.uid(); v_rows jsonb;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select coalesce(jsonb_agg(x order by (x->>'created_at') desc),'[]'::jsonb) into v_rows
  from (
    select jsonb_build_object(
      'id',b.id,'booking_number',b.booking_number,'status',b.status,
      'reader_id',b.reader_id,'owner_id',b.owner_id,'is_reader',(b.reader_id=v_user),
      'requested_start_at',b.requested_start_at,'requested_end_at',b.requested_end_at,
      'requested_duration_days',b.requested_duration_days,'rent_subtotal_paise',b.rent_subtotal_paise,
      'platform_fee_paise',b.platform_fee_paise,'tax_paise',b.tax_paise,
      'deposit_required_paise',b.deposit_required_paise,'total_due_paise',b.total_due_paise,
      'created_at',b.created_at,'accepted_at',b.accepted_at,'completed_at',b.completed_at,
      'cancellation_reason_code',b.cancellation_reason_code,'title',t.title,'authors',t.authors,
      'copy_id',c.id,'condition',c.condition_summary,'city_id',b.city_id,'locality_id',c.locality_id,
      'handover_location_id',b.requested_handover_location_id,'handover_location',h.name,
      'payment_status',(select p.status from public.payments p where p.booking_id=b.id order by p.created_at desc limit 1),
      'payment_amount_paise',(select p.amount_paise from public.payments p where p.booking_id=b.id order by p.created_at desc limit 1),
      'rental_start_at',b.rental_start_at,'rental_due_at',b.rental_due_at,
      'active_handover',(select jsonb_build_object('id',s.id,'type',s.handover_type,'expires_at',s.expires_at,'status',s.status,
        'qr_consumed_at',s.qr_consumed_at,'owner_confirmed',s.owner_confirmed_at is not null,
        'reader_confirmed',s.reader_confirmed_at is not null)
        from public.handover_sessions s where s.booking_id=b.id order by s.created_at desc limit 1)
    ) as x
    from public.bookings b
    left join public.book_copies c on c.id=b.requested_copy_id
    left join public.book_titles t on t.id=c.book_title_id
    left join public.handover_locations h on h.id=b.requested_handover_location_id
    where b.reader_id=v_user or b.owner_id=v_user
  ) q;
  return v_rows;
end;
$$;
revoke all on function public.get_my_booking_workspace() from public, anon;
grant execute on function public.get_my_booking_workspace() to authenticated;

create or replace function public.get_my_financial_history()
returns table(transaction_type text,reference_id uuid,status text,amount_paise bigint,currency char(3),description text,created_at timestamptz)
language sql stable security definer
set search_path = pg_catalog, public
as $$
  select 'rental_payment',p.id,p.status::text,p.amount_paise,p.currency,'Rental payment'::text,p.created_at
    from public.payments p where p.payer_id=auth.uid()
  union all
  select 'refund',r.id,r.status,r.amount_paise,r.currency,'Refund request'::text,r.created_at
    from public.refunds r join public.payments p on p.id=r.payment_id
    where p.payer_id=auth.uid()
  union all
  select 'owner_earning',e.id,e.status::text,e.net_payable_paise,'INR'::char(3),'Owner earning (pre-tax/provider-fee approval)'::text,e.created_at
    from public.owner_earnings e where e.owner_id=auth.uid()
  union all
  select 'payout',p.id,p.status::text,p.amount_paise,p.currency,'Owner settlement'::text,p.created_at
    from public.payouts p where p.owner_id=auth.uid()
  union all
  select 'deposit',d.id,d.status::text,d.amount_paise,d.currency,'Booking security deposit (provider status)'::text,d.created_at
    from public.deposits d where d.payer_id=auth.uid()
  order by created_at desc;
$$;
revoke all on function public.get_my_financial_history() from public, anon;
grant execute on function public.get_my_financial_history() to authenticated;

-- Payout requests are only possible with a provider-onboarded, KYC-verified seller
-- and after verified collection. The provider adapter must confirm actual settlement.
create unique index if not exists payouts_one_open_per_earning_uq
  on public.payouts(owner_earning_id)
  where status in ('pending','eligible','processing','reconciliation_required');

create or replace function public.create_owner_payout_request(
  p_earning_id uuid,p_provider text,p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_user uuid:=auth.uid(); v_earning public.owner_earnings%rowtype; v_approval public.payment_provider_approvals%rowtype;
  v_vendor public.provider_vendor_accounts%rowtype; v_payout uuid; v_cfg public.booking_workflow_configuration%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select * into v_earning from public.owner_earnings where id=p_earning_id and owner_id=v_user for update;
  if not found or v_earning.status<>'eligible' then raise exception 'No eligible owner settlement found'; end if;
  select * into v_approval from public.payment_provider_approvals
    where provider_code=p_provider and enabled_for_rent and supports_vendor_onboarding and supports_split_settlement
      and supports_delayed_transfer and supports_reconciliation and accounting_approval_reference is not null
      and legal_approval_reference is not null and (expires_at is null or expires_at>now());
  if not found then raise exception 'Approved marketplace settlement provider is unavailable'; end if;
  select * into v_vendor from public.provider_vendor_accounts
    where provider_approval_id=v_approval.id and user_id=v_user and kyc_status='verified';
  if not found then raise exception 'Owner has not completed provider merchant onboarding and KYC'; end if;
  if exists(select 1 from public.payment_disputes d join public.bookings b on b.id=d.booking_id where b.id=v_earning.booking_id and d.status not in ('won','closed')) then
    raise exception 'An open payment dispute blocks owner settlement';
  end if;
  if exists(select 1 from public.payouts p where p.owner_earning_id=p_earning_id and p.status in ('pending','eligible','processing','reconciliation_required')) then
    raise exception 'A settlement request is already in progress';
  end if;
  insert into public.payouts(owner_earning_id,owner_id,provider,idempotency_key,amount_paise,status)
    values(p_earning_id,v_user,p_provider,p_idempotency_key,v_earning.net_payable_paise,'pending') returning id into v_payout;
  update public.owner_earnings set status='processing' where id=p_earning_id;
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('payout',v_payout,'owner_payout_requested',jsonb_build_object('payout_id',v_payout,'provider_vendor_reference',v_vendor.provider_vendor_reference),
      'owner-payout:'||p_idempotency_key) on conflict(idempotency_key) do nothing;
  return v_payout;
end;
$$;
revoke all on function public.create_owner_payout_request(uuid,text,text) from public, anon;
grant execute on function public.create_owner_payout_request(uuid,text,text) to authenticated;

-- No-show reports create incidents only. Fees, forfeiture, compensation and
-- cancellation/refund percentages require the unresolved policy matrix.
create or replace function public.report_booking_incident(p_booking_id uuid,p_incident_type text,p_description text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_user uuid:=auth.uid(); v_booking public.bookings%rowtype; v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_user not in (v_booking.reader_id,v_booking.owner_id) then raise exception 'Booking participant required'; end if;
  if p_incident_type not in ('owner_no_show','reader_no_show','venue_unavailable','safety_issue','other')
    or length(btrim(coalesce(p_description,'')))<10 then raise exception 'Valid incident type and evidence description are required'; end if;
  if (p_incident_type='owner_no_show' and v_user<>v_booking.reader_id)
    or (p_incident_type='reader_no_show' and v_user<>v_booking.owner_id) then
    raise exception 'Only the other participant may report this no-show';
  end if;
  insert into public.booking_incidents(booking_id,reported_by,incident_type,description)
    values(p_booking_id,v_user,p_incident_type,left(p_description,2000)) returning id into v_id;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(p_booking_id,v_user,'incident_reported',jsonb_build_object('incident_id',v_id,'type',p_incident_type),'incident:'||v_id::text);
  return v_id;
end;
$$;
revoke all on function public.report_booking_incident(uuid,text,text) from public, anon;
grant execute on function public.report_booking_incident(uuid,text,text) to authenticated;

-- RLS is read-only for participants; all financial writes remain service-side or RPC-only.
alter table public.booking_audit_events enable row level security;
create policy booking_audit_participant_read on public.booking_audit_events for select to authenticated
  using (exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.reader_id,b.owner_id)));
alter table public.booking_incidents enable row level security;
create policy booking_incidents_participant_read on public.booking_incidents for select to authenticated
  using (exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.reader_id,b.owner_id)));
alter table public.deposit_claims enable row level security;
create policy deposit_claim_participant_read on public.deposit_claims for select to authenticated
  using (claimant_id=auth.uid() or against_user_id=auth.uid());
alter table public.payment_disputes enable row level security;
create policy payment_dispute_participant_read on public.payment_disputes for select to authenticated
  using (exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.reader_id,b.owner_id)));

revoke all on public.booking_workflow_configuration,public.payment_provider_approvals,public.provider_vendor_accounts,
  public.payment_reconciliation_runs,public.payment_reconciliation_items from anon,authenticated;
revoke insert,update,delete on public.booking_audit_events,public.booking_incidents,public.payment_disputes,
  public.deposit_claims,public.payment_reconciliation_runs,public.payment_reconciliation_items from anon,authenticated;
revoke all on public.payments,public.payment_events,public.deposits,public.deposit_ledger,public.deposit_release_requests,
  public.refunds,public.owner_earnings,public.payouts,public.commission_ledger from anon,authenticated;

commit;

begin;

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

alter table public.bookings
  add column if not exists tax_calculated_at timestamptz,
  add column if not exists payment_policy_version text;
alter table public.owner_earnings
  add column if not exists settlement_calculated_at timestamptz,
  add column if not exists settlement_policy_version text,
  add column if not exists settlement_approved_by uuid references auth.users(id) on delete restrict;

create table if not exists public.booking_workflow_configuration (
  id boolean primary key default true check (id),
  is_active boolean not null default false,
  configuration_version text not null,
  buffer_before interval not null default interval '0',
  buffer_after interval not null default interval '0',
  request_hold_seconds integer,
  payment_hold_seconds integer,
  handover_ttl_seconds integer not null default 300,
  rental_duration_mode text check (rental_duration_mode in ('elapsed_24h','calendar_day')),
  tax_policy_version text,
  cancellation_policy_version text,
  tax_approval_reference text,
  tax_approved_by uuid references auth.users(id) on delete restrict,
  tax_approved_at timestamptz,
  deposit_claim_window_seconds integer,
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  updated_at timestamptz not null default now(),
  check (buffer_before >= interval '0' and buffer_after >= interval '0'),
  check (request_hold_seconds is null or request_hold_seconds between 60 and 172800),
  check (payment_hold_seconds is null or payment_hold_seconds between 60 and 3600),
  check (handover_ttl_seconds between 60 and 900),
  check (deposit_claim_window_seconds is null or deposit_claim_window_seconds between 0 and 2592000),
  check (not is_active or (
    approved_by is not null and approved_at is not null
    and tax_policy_version is not null and cancellation_policy_version is not null
    and length(btrim(coalesce(tax_approval_reference,''))) >= 5
    and tax_approved_by is not null and tax_approved_at is not null
    and request_hold_seconds is not null and payment_hold_seconds is not null
    and rental_duration_mode is not null
  ))
);
alter table public.booking_workflow_configuration enable row level security;
revoke all on public.booking_workflow_configuration from anon,authenticated;

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
    marketplace_model='peer_to_peer_physical_book_rental'
    and supports_vendor_onboarding and supports_split_settlement and supports_delayed_transfer
    and supports_refunds and supports_chargebacks and supports_signed_webhooks and supports_reconciliation
    and length(btrim(coalesce(provider_approval_reference,'')))>=5
    and length(btrim(coalesce(marketplace_approval_reference,'')))>=5
    and length(btrim(coalesce(legal_approval_reference,'')))>=5
    and length(btrim(coalesce(accounting_approval_reference,'')))>=5
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
revoke all on public.payment_provider_approvals from anon,authenticated;

create table if not exists public.provider_vendor_accounts (
  id uuid primary key default gen_random_uuid(),
  provider_approval_id uuid not null references public.payment_provider_approvals(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  provider_vendor_reference text not null,
  kyc_status text not null check (kyc_status in ('pending','verified','rejected','suspended')),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  unique(provider_approval_id,user_id),
  unique(provider_approval_id,provider_vendor_reference),
  check (kyc_status<>'verified' or verified_at is not null)
);
alter table public.provider_vendor_accounts enable row level security;
revoke all on public.provider_vendor_accounts from anon,authenticated;

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
  on public.booking_audit_events(booking_id,created_at desc);
alter table public.booking_audit_events enable row level security;
create policy booking_audit_participant_read on public.booking_audit_events for select to authenticated
  using (exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.reader_id,b.owner_id)));

create table if not exists public.payment_disputes (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments(id) on delete restrict,
  booking_id uuid not null references public.bookings(id) on delete restrict,
  provider text not null,
  provider_dispute_reference text not null,
  amount_paise bigint not null check (amount_paise>0),
  reason_code text not null,
  status text not null default 'open' check (status in ('open','evidence_due','under_review','won','lost','closed','reconciliation_required')),
  response_due_at timestamptz,
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  unique(provider,provider_dispute_reference)
);
alter table public.payment_disputes enable row level security;
create policy payment_dispute_participant_read on public.payment_disputes for select to authenticated
  using (exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.reader_id,b.owner_id)));

create table if not exists public.deposit_claims (
  id uuid primary key default gen_random_uuid(),
  deposit_id uuid not null references public.deposits(id) on delete restrict,
  booking_id uuid not null references public.bookings(id) on delete restrict,
  claimant_id uuid not null references auth.users(id) on delete restrict,
  against_user_id uuid not null references auth.users(id) on delete restrict,
  amount_requested_paise bigint not null check (amount_requested_paise>0),
  reason_code text not null,
  description text not null,
  status text not null default 'submitted' check (status in ('submitted','under_review','needs_response','approved','rejected','appealed','closed')),
  decision_amount_paise bigint check (decision_amount_paise is null or decision_amount_paise>=0),
  decision_reason text,
  decided_by uuid references auth.users(id) on delete restrict,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  check(claimant_id<>against_user_id),
  check(decision_amount_paise is null or decision_amount_paise<=amount_requested_paise)
);
alter table public.deposit_claims enable row level security;
create policy deposit_claim_participant_read on public.deposit_claims for select to authenticated
  using (claimant_id=auth.uid() or against_user_id=auth.uid());

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
  check(period_end>period_start)
);
create table if not exists public.payment_reconciliation_items (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.payment_reconciliation_runs(id) on delete restrict,
  record_type text not null check (record_type in ('payment','refund','payout','deposit','chargeback','settlement')),
  internal_reference text,
  provider_reference text,
  expected_amount_paise bigint,
  provider_amount_paise bigint,
  currency char(3) not null default 'INR' check(currency='INR'),
  match_status text not null check (match_status in ('matched','amount_mismatch','missing_internal','missing_provider','status_mismatch','manual_review')),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.payment_reconciliation_runs enable row level security;
alter table public.payment_reconciliation_items enable row level security;
revoke all on public.payment_reconciliation_runs,public.payment_reconciliation_items from anon,authenticated;

create or replace function public.get_my_deposit_positions()
returns table(deposit_id uuid,booking_id uuid,status public.deposit_status,amount_paise bigint,
  locked_paise bigint,available_for_release_paise bigint,currency char(3),provider_reference text)
language sql stable security definer
set search_path=pg_catalog,public
as $$
  select d.id,d.booking_id,d.status,d.amount_paise,
    case when d.status in ('held_by_provider','claim_hold_pending','claim_hold','release_pending','refund_pending','partially_applied')
      then greatest(d.amount_paise-coalesce((select sum(l.amount_paise) from public.deposit_ledger l
        where l.deposit_id=d.id and l.event_type in ('released','amount_applied')),0),0)::bigint
      else 0::bigint end,
    case when d.status in ('held_by_provider','partially_applied') and b.status='completed'
      and exists(select 1 from public.booking_workflow_configuration c where c.id=true
        and c.deposit_claim_window_seconds is not null
        and b.completed_at+make_interval(secs=>c.deposit_claim_window_seconds)<=now())
      and not exists(select 1 from public.disputes x where x.booking_id=b.id and x.status<>'closed')
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

create or replace function public.configure_booking_deposit(
  p_booking_id uuid,p_provider text,p_amount_paise bigint,p_policy_version text,p_custody_descriptor text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_booking public.bookings%rowtype; v_approval public.payment_provider_approvals%rowtype;
  v_deposit uuid; v_actor uuid:=auth.uid();
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then
    if not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
      and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance approval required'; end if;
  end if;
  if p_amount_paise is null or p_amount_paise<=0 or length(btrim(coalesce(p_policy_version,'')))<3
    or length(btrim(coalesce(p_custody_descriptor,'')))<10 then raise exception 'Approved deposit amount, policy and custody disclosure are required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.status<>'owner_accepted' then raise exception 'Deposit must be configured before a payment attempt starts'; end if;
  if exists(select 1 from public.payments where booking_id=p_booking_id) then
    raise exception 'A payment attempt already exists; deposit policy cannot be changed after checkout begins';
  end if;
  if exists(select 1 from public.deposits where booking_id=p_booking_id) then raise exception 'Deposit already exists'; end if;
  select * into v_approval from public.payment_provider_approvals
    where provider_code=p_provider and enabled_for_rent and enabled_for_deposits
      and marketplace_model='peer_to_peer_physical_book_rental'
      and supports_deposit_hold and supports_deposit_release and supports_deposit_dispute_hold and supports_deposit_application
      and (expires_at is null or expires_at>now());
  if not found then raise exception 'Written provider, legal and accounting approval for this deposit model is required'; end if;
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
  if p_tax_paise<0 or length(btrim(coalesce(p_policy_version,'')))<3 or length(btrim(coalesce(p_calculation_reference,'')))<5 then
    raise exception 'A versioned, approved tax calculation is required'; end if;
  select * into v_cfg from public.booking_workflow_configuration where id=true and is_active for update;
  if not found or v_cfg.tax_policy_version<>p_policy_version or v_cfg.tax_approval_reference is null then
    raise exception 'Tax policy is not approved or no longer current'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.status not in ('owner_accepted','payment_pending') then raise exception 'Booking is no longer eligible for tax calculation'; end if;
  update public.bookings set tax_paise=p_tax_paise,total_due_paise=rent_subtotal_paise+platform_fee_paise+p_tax_paise,
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
  if least(p_tax_withheld_paise,p_provider_fee_paise)<0 or length(btrim(coalesce(p_policy_version,'')))<3 then
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

create or replace function public.request_deposit_release(p_deposit_id uuid,p_idempotency_key text)
returns uuid language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_user uuid:=auth.uid(); v_deposit public.deposits%rowtype; v_booking public.bookings%rowtype;
  v_request uuid; v_provider public.payment_provider_approvals%rowtype; v_released bigint; v_remaining bigint; v_window integer;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 or length(p_idempotency_key)>128 then raise exception 'Valid idempotency key required'; end if;
  select * into v_deposit from public.deposits where id=p_deposit_id for update;
  if not found or v_deposit.payer_id<>v_user or not v_deposit.feature_enabled_at_creation then raise exception 'Provider-held deposit not found'; end if;
  select id into v_request from public.deposit_release_requests where idempotency_key=p_idempotency_key;
  if v_request is not null then return v_request; end if;
  if v_deposit.status not in ('held_by_provider','partially_applied') then raise exception 'Deposit is not releasable'; end if;
  select * into v_booking from public.bookings where id=v_deposit.booking_id for update;
  select deposit_claim_window_seconds into v_window from public.booking_workflow_configuration where id=true and is_active;
  if v_booking.status<>'completed' or v_booking.completed_at is null or v_window is null
    or v_booking.completed_at+make_interval(secs=>v_window)>now() then raise exception 'Return closure or approved claim window is incomplete'; end if;
  if exists(select 1 from public.disputes x where x.booking_id=v_booking.id and x.status<>'closed')
    or exists(select 1 from public.deposit_claims x where x.deposit_id=v_deposit.id and x.status not in ('rejected','closed')) then raise exception 'Open dispute or claim blocks release'; end if;
  if exists(select 1 from public.bookings x where (x.reader_id=v_user or x.owner_id=v_user)
    and x.status::text in ('owner_accepted','payment_pending','confirmed','collection_pending','active','return_pending','disputed')) then
    raise exception 'Deposit release is blocked while this member has an active rental'; end if;
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
    values('deposit',v_deposit.id,'deposit_release_requested',jsonb_build_object('request_id',v_request,'amount_paise',v_remaining,'provider',v_deposit.provider),
      'deposit-release-outbox:'||p_idempotency_key) on conflict(idempotency_key) do nothing;
  return v_request;
end;
$$;
revoke all on function public.request_deposit_release(uuid,text) from public,anon;
grant execute on function public.request_deposit_release(uuid,text) to authenticated;

create or replace function public.apply_verified_refund_event(
  p_provider text,p_event_id text,p_refund_id uuid,p_event_type text,p_provider_refund_id text,
  p_amount_paise bigint,p_currency char(3),p_payload_sha256 text
) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_refund public.refunds%rowtype; v_payment public.payments%rowtype; v_sum bigint; v_count bigint; v_inserted bigint;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_event_id is null or p_payload_sha256 is null or p_payload_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'Invalid verified refund event'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256,provider_payment_reference)
    values((select payment_id from public.refunds where id=p_refund_id),p_provider,p_event_id,p_event_type,true,p_payload_sha256,p_provider_refund_id)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_inserted=row_count;
  if v_inserted=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_refund from public.refunds where id=p_refund_id and provider=p_provider for update;
  if not found or v_refund.amount_paise<>p_amount_paise or p_currency<>'INR'
    or (v_refund.provider_refund_id is not null and p_provider_refund_id is not null and v_refund.provider_refund_id<>p_provider_refund_id) then
    update public.payment_events set processing_status='dead_letter',processing_error_code='refund_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','refund_reference_or_amount_mismatch');
  end if;
  if p_event_type in ('refund.succeeded','refund.processed') then
    update public.refunds set status='succeeded',provider_refund_id=coalesce(provider_refund_id,p_provider_refund_id),completed_at=coalesce(completed_at,now())
      where id=p_refund_id;
  elsif p_event_type in ('refund.failed','refund.rejected') then
    update public.refunds set status='failed',provider_refund_id=coalesce(provider_refund_id,p_provider_refund_id) where id=p_refund_id;
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
set search_path=pg_catalog,public
as $$
declare v_payout public.payouts%rowtype; v_count bigint;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_event_id is null or p_payload_sha256 is null or p_payload_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'Invalid verified payout event'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256)
    values((select p.id from public.payments p join public.owner_earnings e on e.booking_id=p.booking_id
      join public.payouts x on x.owner_earning_id=e.id where x.id=p_payout_id limit 1),
      p_provider,p_event_id,p_event_type,true,p_payload_sha256) on conflict(provider,provider_event_id) do nothing;
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
    update public.payouts set status='paid',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),settled_at=coalesce(settled_at,now()) where id=p_payout_id;
    update public.owner_earnings set status='paid' where id=v_payout.owner_earning_id;
  elsif p_event_type in ('transfer.failed','payout.failed') then
    update public.payouts set status='failed',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),failure_code=p_event_type where id=p_payout_id;
    update public.owner_earnings set status='eligible' where id=v_payout.owner_earning_id;
  elsif p_event_type in ('transfer.reversed','payout.reversed') then
    update public.payouts set status='reversed',provider_transfer_id=coalesce(provider_transfer_id,p_provider_transfer_id),failure_code=p_event_type where id=p_payout_id;
    update public.owner_earnings set status='reconciliation_required' where id=v_payout.owner_earning_id;
  else
    update public.payment_events set processing_status='ignored_duplicate',processing_error_code='unsupported_payout_event',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',true,'ignored',true);
  end if;
  update public.payment_events set processing_status='processed',processed_at=now() where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'payout_status',(select status from public.payouts where id=p_payout_id));
end;
$$;
revoke all on function public.apply_verified_payout_event(text,text,uuid,text,text,bigint,char,text) from public,anon,authenticated;
grant execute on function public.apply_verified_payout_event(text,text,uuid,text,text,bigint,char,text) to service_role;

create or replace function public.apply_verified_deposit_event(
  p_provider text,p_event_id text,p_deposit_id uuid,p_event_type text,p_provider_reference text,
  p_amount_paise bigint,p_currency char(3),p_payload_sha256 text,p_claim_id uuid default null
) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_deposit public.deposits%rowtype; v_claim public.deposit_claims%rowtype; v_count bigint; v_inserted bigint; v_key text;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_event_id is null or p_payload_sha256 is null or p_payload_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'Invalid verified deposit event'; end if;
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
  elsif p_event_type in ('deposit.claim_held','deposit.dispute_hold') then
    if v_deposit.status not in ('held_by_provider','claim_hold_pending') then raise exception 'Deposit cannot be claim-held'; end if;
    select * into v_claim from public.deposit_claims where id=p_claim_id and deposit_id=p_deposit_id for update;
    if not found or v_claim.status<>'approved' or v_claim.decision_amount_paise<>p_amount_paise then raise exception 'Claim hold must match approved amount'; end if;
    update public.deposits set status='claim_hold' where id=p_deposit_id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,provider_reference,idempotency_key)
      values(p_deposit_id,'claim_held',p_amount_paise,p_provider_reference,v_key) on conflict(idempotency_key) do nothing;
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
revoke all on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid) from public,anon,authenticated;
grant execute on function public.apply_verified_deposit_event(text,text,uuid,text,text,bigint,char,text,uuid) to service_role;

create or replace function public.submit_deposit_claim(p_deposit_id uuid,p_amount_paise bigint,p_reason_code text,p_description text)
returns uuid language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_user uuid:=auth.uid(); v_deposit public.deposits%rowtype; v_booking public.bookings%rowtype; v_claim uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_amount_paise<=0 or length(btrim(coalesce(p_reason_code,'')))<3 or length(btrim(coalesce(p_description,'')))<20 then
    raise exception 'Provide claim amount, reason and evidence description'; end if;
  select * into v_deposit from public.deposits where id=p_deposit_id for update;
  if not found or not v_deposit.feature_enabled_at_creation or v_deposit.status not in ('held_by_provider','claim_hold') then
    raise exception 'Provider-confirmed deposit is not available for claim'; end if;
  select * into v_booking from public.bookings where id=v_deposit.booking_id for update;
  if v_booking.owner_id<>v_user or v_booking.status not in ('completed','disputed') then
    raise exception 'Only the lending owner can submit a post-return deposit claim'; end if;
  if p_amount_paise>v_deposit.amount_paise then raise exception 'Claim amount cannot exceed the confirmed deposit'; end if;
  if exists(select 1 from public.deposit_claims x where x.deposit_id=p_deposit_id and x.status not in ('rejected','closed')) then
    raise exception 'An active deposit claim already exists'; end if;
  insert into public.deposit_claims(deposit_id,booking_id,claimant_id,against_user_id,amount_requested_paise,reason_code,description)
  values(p_deposit_id,v_booking.id,v_user,v_booking.reader_id,p_amount_paise,left(p_reason_code,80),left(p_description,3000))
  returning id into v_claim;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(v_booking.id,v_user,'deposit_claim_submitted',jsonb_build_object('claim_id',v_claim,'amount_paise',p_amount_paise),'deposit-claim:'||v_claim::text);
  insert into public.notifications(user_id,channel,template_key,payload)
    values(v_booking.reader_id,'in_app','deposit.claim_submitted',jsonb_build_object('booking_id',v_booking.id,'claim_id',v_claim));
  return v_claim;
end;
$$;
revoke all on function public.submit_deposit_claim(uuid,bigint,text,text) from public,anon;
grant execute on function public.submit_deposit_claim(uuid,bigint,text,text) to authenticated;

create or replace function public.decide_deposit_claim(p_claim_id uuid,p_decision text,p_amount_paise bigint,p_reason text)
returns void language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.deposit_claims%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance reviewer permission required'; end if;
  if p_decision not in ('approve','reject') or length(btrim(coalesce(p_reason,'')))<10 then raise exception 'Decision reason required'; end if;
  select * into v_claim from public.deposit_claims where id=p_claim_id for update;
  if not found or v_claim.status not in ('submitted','under_review','needs_response') then raise exception 'Claim is not reviewable'; end if;
  if p_decision='approve' then
    if p_amount_paise is null or p_amount_paise<=0 or p_amount_paise>v_claim.amount_requested_paise then raise exception 'Approved amount exceeds claim'; end if;
    update public.deposit_claims set status='approved',decision_amount_paise=p_amount_paise,decision_reason=left(p_reason,2000),
      decided_by=v_actor,decided_at=now() where id=p_claim_id;
  else
    if p_amount_paise is not null and p_amount_paise<>0 then raise exception 'Rejected claim cannot apply an amount'; end if;
    update public.deposit_claims set status='rejected',decision_amount_paise=0,decision_reason=left(p_reason,2000),
      decided_by=v_actor,decided_at=now() where id=p_claim_id;
  end if;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,metadata,idempotency_key)
    values(v_claim.booking_id,v_actor,'deposit_claim_decided',jsonb_build_object('claim_id',p_claim_id,'decision',p_decision,
      'amount_paise',coalesce(p_amount_paise,0),'reason',left(p_reason,2000)),'deposit-claim-decision:'||p_claim_id::text);
end;
$$;
revoke all on function public.decide_deposit_claim(uuid,text,bigint,text) from public,anon;
grant execute on function public.decide_deposit_claim(uuid,text,bigint,text) to authenticated;

create or replace function public.request_deposit_claim_application(p_claim_id uuid,p_idempotency_key text)
returns uuid language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.deposit_claims%rowtype; v_deposit public.deposits%rowtype; v_event uuid;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('finance_operator','admin','super_admin')) then raise exception 'Finance reviewer permission required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 then raise exception 'Idempotency key required'; end if;
  select id into v_event from public.outbox_events where idempotency_key='deposit-claim-application:'||p_idempotency_key;
  if v_event is not null then return v_event; end if;
  select * into v_claim from public.deposit_claims where id=p_claim_id for update;
  if not found or v_claim.status<>'approved' or coalesce(v_claim.decision_amount_paise,0)<=0 then raise exception 'Approved reasoned claim required'; end if;
  select * into v_deposit from public.deposits where id=v_claim.deposit_id for update;
  if v_deposit.status not in ('held_by_provider','claim_hold') then raise exception 'Deposit is not in an eligible provider state'; end if;
  if not exists(select 1 from public.payment_provider_approvals p where p.provider_code=v_deposit.provider
    and p.enabled_for_deposits and p.supports_deposit_application and p.supports_deposit_dispute_hold
    and p.legal_approval_reference is not null) then raise exception 'Provider/legal approval is not active'; end if;
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('deposit',v_deposit.id,'deposit_claim_application_requested',
      jsonb_build_object('deposit_id',v_deposit.id,'claim_id',p_claim_id,'amount_paise',v_claim.decision_amount_paise,'provider',v_deposit.provider),
      'deposit-claim-application:'||p_idempotency_key) returning id into v_event;
  update public.deposits set status='claim_hold_pending' where id=v_deposit.id;
  insert into public.deposit_ledger(deposit_id,event_type,amount_paise,idempotency_key,metadata)
    values(v_deposit.id,'claim_hold_requested',v_claim.decision_amount_paise,'deposit-claim-hold:'||p_idempotency_key,
      jsonb_build_object('claim_id',p_claim_id));
  return v_event;
end;
$$;
revoke all on function public.request_deposit_claim_application(uuid,text) from public,anon;
grant execute on function public.request_deposit_claim_application(uuid,text) to authenticated;

create or replace function public.record_provider_reconciliation(
  p_provider text,p_report_reference text,p_period_start timestamptz,p_period_end timestamptz,p_records jsonb
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_run uuid; v_record jsonb; v_type text; v_internal text; v_ref text;
  v_expected bigint; v_actual bigint; v_currency char(3); v_status text; v_matched integer:=0; v_unmatched integer:=0;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_period_start is null or p_period_end is null or p_period_end<=p_period_start
    or p_records is null or jsonb_typeof(p_records)<>'array' or jsonb_array_length(p_records)>10000 then
    raise exception 'Invalid reconciliation report'; end if;
  if not exists(select 1 from public.payment_provider_approvals p where p.provider_code=p_provider
    and p.supports_reconciliation and (p.expires_at is null or p.expires_at>now())) then raise exception 'Provider reconciliation is not approved'; end if;
  insert into public.payment_reconciliation_runs(provider,report_reference,period_start,period_end,status)
    values(p_provider,left(p_report_reference,200),p_period_start,p_period_end,'started') returning id into v_run;
  for v_record in select value from jsonb_array_elements(p_records) loop
    v_type:=v_record->>'recordType'; v_ref:=nullif(v_record->>'providerReference','');
    v_actual:=nullif(v_record->>'amountPaise','')::bigint; v_currency:=coalesce(v_record->>'currency','INR')::char(3);
    v_status:=nullif(v_record->>'status',''); v_internal:=nullif(v_record->>'internalReference','');
    v_expected:=nullif(v_record->>'expectedAmountPaise','')::bigint;
    if v_type is null or v_type not in ('payment','refund','payout','deposit','chargeback','settlement') or v_currency<>'INR' then
      raise exception 'Unsupported reconciliation record'; end if;
    if v_type='payment' and v_ref is not null then
      select p.id::text,p.amount_paise into v_internal,v_expected from public.payments p
        where p.provider=p_provider and (p.provider_payment_id=v_ref or p.merchant_reference=v_ref) limit 1;
    elsif v_type='refund' and v_ref is not null then
      select r.id::text,r.amount_paise into v_internal,v_expected from public.refunds r
        where r.provider=p_provider and r.provider_refund_id=v_ref limit 1;
    elsif v_type='payout' and v_ref is not null then
      select p.id::text,p.amount_paise into v_internal,v_expected from public.payouts p
        where p.provider=p_provider and p.provider_transfer_id=v_ref limit 1;
    elsif v_type='deposit' and v_ref is not null then
      select d.id::text,d.amount_paise into v_internal,v_expected from public.deposits d
        where d.provider=p_provider and d.provider_reference=v_ref limit 1;
    end if;
    insert into public.payment_reconciliation_items(run_id,record_type,internal_reference,provider_reference,
      expected_amount_paise,provider_amount_paise,currency,match_status,details)
    values(v_run,v_type,v_internal,v_ref,v_expected,v_actual,v_currency,
      case when v_internal is null then 'missing_internal' when v_actual is null then 'missing_provider'
        when v_expected is distinct from v_actual then 'amount_mismatch' else 'manual_review' end,
      jsonb_build_object('provider_status',v_status,'source','provider_adapter'));
    if v_internal is not null and v_actual is not null and v_expected=v_actual then v_matched:=v_matched+1; else v_unmatched:=v_unmatched+1; end if;
  end loop;
  update public.payment_reconciliation_runs set matched_count=v_matched,unmatched_count=v_unmatched,
    status=case when v_unmatched=0 then 'completed' else 'partial' end,completed_at=now() where id=v_run;
  return v_run;
end;
$$;
revoke all on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) to service_role;

create or replace function public.attach_refund_provider_reference(p_refund_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path=pg_catalog,public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.refunds set provider_refund_id=p_provider_reference,status='pending'
    where id=p_refund_id and status in ('requested','pending');
  if not found then raise exception 'Refund reference cannot be attached'; end if;
end;
$$;
revoke all on function public.attach_refund_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_refund_provider_reference(uuid,text) to service_role;

create or replace function public.attach_payout_provider_reference(p_payout_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path=pg_catalog,public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.payouts set provider_transfer_id=p_provider_reference,status='processing',initiated_at=coalesce(initiated_at,now())
    where id=p_payout_id and status in ('pending','processing');
  if not found then raise exception 'Payout reference cannot be attached'; end if;
end;
$$;
revoke all on function public.attach_payout_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_payout_provider_reference(uuid,text) to service_role;

create or replace function public.attach_deposit_provider_reference(p_deposit_id uuid,p_provider_reference text)
returns void language plpgsql security definer
set search_path=pg_catalog,public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  update public.deposits set provider_reference=p_provider_reference
    where id=p_deposit_id and feature_enabled_at_creation and status='collection_pending';
  if not found then raise exception 'Deposit reference cannot be attached'; end if;
end;
$$;
revoke all on function public.attach_deposit_provider_reference(uuid,text) from public,anon,authenticated;
grant execute on function public.attach_deposit_provider_reference(uuid,text) to service_role;

create or replace function private.reject_deposit_ledger_mutation()
returns trigger language plpgsql set search_path=pg_catalog
as $$ begin raise exception 'Deposit ledger is append-only'; end; $$;
drop trigger if exists deposit_ledger_append_only on public.deposit_ledger;
create trigger deposit_ledger_append_only before update or delete on public.deposit_ledger
for each row execute function private.reject_deposit_ledger_mutation();

revoke insert,update,delete on public.booking_audit_events,public.payment_disputes,public.deposit_claims,
  public.payment_reconciliation_runs,public.payment_reconciliation_items from anon,authenticated;
revoke all on public.payments,public.payment_events,public.deposits,public.deposit_ledger,public.deposit_release_requests,
  public.refunds,public.owner_earnings,public.payouts,public.commission_ledger from anon,authenticated;

commit;

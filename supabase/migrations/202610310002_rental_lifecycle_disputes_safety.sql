begin;

-- Rental operations policy: inactive until the product/legal/finance owner approves it.
create table public.rental_operation_policy (
  id boolean primary key default true check (id),
  policy_version text not null,
  is_active boolean not null default false,
  grace_period_hours integer not null default 24 check (grace_period_hours between 0 and 168),
  reminder_hours_before integer[] not null default array[72,24,0],
  no_show_report_window_hours integer not null default 24 check (no_show_report_window_hours between 1 and 168),
  claim_response_hours integer not null default 48 check (claim_response_hours between 12 and 720),
  appeal_window_hours integer not null default 72 check (appeal_window_hours between 12 and 720),
  return_inspection_hours integer not null default 48 check (return_inspection_hours between 1 and 720),
  extensions_enabled boolean not null default false,
  zero_fee_extensions_enabled boolean not null default false,
  rescheduling_enabled boolean not null default false,
  max_reschedules integer not null default 1 check (max_reschedules between 0 and 5),
  reschedule_cutoff_hours integer not null default 24 check (reschedule_cutoff_hours between 0 and 720),
  late_fee_enabled boolean not null default false,
  late_fee_daily_paise bigint,
  late_fee_max_paise bigint,
  late_fee_legal_approval_reference text,
  late_fee_accounting_approval_reference text,
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  updated_at timestamptz not null default now(),
  check (array_position(reminder_hours_before, null) is null),
  check (not zero_fee_extensions_enabled or extensions_enabled),
  check (not late_fee_enabled or (
    late_fee_daily_paise is not null and late_fee_max_paise is not null
    and late_fee_daily_paise > 0 and late_fee_max_paise >= late_fee_daily_paise
    and length(btrim(coalesce(late_fee_legal_approval_reference,''))) >= 5
    and length(btrim(coalesce(late_fee_accounting_approval_reference,''))) >= 5
    and approved_by is not null and approved_at is not null
  )),
  check (not is_active or (approved_by is not null and approved_at is not null))
);
insert into public.rental_operation_policy(id,policy_version)
values (true,'rental_ops_v1')
on conflict (id) do nothing;
alter table public.rental_operation_policy enable row level security;

create table public.rental_lifecycle (
  booking_id uuid primary key references public.bookings(id) on delete restrict,
  lifecycle_status text not null default 'requested'
    check (lifecycle_status in ('requested','scheduled','active','due','overdue','return_requested','returned','completed','cancelled','disputed')),
  rental_started_at timestamptz,
  due_at timestamptz,
  grace_ends_at timestamptz,
  overdue_since timestamptz,
  return_requested_at timestamptz,
  returned_at timestamptz,
  closed_at timestamptz,
  reschedule_count integer not null default 0 check (reschedule_count between 0 and 5),
  last_reminder_at timestamptz,
  updated_at timestamptz not null default now()
);
create index rental_lifecycle_due_idx on public.rental_lifecycle(due_at, lifecycle_status)
  where lifecycle_status in ('active','due','overdue','return_requested');

create table public.rental_operations_events (
  id bigint generated always as identity primary key,
  booking_id uuid not null references public.bookings(id) on delete restrict,
  actor_id uuid references auth.users(id) on delete restrict,
  event_type text not null,
  from_state text,
  to_state text,
  reason_code text,
  details jsonb not null default '{}'::jsonb,
  idempotency_key text not null unique,
  created_at timestamptz not null default now()
);
create index rental_operations_events_booking_idx
  on public.rental_operations_events(booking_id,created_at desc);

create table public.rental_notification_log (
  id bigint generated always as identity primary key,
  booking_id uuid not null references public.bookings(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  notification_key text not null,
  notification_id uuid references public.notifications(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(booking_id,user_id,notification_key)
);

create table public.rental_extension_requests (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete restrict,
  requested_by uuid not null references auth.users(id) on delete restrict,
  requested_due_at timestamptz not null,
  previous_due_at timestamptz not null,
  reason text not null,
  status text not null default 'requested'
    check (status in ('requested','approved_zero_fee','approved_pending_payment','rejected','cancelled','expired')),
  decision_by uuid references auth.users(id) on delete restrict,
  decision_reason text,
  decided_at timestamptz,
  idempotency_key text not null unique,
  created_at timestamptz not null default now(),
  check (requested_due_at > previous_due_at)
);
create index rental_extension_requests_booking_idx
  on public.rental_extension_requests(booking_id,created_at desc);
create unique index rental_extension_one_open_per_booking_uq
  on public.rental_extension_requests(booking_id)
  where status in ('requested','approved_pending_payment');

create table public.rental_reschedule_requests (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete restrict,
  requested_by uuid not null references auth.users(id) on delete restrict,
  previous_start_at timestamptz not null,
  previous_end_at timestamptz not null,
  new_start_at timestamptz not null,
  new_end_at timestamptz not null,
  reason text not null,
  status text not null default 'requested'
    check (status in ('requested','approved','rejected','cancelled','conflict')),
  decision_by uuid references auth.users(id) on delete restrict,
  decision_reason text,
  decided_at timestamptz,
  idempotency_key text not null unique,
  created_at timestamptz not null default now(),
  check (new_end_at > new_start_at),
  check (previous_end_at - previous_start_at = new_end_at - new_start_at)
);
create index rental_reschedule_requests_booking_idx
  on public.rental_reschedule_requests(booking_id,created_at desc);
create unique index rental_reschedule_one_open_per_booking_uq
  on public.rental_reschedule_requests(booking_id) where status='requested';

create table public.rental_cancellation_requests (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete restrict,
  requested_by uuid not null references auth.users(id) on delete restrict,
  reason_code text not null,
  description text not null,
  status text not null default 'requested'
    check (status in ('requested','cancelled_without_capture','refund_review_required','resolved','rejected')),
  payment_captured boolean not null default false,
  policy_version text,
  created_at timestamptz not null default now(),
  idempotency_key text not null unique
);
create unique index rental_cancellation_one_open_per_booking_uq
  on public.rental_cancellation_requests(booking_id)
  where status in ('requested','refund_review_required');

create table public.rental_damage_claims (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete restrict,
  dispute_id uuid references public.disputes(id) on delete restrict,
  claimant_id uuid not null references auth.users(id) on delete restrict,
  respondent_id uuid not null references auth.users(id) on delete restrict,
  claim_category text not null check (claim_category in (
    'minor_damage','major_damage','missing_pages','water_damage','lost_book',
    'non_return','wrong_book_returned'
  )),
  description text not null,
  requested_compensation_paise bigint not null default 0 check (requested_compensation_paise >= 0),
  approved_compensation_paise bigint not null default 0 check (approved_compensation_paise >= 0),
  status text not null default 'submitted'
    check (status in ('submitted','awaiting_response','under_review','approved','partially_approved','rejected','appealed','closed')),
  response_due_at timestamptz,
  decision_by uuid references auth.users(id) on delete restrict,
  decision_code text,
  decision_reason text,
  decided_at timestamptz,
  policy_version text not null,
  created_at timestamptz not null default now(),
  check (claimant_id <> respondent_id),
  check (approved_compensation_paise <= requested_compensation_paise)
);
create index rental_damage_claims_booking_idx
  on public.rental_damage_claims(booking_id,created_at desc);

create table public.rental_case_messages (
  id uuid primary key default gen_random_uuid(),
  case_type text not null check (case_type in ('claim','dispute','appeal')),
  case_id uuid not null,
  booking_id uuid not null references public.bookings(id) on delete restrict,
  sender_id uuid not null references auth.users(id) on delete restrict,
  body text not null check (length(btrim(body)) between 1 and 5000),
  created_at timestamptz not null default now()
);
create index rental_case_messages_case_idx
  on public.rental_case_messages(case_type,case_id,created_at);

create table public.rental_case_evidence (
  id uuid primary key default gen_random_uuid(),
  case_type text not null check (case_type in ('claim','dispute')),
  case_id uuid not null,
  booking_id uuid not null references public.bookings(id) on delete restrict,
  submitted_by uuid not null references auth.users(id) on delete restrict,
  object_key text not null,
  evidence_type text not null,
  description text,
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  unique(object_key)
);
create index rental_case_evidence_case_idx
  on public.rental_case_evidence(case_type,case_id,created_at);

create table public.rental_appeals (
  id uuid primary key default gen_random_uuid(),
  case_type text not null check (case_type in ('claim','dispute')),
  case_id uuid not null,
  booking_id uuid not null references public.bookings(id) on delete restrict,
  appellant_id uuid not null references auth.users(id) on delete restrict,
  grounds text not null check (length(btrim(grounds)) between 20 and 4000),
  status text not null default 'submitted'
    check (status in ('submitted','under_review','upheld','revised','dismissed')),
  reviewer_id uuid references auth.users(id) on delete restrict,
  decision_code text,
  decision_reason text,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  unique(case_type,case_id,appellant_id)
);
create index rental_appeals_booking_idx on public.rental_appeals(booking_id,created_at desc);

create table public.rental_safety_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete restrict,
  target_type text not null check (target_type in ('user','book_copy','booking','handover_location')),
  target_id uuid not null,
  reported_user_id uuid references auth.users(id) on delete restrict,
  booking_id uuid references public.bookings(id) on delete restrict,
  report_type text not null check (report_type in (
    'unsafe_handover','harassment','threat','physical_safety','fraud','listing_misrepresentation','other'
  )),
  description text not null check (length(btrim(description)) between 10 and 4000),
  severity text not null default 'medium' check (severity in ('low','medium','high','critical')),
  status text not null default 'open' check (status in ('open','triaged','investigating','actioned','dismissed','closed')),
  assigned_to uuid references auth.users(id) on delete restrict,
  resolution_code text,
  resolution_reason text,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  check (reported_user_id is null or reported_user_id <> reporter_id)
);
create index rental_safety_reports_open_idx
  on public.rental_safety_reports(severity,created_at) where status in ('open','triaged','investigating');

create table public.chat_mutes (
  conversation_id uuid not null references public.chat_conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  muted_until timestamptz,
  reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(conversation_id,user_id)
);

create table public.user_suspensions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  previous_status public.account_status not null,
  new_status public.account_status not null,
  reason_code text not null,
  reason text not null,
  effective_at timestamptz not null default now(),
  expires_at timestamptz,
  actor_id uuid not null references auth.users(id) on delete restrict,
  active_rentals_preserved integer not null default 0,
  created_at timestamptz not null default now(),
  check (new_status in ('restricted','suspended','active')),
  check (expires_at is null or expires_at > effective_at)
);
create index user_suspensions_user_idx on public.user_suspensions(user_id,created_at desc);

alter table public.late_fees add column if not exists billing_day date;
alter table public.late_fees add column if not exists assessment_idempotency_key text;
create unique index if not exists late_fees_booking_day_uq
  on public.late_fees(booking_id,billing_day) where billing_day is not null;
create unique index if not exists late_fees_assessment_key_uq
  on public.late_fees(assessment_idempotency_key) where assessment_idempotency_key is not null;

-- Synchronise the new rental lifecycle projection with the authoritative booking.
create or replace function private.sync_rental_lifecycle()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_status text;
  v_grace integer := 24;
  v_old text;
begin
  select grace_period_hours into v_grace
  from public.rental_operation_policy where id=true;
  v_status := case new.status::text
    when 'requested' then 'requested'
    when 'owner_accepted' then 'scheduled'
    when 'payment_pending' then 'scheduled'
    when 'confirmed' then 'scheduled'
    when 'collection_pending' then 'scheduled'
    when 'active' then 'active'
    when 'return_pending' then 'return_requested'
    when 'completed' then 'completed'
    when 'cancelled' then 'cancelled'
    when 'expired' then 'cancelled'
    when 'disputed' then 'disputed'
    else 'scheduled'
  end;
  select lifecycle_status into v_old from public.rental_lifecycle where booking_id=new.id;
  insert into public.rental_lifecycle(
    booking_id,lifecycle_status,rental_started_at,due_at,grace_ends_at,
    return_requested_at,returned_at,closed_at,updated_at
  ) values (
    new.id,v_status,new.rental_start_at,new.rental_due_at,
    case when new.rental_due_at is not null then new.rental_due_at + make_interval(hours=>coalesce(v_grace,24)) end,
    case when new.status::text='return_pending' then now() end,
    case when new.status::text='completed' then coalesce(new.completed_at,now()) end,
    case when new.status::text in ('completed','cancelled','expired') then coalesce(new.completed_at,now()) end,
    now()
  )
  on conflict(booking_id) do update set
    lifecycle_status=excluded.lifecycle_status,
    rental_started_at=coalesce(excluded.rental_started_at,public.rental_lifecycle.rental_started_at),
    due_at=coalesce(excluded.due_at,public.rental_lifecycle.due_at),
    grace_ends_at=coalesce(excluded.grace_ends_at,public.rental_lifecycle.grace_ends_at),
    return_requested_at=coalesce(excluded.return_requested_at,public.rental_lifecycle.return_requested_at),
    returned_at=coalesce(excluded.returned_at,public.rental_lifecycle.returned_at),
    closed_at=coalesce(excluded.closed_at,public.rental_lifecycle.closed_at),
    updated_at=now();

  if v_old is distinct from v_status then
    insert into public.rental_operations_events(booking_id,event_type,from_state,to_state,details,idempotency_key)
    values(new.id,'booking_status_synchronised',v_old,v_status,
      jsonb_build_object('booking_status',new.status::text,'due_at',new.rental_due_at),
      'rental-sync:'||new.id::text||':'||new.status::text||':'||coalesce(extract(epoch from new.updated_at)::bigint,0)::text)
    on conflict(idempotency_key) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists bookings_sync_rental_lifecycle on public.bookings;
create trigger bookings_sync_rental_lifecycle
after insert or update of status,rental_start_at,rental_due_at,completed_at on public.bookings
for each row execute function private.sync_rental_lifecycle();

-- Existing bookings predate this projection; backfill them without inventing a financial state.
insert into public.rental_lifecycle(booking_id,lifecycle_status,rental_started_at,due_at,grace_ends_at,updated_at)
select b.id,
  case b.status::text
    when 'requested' then 'requested'
    when 'owner_accepted' then 'scheduled'
    when 'payment_pending' then 'scheduled'
    when 'confirmed' then 'scheduled'
    when 'collection_pending' then 'scheduled'
    when 'active' then 'active'
    when 'return_pending' then 'return_requested'
    when 'completed' then 'completed'
    when 'cancelled' then 'cancelled'
    when 'expired' then 'cancelled'
    when 'disputed' then 'disputed'
    else 'scheduled'
  end,
  b.rental_start_at,b.rental_due_at,
  case when b.rental_due_at is not null then b.rental_due_at + interval '24 hours' end,
  now()
from public.bookings b
on conflict(booking_id) do nothing;

-- Append-only lifecycle history and evidence references.
create or replace function private.reject_rental_ops_mutation()
returns trigger language plpgsql set search_path = pg_catalog
as $$ begin raise exception 'Rental operation and evidence history is append-only'; end; $$;
create trigger rental_operations_events_append_only before update or delete on public.rental_operations_events
for each row execute function private.reject_rental_ops_mutation();
create trigger rental_case_evidence_append_only before update or delete on public.rental_case_evidence
for each row execute function private.reject_rental_ops_mutation();
create trigger rental_case_messages_append_only before update or delete on public.rental_case_messages
for each row execute function private.reject_rental_ops_mutation();

-- Active-rental dashboard: only records where the caller is a booking participant.
create or replace function public.get_my_active_rentals()
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare v_user uuid:=auth.uid(); v_rows jsonb;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select coalesce(jsonb_agg(x order by (x->>'due_at') asc),'[]'::jsonb) into v_rows
  from (
    select jsonb_build_object(
      'booking_id',b.id,'booking_number',b.booking_number,'booking_status',b.status::text,
      'lifecycle_status',rl.lifecycle_status,'is_reader',b.reader_id=v_user,
      'reader_id',b.reader_id,'owner_id',b.owner_id,
      'title',t.title,'authors',t.authors,'copy_id',c.id,
      'rental_started_at',rl.rental_started_at,'due_at',rl.due_at,
      'grace_ends_at',rl.grace_ends_at,'overdue_since',rl.overdue_since,
      'return_requested_at',rl.return_requested_at,'returned_at',rl.returned_at,
      'city_id',b.city_id,'handover_location_id',b.requested_handover_location_id,
      'created_at',b.created_at
    ) x
    from public.bookings b
    join public.rental_lifecycle rl on rl.booking_id=b.id
    left join public.book_copies c on c.id=b.requested_copy_id
    left join public.book_titles t on t.id=c.book_title_id
    where (b.reader_id=v_user or b.owner_id=v_user)
      and b.status in ('confirmed','collection_pending','active','return_pending','disputed')
  ) q;
  return v_rows;
end;
$$;
revoke all on function public.get_my_active_rentals() from public,anon;
grant execute on function public.get_my_active_rentals() to authenticated;

create or replace function public.request_rental_early_return(
  p_booking_id uuid,p_reason text,p_idempotency_key text
) returns void language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_user uuid:=auth.uid(); v_booking public.bookings%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if length(btrim(coalesce(p_reason,'')))<5 or length(coalesce(p_idempotency_key,''))<16 then
    raise exception 'Reason and idempotency key are required';
  end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.reader_id<>v_user then raise exception 'Only the Reader may request an early return'; end if;
  if v_booking.status not in ('active','disputed') then raise exception 'Only an active rental can be returned early'; end if;
  update public.bookings set status='return_pending' where id=p_booking_id;
  insert into public.rental_operations_events(booking_id,actor_id,event_type,from_state,to_state,reason_code,details,idempotency_key)
  values(p_booking_id,v_user,'early_return_requested',v_booking.status::text,'return_pending','reader_requested',
    jsonb_build_object('reason',left(p_reason,1000)),'early-return:'||p_idempotency_key)
  on conflict(idempotency_key) do nothing;
  insert into public.notifications(user_id,channel,template_key,payload)
  values(v_booking.owner_id,'in_app','rental.early_return_requested',jsonb_build_object('booking_id',p_booking_id));
end;
$$;
revoke all on function public.request_rental_early_return(uuid,text,text) from public,anon;
grant execute on function public.request_rental_early_return(uuid,text,text) to authenticated;

create or replace function public.request_rental_extension(
  p_booking_id uuid,p_requested_due_at timestamptz,p_reason text,p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_user uuid:=auth.uid(); v_booking public.bookings%rowtype; v_cfg public.rental_operation_policy%rowtype; v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if length(coalesce(p_idempotency_key,''))<16 or length(btrim(coalesce(p_reason,'')))<5 then raise exception 'Reason and idempotency key are required'; end if;
  select id into v_id from public.rental_extension_requests where idempotency_key=p_idempotency_key;
  if v_id is not null then return v_id; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.reader_id<>v_user then raise exception 'Only the Reader may request an extension'; end if;
  if v_booking.status<>'active' or v_booking.rental_due_at is null then raise exception 'Only an active rental can be extended'; end if;
  select * into v_cfg from public.rental_operation_policy where id=true and is_active and extensions_enabled;
  if not found then raise exception 'Rental extensions are not enabled under an approved policy'; end if;
  if now()>=v_booking.rental_due_at then raise exception 'Extension must be requested before the original due date'; end if;
  if p_requested_due_at<=v_booking.rental_due_at or p_requested_due_at>v_booking.rental_due_at+interval '90 days' then
    raise exception 'Requested due date must extend the current due date by no more than 90 days';
  end if;
  insert into public.rental_extension_requests(
    booking_id,requested_by,requested_due_at,previous_due_at,reason,idempotency_key
  ) values (
    p_booking_id,v_user,p_requested_due_at,v_booking.rental_due_at,left(p_reason,1000),p_idempotency_key
  ) on conflict(idempotency_key) do update set idempotency_key=excluded.idempotency_key
  returning id into v_id;
  insert into public.notifications(user_id,channel,template_key,payload)
  values(v_booking.owner_id,'in_app','rental.extension_requested',jsonb_build_object('booking_id',p_booking_id,'request_id',v_id,'requested_due_at',p_requested_due_at));
  insert into public.rental_operations_events(booking_id,actor_id,event_type,from_state,to_state,details,idempotency_key)
  values(p_booking_id,v_user,'extension_requested','active','extension_pending',
    jsonb_build_object('request_id',v_id,'new_due_at',p_requested_due_at),'extension-request:'||p_idempotency_key)
  on conflict(idempotency_key) do nothing;
  return v_id;
end;
$$;
revoke all on function public.request_rental_extension(uuid,timestamptz,text,text) from public,anon;
grant execute on function public.request_rental_extension(uuid,timestamptz,text,text) to authenticated;

create or replace function public.respond_rental_extension(
  p_request_id uuid,p_approve boolean,p_reason text
) returns text language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_user uuid:=auth.uid(); v_req public.rental_extension_requests%rowtype; v_booking public.bookings%rowtype;
  v_cfg public.rental_operation_policy%rowtype; v_item public.rental_items%rowtype; v_res public.copy_reservations%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if length(btrim(coalesce(p_reason,'')))<5 then raise exception 'Decision reason is required'; end if;
  select * into v_req from public.rental_extension_requests where id=p_request_id for update;
  if not found then raise exception 'Extension request not found'; end if;
  select * into v_booking from public.bookings where id=v_req.booking_id for update;
  if v_booking.owner_id<>v_user or v_req.status<>'requested' then raise exception 'Only the Owner may decide a pending request'; end if;
  select * into v_cfg from public.rental_operation_policy where id=true and is_active;
  if not found then raise exception 'Approved rental operations policy is required'; end if;
  if not p_approve then
    update public.rental_extension_requests set status='rejected',decision_by=v_user,decision_reason=left(p_reason,1000),decided_at=now() where id=p_request_id;
    insert into public.notifications(user_id,channel,template_key,payload)
    values(v_req.requested_by,'in_app','rental.extension_rejected',jsonb_build_object('booking_id',v_booking.id,'request_id',p_request_id,'reason',left(p_reason,300)));
    return 'rejected';
  end if;
  if not v_cfg.zero_fee_extensions_enabled then
    update public.rental_extension_requests set status='approved_pending_payment',decision_by=v_user,
      decision_reason=left(p_reason,1000),decided_at=now() where id=p_request_id;
    insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('rental_extension',p_request_id,'extension_requires_pricing_and_payment',
      jsonb_build_object('booking_id',v_booking.id,'requested_due_at',v_req.requested_due_at),
      'extension-payment-gate:'||p_request_id::text) on conflict(idempotency_key) do nothing;
    return 'approved_pending_payment';
  end if;
  select * into v_item from public.rental_items where booking_id=v_booking.id limit 1;
  select * into v_res from public.copy_reservations where booking_id=v_booking.id and status='in_use' for update;
  if not found then raise exception 'Active inventory reservation not found'; end if;
  begin
    update public.copy_reservations
    set reserved_period=tstzrange(lower(v_res.reserved_period),v_req.requested_due_at+v_item.buffer_after,'[)')
    where id=v_res.id;
    update public.rental_items
    set reserved_period=tstzrange(lower(v_item.reserved_period),v_req.requested_due_at+v_item.buffer_after,'[)')
    where id=v_item.id;
  exception when exclusion_violation then
    raise exception 'The requested extension conflicts with another reservation';
  end;
  update public.bookings set rental_due_at=v_req.requested_due_at,requested_end_at=v_req.requested_due_at where id=v_booking.id;
  update public.rental_extension_requests set status='approved_zero_fee',decision_by=v_user,
    decision_reason=left(p_reason,1000),decided_at=now() where id=p_request_id;
  insert into public.rental_operations_events(booking_id,actor_id,event_type,from_state,to_state,details,idempotency_key)
  values(v_booking.id,v_user,'extension_approved','active','active',
    jsonb_build_object('request_id',p_request_id,'new_due_at',v_req.requested_due_at,'fee_paise',0),
    'extension-approved:'||p_request_id::text);
  insert into public.notifications(user_id,channel,template_key,payload)
  values(v_req.requested_by,'in_app','rental.extension_approved',jsonb_build_object('booking_id',v_booking.id,'new_due_at',v_req.requested_due_at));
  return 'approved_zero_fee';
end;
$$;
revoke all on function public.respond_rental_extension(uuid,boolean,text) from public,anon;
grant execute on function public.respond_rental_extension(uuid,boolean,text) to authenticated;

create or replace function public.request_rental_reschedule(
  p_booking_id uuid,p_new_start_at timestamptz,p_new_end_at timestamptz,p_reason text,p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_user uuid:=auth.uid(); v_booking public.bookings%rowtype; v_cfg public.rental_operation_policy%rowtype; v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if length(coalesce(p_idempotency_key,''))<16 or length(btrim(coalesce(p_reason,'')))<5 then raise exception 'Reason and idempotency key are required'; end if;
  select id into v_id from public.rental_reschedule_requests where idempotency_key=p_idempotency_key;
  if v_id is not null then return v_id; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.reader_id<>v_user then raise exception 'Only the Reader may request rescheduling'; end if;
  if v_booking.status not in ('owner_accepted','payment_pending','confirmed') then raise exception 'Rescheduling is available only before collection'; end if;
  select * into v_cfg from public.rental_operation_policy where id=true and is_active and rescheduling_enabled;
  if not found then raise exception 'Rescheduling is not enabled under an approved policy'; end if;
  if now()+make_interval(hours=>v_cfg.reschedule_cutoff_hours)>v_booking.requested_start_at then
    raise exception 'The rescheduling cutoff has passed';
  end if;
  if p_new_start_at<=now() or p_new_end_at<=p_new_start_at or
    p_new_end_at-p_new_start_at<>v_booking.requested_end_at-v_booking.requested_start_at then
    raise exception 'New dates must be future dates with the same rental duration';
  end if;
  if (select reschedule_count from public.rental_lifecycle where booking_id=p_booking_id)>=v_cfg.max_reschedules then
    raise exception 'Maximum reschedule count reached';
  end if;
  insert into public.rental_reschedule_requests(
    booking_id,requested_by,previous_start_at,previous_end_at,new_start_at,new_end_at,reason,idempotency_key
  ) values(p_booking_id,v_user,v_booking.requested_start_at,v_booking.requested_end_at,p_new_start_at,p_new_end_at,left(p_reason,1000),p_idempotency_key)
  returning id into v_id;
  insert into public.notifications(user_id,channel,template_key,payload)
  values(v_booking.owner_id,'in_app','rental.reschedule_requested',jsonb_build_object('booking_id',p_booking_id,'request_id',v_id,'new_start_at',p_new_start_at,'new_end_at',p_new_end_at));
  return v_id;
end;
$$;
revoke all on function public.request_rental_reschedule(uuid,timestamptz,timestamptz,text,text) from public,anon;
grant execute on function public.request_rental_reschedule(uuid,timestamptz,timestamptz,text,text) to authenticated;

create or replace function public.respond_rental_reschedule(
  p_request_id uuid,p_approve boolean,p_reason text
) returns text language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_user uuid:=auth.uid(); v_req public.rental_reschedule_requests%rowtype; v_booking public.bookings%rowtype;
  v_item public.rental_items%rowtype; v_res public.copy_reservations%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if length(btrim(coalesce(p_reason,'')))<5 then raise exception 'Decision reason is required'; end if;
  select * into v_req from public.rental_reschedule_requests where id=p_request_id for update;
  if not found or v_req.status<>'requested' then raise exception 'Pending reschedule request not found'; end if;
  select * into v_booking from public.bookings where id=v_req.booking_id for update;
  if v_booking.owner_id<>v_user then raise exception 'Only the Owner may decide a reschedule request'; end if;
  if not p_approve then
    update public.rental_reschedule_requests set status='rejected',decision_by=v_user,decision_reason=left(p_reason,1000),decided_at=now()
    where id=p_request_id;
    insert into public.notifications(user_id,channel,template_key,payload)
    values(v_req.requested_by,'in_app','rental.reschedule_rejected',jsonb_build_object('booking_id',v_booking.id,'reason',left(p_reason,300)));
    return 'rejected';
  end if;
  select * into v_item from public.rental_items where booking_id=v_booking.id limit 1;
  select * into v_res from public.copy_reservations where booking_id=v_booking.id and status in ('hold','confirmed') for update;
  begin
    if found then
      update public.copy_reservations
        set reserved_period=tstzrange(v_req.new_start_at-v_item.buffer_before,v_req.new_end_at+v_item.buffer_after,'[)')
        where id=v_res.id;
    end if;
    update public.rental_items set reserved_period=tstzrange(v_req.new_start_at-v_item.buffer_before,v_req.new_end_at+v_item.buffer_after,'[)')
      where id=v_item.id;
  exception when exclusion_violation then
    update public.rental_reschedule_requests set status='conflict',decision_by=v_user,decision_reason='Inventory conflict',decided_at=now()
      where id=p_request_id;
    return 'conflict';
  end;
  update public.bookings set requested_start_at=v_req.new_start_at,requested_end_at=v_req.new_end_at
    where id=v_booking.id;
  update public.rental_lifecycle set reschedule_count=reschedule_count+1,updated_at=now() where booking_id=v_booking.id;
  update public.rental_reschedule_requests set status='approved',decision_by=v_user,decision_reason=left(p_reason,1000),decided_at=now()
    where id=p_request_id;
  insert into public.rental_operations_events(booking_id,actor_id,event_type,from_state,to_state,details,idempotency_key)
  values(v_booking.id,v_user,'rescheduled','scheduled','scheduled',
    jsonb_build_object('request_id',p_request_id,'new_start_at',v_req.new_start_at,'new_end_at',v_req.new_end_at),
    'reschedule-approved:'||p_request_id::text);
  insert into public.notifications(user_id,channel,template_key,payload)
  values(v_req.requested_by,'in_app','rental.reschedule_approved',jsonb_build_object('booking_id',v_booking.id,'new_start_at',v_req.new_start_at,'new_end_at',v_req.new_end_at));
  return 'approved';
end;
$$;
revoke all on function public.respond_rental_reschedule(uuid,boolean,text) from public,anon;
grant execute on function public.respond_rental_reschedule(uuid,boolean,text) to authenticated;

create or replace function public.request_booking_cancellation(
  p_booking_id uuid,p_reason_code text,p_description text,p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_user uuid:=auth.uid(); v_booking public.bookings%rowtype; v_captured boolean; v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if length(coalesce(p_idempotency_key,''))<16 or length(btrim(coalesce(p_description,'')))<10 then raise exception 'Description and idempotency key are required'; end if;
  select id into v_id from public.rental_cancellation_requests where idempotency_key=p_idempotency_key;
  if v_id is not null then return v_id; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_user not in (v_booking.reader_id,v_booking.owner_id) then raise exception 'Booking participant required'; end if;
  if v_booking.status in ('active','return_pending','disputed','completed') then
    raise exception 'An active or completed rental must use the return/dispute workflow, not cancellation';
  end if;
  if v_booking.status in ('cancelled','expired') then raise exception 'Booking is already closed';
  end if;
  select exists(select 1 from public.payments where booking_id=p_booking_id and status in ('captured','partially_refunded','refunded'))
    into v_captured;
  insert into public.rental_cancellation_requests(
    booking_id,requested_by,reason_code,description,status,payment_captured,policy_version,idempotency_key
  ) values (
    p_booking_id,v_user,left(p_reason_code,100),left(p_description,2000),
    case when v_captured then 'refund_review_required' else 'cancelled_without_capture' end,
    v_captured,coalesce(v_booking.payment_policy_version,'cancellation_policy_pending'),p_idempotency_key
  ) returning id into v_id;
  update public.copy_reservations set status='released',expires_at=null
  where booking_id=p_booking_id and status in ('hold','confirmed');
  update public.bookings set status='cancelled',cancellation_reason_code=left(p_reason_code,100) where id=p_booking_id;
  if v_captured then
    insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('booking',p_booking_id,'cancellation_refund_review_required',
      jsonb_build_object('cancellation_id',v_id,'payment_review_required',true),
      'cancellation-refund-review:'||v_id::text) on conflict(idempotency_key) do nothing;
  end if;
  insert into public.rental_operations_events(booking_id,actor_id,event_type,from_state,to_state,reason_code,details,idempotency_key)
  values(p_booking_id,v_user,'cancellation_requested',v_booking.status::text,'cancelled',left(p_reason_code,100),
    jsonb_build_object('cancellation_id',v_id,'captured_payment',v_captured,'automatic_deduction',false),
    'cancellation:'||p_idempotency_key);
  insert into public.notifications(user_id,channel,template_key,payload)
  values(case when v_user=v_booking.reader_id then v_booking.owner_id else v_booking.reader_id end,
    'in_app','rental.cancelled',jsonb_build_object('booking_id',p_booking_id,'cancellation_id',v_id,'refund_review_required',v_captured));
  return v_id;
end;
$$;
revoke all on function public.request_booking_cancellation(uuid,text,text,text) from public,anon;
grant execute on function public.request_booking_cancellation(uuid,text,text,text) to authenticated;

create or replace function public.report_rental_no_show(
  p_booking_id uuid,p_incident_type text,p_description text
) returns uuid language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_user uuid:=auth.uid(); v_booking public.bookings%rowtype; v_cfg public.rental_operation_policy%rowtype; v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_incident_type not in ('owner_no_show','reader_no_show') or length(btrim(coalesce(p_description,'')))<10 then
    raise exception 'Valid no-show category and description are required';
  end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_user not in (v_booking.reader_id,v_booking.owner_id) then raise exception 'Booking participant required'; end if;
  if (p_incident_type='owner_no_show' and v_user<>v_booking.reader_id)
    or (p_incident_type='reader_no_show' and v_user<>v_booking.owner_id) then
    raise exception 'Only the other participant may report this no-show';
  end if;
  select * into v_cfg from public.rental_operation_policy where id=true;
  if now()<v_booking.requested_start_at+make_interval(hours=>coalesce(v_cfg.no_show_report_window_hours,24)) then
    raise exception 'No-show report window has not elapsed';
  end if;
  if v_booking.status not in ('confirmed','collection_pending') then raise exception 'No-show applies only to a confirmed pre-collection booking'; end if;
  insert into public.booking_incidents(booking_id,reported_by,incident_type,description)
  values(p_booking_id,v_user,p_incident_type,left(p_description,2000)) returning id into v_id;
  insert into public.rental_operations_events(booking_id,actor_id,event_type,reason_code,details,idempotency_key)
  values(p_booking_id,v_user,'no_show_reported',p_incident_type,
    jsonb_build_object('incident_id',v_id,'automatic_fee',false,'automatic_forfeiture',false),
    'no-show:'||v_id::text);
  insert into public.notifications(user_id,channel,template_key,payload)
  values(v_booking.owner_id,'in_app','rental.no_show_reported',jsonb_build_object('booking_id',p_booking_id,'incident_id',v_id));
  return v_id;
end;
$$;
revoke all on function public.report_rental_no_show(uuid,text,text) from public,anon;
grant execute on function public.report_rental_no_show(uuid,text,text) to authenticated;

create or replace function public.submit_rental_damage_claim(
  p_booking_id uuid,p_claim_category text,p_description text,p_requested_compensation_paise bigint
) returns uuid language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_user uuid:=auth.uid(); v_booking public.bookings%rowtype; v_claim uuid; v_dispute uuid; v_cfg public.rental_operation_policy%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_claim_category not in ('minor_damage','major_damage','missing_pages','water_damage','lost_book','non_return','wrong_book_returned')
    or length(btrim(coalesce(p_description,'')))<30 or p_requested_compensation_paise<0 then
    raise exception 'Valid claim category, detailed description and non-negative requested amount are required';
  end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.owner_id<>v_user then raise exception 'Only the Owner may submit a claim against the Reader';
  end if;
  if v_booking.status not in ('return_pending','completed','disputed','active') then
    raise exception 'Claims are available only during return, after return, or for an overdue/lost rental';
  end if;
  if p_claim_category in ('minor_damage','major_damage','missing_pages','water_damage','wrong_book_returned')
    and not exists(select 1 from public.rental_condition_photos p where p.booking_id=p_booking_id and p.evidence_kind='collection')
  then raise exception 'Initial collection-condition evidence is required before a damage claim'; end if;
  if p_claim_category='non_return' and v_booking.rental_due_at is not null and now()<v_booking.rental_due_at+interval '24 hours' then
    raise exception 'Non-return claim cannot be raised before the proposed grace period expires';
  end if;
  select * into v_cfg from public.rental_operation_policy where id=true;
  insert into public.disputes(booking_id,opened_by,against_user_id,status,reason_code,description,policy_version)
  values(p_booking_id,v_user,v_booking.reader_id,'awaiting_reader','rental_claim:'||p_claim_category,
    left(p_description,4000),coalesce(v_cfg.policy_version,'rental_ops_v1')) returning id into v_dispute;
  insert into public.rental_damage_claims(
    booking_id,dispute_id,claimant_id,respondent_id,claim_category,description,
    requested_compensation_paise,status,response_due_at,policy_version
  ) values (
    p_booking_id,v_dispute,v_user,v_booking.reader_id,p_claim_category,left(p_description,4000),
    p_requested_compensation_paise,'awaiting_response',
    now()+make_interval(hours=>coalesce(v_cfg.claim_response_hours,48)),
    coalesce(v_cfg.policy_version,'rental_ops_v1')
  ) returning id into v_claim;
  insert into public.rental_operations_events(booking_id,actor_id,event_type,reason_code,details,idempotency_key)
  values(p_booking_id,v_user,'damage_claim_submitted',p_claim_category,
    jsonb_build_object('claim_id',v_claim,'dispute_id',v_dispute,'requested_compensation_paise',p_requested_compensation_paise),
    'damage-claim:'||v_claim::text);
  insert into public.notifications(user_id,channel,template_key,payload)
  values(v_booking.reader_id,'in_app','rental.claim_response_required',jsonb_build_object('booking_id',p_booking_id,'claim_id',v_claim,'dispute_id',v_dispute));
  return v_claim;
end;
$$;
revoke all on function public.submit_rental_damage_claim(uuid,text,text,bigint) from public,anon;
grant execute on function public.submit_rental_damage_claim(uuid,text,text,bigint) to authenticated;

create or replace function public.post_rental_case_message(
  p_case_type text,p_case_id uuid,p_body text
) returns uuid language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_user uuid:=auth.uid(); v_booking_id uuid; v_allowed boolean:=false; v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_case_type not in ('claim','dispute') or length(btrim(coalesce(p_body,''))) not between 1 and 5000 then
    raise exception 'Valid case type and message are required';
  end if;
  if p_case_type='claim' then
    select booking_id into v_booking_id from public.rental_damage_claims where id=p_case_id;
  else
    select booking_id into v_booking_id from public.disputes where id=p_case_id;
  end if;
  if v_booking_id is null then raise exception 'Resolution case not found'; end if;
  select (v_user in (reader_id,owner_id)) into v_allowed from public.bookings where id=v_booking_id;
  if not coalesce(v_allowed,false) then raise exception 'Only rental participants may post to the resolution centre'; end if;
  insert into public.rental_case_messages(case_type,case_id,booking_id,sender_id,body)
  values(p_case_type,p_case_id,v_booking_id,v_user,left(p_body,5000)) returning id into v_id;
  if p_case_type='claim' then
    update public.rental_damage_claims set status='under_review'
      where id=p_case_id and status='awaiting_response' and respondent_id=v_user;
  end if;
  insert into public.rental_operations_events(booking_id,actor_id,event_type,details,idempotency_key)
  values(v_booking_id,v_user,'resolution_message_posted',
    jsonb_build_object('case_type',p_case_type,'case_id',p_case_id,'message_id',v_id),
    'case-message:'||v_id::text);
  return v_id;
end;
$$;
revoke all on function public.post_rental_case_message(text,uuid,text) from public,anon;
grant execute on function public.post_rental_case_message(text,uuid,text) to authenticated;

create or replace function public.decide_rental_damage_claim(
  p_claim_id uuid,p_approved_compensation_paise bigint,p_decision_code text,p_decision_reason text
) returns void language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_actor uuid:=auth.uid(); v_claim public.rental_damage_claims%rowtype; v_booking public.bookings%rowtype;
  v_cfg public.rental_operation_policy%rowtype; v_reader_responded boolean; v_evidence_count integer;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null and r.role in ('admin','super_admin')) then
    raise exception 'Admin decision permission required';
  end if;
  if p_approved_compensation_paise<0 or length(btrim(coalesce(p_decision_code,'')))<3
    or length(btrim(coalesce(p_decision_reason,'')))<30 then
    raise exception 'A bounded amount, decision code and reasoned explanation are required';
  end if;
  select * into v_claim from public.rental_damage_claims where id=p_claim_id for update;
  if not found or v_claim.status not in ('submitted','awaiting_response','under_review') then raise exception 'Claim is not awaiting decision'; end if;
  if p_approved_compensation_paise>v_claim.requested_compensation_paise then raise exception 'Decision cannot exceed the amount requested';
  end if;
  select * into v_booking from public.bookings where id=v_claim.booking_id;
  select * into v_cfg from public.rental_operation_policy where id=true;
  select exists(select 1 from public.rental_case_messages where case_type='claim' and case_id=p_claim_id and sender_id=v_claim.respondent_id)
    into v_reader_responded;
  if not v_reader_responded and now()<v_claim.response_due_at then
    raise exception 'Respondent response window is still open';
  end if;
  select count(*) into v_evidence_count from public.rental_case_evidence
    where case_type in ('claim','dispute') and case_id in (p_claim_id,v_claim.dispute_id);
  if v_evidence_count<1 then raise exception 'At least one case evidence item is required before decision'; end if;
  update public.rental_damage_claims set
    status=case when p_approved_compensation_paise=0 then 'rejected'
      when p_approved_compensation_paise=requested_compensation_paise then 'approved' else 'partially_approved' end,
    approved_compensation_paise=p_approved_compensation_paise,decision_by=v_actor,
    decision_code=left(p_decision_code,100),decision_reason=left(p_decision_reason,4000),decided_at=now()
  where id=p_claim_id;
  update public.disputes set status='decided',decision_code=left(p_decision_code,100),
    decision_notes=left(p_decision_reason,4000),assigned_to=v_actor,decided_at=now()
  where id=v_claim.dispute_id;
  insert into public.rental_operations_events(booking_id,actor_id,event_type,reason_code,details,idempotency_key)
  values(v_claim.booking_id,v_actor,'damage_claim_decided',p_decision_code,
    jsonb_build_object('claim_id',p_claim_id,'requested_paise',v_claim.requested_compensation_paise,
      'approved_paise',p_approved_compensation_paise,'automatic_deduction',false,'deposit_applied',false),
    'damage-claim-decision:'||p_claim_id::text);
  insert into public.notifications(user_id,channel,template_key,payload)
  values(v_claim.claimant_id,'in_app','rental.claim_decided',jsonb_build_object('claim_id',p_claim_id,'approved_compensation_paise',p_approved_compensation_paise)),
    (v_claim.respondent_id,'in_app','rental.claim_decided',jsonb_build_object('claim_id',p_claim_id,'approved_compensation_paise',p_approved_compensation_paise));
end;
$$;
revoke all on function public.decide_rental_damage_claim(uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.decide_rental_damage_claim(uuid,bigint,text,text) to authenticated;

create or replace function public.submit_rental_appeal(
  p_case_type text,p_case_id uuid,p_grounds text
) returns uuid language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_user uuid:=auth.uid(); v_booking uuid; v_decided_at timestamptz; v_cfg public.rental_operation_policy%rowtype; v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_case_type not in ('claim','dispute') or length(btrim(coalesce(p_grounds,'')))<20 then raise exception 'Detailed appeal grounds are required'; end if;
  if p_case_type='claim' then
    select booking_id,decided_at into v_booking,v_decided_at from public.rental_damage_claims where id=p_case_id and status in ('approved','partially_approved','rejected');
  else
    select booking_id,decided_at into v_booking,v_decided_at from public.disputes where id=p_case_id and status='decided';
  end if;
  if v_booking is null or v_decided_at is null then raise exception 'Only a decided case can be appealed'; end if;
  if not exists(select 1 from public.bookings b where b.id=v_booking and v_user in (b.reader_id,b.owner_id)) then raise exception 'Only rental participants may appeal'; end if;
  select * into v_cfg from public.rental_operation_policy where id=true;
  if now()>v_decided_at+make_interval(hours=>coalesce(v_cfg.appeal_window_hours,72)) then raise exception 'Appeal window has expired'; end if;
  insert into public.rental_appeals(case_type,case_id,booking_id,appellant_id,grounds)
  values(p_case_type,p_case_id,v_booking,v_user,left(p_grounds,4000)) returning id into v_id;
  insert into public.rental_operations_events(booking_id,actor_id,event_type,details,idempotency_key)
  values(v_booking,v_user,'appeal_submitted',jsonb_build_object('appeal_id',v_id,'case_type',p_case_type,'case_id',p_case_id),
    'rental-appeal:'||v_id::text);
  return v_id;
end;
$$;
revoke all on function public.submit_rental_appeal(text,uuid,text) from public,anon;
grant execute on function public.submit_rental_appeal(text,uuid,text) to authenticated;

create or replace function public.report_rental_safety_issue(
  p_target_type text,p_target_id uuid,p_report_type text,p_description text,p_severity text default 'medium'
) returns uuid language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_user uuid:=auth.uid(); v_reported uuid; v_booking uuid; v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_target_type not in ('user','book_copy','booking','handover_location')
    or p_report_type not in ('unsafe_handover','harassment','threat','physical_safety','fraud','listing_misrepresentation','other')
    or p_severity not in ('low','medium','high','critical')
    or length(btrim(coalesce(p_description,'')))<10 then raise exception 'Invalid safety report'; end if;
  if p_target_type='user' then
    if not exists(select 1 from auth.users where id=p_target_id) or p_target_id=v_user then raise exception 'Invalid reported user'; end if;
    v_reported:=p_target_id;
  elsif p_target_type='book_copy' then
    if not exists(select 1 from public.book_copies where id=p_target_id) then raise exception 'Listing not found'; end if;
    select owner_id into v_reported from public.book_copies where id=p_target_id;
    if v_reported=v_user then raise exception 'You cannot report your own listing'; end if;
  elsif p_target_type='booking' then
    select id into v_booking from public.bookings
      where id=p_target_id and v_user in (reader_id,owner_id);
    if v_booking is null then raise exception 'Booking participant required'; end if;
    select case when reader_id=v_user then owner_id else reader_id end into v_reported from public.bookings where id=p_target_id;
  else
    if not exists(select 1 from public.handover_locations where id=p_target_id) then raise exception 'Handover location not found'; end if;
  end if;
  insert into public.rental_safety_reports(reporter_id,target_type,target_id,reported_user_id,booking_id,report_type,description,severity)
  values(v_user,p_target_type,p_target_id,v_reported,v_booking,p_report_type,left(p_description,4000),p_severity)
  returning id into v_id;
  insert into public.risk_alerts(subject_user_id,booking_id,alert_type,severity,signal_summary,internal_details)
  values(v_reported,v_booking,'safety_report:'||p_report_type,
    case when p_severity='critical' then 'critical' when p_severity='high' then 'high' else p_severity end,
    'New customer safety report',jsonb_build_object('report_id',v_id,'target_type',p_target_type));
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
  values('safety_report',v_id,'safety_report_received',jsonb_build_object('report_id',v_id,'severity',p_severity),
    'safety-report:'||v_id::text) on conflict(idempotency_key) do nothing;
  return v_id;
end;
$$;
revoke all on function public.report_rental_safety_issue(text,uuid,text,text,text) from public,anon;
grant execute on function public.report_rental_safety_issue(text,uuid,text,text,text) to authenticated;

create or replace function public.set_chat_mute(
  p_conversation_id uuid,p_muted_until timestamptz,p_reason text default null
) returns void language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_user uuid:=auth.uid();
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.chat_participants where conversation_id=p_conversation_id and user_id=v_user and left_at is null) then
    raise exception 'Active chat participant required';
  end if;
  if p_muted_until is null then
    delete from public.chat_mutes where conversation_id=p_conversation_id and user_id=v_user;
  elsif p_muted_until<=now() or p_muted_until>now()+interval '365 days' then
    raise exception 'Mute expiry must be in the future and within one year';
  else
    insert into public.chat_mutes(conversation_id,user_id,muted_until,reason)
    values(p_conversation_id,v_user,p_muted_until,left(coalesce(p_reason,''),500))
    on conflict(conversation_id,user_id) do update set muted_until=excluded.muted_until,reason=excluded.reason,updated_at=now();
  end if;
end;
$$;
revoke all on function public.set_chat_mute(uuid,timestamptz,text) from public,anon;
grant execute on function public.set_chat_mute(uuid,timestamptz,text) to authenticated;

create or replace function public.block_marketplace_user(p_blocked_user_id uuid,p_reason text default null)
returns void language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_user uuid:=auth.uid();
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_blocked_user_id=v_user or not exists(select 1 from auth.users where id=p_blocked_user_id) then
    raise exception 'Invalid user to block';
  end if;
  insert into public.user_blocks(blocker_id,blocked_id,reason_code)
  values(v_user,p_blocked_user_id,left(coalesce(p_reason,'user_block'),100))
  on conflict(blocker_id,blocked_id) do nothing;
  -- Blocking only changes future contact/discovery; active rental obligations remain intact.
  insert into public.admin_audit_logs(actor_id,action,target_table,target_id,reason,after_data)
  values(v_user,'user_blocked','user_blocks',p_blocked_user_id::text,left(coalesce(p_reason,'user_block'),300),
    jsonb_build_object('active_rentals_unchanged',true));
end;
$$;
revoke all on function public.block_marketplace_user(uuid,text) from public,anon;
grant execute on function public.block_marketplace_user(uuid,text) to authenticated;

create or replace function public.create_safety_support_ticket(p_subject text,p_description text,p_booking_id uuid default null)
returns uuid language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_user uuid:=auth.uid(); v_ticket uuid; v_number text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if length(btrim(coalesce(p_subject,'')))<5 or length(btrim(coalesce(p_description,'')))<20 then
    raise exception 'Safety support subject and details are required';
  end if;
  if p_booking_id is not null and not exists(select 1 from public.bookings where id=p_booking_id and v_user in (reader_id,owner_id)) then
    raise exception 'Booking participant required';
  end if;
  v_number:='SS-SAFE-'||upper(substr(encode(extensions.gen_random_bytes(6),'hex'),1,10));
  insert into public.grievance_tickets(ticket_number,requester_id,category,subject,description,priority)
  values(v_number,v_user,'customer_safety',left(p_subject,200),left(p_description,4000),'urgent')
  returning id into v_ticket;
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
  values('safety_ticket',v_ticket,'safety_support_ticket_created',
    jsonb_build_object('ticket_id',v_ticket,'ticket_number',v_number,'booking_id',p_booking_id),
    'safety-ticket:'||v_ticket::text) on conflict(idempotency_key) do nothing;
  return v_ticket;
end;
$$;
revoke all on function public.create_safety_support_ticket(text,text,uuid) from public,anon;
grant execute on function public.create_safety_support_ticket(text,text,uuid) to authenticated;

create or replace function public.admin_set_user_account_status(
  p_user_id uuid,p_new_status public.account_status,p_reason_code text,p_reason text,p_expires_at timestamptz default null
) returns uuid language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_actor uuid:=auth.uid(); v_profile public.profiles%rowtype; v_active_count integer; v_id uuid;
  v_booking record;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null and r.role in ('admin','super_admin')) then
    raise exception 'Admin/super-admin permission required';
  end if;
  if p_new_status not in ('active','restricted','suspended') or length(btrim(coalesce(p_reason_code,'')))<3
    or length(btrim(coalesce(p_reason,'')))<20 then raise exception 'Valid account status and documented reason are required'; end if;
  select * into v_profile from public.profiles where id=p_user_id for update;
  if not found then raise exception 'User profile not found'; end if;
  select count(*) into v_active_count from public.bookings
  where (reader_id=p_user_id or owner_id=p_user_id) and status in ('owner_accepted','payment_pending','confirmed','collection_pending','active','return_pending','disputed');
  update public.profiles set account_status=p_new_status where id=p_user_id;
  insert into public.user_suspensions(user_id,previous_status,new_status,reason_code,reason,expires_at,actor_id,active_rentals_preserved)
  values(p_user_id,v_profile.account_status,p_new_status,left(p_reason_code,100),left(p_reason,2000),p_expires_at,v_actor,v_active_count)
  returning id into v_id;
  for v_booking in
    select id,case when reader_id=p_user_id then owner_id else reader_id end as other_party
    from public.bookings
    where (reader_id=p_user_id or owner_id=p_user_id)
      and status in ('owner_accepted','payment_pending','confirmed','collection_pending','active','return_pending','disputed')
  loop
    insert into public.rental_operations_events(booking_id,actor_id,event_type,reason_code,details,idempotency_key)
    values(v_booking.id,v_actor,'participant_account_status_changed',p_reason_code,
      jsonb_build_object('suspended_user_id',p_user_id,'new_status',p_new_status::text,'active_obligation_preserved',true),
      'account-status:'||v_id::text||':'||v_booking.id::text)
    on conflict(idempotency_key) do nothing;
    insert into public.notifications(user_id,channel,template_key,payload)
    values(v_booking.other_party,'in_app','safety.participant_account_restricted',
      jsonb_build_object('booking_id',v_booking.id,'support_ticket_required',true));
  end loop;
  insert into public.admin_audit_logs(actor_id,action,target_table,target_id,reason,before_data,after_data)
  values(v_actor,'account_status_changed','profiles',p_user_id::text,left(p_reason,1000),
    jsonb_build_object('account_status',v_profile.account_status::text),
    jsonb_build_object('account_status',p_new_status::text,'active_rentals_preserved',v_active_count,'suspension_id',v_id));
  return v_id;
end;
$$;
revoke all on function public.admin_set_user_account_status(uuid,public.account_status,text,text,timestamptz) from public,anon;
grant execute on function public.admin_set_user_account_status(uuid,public.account_status,text,text,timestamptz) to authenticated;

-- Scheduler is service-role only. It queues in-app reminders and overdue proposals, never a charge.
create or replace function public.run_rental_due_sweep(p_now timestamptz default now())
returns jsonb language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare
  v_cfg public.rental_operation_policy%rowtype;
  v_booking record;
  v_user uuid;
  v_hours integer;
  v_key text;
  v_inserted integer:=0;
  v_overdue integer:=0;
  v_fee_inserted integer:=0;
  v_notification_id uuid;
  v_day integer;
  v_total bigint;
  v_fee bigint;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted scheduler required'; end if;
  select * into v_cfg from public.rental_operation_policy where id=true and is_active;
  if not found then return jsonb_build_object('enabled',false,'reason','policy_not_approved'); end if;

  for v_booking in
    select b.id,b.reader_id,b.owner_id,b.rental_due_at,rl.lifecycle_status,
      rl.grace_ends_at,b.status
    from public.bookings b join public.rental_lifecycle rl on rl.booking_id=b.id
    where b.status='active' and b.rental_due_at is not null
  loop
    update public.rental_lifecycle set
      grace_ends_at=v_booking.rental_due_at+make_interval(hours=>v_cfg.grace_period_hours),
      lifecycle_status=case when lifecycle_status='return_requested' then 'return_requested'
        when p_now>v_booking.rental_due_at+make_interval(hours=>v_cfg.grace_period_hours) then 'overdue'
        when p_now>=v_booking.rental_due_at then 'due' else 'active' end,
      overdue_since=case when p_now>v_booking.rental_due_at+make_interval(hours=>v_cfg.grace_period_hours)
        then coalesce(overdue_since,v_booking.rental_due_at+make_interval(hours=>v_cfg.grace_period_hours)) else overdue_since end,
      updated_at=p_now
    where booking_id=v_booking.id;
    if p_now>v_booking.rental_due_at+make_interval(hours=>v_cfg.grace_period_hours) then v_overdue:=v_overdue+1; end if;

    foreach v_hours in array v_cfg.reminder_hours_before loop
      if p_now>=v_booking.rental_due_at-make_interval(hours=>v_hours) then
        v_key:='due_'||v_hours::text||'h';
        foreach v_user in array array[v_booking.reader_id,v_booking.owner_id] loop
          insert into public.notifications(user_id,channel,template_key,payload,scheduled_at)
          values(v_user,'in_app','rental.due_reminder',
            jsonb_build_object('booking_id',v_booking.id,'due_at',v_booking.rental_due_at,'reminder_key',v_key),p_now)
          returning id into v_notification_id;
          insert into public.rental_notification_log(booking_id,user_id,notification_key,notification_id)
          values(v_booking.id,v_user,v_key,v_notification_id)
          on conflict(booking_id,user_id,notification_key) do nothing;
          if found then
            v_inserted:=v_inserted+1;
            insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
            values('booking',v_booking.id,'rental_due_notification_queued',
              jsonb_build_object('user_id',v_user,'notification_id',v_notification_id,'notification_key',v_key),
              'rental-notification:'||v_booking.id::text||':'||v_user::text||':'||v_key)
            on conflict(idempotency_key) do nothing;
          else
            delete from public.notifications where id=v_notification_id;
          end if;
        end loop;
      end if;
    end loop;

    if p_now>v_booking.rental_due_at+make_interval(hours=>v_cfg.grace_period_hours) then
      v_day:=greatest(1,floor(extract(epoch from (p_now-(v_booking.rental_due_at+make_interval(hours=>v_cfg.grace_period_hours))))/86400.0)::integer+1);
      v_key:='overdue_day_'||v_day::text;
      foreach v_user in array array[v_booking.reader_id,v_booking.owner_id] loop
        insert into public.notifications(user_id,channel,template_key,payload,scheduled_at)
        values(v_user,'in_app','rental.overdue_reminder',
          jsonb_build_object('booking_id',v_booking.id,'due_at',v_booking.rental_due_at,'grace_ends_at',v_booking.rental_due_at+make_interval(hours=>v_cfg.grace_period_hours),'overdue_day',v_day),p_now)
        returning id into v_notification_id;
        insert into public.rental_notification_log(booking_id,user_id,notification_key,notification_id)
        values(v_booking.id,v_user,v_key,v_notification_id)
        on conflict(booking_id,user_id,notification_key) do nothing;
        if found then v_inserted:=v_inserted+1; else delete from public.notifications where id=v_notification_id; end if;
      end loop;

      if v_cfg.late_fee_enabled then
        v_total:=coalesce((select sum(amount_paise) from public.late_fees where booking_id=v_booking.id and status in ('proposed','approved','charged','disputed')),0);
        v_fee:=least(v_cfg.late_fee_daily_paise,greatest(v_cfg.late_fee_max_paise-v_total,0));
        if v_fee>0 then
          insert into public.late_fees(booking_id,assessed_to,amount_paise,policy_version,reason_code,status,billing_day,assessment_idempotency_key)
          values(v_booking.id,v_booking.reader_id,v_fee,v_cfg.policy_version,'overdue_after_grace','proposed',(p_now at time zone 'Asia/Kolkata')::date,
            'late-fee:'||v_booking.id::text||':'||(p_now at time zone 'Asia/Kolkata')::date::text)
          on conflict do nothing;
          if found then v_fee_inserted:=v_fee_inserted+1; end if;
        end if;
      end if;
    end if;
  end loop;

  return jsonb_build_object('enabled',true,'notifications_queued',v_inserted,'overdue_rentals',v_overdue,'late_fee_proposals_created',v_fee_inserted,
    'late_fees_charged',0,'automatic_deductions',false);
end;
$$;
revoke all on function public.run_rental_due_sweep(timestamptz) from public,anon,authenticated;
grant execute on function public.run_rental_due_sweep(timestamptz) to service_role;

-- RLS: participants can read their operational cases. All decisions and writes go through RPCs.
alter table public.rental_lifecycle enable row level security;
create policy rental_lifecycle_participant_read on public.rental_lifecycle for select to authenticated
  using (exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.reader_id,b.owner_id)));
alter table public.rental_operations_events enable row level security;
create policy rental_ops_events_participant_read on public.rental_operations_events for select to authenticated
  using (exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.reader_id,b.owner_id)));
alter table public.rental_extension_requests enable row level security;
create policy rental_extension_participant_read on public.rental_extension_requests for select to authenticated
  using (exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.reader_id,b.owner_id)));
alter table public.rental_reschedule_requests enable row level security;
create policy rental_reschedule_participant_read on public.rental_reschedule_requests for select to authenticated
  using (exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.reader_id,b.owner_id)));
alter table public.rental_cancellation_requests enable row level security;
create policy rental_cancel_participant_read on public.rental_cancellation_requests for select to authenticated
  using (exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.reader_id,b.owner_id)));
alter table public.rental_damage_claims enable row level security;
create policy rental_claim_participant_read on public.rental_damage_claims for select to authenticated
  using (claimant_id=auth.uid() or respondent_id=auth.uid());
alter table public.rental_case_messages enable row level security;
create policy rental_case_message_participant_read on public.rental_case_messages for select to authenticated
  using (exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.reader_id,b.owner_id)));
alter table public.rental_case_evidence enable row level security;
create policy rental_case_evidence_participant_read on public.rental_case_evidence for select to authenticated
  using (exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.reader_id,b.owner_id)));
alter table public.rental_appeals enable row level security;
create policy rental_appeal_participant_read on public.rental_appeals for select to authenticated
  using (exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.reader_id,b.owner_id)));
alter table public.rental_safety_reports enable row level security;
create policy rental_safety_reporter_read on public.rental_safety_reports for select to authenticated using (reporter_id=auth.uid());
alter table public.chat_mutes enable row level security;
create policy chat_mutes_owner_all on public.chat_mutes for all to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
alter table public.user_suspensions enable row level security;
alter table public.rental_notification_log enable row level security;
alter table public.rental_operation_policy enable row level security;

revoke all on public.rental_operation_policy,public.user_suspensions,public.rental_notification_log from anon,authenticated;
revoke insert,update,delete on public.rental_lifecycle,public.rental_operations_events,public.rental_extension_requests,
  public.rental_reschedule_requests,public.rental_cancellation_requests,public.rental_damage_claims,
  public.rental_case_messages,public.rental_case_evidence,public.rental_appeals,public.rental_safety_reports
from anon,authenticated;
revoke update,delete on public.rental_operations_events,public.rental_case_evidence from service_role;


create or replace function public.register_rental_case_evidence(
  p_case_type text,p_case_id uuid,p_actor_id uuid,p_object_key text,
  p_evidence_type text,p_description text,p_sha256 text
) returns uuid language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_booking uuid; v_reader uuid; v_owner uuid; v_id uuid; v_reporter uuid;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted evidence service required'; end if;
  if p_case_type not in ('claim','dispute') or p_sha256 !~ '^[a-f0-9]{64}$'
    or length(btrim(coalesce(p_evidence_type,'')))<3 then raise exception 'Invalid evidence metadata'; end if;
  if p_case_type='claim' then
    select booking_id into v_booking from public.rental_damage_claims where id=p_case_id;
  else
    select booking_id into v_booking from public.disputes where id=p_case_id;
  end if;
  if v_booking is null then raise exception 'Resolution case not found'; end if;
  select reader_id,owner_id into v_reader,v_owner from public.bookings where id=v_booking;
  if p_actor_id not in (v_reader,v_owner) then raise exception 'Evidence submitter is not a booking participant'; end if;
  if p_object_key not like p_actor_id::text||'/'||v_booking::text||'/'||p_case_type||'/'||p_case_id::text||'/%'
    or p_object_key like '%..%' or p_object_key like '/%' then raise exception 'Evidence object path is not participant/case scoped'; end if;
  insert into public.rental_case_evidence(case_type,case_id,booking_id,submitted_by,object_key,evidence_type,description,sha256)
  values(p_case_type,p_case_id,v_booking,p_actor_id,p_object_key,left(p_evidence_type,80),left(coalesce(p_description,''),1000),p_sha256)
  returning id into v_id;
  insert into public.rental_operations_events(booking_id,actor_id,event_type,details,idempotency_key)
  values(v_booking,p_actor_id,'case_evidence_added',
    jsonb_build_object('case_type',p_case_type,'case_id',p_case_id,'evidence_id',v_id,'sha256',p_sha256),
    'case-evidence:'||v_id::text);
  return v_id;
end;
$$;
revoke all on function public.register_rental_case_evidence(text,uuid,uuid,text,text,text,text) from public,anon,authenticated;
grant execute on function public.register_rental_case_evidence(text,uuid,uuid,text,text,text,text) to service_role;

create or replace function public.decide_rental_appeal(
  p_appeal_id uuid,p_outcome text,p_decision_code text,p_decision_reason text,
  p_revised_compensation_paise bigint default null
) returns void language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_actor uuid:=auth.uid(); v_appeal public.rental_appeals%rowtype;
  v_claim public.rental_damage_claims%rowtype; v_booking public.bookings%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor
    and r.revoked_at is null and r.role in ('admin','super_admin')) then
    raise exception 'Admin/super-admin appeal reviewer permission required';
  end if;
  if p_outcome not in ('upheld','revised','dismissed') or length(btrim(coalesce(p_decision_code,'')))<3
    or length(btrim(coalesce(p_decision_reason,'')))<30 then raise exception 'A reasoned appeal outcome is required'; end if;
  select * into v_appeal from public.rental_appeals where id=p_appeal_id for update;
  if not found or v_appeal.status not in ('submitted','under_review') then raise exception 'Appeal is not awaiting review'; end if;
  select * into v_booking from public.bookings where id=v_appeal.booking_id;
  if v_appeal.case_type='claim' then
    select * into v_claim from public.rental_damage_claims where id=v_appeal.case_id for update;
    if not found then raise exception 'Original claim not found'; end if;
    if p_outcome='revised' then
      if p_revised_compensation_paise is null or p_revised_compensation_paise<0
        or p_revised_compensation_paise>v_claim.requested_compensation_paise then
        raise exception 'Revised compensation must be between zero and the evidence-backed requested amount';
      end if;
      update public.rental_damage_claims set
        approved_compensation_paise=p_revised_compensation_paise,
        status=case when p_revised_compensation_paise=0 then 'rejected'
          when p_revised_compensation_paise=requested_compensation_paise then 'approved' else 'partially_approved' end,
        decision_by=v_actor,decision_code=left(p_decision_code,100),
        decision_reason=left(p_decision_reason,4000),decided_at=now()
      where id=v_claim.id;
    elsif p_outcome='upheld' then
      update public.rental_damage_claims set status=case when approved_compensation_paise=0 then 'rejected'
        when approved_compensation_paise=requested_compensation_paise then 'approved' else 'partially_approved' end
      where id=v_claim.id;
    end if;
  end if;
  update public.rental_appeals set status=p_outcome,reviewer_id=v_actor,
    decision_code=left(p_decision_code,100),decision_reason=left(p_decision_reason,4000),decided_at=now()
  where id=p_appeal_id;
  insert into public.rental_operations_events(booking_id,actor_id,event_type,reason_code,details,idempotency_key)
  values(v_appeal.booking_id,v_actor,'appeal_decided',p_decision_code,
    jsonb_build_object('appeal_id',p_appeal_id,'case_type',v_appeal.case_type,'case_id',v_appeal.case_id,
      'outcome',p_outcome,'revised_compensation_paise',p_revised_compensation_paise,
      'automatic_deduction',false,'deposit_applied',false),
    'appeal-decision:'||p_appeal_id::text);
  insert into public.admin_audit_logs(actor_id,action,target_table,target_id,reason,after_data)
  values(v_actor,'rental_appeal_decided','rental_appeals',p_appeal_id::text,left(p_decision_reason,1000),
    jsonb_build_object('outcome',p_outcome,'decision_code',p_decision_code,'compensation_paise',p_revised_compensation_paise));
  insert into public.notifications(user_id,channel,template_key,payload)
  values(v_booking.reader_id,'in_app','rental.appeal_decided',jsonb_build_object('appeal_id',p_appeal_id,'outcome',p_outcome)),
    (v_booking.owner_id,'in_app','rental.appeal_decided',jsonb_build_object('appeal_id',p_appeal_id,'outcome',p_outcome));
end;
$$;
revoke all on function public.decide_rental_appeal(uuid,text,text,text,bigint) from public,anon,authenticated;
grant execute on function public.decide_rental_appeal(uuid,text,text,text,bigint) to authenticated;

create or replace function public.admin_resolve_rental_safety_report(
  p_report_id uuid,p_status text,p_resolution_code text,p_resolution_reason text
) returns void language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_actor uuid:=auth.uid(); v_report public.rental_safety_reports%rowtype;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor and r.revoked_at is null
    and r.role in ('admin','super_admin','moderator','support_agent')) then raise exception 'Safety support permission required'; end if;
  if p_status not in ('triaged','investigating','actioned','dismissed','closed')
    or length(btrim(coalesce(p_resolution_code,'')))<3
    or length(btrim(coalesce(p_resolution_reason,'')))<20 then raise exception 'Reasoned safety case outcome is required'; end if;
  select * into v_report from public.rental_safety_reports where id=p_report_id for update;
  if not found then raise exception 'Safety report not found'; end if;
  update public.rental_safety_reports set status=p_status,assigned_to=coalesce(assigned_to,v_actor),
    resolution_code=left(p_resolution_code,100),resolution_reason=left(p_resolution_reason,2000),
    resolved_at=case when p_status in ('actioned','dismissed','closed') then now() else null end
  where id=p_report_id;
  insert into public.admin_audit_logs(actor_id,action,target_table,target_id,reason,before_data,after_data)
  values(v_actor,'rental_safety_report_resolved','rental_safety_reports',p_report_id::text,left(p_resolution_reason,1000),
    jsonb_build_object('status',v_report.status),jsonb_build_object('status',p_status,'resolution_code',p_resolution_code));
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
  values('safety_report',p_report_id,'safety_report_status_changed',
    jsonb_build_object('status',p_status,'resolution_code',p_resolution_code),
    'safety-report-resolution:'||p_report_id::text||':'||p_status)
  on conflict(idempotency_key) do nothing;
end;
$$;
revoke all on function public.admin_resolve_rental_safety_report(uuid,text,text,text) from public,anon;
grant execute on function public.admin_resolve_rental_safety_report(uuid,text,text,text) to authenticated;

commit;

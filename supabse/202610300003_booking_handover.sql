begin;

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  booking_number text not null unique,
  reader_id uuid not null references auth.users(id) on delete restrict,
  owner_id uuid not null references auth.users(id) on delete restrict,
  city_id uuid not null references public.cities(id) on delete restrict,
  status public.booking_status not null default 'requested',
  requested_start_at timestamptz not null,
  requested_end_at timestamptz not null,
  rental_start_at timestamptz,
  rental_due_at timestamptz,
  completed_at timestamptz,
  cancellation_reason_code text,
  policy_snapshot jsonb not null default '{}'::jsonb,
  currency char(3) not null default 'INR' check (currency = 'INR'),
  rent_subtotal_paise bigint not null default 0 check (rent_subtotal_paise >= 0),
  platform_fee_paise bigint not null default 0 check (platform_fee_paise >= 0),
  tax_paise bigint not null default 0 check (tax_paise >= 0),
  deposit_required_paise bigint not null default 0 check (deposit_required_paise >= 0),
  total_due_paise bigint not null default 0 check (total_due_paise >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (reader_id <> owner_id),
  check (requested_end_at > requested_start_at),
  check (rental_due_at is null or rental_start_at is null or rental_due_at > rental_start_at)
);
create index bookings_reader_idx on public.bookings(reader_id, created_at desc);
create index bookings_owner_idx on public.bookings(owner_id, created_at desc);
create index bookings_status_due_idx on public.bookings(status, rental_due_at);

create table public.rental_items (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete restrict,
  book_copy_id uuid not null references public.book_copies(id) on delete restrict,
  city_id uuid not null references public.cities(id) on delete restrict,
  pricing_snapshot jsonb not null,
  rental_fee_paise bigint not null check (rental_fee_paise >= 0),
  buffer_before interval not null default interval '0',
  buffer_after interval not null default interval '0',
  reserved_period tstzrange not null,
  created_at timestamptz not null default now(),
  unique (booking_id, book_copy_id),
  foreign key (book_copy_id, city_id) references public.book_copies(id, city_id) on delete restrict,
  check (not isempty(reserved_period)),
  check (lower_inc(reserved_period) and not upper_inc(reserved_period)),
  check (buffer_before >= interval '0' and buffer_after >= interval '0')
);
create index rental_items_booking_idx on public.rental_items(booking_id);
create index rental_items_copy_idx on public.rental_items(book_copy_id);

create table public.copy_reservations (
  id uuid primary key default gen_random_uuid(),
  rental_item_id uuid not null unique references public.rental_items(id) on delete restrict,
  booking_id uuid not null references public.bookings(id) on delete restrict,
  book_copy_id uuid not null references public.book_copies(id) on delete restrict,
  reserved_period tstzrange not null,
  status public.reservation_status not null default 'hold',
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (not isempty(reserved_period)),
  check (lower_inc(reserved_period) and not upper_inc(reserved_period))
);
alter table public.copy_reservations
  add constraint copy_reservations_no_double_booking
  exclude using gist (book_copy_id with =, reserved_period with &&)
  where (status in ('hold','confirmed','in_use'));
create index copy_reservations_booking_idx on public.copy_reservations(booking_id);
create index copy_reservations_expiry_idx on public.copy_reservations(expires_at) where status = 'hold';

create table public.rental_agreements (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  legal_document_id uuid,
  document_version text not null,
  document_sha256 text not null check (document_sha256 ~ '^[a-f0-9]{64}$'),
  accepted_at timestamptz not null default now(),
  ip_hash text,
  user_agent_hash text,
  unique (booking_id, user_id, document_version)
);

create table public.rental_condition_photos (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete restrict,
  rental_item_id uuid not null references public.rental_items(id) on delete restrict,
  submitted_by uuid not null references auth.users(id) on delete restrict,
  evidence_kind public.evidence_kind not null check (evidence_kind in ('collection','return','damage')),
  storage_bucket text not null default 'rental-evidence-private' check (storage_bucket = 'rental-evidence-private'),
  object_key text not null,
  content_sha256 text,
  caption text,
  captured_at timestamptz,
  created_at timestamptz not null default now(),
  unique (storage_bucket, object_key),
  check (object_key !~ '(^/|\\.\\.)')
);
create index rental_condition_photos_booking_idx on public.rental_condition_photos(booking_id, created_at);

create table public.handover_sessions (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete restrict,
  rental_item_id uuid not null references public.rental_items(id) on delete restrict,
  handover_type text not null check (handover_type in ('collection','return')),
  handover_location_id uuid references public.handover_locations(id) on delete restrict,
  initiator_id uuid not null references auth.users(id) on delete restrict,
  qr_token_hash text not null unique,
  otp_hash text,
  expires_at timestamptz not null,
  completed_at timestamptz,
  status text not null default 'created' check (status in ('created','awaiting_counterparty','completed','expired','cancelled','failed')),
  created_at timestamptz not null default now()
);
create index handover_sessions_booking_idx on public.handover_sessions(booking_id, created_at desc);

create table public.handover_events (
  id bigint generated always as identity primary key,
  handover_session_id uuid not null references public.handover_sessions(id) on delete restrict,
  actor_id uuid references auth.users(id) on delete restrict,
  event_type text not null,
  event_payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);
create index handover_events_session_idx on public.handover_events(handover_session_id, occurred_at);

create trigger bookings_updated_at before update on public.bookings for each row execute function private.set_updated_at();
create trigger copy_reservations_updated_at before update on public.copy_reservations for each row execute function private.set_updated_at();

commit;

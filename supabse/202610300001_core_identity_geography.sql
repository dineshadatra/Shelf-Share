begin;

create extension if not exists pgcrypto with schema extensions;
create extension if not exists btree_gist with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create type public.account_status as enum ('active','restricted','suspended','closed');
create type public.verification_status as enum ('not_submitted','pending','under_review','verified','rejected','expired','needs_resubmission');
create type public.identity_document_type as enum ('passport','pan','driving_licence','other');
create type public.document_review_status as enum ('submitted','under_review','accepted','rejected','expired');
create type public.city_status as enum ('draft','active','paused','retired');
create type public.listing_status as enum ('draft','pending_review','approved','rejected','paused','removed');
create type public.copy_condition as enum ('new','like_new','good','acceptable','poor','damaged');
create type public.booking_status as enum ('requested','payment_pending','confirmed','collection_pending','active','return_pending','completed','cancelled','expired','disputed');
create type public.reservation_status as enum ('hold','confirmed','in_use','released','expired','cancelled');
create type public.payment_status as enum ('created','pending','authorized','captured','failed','cancelled','partially_refunded','refunded','reconciliation_required');
create type public.deposit_status as enum ('required_unconfigured','collection_pending','held_by_provider','claim_hold_pending','claim_hold','release_pending','refund_pending','partially_applied','released','failed','reconciliation_required');
create type public.payout_status as enum ('pending','eligible','processing','paid','failed','reversed','reconciliation_required');
create type public.dispute_status as enum ('open','awaiting_reader','awaiting_owner','under_review','decided','appealed','closed');
create type public.evidence_kind as enum ('identity','listing','collection','return','damage','dispute','support','profile');
create type public.ledger_entry_status as enum ('draft','posted','reversed');
create type public.community_content_status as enum ('draft','published','hidden','removed');
create type public.ticket_status as enum ('open','in_progress','waiting_user','resolved','closed');
create type public.exchange_status as enum ('requested','accepted','declined','cancelled','in_progress','completed','disputed','expired');

create or replace function private.set_updated_at()
returns trigger language plpgsql set search_path = pg_catalog
as $$ begin new.updated_at = now(); return new; end $$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  display_name text not null check (length(btrim(display_name)) between 1 and 80),
  avatar_object_key text,
  bio text check (bio is null or length(bio) <= 500),
  preferred_city_id uuid,
  account_status public.account_status not null default 'active',
  locale text not null default 'en-IN',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  role text not null check (role in ('support_agent','verification_reviewer','finance_operator','moderator','admin','super_admin')),
  granted_by uuid references auth.users(id) on delete restrict,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  reason text not null,
  check (revoked_at is null or revoked_at >= granted_at)
);
create unique index user_roles_one_active_role_uq on public.user_roles(user_id, role) where revoked_at is null;
create index user_roles_user_active_idx on public.user_roles(user_id) where revoked_at is null;

create table public.cities (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9_-]{2,12}$'),
  name text not null,
  state_name text not null,
  country_code char(2) not null default 'IN',
  timezone text not null default 'Asia/Kolkata',
  status public.city_status not null default 'draft',
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles add constraint profiles_preferred_city_fk
  foreign key (preferred_city_id) references public.cities(id) on delete set null;

create table public.localities (
  id uuid primary key default gen_random_uuid(),
  city_id uuid not null references public.cities(id) on delete restrict,
  name text not null,
  normalized_name text not null,
  postal_codes text[] not null default '{}',
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  unique (city_id, normalized_name),
  unique (id, city_id)
);
create index localities_city_active_idx on public.localities(city_id, name) where is_active;

create table public.user_verifications (
  user_id uuid primary key references auth.users(id) on delete restrict,
  status public.verification_status not null default 'not_submitted',
  age_eligible boolean,
  phone_verified_at timestamptz,
  identity_verified_at timestamptz,
  address_verified_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete restrict,
  reviewed_at timestamptz,
  rejection_reason_code text,
  policy_version text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status <> 'verified') or (age_eligible is true and identity_verified_at is not null))
);

create table public.identity_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  verification_user_id uuid not null references public.user_verifications(user_id) on delete restrict,
  document_type public.identity_document_type not null,
  storage_bucket text not null default 'identity-private' check (storage_bucket = 'identity-private'),
  object_key text not null,
  document_last4 text check (document_last4 is null or document_last4 ~ '^[A-Za-z0-9]{2,8}$'),
  provider_reference text,
  status public.document_review_status not null default 'submitted',
  submitted_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id) on delete restrict,
  reviewed_at timestamptz,
  rejection_reason_code text,
  expires_on date,
  unique (storage_bucket, object_key),
  check (object_key !~ '(^/|\\.\\.)')
);
create index identity_documents_user_idx on public.identity_documents(user_id, submitted_at desc);

create table public.verification_audit (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete restrict,
  action text not null,
  from_status public.verification_status,
  to_status public.verification_status,
  reason_code text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index verification_audit_user_time_idx on public.verification_audit(user_id, created_at desc);

create table public.handover_locations (
  id uuid primary key default gen_random_uuid(),
  locality_id uuid not null,
  city_id uuid not null,
  name text not null,
  description text,
  public_address text not null,
  latitude numeric(9,6),
  longitude numeric(9,6),
  opening_hours jsonb not null default '{}'::jsonb,
  safety_notes text,
  status text not null default 'draft' check (status in ('draft','pending_review','active','paused','retired')),
  created_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (locality_id, city_id) references public.localities(id, city_id) on delete restrict,
  check ((latitude is null and longitude is null) or (latitude between -90 and 90 and longitude between -180 and 180))
);
create index handover_locations_city_status_idx on public.handover_locations(city_id, status);

create or replace function private.is_staff()
returns boolean language sql stable security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.user_roles r
    where r.user_id = auth.uid() and r.revoked_at is null
  );
$$;
create or replace function private.has_role(required_role text)
returns boolean language sql stable security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.user_roles r
    where r.user_id = auth.uid() and r.revoked_at is null and r.role = required_role
  );
$$;
revoke all on function private.is_staff() from public;
revoke all on function private.has_role(text) from public;
grant execute on function private.is_staff() to authenticated;
grant execute on function private.has_role(text) to authenticated;

create trigger profiles_updated_at before update on public.profiles for each row execute function private.set_updated_at();
create trigger cities_updated_at before update on public.cities for each row execute function private.set_updated_at();
create trigger user_verifications_updated_at before update on public.user_verifications for each row execute function private.set_updated_at();
create trigger handover_locations_updated_at before update on public.handover_locations for each row execute function private.set_updated_at();

commit;

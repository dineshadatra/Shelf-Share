begin;

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete restrict,
  payer_id uuid not null references auth.users(id) on delete restrict,
  provider text not null,
  provider_payment_id text,
  provider_order_id text,
  idempotency_key text not null unique,
  amount_paise bigint not null check (amount_paise > 0),
  currency char(3) not null default 'INR' check (currency = 'INR'),
  status public.payment_status not null default 'created',
  captured_at timestamptz,
  failure_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider, provider_payment_id),
  unique (provider, provider_order_id)
);
create index payments_booking_idx on public.payments(booking_id, created_at desc);
create index payments_payer_idx on public.payments(payer_id, created_at desc);

create table public.payment_events (
  id bigint generated always as identity primary key,
  payment_id uuid references public.payments(id) on delete restrict,
  provider text not null,
  provider_event_id text not null,
  event_type text not null,
  signature_valid boolean not null,
  payload_object_key text,
  payload_sha256 text,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  processing_status text not null default 'received' check (processing_status in ('received','processed','ignored_duplicate','retrying','dead_letter','rejected')),
  processing_error_code text,
  unique (provider, provider_event_id)
);
create index payment_events_unprocessed_idx on public.payment_events(received_at) where processed_at is null;

create table public.deposits (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings(id) on delete restrict,
  payer_id uuid not null references auth.users(id) on delete restrict,
  provider text,
  provider_reference text,
  amount_paise bigint not null check (amount_paise >= 0),
  currency char(3) not null default 'INR' check (currency = 'INR'),
  status public.deposit_status not null default 'required_unconfigured',
  custody_descriptor text,
  legal_approval_reference text,
  policy_version text,
  feature_enabled_at_creation boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index deposits_payer_idx on public.deposits(payer_id, created_at desc);

create table public.deposit_ledger (
  id bigint generated always as identity primary key,
  deposit_id uuid not null references public.deposits(id) on delete restrict,
  event_type text not null check (event_type in ('collection_requested','provider_held','claim_hold_requested','claim_held','amount_applied','release_requested','refund_requested','released','failed','reversed')),
  amount_paise bigint not null check (amount_paise >= 0),
  provider_reference text,
  idempotency_key text not null unique,
  related_event_id bigint references public.deposit_ledger(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index deposit_ledger_deposit_idx on public.deposit_ledger(deposit_id, created_at);

create table public.deposit_release_requests (
  id uuid primary key default gen_random_uuid(),
  deposit_id uuid not null references public.deposits(id) on delete restrict,
  requested_by uuid not null references auth.users(id) on delete restrict,
  amount_paise bigint not null check (amount_paise > 0),
  status text not null default 'requested' check (status in ('requested','approved','processing','released','rejected','failed','reconciliation_required')),
  idempotency_key text not null unique,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);
create unique index deposit_release_one_open_uq on public.deposit_release_requests(deposit_id)
where status in ('requested','approved','processing','reconciliation_required');

create table public.commission_ledger (
  id bigint generated always as identity primary key,
  booking_id uuid not null references public.bookings(id) on delete restrict,
  payment_id uuid references public.payments(id) on delete restrict,
  commission_rate_bps integer not null check (commission_rate_bps between 0 and 10000),
  rent_basis_paise bigint not null check (rent_basis_paise >= 0),
  commission_paise bigint not null check (commission_paise >= 0),
  currency char(3) not null default 'INR' check (currency = 'INR'),
  policy_version text not null,
  created_at timestamptz not null default now(),
  unique (booking_id, policy_version)
);

create table public.owner_earnings (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings(id) on delete restrict,
  owner_id uuid not null references auth.users(id) on delete restrict,
  gross_rent_paise bigint not null check (gross_rent_paise >= 0),
  commission_paise bigint not null check (commission_paise >= 0),
  tax_withheld_paise bigint not null default 0 check (tax_withheld_paise >= 0),
  provider_fee_paise bigint not null default 0 check (provider_fee_paise >= 0),
  adjustment_paise bigint not null default 0,
  net_payable_paise bigint not null check (net_payable_paise >= 0),
  status public.payout_status not null default 'pending',
  eligible_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index owner_earnings_owner_idx on public.owner_earnings(owner_id, created_at desc);

create table public.payouts (
  id uuid primary key default gen_random_uuid(),
  owner_earning_id uuid not null references public.owner_earnings(id) on delete restrict,
  owner_id uuid not null references auth.users(id) on delete restrict,
  provider text not null,
  provider_transfer_id text,
  idempotency_key text not null unique,
  amount_paise bigint not null check (amount_paise > 0),
  currency char(3) not null default 'INR' check (currency = 'INR'),
  status public.payout_status not null default 'pending',
  initiated_at timestamptz,
  settled_at timestamptz,
  failure_code text,
  created_at timestamptz not null default now(),
  unique (provider, provider_transfer_id)
);
create index payouts_owner_idx on public.payouts(owner_id, created_at desc);

create table public.refunds (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete restrict,
  payment_id uuid not null references public.payments(id) on delete restrict,
  requested_by uuid references auth.users(id) on delete restrict,
  provider text not null,
  provider_refund_id text,
  idempotency_key text not null unique,
  amount_paise bigint not null check (amount_paise > 0),
  currency char(3) not null default 'INR' check (currency = 'INR'),
  status text not null default 'requested' check (status in ('requested','pending','succeeded','failed','reconciliation_required')),
  reason_code text not null,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (provider, provider_refund_id)
);
create index refunds_payment_idx on public.refunds(payment_id, created_at);

create table public.late_fees (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete restrict,
  assessed_to uuid not null references auth.users(id) on delete restrict,
  amount_paise bigint not null check (amount_paise >= 0),
  currency char(3) not null default 'INR' check (currency = 'INR'),
  policy_version text not null,
  reason_code text not null,
  status text not null default 'proposed' check (status in ('proposed','approved','waived','charged','disputed','reversed')),
  assessed_at timestamptz not null default now(),
  approved_by uuid references auth.users(id) on delete restrict
);
create index late_fees_booking_idx on public.late_fees(booking_id);

create table public.financial_accounts (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  account_type text not null check (account_type in ('asset','liability','equity','revenue','expense')),
  currency char(3) not null default 'INR' check (currency = 'INR'),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create table public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  entry_reference text not null unique,
  description text not null,
  source_type text not null,
  source_id uuid,
  status public.ledger_entry_status not null default 'draft',
  reversal_of uuid references public.journal_entries(id) on delete restrict,
  posted_at timestamptz,
  created_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (reversal_of is null or reversal_of <> id)
);
create unique index journal_entries_one_reversal_uq on public.journal_entries(reversal_of) where reversal_of is not null;

create table public.journal_lines (
  id bigint generated always as identity primary key,
  journal_entry_id uuid not null references public.journal_entries(id) on delete restrict,
  account_id uuid not null references public.financial_accounts(id) on delete restrict,
  currency char(3) not null default 'INR' check (currency = 'INR'),
  debit_paise bigint not null default 0 check (debit_paise >= 0),
  credit_paise bigint not null default 0 check (credit_paise >= 0),
  dimensions jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check ((debit_paise > 0 and credit_paise = 0) or (credit_paise > 0 and debit_paise = 0))
);
create index journal_lines_entry_idx on public.journal_lines(journal_entry_id);
create index journal_lines_account_idx on public.journal_lines(account_id, created_at desc);

create or replace function private.assert_journal_balanced()
returns trigger language plpgsql set search_path = pg_catalog, public
as $$
declare v_entry uuid; v_bad boolean;
begin
  v_entry := coalesce(new.journal_entry_id, old.journal_entry_id);
  select exists (
    select 1
    from public.journal_lines
    where journal_entry_id = v_entry
    group by currency
    having sum(debit_paise) <> sum(credit_paise)
  ) into v_bad;
  if v_bad then raise exception 'Journal entry % is not balanced by currency', v_entry; end if;
  if not exists (select 1 from public.journal_lines where journal_entry_id = v_entry) then
    raise exception 'Journal entry % must contain at least one line', v_entry;
  end if;
  return null;
end;
$$;
create constraint trigger journal_lines_balance_ct
after insert or update or delete on public.journal_lines
deferrable initially deferred for each row execute function private.assert_journal_balanced();

create or replace function private.prevent_posted_journal_mutation()
returns trigger language plpgsql set search_path = pg_catalog, public
as $$
declare v_status public.ledger_entry_status;
begin
  select status into v_status from public.journal_entries where id = coalesce(old.journal_entry_id, new.journal_entry_id);
  if v_status = 'posted' then raise exception 'Posted journal lines are immutable; create a reversal'; end if;
  return coalesce(new, old);
end;
$$;
create trigger journal_lines_immutable
before update or delete on public.journal_lines
for each row execute function private.prevent_posted_journal_mutation();

create trigger payments_updated_at before update on public.payments for each row execute function private.set_updated_at();
create trigger deposits_updated_at before update on public.deposits for each row execute function private.set_updated_at();
create trigger owner_earnings_updated_at before update on public.owner_earnings for each row execute function private.set_updated_at();

commit;

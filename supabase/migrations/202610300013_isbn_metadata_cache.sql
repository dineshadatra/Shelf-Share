begin;

create table public.book_metadata_cache (
  isbn13 char(13) primary key check (isbn13 ~ '^[0-9]{13}$'),
  provider text not null check (provider='openlibrary'),
  metadata jsonb not null,
  fetched_at timestamptz not null default now(),
  expires_at timestamptz not null,
  check (expires_at>fetched_at)
);
alter table public.book_metadata_cache enable row level security;
revoke all on public.book_metadata_cache from public,anon,authenticated;
grant select,insert,update,delete on public.book_metadata_cache to service_role;

commit;

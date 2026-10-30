begin;

create table public.book_titles (
  id uuid primary key default gen_random_uuid(),
  isbn13 text check (isbn13 is null or isbn13 ~ '^[0-9]{13}$'),
  title text not null,
  subtitle text,
  edition text,
  authors text[] not null default '{}',
  publisher text,
  language_code text,
  publication_year smallint check (publication_year is null or publication_year between 1400 and 2200),
  description text,
  cover_image_url text,
  metadata_source text,
  metadata_source_id text,
  moderation_status text not null default 'pending_review' check (moderation_status in ('pending_review','approved','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index book_titles_isbn13_uq on public.book_titles(isbn13) where isbn13 is not null;
create index book_titles_title_search_idx on public.book_titles using gin (to_tsvector('simple', coalesce(title,'') || ' ' || coalesce(array_to_string(authors,' '),'')));
create index book_titles_publisher_idx on public.book_titles(publisher);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text,
  parent_id uuid references public.categories(id) on delete restrict,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create table public.book_title_categories (
  book_title_id uuid not null references public.book_titles(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete restrict,
  primary key (book_title_id, category_id)
);
create index book_title_categories_category_idx on public.book_title_categories(category_id, book_title_id);

create table public.book_copies (
  id uuid primary key default gen_random_uuid(),
  book_title_id uuid not null references public.book_titles(id) on delete restrict,
  owner_id uuid not null references auth.users(id) on delete restrict,
  city_id uuid not null references public.cities(id) on delete restrict,
  locality_id uuid not null,
  owner_reference text,
  condition_summary public.copy_condition not null,
  description text,
  listing_status public.listing_status not null default 'draft',
  is_available_for_rent boolean not null default false,
  acquisition_year smallint check (acquisition_year is null or acquisition_year between 1400 and 2200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (locality_id, city_id) references public.localities(id, city_id) on delete restrict,
  unique (id, city_id)
);
create index book_copies_owner_idx on public.book_copies(owner_id, created_at desc);
create index book_copies_discovery_idx on public.book_copies(city_id, locality_id, book_title_id) where listing_status = 'approved' and is_available_for_rent;
create index book_copies_title_idx on public.book_copies(book_title_id);

create table public.book_images (
  id uuid primary key default gen_random_uuid(),
  book_copy_id uuid not null references public.book_copies(id) on delete cascade,
  storage_bucket text not null default 'book-listing-public' check (storage_bucket = 'book-listing-public'),
  object_key text not null,
  alt_text text,
  display_order smallint not null default 0,
  is_cover boolean not null default false,
  moderation_status text not null default 'pending_review' check (moderation_status in ('pending_review','approved','rejected')),
  created_at timestamptz not null default now(),
  unique (storage_bucket, object_key)
);
create unique index book_images_one_cover_per_copy_uq on public.book_images(book_copy_id) where is_cover and moderation_status = 'approved';
create index book_images_copy_order_idx on public.book_images(book_copy_id, display_order);

create table public.book_condition_records (
  id uuid primary key default gen_random_uuid(),
  book_copy_id uuid not null references public.book_copies(id) on delete restrict,
  booking_id uuid,
  assessed_by uuid references auth.users(id) on delete restrict,
  condition public.copy_condition not null,
  notes text,
  assessed_at timestamptz not null default now(),
  source text not null check (source in ('listing','collection','return','admin_inspection','claim'))
);
create index book_condition_records_copy_time_idx on public.book_condition_records(book_copy_id, assessed_at desc);

create table public.book_availability_blocks (
  id uuid primary key default gen_random_uuid(),
  book_copy_id uuid not null references public.book_copies(id) on delete restrict,
  blocked_period tstzrange not null,
  reason text not null check (reason in ('owner_unavailable','maintenance','lost','damaged','admin_hold')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (not isempty(blocked_period)),
  check (lower_inc(blocked_period) and not upper_inc(blocked_period))
);
alter table public.book_availability_blocks
  add constraint book_availability_blocks_no_overlap
  exclude using gist (book_copy_id with =, blocked_period with &&);

create table public.book_pricing (
  id uuid primary key default gen_random_uuid(),
  book_copy_id uuid not null references public.book_copies(id) on delete restrict,
  currency char(3) not null default 'INR' check (currency = 'INR'),
  rental_3d_paise bigint check (rental_3d_paise is null or rental_3d_paise >= 0),
  rental_7d_paise bigint check (rental_7d_paise is null or rental_7d_paise >= 0),
  rental_15d_paise bigint check (rental_15d_paise is null or rental_15d_paise >= 0),
  rental_30d_paise bigint check (rental_30d_paise is null or rental_30d_paise >= 0),
  custom_daily_paise bigint check (custom_daily_paise is null or custom_daily_paise >= 0),
  min_custom_days integer,
  max_custom_days integer,
  effective_from timestamptz not null default now(),
  effective_until timestamptz,
  approved_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (effective_until is null or effective_until > effective_from),
  check ((min_custom_days is null and max_custom_days is null) or (min_custom_days >= 1 and max_custom_days >= min_custom_days))
);
create index book_pricing_current_idx on public.book_pricing(book_copy_id, effective_from desc);
create unique index book_pricing_one_open_version_uq on public.book_pricing(book_copy_id) where effective_until is null;

create table public.wishlists (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null default 'My wishlist',
  is_private boolean not null default true,
  created_at timestamptz not null default now(),
  unique (user_id, name)
);
create table public.wishlist_items (
  wishlist_id uuid not null references public.wishlists(id) on delete cascade,
  book_title_id uuid not null references public.book_titles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (wishlist_id, book_title_id)
);
create table public.book_recommendations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  book_title_id uuid not null references public.book_titles(id) on delete cascade,
  score numeric(8,6),
  reason_code text,
  model_version text,
  created_at timestamptz not null default now(),
  unique (user_id, book_title_id)
);

create trigger book_copies_updated_at before update on public.book_copies for each row execute function private.set_updated_at();
create trigger book_titles_updated_at before update on public.book_titles for each row execute function private.set_updated_at();

commit;

begin;

-- Approximate locality centres are optional and maintained by operations. Never store
-- a member's home/GPS coordinate in public discovery data.
alter table public.localities add column if not exists map_latitude numeric(9,6);
alter table public.localities add column if not exists map_longitude numeric(9,6);
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'localities_map_coordinate_pair_ck') then
    alter table public.localities add constraint localities_map_coordinate_pair_ck
      check ((map_latitude is null and map_longitude is null)
        or (map_latitude between -90 and 90 and map_longitude between -180 and 180));
  end if;
end $$;

create table public.book_copy_listing_details (
  book_copy_id uuid primary key references public.book_copies(id) on delete cascade,
  existing_damage text not null default '' check (length(existing_damage) <= 2000),
  original_price_paise bigint check (original_price_paise is null or original_price_paise >= 0),
  original_price_evidence_note text check (original_price_evidence_note is null or length(original_price_evidence_note) <= 1000),
  original_price_evidence_key text,
  requested_deposit_paise bigint not null default 0 check (requested_deposit_paise >= 0),
  deposit_feature_enabled boolean not null default false check (deposit_feature_enabled = false),
  ownership_declaration_type text not null check (ownership_declaration_type in ('lawful_owner','authorised_to_rent')),
  ownership_declaration_version text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (original_price_evidence_key is null or original_price_evidence_key !~ '(^/|\\.\\.)')
);

create table public.book_ownership_declarations (
  id uuid primary key default gen_random_uuid(),
  book_copy_id uuid not null references public.book_copies(id) on delete restrict,
  owner_id uuid not null references auth.users(id) on delete restrict,
  declaration_type text not null check (declaration_type in ('lawful_owner','authorised_to_rent')),
  declaration_version text not null,
  declaration_text text not null,
  accepted_at timestamptz not null default now(),
  withdrawn_at timestamptz,
  created_at timestamptz not null default now()
);
create index book_ownership_declarations_copy_idx on public.book_ownership_declarations(book_copy_id, accepted_at desc);

create table public.book_listing_moderation_events (
  id bigint generated always as identity primary key,
  book_copy_id uuid not null references public.book_copies(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete restrict,
  action text not null check (action in ('draft_saved','submitted','approved','rejected','suspended','resumed','removed','edited')),
  from_status public.listing_status,
  to_status public.listing_status not null,
  reason text,
  internal_notes text,
  created_at timestamptz not null default now()
);
create index book_listing_moderation_events_copy_idx on public.book_listing_moderation_events(book_copy_id, created_at desc);

create table public.book_waitlist_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  book_title_id uuid not null references public.book_titles(id) on delete cascade,
  city_id uuid not null references public.cities(id) on delete restrict,
  preferred_locality_id uuid,
  requested_start_at timestamptz,
  requested_end_at timestamptz,
  duration_days integer check (duration_days is null or duration_days in (3,7,15,30)),
  status text not null default 'waiting' check (status in ('waiting','notified','fulfilled','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (preferred_locality_id, city_id) references public.localities(id, city_id) on delete restrict,
  check ((requested_start_at is null and requested_end_at is null) or requested_end_at > requested_start_at)
);
create unique index book_waitlist_one_active_uq on public.book_waitlist_entries(user_id, book_title_id, city_id)
  where status in ('waiting','notified');
create index book_waitlist_discovery_idx on public.book_waitlist_entries(book_title_id, city_id, status, created_at);

create table public.book_bundles (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete restrict,
  city_id uuid not null references public.cities(id) on delete restrict,
  name text not null check (length(btrim(name)) between 3 and 80),
  description text check (description is null or length(description) <= 1000),
  status text not null default 'draft' check (status in ('draft','pending_review','approved','rejected','paused','removed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.book_bundle_items (
  bundle_id uuid not null references public.book_bundles(id) on delete cascade,
  book_copy_id uuid not null references public.book_copies(id) on delete restrict,
  display_order smallint not null default 0,
  primary key (bundle_id, book_copy_id)
);
create index book_bundles_discovery_idx on public.book_bundles(city_id, status, created_at desc);

-- Private evidence bucket for receipts/original-price evidence. Listing photos are private
-- at rest too; approved images are served only through short-lived signed URLs by Edge Function.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('listing-evidence-private','listing-evidence-private',false,10485760,
  array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do nothing;

create policy listing_photo_upload_own_copy on storage.objects for insert to authenticated
with check (
  bucket_id = 'book-listing-public'
  and (storage.foldername(name))[1] = auth.uid()::text
  and exists (
    select 1 from public.book_copies c
    where c.id::text = (storage.foldername(name))[2] and c.owner_id = auth.uid()
  )
);
create policy listing_photo_delete_own_copy on storage.objects for delete to authenticated
using (
  bucket_id = 'book-listing-public'
  and (storage.foldername(name))[1] = auth.uid()::text
  and exists (
    select 1 from public.book_copies c
    where c.id::text = (storage.foldername(name))[2] and c.owner_id = auth.uid()
  )
);
create policy listing_evidence_upload_own_copy on storage.objects for insert to authenticated
with check (
  bucket_id = 'listing-evidence-private'
  and (storage.foldername(name))[1] = auth.uid()::text
  and exists (
    select 1 from public.book_copies c
    where c.id::text = (storage.foldername(name))[2] and c.owner_id = auth.uid()
  )
);

alter table public.book_copy_listing_details enable row level security;
alter table public.book_ownership_declarations enable row level security;
alter table public.book_listing_moderation_events enable row level security;
alter table public.book_waitlist_entries enable row level security;
alter table public.book_bundles enable row level security;
alter table public.book_bundle_items enable row level security;

revoke all on public.book_copy_listing_details, public.book_ownership_declarations,
  public.book_listing_moderation_events, public.book_waitlist_entries,
  public.book_bundles, public.book_bundle_items from anon, authenticated;

-- Owner listing creation/editing is an atomic server operation. ISBN only identifies a
-- bibliographic edition; ownership is separately declared and can never be inferred from ISBN.
create or replace function public.save_book_listing(
  p_book_copy_id uuid,
  p_title jsonb,
  p_copy jsonb,
  p_pricing jsonb,
  p_listing_details jsonb,
  p_declaration_type text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_user uuid := auth.uid();
  v_copy public.book_copies%rowtype;
  v_title_id uuid;
  v_copy_id uuid;
  v_isbn text := nullif(regexp_replace(coalesce(p_title->>'isbn13',''), '[^0-9]', '', 'g'), '');
  v_authors text[];
  v_condition public.copy_condition;
  v_city uuid := nullif(p_copy->>'city_id','')::uuid;
  v_locality uuid := nullif(p_copy->>'locality_id','')::uuid;
  v_category uuid;
  v_has_copy boolean := false;
  v_r3 bigint := nullif(p_pricing->>'rental_3d_paise','')::bigint;
  v_r7 bigint := nullif(p_pricing->>'rental_7d_paise','')::bigint;
  v_r15 bigint := nullif(p_pricing->>'rental_15d_paise','')::bigint;
  v_r30 bigint := nullif(p_pricing->>'rental_30d_paise','')::bigint;
  v_custom bigint := nullif(p_pricing->>'custom_daily_paise','')::bigint;
  v_min_days integer := nullif(p_pricing->>'min_custom_days','')::integer;
  v_max_days integer := nullif(p_pricing->>'max_custom_days','')::integer;
  v_declaration text := 'I declare that I lawfully own this physical book or have authority to rent it to others. I will disclose existing damage and will not list a copy I do not have the right to lend.';
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists (
    select 1 from public.user_verifications uv
    join public.profiles p on p.id = uv.user_id
    where uv.user_id = v_user and uv.status = 'verified' and uv.age_eligible is true
      and p.account_status = 'active'
  ) then raise exception 'An active, identity-verified, age-eligible account is required to list books'; end if;

  if length(btrim(coalesce(p_title->>'title',''))) not between 1 and 240 then raise exception 'Book title is required'; end if;
  if length(btrim(coalesce(p_copy->>'condition',''))) = 0 then raise exception 'Copy condition is required'; end if;
  if p_declaration_type not in ('lawful_owner','authorised_to_rent') then raise exception 'A lawful ownership/rental-authority declaration is required'; end if;
  if v_isbn is not null and v_isbn !~ '^[0-9]{13}$' then raise exception 'ISBN must be a valid 13-digit normalized ISBN'; end if;
  if v_r3 < 0 or v_r7 < 0 or v_r15 < 0 or v_r30 < 0 or v_custom < 0 then raise exception 'Rental prices cannot be negative'; end if;
  if coalesce(v_r3,0) + coalesce(v_r7,0) + coalesce(v_r15,0) + coalesce(v_r30,0) + coalesce(v_custom,0) <= 0 then
    raise exception 'At least one positive rental price is required';
  end if;
  if (v_min_days is null) <> (v_max_days is null) or (v_min_days is not null and (v_min_days < 1 or v_max_days < v_min_days or v_max_days > 90)) then
    raise exception 'Custom rental duration must be between 1 and 90 days';
  end if;
  if not exists (select 1 from public.cities c where c.id=v_city and c.is_active and c.status='active')
     or not exists (select 1 from public.localities l where l.id=v_locality and l.city_id=v_city and l.is_active) then
    raise exception 'Choose an active city and locality';
  end if;

  begin
    v_condition := (p_copy->>'condition')::public.copy_condition;
  exception when others then
    raise exception 'Unsupported copy condition';
  end;

  select coalesce(array_agg(value), array[]::text[]) into v_authors
  from jsonb_array_elements_text(coalesce(p_title->'authors','[]'::jsonb)) as x(value);
  if cardinality(v_authors) = 0 then
    v_authors := array[coalesce(nullif(btrim(p_title->>'author'),''),'Unknown author')];
  end if;
  if exists (select 1 from unnest(v_authors) a where length(a) > 120) then raise exception 'Author name is too long'; end if;

  if p_book_copy_id is not null then
    select * into v_copy from public.book_copies where id=p_book_copy_id and owner_id=v_user for update;
    if not found then raise exception 'Listing not found'; end if;
    v_has_copy := true;
    if v_copy.listing_status not in ('draft','rejected','paused') then
      raise exception 'Only draft, rejected or paused listings can be edited; approved listings must be paused by an administrator first';
    end if;
    v_title_id := v_copy.book_title_id;
    if exists (
      select 1 from public.book_titles bt where bt.id=v_title_id and bt.moderation_status <> 'approved'
    ) and (select count(*) from public.book_copies c where c.book_title_id=v_title_id) = 1 then
      update public.book_titles set
        isbn13=v_isbn, title=btrim(p_title->>'title'), subtitle=nullif(btrim(p_title->>'subtitle'),''),
        edition=nullif(btrim(p_title->>'edition'),''), authors=v_authors,
        publisher=nullif(btrim(p_title->>'publisher'),''), language_code=nullif(btrim(p_title->>'language_code'),''),
        publication_year=nullif(p_title->>'publication_year','')::smallint,
        description=nullif(btrim(p_title->>'description'),''), cover_image_url=nullif(btrim(p_title->>'cover_image_url'),''),
        metadata_source=coalesce(nullif(p_title->>'metadata_source',''),'manual'),
        metadata_source_id=nullif(p_title->>'metadata_source_id',''), moderation_status='pending_review'
      where id=v_title_id;
    end if;
  else
    if v_isbn is not null then
      select id into v_title_id from public.book_titles where isbn13=v_isbn limit 1;
    end if;
    if v_title_id is null then
      insert into public.book_titles(
        isbn13,title,subtitle,edition,authors,publisher,language_code,publication_year,
        description,cover_image_url,metadata_source,metadata_source_id,moderation_status
      ) values (
        v_isbn,btrim(p_title->>'title'),nullif(btrim(p_title->>'subtitle'),''),
        nullif(btrim(p_title->>'edition'),''),v_authors,nullif(btrim(p_title->>'publisher'),''),
        nullif(btrim(p_title->>'language_code'),''),nullif(p_title->>'publication_year','')::smallint,
        nullif(btrim(p_title->>'description'),''),nullif(btrim(p_title->>'cover_image_url'),''),
        coalesce(nullif(p_title->>'metadata_source',''),'manual'),nullif(p_title->>'metadata_source_id',''),'pending_review'
      ) returning id into v_title_id;
    end if;
  end if;

  if not exists (
    select 1 from public.categories c
    where c.is_active and (c.slug=lower(coalesce(p_title->>'genre','')) or lower(c.name)=lower(coalesce(p_title->>'genre','')))
  ) then raise exception 'Choose a genre from the active catalogue'; end if;
  select id into v_category from public.categories c
    where c.is_active and (c.slug=lower(p_title->>'genre') or lower(c.name)=lower(p_title->>'genre')) limit 1;
  insert into public.book_title_categories(book_title_id,category_id)
  values(v_title_id,v_category) on conflict do nothing;

  if v_has_copy then
    update public.book_copies set
      city_id=v_city, locality_id=v_locality, condition_summary=v_condition,
      description=nullif(btrim(p_copy->>'description'),''), owner_reference=nullif(btrim(p_copy->>'owner_reference'),''),
      acquisition_year=nullif(p_copy->>'acquisition_year','')::smallint,
      listing_status='draft', is_available_for_rent=false
    where id=v_copy.id;
    v_copy_id := v_copy.id;
  else
    insert into public.book_copies(
      book_title_id,owner_id,city_id,locality_id,owner_reference,condition_summary,description,
      listing_status,is_available_for_rent,acquisition_year
    ) values (
      v_title_id,v_user,v_city,v_locality,nullif(btrim(p_copy->>'owner_reference'),''),
      v_condition,nullif(btrim(p_copy->>'description'),''),'draft',false,
      nullif(p_copy->>'acquisition_year','')::smallint
    ) returning id into v_copy_id;
  end if;

  update public.book_pricing set effective_until=now()
    where book_copy_id=v_copy_id and effective_until is null;
  insert into public.book_pricing(
    book_copy_id,rental_3d_paise,rental_7d_paise,rental_15d_paise,rental_30d_paise,
    custom_daily_paise,min_custom_days,max_custom_days
  ) values(v_copy_id,v_r3,v_r7,v_r15,v_r30,v_custom,v_min_days,v_max_days);

  insert into public.book_copy_listing_details(
    book_copy_id,existing_damage,original_price_paise,original_price_evidence_note,
    requested_deposit_paise,deposit_feature_enabled,ownership_declaration_type,ownership_declaration_version
  ) values(
    v_copy_id,left(coalesce(p_listing_details->>'existing_damage',''),2000),
    nullif(p_listing_details->>'original_price_paise','')::bigint,
    nullif(left(p_listing_details->>'original_price_evidence_note',1000),''),
    coalesce(nullif(p_listing_details->>'requested_deposit_paise','')::bigint,0),
    false,p_declaration_type,'2026-10-v1'
  )
  on conflict(book_copy_id) do update set
    existing_damage=excluded.existing_damage,
    original_price_paise=excluded.original_price_paise,
    original_price_evidence_note=excluded.original_price_evidence_note,
    requested_deposit_paise=excluded.requested_deposit_paise,
    ownership_declaration_type=excluded.ownership_declaration_type,
    updated_at=now();

  if not exists (
    select 1 from public.book_ownership_declarations d
    where d.book_copy_id=v_copy_id and d.owner_id=v_user and d.withdrawn_at is null
  ) then
    insert into public.book_ownership_declarations(book_copy_id,owner_id,declaration_type,declaration_version,declaration_text)
    values(v_copy_id,v_user,p_declaration_type,'2026-10-v1',v_declaration);
  end if;

  insert into public.book_condition_records(book_copy_id,assessed_by,condition,notes,source)
  values(v_copy_id,v_user,v_condition,left(coalesce(p_listing_details->>'existing_damage',''),1000),'listing');

  insert into public.book_listing_moderation_events(book_copy_id,actor_user_id,action,to_status)
  values(v_copy_id,v_user,'draft_saved','draft');

  return v_copy_id;
end;
$$;
revoke all on function public.save_book_listing(uuid,jsonb,jsonb,jsonb,jsonb,text) from public,anon;
grant execute on function public.save_book_listing(uuid,jsonb,jsonb,jsonb,jsonb,text) to authenticated;

create or replace function public.register_book_listing_image(
  p_book_copy_id uuid,p_object_key text,p_alt_text text,p_is_cover boolean,p_display_order smallint
)
returns uuid
language plpgsql security definer
set search_path = pg_catalog, public, auth, storage
as $$
declare v_user uuid:=auth.uid(); v_image uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.book_copies where id=p_book_copy_id and owner_id=v_user and listing_status in ('draft','rejected','paused')) then
    raise exception 'Listing is not editable by this user';
  end if;
  if p_object_key !~ ('^'||v_user::text||'/'||p_book_copy_id::text||'/[A-Za-z0-9._-]+$') then
    raise exception 'Invalid listing image path';
  end if;
  if not exists(select 1 from storage.objects where bucket_id='book-listing-public' and name=p_object_key) then
    raise exception 'Uploaded image was not found';
  end if;
  insert into public.book_images(book_copy_id,object_key,alt_text,display_order,is_cover,moderation_status)
  values(p_book_copy_id,p_object_key,left(p_alt_text,240),greatest(0,p_display_order),p_is_cover,'pending_review')
  returning id into v_image;
  return v_image;
end;
$$;
revoke all on function public.register_book_listing_image(uuid,text,text,boolean,smallint) from public,anon;
grant execute on function public.register_book_listing_image(uuid,text,text,boolean,smallint) to authenticated;

create or replace function public.register_book_price_evidence(
  p_book_copy_id uuid,p_object_key text,p_note text
)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, storage
as $$
declare v_user uuid:=auth.uid();
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.book_copies where id=p_book_copy_id and owner_id=v_user and listing_status in ('draft','rejected','paused')) then
    raise exception 'Listing is not editable by this user';
  end if;
  if p_object_key !~ ('^'||v_user::text||'/'||p_book_copy_id::text||'/evidence/[A-Za-z0-9._-]+$') then raise exception 'Invalid evidence path'; end if;
  if not exists(select 1 from storage.objects where bucket_id='listing-evidence-private' and name=p_object_key) then raise exception 'Evidence file not found'; end if;
  update public.book_copy_listing_details set original_price_evidence_key=p_object_key,
    original_price_evidence_note=left(p_note,1000),updated_at=now()
  where book_copy_id=p_book_copy_id;
end;
$$;
revoke all on function public.register_book_price_evidence(uuid,text,text) from public,anon;
grant execute on function public.register_book_price_evidence(uuid,text,text) to authenticated;

create or replace function public.submit_book_listing(p_book_copy_id uuid)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_user uuid:=auth.uid(); v_title uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.user_verifications v join public.profiles p on p.id=v.user_id
    where v.user_id=v_user and v.status='verified' and v.age_eligible is true and p.account_status='active') then
    raise exception 'Active identity verification is required';
  end if;
  select book_title_id into v_title from public.book_copies
    where id=p_book_copy_id and owner_id=v_user and listing_status in ('draft','rejected');
  if not found then raise exception 'Draft or rejected listing not found'; end if;
  if (select count(*) from public.book_images i where i.book_copy_id=p_book_copy_id and i.moderation_status='pending_review') < 2 then
    raise exception 'At least two actual photographs of this physical copy are required';
  end if;
  if not exists(select 1 from public.book_ownership_declarations d where d.book_copy_id=p_book_copy_id and d.owner_id=v_user and d.withdrawn_at is null) then
    raise exception 'Ownership/rental-authority declaration is required';
  end if;
  if not exists(select 1 from public.book_pricing p where p.book_copy_id=p_book_copy_id and p.effective_until is null
    and (coalesce(p.rental_3d_paise,0)+coalesce(p.rental_7d_paise,0)+coalesce(p.rental_15d_paise,0)+coalesce(p.rental_30d_paise,0)+coalesce(p.custom_daily_paise,0))>0) then
    raise exception 'A valid rental price is required';
  end if;
  update public.book_copies set listing_status='pending_review',is_available_for_rent=false where id=p_book_copy_id;
  insert into public.book_listing_moderation_events(book_copy_id,actor_user_id,action,from_status,to_status)
  values(p_book_copy_id,v_user,'submitted','draft','pending_review');
end;
$$;
revoke all on function public.submit_book_listing(uuid) from public,anon;
grant execute on function public.submit_book_listing(uuid) to authenticated;

create or replace function public.get_my_book_listings()
returns jsonb
language sql stable security definer
set search_path = pg_catalog, public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'listing_status',c.listing_status,'is_available_for_rent',c.is_available_for_rent,
    'condition',c.condition_summary,'city_id',c.city_id,'locality_id',c.locality_id,
    'title',t.title,'authors',t.authors,'isbn13',t.isbn13,'edition',t.edition,'publisher',t.publisher,
    'cover_image_url',t.cover_image_url,'city',ci.name,'locality',l.name,
    'images',(select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'object_key',i.object_key,'moderation_status',i.moderation_status,'is_cover',i.is_cover) order by i.display_order),'[]'::jsonb) from public.book_images i where i.book_copy_id=c.id),
    'pricing',(select to_jsonb(p) - 'book_copy_id' from public.book_pricing p where p.book_copy_id=c.id order by p.effective_from desc limit 1),
    'details',(select to_jsonb(d) - 'book_copy_id' from public.book_copy_listing_details d where d.book_copy_id=c.id)
  ) order by c.created_at desc),'[]'::jsonb)
  from public.book_copies c
  join public.book_titles t on t.id=c.book_title_id
  join public.cities ci on ci.id=c.city_id
  join public.localities l on l.id=c.locality_id
  where c.owner_id=auth.uid();
$$;
revoke all on function public.get_my_book_listings() from public,anon;
grant execute on function public.get_my_book_listings() to authenticated;

create or replace function public.create_owner_availability_block(
  p_book_copy_id uuid,p_start_at timestamptz,p_end_at timestamptz,p_reason text default 'owner_unavailable'
)
returns uuid
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_id uuid; v_user uuid:=auth.uid();
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_end_at<=p_start_at or p_start_at<now() then raise exception 'Choose a future availability interval'; end if;
  if p_reason not in ('owner_unavailable','maintenance') then raise exception 'Unsupported owner block reason'; end if;
  if not exists(select 1 from public.book_copies where id=p_book_copy_id and owner_id=v_user and listing_status in ('approved','draft','pending_review')) then
    raise exception 'Listing not found or not owned';
  end if;
  insert into public.book_availability_blocks(book_copy_id,blocked_period,reason,created_by)
  values(p_book_copy_id,tstzrange(p_start_at,p_end_at,'[)'),p_reason,v_user) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.create_owner_availability_block(uuid,timestamptz,timestamptz,text) from public,anon;
grant execute on function public.create_owner_availability_block(uuid,timestamptz,timestamptz,text) to authenticated;

create or replace function public.delete_owner_availability_block(p_block_id uuid)
returns void
language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  delete from public.book_availability_blocks b
  using public.book_copies c
  where b.id=p_block_id and c.id=b.book_copy_id and c.owner_id=auth.uid()
    and b.reason in ('owner_unavailable','maintenance') and lower(b.blocked_period)>now();
  if not found then raise exception 'Future owner-created block not found'; end if;
end;
$$;
revoke all on function public.delete_owner_availability_block(uuid) from public,anon;
grant execute on function public.delete_owner_availability_block(uuid) to authenticated;

create or replace function public.join_book_waitlist(
  p_book_title_id uuid,p_city_id uuid,p_locality_id uuid default null,
  p_start_at timestamptz default null,p_end_at timestamptz default null,p_duration_days integer default null
)
returns uuid
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.user_verifications v join public.profiles p on p.id=v.user_id
    where v.user_id=auth.uid() and v.status='verified' and v.age_eligible is true and p.account_status='active') then
    raise exception 'An active verified account is required to join a rental waitlist';
  end if;
  if not exists(select 1 from public.book_titles where id=p_book_title_id and moderation_status='approved') then raise exception 'Book edition not found'; end if;
  if p_locality_id is not null and not exists(select 1 from public.localities where id=p_locality_id and city_id=p_city_id and is_active) then raise exception 'Invalid preferred locality'; end if;
  if (p_start_at is null) <> (p_end_at is null) or (p_end_at is not null and p_end_at<=p_start_at) then raise exception 'Invalid preferred date range'; end if;
  insert into public.book_waitlist_entries(user_id,book_title_id,city_id,preferred_locality_id,requested_start_at,requested_end_at,duration_days)
  values(auth.uid(),p_book_title_id,p_city_id,p_locality_id,p_start_at,p_end_at,p_duration_days)
  on conflict(user_id,book_title_id,city_id) where status in ('waiting','notified')
  do update set preferred_locality_id=excluded.preferred_locality_id,requested_start_at=excluded.requested_start_at,
    requested_end_at=excluded.requested_end_at,duration_days=excluded.duration_days,updated_at=now()
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.join_book_waitlist(uuid,uuid,uuid,timestamptz,timestamptz,integer) from public,anon;
grant execute on function public.join_book_waitlist(uuid,uuid,uuid,timestamptz,timestamptz,integer) to authenticated;

create or replace function public.leave_book_waitlist(p_entry_id uuid)
returns void
language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  update public.book_waitlist_entries set status='cancelled',updated_at=now()
    where id=p_entry_id and user_id=auth.uid() and status in ('waiting','notified');
  if not found then raise exception 'Active waitlist entry not found'; end if;
end;
$$;
revoke all on function public.leave_book_waitlist(uuid) from public,anon;
grant execute on function public.leave_book_waitlist(uuid) to authenticated;

create or replace function public.create_book_bundle(p_name text,p_description text,p_book_copy_ids uuid[])
returns uuid
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_id uuid; v_city uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.user_verifications v join public.profiles p on p.id=v.user_id
    where v.user_id=auth.uid() and v.status='verified' and v.age_eligible is true and p.account_status='active') then
    raise exception 'An active verified account is required to create a bundle';
  end if;
  if coalesce(array_length(p_book_copy_ids,1),0) not between 2 and 5 then raise exception 'A bundle must contain two to five copies'; end if;
  if (select count(distinct x) from unnest(p_book_copy_ids) x)<>array_length(p_book_copy_ids,1) then raise exception 'Duplicate copies are not allowed'; end if;
  select min(city_id) into v_city from public.book_copies where id=any(p_book_copy_ids) and owner_id=auth.uid() and listing_status='approved';
  if v_city is null or (select count(*) from public.book_copies where id=any(p_book_copy_ids) and owner_id=auth.uid() and listing_status='approved' and city_id=v_city)<>array_length(p_book_copy_ids,1) then
    raise exception 'All bundle copies must be approved listings owned by you in the same city';
  end if;
  insert into public.book_bundles(owner_id,city_id,name,description,status)
    values(auth.uid(),v_city,btrim(p_name),left(p_description,1000),'pending_review') returning id into v_id;
  insert into public.book_bundle_items(bundle_id,book_copy_id,display_order)
    select v_id,x,ord::smallint from unnest(p_book_copy_ids) with ordinality t(x,ord);
  return v_id;
end;
$$;
revoke all on function public.create_book_bundle(text,text,uuid[]) from public,anon;
grant execute on function public.create_book_bundle(text,text,uuid[]) to authenticated;

create or replace function public.review_book_listing(p_book_copy_id uuid,p_action text,p_reason text,p_internal_notes text default null)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_actor uuid:=auth.uid(); v_copy public.book_copies%rowtype; v_status public.listing_status; v_to public.listing_status;
begin
  if v_actor is null or not (private.has_role('moderator') or private.has_role('admin') or private.has_role('super_admin')) then
    raise exception 'Moderator permission required';
  end if;
  select * into v_copy from public.book_copies where id=p_book_copy_id for update;
  if not found then raise exception 'Listing not found'; end if;
  if v_copy.owner_id=v_actor then raise exception 'A moderator cannot approve or decide their own listing'; end if;
  if v_copy.listing_status not in ('pending_review','approved','paused') then raise exception 'Listing is not reviewable in the current state'; end if;
  if p_reason is null or length(btrim(p_reason))<5 then raise exception 'A decision reason of at least five characters is required'; end if;
  if p_action not in ('approve','reject','suspend','remove') then raise exception 'Unsupported moderation action'; end if;
  v_status:=v_copy.listing_status;
  if p_action='approve' then v_to:='approved';
    update public.book_titles set moderation_status='approved' where id=v_copy.book_title_id;
    update public.book_images set moderation_status='approved' where book_copy_id=p_book_copy_id;
    update public.book_copies set listing_status='approved',is_available_for_rent=true where id=p_book_copy_id;
  elsif p_action='reject' then v_to:='rejected';
    update public.book_images set moderation_status='rejected' where book_copy_id=p_book_copy_id;
    update public.book_copies set listing_status='rejected',is_available_for_rent=false where id=p_book_copy_id;
  elsif p_action='suspend' then v_to:='paused';
    update public.book_copies set listing_status='paused',is_available_for_rent=false where id=p_book_copy_id;
  else v_to:='removed';
    update public.book_copies set listing_status='removed',is_available_for_rent=false where id=p_book_copy_id;
  end if;
  insert into public.book_listing_moderation_events(book_copy_id,actor_user_id,action,from_status,to_status,reason,internal_notes)
  values(p_book_copy_id,v_actor,p_action,v_status,v_to,left(p_reason,1000),left(p_internal_notes,4000));
end;
$$;
revoke all on function public.review_book_listing(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.review_book_listing(uuid,text,text,text) to authenticated;

create or replace function public.search_book_listings(p_filters jsonb default '{}'::jsonb,p_limit integer default 12,p_offset integer default 0)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_q text:=left(coalesce(p_filters->>'query',''),120);
  v_city text:=nullif(p_filters->>'city','');
  v_locality text:=nullif(p_filters->>'locality','');
  v_genre text:=nullif(p_filters->>'genre','');
  v_language text:=nullif(p_filters->>'language','');
  v_edition text:=nullif(p_filters->>'edition','');
  v_condition text:=nullif(p_filters->>'condition','');
  v_isbn text:=nullif(regexp_replace(coalesce(p_filters->>'isbn',''),'[^0-9]','','g'),'');
  v_author text:=nullif(p_filters->>'author','');
  v_min bigint:=nullif(p_filters->>'min_price_paise','')::bigint;
  v_max bigint:=nullif(p_filters->>'max_price_paise','')::bigint;
  v_days integer:=nullif(p_filters->>'duration_days','')::integer;
  v_from timestamptz:=nullif(p_filters->>'available_from','')::timestamptz;
  v_until timestamptz:=nullif(p_filters->>'available_until','')::timestamptz;
  v_lat numeric:=nullif(p_filters->>'latitude','')::numeric;
  v_lon numeric:=nullif(p_filters->>'longitude','')::numeric;
  v_radius numeric:=nullif(p_filters->>'radius_km','')::numeric;
  v_limit integer:=least(30,greatest(1,coalesce(p_limit,12)));
  v_offset integer:=greatest(0,coalesce(p_offset,0));
  v_total bigint:=0;
  v_results jsonb:='[]'::jsonb;
begin
  if v_min is not null and v_min<0 or v_max is not null and v_max<0 or (v_min is not null and v_max is not null and v_max<v_min) then
    raise exception 'Invalid price range';
  end if;
  if v_days is not null and v_days not in (3,7,15,30) and v_days not between 1 and 90 then raise exception 'Unsupported rental duration'; end if;
  if (v_from is null) <> (v_until is null) or (v_until is not null and v_until<=v_from) then raise exception 'Invalid availability range'; end if;
  if (v_lat is null) <> (v_lon is null) or (v_lat is not null and (v_lat not between -90 and 90 or v_lon not between -180 and 180)) then raise exception 'Invalid map centre'; end if;

  with candidates as (
    select c.id,c.book_title_id,t.title,t.authors,t.isbn13,t.publisher,t.edition,t.publication_year,t.language_code,
      t.description as book_description,t.cover_image_url,c.condition_summary,c.description as copy_description,
      c.city_id,ci.name as city_name,c.locality_id,l.name as locality_name,l.map_latitude,l.map_longitude,
      d.existing_damage,d.original_price_paise,d.requested_deposit_paise,
      case when v_days=3 then pr.rental_3d_paise
        when v_days=7 then pr.rental_7d_paise
        when v_days=15 then pr.rental_15d_paise
        when v_days=30 then pr.rental_30d_paise
        when v_days is not null and pr.custom_daily_paise is not null
          and (pr.min_custom_days is null or v_days between pr.min_custom_days and pr.max_custom_days) then pr.custom_daily_paise*v_days
        else coalesce(pr.rental_7d_paise,pr.rental_3d_paise,pr.rental_15d_paise,pr.rental_30d_paise,
          case when pr.custom_daily_paise is not null then pr.custom_daily_paise*greatest(1,coalesce(pr.min_custom_days,1)) end)
      end as price_paise,
      case when v_lat is not null and l.map_latitude is not null then
        6371*2*asin(sqrt(least(1,
          power(sin(radians((l.map_latitude-v_lat)::double precision)/2),2)
          +cos(radians(v_lat::double precision))*cos(radians(l.map_latitude::double precision))
          *power(sin(radians((l.map_longitude-v_lon)::double precision)/2),2))))
        else null end as distance_km,
      exists(select 1 from public.user_verifications uv where uv.user_id=c.owner_id and uv.status='verified' and uv.age_eligible is true) as owner_verified,
      (select coalesce(jsonb_agg(jsonb_build_object('object_key',i.object_key,'alt_text',i.alt_text,'is_cover',i.is_cover) order by i.is_cover desc,i.display_order),'[]'::jsonb)
        from public.book_images i where i.book_copy_id=c.id and i.moderation_status='approved') as image_keys,
      (select coalesce(string_agg(cat.name,', '),'') from public.book_title_categories btc
        join public.categories cat on cat.id=btc.category_id where btc.book_title_id=t.id and cat.is_active) as genres,
      case when v_city is not null and lower(ci.name)=lower(v_city) then 4 else 0 end
        + case when v_locality is not null and lower(l.name)=lower(v_locality) then 3 else 0 end
        + case when v_genre is not null and exists(select 1 from public.book_title_categories btc join public.categories cat on cat.id=btc.category_id
            where btc.book_title_id=t.id and lower(cat.slug)=lower(v_genre)) then 2 else 0 end
        + case when exists(select 1 from public.wishlist_items wi join public.wishlists w on w.id=wi.wishlist_id
            where w.user_id=auth.uid() and wi.book_title_id=t.id) then 3 else 0 end as recommendation_score
    from public.book_copies c
    join public.book_titles t on t.id=c.book_title_id
    join public.cities ci on ci.id=c.city_id
    join public.localities l on l.id=c.locality_id
    join lateral (select * from public.book_pricing pp where pp.book_copy_id=c.id and pp.effective_from<=now()
      and (pp.effective_until is null or pp.effective_until>now()) order by pp.effective_from desc limit 1) pr on true
    left join public.book_copy_listing_details d on d.book_copy_id=c.id
    where c.listing_status='approved' and c.is_available_for_rent
      and t.moderation_status='approved' and ci.is_active and ci.status='active' and l.is_active
      and (v_q='' or lower(t.title||' '||array_to_string(t.authors,' ')||' '||coalesce(t.isbn13,'')||' '||coalesce(t.publisher,'')||' '||coalesce(t.description,'')) like '%'||lower(v_q)||'%')
      and (v_author is null or exists(select 1 from unnest(t.authors) a where lower(a) like '%'||lower(v_author)||'%'))
      and (v_isbn is null or t.isbn13 like '%'||v_isbn||'%')
      and (v_city is null or lower(ci.name)=lower(v_city))
      and (v_locality is null or lower(l.name)=lower(v_locality))
      and (v_genre is null or exists(select 1 from public.book_title_categories btc join public.categories cat on cat.id=btc.category_id
        where btc.book_title_id=t.id and cat.is_active and (lower(cat.slug)=lower(v_genre) or lower(cat.name)=lower(v_genre))))
      and (v_language is null or lower(coalesce(t.language_code,''))=lower(v_language))
      and (v_edition is null or lower(coalesce(t.edition,'')) like '%'||lower(v_edition)||'%')
      and (v_condition is null or c.condition_summary::text=v_condition)
      and (not (p_filters ? 'min_price_paise') or pr.rental_3d_paise is not null or pr.rental_7d_paise is not null or pr.rental_15d_paise is not null or pr.rental_30d_paise is not null or pr.custom_daily_paise is not null)
      and (v_from is null or not exists(select 1 from public.book_availability_blocks b where b.book_copy_id=c.id and b.blocked_period && tstzrange(v_from,v_until,'[)')))
      and (v_from is null or not exists(select 1 from public.copy_reservations r where r.book_copy_id=c.id and r.status in ('hold','confirmed','in_use')
        and (r.status<>'hold' or r.expires_at is null or r.expires_at>now()) and r.reserved_period && tstzrange(v_from,v_until,'[)')))
  )
  select count(*) into v_total from candidates
  where price_paise is not null and (v_min is null or price_paise>=v_min) and (v_max is null or price_paise<=v_max)
    and (v_lat is null or distance_km is not null) and (v_radius is null or distance_km<=v_radius);

  with candidates as (
    select c.id,c.book_title_id,t.title,t.authors,t.isbn13,t.publisher,t.edition,t.publication_year,t.language_code,
      t.description as book_description,t.cover_image_url,c.condition_summary,c.description as copy_description,
      ci.name as city_name,l.name as locality_name,l.map_latitude,l.map_longitude,
      d.existing_damage,d.original_price_paise,d.requested_deposit_paise,
      case when v_days=3 then pr.rental_3d_paise when v_days=7 then pr.rental_7d_paise
        when v_days=15 then pr.rental_15d_paise when v_days=30 then pr.rental_30d_paise
        when v_days is not null and pr.custom_daily_paise is not null and (pr.min_custom_days is null or v_days between pr.min_custom_days and pr.max_custom_days) then pr.custom_daily_paise*v_days
        else coalesce(pr.rental_7d_paise,pr.rental_3d_paise,pr.rental_15d_paise,pr.rental_30d_paise,
          case when pr.custom_daily_paise is not null then pr.custom_daily_paise*greatest(1,coalesce(pr.min_custom_days,1)) end) end as price_paise,
      case when v_lat is not null and l.map_latitude is not null then
        6371*2*asin(sqrt(least(1,power(sin(radians((l.map_latitude-v_lat)::double precision)/2),2)
          +cos(radians(v_lat::double precision))*cos(radians(l.map_latitude::double precision))
          *power(sin(radians((l.map_longitude-v_lon)::double precision)/2),2)))) else null end as distance_km,
      exists(select 1 from public.user_verifications uv where uv.user_id=c.owner_id and uv.status='verified' and uv.age_eligible is true) as owner_verified,
      (select coalesce(jsonb_agg(jsonb_build_object('object_key',i.object_key,'alt_text',i.alt_text,'is_cover',i.is_cover) order by i.is_cover desc,i.display_order),'[]'::jsonb)
        from public.book_images i where i.book_copy_id=c.id and i.moderation_status='approved') as image_keys,
      (select coalesce(string_agg(cat.name,', '),'') from public.book_title_categories btc join public.categories cat on cat.id=btc.category_id
        where btc.book_title_id=t.id and cat.is_active) as genres,
      case when v_city is not null and lower(ci.name)=lower(v_city) then 4 else 0 end
        + case when v_locality is not null and lower(l.name)=lower(v_locality) then 3 else 0 end
        + case when v_genre is not null and exists(select 1 from public.book_title_categories btc join public.categories cat on cat.id=btc.category_id
            where btc.book_title_id=t.id and lower(cat.slug)=lower(v_genre)) then 2 else 0 end
        + case when exists(select 1 from public.wishlist_items wi join public.wishlists w on w.id=wi.wishlist_id
            where w.user_id=auth.uid() and wi.book_title_id=t.id) then 3 else 0 end as recommendation_score
    from public.book_copies c join public.book_titles t on t.id=c.book_title_id
    join public.cities ci on ci.id=c.city_id join public.localities l on l.id=c.locality_id
    join lateral (select * from public.book_pricing pp where pp.book_copy_id=c.id and pp.effective_from<=now()
      and (pp.effective_until is null or pp.effective_until>now()) order by pp.effective_from desc limit 1) pr on true
    left join public.book_copy_listing_details d on d.book_copy_id=c.id
    where c.listing_status='approved' and c.is_available_for_rent and t.moderation_status='approved'
      and ci.is_active and ci.status='active' and l.is_active
      and (v_q='' or lower(t.title||' '||array_to_string(t.authors,' ')||' '||coalesce(t.isbn13,'')||' '||coalesce(t.publisher,'')||' '||coalesce(t.description,'')) like '%'||lower(v_q)||'%')
      and (v_author is null or exists(select 1 from unnest(t.authors) a where lower(a) like '%'||lower(v_author)||'%'))
      and (v_isbn is null or t.isbn13 like '%'||v_isbn||'%')
      and (v_city is null or lower(ci.name)=lower(v_city)) and (v_locality is null or lower(l.name)=lower(v_locality))
      and (v_genre is null or exists(select 1 from public.book_title_categories btc join public.categories cat on cat.id=btc.category_id where btc.book_title_id=t.id and cat.is_active and (lower(cat.slug)=lower(v_genre) or lower(cat.name)=lower(v_genre))))
      and (v_language is null or lower(coalesce(t.language_code,''))=lower(v_language))
      and (v_edition is null or lower(coalesce(t.edition,'')) like '%'||lower(v_edition)||'%')
      and (v_condition is null or c.condition_summary::text=v_condition)
      and (v_from is null or not exists(select 1 from public.book_availability_blocks b where b.book_copy_id=c.id and b.blocked_period && tstzrange(v_from,v_until,'[)')))
      and (v_from is null or not exists(select 1 from public.copy_reservations r where r.book_copy_id=c.id and r.status in ('hold','confirmed','in_use')
        and (r.status<>'hold' or r.expires_at is null or r.expires_at>now()) and r.reserved_period && tstzrange(v_from,v_until,'[)')))
  )
  select coalesce(jsonb_agg(row_data order by sort_key, title), '[]'::jsonb) into v_results
  from (
    select jsonb_build_object(
      'id',id,'book_title_id',book_title_id,'title',title,'authors',authors,'isbn13',isbn13,
      'publisher',publisher,'edition',edition,'publication_year',publication_year,'language_code',language_code,
      'description',book_description,'copy_description',copy_description,'cover_image_url',cover_image_url,
      'genres',genres,'condition',condition_summary,'existing_damage',existing_damage,
      'original_price_paise',original_price_paise,'requested_deposit_paise',requested_deposit_paise,
      'price_paise',price_paise,'city',city_name,'locality',locality_name,
      'latitude',map_latitude,'longitude',map_longitude,'distance_km',distance_km,
      'owner_verified',owner_verified,'images',image_keys
    ) as row_data,
    case when coalesce(p_filters->>'sort','')='price_low' then price_paise::numeric
      when coalesce(p_filters->>'sort','')='price_high' then -price_paise::numeric
      when coalesce(p_filters->>'sort','')='distance' then coalesce(distance_km,999999)::numeric
      when coalesce(p_filters->>'sort','')='recommended' then -recommendation_score::numeric
      else 0::numeric end as sort_key,title
    from candidates
    where price_paise is not null and (v_min is null or price_paise>=v_min) and (v_max is null or price_paise<=v_max)
      and (v_lat is null or distance_km is not null) and (v_radius is null or distance_km<=v_radius)
    order by sort_key,title limit v_limit offset v_offset
  ) page;
  return jsonb_build_object('total',v_total,'page',floor(v_offset::numeric/v_limit)+1,'page_size',v_limit,'results',v_results);
end;
$$;
revoke all on function public.search_book_listings(jsonb,integer,integer) from public,anon,authenticated;
grant execute on function public.search_book_listings(jsonb,integer,integer) to service_role;

create or replace function public.get_public_book_bundles(p_city text default null)
returns jsonb
language sql stable security definer
set search_path = pg_catalog, public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',b.id,'name',b.name,'description',b.description,'city',c.name,
    'items',(select coalesce(jsonb_agg(jsonb_build_object('copy_id',bc.id,'title',bt.title,'author',array_to_string(bt.authors,', '),'locality',l.name)
      order by bi.display_order),'[]'::jsonb)
      from public.book_bundle_items bi join public.book_copies bc on bc.id=bi.book_copy_id
      join public.book_titles bt on bt.id=bc.book_title_id join public.localities l on l.id=bc.locality_id
      where bi.bundle_id=b.id and bc.listing_status='approved' and bc.is_available_for_rent and bt.moderation_status='approved')
  ) order by b.created_at desc),'[]'::jsonb)
  from public.book_bundles b join public.cities c on c.id=b.city_id
  where b.status='approved' and (p_city is null or lower(c.name)=lower(p_city))
    and c.is_active and c.status='active';
$$;
revoke all on function public.get_public_book_bundles(text) from public,anon,authenticated;
grant execute on function public.get_public_book_bundles(text) to service_role;

create trigger book_copy_listing_details_updated_at before update on public.book_copy_listing_details
for each row execute function private.set_updated_at();

commit;

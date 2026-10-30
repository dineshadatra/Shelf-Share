begin;

create table public.book_listing_image_access_audit (
  id bigint generated always as identity primary key,
  book_copy_id uuid not null references public.book_copies(id) on delete restrict,
  book_image_id uuid not null references public.book_images(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  purpose text not null check (length(btrim(purpose)) between 5 and 500),
  accessed_at timestamptz not null default now()
);
create index book_listing_image_access_audit_copy_time_idx
  on public.book_listing_image_access_audit(book_copy_id, accessed_at desc);
alter table public.book_listing_image_access_audit enable row level security;
revoke all on public.book_listing_image_access_audit from anon,authenticated;

-- A wish-list toggle operates only on the caller's default list.
create or replace function public.toggle_book_wishlist(p_book_title_id uuid)
returns boolean
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_wishlist uuid; v_removed boolean:=false;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.book_titles where id=p_book_title_id and moderation_status='approved') then
    raise exception 'Book edition is not available';
  end if;
  insert into public.wishlists(user_id,name,is_private)
    values(auth.uid(),'My wishlist',true)
  on conflict(user_id,name) do update set is_private=true
  returning id into v_wishlist;
  delete from public.wishlist_items where wishlist_id=v_wishlist and book_title_id=p_book_title_id;
  get diagnostics v_removed = row_count;
  if not v_removed then
    insert into public.wishlist_items(wishlist_id,book_title_id) values(v_wishlist,p_book_title_id);
  end if;
  return not v_removed;
end;
$$;
revoke all on function public.toggle_book_wishlist(uuid) from public,anon;
grant execute on function public.toggle_book_wishlist(uuid) to authenticated;

create or replace function public.get_my_book_waitlist()
returns jsonb
language sql stable security definer
set search_path = pg_catalog, public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',w.id,'book_title_id',w.book_title_id,'title',t.title,'authors',t.authors,
    'city',c.name,'locality',l.name,'status',w.status,'created_at',w.created_at,
    'requested_start_at',w.requested_start_at,'requested_end_at',w.requested_end_at
  ) order by w.created_at desc),'[]'::jsonb)
  from public.book_waitlist_entries w
  join public.book_titles t on t.id=w.book_title_id
  join public.cities c on c.id=w.city_id
  left join public.localities l on l.id=w.preferred_locality_id
  where w.user_id=auth.uid();
$$;
revoke all on function public.get_my_book_waitlist() from public,anon;
grant execute on function public.get_my_book_waitlist() to authenticated;

create or replace function public.review_book_bundle(p_bundle_id uuid,p_action text,p_reason text)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_bundle public.book_bundles%rowtype;
begin
  if auth.uid() is null or not (private.has_role('moderator') or private.has_role('admin') or private.has_role('super_admin')) then
    raise exception 'Moderator permission required';
  end if;
  select * into v_bundle from public.book_bundles where id=p_bundle_id for update;
  if not found then raise exception 'Bundle not found'; end if;
  if v_bundle.owner_id=auth.uid() then raise exception 'A moderator cannot approve their own bundle'; end if;
  if p_reason is null or length(btrim(p_reason))<5 then raise exception 'A moderation reason is required'; end if;
  if p_action not in ('approve','reject','suspend','remove') then raise exception 'Unsupported moderation action'; end if;
  if p_action='approve' then
    if (select count(*) from public.book_bundle_items bi join public.book_copies bc on bc.id=bi.book_copy_id
        where bi.bundle_id=p_bundle_id and bc.owner_id=v_bundle.owner_id and bc.city_id=v_bundle.city_id
          and bc.listing_status='approved' and bc.is_available_for_rent) not between 2 and 5 then
      raise exception 'Bundle must contain two to five approved, available copies in one city';
    end if;
    update public.book_bundles set status='approved',updated_at=now() where id=p_bundle_id;
  elsif p_action='reject' then update public.book_bundles set status='rejected',updated_at=now() where id=p_bundle_id;
  elsif p_action='suspend' then update public.book_bundles set status='paused',updated_at=now() where id=p_bundle_id;
  else update public.book_bundles set status='removed',updated_at=now() where id=p_bundle_id;
  end if;
end;
$$;
revoke all on function public.review_book_bundle(uuid,text,text) from public,anon,authenticated;
grant execute on function public.review_book_bundle(uuid,text,text) to authenticated;

-- Tighten approval after an owner's verification or account status has changed.
create or replace function public.review_book_listing(p_book_copy_id uuid,p_action text,p_reason text,p_internal_notes text default null)
returns void
language plpgsql
security definer
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
  if p_action='approve' and not exists (
    select 1 from public.user_verifications v join public.profiles p on p.id=v.user_id
    where v.user_id=v_copy.owner_id and v.status='verified' and v.age_eligible is true and p.account_status='active'
  ) then raise exception 'Owner must remain active, verified and age eligible before approval'; end if;
  v_status:=v_copy.listing_status;
  if p_action='approve' then
    v_to:='approved';
    update public.book_titles set moderation_status='approved' where id=v_copy.book_title_id;
    update public.book_images set moderation_status='approved' where book_copy_id=p_book_copy_id;
    update public.book_copies set listing_status='approved',is_available_for_rent=true where id=p_book_copy_id;
  elsif p_action='reject' then
    v_to:='rejected';
    update public.book_images set moderation_status='rejected' where book_copy_id=p_book_copy_id;
    update public.book_copies set listing_status='rejected',is_available_for_rent=false where id=p_book_copy_id;
  elsif p_action='suspend' then
    v_to:='paused';
    update public.book_copies set listing_status='paused',is_available_for_rent=false where id=p_book_copy_id;
  else
    v_to:='removed';
    update public.book_copies set listing_status='removed',is_available_for_rent=false where id=p_book_copy_id;
  end if;
  insert into public.book_listing_moderation_events(book_copy_id,actor_user_id,action,from_status,to_status,reason,internal_notes)
  values(p_book_copy_id,v_actor,p_action,v_status,v_to,left(p_reason,1000),left(p_internal_notes,4000));
end;
$$;
revoke all on function public.review_book_listing(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.review_book_listing(uuid,text,text,text) to authenticated;

commit;

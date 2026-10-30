begin;

-- Correct wishlist toggle row-count handling and avoid relying on UUID aggregate support.
create or replace function public.toggle_book_wishlist(p_book_title_id uuid)
returns boolean
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_wishlist uuid; v_deleted bigint;
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
  get diagnostics v_deleted = row_count;
  if v_deleted > 0 then return false; end if;
  insert into public.wishlist_items(wishlist_id,book_title_id) values(v_wishlist,p_book_title_id);
  return true;
end;
$$;
revoke all on function public.toggle_book_wishlist(uuid) from public,anon;
grant execute on function public.toggle_book_wishlist(uuid) to authenticated;

-- Select a bundle's city from its owner-approved copies without requiring min(uuid).
create or replace function public.create_book_bundle(p_name text,p_description text,p_book_copy_ids uuid[])
returns uuid
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_id uuid; v_city uuid; v_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.user_verifications v join public.profiles p on p.id=v.user_id
    where v.user_id=auth.uid() and v.status='verified' and v.age_eligible is true and p.account_status='active') then
    raise exception 'An active verified account is required to create a bundle';
  end if;
  if length(btrim(coalesce(p_name,''))) not between 3 and 80 then raise exception 'Bundle name must be 3 to 80 characters'; end if;
  if coalesce(array_length(p_book_copy_ids,1),0) not between 2 and 5 then raise exception 'A bundle must contain two to five copies'; end if;
  select count(distinct x) into v_count from unnest(p_book_copy_ids) x;
  if v_count<>array_length(p_book_copy_ids,1) then raise exception 'Duplicate copies are not allowed'; end if;
  select city_id into v_city from public.book_copies
    where id=any(p_book_copy_ids) and owner_id=auth.uid() and listing_status='approved' and is_available_for_rent
    limit 1;
  if v_city is null or (select count(*) from public.book_copies
      where id=any(p_book_copy_ids) and owner_id=auth.uid() and listing_status='approved'
        and is_available_for_rent and city_id=v_city)<>array_length(p_book_copy_ids,1) then
    raise exception 'All bundle copies must be approved, available, owned by you and in the same city';
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

-- Preserve each change to the owner declaration as an auditable immutable declaration row.
create or replace function private.append_book_ownership_declaration()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
declare v_owner uuid;
begin
  if old.ownership_declaration_type is distinct from new.ownership_declaration_type then
    select owner_id into v_owner from public.book_copies where id=new.book_copy_id;
    insert into public.book_ownership_declarations(
      book_copy_id,owner_id,declaration_type,declaration_version,declaration_text
    ) values (
      new.book_copy_id,v_owner,new.ownership_declaration_type,'2026-10-v1',
      'I declare that I lawfully own this physical book or have authority to rent it to others. I will disclose existing damage and will not list a copy I do not have the right to lend.'
    );
  end if;
  return new;
end;
$$;
drop trigger if exists book_ownership_declaration_history on public.book_copy_listing_details;
create trigger book_ownership_declaration_history
after update of ownership_declaration_type on public.book_copy_listing_details
for each row execute function private.append_book_ownership_declaration();

-- A member may pause only an approved copy they own. Resubmission after editing
-- returns it to moderation; it does not silently reactivate a suspended listing.
alter table public.book_listing_moderation_events
  drop constraint if exists book_listing_moderation_events_action_check;
alter table public.book_listing_moderation_events
  add constraint book_listing_moderation_events_action_check
  check (action in ('draft_saved','submitted','approved','rejected','suspended','resumed','removed','edited','owner_paused'));

create or replace function public.pause_my_book_listing(p_book_copy_id uuid)
returns void
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_status public.listing_status;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select listing_status into v_status from public.book_copies
    where id=p_book_copy_id and owner_id=auth.uid() for update;
  if not found then raise exception 'Listing not found'; end if;
  if v_status<>'approved' then raise exception 'Only an approved listing can be paused by its owner'; end if;
  update public.book_copies set listing_status='paused',is_available_for_rent=false where id=p_book_copy_id;
  insert into public.book_listing_moderation_events(book_copy_id,actor_user_id,action,from_status,to_status,reason)
    values(p_book_copy_id,auth.uid(),'owner_paused','approved','paused','Owner temporarily paused this listing');
end;
$$;
revoke all on function public.pause_my_book_listing(uuid) from public,anon;
grant execute on function public.pause_my_book_listing(uuid) to authenticated;

create or replace function public.get_my_book_availability_blocks(p_book_copy_id uuid)
returns table(block_id uuid,starts_at timestamptz,ends_at timestamptz,reason text)
language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.book_copies where id=p_book_copy_id and owner_id=auth.uid()) then
    raise exception 'Listing not found';
  end if;
  return query
    select b.id,lower(b.blocked_period),upper(b.blocked_period),b.reason::text
    from public.book_availability_blocks b
    where b.book_copy_id=p_book_copy_id and upper(b.blocked_period)>now()
    order by lower(b.blocked_period);
end;
$$;
revoke all on function public.get_my_book_availability_blocks(uuid) from public,anon;
grant execute on function public.get_my_book_availability_blocks(uuid) to authenticated;

commit;

begin;

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
  if p_action='approve' and not exists (
    select 1 from public.user_verifications v join public.profiles p on p.id=v.user_id
    where v.user_id=v_copy.owner_id and v.status='verified' and v.age_eligible is true and p.account_status='active'
  ) then raise exception 'Owner must remain active, verified and age eligible before approval'; end if;
  v_status:=v_copy.listing_status;
  if p_action='approve' then
    if (select count(*) from public.book_images i where i.book_copy_id=p_book_copy_id and i.moderation_status in ('pending_review','approved')) < 2 then
      raise exception 'At least two reviewable physical copy photographs are required';
    end if;
    v_to:='approved';
    update public.book_titles set moderation_status='approved' where id=v_copy.book_title_id;
    update public.book_images set moderation_status='approved'
      where book_copy_id=p_book_copy_id and moderation_status='pending_review';
    update public.book_copies set listing_status='approved',is_available_for_rent=true where id=p_book_copy_id;
  elsif p_action='reject' then
    v_to:='rejected';
    update public.book_images set moderation_status='rejected'
      where book_copy_id=p_book_copy_id and moderation_status='pending_review';
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

create or replace function public.get_public_book_bundles(p_city text default null)
returns jsonb
language sql stable security definer
set search_path = pg_catalog, public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',b.id,'name',b.name,'description',b.description,'city',c.name,
    'items',(select coalesce(jsonb_agg(jsonb_build_object(
      'copy_id',bc.id,'title',bt.title,'author',array_to_string(bt.authors,', '),'locality',l.name
    ) order by bi.display_order),'[]'::jsonb)
      from public.book_bundle_items bi
      join public.book_copies bc on bc.id=bi.book_copy_id
      join public.book_titles bt on bt.id=bc.book_title_id
      join public.localities l on l.id=bc.locality_id
      where bi.bundle_id=b.id)
  ) order by b.created_at desc),'[]'::jsonb)
  from public.book_bundles b
  join public.cities c on c.id=b.city_id
  where b.status='approved'
    and (p_city is null or lower(c.name)=lower(p_city))
    and c.is_active and c.status='active'
    and (select count(*) from public.book_bundle_items bi where bi.bundle_id=b.id) between 2 and 5
    and not exists (
      select 1
      from public.book_bundle_items bi
      join public.book_copies bc on bc.id=bi.book_copy_id
      join public.book_titles bt on bt.id=bc.book_title_id
      where bi.bundle_id=b.id
        and (bc.listing_status<>'approved' or not bc.is_available_for_rent or bt.moderation_status<>'approved')
    );
$$;
revoke all on function public.get_public_book_bundles(text) from public,anon,authenticated;
grant execute on function public.get_public_book_bundles(text) to service_role;

commit;

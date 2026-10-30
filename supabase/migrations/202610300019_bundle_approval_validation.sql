begin;

create or replace function public.review_book_bundle(p_bundle_id uuid,p_action text,p_reason text)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_bundle public.book_bundles%rowtype; v_to text; v_event_action text; v_total integer; v_valid integer;
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
    if not exists(
      select 1 from public.user_verifications v join public.profiles p on p.id=v.user_id
      where v.user_id=v_bundle.owner_id and v.status='verified' and v.age_eligible is true and p.account_status='active'
    ) then raise exception 'Bundle owner must remain active, verified and age eligible'; end if;
    select count(*) into v_total from public.book_bundle_items where bundle_id=p_bundle_id;
    select count(*) into v_valid
    from public.book_bundle_items bi
    join public.book_copies bc on bc.id=bi.book_copy_id
    join public.book_titles bt on bt.id=bc.book_title_id
    where bi.bundle_id=p_bundle_id
      and bc.owner_id=v_bundle.owner_id
      and bc.city_id=v_bundle.city_id
      and bc.listing_status='approved'
      and bc.is_available_for_rent
      and bt.moderation_status='approved';
    if v_total not between 2 and 5 or v_valid<>v_total then
      raise exception 'Every bundle item must be an approved, available copy owned by the active bundle owner in the bundle city';
    end if;
    update public.book_bundles set status='approved',updated_at=now() where id=p_bundle_id;
    v_to:='approved'; v_event_action:='approved';
  elsif p_action='reject' then
    update public.book_bundles set status='rejected',updated_at=now() where id=p_bundle_id;
    v_to:='rejected'; v_event_action:='rejected';
  elsif p_action='suspend' then
    update public.book_bundles set status='paused',updated_at=now() where id=p_bundle_id;
    v_to:='paused'; v_event_action:='suspended';
  else
    update public.book_bundles set status='removed',updated_at=now() where id=p_bundle_id;
    v_to:='removed'; v_event_action:='removed';
  end if;
  insert into public.book_bundle_moderation_events(bundle_id,actor_user_id,action,from_status,to_status,reason)
    values(p_bundle_id,auth.uid(),v_event_action,v_bundle.status,v_to,left(p_reason,1000));
end;
$$;
revoke all on function public.review_book_bundle(uuid,text,text) from public,anon,authenticated;
grant execute on function public.review_book_bundle(uuid,text,text) to authenticated;

commit;

begin;

create table public.book_bundle_moderation_events (
  id bigint generated always as identity primary key,
  bundle_id uuid not null references public.book_bundles(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete restrict,
  action text not null check(action in ('submitted','approved','rejected','suspended','removed')),
  from_status text,
  to_status text not null,
  reason text,
  created_at timestamptz not null default now()
);
create index book_bundle_moderation_events_bundle_idx on public.book_bundle_moderation_events(bundle_id,created_at desc);
alter table public.book_bundle_moderation_events enable row level security;
revoke all on public.book_bundle_moderation_events from anon,authenticated;

create table public.book_waitlist_notifications (
  id uuid primary key default gen_random_uuid(),
  waitlist_entry_id uuid not null references public.book_waitlist_entries(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  book_title_id uuid not null references public.book_titles(id) on delete restrict,
  book_copy_id uuid not null references public.book_copies(id) on delete restrict,
  message text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  unique(waitlist_entry_id,book_copy_id)
);
create index book_waitlist_notifications_user_idx on public.book_waitlist_notifications(user_id,is_read,created_at desc);
alter table public.book_waitlist_notifications enable row level security;
revoke all on public.book_waitlist_notifications from anon,authenticated;

create or replace function private.queue_waitlist_notifications_for_copy(p_book_copy_id uuid)
returns void
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_copy public.book_copies%rowtype;
begin
  select * into v_copy from public.book_copies where id=p_book_copy_id;
  if not found or v_copy.listing_status<>'approved' or not v_copy.is_available_for_rent then return; end if;
  with inserted_notes as (
    insert into public.book_waitlist_notifications(
      waitlist_entry_id,user_id,book_title_id,book_copy_id,message
    )
    select w.id,w.user_id,w.book_title_id,v_copy.id,
      'A physical copy of "'||t.title||'" is available in '||ci.name||'.'
    from public.book_waitlist_entries w
    join public.book_titles t on t.id=w.book_title_id
    join public.cities ci on ci.id=v_copy.city_id
    where w.book_title_id=v_copy.book_title_id
      and w.city_id=v_copy.city_id
      and w.user_id<>v_copy.owner_id
      and w.status='waiting'
      and (w.preferred_locality_id is null or w.preferred_locality_id=v_copy.locality_id)
      and (
        w.requested_start_at is null
        or (
          not exists(select 1 from public.book_availability_blocks b
            where b.book_copy_id=v_copy.id and b.blocked_period && tstzrange(w.requested_start_at,w.requested_end_at,'[)'))
          and not exists(select 1 from public.copy_reservations r
            where r.book_copy_id=v_copy.id and r.status in ('hold','confirmed','in_use')
              and (r.status<>'hold' or r.expires_at is null or r.expires_at>now())
              and r.reserved_period && tstzrange(w.requested_start_at,w.requested_end_at,'[)'))
        )
      )
    on conflict(waitlist_entry_id,book_copy_id) do nothing
    returning waitlist_entry_id
  )
  update public.book_waitlist_entries w
    set status='notified',updated_at=now()
    where w.id in (select waitlist_entry_id from inserted_notes);
end;
$$;
revoke all on function private.queue_waitlist_notifications_for_copy(uuid) from public,anon,authenticated;

create or replace function private.notify_waitlist_after_copy_availability()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
begin
  if new.listing_status='approved' and new.is_available_for_rent
    and (tg_op='INSERT' or old.listing_status is distinct from new.listing_status
      or old.is_available_for_rent is distinct from new.is_available_for_rent) then
    perform private.queue_waitlist_notifications_for_copy(new.id);
  end if;
  return new;
end;
$$;
drop trigger if exists book_copy_waitlist_availability on public.book_copies;
create trigger book_copy_waitlist_availability
after insert or update of listing_status,is_available_for_rent on public.book_copies
for each row execute function private.notify_waitlist_after_copy_availability();

create or replace function private.notify_waitlist_after_entry()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_copy_id uuid;
begin
  if new.status='waiting' then
    for v_copy_id in
      select c.id from public.book_copies c
      where c.book_title_id=new.book_title_id and c.city_id=new.city_id
        and (new.preferred_locality_id is null or c.locality_id=new.preferred_locality_id)
        and c.listing_status='approved' and c.is_available_for_rent
    loop
      perform private.queue_waitlist_notifications_for_copy(v_copy_id);
    end loop;
  end if;
  return new;
end;
$$;
drop trigger if exists waitlist_entry_availability_check on public.book_waitlist_entries;
create trigger waitlist_entry_availability_check
after insert or update of status on public.book_waitlist_entries
for each row execute function private.notify_waitlist_after_entry();

create or replace function private.notify_waitlist_after_block_removed()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_available boolean;
begin
  select (listing_status='approved' and is_available_for_rent) into v_available
  from public.book_copies where id=old.book_copy_id;
  if coalesce(v_available,false) then perform private.queue_waitlist_notifications_for_copy(old.book_copy_id); end if;
  return old;
end;
$$;
drop trigger if exists availability_block_removed_notify_waitlist on public.book_availability_blocks;
create trigger availability_block_removed_notify_waitlist
after delete on public.book_availability_blocks
for each row execute function private.notify_waitlist_after_block_removed();

create or replace function public.get_my_book_waitlist_notifications()
returns jsonb
language sql stable security definer
set search_path = pg_catalog, public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',n.id,'waitlist_entry_id',n.waitlist_entry_id,'copy_id',c.id,
    'title',t.title,'city',ci.name,'locality',l.name,'message',n.message,
    'is_read',n.is_read,'created_at',n.created_at
  ) order by n.created_at desc),'[]'::jsonb)
  from public.book_waitlist_notifications n
  join public.book_copies c on c.id=n.book_copy_id
  join public.book_titles t on t.id=n.book_title_id
  join public.cities ci on ci.id=c.city_id
  join public.localities l on l.id=c.locality_id
  where n.user_id=auth.uid();
$$;
revoke all on function public.get_my_book_waitlist_notifications() from public,anon;
grant execute on function public.get_my_book_waitlist_notifications() to authenticated;

create or replace function public.mark_book_waitlist_notification_read(p_notification_id uuid)
returns void
language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  update public.book_waitlist_notifications set is_read=true
  where id=p_notification_id and user_id=auth.uid();
  if not found then raise exception 'Waitlist notification not found'; end if;
end;
$$;
revoke all on function public.mark_book_waitlist_notification_read(uuid) from public,anon;
grant execute on function public.mark_book_waitlist_notification_read(uuid) to authenticated;

create or replace function public.get_my_book_bundles()
returns jsonb
language sql stable security definer
set search_path = pg_catalog, public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',b.id,'name',b.name,'description',b.description,'status',b.status,'city',c.name,
    'created_at',b.created_at,
    'items',(select coalesce(jsonb_agg(jsonb_build_object(
      'copy_id',bc.id,'title',t.title,'authors',t.authors
    ) order by bi.display_order),'[]'::jsonb)
    from public.book_bundle_items bi join public.book_copies bc on bc.id=bi.book_copy_id
    join public.book_titles t on t.id=bc.book_title_id where bi.bundle_id=b.id)
  ) order by b.created_at desc),'[]'::jsonb)
  from public.book_bundles b join public.cities c on c.id=b.city_id
  where b.owner_id=auth.uid();
$$;
revoke all on function public.get_my_book_bundles() from public,anon;
grant execute on function public.get_my_book_bundles() to authenticated;

create or replace function private.log_book_bundle_submission()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public
as $
begin
  if new.status='pending_review' then
    insert into public.book_bundle_moderation_events(bundle_id,actor_user_id,action,from_status,to_status,reason)
    values(new.id,new.owner_id,'submitted',null,new.status,'Owner submitted bundle for manual moderation');
  end if;
  return new;
end;
$;
create trigger book_bundle_submission_event
after insert on public.book_bundles
for each row execute function private.log_book_bundle_submission();

create or replace function public.review_book_bundle(p_bundle_id uuid,p_action text,p_reason text)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_bundle public.book_bundles%rowtype; v_to text; v_event_action text;
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
    update public.book_bundles set status='approved',updated_at=now() where id=p_bundle_id; v_to:='approved'; v_event_action:='approved';
  elsif p_action='reject' then update public.book_bundles set status='rejected',updated_at=now() where id=p_bundle_id; v_to:='rejected'; v_event_action:='rejected';
  elsif p_action='suspend' then update public.book_bundles set status='paused',updated_at=now() where id=p_bundle_id; v_to:='paused'; v_event_action:='suspended';
  else update public.book_bundles set status='removed',updated_at=now() where id=p_bundle_id; v_to:='removed'; v_event_action:='removed';
  end if;
  insert into public.book_bundle_moderation_events(bundle_id,actor_user_id,action,from_status,to_status,reason)
    values(p_bundle_id,auth.uid(),v_event_action,v_bundle.status,v_to,left(p_reason,1000));
end;
$$;
revoke all on function public.review_book_bundle(uuid,text,text) from public,anon,authenticated;
grant execute on function public.review_book_bundle(uuid,text,text) to authenticated;

create or replace function private.reject_bundle_moderation_mutation()
returns trigger language plpgsql set search_path=pg_catalog
as $$ begin raise exception 'Bundle moderation history is append-only'; end; $$;
create trigger book_bundle_moderation_events_append_only
before update or delete on public.book_bundle_moderation_events
for each row execute function private.reject_bundle_moderation_mutation();

commit;

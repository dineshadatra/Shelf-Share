begin;

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
        (
          w.requested_start_at is null
          and not exists(select 1 from public.book_availability_blocks b
            where b.book_copy_id=v_copy.id and b.blocked_period @> now())
          and not exists(select 1 from public.copy_reservations r
            where r.book_copy_id=v_copy.id and r.status in ('hold','confirmed','in_use')
              and (r.status<>'hold' or r.expires_at is null or r.expires_at>now())
              and r.reserved_period @> now())
        )
        or
        (
          w.requested_start_at is not null
          and not exists(select 1 from public.book_availability_blocks b
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

commit;

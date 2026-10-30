begin;

-- A newly released, cancelled or expired reservation can make a copy match an
-- existing waitlist. The availability matcher re-checks owner blocks and all
-- other active reservations before emitting an in-app notice.
create or replace function private.notify_waitlist_after_reservation_release()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if old.status in ('hold','confirmed','in_use')
    and new.status in ('released','expired','cancelled') then
    perform private.queue_waitlist_notifications_for_copy(new.book_copy_id);
  end if;
  return new;
end;
$$;
drop trigger if exists reservation_release_notify_waitlist on public.copy_reservations;
create trigger reservation_release_notify_waitlist
after update of status on public.copy_reservations
for each row execute function private.notify_waitlist_after_reservation_release();

-- Avoid referring to OLD in the INSERT branch of the availability trigger.
create or replace function private.notify_waitlist_after_copy_availability()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
begin
  if tg_op='INSERT' then
    if new.listing_status='approved' and new.is_available_for_rent then
      perform private.queue_waitlist_notifications_for_copy(new.id);
    end if;
  elsif new.listing_status='approved' and new.is_available_for_rent
    and (old.listing_status is distinct from new.listing_status
      or old.is_available_for_rent is distinct from new.is_available_for_rent) then
    perform private.queue_waitlist_notifications_for_copy(new.id);
  end if;
  return new;
end;
$$;

commit;

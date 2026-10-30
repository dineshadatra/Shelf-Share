begin;

alter table public.outbox_events
  add column if not exists dead_letter_at timestamptz;
create index if not exists outbox_events_dead_letter_pending_idx
  on public.outbox_events(dead_letter_at,available_at)
  where published_at is null and dead_letter_at is null;

create or replace function public.claim_marketplace_outbox_events(
  p_limit integer default 20,p_lease_seconds integer default 60
) returns table(
  event_id uuid,aggregate_type text,aggregate_id uuid,event_type text,payload jsonb,
  idempotency_key text,attempts integer
)
language plpgsql security definer
set search_path=pg_catalog,public
as $$
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_limit<1 or p_limit>100 or p_lease_seconds<15 or p_lease_seconds>900 then
    raise exception 'Invalid outbox batch size or lease'; end if;
  return query
  with candidates as (
    select o.id from public.outbox_events o
      where o.published_at is null and o.dead_letter_at is null and o.attempts<20 and o.available_at<=now()
      order by o.available_at,o.created_at
      for update skip locked limit p_limit
  ), claimed as (
    update public.outbox_events o
      set available_at=now()+make_interval(secs=>p_lease_seconds),
          attempts=o.attempts+1
      from candidates c where o.id=c.id
      returning o.id,o.aggregate_type,o.aggregate_id,o.event_type,o.payload,o.idempotency_key,o.attempts
  )
  select claimed.id,claimed.aggregate_type,claimed.aggregate_id,claimed.event_type,
    claimed.payload,claimed.idempotency_key,claimed.attempts from claimed;
end;
$$;
revoke all on function public.claim_marketplace_outbox_events(integer,integer) from public,anon,authenticated;
grant execute on function public.claim_marketplace_outbox_events(integer,integer) to service_role;

create or replace function public.finish_marketplace_outbox_event(
  p_event_id uuid,p_succeeded boolean,p_error_code text default null
) returns void language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_event public.outbox_events%rowtype; v_delay integer;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  select * into v_event from public.outbox_events where id=p_event_id for update;
  if not found or v_event.published_at is not null then return; end if;
  if p_succeeded then
    update public.outbox_events set published_at=now(),last_error_code=null where id=p_event_id;
  else
    if v_event.attempts>=20 then
      update public.outbox_events set dead_letter_at=now(),
        last_error_code=left(coalesce(p_error_code,'provider_operation_failed'),120)
        where id=p_event_id;
    else
      v_delay:=least(3600,greatest(15,(power(2,least(v_event.attempts,11))::integer)*5));
      update public.outbox_events set available_at=now()+make_interval(secs=>v_delay),
        last_error_code=left(coalesce(p_error_code,'provider_operation_failed'),120)
        where id=p_event_id;
    end if;
  end if;
end;
$$;
revoke all on function public.finish_marketplace_outbox_event(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.finish_marketplace_outbox_event(uuid,boolean,text) to service_role;

create or replace function public.request_book_return(p_booking_id uuid)
returns void language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_actor uuid:=auth.uid(); v_booking public.bookings%rowtype;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.reader_id<>v_actor then
    raise exception 'Only the Reader may initiate the return request'; end if;
  if v_booking.status='return_pending' then return; end if;
  if v_booking.status<>'active' then raise exception 'Only an active rental can enter return workflow'; end if;
  update public.bookings set status='return_pending' where id=p_booking_id;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,from_status,to_status,metadata,idempotency_key)
    values(p_booking_id,v_actor,'return_requested','active','return_pending','{}'::jsonb,'return-request:'||p_booking_id::text)
    on conflict(idempotency_key) do nothing;
  insert into public.notifications(user_id,channel,template_key,payload)
    values(v_booking.owner_id,'in_app','booking.return_requested',jsonb_build_object('booking_id',p_booking_id));
end;
$$;
revoke all on function public.request_book_return(uuid) from public,anon;
grant execute on function public.request_book_return(uuid) to authenticated;

commit;

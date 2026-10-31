begin;

-- These are append-only event/ledger tables. Correct errors with compensating
-- entries; never rewrite historical deposit, commission or handover evidence.
create or replace function private.reject_append_only_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception 'Append-only record cannot be updated or deleted';
end;
$$;

 drop trigger if exists deposit_ledger_append_only on public.deposit_ledger;
create trigger deposit_ledger_append_only
before update or delete on public.deposit_ledger
for each row execute function private.reject_append_only_mutation();

 drop trigger if exists commission_ledger_append_only on public.commission_ledger;
create trigger commission_ledger_append_only
before update or delete on public.commission_ledger
for each row execute function private.reject_append_only_mutation();

 drop trigger if exists handover_events_append_only on public.handover_events;
create trigger handover_events_append_only
before update or delete on public.handover_events
for each row execute function private.reject_append_only_mutation();

-- The booking row is locked by create_handover_session_secure, and this index
-- supplies an independent database-level guarantee against two live sessions
-- for the same booking/action.
do $$
begin
  if exists (
    select 1 from public.handover_sessions
    where status in ('created','awaiting_counterparty')
    group by booking_id, handover_type
    having count(*) > 1
  ) then
    raise exception 'Resolve duplicate active handover sessions before applying runtime guard migration';
  end if;
end;
$$;

create unique index if not exists handover_one_active_session_per_action_uq
on public.handover_sessions(booking_id, handover_type)
where status in ('created','awaiting_counterparty');

commit;

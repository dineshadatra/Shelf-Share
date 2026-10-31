begin;

-- Match the displayed available deposit position to the transactional release
-- guard: a live, short-lived booking-request hold also makes the member active.
create or replace function public.get_my_deposit_positions()
returns table(deposit_id uuid,booking_id uuid,status public.deposit_status,amount_paise bigint,
  locked_paise bigint,available_for_release_paise bigint,currency char(3),provider_reference text)
language sql stable security definer
set search_path=pg_catalog,public
as $$
  select d.id,d.booking_id,d.status,d.amount_paise,
    case when d.provider_reference is not null and d.status in ('held_by_provider','claim_hold_pending','claim_hold','release_pending','refund_pending','partially_applied')
      then greatest(d.amount_paise-coalesce((select sum(l.amount_paise) from public.deposit_ledger l
        where l.deposit_id=d.id and l.event_type in ('released','amount_applied')),0),0)::bigint
      else 0::bigint end,
    case when d.provider_reference is not null and d.status in ('held_by_provider','partially_applied','claim_hold') and b.status='completed'
      and exists(select 1 from public.booking_workflow_configuration c where c.id=true
        and c.deposit_claim_window_seconds is not null
        and b.completed_at+make_interval(secs=>c.deposit_claim_window_seconds)<=now())
      and not exists(select 1 from public.disputes x where x.booking_id=b.id and x.status<>'closed')
      and not exists(select 1 from public.payment_disputes x where x.booking_id=b.id and x.status not in ('won','closed'))
      and not exists(select 1 from public.deposit_claims x where x.deposit_id=d.id and x.status not in ('rejected','closed'))
      and not exists(select 1 from public.bookings active
        where (active.reader_id=d.payer_id or active.owner_id=d.payer_id)
          and (
          active.status::text in ('owner_accepted','payment_pending','confirmed','collection_pending','active','return_pending','disputed')
          or (active.status='requested' and exists(
            select 1 from public.copy_reservations r where r.booking_id=active.id and r.status='hold' and r.expires_at>now()
          ))
        ))
      then greatest(d.amount_paise-coalesce((select sum(l.amount_paise) from public.deposit_ledger l
        where l.deposit_id=d.id and l.event_type in ('released','amount_applied')),0),0)::bigint
      else 0::bigint end,
    d.currency,d.provider_reference
  from public.deposits d join public.bookings b on b.id=d.booking_id
  where d.payer_id=auth.uid()
  order by d.created_at desc;
$$;
revoke all on function public.get_my_deposit_positions() from public,anon;
grant execute on function public.get_my_deposit_positions() to authenticated;

commit;

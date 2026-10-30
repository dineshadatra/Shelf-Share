begin;

alter table public.disputes
  add column if not exists booking_status_before_dispute public.booking_status;

create or replace function public.open_booking_dispute(
  p_booking_id uuid,p_reason_code text,p_description text
) returns uuid
language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare
  v_actor uuid:=auth.uid(); v_booking public.bookings%rowtype; v_id uuid;
  v_against uuid; v_policy text; v_deposit public.deposits%rowtype;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if length(btrim(coalesce(p_reason_code,'')))<3 or length(btrim(coalesce(p_reason_code,'')))>80
    or length(btrim(coalesce(p_description,'')))<20 then
    raise exception 'A dispute reason and a detailed description are required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_actor not in (v_booking.reader_id,v_booking.owner_id) then
    raise exception 'Only a booking participant may open a dispute'; end if;
  if v_booking.status not in ('confirmed','collection_pending','active','return_pending','completed','disputed') then
    raise exception 'This booking state is not eligible for a rental dispute'; end if;
  if exists(select 1 from public.disputes d where d.booking_id=p_booking_id and d.status<>'closed') then
    raise exception 'An open dispute already exists for this booking'; end if;
  v_against:=case when v_actor=v_booking.reader_id then v_booking.owner_id else v_booking.reader_id end;
  v_policy:=coalesce(v_booking.policy_snapshot->>'cancellation_policy_version','unconfigured');
  insert into public.disputes(booking_id,opened_by,against_user_id,reason_code,description,status,policy_version,booking_status_before_dispute)
    values(p_booking_id,v_actor,v_against,left(p_reason_code,80),left(p_description,4000),'open',v_policy,v_booking.status)
    returning id into v_id;
  update public.bookings set status='disputed' where id=p_booking_id;
  update public.owner_earnings set status='reconciliation_required'
    where booking_id=p_booking_id and status in ('pending','eligible','processing');
  insert into public.booking_audit_events(booking_id,actor_id,event_type,from_status,to_status,metadata,idempotency_key)
    values(p_booking_id,v_actor,'rental_dispute_opened',v_booking.status,'disputed',
      jsonb_build_object('dispute_id',v_id,'reason_code',p_reason_code),'rental-dispute:'||v_id::text);
  insert into public.notifications(user_id,channel,template_key,payload)
    values(v_against,'in_app','booking.dispute_opened',jsonb_build_object('booking_id',p_booking_id,'dispute_id',v_id));
  select * into v_deposit from public.deposits where booking_id=p_booking_id for update;
  if found and v_deposit.feature_enabled_at_creation and v_deposit.status='held_by_provider' then
    insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
      values('deposit',v_deposit.id,'deposit_dispute_hold_requested',
        jsonb_build_object('deposit_id',v_deposit.id,'booking_id',p_booking_id,'dispute_id',v_id,
          'amount_paise',v_deposit.amount_paise,'provider',v_deposit.provider),
        'deposit-dispute-hold:'||v_id::text) on conflict(idempotency_key) do nothing;
    update public.deposits set status='claim_hold_pending' where id=v_deposit.id;
    insert into public.deposit_ledger(deposit_id,event_type,amount_paise,idempotency_key,metadata)
      values(v_deposit.id,'claim_hold_requested',v_deposit.amount_paise,'deposit-dispute-hold-ledger:'||v_id::text,
        jsonb_build_object('dispute_id',v_id));
  end if;
  return v_id;
end;
$$;
revoke all on function public.open_booking_dispute(uuid,text,text) from public,anon;
grant execute on function public.open_booking_dispute(uuid,text,text) to authenticated;

create or replace function public.resolve_booking_dispute(
  p_dispute_id uuid,p_decision_code text,p_decision_notes text
) returns void language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare
  v_actor uuid:=auth.uid(); v_dispute public.disputes%rowtype; v_booking public.bookings%rowtype;
  v_next public.booking_status;
begin
  if v_actor is null or not exists(select 1 from public.user_roles r where r.user_id=v_actor
    and r.revoked_at is null and r.role in ('admin','super_admin','finance_operator')) then
    raise exception 'Authorised independent dispute reviewer required';
  end if;
  if length(btrim(coalesce(p_decision_code,'')))<3 or length(btrim(coalesce(p_decision_notes,'')))<20 then
    raise exception 'A decision code and reasoned decision notes are required';
  end if;
  select * into v_dispute from public.disputes where id=p_dispute_id for update;
  if not found or v_dispute.status not in ('open','awaiting_reader','awaiting_owner','under_review','decided','appealed') then
    raise exception 'Dispute is not available for resolution';
  end if;
  select * into v_booking from public.bookings where id=v_dispute.booking_id for update;
  if v_actor in (v_booking.reader_id,v_booking.owner_id) then
    raise exception 'A booking participant cannot review or resolve their own dispute';
  end if;
  if v_dispute.booking_status_before_dispute is null then
    raise exception 'Original booking state is missing; manual reconciliation is required';
  end if;
  update public.disputes set status='closed',decision_code=left(p_decision_code,80),
    decision_notes=left(p_decision_notes,4000),assigned_to=coalesce(assigned_to,v_actor),
    decided_at=now(),closed_at=now()
    where id=p_dispute_id;
  if not exists(select 1 from public.disputes d where d.booking_id=v_booking.id and d.id<>p_dispute_id and d.status<>'closed')
    and not exists(select 1 from public.payment_disputes pd where pd.booking_id=v_booking.id and pd.status not in ('won','closed')) then
    v_next:=v_dispute.booking_status_before_dispute;
    update public.bookings set status=v_next where id=v_booking.id and status='disputed';
  end if;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,from_status,to_status,reason_code,metadata,idempotency_key)
    values(v_booking.id,v_actor,'rental_dispute_resolved','disputed',
      case when not exists(select 1 from public.disputes d where d.booking_id=v_booking.id and d.id<>p_dispute_id and d.status<>'closed')
        and not exists(select 1 from public.payment_disputes pd where pd.booking_id=v_booking.id and pd.status not in ('won','closed'))
        then v_dispute.booking_status_before_dispute else 'disputed'::public.booking_status end,
      left(p_decision_code,80),jsonb_build_object('dispute_id',p_dispute_id,'decision_notes',left(p_decision_notes,4000)),
      'rental-dispute-resolved:'||p_dispute_id::text)
    on conflict(idempotency_key) do nothing;
  insert into public.notifications(user_id,channel,template_key,payload)
    values(v_booking.reader_id,'in_app','booking.dispute_resolved',
      jsonb_build_object('booking_id',v_booking.id,'dispute_id',p_dispute_id,'decision_code',p_decision_code)),
      (v_booking.owner_id,'in_app','booking.dispute_resolved',
      jsonb_build_object('booking_id',v_booking.id,'dispute_id',p_dispute_id,'decision_code',p_decision_code));
end;
$$;
revoke all on function public.resolve_booking_dispute(uuid,text,text) from public,anon;
grant execute on function public.resolve_booking_dispute(uuid,text,text) to authenticated;

create or replace function public.get_my_deposit_positions()
returns table(deposit_id uuid,booking_id uuid,status public.deposit_status,amount_paise bigint,
  locked_paise bigint,available_for_release_paise bigint,currency char(3),provider_reference text)
language sql stable security definer
set search_path=pg_catalog,public
as $$
  select d.id,d.booking_id,d.status,d.amount_paise,
    case when d.status in ('held_by_provider','claim_hold_pending','claim_hold','release_pending','refund_pending','partially_applied')
      then greatest(d.amount_paise-coalesce((select sum(l.amount_paise) from public.deposit_ledger l
        where l.deposit_id=d.id and l.event_type in ('released','amount_applied')),0),0)::bigint
      else 0::bigint end,
    case when d.status in ('held_by_provider','partially_applied','claim_hold') and b.status='completed'
      and exists(select 1 from public.booking_workflow_configuration c where c.id=true
        and c.deposit_claim_window_seconds is not null
        and b.completed_at+make_interval(secs=>c.deposit_claim_window_seconds)<=now())
      and not exists(select 1 from public.disputes x where x.booking_id=b.id and x.status<>'closed')
      and not exists(select 1 from public.deposit_claims x where x.deposit_id=d.id and x.status not in ('rejected','closed'))
      and not exists(select 1 from public.bookings active
        where (active.reader_id=d.payer_id or active.owner_id=d.payer_id)
          and active.status::text in ('owner_accepted','payment_pending','confirmed','collection_pending','active','return_pending','disputed'))
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

create or replace function public.request_deposit_release(p_deposit_id uuid,p_idempotency_key text)
returns uuid language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_user uuid:=auth.uid(); v_deposit public.deposits%rowtype; v_booking public.bookings%rowtype;
  v_request uuid; v_provider public.payment_provider_approvals%rowtype; v_released bigint; v_remaining bigint; v_window integer;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 or length(p_idempotency_key)>128 then raise exception 'Valid idempotency key required'; end if;
  select * into v_deposit from public.deposits where id=p_deposit_id for update;
  if not found or v_deposit.payer_id<>v_user or not v_deposit.feature_enabled_at_creation then raise exception 'Provider-held deposit not found'; end if;
  select id into v_request from public.deposit_release_requests where idempotency_key=p_idempotency_key;
  if v_request is not null then return v_request; end if;
  if v_deposit.status not in ('held_by_provider','partially_applied','claim_hold') then raise exception 'Deposit is not releasable'; end if;
  select * into v_booking from public.bookings where id=v_deposit.booking_id for update;
  select deposit_claim_window_seconds into v_window from public.booking_workflow_configuration where id=true and is_active;
  if v_booking.status<>'completed' or v_booking.completed_at is null or v_window is null
    or v_booking.completed_at+make_interval(secs=>v_window)>now() then raise exception 'Return closure or approved claim window is incomplete'; end if;
  if exists(select 1 from public.disputes x where x.booking_id=v_booking.id and x.status<>'closed')
    or exists(select 1 from public.deposit_claims x where x.deposit_id=v_deposit.id and x.status not in ('rejected','closed')) then raise exception 'Open dispute or claim blocks release'; end if;
  if exists(select 1 from public.bookings x where (x.reader_id=v_user or x.owner_id=v_user)
    and x.status::text in ('owner_accepted','payment_pending','confirmed','collection_pending','active','return_pending','disputed')) then
    raise exception 'Deposit release is blocked while this member has an active rental'; end if;
  select p.* into v_provider from public.payment_provider_approvals p
    where p.provider_code=v_deposit.provider and p.enabled_for_deposits and p.supports_deposit_release
      and p.legal_approval_reference is not null and p.accounting_approval_reference is not null
      and (p.expires_at is null or p.expires_at>now());
  if not found then raise exception 'Approved provider deposit release is unavailable'; end if;
  select coalesce(sum(l.amount_paise),0) into v_released from public.deposit_ledger l
    where l.deposit_id=v_deposit.id and l.event_type in ('released','amount_applied');
  v_remaining:=greatest(v_deposit.amount_paise-v_released,0);
  if v_remaining<=0 then raise exception 'No provider-confirmed deposit funds remain'; end if;
  insert into public.deposit_release_requests(deposit_id,requested_by,amount_paise,idempotency_key)
    values(v_deposit.id,v_user,v_remaining,p_idempotency_key) returning id into v_request;
  update public.deposits set status='release_pending' where id=v_deposit.id;
  insert into public.deposit_ledger(deposit_id,event_type,amount_paise,idempotency_key,metadata)
    values(v_deposit.id,'release_requested',v_remaining,'deposit-release:'||p_idempotency_key,jsonb_build_object('request_id',v_request));
  insert into public.outbox_events(aggregate_type,aggregate_id,event_type,payload,idempotency_key)
    values('deposit',v_deposit.id,'deposit_release_requested',jsonb_build_object('request_id',v_request,'amount_paise',v_remaining),
      'deposit-release-outbox:'||p_idempotency_key) on conflict(idempotency_key) do nothing;
  return v_request;
end;
$$;
revoke all on function public.request_deposit_release(uuid,text) from public,anon;
grant execute on function public.request_deposit_release(uuid,text) to authenticated;

commit;

begin;

-- Collection is a service notification tied to the booking's scheduled collection state.
create or replace function private.notify_collection_stage()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
begin
  if new.status::text='collection_pending' and old.status::text is distinct from new.status::text then
    perform private.enqueue_notification_event(new.reader_id,'collection.reminder',new.id,
      jsonb_build_object('booking_number',new.booking_number,'status','collection_pending'),
      'collection-reminder:'||new.id::text||':'||new.reader_id::text);
    perform private.enqueue_notification_event(new.owner_id,'collection.reminder',new.id,
      jsonb_build_object('booking_number',new.booking_number,'status','collection_pending'),
      'collection-reminder:'||new.id::text||':'||new.owner_id::text);
  end if;
  return new;
end;
$$;
create trigger booking_collection_notification
after update of status on public.bookings
for each row execute function private.notify_collection_stage();

-- Notify the account holder as well as the verification team when a request arrives.
create or replace function private.notify_verification_submitter()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
begin
  if new.status in ('pending','under_review') then
    perform private.enqueue_notification_event(new.user_id,'verification.submitted',new.user_id,
      jsonb_build_object('verification_status',new.status),
      'verification-submitted-user:'||new.user_id::text);
  end if;
  return new;
end;
$$;
create trigger verification_submitter_notification
after insert on public.user_verifications
for each row execute function private.notify_verification_submitter();

-- Cancelling SMS preferences also cancels already-claimed jobs that have not been sent.
create or replace function private.cancel_unconsented_notification_jobs()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public
as $$
begin
  update public.notification_delivery_jobs j
  set status='cancelled',claimed_at=null,updated_at=now()
  from public.notification_templates t
  where j.template_key=t.template_key and j.user_id=new.user_id
    and j.status in ('queued','processing') and j.channel='sms'
    and ((t.category='service' and not new.sms_service_enabled)
      or (t.category='marketing' and not new.sms_marketing_enabled));
  update public.notifications n set status='cancelled'
  from public.notification_events e,public.notification_templates t
  where n.event_id=e.id and e.event_key=t.template_key
    and n.user_id=new.user_id and n.channel='sms' and n.status='queued'
    and ((t.category='service' and not new.sms_service_enabled)
      or (t.category='marketing' and not new.sms_marketing_enabled));
  return new;
end;
$$;
create trigger notification_preference_cancel_jobs
after update of sms_service_enabled,sms_marketing_enabled on public.notification_preferences
for each row execute function private.cancel_unconsented_notification_jobs();

create or replace function public.notification_delivery_job_sendable(p_job_id uuid)
returns boolean language sql security definer
set search_path=pg_catalog,public
as $$
  select coalesce((
    select j.status='processing'
      and t.sms_enabled and t.sms_body_template is not null
      and t.sms_header is not null and t.sms_content_template_id is not null
      and d.is_active and d.principal_entity_id is not null
      and u.phone is not null and u.phone_confirmed_at is not null
      and ((t.category='service' and pref.sms_service_enabled)
        or (t.category='marketing' and pref.sms_marketing_enabled))
    from public.notification_delivery_jobs j
    join public.notification_templates t on t.template_key=j.template_key
    join public.notification_preferences pref on pref.user_id=j.user_id
    join auth.users u on u.id=j.user_id
    join public.notification_dlt_config d on d.id=true
    where j.id=p_job_id and j.channel='sms'
  ),false);
$$;
revoke all on function public.notification_delivery_job_sendable(uuid) from public,anon,authenticated;
grant execute on function public.notification_delivery_job_sendable(uuid) to service_role;

-- Report values are net of explicit reversals: a reversal row points to the
-- original immutable cost entry rather than mutating historical evidence.
create or replace function public.get_admin_financial_analytics(p_from date,p_to date)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog,public
as $$
declare
  v_gross bigint:=0; v_paid_count bigint:=0; v_commission bigint:=0; v_gateway bigint:=0;
  v_refunds bigint:=0; v_tax bigint:=0; v_sms bigint:=0; v_verification bigint:=0;
  v_referral_ops bigint:=0; v_referral_rewards bigint:=0; v_support bigint:=0;
  v_repeat numeric:=0; v_conversion numeric:=0; v_average numeric:=0; v_active_books bigint:=0;
  v_total_requests bigint:=0; v_paid_requests bigint:=0; v_completed_readers bigint:=0;
  v_repeat_readers bigint:=0; v_localities jsonb:='[]'::jsonb; v_daily jsonb:='[]'::jsonb;
  v_net bigint:=0;
begin
  if auth.uid() is null or not public.admin_has_permission('finance.analytics.read')
    or coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception 'Finance analytics permission and MFA AAL2 required'; end if;
  if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then
    raise exception 'Report date range must be between 1 and 367 calendar days';
  end if;

  with paid as (
    select b.id,b.reader_id,b.city_id,b.rent_subtotal_paise,b.tax_paise,
      min(p.captured_at) as captured_at
    from public.bookings b join public.payments p on p.booking_id=b.id
    where p.status::text in ('captured','partially_refunded','refunded')
      and p.captured_at>=p_from::timestamptz and p.captured_at<(p_to+1)::timestamptz
    group by b.id,b.reader_id,b.city_id,b.rent_subtotal_paise,b.tax_paise
  )
  select coalesce(sum(rent_subtotal_paise),0),count(*),coalesce(sum(tax_paise),0)
    into v_gross,v_paid_count,v_tax from paid;

  select coalesce(sum(cl.commission_paise),0) into v_commission
  from public.commission_ledger cl
  where cl.created_at>=p_from::timestamptz and cl.created_at<(p_to+1)::timestamptz;

  select coalesce(sum(case when c.reverses_entry_id is null then c.amount_paise else -c.amount_paise end),0)
    into v_gateway from public.financial_cost_entries c
  where c.cost_category='gateway_charge' and c.occurred_at>=p_from::timestamptz
    and c.occurred_at<(p_to+1)::timestamptz;
  select coalesce(sum(case when c.reverses_entry_id is null then c.amount_paise else -c.amount_paise end),0)
    into v_sms from public.financial_cost_entries c
  where c.cost_category='sms' and c.occurred_at>=p_from::timestamptz and c.occurred_at<(p_to+1)::timestamptz;
  select coalesce(sum(case when c.reverses_entry_id is null then c.amount_paise else -c.amount_paise end),0)
    into v_verification from public.financial_cost_entries c
  where c.cost_category='verification' and c.occurred_at>=p_from::timestamptz and c.occurred_at<(p_to+1)::timestamptz;
  select coalesce(sum(case when c.reverses_entry_id is null then c.amount_paise else -c.amount_paise end),0)
    into v_referral_ops from public.financial_cost_entries c
  where c.cost_category='referral' and c.occurred_at>=p_from::timestamptz and c.occurred_at<(p_to+1)::timestamptz;
  select coalesce(sum(reward_value_paise),0) into v_referral_rewards
  from public.referral_rewards where status='issued'
    and issued_at>=p_from::timestamptz and issued_at<(p_to+1)::timestamptz;
  select coalesce(sum(case when c.reverses_entry_id is null then c.amount_paise else -c.amount_paise end),0)
    into v_support from public.financial_cost_entries c
  where c.cost_category='support' and c.occurred_at>=p_from::timestamptz and c.occurred_at<(p_to+1)::timestamptz;
  select coalesce(sum(amount_paise),0) into v_refunds
  from public.refunds where status='succeeded'
    and completed_at>=p_from::timestamptz and completed_at<(p_to+1)::timestamptz;

  select count(*) into v_total_requests from public.bookings
    where created_at>=p_from::timestamptz and created_at<(p_to+1)::timestamptz;
  select count(distinct b.id) into v_paid_requests
  from public.bookings b join public.payments p on p.booking_id=b.id
  where b.created_at>=p_from::timestamptz and b.created_at<(p_to+1)::timestamptz
    and p.status::text in ('captured','partially_refunded','refunded') and p.captured_at is not null;
  v_conversion:=case when v_total_requests=0 then 0 else round((v_paid_requests::numeric/v_total_requests)*100,2) end;
  v_average:=case when v_paid_count=0 then 0 else round(v_gross::numeric/v_paid_count,2) end;

  with readers as (
    select reader_id,count(*) as rentals from public.bookings
    where status='completed' and completed_at>=p_from::timestamptz
      and completed_at<(p_to+1)::timestamptz group by reader_id
  )
  select count(*) filter(where rentals>=2),count(*) into v_repeat_readers,v_completed_readers from readers;
  v_repeat:=case when v_completed_readers=0 then 0 else round((v_repeat_readers::numeric/v_completed_readers)*100,2) end;

  select count(*) into v_active_books from public.book_copies
  where listing_status='approved' and is_available_for_rent;

  with paid_locality as (
    select b.id,b.rent_subtotal_paise,cp.locality_id,cp.city_id
    from public.bookings b
    join public.rental_items ri on ri.booking_id=b.id
    join public.book_copies cp on cp.id=ri.book_copy_id
    where exists(select 1 from public.payments p where p.booking_id=b.id
      and p.status::text in ('captured','partially_refunded','refunded')
      and p.captured_at>=p_from::timestamptz and p.captured_at<(p_to+1)::timestamptz)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'locality_id',l.id,'locality',l.name,'city',c.name,
    'paid_bookings',x.booking_count,'gross_rental_value_paise',x.gross_paise
  ) order by x.gross_paise desc),'[]'::jsonb)
  into v_localities
  from (
    select locality_id,city_id,count(distinct id) as booking_count,
      sum(booking_value) as gross_paise
    from (select locality_id,city_id,id,max(rent_subtotal_paise) as booking_value
      from paid_locality group by locality_id,city_id,id) q
    group by locality_id,city_id
  ) x
  join public.localities l on l.id=x.locality_id
  join public.cities c on c.id=x.city_id;

  with paid_daily as (
    select b.id,b.rent_subtotal_paise,min(p.captured_at)::date as metric_day
    from public.bookings b join public.payments p on p.booking_id=b.id
    where p.status::text in ('captured','partially_refunded','refunded')
      and p.captured_at>=p_from::timestamptz and p.captured_at<(p_to+1)::timestamptz
    group by b.id,b.rent_subtotal_paise
  )
  select coalesce(jsonb_agg(jsonb_build_object('date',metric_day,'gross_rental_value_paise',gross_paise,
      'paid_bookings',booking_count) order by metric_day),'[]'::jsonb)
  into v_daily from (
    select metric_day,sum(rent_subtotal_paise) as gross_paise,count(*) as booking_count
    from paid_daily group by metric_day
  ) d;

  v_net:=v_commission-v_gateway-v_sms-v_verification-v_referral_ops-v_referral_rewards-v_support;
  return jsonb_build_object(
    'period',jsonb_build_object('from',p_from,'to',p_to,'timezone','UTC'),
    'summary',jsonb_build_object(
      'gross_rental_transaction_value_paise',v_gross,'paid_bookings',v_paid_count,
      'commission_paise',v_commission,'gateway_charges_paise',v_gateway,
      'refunds_completed_paise',v_refunds,'booked_tax_paise',v_tax,
      'sms_cost_paise',v_sms,'verification_cost_paise',v_verification,
      'referral_reward_expenditure_paise',v_referral_rewards,
      'referral_operating_cost_paise',v_referral_ops,'support_cost_paise',v_support,
      'net_contribution_before_other_overheads_paise',v_net,
      'repeat_rental_rate_percent',v_repeat,'booking_conversion_percent',v_conversion,
      'average_rental_value_paise',v_average,'active_books_now',v_active_books,
      'booking_requests',v_total_requests,'paid_booking_requests',v_paid_requests,
      'completed_reader_count',v_completed_readers,'repeat_readers',v_repeat_readers
    ),
    'locality_performance',v_localities,'daily_performance',v_daily
  );
end;
$$;
revoke all on function public.get_admin_financial_analytics(date,date) from public,anon;
grant execute on function public.get_admin_financial_analytics(date,date) to authenticated;

commit;

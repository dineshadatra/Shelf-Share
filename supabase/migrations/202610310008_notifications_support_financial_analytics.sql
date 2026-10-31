begin;

-- Notifications are event-driven. Auth OTP remains in Supabase Auth and is never
-- copied into the application notification payload or delivery queue.
create table public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  in_app_enabled boolean not null default true,
  sms_service_enabled boolean not null default false,
  sms_marketing_enabled boolean not null default false,
  email_enabled boolean not null default false,
  push_enabled boolean not null default false,
  sms_service_consent_at timestamptz,
  sms_marketing_consent_at timestamptz,
  sms_consent_source text,
  sms_consent_version text,
  sms_revoked_at timestamptz,
  updated_at timestamptz not null default now(),
  check (not sms_service_enabled or sms_service_consent_at is not null),
  check (not sms_marketing_enabled or sms_marketing_consent_at is not null)
);

create table public.notification_consent_history (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  channel text not null check (channel in ('sms_service','sms_marketing')),
  enabled boolean not null,
  consent_source text,
  consent_version text,
  recorded_at timestamptz not null default now()
);
create index notification_consent_user_time_idx
  on public.notification_consent_history(user_id, recorded_at desc);

create table public.notification_templates (
  template_key text primary key,
  category text not null check (category in ('service','marketing','auth')),
  in_app_title text not null,
  in_app_body text not null,
  sms_body_template text,
  sms_header text,
  sms_content_template_id text,
  dlt_variable_policy jsonb not null default '[]'::jsonb
    check (jsonb_typeof(dlt_variable_policy) = 'array'),
  sms_enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  check (sms_body_template is null or length(sms_body_template) between 1 and 1600),
  check (sms_header is null or sms_header ~ '^[A-Z0-9]{1,11}$'),
  check (sms_content_template_id is null or sms_content_template_id ~ '^[0-9]{1,30}$')
);
insert into public.notification_templates(template_key,category,in_app_title,in_app_body) values
('auth.otp','auth','Sign-in code','Use the secure sign-in flow to receive your one-time code.'),
('verification.submitted','service','Verification submitted','Your verification request has been submitted for review.'),
('verification.approved','service','Verification approved','Your ShelfShare account verification is complete.'),
('verification.rejected','service','Verification needs attention','Your verification needs an update. Open the app to review the next steps.'),
('listing.approved','service','Book listing approved','Your book listing is approved and can be rented.'),
('listing.rejected','service','Book listing needs changes','Your book listing was not approved. Open the app to review the reason.'),
('booking.requested','service','New booking request','You have received a new book rental request.'),
('booking.accepted','service','Booking accepted','The owner accepted your rental request. Complete the payment step in the app.'),
('booking.rejected','service','Booking not accepted','Your rental request was not accepted.'),
('payment.succeeded','service','Payment confirmed','Your rental payment has been confirmed.'),
('payment.failed','service','Payment not completed','Your payment could not be completed. Review the payment status in the app.'),
('collection.reminder','service','Collection reminder','A scheduled book collection is coming up. Check the booking for details.'),
('handover.confirmed','service','Handover confirmed','The book handover has been confirmed.'),
('rental.due_reminder','service','Return reminder','Your book rental is approaching its return date.'),
('rental.overdue','service','Book return overdue','Your book rental is overdue. Please review the return steps.'),
('extension.requested','service','Extension request','A rental extension request needs your response.'),
('return.confirmed','service','Return confirmed','The book return has been confirmed.'),
('dispute.opened','service','Dispute opened','A dispute has been opened for a rental involving you.'),
('dispute.updated','service','Dispute update','There is an update to your rental dispute.'),
('refund.updated','service','Refund update','There is an update to your refund.'),
('payout.updated','service','Payout update','There is an update to your owner payout.'),
('referral.rewarded','service','Referral reward','A referral reward has been issued to your account.'),
('community.activity','marketing','Community activity','There is new activity on your community post.'),
('grievance.updated','service','Support ticket update','There is an update to your ShelfShare support ticket.')
on conflict(template_key) do nothing;

create table public.notification_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  event_key text not null references public.notification_templates(template_key) on delete restrict,
  reference_id uuid,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  dedupe_key text not null unique,
  created_at timestamptz not null default now(),
  check (length(payload::text) <= 4096)
);
create index notification_events_user_time_idx
  on public.notification_events(user_id, created_at desc);

alter table public.notifications
  add column if not exists event_id uuid references public.notification_events(id) on delete set null;
create index if not exists notifications_event_idx on public.notifications(event_id);

create table public.notification_dlt_config (
  id boolean primary key default true check (id),
  principal_entity_id text not null,
  telemarketer_chain jsonb not null default '[]'::jsonb
    check (jsonb_typeof(telemarketer_chain) = 'array'),
  is_active boolean not null default false,
  updated_at timestamptz not null default now()
);

create table public.notification_delivery_jobs (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notifications(id) on delete restrict,
  event_id uuid not null references public.notification_events(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  template_key text not null references public.notification_templates(template_key) on delete restrict,
  channel text not null check (channel in ('sms','email','push')),
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  status text not null default 'queued'
    check (status in ('queued','processing','sent','dead_letter','cancelled')),
  attempts integer not null default 0 check (attempts between 0 and 10),
  available_at timestamptz not null default now(),
  claimed_at timestamptz,
  provider_reference text,
  last_error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(notification_id, channel)
);
create index notification_jobs_pending_idx
  on public.notification_delivery_jobs(status, available_at, created_at)
  where status in ('queued','processing');

create or replace function private.redact_notification_json(p_value jsonb, p_depth integer default 0)
returns jsonb language plpgsql immutable
set search_path = pg_catalog
as $$
declare v_result jsonb;
begin
  if p_depth > 6 then return '{}'::jsonb; end if;
  if jsonb_typeof(p_value) = 'object' then
    select coalesce(jsonb_object_agg(key, private.redact_notification_json(value, p_depth + 1)), '{}'::jsonb)
      into v_result
    from jsonb_each(p_value)
    where key !~* '(otp|one.?time|password|secret|token|phone|email|address|document|identity|aadhaar|pan|object.?key|storage|signed.?url|authorization)';
    return v_result;
  elsif jsonb_typeof(p_value) = 'array' then
    select coalesce(jsonb_agg(private.redact_notification_json(value, p_depth + 1)), '[]'::jsonb)
      into v_result
    from jsonb_array_elements(p_value);
    return v_result;
  end if;
  if jsonb_typeof(p_value) in ('string','number','boolean','null') then return p_value; end if;
  return 'null'::jsonb;
end;
$$;
revoke all on function private.redact_notification_json(jsonb,integer) from public,anon,authenticated;

create or replace function private.enqueue_notification_event(
  p_user_id uuid,
  p_event_key text,
  p_reference_id uuid,
  p_payload jsonb,
  p_dedupe_key text,
  p_create_in_app boolean default true
) returns uuid language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare
  v_event_id uuid;
  v_notification_id uuid;
  v_template public.notification_templates%rowtype;
  v_pref public.notification_preferences%rowtype;
  v_dlt public.notification_dlt_config%rowtype;
  v_payload jsonb;
  v_sms_allowed boolean := false;
begin
  if p_user_id is null or p_dedupe_key is null or length(p_dedupe_key) not between 8 and 240 then
    raise exception 'Invalid notification recipient or dedupe key';
  end if;
  select * into v_template from public.notification_templates where template_key=p_event_key;
  if not found then raise exception 'Unknown notification template'; end if;
  v_payload := private.redact_notification_json(coalesce(p_payload,'{}'::jsonb));
  if jsonb_typeof(v_payload)<>'object' or length(v_payload::text)>4096 then
    raise exception 'Notification payload is invalid';
  end if;
  insert into public.notification_events(user_id,event_key,reference_id,payload,dedupe_key)
  values(p_user_id,p_event_key,p_reference_id,v_payload,p_dedupe_key)
  on conflict(dedupe_key) do nothing
  returning id into v_event_id;
  if v_event_id is null then
    select id into v_event_id from public.notification_events where dedupe_key=p_dedupe_key;
    return v_event_id;
  end if;

  select * into v_pref from public.notification_preferences where user_id=p_user_id;
  if not found then
    insert into public.notification_preferences(user_id) values(p_user_id)
    on conflict(user_id) do nothing;
    select * into v_pref from public.notification_preferences where user_id=p_user_id;
  end if;

  if p_create_in_app and v_pref.in_app_enabled and v_template.category<>'auth' then
    perform set_config('app.notification_enqueue','on',true);
    insert into public.notifications(user_id,channel,template_key,payload,event_id,status)
    values(p_user_id,'in_app',p_event_key,v_payload,v_event_id,'queued')
    returning id into v_notification_id;
    perform set_config('app.notification_enqueue','off',true);
  end if;

  v_sms_allowed := case
    when v_template.category='marketing' then v_pref.sms_marketing_enabled
    when v_template.category='service' then v_pref.sms_service_enabled
    else false
  end;
  select * into v_dlt from public.notification_dlt_config where id=true and is_active;
  if v_sms_allowed and v_template.sms_enabled and v_template.sms_body_template is not null
     and v_template.sms_header is not null and v_template.sms_content_template_id is not null
     and found and v_dlt.principal_entity_id is not null then
    insert into public.notifications(user_id,channel,template_key,payload,event_id,status)
    values(p_user_id,'sms',p_event_key,v_payload,v_event_id,'queued')
    returning id into v_notification_id;
    insert into public.notification_delivery_jobs(
      notification_id,event_id,user_id,template_key,channel,payload
    ) values(v_notification_id,v_event_id,p_user_id,p_event_key,'sms',v_payload)
    on conflict(notification_id,channel) do nothing;
  end if;
  return v_event_id;
end;
$$;
revoke all on function private.enqueue_notification_event(uuid,text,uuid,jsonb,text,boolean) from public,anon,authenticated;

create or replace function public.update_notification_preferences(
  p_in_app_enabled boolean,
  p_sms_service_enabled boolean,
  p_sms_marketing_enabled boolean,
  p_email_enabled boolean default false,
  p_push_enabled boolean default false,
  p_consent_source text default null,
  p_consent_version text default null
) returns public.notification_preferences language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare
  v_user uuid:=auth.uid();
  v_old public.notification_preferences%rowtype;
  v_new public.notification_preferences%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_sms_service_enabled is null or p_sms_marketing_enabled is null or p_in_app_enabled is null then
    raise exception 'Notification preference values are required';
  end if;
  if (p_sms_service_enabled or p_sms_marketing_enabled) and
     (length(btrim(coalesce(p_consent_source,'')))<3 or length(btrim(coalesce(p_consent_version,'')))<1) then
    raise exception 'Explicit SMS consent source and version are required';
  end if;
  select * into v_old from public.notification_preferences where user_id=v_user for update;
  if not found then
    insert into public.notification_preferences(user_id) values(v_user);
    select * into v_old from public.notification_preferences where user_id=v_user for update;
  end if;
  insert into public.notification_consent_history(user_id,actor_id,channel,enabled,consent_source,consent_version)
  select v_user,v_user,'sms_service',p_sms_service_enabled,
    case when p_sms_service_enabled then left(p_consent_source,100) else null end,
    case when p_sms_service_enabled then left(p_consent_version,40) else null end
  where v_old.sms_service_enabled is distinct from p_sms_service_enabled;
  insert into public.notification_consent_history(user_id,actor_id,channel,enabled,consent_source,consent_version)
  select v_user,v_user,'sms_marketing',p_sms_marketing_enabled,
    case when p_sms_marketing_enabled then left(p_consent_source,100) else null end,
    case when p_sms_marketing_enabled then left(p_consent_version,40) else null end
  where v_old.sms_marketing_enabled is distinct from p_sms_marketing_enabled;
  update public.notification_preferences set
    in_app_enabled=p_in_app_enabled,
    sms_service_enabled=p_sms_service_enabled,
    sms_marketing_enabled=p_sms_marketing_enabled,
    email_enabled=coalesce(p_email_enabled,false),
    push_enabled=coalesce(p_push_enabled,false),
    sms_service_consent_at=case when p_sms_service_enabled then
      case when not v_old.sms_service_enabled then now() else v_old.sms_service_consent_at end else null end,
    sms_marketing_consent_at=case when p_sms_marketing_enabled then
      case when not v_old.sms_marketing_enabled then now() else v_old.sms_marketing_consent_at end else null end,
    sms_consent_source=case when p_sms_service_enabled or p_sms_marketing_enabled then left(p_consent_source,100) else null end,
    sms_consent_version=case when p_sms_service_enabled or p_sms_marketing_enabled then left(p_consent_version,40) else null end,
    sms_revoked_at=case when (v_old.sms_service_enabled or v_old.sms_marketing_enabled)
      and not (p_sms_service_enabled or p_sms_marketing_enabled) then now()
      when p_sms_service_enabled or p_sms_marketing_enabled then null else v_old.sms_revoked_at end,
    updated_at=now()
  where user_id=v_user returning * into v_new;
  if not p_sms_service_enabled and not p_sms_marketing_enabled then
    update public.notification_delivery_jobs set status='cancelled',updated_at=now()
    where user_id=v_user and channel='sms' and status='queued';
    update public.notifications set status='cancelled'
    where user_id=v_user and channel='sms' and status='queued';
  end if;
  return v_new;
end;
$$;
revoke all on function public.update_notification_preferences(boolean,boolean,boolean,boolean,boolean,text,text) from public,anon;
grant execute on function public.update_notification_preferences(boolean,boolean,boolean,boolean,boolean,text,text) to authenticated;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns void language plpgsql security definer
set search_path = pg_catalog,public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.notifications set read_at=coalesce(read_at,now()),status=case when status='sent' or status='delivered' or status='queued' then 'read' else status end
  where id=p_notification_id and user_id=auth.uid() and channel='in_app';
  if not found then raise exception 'Notification not found'; end if;
end;
$$;
revoke all on function public.mark_notification_read(uuid) from public,anon;
grant execute on function public.mark_notification_read(uuid) to authenticated;

create or replace function public.get_my_notification_preferences()
returns public.notification_preferences language sql stable security definer
set search_path = pg_catalog,public
as $$
  select p from public.notification_preferences p where p.user_id=auth.uid();
$$;
revoke all on function public.get_my_notification_preferences() from public,anon;
grant execute on function public.get_my_notification_preferences() to authenticated;

create or replace function private.seed_notification_preferences()
returns trigger language plpgsql security definer
set search_path = pg_catalog,public
as $$
begin
  insert into public.notification_preferences(user_id) values(new.id)
  on conflict(user_id) do nothing;
  return new;
end;
$$;
drop trigger if exists auth_user_seed_notification_preferences on auth.users;
create trigger auth_user_seed_notification_preferences after insert on auth.users
for each row execute function private.seed_notification_preferences();

-- Bridge the existing due-reminder scheduler into the event/delivery pipeline.
create or replace function private.bridge_rental_notification_to_event()
returns trigger language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
begin
  if coalesce(current_setting('app.notification_enqueue',true),'off')='on' then return new; end if;
  if new.channel='in_app' and new.template_key in ('rental.due_reminder','rental.overdue') then
    perform private.enqueue_notification_event(new.user_id,new.template_key,
      null,coalesce(new.payload,'{}'::jsonb),'legacy-rental-notification:'||new.id::text,false);
  end if;
  return new;
end;
$$;
create trigger notifications_legacy_rental_event
after insert on public.notifications
for each row execute function private.bridge_rental_notification_to_event();

-- SMS queue claiming and completion are service-role-only. The dispatch worker
-- rechecks active consent and confirmed phone ownership immediately before send.
create table public.financial_cost_entries (
  id uuid primary key default gen_random_uuid(),
  cost_category text not null check (cost_category in ('gateway_charge','verification','referral','support','sms')),
  amount_paise bigint not null check (amount_paise > 0),
  currency char(3) not null default 'INR' check (currency='INR'),
  occurred_at timestamptz not null,
  city_id uuid references public.cities(id) on delete set null,
  locality_id uuid references public.localities(id) on delete set null,
  vendor text,
  source_type text not null,
  source_reference text not null,
  reason text not null,
  idempotency_key text not null unique,
  created_by uuid references auth.users(id) on delete restrict,
  reverses_entry_id uuid references public.financial_cost_entries(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (length(btrim(reason)) between 10 and 1000),
  check (length(btrim(source_type)) between 2 and 60),
  check (length(btrim(source_reference)) between 1 and 160)
);
create index financial_cost_period_idx on public.financial_cost_entries(cost_category,occurred_at);
create index financial_cost_locality_idx on public.financial_cost_entries(city_id,locality_id,occurred_at);

create or replace function public.claim_notification_delivery_jobs(p_limit integer default 20)
returns table(
  job_id uuid,notification_id uuid,user_id uuid,phone text,template_key text,
  sms_body_template text,sms_header text,sms_content_template_id text,
  principal_entity_id text,telemarketer_chain jsonb,payload jsonb,attempts integer
) language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_job record;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'Service role required';
  end if;
  if p_limit not between 1 and 100 then raise exception 'Invalid claim limit'; end if;
  update public.notification_delivery_jobs
    set status='queued',claimed_at=null,available_at=now(),updated_at=now()
  where status='processing' and claimed_at<now()-interval '5 minutes';

  for v_job in
    select j.id,j.notification_id,j.user_id,j.template_key,j.payload,
      t.sms_body_template,t.sms_header,t.sms_content_template_id,
      d.principal_entity_id,d.telemarketer_chain,u.phone
    from public.notification_delivery_jobs j
    join public.notification_templates t on t.template_key=j.template_key
    join public.notification_preferences pref on pref.user_id=j.user_id
    join auth.users u on u.id=j.user_id
    join public.notification_dlt_config d on d.id=true and d.is_active
    where j.channel='sms' and j.status='queued' and j.available_at<=now()
      and j.attempts<5 and t.sms_enabled and t.sms_body_template is not null
      and t.sms_header is not null and t.sms_content_template_id is not null
      and d.principal_entity_id is not null and u.phone is not null and u.phone_confirmed_at is not null
      and ((t.category='service' and pref.sms_service_enabled)
        or (t.category='marketing' and pref.sms_marketing_enabled))
    order by j.available_at,j.created_at
    limit p_limit
    for update of j skip locked
  loop
    update public.notification_delivery_jobs j
      set status='processing',claimed_at=now(),attempts=j.attempts+1,updated_at=now()
    where j.id=v_job.id;
    return query select v_job.id,v_job.notification_id,v_job.user_id,v_job.phone,v_job.template_key,
      v_job.sms_body_template,v_job.sms_header,v_job.sms_content_template_id,
      v_job.principal_entity_id,v_job.telemarketer_chain,v_job.payload,
      (select j.attempts from public.notification_delivery_jobs j where j.id=v_job.id);
  end loop;
end;
$$;
revoke all on function public.claim_notification_delivery_jobs(integer) from public,anon,authenticated;
grant execute on function public.claim_notification_delivery_jobs(integer) to service_role;

create or replace function public.complete_notification_delivery(
  p_job_id uuid,p_status text,p_provider_reference text default null,
  p_error_code text default null,p_cost_paise bigint default null
) returns void language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_job public.notification_delivery_jobs%rowtype;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Service role required'; end if;
  if p_status not in ('sent','failed') then raise exception 'Invalid delivery status'; end if;
  select * into v_job from public.notification_delivery_jobs where id=p_job_id for update;
  if not found or v_job.status<>'processing' then raise exception 'Delivery job is not processing'; end if;
  if p_status='sent' then
    update public.notification_delivery_jobs set status='sent',
      provider_reference=left(coalesce(p_provider_reference,''),200),
      last_error_code=null,updated_at=now() where id=p_job_id;
    update public.notifications set status='sent',sent_at=now(),
      provider_reference=left(coalesce(p_provider_reference,''),200)
    where id=v_job.notification_id;
    if p_cost_paise is not null and p_cost_paise>0 then
      insert into public.financial_cost_entries(cost_category,amount_paise,occurred_at,
        vendor,source_type,source_reference,reason,idempotency_key)
      values('sms',p_cost_paise,now(),'configured_sms_provider','notification_delivery',
        p_job_id::text,'Provider-reported SMS delivery cost','notification-sms:'||p_job_id::text)
      on conflict(idempotency_key) do nothing;
    end if;
  else
    update public.notification_delivery_jobs set
      status=case when attempts>=5 then 'dead_letter' else 'queued' end,
      available_at=now()+make_interval(secs=>least(3600,(power(2,least(attempts,10))::integer)*30)),
      last_error_code=left(coalesce(p_error_code,'provider_error'),100),
      claimed_at=null,updated_at=now()
    where id=p_job_id;
    update public.notifications set status='failed' where id=v_job.notification_id
      and (select status from public.notification_delivery_jobs where id=p_job_id)='dead_letter';
  end if;
end;
$$;
revoke all on function public.complete_notification_delivery(uuid,text,text,text,bigint) from public,anon,authenticated;
grant execute on function public.complete_notification_delivery(uuid,text,text,text,bigint) to service_role;

-- Notifications from domain events.
create or replace function private.notify_verification_event()
returns trigger language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare v_event text;
begin
  if tg_op='INSERT' then
    if new.status in ('pending','under_review') then
      for v_event in select ur.user_id::text from public.user_roles ur
        where ur.role='verification_reviewer' and ur.revoked_at is null
      loop
        perform private.enqueue_notification_event(v_event::uuid,'verification.submitted',new.user_id,
          jsonb_build_object('verification_status',new.status),'verification-submitted:'||new.user_id::text||':'||v_event);
      end loop;
    end if;
  elsif new.status is distinct from old.status then
    if new.status='verified' then
      perform private.enqueue_notification_event(new.user_id,'verification.approved',new.user_id,
        jsonb_build_object('verification_status',new.status),'verification-approved:'||new.user_id::text);
    elsif new.status in ('rejected','needs_resubmission') then
      perform private.enqueue_notification_event(new.user_id,'verification.rejected',new.user_id,
        jsonb_build_object('verification_status',new.status),'verification-rejected:'||new.user_id::text||':'||new.updated_at::text);
    end if;
  end if;
  return new;
end;
$$;
create trigger user_verification_notification
after insert or update of status on public.user_verifications
for each row execute function private.notify_verification_event();

create or replace function private.notify_listing_event()
returns trigger language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
begin
  if new.listing_status='approved' and (tg_op='INSERT' or old.listing_status is distinct from new.listing_status) then
    perform private.enqueue_notification_event(new.owner_id,'listing.approved',new.id,
      jsonb_build_object('listing_status','approved'),'listing-approved:'||new.id::text||':'||new.updated_at::text);
  elsif new.listing_status='rejected' and (tg_op='INSERT' or old.listing_status is distinct from new.listing_status) then
    perform private.enqueue_notification_event(new.owner_id,'listing.rejected',new.id,
      jsonb_build_object('listing_status','rejected'),'listing-rejected:'||new.id::text||':'||new.updated_at::text);
  end if;
  return new;
end;
$$;
create trigger book_copy_listing_notification
after insert or update of listing_status on public.book_copies
for each row execute function private.notify_listing_event();

create or replace function private.notify_booking_event()
returns trigger language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
begin
  if tg_op='INSERT' then
    perform private.enqueue_notification_event(new.owner_id,'booking.requested',new.id,
      jsonb_build_object('booking_number',new.booking_number,'status',new.status::text),
      'booking-requested:'||new.id::text);
  else
    if new.accepted_at is not null and old.accepted_at is null then
      perform private.enqueue_notification_event(new.reader_id,'booking.accepted',new.id,
        jsonb_build_object('booking_number',new.booking_number,'status',new.status::text),
        'booking-accepted:'||new.id::text);
    end if;
    if new.declined_at is not null and old.declined_at is null then
      perform private.enqueue_notification_event(new.reader_id,'booking.rejected',new.id,
        jsonb_build_object('booking_number',new.booking_number,'status','declined'),
        'booking-rejected:'||new.id::text);
    end if;
  end if;
  return new;
end;
$$;
create trigger booking_notification_events
after insert or update of accepted_at,declined_at on public.bookings
for each row execute function private.notify_booking_event();

create or replace function private.notify_payment_event()
returns trigger language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
begin
  if new.status::text in ('captured','partially_refunded','refunded')
     and (tg_op='INSERT' or old.status::text not in ('captured','partially_refunded','refunded')) then
    perform private.enqueue_notification_event(new.payer_id,'payment.succeeded',new.booking_id,
      jsonb_build_object('payment_status',new.status::text,'amount_paise',new.amount_paise),
      'payment-succeeded:'||new.id::text);
  elsif new.status::text='failed' and (tg_op='INSERT' or old.status::text is distinct from new.status::text) then
    perform private.enqueue_notification_event(new.payer_id,'payment.failed',new.booking_id,
      jsonb_build_object('payment_status','failed','failure_code',new.failure_code),
      'payment-failed:'||new.id::text);
  end if;
  return new;
end;
$$;
create trigger payment_notification_events
after insert or update of status on public.payments
for each row execute function private.notify_payment_event();

create or replace function private.notify_handover_event()
returns trigger language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare v_booking public.bookings%rowtype;
begin
  if new.status='completed' and (tg_op='INSERT' or old.status is distinct from new.status) then
    select * into v_booking from public.bookings where id=new.booking_id;
    if found then
      perform private.enqueue_notification_event(v_booking.reader_id,
        case when new.handover_type='return' then 'return.confirmed' else 'handover.confirmed' end,
        new.booking_id,jsonb_build_object('handover_type',new.handover_type),'handover-complete:'||new.id::text||':'||v_booking.reader_id::text);
      perform private.enqueue_notification_event(v_booking.owner_id,
        case when new.handover_type='return' then 'return.confirmed' else 'handover.confirmed' end,
        new.booking_id,jsonb_build_object('handover_type',new.handover_type),'handover-complete:'||new.id::text||':'||v_booking.owner_id::text);
    end if;
  end if;
  return new;
end;
$$;
create trigger handover_notification_events
after insert or update of status on public.handover_sessions
for each row execute function private.notify_handover_event();

create or replace function private.notify_extension_event()
returns trigger language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare v_booking public.bookings%rowtype; v_recipient uuid;
begin
  select * into v_booking from public.bookings where id=new.booking_id;
  if not found then return new; end if;
  v_recipient:=case when new.requested_by=v_booking.reader_id then v_booking.owner_id else v_booking.reader_id end;
  perform private.enqueue_notification_event(v_recipient,'extension.requested',new.booking_id,
    jsonb_build_object('request_id',new.id,'status',new.status),
    'extension-requested:'||new.id::text||':'||v_recipient::text);
  return new;
end;
$$;
create trigger extension_notification_events
after insert on public.rental_extension_requests
for each row execute function private.notify_extension_event();

create or replace function private.notify_dispute_event()
returns trigger language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
begin
  if tg_op='INSERT' then
    perform private.enqueue_notification_event(new.opened_by,'dispute.opened',new.id,
      jsonb_build_object('dispute_status',new.status::text),'dispute-opened:'||new.id::text||':'||new.opened_by::text);
    perform private.enqueue_notification_event(new.against_user_id,'dispute.opened',new.id,
      jsonb_build_object('dispute_status',new.status::text),'dispute-opened:'||new.id::text||':'||new.against_user_id::text);
  elsif new.status is distinct from old.status then
    perform private.enqueue_notification_event(new.opened_by,'dispute.updated',new.id,
      jsonb_build_object('dispute_status',new.status::text),'dispute-updated:'||new.id::text||':'||new.status::text||':'||new.opened_by::text);
    perform private.enqueue_notification_event(new.against_user_id,'dispute.updated',new.id,
      jsonb_build_object('dispute_status',new.status::text),'dispute-updated:'||new.id::text||':'||new.status::text||':'||new.against_user_id::text);
  end if;
  return new;
end;
$$;
create trigger dispute_notification_events
after insert or update of status on public.disputes
for each row execute function private.notify_dispute_event();

create or replace function private.notify_refund_event()
returns trigger language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare v_user uuid;
begin
  if new.status is distinct from old.status then
    select payer_id into v_user from public.payments where id=new.payment_id;
    if v_user is not null then perform private.enqueue_notification_event(v_user,'refund.updated',new.booking_id,
      jsonb_build_object('refund_status',new.status),'refund-updated:'||new.id::text||':'||new.status); end if;
  end if;
  return new;
end;
$$;
create trigger refund_notification_events
after update of status on public.refunds
for each row execute function private.notify_refund_event();

create or replace function private.notify_payout_event()
returns trigger language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
begin
  if new.status is distinct from old.status then
    perform private.enqueue_notification_event(new.owner_id,'payout.updated',new.owner_earning_id,
      jsonb_build_object('payout_status',new.status::text,'amount_paise',new.amount_paise),
      'payout-updated:'||new.id::text||':'||new.status::text);
  end if;
  return new;
end;
$$;
create trigger payout_notification_events
after update of status on public.payouts
for each row execute function private.notify_payout_event();

create or replace function private.notify_referral_reward_event()
returns trigger language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
begin
  if new.status='issued' and (tg_op='INSERT' or old.status is distinct from new.status) then
    perform private.enqueue_notification_event(new.beneficiary_id,'referral.rewarded',new.id,
      jsonb_build_object('reward_type',new.reward_type,'reward_value_paise',new.reward_value_paise),
      'referral-rewarded:'||new.id::text);
  end if;
  return new;
end;
$$;
create trigger referral_reward_notification_events
after insert or update of status on public.referral_rewards
for each row execute function private.notify_referral_reward_event();

create or replace function private.notify_community_activity()
returns trigger language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare v_author uuid;
begin
  select author_id into v_author from public.community_posts where id=new.post_id and status='published';
  if new.status='published' and v_author is not null and v_author<>new.author_id then
    perform private.enqueue_notification_event(v_author,'community.activity',new.post_id,
      jsonb_build_object('post_id',new.post_id,'activity_type','comment'),
      'community-comment:'||new.id::text||':'||v_author::text);
  end if;
  return new;
end;
$$;
create trigger community_comment_notification_events
after insert on public.community_comments
for each row execute function private.notify_community_activity();

create or replace function private.notify_grievance_update()
returns trigger language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
begin
  if tg_op='UPDATE' and (
    new.status is distinct from old.status or new.priority is distinct from old.priority
    or new.assigned_to is distinct from old.assigned_to or new.resolved_at is distinct from old.resolved_at
  ) then
    perform private.enqueue_notification_event(new.requester_id,'grievance.updated',new.id,
      jsonb_build_object('ticket_number',new.ticket_number,'status',new.status::text,'priority',new.priority),
      'grievance-updated:'||new.id::text||':'||new.updated_at::text);
  end if;
  return new;
end;
$$;
create trigger grievance_notification_events
after update on public.grievance_tickets
for each row execute function private.notify_grievance_update();

-- Support tickets reuse grievance_tickets and add auditable conversation, history,
-- assignment, SLA and escalation data instead of creating a competing case table.
create sequence public.support_ticket_number_seq;
create table public.support_ticket_categories (
  category_key text primary key,
  label text not null,
  is_active boolean not null default true,
  sort_order integer not null default 100
);
insert into public.support_ticket_categories(category_key,label,sort_order) values
('booking','Booking',10),('payment','Payments',20),('deposit','Security deposit',30),
('account','Account',40),('verification','Verification',50),('listing','Book listing',60),
('safety','Safety and disputes',70),('privacy','Privacy request',80),('other','Other',90)
on conflict(category_key) do nothing;

create table public.support_sla_policies (
  priority text primary key check (priority in ('low','normal','high','urgent')),
  first_response_minutes integer not null check (first_response_minutes between 5 and 10080),
  resolution_minutes integer not null check (resolution_minutes between 30 and 43200),
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  check (resolution_minutes>=first_response_minutes)
);
insert into public.support_sla_policies(priority,first_response_minutes,resolution_minutes) values
('low',1440,10080),('normal',480,4320),('high',120,1440),('urgent',30,240)
on conflict(priority) do nothing;

alter table public.grievance_tickets
  add column if not exists first_response_due_at timestamptz,
  add column if not exists resolution_due_at timestamptz,
  add column if not exists first_response_at timestamptz,
  add column if not exists sla_breached_at timestamptz,
  add column if not exists escalated_at timestamptz,
  add column if not exists closed_at timestamptz,
  add column if not exists last_requester_message_at timestamptz,
  add column if not exists last_staff_message_at timestamptz;
update public.grievance_tickets t set
  first_response_due_at=coalesce(t.first_response_due_at,t.created_at+make_interval(mins=>p.first_response_minutes)),
  resolution_due_at=coalesce(t.resolution_due_at,t.created_at+make_interval(mins=>p.resolution_minutes)),
  last_requester_message_at=coalesce(t.last_requester_message_at,t.created_at)
from public.support_sla_policies p where p.priority=t.priority;

create table public.support_ticket_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.grievance_tickets(id) on delete restrict,
  author_id uuid references auth.users(id) on delete restrict,
  author_type text not null check (author_type in ('requester','staff','system')),
  body text not null check (length(btrim(body)) between 1 and 5000),
  is_internal boolean not null default false,
  created_at timestamptz not null default now(),
  check ((author_type='system' and author_id is null) or (author_type<>'system' and author_id is not null)),
  check (not is_internal or author_type in ('staff','system'))
);
create index support_ticket_messages_ticket_idx on public.support_ticket_messages(ticket_id,created_at);

create table public.support_ticket_history (
  id bigint generated always as identity primary key,
  ticket_id uuid not null references public.grievance_tickets(id) on delete restrict,
  actor_id uuid references auth.users(id) on delete restrict,
  event_type text not null,
  old_status public.ticket_status,
  new_status public.ticket_status,
  old_priority text,
  new_priority text,
  old_assignee uuid,
  new_assignee uuid,
  reason text,
  created_at timestamptz not null default now()
);
create index support_ticket_history_ticket_idx on public.support_ticket_history(ticket_id,created_at desc);

create or replace function private.reject_support_history_mutation()
returns trigger language plpgsql set search_path=pg_catalog
as $$ begin raise exception 'Support history is append-only'; end $$;
create trigger support_ticket_history_append_only
before update or delete on public.support_ticket_history
for each row execute function private.reject_support_history_mutation();
create trigger notification_events_append_only
before update or delete on public.notification_events
for each row execute function private.reject_support_history_mutation();
create trigger notification_consent_history_append_only
before update or delete on public.notification_consent_history
for each row execute function private.reject_support_history_mutation();

create or replace function public.create_support_ticket(
  p_category text,p_subject text,p_description text,p_priority text default 'normal'
) returns uuid language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare
  v_user uuid:=auth.uid();
  v_ticket_id uuid;
  v_number text;
  v_priority text:=coalesce(p_priority,'normal');
  v_sla public.support_sla_policies%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if length(btrim(coalesce(p_subject,''))) not between 4 and 160
    or length(btrim(coalesce(p_description,''))) not between 10 and 5000 then
    raise exception 'A valid ticket subject and description are required';
  end if;
  if v_priority not in ('low','normal','high','urgent') then raise exception 'Invalid ticket priority'; end if;
  if not exists(select 1 from public.support_ticket_categories where category_key=p_category and is_active) then
    raise exception 'Unsupported support category';
  end if;
  select * into v_sla from public.support_sla_policies where priority=v_priority and is_active;
  if not found then raise exception 'Active support SLA policy not found'; end if;
  v_number:='SS-'||to_char(now() at time zone 'UTC','YYMMDD')||'-'||lpad(nextval('public.support_ticket_number_seq')::text,6,'0');
  insert into public.grievance_tickets(
    ticket_number,requester_id,category,subject,description,status,priority,
    first_response_due_at,resolution_due_at,last_requester_message_at
  ) values (
    v_number,v_user,p_category,left(p_subject,160),left(p_description,5000),'open',v_priority,
    now()+make_interval(mins=>v_sla.first_response_minutes),
    now()+make_interval(mins=>v_sla.resolution_minutes),now()
  ) returning id into v_ticket_id;
  insert into public.support_ticket_messages(ticket_id,author_id,author_type,body)
    values(v_ticket_id,v_user,'requester',left(p_description,5000));
  insert into public.support_ticket_history(ticket_id,actor_id,event_type,new_status,new_priority,reason)
    values(v_ticket_id,v_user,'ticket_created','open',v_priority,'Customer created support ticket');
  perform private.enqueue_notification_event(v_user,'grievance.updated',v_ticket_id,
    jsonb_build_object('ticket_number',v_number,'status','open'),
    'grievance-created:'||v_ticket_id::text);
  return v_ticket_id;
end;
$$;
revoke all on function public.create_support_ticket(text,text,text,text) from public,anon;
grant execute on function public.create_support_ticket(text,text,text,text) to authenticated;

create or replace function public.reply_support_ticket(
  p_ticket_id uuid,p_body text,p_internal boolean default false
) returns uuid language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare
  v_user uuid:=auth.uid();
  v_ticket public.grievance_tickets%rowtype;
  v_staff boolean:=false;
  v_message uuid;
  v_other uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if length(btrim(coalesce(p_body,''))) not between 1 and 5000 then raise exception 'Message body is required'; end if;
  select * into v_ticket from public.grievance_tickets where id=p_ticket_id for update;
  if not found then raise exception 'Support ticket not found'; end if;
  v_staff:=public.admin_has_permission('support.manage') or public.admin_has_permission('grievances.manage');
  if v_ticket.requester_id<>v_user and not v_staff then raise exception 'Support ticket access denied'; end if;
  if p_internal and not v_staff then raise exception 'Only support staff may add internal notes'; end if;
  if v_ticket.status='closed' then raise exception 'Closed ticket cannot receive replies'; end if;
  insert into public.support_ticket_messages(ticket_id,author_id,author_type,body,is_internal)
  values(p_ticket_id,v_user,case when v_staff then 'staff' else 'requester' end,left(p_body,5000),coalesce(p_internal,false))
  returning id into v_message;
  if not coalesce(p_internal,false) then
    if v_staff then
      update public.grievance_tickets set
        first_response_at=coalesce(first_response_at,now()),
        last_staff_message_at=now(),
        status=case when status='open' or status='waiting_user' then 'waiting_user'::public.ticket_status else status end,
        updated_at=now()
      where id=p_ticket_id;
      v_other:=v_ticket.requester_id;
    else
      update public.grievance_tickets set
        last_requester_message_at=now(),
        status=case when status in ('waiting_user','resolved') then 'in_progress'::public.ticket_status else status end,
        resolved_at=case when status='resolved' then null else resolved_at end,
        closed_at=null,updated_at=now()
      where id=p_ticket_id;
      v_other:=v_ticket.assigned_to;
    end if;
    if v_other is not null then
      perform private.enqueue_notification_event(v_other,'grievance.updated',p_ticket_id,
        jsonb_build_object('ticket_number',v_ticket.ticket_number,'status',
          case when v_staff then 'waiting_user' else 'in_progress' end),
        'support-reply:'||v_message::text||':'||v_other::text);
    end if;
  end if;
  insert into public.support_ticket_history(ticket_id,actor_id,event_type,old_status,new_status,reason)
  values(p_ticket_id,v_user,case when p_internal then 'internal_note_added' else 'reply_added' end,
    v_ticket.status,(select status from public.grievance_tickets where id=p_ticket_id),
    case when p_internal then 'Internal support note' else null end);
  return v_message;
end;
$$;
revoke all on function public.reply_support_ticket(uuid,text,boolean) from public,anon;
grant execute on function public.reply_support_ticket(uuid,text,boolean) to authenticated;

create or replace function public.manage_support_ticket(
  p_ticket_id uuid,p_status text,p_priority text,p_assigned_to uuid,p_reason text
) returns void language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare
  v_user uuid:=auth.uid();
  v_ticket public.grievance_tickets%rowtype;
  v_sla public.support_sla_policies%rowtype;
  v_status public.ticket_status;
begin
  if v_user is null or not (public.admin_has_permission('support.manage') or public.admin_has_permission('grievances.manage')) then
    raise exception 'Support management permission required';
  end if;
  if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception 'Step-up MFA AAL2 required'; end if;
  if p_status not in ('open','in_progress','waiting_user','resolved','closed')
    or p_priority not in ('low','normal','high','urgent')
    or length(btrim(coalesce(p_reason,'')))<15 then raise exception 'Invalid support update or reason';
  end if;
  select * into v_ticket from public.grievance_tickets where id=p_ticket_id for update;
  if not found then raise exception 'Support ticket not found'; end if;
  if p_assigned_to is not null and not exists(
    select 1 from public.user_roles ur join public.admin_role_permissions rp on rp.role=ur.role
    where ur.user_id=p_assigned_to and ur.revoked_at is null and rp.permission_key in ('support.manage','grievances.manage')
  ) then raise exception 'Assignee is not an active support staff member'; end if;
  select * into v_sla from public.support_sla_policies where priority=p_priority and is_active;
  if not found then raise exception 'Active support SLA policy not found'; end if;
  v_status:=p_status::public.ticket_status;
  update public.grievance_tickets set
    status=v_status,priority=p_priority,assigned_to=p_assigned_to,
    first_response_due_at=case when first_response_at is null then least(coalesce(first_response_due_at,created_at+make_interval(mins=>v_sla.first_response_minutes)),created_at+make_interval(mins=>v_sla.first_response_minutes)) else first_response_due_at end,
    resolution_due_at=case when v_status not in ('resolved','closed') then greatest(coalesce(resolution_due_at,now()),now()) else resolution_due_at end,
    resolved_at=case when v_status='resolved' then coalesce(resolved_at,now()) when v_status in ('open','in_progress','waiting_user') then null else resolved_at end,
    closed_at=case when v_status='closed' then coalesce(closed_at,now()) else null end,
    updated_at=now()
  where id=p_ticket_id;
  insert into public.support_ticket_history(ticket_id,actor_id,event_type,old_status,new_status,
    old_priority,new_priority,old_assignee,new_assignee,reason)
  values(p_ticket_id,v_user,'ticket_managed',v_ticket.status,v_status,v_ticket.priority,p_priority,
    v_ticket.assigned_to,p_assigned_to,left(p_reason,1000));
  insert into public.admin_audit_logs(actor_id,action,target_table,target_id,reason,before_data,after_data)
  values(v_user,'support_ticket_managed','grievance_tickets',p_ticket_id::text,left(p_reason,1000),
    jsonb_build_object('status',v_ticket.status,'priority',v_ticket.priority,'assigned_to',v_ticket.assigned_to),
    jsonb_build_object('status',v_status,'priority',p_priority,'assigned_to',p_assigned_to));
end;
$$;
revoke all on function public.manage_support_ticket(uuid,text,text,uuid,text) from public,anon;
grant execute on function public.manage_support_ticket(uuid,text,text,uuid,text) to authenticated;

create or replace function public.run_support_sla_sweep(p_now timestamptz default now())
returns jsonb language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_ticket record; v_count integer:=0; v_assignee uuid;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Service role required'; end if;
  for v_ticket in
    select * from public.grievance_tickets
    where status not in ('resolved','closed') and escalated_at is null
      and ((first_response_at is null and first_response_due_at<=p_now)
        or resolution_due_at<=p_now)
    order by coalesce(first_response_due_at,resolution_due_at)
    for update skip locked
  loop
    select ur.user_id into v_assignee from public.user_roles ur
    join public.admin_role_permissions rp on rp.role=ur.role and rp.permission_key in ('support.manage','grievances.manage')
    where ur.revoked_at is null order by ur.granted_at limit 1;
    update public.grievance_tickets set
      sla_breached_at=coalesce(sla_breached_at,p_now),
      escalated_at=p_now,
      priority=case when priority in ('low','normal') then 'high' else 'urgent' end,
      assigned_to=coalesce(assigned_to,v_assignee),
      updated_at=p_now
    where id=v_ticket.id;
    insert into public.support_ticket_history(ticket_id,event_type,old_status,new_status,old_priority,new_priority,
      old_assignee,new_assignee,reason)
    values(v_ticket.id,'sla_escalated',v_ticket.status,v_ticket.status,v_ticket.priority,
      case when v_ticket.priority in ('low','normal') then 'high' else 'urgent' end,
      v_ticket.assigned_to,coalesce(v_ticket.assigned_to,v_assignee),'SLA deadline passed');
    insert into public.support_ticket_messages(ticket_id,author_type,body,is_internal)
    values(v_ticket.id,'system','This ticket has been escalated because its configured SLA deadline was missed.',true);
    perform private.enqueue_notification_event(v_ticket.requester_id,'grievance.updated',v_ticket.id,
      jsonb_build_object('ticket_number',v_ticket.ticket_number,'status',v_ticket.status::text,'escalated',true),
      'support-sla-escalation:'||v_ticket.id::text);
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('escalated_tickets',v_count,'checked_at',p_now);
end;
$$;
revoke all on function public.run_support_sla_sweep(timestamptz) from public,anon,authenticated;
grant execute on function public.run_support_sla_sweep(timestamptz) to service_role;

-- Financial cost inputs are append-only, idempotent and separate from marketplace
-- rental proceeds. Costs only represent values recorded from invoices or providers.
insert into public.admin_permission_catalog(permission_key,module_key,description,sensitivity) values
('finance.analytics.read','financial-analytics','Read finance analytics and download financial reports','financial'),
('finance.costs.write','financial-analytics','Record verified operating cost entries','financial')
on conflict(permission_key) do update set module_key=excluded.module_key,description=excluded.description,sensitivity=excluded.sensitivity;
insert into public.admin_role_permissions(role,permission_key) values
('finance_operator','finance.analytics.read'),('finance_operator','finance.costs.write')
on conflict do nothing;

create or replace function private.reject_financial_cost_mutation()
returns trigger language plpgsql set search_path=pg_catalog
as $$ begin raise exception 'Financial cost entries are append-only; record a reversal'; end $$;
create trigger financial_cost_entries_append_only
before update or delete on public.financial_cost_entries
for each row execute function private.reject_financial_cost_mutation();

create or replace function public.record_financial_cost(
  p_cost_category text,p_amount_paise bigint,p_occurred_at timestamptz,p_vendor text,
  p_source_type text,p_source_reference text,p_reason text,p_idempotency_key text,
  p_city_id uuid default null,p_locality_id uuid default null
) returns uuid language plpgsql security definer
set search_path = pg_catalog,public
as $$
declare v_user uuid:=auth.uid(); v_id uuid;
begin
  if v_user is null or not public.admin_has_permission('finance.costs.write')
    or coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception 'Finance cost permission and MFA AAL2 required'; end if;
  if p_cost_category not in ('gateway_charge','verification','referral','support','sms')
    or p_amount_paise<=0 or p_occurred_at is null or length(btrim(coalesce(p_reason,'')))<20
    or length(btrim(coalesce(p_idempotency_key,''))) not between 20 and 160 then
    raise exception 'Invalid financial cost entry';
  end if;
  if p_locality_id is not null and (p_city_id is null or not exists(
    select 1 from public.localities l where l.id=p_locality_id and l.city_id=p_city_id
  )) then raise exception 'Locality must belong to the selected city'; end if;
  insert into public.financial_cost_entries(cost_category,amount_paise,occurred_at,city_id,locality_id,
    vendor,source_type,source_reference,reason,idempotency_key,created_by)
  values(p_cost_category,p_amount_paise,p_occurred_at,p_city_id,p_locality_id,
    nullif(left(coalesce(p_vendor,''),120),''),p_source_type,p_source_reference,left(p_reason,1000),
    p_idempotency_key,v_user)
  on conflict(idempotency_key) do nothing
  returning id into v_id;
  if v_id is null then select id into v_id from public.financial_cost_entries where idempotency_key=p_idempotency_key; end if;
  insert into public.admin_audit_logs(actor_id,action,target_table,target_id,reason,after_data)
  values(v_user,'financial_cost_recorded','financial_cost_entries',v_id::text,left(p_reason,1000),
    jsonb_build_object('category',p_cost_category,'amount_paise',p_amount_paise,'source_reference',p_source_reference));
  return v_id;
end;
$$;
revoke all on function public.record_financial_cost(text,bigint,timestamptz,text,text,text,text,text,uuid,uuid) from public,anon;
grant execute on function public.record_financial_cost(text,bigint,timestamptz,text,text,text,text,text,uuid,uuid) to authenticated;

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
      and p.captured_at>=p_from::timestamptz
      and p.captured_at<(p_to+1)::timestamptz
    group by b.id,b.reader_id,b.city_id,b.rent_subtotal_paise,b.tax_paise
  )
  select coalesce(sum(rent_subtotal_paise),0),count(*),coalesce(sum(tax_paise),0)
    into v_gross,v_paid_count,v_tax from paid;

  select coalesce(sum(cl.commission_paise),0) into v_commission
  from public.commission_ledger cl
  where cl.created_at>=p_from::timestamptz and cl.created_at<(p_to+1)::timestamptz;

  select coalesce(sum(amount_paise),0) into v_gateway
  from public.financial_cost_entries where cost_category='gateway_charge'
    and occurred_at>=p_from::timestamptz and occurred_at<(p_to+1)::timestamptz;
  select coalesce(sum(amount_paise),0) into v_sms
  from public.financial_cost_entries where cost_category='sms'
    and occurred_at>=p_from::timestamptz and occurred_at<(p_to+1)::timestamptz;
  select coalesce(sum(amount_paise),0) into v_verification
  from public.financial_cost_entries where cost_category='verification'
    and occurred_at>=p_from::timestamptz and occurred_at<(p_to+1)::timestamptz;
  select coalesce(sum(amount_paise),0) into v_referral_ops
  from public.financial_cost_entries where cost_category='referral'
    and occurred_at>=p_from::timestamptz and occurred_at<(p_to+1)::timestamptz;
  select coalesce(sum(reward_value_paise),0) into v_referral_rewards
  from public.referral_rewards where status='issued'
    and created_at>=p_from::timestamptz and created_at<(p_to+1)::timestamptz;
  select coalesce(sum(amount_paise),0) into v_support
  from public.financial_cost_entries where cost_category='support'
    and occurred_at>=p_from::timestamptz and occurred_at<(p_to+1)::timestamptz;
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
    select locality_id,city_id,count(distinct id) as booking_count,sum(rent_subtotal_paise) as gross_paise
    from paid_locality group by locality_id,city_id
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

-- Access restrictions for application-facing roles. Service role remains trusted.
alter table public.notification_preferences enable row level security;
alter table public.notification_consent_history enable row level security;
alter table public.notification_templates enable row level security;
alter table public.notification_events enable row level security;
alter table public.notification_dlt_config enable row level security;
alter table public.notification_delivery_jobs enable row level security;
alter table public.support_ticket_categories enable row level security;
alter table public.support_sla_policies enable row level security;
alter table public.support_ticket_messages enable row level security;
alter table public.support_ticket_history enable row level security;
alter table public.financial_cost_entries enable row level security;

create policy notification_preferences_read_self on public.notification_preferences
  for select to authenticated using(user_id=auth.uid());
create policy notification_consent_read_self on public.notification_consent_history
  for select to authenticated using(user_id=auth.uid());
create policy support_categories_read_active on public.support_ticket_categories
  for select to anon,authenticated using(is_active);
create policy grievance_tickets_support_read on public.grievance_tickets
  for select to authenticated using(public.admin_has_permission('support.manage') or public.admin_has_permission('grievances.manage'));
create policy support_messages_participant_read on public.support_ticket_messages
  for select to authenticated using(
    exists(select 1 from public.grievance_tickets t where t.id=ticket_id and t.requester_id=auth.uid() and not is_internal)
    or public.admin_has_permission('support.manage') or public.admin_has_permission('grievances.manage')
  );
create policy support_history_participant_read on public.support_ticket_history
  for select to authenticated using(
    exists(select 1 from public.grievance_tickets t where t.id=ticket_id and t.requester_id=auth.uid())
    or public.admin_has_permission('support.manage') or public.admin_has_permission('grievances.manage')
  );

revoke all on public.notification_preferences,public.notification_consent_history,
  public.notification_templates,public.notification_events,public.notification_dlt_config,
  public.notification_delivery_jobs,public.support_sla_policies,public.support_ticket_messages,
  public.support_ticket_history,public.financial_cost_entries from anon,authenticated;
grant select on public.notification_preferences,public.notification_consent_history to authenticated;
grant select on public.support_ticket_categories to anon,authenticated;
grant select on public.grievance_tickets,public.support_ticket_messages,public.support_ticket_history to authenticated;
revoke insert,update,delete on public.notifications,public.grievance_tickets from anon,authenticated;
grant select on public.notifications to authenticated;

commit;

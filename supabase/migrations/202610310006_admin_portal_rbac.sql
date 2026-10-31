begin;

-- Fine-grained permissions sit on top of the six existing staff roles.
create table public.admin_permission_catalog (
  permission_key text primary key,
  module_key text not null,
  description text not null,
  sensitivity text not null default 'standard'
    check (sensitivity in ('standard','personal_data','identity','financial','high_risk'))
);

create table public.admin_role_permissions (
  role text not null check (role in (
    'support_agent','verification_reviewer','finance_operator',
    'moderator','admin','super_admin'
  )),
  permission_key text not null references public.admin_permission_catalog(permission_key) on delete restrict,
  granted_at timestamptz not null default now(),
  primary key(role, permission_key)
);

create table public.admin_activity_events (
  id bigint generated always as identity primary key,
  actor_id uuid not null references auth.users(id) on delete restrict,
  action text not null,
  module_key text not null,
  permission_key text,
  target_table text,
  target_id text,
  outcome text not null check (outcome in ('success','denied','failed')),
  reason text,
  request_id text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index admin_activity_actor_time_idx
  on public.admin_activity_events(actor_id, created_at desc);
create index admin_activity_module_time_idx
  on public.admin_activity_events(module_key, created_at desc);
create index admin_activity_target_idx
  on public.admin_activity_events(target_table, target_id, created_at desc);

create table public.admin_approval_requests (
  id uuid primary key default gen_random_uuid(),
  action_key text not null check (action_key in (
    'refund.execute','payout.execute','deposit.release','dispute.finalize',
    'pricing.publish','valuation.publish','legal.publish','risk.resolve',
    'user.suspend','user.role.grant'
  )),
  target_table text not null,
  target_id text not null,
  request_payload jsonb not null default '{}'::jsonb,
  reason text not null check (length(btrim(reason)) between 30 and 2000),
  requested_by uuid not null references auth.users(id) on delete restrict,
  approved_by uuid references auth.users(id) on delete restrict,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','expired','cancelled','executed')),
  decision_reason text,
  expires_at timestamptz not null default (now() + interval '48 hours'),
  decided_at timestamptz,
  executed_at timestamptz,
  idempotency_key text not null unique,
  created_at timestamptz not null default now(),
  check (approved_by is null or approved_by <> requested_by),
  check (jsonb_typeof(request_payload) = 'object'),
  check (length(request_payload::text) <= 8192)
);
create index admin_approval_pending_idx
  on public.admin_approval_requests(status, expires_at, created_at desc);
create index admin_approval_actor_idx
  on public.admin_approval_requests(requested_by, created_at desc);

-- Rules are versioned, inactive until separately approved, and never applied
-- automatically by an admin browser request.
create table public.book_valuation_rules (
  id uuid primary key default gen_random_uuid(),
  rule_key text not null,
  version text not null,
  description text not null,
  formula jsonb not null,
  effective_from timestamptz not null,
  effective_until timestamptz,
  status text not null default 'draft'
    check (status in ('draft','pending_approval','active','paused','retired')),
  created_by uuid not null references auth.users(id) on delete restrict,
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  unique(rule_key,version),
  check (effective_until is null or effective_until > effective_from),
  check (approved_by is null or approved_by <> created_by),
  check (status <> 'active' or (approved_by is not null and approved_at is not null))
);
create index book_valuation_rules_effective_idx
  on public.book_valuation_rules(rule_key,effective_from desc);

create table public.admin_referral_campaigns (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  reward_type text not null check (reward_type in ('booking_discount','fee_credit','non_cash')),
  reward_value_paise bigint not null default 0 check (reward_value_paise >= 0),
  qualifying_minimum_paise bigint not null default 0 check (qualifying_minimum_paise >= 0),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  max_redemptions integer check (max_redemptions is null or max_redemptions > 0),
  status text not null default 'draft'
    check (status in ('draft','scheduled','active','paused','ended')),
  created_by uuid not null references auth.users(id) on delete restrict,
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (approved_by is null or approved_by <> created_by),
  check (status <> 'active' or (approved_by is not null and approved_at is not null))
);
create index admin_referral_campaigns_status_idx
  on public.admin_referral_campaigns(status,starts_at,ends_at);

alter table public.referrals
  add column if not exists campaign_id uuid references public.admin_referral_campaigns(id) on delete restrict;

-- Role permissions: explicit allowlists. No role has access to every data class.
insert into public.admin_permission_catalog(permission_key,module_key,description,sensitivity) values
('dashboard.read','dashboard','Read operational KPI cards','standard'),
('users.read','users','Read public-safe account metadata','personal_data'),
('users.manage','users','Change account restrictions and staff-managed profile state','high_risk'),
('users.suspend.request','users','Request an account suspension action','high_risk'),
('users.suspend.approve','users','Approve an account suspension action','high_risk'),
('verification.queue.read','verification','Read verification queue metadata only','personal_data'),
('verification.decide','verification','Accept/reject identity verification records','identity'),
('identity.documents.read','verification','Open a private identity document using a short-lived URL','identity'),
('catalogue.read','catalogue','Read book-title catalogue metadata','standard'),
('catalogue.moderate','catalogue','Moderate book-title metadata','standard'),
('inventory.read','inventory','Read physical copy moderation metadata','personal_data'),
('inventory.moderate','inventory','Approve, reject or pause physical copy listings','high_risk'),
('geography.read','geography','Read city, locality and handover location records','standard'),
('geography.manage','geography','Manage city, locality and handover reference data','high_risk'),
('pricing.read','pricing','Read versioned rental pricing rules','financial'),
('pricing.publish.request','pricing','Request publication of rental pricing rules','high_risk'),
('pricing.publish.approve','pricing','Approve publication of rental pricing rules','high_risk'),
('valuation.read','valuation','Read book valuation rules','financial'),
('valuation.publish.request','valuation','Request publication of valuation rules','high_risk'),
('valuation.publish.approve','valuation','Approve publication of valuation rules','high_risk'),
('bookings.read','bookings','Read booking operations metadata','personal_data'),
('payments.read','payments','Read payment transaction metadata','financial'),
('deposits.read','deposits','Read booking-specific deposit status','financial'),
('deposits.release.request','deposits','Request a provider-approved deposit release','financial'),
('deposits.release.approve','deposits','Approve a deposit release request','financial'),
('commission.read','commission','Read commission ledger summaries','financial'),
('payouts.read','payouts','Read owner payout metadata','financial'),
('payouts.execute.request','payouts','Request an owner payout operation','financial'),
('payouts.execute.approve','payouts','Approve an owner payout operation','financial'),
('refunds.read','refunds','Read refund transaction metadata','financial'),
('refunds.execute.request','refunds','Request a payment refund operation','financial'),
('refunds.execute.approve','refunds','Approve a payment refund operation','financial'),
('disputes.read','disputes','Read dispute case metadata','personal_data'),
('disputes.finalize.request','disputes','Request a final dispute decision','high_risk'),
('disputes.finalize.approve','disputes','Approve a final dispute decision','high_risk'),
('claims.read','claims','Read damage claim metadata','personal_data'),
('claims.decide','claims','Decide damage claim outcomes','high_risk'),
('late_fees.read','late-fees','Read proposed and assessed late fees','financial'),
('community.moderate','community','Moderate posts and comments','standard'),
('reviews.moderate','reviews','Moderate customer reviews','personal_data'),
('referrals.read','referrals','Read referral campaign and reward metadata','financial'),
('referrals.manage','referrals','Manage referral campaign drafts','high_risk'),
('risk.read','risk','Read risk alert summaries','personal_data'),
('risk.resolve.request','risk','Request a risk alert resolution','high_risk'),
('risk.resolve.approve','risk','Approve a risk alert resolution','high_risk'),
('support.read','support','Read customer support incident metadata','personal_data'),
('support.manage','support','Assign and manage support incidents','personal_data'),
('grievances.read','grievances','Read grievance case metadata','personal_data'),
('grievances.manage','grievances','Assign and manage grievance cases','personal_data'),
('privacy.read','privacy','Read privacy request metadata','identity'),
('privacy.manage','privacy','Process privacy request workflow metadata','identity'),
('legal.read','legal','Read published and draft legal document metadata','standard'),
('legal.publish.request','legal','Request legal document publication','high_risk'),
('legal.publish.approve','legal','Approve legal document publication','high_risk'),
('audit.read','audit','Read redacted admin activity history','personal_data'),
('reconciliation.read','reconciliation','Read payment reconciliation run summaries','financial'),
('reconciliation.run','reconciliation','Request or start a reconciliation run','financial'),
('analytics.read','analytics','Read aggregate business metrics','standard'),
('settings.read','settings','Read operational settings','high_risk'),
('settings.manage','settings','Manage non-financial operational settings','high_risk'),
('access.roles.manage','access','Grant or revoke non-super-admin staff roles','high_risk'),
('approvals.read','approvals','Read maker-checker approval requests','high_risk')
on conflict(permission_key) do update set
  module_key=excluded.module_key,
  description=excluded.description,
  sensitivity=excluded.sensitivity;

-- Verification is a distinct fiduciary function. Identity access is not granted
-- to admin or super_admin by default.
insert into public.admin_role_permissions(role,permission_key)
select 'verification_reviewer',permission_key from public.admin_permission_catalog
where permission_key = any(array[
  'dashboard.read','users.read','verification.queue.read',
  'verification.decide','identity.documents.read'
]) on conflict do nothing;

insert into public.admin_role_permissions(role,permission_key)
select 'support_agent',permission_key from public.admin_permission_catalog
where permission_key = any(array[
  'dashboard.read','users.read','bookings.read','disputes.read','claims.read',
  'risk.read','support.read','support.manage','grievances.read','grievances.manage',
  'privacy.read'
]) on conflict do nothing;

insert into public.admin_role_permissions(role,permission_key)
select 'moderator',permission_key from public.admin_permission_catalog
where permission_key = any(array[
  'dashboard.read','users.read','catalogue.read','catalogue.moderate',
  'inventory.read','inventory.moderate','community.moderate','reviews.moderate',
  'risk.read','referrals.read'
]) on conflict do nothing;

insert into public.admin_role_permissions(role,permission_key)
select 'finance_operator',permission_key from public.admin_permission_catalog
where permission_key = any(array[
  'dashboard.read','bookings.read','payments.read','deposits.read',
  'deposits.release.request','deposits.release.approve','commission.read',
  'payouts.read','payouts.execute.request','payouts.execute.approve',
  'refunds.read','refunds.execute.request','refunds.execute.approve',
  'disputes.read','disputes.finalize.request','disputes.finalize.approve',
  'claims.read','late_fees.read','reconciliation.read','reconciliation.run',
  'analytics.read','approvals.read'
]) on conflict do nothing;

-- Admin gets operational management and safe summaries, but no payment/deposit/
-- payout/refund rows, no identity files, and no finance execution permissions.
insert into public.admin_role_permissions(role,permission_key)
select 'admin',permission_key from public.admin_permission_catalog
where permission_key = any(array[
  'dashboard.read','users.read','users.manage','users.suspend.request',
  'verification.queue.read','catalogue.read','catalogue.moderate',
  'inventory.read','inventory.moderate','geography.read','geography.manage',
  'pricing.read','pricing.publish.request','valuation.read','valuation.publish.request',
  'bookings.read','community.moderate','reviews.moderate','referrals.read',
  'referrals.manage','risk.read','risk.resolve.request','support.read','support.manage',
  'grievances.read','grievances.manage','privacy.read','privacy.manage','legal.read',
  'legal.publish.request','audit.read','analytics.read','settings.read','approvals.read'
]) on conflict do nothing;

insert into public.admin_role_permissions(role,permission_key)
select 'super_admin',permission_key from public.admin_role_permissions
where role='admin'
on conflict do nothing;

insert into public.admin_role_permissions(role,permission_key)
select 'super_admin',permission_key from public.admin_permission_catalog
where permission_key = any(array[
  'users.suspend.approve','pricing.publish.approve','valuation.publish.approve',
  'risk.resolve.approve','legal.publish.approve','settings.manage','access.roles.manage'
]) on conflict do nothing;

create or replace function private.admin_can(p_user_id uuid,p_permission_key text)
returns boolean language sql stable security definer
set search_path = pg_catalog,public
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.admin_role_permissions rp on rp.role=ur.role
    where ur.user_id=p_user_id and ur.revoked_at is null
      and rp.permission_key=p_permission_key
  );
$$;
revoke all on function private.admin_can(uuid,text) from public,anon,authenticated;

create or replace function public.admin_has_permission(p_permission_key text)
returns boolean language sql stable security definer
set search_path = pg_catalog,public
as $$
  select auth.uid() is not null
    and p_permission_key ~ '^[a-z0-9_.-]{3,100}$'
    and private.admin_can(auth.uid(),p_permission_key);
$$;
revoke all on function public.admin_has_permission(text) from public,anon;
grant execute on function public.admin_has_permission(text) to authenticated;

create or replace function public.admin_my_permissions()
returns text[] language sql stable security definer
set search_path = pg_catalog,public
as $$
  select coalesce(array_agg(distinct rp.permission_key order by rp.permission_key),'{}'::text[])
  from public.user_roles ur
  join public.admin_role_permissions rp on rp.role=ur.role
  where ur.user_id=auth.uid() and ur.revoked_at is null;
$$;
revoke all on function public.admin_my_permissions() from public,anon;
grant execute on function public.admin_my_permissions() to authenticated;

create or replace function public.admin_request_approval(
  p_action_key text,p_target_id text,p_request_payload jsonb,p_reason text,p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare
  v_actor uuid:=auth.uid();
  v_request_permission text;
  v_target_table text;
  v_id uuid;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception 'Step-up MFA AAL2 required'; end if;
  if length(btrim(coalesce(p_reason,'')))<30 or length(btrim(coalesce(p_reason,'')))>2000 then
    raise exception 'A reason of 30 to 2000 characters is required';
  end if;
  if p_request_payload is null or jsonb_typeof(p_request_payload)<>'object'
    or length(p_request_payload::text)>8192 then raise exception 'Invalid approval payload'; end if;
  if p_idempotency_key !~ '^[A-Za-z0-9:_-]{20,120}$' then raise exception 'Invalid idempotency key'; end if;

  case p_action_key
    when 'refund.execute' then v_request_permission:='refunds.execute.request'; v_target_table:='refunds';
    when 'payout.execute' then v_request_permission:='payouts.execute.request'; v_target_table:='payouts';
    when 'deposit.release' then v_request_permission:='deposits.release.request'; v_target_table:='deposit_release_requests';
    when 'dispute.finalize' then v_request_permission:='disputes.finalize.request'; v_target_table:='disputes';
    when 'pricing.publish' then v_request_permission:='pricing.publish.request'; v_target_table:='pricing_configuration';
    when 'valuation.publish' then v_request_permission:='valuation.publish.request'; v_target_table:='book_valuation_rules';
    when 'legal.publish' then v_request_permission:='legal.publish.request'; v_target_table:='legal_documents';
    when 'risk.resolve' then v_request_permission:='risk.resolve.request'; v_target_table:='risk_alerts';
    when 'user.suspend' then v_request_permission:='users.suspend.request'; v_target_table:='profiles';
    when 'user.role.grant' then v_request_permission:='access.roles.manage'; v_target_table:='user_roles';
    else raise exception 'Unsupported high-risk action';
  end case;

  if not private.admin_can(v_actor,v_request_permission) then raise exception 'Permission denied'; end if;
  insert into public.admin_approval_requests(
    action_key,target_table,target_id,request_payload,reason,requested_by,idempotency_key
  ) values (
    p_action_key,v_target_table,left(coalesce(p_target_id,''),100),p_request_payload,
    left(p_reason,2000),v_actor,p_idempotency_key
  ) returning id into v_id;

  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,
    outcome,reason,request_id,metadata)
  values(v_actor,'approval_requested','approvals',v_request_permission,v_target_table,left(coalesce(p_target_id,''),100),
    'success',left(p_reason,500),p_idempotency_key,jsonb_build_object('approval_id',v_id,'action_key',p_action_key));
  return v_id;
end;
$$;
revoke all on function public.admin_request_approval(text,text,jsonb,text,text) from public,anon;
grant execute on function public.admin_request_approval(text,text,jsonb,text,text) to authenticated;

create or replace function public.admin_decide_approval(
  p_request_id uuid,p_decision text,p_reason text
) returns void language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare
  v_actor uuid:=auth.uid();
  v_request public.admin_approval_requests%rowtype;
  v_permission text;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception 'Step-up MFA AAL2 required'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'Invalid approval decision'; end if;
  if length(btrim(coalesce(p_reason,'')))<30 or length(btrim(coalesce(p_reason,'')))>2000 then
    raise exception 'A reason of 30 to 2000 characters is required';
  end if;
  select * into v_request from public.admin_approval_requests
    where id=p_request_id for update;
  if not found or v_request.status<>'pending' then raise exception 'Approval request is not pending'; end if;
  if v_request.expires_at<=now() then
    update public.admin_approval_requests set status='expired',decided_at=now()
    where id=p_request_id;
    insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,
      outcome,reason,request_id,metadata)
    values(v_actor,'approval_expired','approvals','approvals.read',v_request.target_table,v_request.target_id,
      'failed','Approval request expired',p_request_id::text,
      jsonb_build_object('approval_id',p_request_id,'maker_id',v_request.requested_by));
    return;
  end if;
  if v_request.requested_by=v_actor then raise exception 'Maker cannot approve their own request'; end if;

  v_permission:=case v_request.action_key
    when 'refund.execute' then 'refunds.execute.approve'
    when 'payout.execute' then 'payouts.execute.approve'
    when 'deposit.release' then 'deposits.release.approve'
    when 'dispute.finalize' then 'disputes.finalize.approve'
    when 'pricing.publish' then 'pricing.publish.approve'
    when 'valuation.publish' then 'valuation.publish.approve'
    when 'legal.publish' then 'legal.publish.approve'
    when 'risk.resolve' then 'risk.resolve.approve'
    when 'user.suspend' then 'users.suspend.approve'
    when 'user.role.grant' then 'access.roles.manage'
    else null end;
  if v_permission is null or not private.admin_can(v_actor,v_permission) then
    raise exception 'Approval permission denied';
  end if;

  update public.admin_approval_requests set status=p_decision,approved_by=v_actor,
    decision_reason=left(p_reason,2000),decided_at=now()
  where id=p_request_id;

  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,
    outcome,reason,request_id,metadata)
  values(v_actor,'approval_'||p_decision,'approvals',v_permission,v_request.target_table,v_request.target_id,
    'success',left(p_reason,500),p_request_id::text,
    jsonb_build_object('approval_id',p_request_id,'maker_id',v_request.requested_by,'action_key',v_request.action_key));
end;
$$;
revoke all on function public.admin_decide_approval(uuid,text,text) from public,anon;
grant execute on function public.admin_decide_approval(uuid,text,text) to authenticated;

create or replace function public.admin_assign_staff_role(
  p_user_id uuid,p_role text,p_reason text
) returns uuid language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid(); v_id uuid;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'access.roles.manage')
    or not private.has_role('super_admin') then raise exception 'Super-admin role-management permission required'; end if;
  if p_user_id=v_actor then raise exception 'Self-assignment is prohibited'; end if;
  if p_role not in ('support_agent','verification_reviewer','finance_operator','moderator','admin') then
    raise exception 'Role cannot be granted through the portal'; end if;
  if length(btrim(coalesce(p_reason,'')))<30 then raise exception 'A reason of at least 30 characters is required'; end if;
  if not exists(select 1 from auth.users where id=p_user_id) then raise exception 'Staff account not found'; end if;
  if exists(select 1 from public.user_roles where user_id=p_user_id and role=p_role and revoked_at is null) then
    raise exception 'Staff role is already active'; end if;
  insert into public.user_roles(user_id,role,granted_by,reason)
  values(p_user_id,p_role,v_actor,left(p_reason,2000)) returning id into v_id;
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,
    outcome,reason,request_id,metadata)
  values(v_actor,'staff_role_granted','access','access.roles.manage','user_roles',v_id::text,
    'success',left(p_reason,500),gen_random_uuid()::text,jsonb_build_object('user_id',p_user_id,'role',p_role));
  insert into public.admin_audit_logs(actor_id,action,target_table,target_id,reason,after_data)
  values(v_actor,'staff_role_granted','user_roles',v_id::text,left(p_reason,1000),
    jsonb_build_object('user_id',p_user_id,'role',p_role));
  return v_id;
end;
$$;
revoke all on function public.admin_assign_staff_role(uuid,text,text) from public,anon;
grant execute on function public.admin_assign_staff_role(uuid,text,text) to authenticated;

create or replace function public.admin_revoke_staff_role(
  p_user_id uuid,p_role text,p_reason text
) returns void language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid(); v_id uuid;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'access.roles.manage')
    or not private.has_role('super_admin') then raise exception 'Super-admin role-management permission required'; end if;
  if p_user_id=v_actor then raise exception 'Self-revocation is prohibited'; end if;
  if p_role not in ('support_agent','verification_reviewer','finance_operator','moderator','admin') then
    raise exception 'Role cannot be revoked through the portal'; end if;
  if length(btrim(coalesce(p_reason,'')))<30 then raise exception 'A reason of at least 30 characters is required'; end if;
  update public.user_roles set revoked_at=now()
  where user_id=p_user_id and role=p_role and revoked_at is null returning id into v_id;
  if v_id is null then raise exception 'Active staff role not found'; end if;
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,
    outcome,reason,request_id,metadata)
  values(v_actor,'staff_role_revoked','access','access.roles.manage','user_roles',v_id::text,
    'success',left(p_reason,500),gen_random_uuid()::text,jsonb_build_object('user_id',p_user_id,'role',p_role));
  insert into public.admin_audit_logs(actor_id,action,target_table,target_id,reason,before_data,after_data)
  values(v_actor,'staff_role_revoked','user_roles',v_id::text,left(p_reason,1000),
    jsonb_build_object('role',p_role,'user_id',p_user_id),jsonb_build_object('revoked_at',now()));
end;
$$;
revoke all on function public.admin_revoke_staff_role(uuid,text,text) from public,anon;
grant execute on function public.admin_revoke_staff_role(uuid,text,text) to authenticated;

create or replace function public.admin_review_identity_document(
  p_document_id uuid,p_decision text,p_reason_code text,p_reason text
) returns void language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare
  v_actor uuid:=auth.uid();
  v_doc public.identity_documents%rowtype;
  v_old_status public.document_review_status;
  v_new_status public.document_review_status;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'verification.decide')
    or not private.has_role('verification_reviewer') then raise exception 'Verification reviewer permission required'; end if;
  if p_decision not in ('accepted','rejected','under_review') or length(btrim(coalesce(p_reason_code,'')))<3
    or length(btrim(coalesce(p_reason,'')))<20 then raise exception 'A documented verification decision is required'; end if;
  select * into v_doc from public.identity_documents where id=p_document_id for update;
  if not found or v_doc.user_id<>v_doc.verification_user_id then raise exception 'Identity document not found'; end if;
  v_old_status:=v_doc.status;
  v_new_status:=p_decision::public.document_review_status;
  update public.identity_documents set status=v_new_status,reviewed_by=v_actor,reviewed_at=now(),
    rejection_reason_code=case when v_new_status='rejected' then left(p_reason_code,100) else null end
  where id=p_document_id;

  if v_new_status='accepted' then
    update public.user_verifications set identity_verified_at=coalesce(identity_verified_at,now()),
      status=case when status='not_submitted' then 'under_review'::public.verification_status else status end
    where user_id=v_doc.user_id;
  elsif v_new_status='rejected' then
    update public.user_verifications set status='needs_resubmission',
      rejection_reason_code=left(p_reason_code,100),reviewed_by=v_actor,reviewed_at=now()
    where user_id=v_doc.user_id;
  end if;

  insert into public.verification_audit(user_id,actor_user_id,action,reason_code,metadata)
  values(v_doc.user_id,v_actor,'identity_document_'||p_decision,left(p_reason_code,100),
    jsonb_build_object('document_id',p_document_id,'reason',left(p_reason,200)));
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,
    outcome,reason,request_id,metadata)
  values(v_actor,'identity_document_'||p_decision,'verification','verification.decide',
    'identity_documents',p_document_id::text,'success',left(p_reason,500),gen_random_uuid()::text,
    jsonb_build_object('user_id',v_doc.user_id,'from_status',v_old_status,'to_status',v_new_status));
end;
$$;
revoke all on function public.admin_review_identity_document(uuid,text,text,text) from public,anon;
grant execute on function public.admin_review_identity_document(uuid,text,text,text) to authenticated;

create or replace function public.admin_finalize_verification(
  p_user_id uuid,p_status text,p_reason_code text,p_reason text
) returns void language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid(); v_verification public.user_verifications%rowtype;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'verification.decide')
    or not private.has_role('verification_reviewer') then raise exception 'Verification reviewer permission required'; end if;
  if p_status not in ('verified','rejected','needs_resubmission')
    or length(btrim(coalesce(p_reason_code,'')))<3
    or length(btrim(coalesce(p_reason,'')))<20 then raise exception 'A reasoned verification decision is required'; end if;
  select * into v_verification from public.user_verifications where user_id=p_user_id for update;
  if not found then raise exception 'Verification request not found'; end if;
  if p_status='verified' and (
    v_verification.age_eligible is not true or v_verification.phone_verified_at is null
    or v_verification.identity_verified_at is null
  ) then raise exception 'Phone, age and identity checks must be complete before verification'; end if;
  update public.user_verifications set status=p_status::public.verification_status,
    reviewed_by=v_actor,reviewed_at=now(),
    rejection_reason_code=case when p_status='verified' then null else left(p_reason_code,100) end
  where user_id=p_user_id;
  insert into public.verification_audit(user_id,actor_user_id,action,from_status,to_status,reason_code,metadata)
  values(p_user_id,v_actor,'verification_'||p_status,v_verification.status,p_status::public.verification_status,
    left(p_reason_code,100),jsonb_build_object('reason',left(p_reason,200)));
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,
    outcome,reason,request_id,metadata)
  values(v_actor,'verification_'||p_status,'verification','verification.decide',
    'user_verifications',p_user_id::text,'success',left(p_reason,500),gen_random_uuid()::text,
    jsonb_build_object('from_status',v_verification.status,'to_status',p_status));
end;
$$;
revoke all on function public.admin_finalize_verification(uuid,text,text,text) from public,anon;
grant execute on function public.admin_finalize_verification(uuid,text,text,text) to authenticated;

-- The portal reads through a backend service after a per-module permission check.
-- No new public table grants or broad admin RLS policies are introduced.
alter table public.admin_permission_catalog enable row level security;
alter table public.admin_role_permissions enable row level security;
alter table public.admin_activity_events enable row level security;
alter table public.admin_approval_requests enable row level security;
alter table public.book_valuation_rules enable row level security;
alter table public.admin_referral_campaigns enable row level security;

revoke all on public.admin_permission_catalog,public.admin_role_permissions,
  public.admin_activity_events,public.admin_approval_requests,
  public.book_valuation_rules,public.admin_referral_campaigns
from anon,authenticated;

create or replace function private.reject_admin_activity_mutation()
returns trigger language plpgsql set search_path=pg_catalog
as $$ begin raise exception 'Admin activity history is append-only'; end; $$;
create trigger admin_activity_events_append_only
before update or delete on public.admin_activity_events
for each row execute function private.reject_admin_activity_mutation();

commit;

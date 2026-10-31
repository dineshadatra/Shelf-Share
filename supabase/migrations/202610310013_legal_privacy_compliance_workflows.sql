begin;

create extension if not exists pgcrypto with schema extensions;

-- Versioned policy text is stored with its hash. Published content is immutable.
alter table public.legal_documents
  add column if not exists content_markdown text,
  add column if not exists counsel_reviewed_by uuid references auth.users(id) on delete restrict,
  add column if not exists counsel_reviewer_name text,
  add column if not exists review_status text not null default 'draft',
  add column if not exists created_by uuid references auth.users(id) on delete restrict,
  add column if not exists updated_by uuid references auth.users(id) on delete restrict,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists approved_by uuid references auth.users(id) on delete restrict,
  add column if not exists approved_at timestamptz,
  add column if not exists published_at timestamptz,
  add column if not exists requires_acceptance boolean not null default true,
  add column if not exists reacceptance_required boolean not null default true,
  add column if not exists supersedes_document_id uuid references public.legal_documents(id) on delete restrict,
  add column if not exists review_notes text,
  add column if not exists counsel_reviewed_at timestamptz,
  add column if not exists counsel_review_reference text;


create table if not exists public.legal_document_revisions (
  id uuid primary key default gen_random_uuid(),
  legal_document_id uuid not null references public.legal_documents(id) on delete restrict,
  revision_number integer not null check (revision_number>0),
  content_markdown text not null,
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}
alter table public.legal_documents drop constraint if exists legal_documents_review_status_check;
alter table public.legal_documents add constraint legal_documents_review_status_check
  check (review_status in ('draft','in_review','approved','published','retired'));
alter table public.legal_documents add constraint legal_documents_content_size_check
  check (content_markdown is null or octet_length(content_markdown)<=150000);
alter table public.legal_documents add constraint legal_documents_published_fields_check
  check (not is_published or (content_markdown is not null and effective_from is not null
    and published_at is not null and review_status in ('published','retired')));
create index if not exists legal_documents_current_idx
  on public.legal_documents(document_type,effective_from desc)
  where is_published;

alter table public.legal_acceptances
  add column if not exists document_sha256 text,
  add column if not exists acceptance_source text not null default 'web',
  add column if not exists consent_notice_version text;
update public.legal_acceptances a
set document_sha256=d.sha256
from public.legal_documents d
where d.id=a.legal_document_id and a.document_sha256 is null;
alter table public.legal_acceptances alter column document_sha256 set not null;
alter table public.legal_acceptances add constraint legal_acceptances_hash_check
  check (document_sha256 ~ '^[a-f0-9]{64}$');

alter table public.privacy_requests
  drop constraint if exists privacy_requests_request_type_check;
alter table public.privacy_requests
  drop constraint if exists privacy_requests_status_check;
alter table public.privacy_requests add constraint privacy_requests_status_check
  check (status in ('received','identity_check','in_progress','awaiting_user','fulfilled','partially_fulfilled','rejected','closed'));
alter table public.privacy_requests add constraint privacy_requests_request_type_check
  check (request_type in ('access','correction','erasure','portability','withdraw_consent','restriction','grievance'));
alter table public.privacy_requests
  add column if not exists request_reference text,
  add column if not exists assigned_to uuid references auth.users(id) on delete restrict,
  add column if not exists identity_verified_at timestamptz,
  add column if not exists resolution_summary text,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists data_scope jsonb not null default '{}'::jsonb,
  add column if not exists acknowledgement_sent_at timestamptz,
  add column if not exists legal_hold boolean not null default false;
update public.privacy_requests
set request_reference='PR-'||to_char(received_at at time zone 'Asia/Kolkata','YYYYMMDD')||'-'||upper(substr(id::text,1,8))
where request_reference is null;
alter table public.privacy_requests alter column request_reference set not null;
create unique index if not exists privacy_requests_reference_uq on public.privacy_requests(request_reference);
alter table public.privacy_requests add constraint privacy_requests_scope_object_check
  check (jsonb_typeof(data_scope)='object' and octet_length(data_scope::text)<=4000);

create table if not exists public.privacy_request_events (
  id bigint generated always as identity primary key,
  privacy_request_id uuid not null references public.privacy_requests(id) on delete restrict,
  actor_id uuid references auth.users(id) on delete restrict,
  event_type text not null check (event_type in (
    'submitted','identity_verified','assigned','status_changed','information_requested',
    'information_received','consent_withdrawn','erasure_approved','erasure_started',
    'erasure_completed','partially_fulfilled','fulfilled','rejected','note_added'
  )),
  old_status text,
  new_status text,
  public_message text,
  internal_reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (octet_length(metadata::text)<=4000)
);
create index if not exists privacy_request_events_request_idx
  on public.privacy_request_events(privacy_request_id,created_at);

-- Append-only consent evidence. Operational consent is purpose-specific; essential
-- service processing is not incorrectly represented as optional consent.
create table if not exists public.privacy_consent_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete restrict,
  purpose_key text not null check (purpose_key in (
    'service_sms','marketing_communications','product_analytics','personalised_recommendations',
    'nonessential_cookies','referral_invitations'
  )),
  action text not null check (action in ('granted','withdrawn')),
  notice_version text not null check (length(btrim(notice_version)) between 1 and 40),
  source text not null check (source in ('web','ios','android','support','admin_correction')),
  recorded_at timestamptz not null default now(),
  actor_id uuid references auth.users(id) on delete restrict
);
create index if not exists privacy_consent_user_purpose_idx
  on public.privacy_consent_events(user_id,purpose_key,recorded_at desc);

create table if not exists public.privacy_breach_incidents (
  id uuid primary key default gen_random_uuid(),
  incident_reference text not null unique,
  detected_at timestamptz not null,
  occurred_from timestamptz,
  occurred_to timestamptz,
  severity text not null check (severity in ('low','medium','high','critical')),
  status text not null default 'detected'
    check (status in ('detected','triage','contained','investigating','notified','remediating','closed')),
  data_categories text[] not null default '{}',
  estimated_affected_subjects integer check (estimated_affected_subjects is null or estimated_affected_subjects>=0),
  systems_affected text[] not null default '{}',
  factual_summary text not null check (length(btrim(factual_summary)) between 20 and 8000),
  containment_actions text,
  risk_assessment text,
  notification_assessment text,
  authority_notification_reference text,
  affected_user_notification_at timestamptz,
  authority_notification_at timestamptz,
  root_cause text,
  remediation text,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete restrict,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists privacy_breach_status_idx
  on public.privacy_breach_incidents(status,severity,detected_at desc);

create table if not exists public.data_retention_policies (
  id uuid primary key default gen_random_uuid(),
  rule_key text not null,
  version text not null,
  data_class text not null check (data_class in (
    'identity_documents','verification_metadata','account_profile','booking_contracts',
    'payment_ledger','tax_records','handover_evidence','support_cases','grievance_records',
    'community_content','security_logs','consent_records','legal_acceptance_records',
    'breach_incident_records','marketing_analytics'
  )),
  retention_days integer,
  rationale text not null check (length(btrim(rationale)) between 20 and 2000),
  legal_basis_note text not null check (length(btrim(legal_basis_note)) between 10 and 2000),
  status text not null default 'draft'
    check (status in ('draft','pending_approval','active','paused','retired')),
  created_by uuid not null references auth.users(id) on delete restrict,
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  effective_from timestamptz,
  effective_until timestamptz,
  created_at timestamptz not null default now(),
  unique(rule_key,version),
  check (retention_days is null or retention_days between 1 and 36500),
  check (approved_by is null or approved_by<>created_by),
  check (status not in ('active','paused') or
    (retention_days is not null and approved_by is not null and approved_at is not null and effective_from is not null)),
  check (effective_until is null or effective_from is null or effective_until>effective_from)
);
create index if not exists data_retention_active_idx
  on public.data_retention_policies(data_class,effective_from desc)
  where status='active';

create table if not exists public.data_retention_runs (
  id uuid primary key default gen_random_uuid(),
  policy_id uuid not null references public.data_retention_policies(id) on delete restrict,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  evaluated_count integer not null default 0,
  queued_count integer not null default 0,
  skipped_legal_hold_count integer not null default 0,
  status text not null default 'review_only' check (status in ('review_only','completed','failed')),
  details jsonb not null default '{}'::jsonb,
  initiated_by uuid references auth.users(id) on delete restrict
);

create table if not exists public.privacy_legal_holds (
  id uuid primary key default gen_random_uuid(),
  subject_user_id uuid not null references auth.users(id) on delete restrict,
  data_class text not null,
  reason text not null check (length(btrim(reason)) between 20 and 2000),
  source_reference text,
  created_by uuid not null references auth.users(id) on delete restrict,
  released_by uuid references auth.users(id) on delete restrict,
  released_at timestamptz,
  created_at timestamptz not null default now(),
  check ((released_at is null and released_by is null) or (released_at is not null and released_by is not null))
);
create index if not exists privacy_legal_holds_subject_active_idx
  on public.privacy_legal_holds(subject_user_id,data_class) where released_at is null;

create table if not exists public.sensitive_data_access_events (
  id bigint generated always as identity primary key,
  actor_id uuid not null references auth.users(id) on delete restrict,
  subject_user_id uuid references auth.users(id) on delete restrict,
  data_class text not null check (data_class in (
    'identity_document','identity_verification','privacy_request','privacy_consent',
    'financial_personal_data','support_private_note','breach_incident','legal_document_draft'
  )),
  resource_table text not null,
  resource_id text not null,
  purpose text not null check (length(btrim(purpose)) between 10 and 1000),
  outcome text not null check (outcome in ('success','denied','failed')),
  request_id text not null,
  metadata jsonb not null default '{}'::jsonb,
  accessed_at timestamptz not null default now(),
  check (octet_length(metadata::text)<=2000)
);
create index if not exists sensitive_data_actor_idx
  on public.sensitive_data_access_events(actor_id,accessed_at desc);
create index if not exists sensitive_data_subject_idx
  on public.sensitive_data_access_events(subject_user_id,accessed_at desc);
create index if not exists sensitive_data_resource_idx
  on public.sensitive_data_access_events(resource_table,resource_id,accessed_at desc);

alter table public.identity_documents
  add column if not exists object_deleted_at timestamptz;

create table if not exists public.privacy_erasure_jobs (
  id uuid primary key default gen_random_uuid(),
  privacy_request_id uuid not null references public.privacy_requests(id) on delete restrict,
  subject_user_id uuid not null references auth.users(id) on delete restrict,
  job_type text not null check (job_type in ('identity_document_delete','profile_anonymise')),
  identity_document_id uuid references public.identity_documents(id) on delete restrict,
  storage_bucket text,
  object_key text,
  status text not null default 'pending'
    check (status in ('pending','processing','completed','blocked','failed')),
  attempts integer not null default 0 check (attempts between 0 and 20),
  last_error_code text,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  unique(privacy_request_id,job_type,identity_document_id),
  check ((job_type='identity_document_delete' and identity_document_id is not null
            and storage_bucket='identity-private' and object_key is not null)
      or (job_type='profile_anonymise' and identity_document_id is null
            and storage_bucket is null and object_key is null))
);
create index if not exists privacy_erasure_jobs_pending_idx
  on public.privacy_erasure_jobs(status,created_at) where status in ('pending','failed');
create unique index if not exists privacy_erasure_profile_job_uq
  on public.privacy_erasure_jobs(privacy_request_id) where job_type='profile_anonymise';

create table if not exists public.privacy_erasure_job_events (
  id bigint generated always as identity primary key,
  job_id uuid not null references public.privacy_erasure_jobs(id) on delete restrict,
  event_type text not null,
  error_code text,
  created_at timestamptz not null default now()
);

-- New fine-grained permissions: only authorised legal/privacy staff receive them.
insert into public.admin_permission_catalog(permission_key,module_key,description,sensitivity) values
('legal.draft.write','legal','Create and revise unpublished legal document drafts','high_risk'),
('privacy.incidents.read','privacy','Read security and privacy incident records','identity'),
('privacy.incidents.manage','privacy','Create and update security/privacy incident records','high_risk'),
('privacy.retention.read','privacy','Read approved data retention rules','identity'),
('privacy.retention.manage','privacy','Create and revise draft retention rules','high_risk'),
('privacy.retention.approve','privacy','Approve retention rules through maker-checker controls','high_risk'),
('privacy.accesslog.read','privacy','Read sensitive-data access logs','identity'),
('privacy.erase.request','privacy','Request a controlled erasure action','high_risk'),
('privacy.erase.approve','privacy','Approve controlled erasure actions','high_risk')
on conflict(permission_key) do update set description=excluded.description,sensitivity=excluded.sensitivity;

insert into public.admin_role_permissions(role,permission_key)
select 'admin',permission_key from public.admin_permission_catalog
where permission_key in ('legal.draft.write','privacy.erase.request','privacy.incidents.read','privacy.retention.read')
on conflict do nothing;

insert into public.admin_role_permissions(role,permission_key)
select 'super_admin',permission_key from public.admin_permission_catalog
where permission_key in (
  'legal.draft.write','privacy.erase.request','privacy.erase.approve',
  'privacy.incidents.read','privacy.incidents.manage','privacy.retention.read',
  'privacy.retention.manage','privacy.retention.approve','privacy.accesslog.read'
)
on conflict do nothing;

-- Extend the existing maker-checker approval catalogue for privacy erasure.
alter table public.admin_approval_requests
  drop constraint if exists admin_approval_requests_action_key_check;
alter table public.admin_approval_requests add constraint admin_approval_requests_action_key_check
  check (action_key in (
    'refund.execute','payout.execute','deposit.release','dispute.finalize',
    'pricing.publish','valuation.publish','legal.publish','risk.resolve',
    'user.suspend','user.role.grant','privacy.erase'
  ));

create or replace function public.admin_request_approval(
  p_action_key text,p_target_id text,p_request_payload jsonb,p_reason text,p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid(); v_request_permission text; v_target_table text; v_id uuid;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
    raise exception 'Authentication and MFA AAL2 required';
  end if;
  if length(btrim(coalesce(p_reason,'')))<30 or length(btrim(p_reason))>2000 then
    raise exception 'Reason must be 30 to 2000 characters';
  end if;
  if p_request_payload is null or jsonb_typeof(p_request_payload)<>'object' or octet_length(p_request_payload::text)>8192 then
    raise exception 'Invalid approval payload';
  end if;
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
    when 'privacy.erase' then v_request_permission:='privacy.erase.request'; v_target_table:='privacy_requests';
    else raise exception 'Unsupported high-risk action';
  end case;
  if not private.admin_can(v_actor,v_request_permission) then raise exception 'Permission denied'; end if;
  insert into public.admin_approval_requests(action_key,target_table,target_id,request_payload,reason,requested_by,idempotency_key)
  values(p_action_key,v_target_table,left(p_target_id,100),p_request_payload,left(p_reason,2000),v_actor,p_idempotency_key)
  returning id into v_id;
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,outcome,reason,request_id,metadata)
  values(v_actor,'approval_requested','approvals',v_request_permission,v_target_table,left(p_target_id,100),
    'success',left(p_reason,500),p_idempotency_key,jsonb_build_object('approval_id',v_id,'action_key',p_action_key));
  return v_id;
end;
$$;
revoke all on function public.admin_request_approval(text,text,jsonb,text,text) from public,anon;
grant execute on function public.admin_request_approval(text,text,jsonb,text,text) to authenticated;

create or replace function public.admin_decide_approval(
  p_request_id uuid,p_decision text,p_reason text
) returns void language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid(); v_request public.admin_approval_requests%rowtype; v_permission text;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception 'MFA AAL2 required'; end if;
  if p_decision not in ('approved','rejected') or length(btrim(coalesce(p_reason,''))) not between 30 and 2000 then
    raise exception 'Invalid approval decision or reason';
  end if;
  select * into v_request from public.admin_approval_requests where id=p_request_id for update;
  if not found or v_request.status<>'pending' or v_request.expires_at<=now() then raise exception 'Approval is not pending or expired'; end if;
  if v_request.requested_by=v_actor then raise exception 'Maker cannot approve own request'; end if;
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
    when 'privacy.erase' then 'privacy.erase.approve'
    else null end;
  if v_permission is null or not private.admin_can(v_actor,v_permission) then raise exception 'Approval permission denied'; end if;
  update public.admin_approval_requests set status=p_decision,approved_by=v_actor,decision_reason=left(p_reason,2000),decided_at=now()
  where id=p_request_id;
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,outcome,reason,request_id,metadata)
  values(v_actor,'approval_'||p_decision,'approvals',v_permission,v_request.target_table,v_request.target_id,
    'success',left(p_reason,500),p_request_id::text,jsonb_build_object('approval_id',p_request_id,'maker_id',v_request.requested_by,'action_key',v_request.action_key));
end;
$$;
revoke all on function public.admin_decide_approval(uuid,text,text) from public,anon;
grant execute on function public.admin_decide_approval(uuid,text,text) to authenticated;

-- A draft is immutable after publication and its hash is computed by the database.
create or replace function public.admin_save_legal_draft(
  p_document_id uuid,p_document_type text,p_version text,p_title text,p_content_uri text,
  p_content_markdown text,p_requires_acceptance boolean,p_reacceptance_required boolean,p_review_notes text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,private,extensions
as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_hash text; v_revision integer;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'legal.draft.write') then raise exception 'Legal draft permission and MFA AAL2 required'; end if;
  if p_document_type not in (
    'terms_conditions','privacy_policy','cookie_policy','marketplace_rules','owner_agreement','reader_agreement',
    'rental_agreement','damage_compensation_policy','cancellation_refund_policy','deposit_policy','non_return_policy',
    'community_guidelines','content_copyright_policy','grievance_policy','identity_verification_notice','referral_terms'
  ) then raise exception 'Unsupported legal document type'; end if;
  if p_version !~ '^[0-9]+\.[0-9]+([.-][A-Za-z0-9_-]+)?$'
    or length(btrim(coalesce(p_title,''))) not between 3 and 160
    or length(coalesce(p_content_markdown,'')) not between 100 and 150000
    or p_content_uri !~ '^docs/legal-drafts/[A-Za-z0-9._/-]+$' then
    raise exception 'Invalid draft metadata or content';
  end if;
  v_hash:=encode(extensions.digest(convert_to(p_content_markdown,'UTF8'),'sha256'),'hex');
  if p_document_id is null then
    insert into public.legal_documents(document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
      content_markdown,review_status,created_by,updated_by,requires_acceptance,reacceptance_required,review_notes)
    values(p_document_type,p_version,p_title,p_content_uri,v_hash,null,null,false,p_content_markdown,'draft',
      v_actor,v_actor,coalesce(p_requires_acceptance,true),coalesce(p_reacceptance_required,true),left(p_review_notes,4000))
    returning id into v_id;
  else
    update public.legal_documents set title=p_title,content_uri=p_content_uri,sha256=v_hash,
      content_markdown=p_content_markdown,review_status='draft',updated_by=v_actor,updated_at=now(),
      requires_acceptance=coalesce(p_requires_acceptance,true),reacceptance_required=coalesce(p_reacceptance_required,true),
      review_notes=left(p_review_notes,4000)
    where id=p_document_id and not is_published and review_status in ('draft','in_review')
      and document_type=p_document_type and version=p_version
    returning id into v_id;
    if v_id is null then raise exception 'Draft not found, immutable or version mismatch'; end if;
  end if;
  select coalesce(max(revision_number),0)+1 into v_revision
    from public.legal_document_revisions where legal_document_id=v_id;
  insert into public.legal_document_revisions(legal_document_id,revision_number,content_markdown,sha256,changed_by,change_note)
  values(v_id,v_revision,p_content_markdown,v_hash,v_actor,left(coalesce(p_review_notes,'Draft saved'),2000));
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,outcome,reason,request_id,metadata)
  values(v_actor,'legal_draft_saved','legal','legal.draft.write','legal_documents',v_id::text,'success',
    left(coalesce(p_review_notes,'Draft saved'),500),gen_random_uuid()::text,jsonb_build_object('version',p_version,'revision',v_revision,'sha256',v_hash));
  return v_id;
end;
$$;
revoke all on function public.admin_save_legal_draft(uuid,text,text,text,text,text,boolean,boolean,text) from public,anon;
grant execute on function public.admin_save_legal_draft(uuid,text,text,text,text,text,boolean,boolean,text) to authenticated;

create or replace function public.admin_submit_legal_draft(p_document_id uuid,p_review_notes text)
returns void language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid();
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'legal.draft.write') then raise exception 'Legal draft permission and MFA required'; end if;
  update public.legal_documents set review_status='in_review',review_notes=left(p_review_notes,4000),
    updated_by=v_actor,updated_at=now()
  where id=p_document_id and not is_published and review_status='draft' and content_markdown is not null;
  if not found then raise exception 'Draft not found or not ready for review'; end if;
end;
$$;
revoke all on function public.admin_submit_legal_draft(uuid,text) from public,anon;
grant execute on function public.admin_submit_legal_draft(uuid,text) to authenticated;


create or replace function public.admin_record_legal_counsel_review(
  p_document_id uuid,p_counsel_name text,p_review_reference text,p_reviewed_at timestamptz,p_reason text
) returns void language plpgsql security definer
set search_path=pg_catalog,public,private
as $
declare v_actor uuid:=auth.uid();
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'legal.publish.request') then
    raise exception 'Legal review recording permission and MFA AAL2 required';
  end if;
  if length(btrim(coalesce(p_counsel_name,''))) not between 3 and 160
    or length(btrim(coalesce(p_review_reference,''))) not between 3 and 200
    or p_reviewed_at is null or p_reviewed_at>now()
    or length(btrim(coalesce(p_reason,''))) not between 20 and 2000 then
    raise exception 'Counsel review name, reference, valid date and reason are required';
  end if;
  update public.legal_documents set
    counsel_reviewed_by=v_actor,counsel_reviewer_name=left(p_counsel_name,160),
    counsel_review_reference=left(p_review_reference,200),counsel_reviewed_at=p_reviewed_at,
    updated_by=v_actor,updated_at=now()
  where id=p_document_id and review_status='in_review' and not is_published;
  if not found then raise exception 'Legal document must be in review before counsel review can be recorded'; end if;
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,
    outcome,reason,request_id,metadata)
  values(v_actor,'legal_counsel_review_recorded','legal','legal.publish.request','legal_documents',p_document_id::text,
    'success',left(p_reason,500),gen_random_uuid()::text,
    jsonb_build_object('counsel_name',left(p_counsel_name,160),'review_reference',left(p_review_reference,200),'reviewed_at',p_reviewed_at));
end;
$;
revoke all on function public.admin_record_legal_counsel_review(uuid,text,text,timestamptz,text) from public,anon;
grant execute on function public.admin_record_legal_counsel_review(uuid,text,text,timestamptz,text) to authenticated;

create or replace function public.admin_publish_legal_document(
  p_document_id uuid,p_approval_request_id uuid,p_effective_from timestamptz
) returns void language plpgsql security definer
set search_path=pg_catalog,public,private,extensions
as $$
declare v_actor uuid:=auth.uid(); v_doc public.legal_documents%rowtype; v_approval public.admin_approval_requests%rowtype;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'legal.publish.approve') then raise exception 'Legal publication approval and MFA required'; end if;
  select * into v_doc from public.legal_documents where id=p_document_id for update;
  select * into v_approval from public.admin_approval_requests where id=p_approval_request_id for update;
  if not found or v_doc.id is null or v_approval.id is null or v_approval.action_key<>'legal.publish'
    or v_approval.target_id<>p_document_id::text or v_approval.status<>'approved'
    or v_approval.requested_by=v_approval.approved_by then
    raise exception 'A separate, approved legal publication request is required';
  end if;
  if v_doc.is_published or v_doc.review_status<>'in_review' or v_doc.content_markdown is null
    or v_doc.counsel_reviewed_at is null or v_doc.counsel_reviewed_by is null
    or v_doc.counsel_reviewer_name is null or v_doc.counsel_review_reference is null
    or v_doc.sha256<>encode(extensions.digest(convert_to(v_doc.content_markdown,'UTF8'),'sha256'),'hex')
    or p_effective_from is null or p_effective_from<now() then
    raise exception 'Document is not publishable or its content hash is invalid';
  end if;
  update public.legal_documents set effective_until=p_effective_from
  where document_type=v_doc.document_type and is_published and effective_until is null;
  update public.legal_documents set is_published=true,review_status='published',
    effective_from=p_effective_from,published_at=now(),approved_by=v_approval.approved_by,
    approved_at=v_approval.decided_at,updated_by=v_actor,updated_at=now()
  where id=p_document_id;
  update public.admin_approval_requests set status='executed',executed_at=now() where id=p_approval_request_id;
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,outcome,request_id,metadata)
  values(v_actor,'legal_document_published','legal','legal.publish.approve','legal_documents',p_document_id::text,
    'success',p_approval_request_id::text,jsonb_build_object('version',v_doc.version,'sha256',v_doc.sha256,'effective_from',p_effective_from));
end;
$$;
revoke all on function public.admin_publish_legal_document(uuid,uuid,timestamptz) from public,anon;
grant execute on function public.admin_publish_legal_document(uuid,uuid,timestamptz) to authenticated;

create or replace function public.record_legal_acceptance(
  p_legal_document_id uuid,p_document_sha256 text,p_acceptance_context text,p_source text,
  p_ip_hash text default null,p_user_agent_hash text default null
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_actor uuid:=auth.uid(); v_doc public.legal_documents%rowtype; v_id uuid;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  select * into v_doc from public.legal_documents where id=p_legal_document_id and is_published
    and effective_from<=now() and (effective_until is null or effective_until>now());
  if not found or v_doc.sha256<>p_document_sha256 or not v_doc.requires_acceptance then
    raise exception 'Document is unavailable or hash mismatch';
  end if;
  if length(btrim(coalesce(p_acceptance_context,''))) not between 2 and 60
    or p_source not in ('web','ios','android') then raise exception 'Invalid acceptance context'; end if;
  insert into public.legal_acceptances(user_id,legal_document_id,accepted_at,acceptance_context,
    ip_hash,user_agent_hash,document_sha256,acceptance_source,consent_notice_version)
  values(v_actor,p_legal_document_id,now(),p_acceptance_context,p_ip_hash,p_user_agent_hash,
    p_document_sha256,p_source,v_doc.version)
  on conflict(user_id,legal_document_id,acceptance_context) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.legal_acceptances
    where user_id=v_actor and legal_document_id=p_legal_document_id and acceptance_context=p_acceptance_context;
  end if;
  return v_id;
end;
$$;
revoke all on function public.record_legal_acceptance(uuid,text,text,text,text,text) from public,anon;
grant execute on function public.record_legal_acceptance(uuid,text,text,text,text,text) to authenticated;

create or replace function public.create_privacy_request(p_request_type text,p_description text)
returns uuid language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_ref text;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if p_request_type not in ('access','correction','erasure','portability','withdraw_consent','restriction','grievance')
    or length(btrim(coalesce(p_description,''))) not between 10 and 5000 then raise exception 'Invalid privacy request'; end if;
  v_ref:='PR-'||to_char(now() at time zone 'Asia/Kolkata','YYYYMMDD')||'-'||upper(substr(gen_random_uuid()::text,1,8));
  insert into public.privacy_requests(requester_id,request_type,description,request_reference,data_scope)
  values(v_actor,p_request_type,left(p_description,5000),v_ref,'{}'::jsonb) returning id into v_id;
  insert into public.privacy_request_events(privacy_request_id,actor_id,event_type,new_status,public_message)
  values(v_id,v_actor,'submitted','received','Your request has been received. We will verify your identity where necessary and provide updates here.');
  return v_id;
end;
$$;
revoke all on function public.create_privacy_request(text,text) from public,anon;
grant execute on function public.create_privacy_request(text,text) to authenticated;

create or replace function public.record_privacy_consent(
  p_purpose_key text,p_action text,p_notice_version text,p_source text
) returns bigint language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_actor uuid:=auth.uid(); v_id bigint;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if p_purpose_key not in ('service_sms','marketing_communications','product_analytics','personalised_recommendations','nonessential_cookies','referral_invitations')
    or p_action not in ('granted','withdrawn') or p_source not in ('web','ios','android')
    or length(btrim(coalesce(p_notice_version,''))) not between 1 and 40 then
    raise exception 'Invalid consent update';
  end if;
  insert into public.privacy_consent_events(user_id,purpose_key,action,notice_version,source,actor_id)
  values(v_actor,p_purpose_key,p_action,p_notice_version,p_source,v_actor) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.record_privacy_consent(text,text,text,text) from public,anon;
grant execute on function public.record_privacy_consent(text,text,text,text) to authenticated;

create or replace function public.admin_update_privacy_request(
  p_request_id uuid,p_status text,p_assigned_to uuid,p_resolution_summary text,p_reason text
) returns void language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid(); v_old public.privacy_requests%rowtype;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'privacy.manage') then raise exception 'Privacy management permission and MFA required'; end if;
  if p_status not in ('received','identity_check','in_progress','awaiting_user','fulfilled','partially_fulfilled','rejected','closed')
    or length(btrim(coalesce(p_reason,'')))<20 then raise exception 'Invalid status or reason'; end if;
  if p_resolution_summary is not null and length(p_resolution_summary)>4000 then raise exception 'Resolution summary too long'; end if;
  select * into v_old from public.privacy_requests where id=p_request_id for update;
  if not found then raise exception 'Privacy request not found'; end if;
  if p_assigned_to is not null and not exists(
    select 1 from public.user_roles where user_id=p_assigned_to and revoked_at is null
      and role in ('admin','super_admin','support_agent')
  ) then raise exception 'Assignee must be active authorised staff'; end if;
  update public.privacy_requests set status=p_status,assigned_to=p_assigned_to,
    resolution_summary=coalesce(left(p_resolution_summary,4000),resolution_summary),
    completed_at=case when p_status in ('fulfilled','partially_fulfilled','rejected','closed') then now() else null end,
    updated_at=now()
  where id=p_request_id;
  insert into public.privacy_request_events(privacy_request_id,actor_id,event_type,old_status,new_status,
    public_message,internal_reason,metadata)
  values(p_request_id,v_actor,'status_changed',v_old.status,p_status,
    case when p_status='fulfilled' then left(coalesce(p_resolution_summary,'Request fulfilled'),1000) else null end,
    left(p_reason,1000),jsonb_build_object('assigned_to',p_assigned_to));
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,outcome,reason,request_id,metadata)
  values(v_actor,'privacy_request_updated','privacy','privacy.manage','privacy_requests',p_request_id::text,
    'success',left(p_reason,500),gen_random_uuid()::text,jsonb_build_object('from_status',v_old.status,'to_status',p_status));
end;
$$;
revoke all on function public.admin_update_privacy_request(uuid,text,uuid,text,text) from public,anon;
grant execute on function public.admin_update_privacy_request(uuid,text,uuid,text,text) to authenticated;

create or replace function public.admin_record_privacy_incident(
  p_incident_reference text,p_detected_at timestamptz,p_severity text,p_data_categories text[],
  p_estimated_subjects integer,p_systems_affected text[],p_factual_summary text,p_containment text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid(); v_id uuid;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'privacy.incidents.manage') then raise exception 'Incident management permission and MFA required'; end if;
  if p_incident_reference !~ '^INC-[A-Z0-9-]{6,40}$' or p_detected_at is null
    or p_severity not in ('low','medium','high','critical')
    or length(btrim(coalesce(p_factual_summary,''))) not between 20 and 8000
    or coalesce(array_length(p_data_categories,1),0)>20
    or coalesce(array_length(p_systems_affected,1),0)>30
    or (p_estimated_subjects is not null and p_estimated_subjects<0) then
    raise exception 'Invalid incident fields';
  end if;
  insert into public.privacy_breach_incidents(incident_reference,detected_at,severity,data_categories,
    estimated_affected_subjects,systems_affected,factual_summary,containment_actions,created_by,updated_by)
  values(p_incident_reference,p_detected_at,p_severity,p_data_categories,p_estimated_subjects,
    p_systems_affected,left(p_factual_summary,8000),left(p_containment,4000),v_actor,v_actor)
  returning id into v_id;
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,outcome,request_id,metadata)
  values(v_actor,'privacy_incident_recorded','privacy','privacy.incidents.manage','privacy_breach_incidents',v_id::text,
    'success',gen_random_uuid()::text,jsonb_build_object('severity',p_severity,'reference',p_incident_reference));
  return v_id;
end;
$$;
revoke all on function public.admin_record_privacy_incident(text,timestamptz,text,text[],integer,text[],text,text) from public,anon;
grant execute on function public.admin_record_privacy_incident(text,timestamptz,text,text[],integer,text[],text,text) to authenticated;

create or replace function public.admin_save_retention_policy(
  p_rule_key text,p_version text,p_data_class text,p_retention_days integer,
  p_rationale text,p_legal_basis_note text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid(); v_id uuid;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'privacy.retention.manage') then raise exception 'Retention management permission and MFA required'; end if;
  if p_retention_days is null or p_retention_days not between 1 and 36500
    or p_version !~ '^[0-9]+\.[0-9]+([.-][A-Za-z0-9_-]+)?$'
    or length(btrim(coalesce(p_rule_key,''))) not between 3 and 80 then raise exception 'Invalid retention rule'; end if;
  insert into public.data_retention_policies(rule_key,version,data_class,retention_days,rationale,legal_basis_note,created_by)
  values(p_rule_key,p_version,p_data_class,p_retention_days,left(p_rationale,2000),left(p_legal_basis_note,2000),v_actor)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.admin_save_retention_policy(text,text,text,integer,text,text) from public,anon;
grant execute on function public.admin_save_retention_policy(text,text,text,integer,text,text) to authenticated;

create or replace function public.admin_approve_retention_policy(p_policy_id uuid,p_effective_from timestamptz,p_reason text)
returns void language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid(); v_policy public.data_retention_policies%rowtype;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'privacy.retention.approve') then raise exception 'Retention approval permission and MFA required'; end if;
  select * into v_policy from public.data_retention_policies where id=p_policy_id for update;
  if not found or v_policy.status<>'draft' or v_policy.created_by=v_actor
    or p_effective_from is null or p_effective_from<now() or length(btrim(coalesce(p_reason,'')))<30 then
    raise exception 'Retention rule cannot be approved';
  end if;
  update public.data_retention_policies set status='active',approved_by=v_actor,approved_at=now(),effective_from=p_effective_from
  where id=p_policy_id;
  update public.data_retention_policies set status='retired',effective_until=p_effective_from
  where rule_key=v_policy.rule_key and status='active' and id<>p_policy_id;
end;
$$;
revoke all on function public.admin_approve_retention_policy(uuid,timestamptz,text) from public,anon;
grant execute on function public.admin_approve_retention_policy(uuid,timestamptz,text) to authenticated;

create or replace function public.admin_queue_privacy_erasure(p_approval_request_id uuid)
returns integer language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare
  v_actor uuid:=auth.uid(); v_approval public.admin_approval_requests%rowtype;
  v_request public.privacy_requests%rowtype; v_count integer:=0;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'privacy.erase.approve') then raise exception 'Erasure approval permission and MFA required'; end if;
  select * into v_approval from public.admin_approval_requests where id=p_approval_request_id for update;
  if not found or v_approval.action_key<>'privacy.erase' or v_approval.status<>'approved'
    or v_approval.requested_by=v_actor then
    raise exception 'Separate approved erasure request required';
  end if;
  select * into v_request from public.privacy_requests
    where id=v_approval.target_id::uuid and request_type='erasure' for update;
  if not found or v_request.status not in ('received','identity_check','in_progress')
    or v_request.identity_verified_at is null then
    raise exception 'Erasure request requires a verified requester and an active case';
  end if;
  if v_request.legal_hold or exists(select 1 from public.privacy_legal_holds where subject_user_id=v_request.requester_id and released_at is null) then
    raise exception 'Erasure is blocked by a legal hold';
  end if;
  if exists(select 1 from public.bookings b where (b.reader_id=v_request.requester_id or b.owner_id=v_request.requester_id)
      and b.status::text not in ('completed','cancelled','expired')) then
    raise exception 'Erasure is blocked by an active rental obligation';
  end if;
  insert into public.privacy_erasure_jobs(privacy_request_id,subject_user_id,job_type,identity_document_id,storage_bucket,object_key)
  select v_request.id,d.user_id,'identity_document_delete',d.id,d.storage_bucket,d.object_key
  from public.identity_documents d
  where d.user_id=v_request.requester_id and d.object_deleted_at is null
  on conflict do nothing;
  get diagnostics v_count=row_count;
  insert into public.privacy_erasure_jobs(privacy_request_id,subject_user_id,job_type)
  values(v_request.id,v_request.requester_id,'profile_anonymise')
  on conflict do nothing;
  update public.privacy_requests set status='in_progress',updated_at=now()
  where id=v_request.id;
  insert into public.privacy_request_events(privacy_request_id,actor_id,event_type,new_status,internal_reason,metadata)
  values(v_request.id,v_actor,'erasure_started','in_progress','Approved identity-file deletion and profile anonymisation jobs queued.',
    jsonb_build_object('identity_documents_queued',v_count,'approval_request_id',p_approval_request_id));
  update public.admin_approval_requests set status='executed',executed_at=now() where id=p_approval_request_id;
  return v_count+1;
end;
$$;
revoke all on function public.admin_queue_privacy_erasure(uuid) from public,anon;
grant execute on function public.admin_queue_privacy_erasure(uuid) to authenticated;

create or replace function public.claim_privacy_erasure_jobs(p_limit integer default 20)
returns setof public.privacy_erasure_jobs language plpgsql security definer
set search_path=pg_catalog,public
as $$
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Service role required'; end if;
  return query
  with picked as (
    select j.id from public.privacy_erasure_jobs j
    join public.privacy_requests r on r.id=j.privacy_request_id
    where j.status in ('pending','failed') and j.attempts<5
      and r.status='in_progress' and not r.legal_hold
      and not exists(select 1 from public.privacy_legal_holds h
        where h.subject_user_id=j.subject_user_id and h.released_at is null)
      and not exists(select 1 from public.bookings b
        where (b.reader_id=j.subject_user_id or b.owner_id=j.subject_user_id)
          and b.status::text not in ('completed','cancelled','expired'))
    order by j.created_at limit greatest(1,least(p_limit,50)) for update of j skip locked
  )
  update public.privacy_erasure_jobs j set status='processing',attempts=attempts+1,started_at=now()
  from picked where j.id=picked.id returning j.*;
end;
$$;
revoke all on function public.claim_privacy_erasure_jobs(integer) from public,anon,authenticated;
grant execute on function public.claim_privacy_erasure_jobs(integer) to service_role;

create or replace function public.complete_privacy_erasure_job(p_job_id uuid,p_success boolean,p_error_code text default null)
returns void language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_job public.privacy_erasure_jobs%rowtype;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Service role required'; end if;
  select * into v_job from public.privacy_erasure_jobs where id=p_job_id for update;
  if not found or v_job.status<>'processing' then raise exception 'Erasure job is not processing'; end if;
  if p_success then
    if v_job.job_type='identity_document_delete' then
      update public.identity_documents set object_key='erased/'||id::text,
        object_deleted_at=now(),document_last4=null,provider_reference=null
      where id=v_job.identity_document_id and user_id=v_job.subject_user_id;
    elsif v_job.job_type='profile_anonymise' then
      update public.profiles set display_name='Deleted user',avatar_object_key=null,bio=null,
        preferred_city_id=null,account_status='suspended',updated_at=now()
      where id=v_job.subject_user_id;
    end if;
    update public.privacy_erasure_jobs set status='completed',completed_at=now(),last_error_code=null where id=p_job_id;
    insert into public.privacy_erasure_job_events(job_id,event_type) values(p_job_id,'completed');
  else
    update public.privacy_erasure_jobs set status=case when attempts>=5 then 'blocked' else 'failed' end,
      last_error_code=left(coalesce(p_error_code,'provider_delete_failed'),100) where id=p_job_id;
    insert into public.privacy_erasure_job_events(job_id,event_type,error_code)
    values(p_job_id,'failed',left(coalesce(p_error_code,'provider_delete_failed'),100));
  end if;
  if not exists(select 1 from public.privacy_erasure_jobs where privacy_request_id=v_job.privacy_request_id and status<>'completed') then
    update public.privacy_requests set status='partially_fulfilled',completed_at=now(),
      resolution_summary='Identity document files deleted and profile metadata anonymised. Account authentication identifiers and transaction/legal records are retained pending separate legal and operational review.',
      updated_at=now()
    where id=v_job.privacy_request_id;
    insert into public.privacy_request_events(privacy_request_id,event_type,new_status,internal_reason)
    values(v_job.privacy_request_id,'partially_fulfilled','partially_fulfilled',
      'Identity files deleted and profile anonymised; remaining account, transaction and statutory records are outside this automated job.');
  end if;
end;
$$;
revoke all on function public.complete_privacy_erasure_job(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.complete_privacy_erasure_job(uuid,boolean,text) to service_role;


create or replace function private.reject_legal_revision_mutation()
returns trigger language plpgsql set search_path=pg_catalog
as $ begin raise exception 'Legal document revision history is append-only'; end; $;
create trigger legal_document_revisions_append_only
before update or delete on public.legal_document_revisions
for each row execute function private.reject_legal_revision_mutation();

-- Append-only histories.
create or replace function private.reject_privacy_history_mutation()
returns trigger language plpgsql set search_path=pg_catalog
as $$ begin raise exception 'Privacy and acceptance histories are append-only'; end; $$;
create trigger privacy_request_events_append_only before update or delete on public.privacy_request_events
for each row execute function private.reject_privacy_history_mutation();
create trigger privacy_consent_events_append_only before update or delete on public.privacy_consent_events
for each row execute function private.reject_privacy_history_mutation();
create trigger sensitive_data_access_append_only before update or delete on public.sensitive_data_access_events
for each row execute function private.reject_privacy_history_mutation();
create trigger privacy_erasure_job_events_append_only before update or delete on public.privacy_erasure_job_events
for each row execute function private.reject_privacy_history_mutation();
create trigger legal_acceptances_append_only before update or delete on public.legal_acceptances
for each row execute function private.reject_privacy_history_mutation();

create or replace function private.guard_published_legal_document()
returns trigger language plpgsql set search_path=pg_catalog
as $$
begin
  if tg_op='UPDATE' and old.is_published then
    if new.document_type is distinct from old.document_type
      or new.version is distinct from old.version or new.title is distinct from old.title
      or new.content_uri is distinct from old.content_uri
      or new.sha256 is distinct from old.sha256
      or new.content_markdown is distinct from old.content_markdown
      or new.effective_from is distinct from old.effective_from then
      raise exception 'Published legal document content is immutable; create a new version';
    end if;
  end if;
  return new;
end;
$$;
create trigger legal_documents_published_immutable
before update on public.legal_documents
for each row execute function private.guard_published_legal_document();

-- Direct access to personal requests and security records is denied; the Edge API
-- performs explicit ownership/permission checks and writes sensitive access logs.
alter table public.privacy_requests enable row level security;
alter table public.privacy_request_events enable row level security;
alter table public.privacy_consent_events enable row level security;
alter table public.privacy_breach_incidents enable row level security;
alter table public.data_retention_policies enable row level security;
alter table public.data_retention_runs enable row level security;
alter table public.privacy_legal_holds enable row level security;
alter table public.sensitive_data_access_events enable row level security;
alter table public.privacy_erasure_jobs enable row level security;
alter table public.privacy_erasure_job_events enable row level security;
alter table public.legal_documents enable row level security;
alter table public.legal_acceptances enable row level security;
alter table public.legal_document_revisions enable row level security;

revoke all on public.legal_documents,public.legal_acceptances from anon,authenticated;
grant select on public.legal_documents to anon,authenticated;
grant select on public.legal_acceptances to authenticated;

revoke all on public.privacy_requests,public.privacy_request_events,public.privacy_consent_events,
  public.privacy_breach_incidents,public.data_retention_policies,public.data_retention_runs,
  public.privacy_legal_holds,public.sensitive_data_access_events,public.privacy_erasure_jobs,
  public.privacy_erasure_job_events,public.legal_document_revisions from anon,authenticated;
grant select on public.privacy_requests,public.privacy_request_events,public.privacy_consent_events,
  public.legal_documents,public.legal_acceptances to authenticated;

create policy privacy_requests_owner_select on public.privacy_requests
  for select to authenticated using (requester_id=auth.uid());
create policy privacy_request_events_owner_select on public.privacy_request_events
  for select to authenticated using (exists(
    select 1 from public.privacy_requests r where r.id=privacy_request_id and r.requester_id=auth.uid()));
create policy privacy_consent_owner_select on public.privacy_consent_events
  for select to authenticated using (user_id=auth.uid());
create policy legal_documents_published_select on public.legal_documents
  for select to anon,authenticated using (is_published=true);
grant select on public.legal_documents to anon;

create policy legal_acceptances_owner_select on public.legal_acceptances
  for select to authenticated using (user_id=auth.uid());

commit;
),
  changed_by uuid not null references auth.users(id) on delete restrict,
  change_note text,
  created_at timestamptz not null default now(),
  unique(legal_document_id,revision_number),
  check (octet_length(content_markdown)<=150000)
);
create index if not exists legal_document_revisions_doc_idx
  on public.legal_document_revisions(legal_document_id,revision_number desc);

alter table public.legal_documents alter column effective_from drop not null;
alter table public.legal_documents drop constraint if exists legal_documents_review_status_check;
alter table public.legal_documents add constraint legal_documents_review_status_check
  check (review_status in ('draft','in_review','approved','published','retired'));
alter table public.legal_documents add constraint legal_documents_content_size_check
  check (content_markdown is null or octet_length(content_markdown)<=150000);
alter table public.legal_documents add constraint legal_documents_published_fields_check
  check (not is_published or (content_markdown is not null and effective_from is not null
    and published_at is not null and review_status in ('published','retired')));
create index if not exists legal_documents_current_idx
  on public.legal_documents(document_type,effective_from desc)
  where is_published;

alter table public.legal_acceptances
  add column if not exists document_sha256 text,
  add column if not exists acceptance_source text not null default 'web',
  add column if not exists consent_notice_version text;
update public.legal_acceptances a
set document_sha256=d.sha256
from public.legal_documents d
where d.id=a.legal_document_id and a.document_sha256 is null;
alter table public.legal_acceptances alter column document_sha256 set not null;
alter table public.legal_acceptances add constraint legal_acceptances_hash_check
  check (document_sha256 ~ '^[a-f0-9]{64}$');

alter table public.privacy_requests
  drop constraint if exists privacy_requests_request_type_check;
alter table public.privacy_requests
  drop constraint if exists privacy_requests_status_check;
alter table public.privacy_requests add constraint privacy_requests_status_check
  check (status in ('received','identity_check','in_progress','awaiting_user','fulfilled','partially_fulfilled','rejected','closed'));
alter table public.privacy_requests add constraint privacy_requests_request_type_check
  check (request_type in ('access','correction','erasure','portability','withdraw_consent','restriction','grievance'));
alter table public.privacy_requests
  add column if not exists request_reference text,
  add column if not exists assigned_to uuid references auth.users(id) on delete restrict,
  add column if not exists identity_verified_at timestamptz,
  add column if not exists resolution_summary text,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists data_scope jsonb not null default '{}'::jsonb,
  add column if not exists acknowledgement_sent_at timestamptz,
  add column if not exists legal_hold boolean not null default false;
update public.privacy_requests
set request_reference='PR-'||to_char(received_at at time zone 'Asia/Kolkata','YYYYMMDD')||'-'||upper(substr(id::text,1,8))
where request_reference is null;
alter table public.privacy_requests alter column request_reference set not null;
create unique index if not exists privacy_requests_reference_uq on public.privacy_requests(request_reference);
alter table public.privacy_requests add constraint privacy_requests_scope_object_check
  check (jsonb_typeof(data_scope)='object' and octet_length(data_scope::text)<=4000);

create table if not exists public.privacy_request_events (
  id bigint generated always as identity primary key,
  privacy_request_id uuid not null references public.privacy_requests(id) on delete restrict,
  actor_id uuid references auth.users(id) on delete restrict,
  event_type text not null check (event_type in (
    'submitted','identity_verified','assigned','status_changed','information_requested',
    'information_received','consent_withdrawn','erasure_approved','erasure_started',
    'erasure_completed','partially_fulfilled','fulfilled','rejected','note_added'
  )),
  old_status text,
  new_status text,
  public_message text,
  internal_reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (octet_length(metadata::text)<=4000)
);
create index if not exists privacy_request_events_request_idx
  on public.privacy_request_events(privacy_request_id,created_at);

-- Append-only consent evidence. Operational consent is purpose-specific; essential
-- service processing is not incorrectly represented as optional consent.
create table if not exists public.privacy_consent_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete restrict,
  purpose_key text not null check (purpose_key in (
    'service_sms','marketing_communications','product_analytics','personalised_recommendations',
    'nonessential_cookies','referral_invitations'
  )),
  action text not null check (action in ('granted','withdrawn')),
  notice_version text not null check (length(btrim(notice_version)) between 1 and 40),
  source text not null check (source in ('web','ios','android','support','admin_correction')),
  recorded_at timestamptz not null default now(),
  actor_id uuid references auth.users(id) on delete restrict
);
create index if not exists privacy_consent_user_purpose_idx
  on public.privacy_consent_events(user_id,purpose_key,recorded_at desc);

create table if not exists public.privacy_breach_incidents (
  id uuid primary key default gen_random_uuid(),
  incident_reference text not null unique,
  detected_at timestamptz not null,
  occurred_from timestamptz,
  occurred_to timestamptz,
  severity text not null check (severity in ('low','medium','high','critical')),
  status text not null default 'detected'
    check (status in ('detected','triage','contained','investigating','notified','remediating','closed')),
  data_categories text[] not null default '{}',
  estimated_affected_subjects integer check (estimated_affected_subjects is null or estimated_affected_subjects>=0),
  systems_affected text[] not null default '{}',
  factual_summary text not null check (length(btrim(factual_summary)) between 20 and 8000),
  containment_actions text,
  risk_assessment text,
  notification_assessment text,
  authority_notification_reference text,
  affected_user_notification_at timestamptz,
  authority_notification_at timestamptz,
  root_cause text,
  remediation text,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete restrict,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists privacy_breach_status_idx
  on public.privacy_breach_incidents(status,severity,detected_at desc);

create table if not exists public.data_retention_policies (
  id uuid primary key default gen_random_uuid(),
  rule_key text not null,
  version text not null,
  data_class text not null check (data_class in (
    'identity_documents','verification_metadata','account_profile','booking_contracts',
    'payment_ledger','tax_records','handover_evidence','support_cases','grievance_records',
    'community_content','security_logs','consent_records','legal_acceptance_records',
    'breach_incident_records','marketing_analytics'
  )),
  retention_days integer,
  rationale text not null check (length(btrim(rationale)) between 20 and 2000),
  legal_basis_note text not null check (length(btrim(legal_basis_note)) between 10 and 2000),
  status text not null default 'draft'
    check (status in ('draft','pending_approval','active','paused','retired')),
  created_by uuid not null references auth.users(id) on delete restrict,
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  effective_from timestamptz,
  effective_until timestamptz,
  created_at timestamptz not null default now(),
  unique(rule_key,version),
  check (retention_days is null or retention_days between 1 and 36500),
  check (approved_by is null or approved_by<>created_by),
  check (status not in ('active','paused') or
    (retention_days is not null and approved_by is not null and approved_at is not null and effective_from is not null)),
  check (effective_until is null or effective_from is null or effective_until>effective_from)
);
create index if not exists data_retention_active_idx
  on public.data_retention_policies(data_class,effective_from desc)
  where status='active';

create table if not exists public.data_retention_runs (
  id uuid primary key default gen_random_uuid(),
  policy_id uuid not null references public.data_retention_policies(id) on delete restrict,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  evaluated_count integer not null default 0,
  queued_count integer not null default 0,
  skipped_legal_hold_count integer not null default 0,
  status text not null default 'review_only' check (status in ('review_only','completed','failed')),
  details jsonb not null default '{}'::jsonb,
  initiated_by uuid references auth.users(id) on delete restrict
);

create table if not exists public.privacy_legal_holds (
  id uuid primary key default gen_random_uuid(),
  subject_user_id uuid not null references auth.users(id) on delete restrict,
  data_class text not null,
  reason text not null check (length(btrim(reason)) between 20 and 2000),
  source_reference text,
  created_by uuid not null references auth.users(id) on delete restrict,
  released_by uuid references auth.users(id) on delete restrict,
  released_at timestamptz,
  created_at timestamptz not null default now(),
  check ((released_at is null and released_by is null) or (released_at is not null and released_by is not null))
);
create index if not exists privacy_legal_holds_subject_active_idx
  on public.privacy_legal_holds(subject_user_id,data_class) where released_at is null;

create table if not exists public.sensitive_data_access_events (
  id bigint generated always as identity primary key,
  actor_id uuid not null references auth.users(id) on delete restrict,
  subject_user_id uuid references auth.users(id) on delete restrict,
  data_class text not null check (data_class in (
    'identity_document','identity_verification','privacy_request','privacy_consent',
    'financial_personal_data','support_private_note','breach_incident','legal_document_draft'
  )),
  resource_table text not null,
  resource_id text not null,
  purpose text not null check (length(btrim(purpose)) between 10 and 1000),
  outcome text not null check (outcome in ('success','denied','failed')),
  request_id text not null,
  metadata jsonb not null default '{}'::jsonb,
  accessed_at timestamptz not null default now(),
  check (octet_length(metadata::text)<=2000)
);
create index if not exists sensitive_data_actor_idx
  on public.sensitive_data_access_events(actor_id,accessed_at desc);
create index if not exists sensitive_data_subject_idx
  on public.sensitive_data_access_events(subject_user_id,accessed_at desc);
create index if not exists sensitive_data_resource_idx
  on public.sensitive_data_access_events(resource_table,resource_id,accessed_at desc);

alter table public.identity_documents
  add column if not exists object_deleted_at timestamptz;

create table if not exists public.privacy_erasure_jobs (
  id uuid primary key default gen_random_uuid(),
  privacy_request_id uuid not null references public.privacy_requests(id) on delete restrict,
  subject_user_id uuid not null references auth.users(id) on delete restrict,
  job_type text not null check (job_type in ('identity_document_delete','profile_anonymise')),
  identity_document_id uuid references public.identity_documents(id) on delete restrict,
  storage_bucket text,
  object_key text,
  status text not null default 'pending'
    check (status in ('pending','processing','completed','blocked','failed')),
  attempts integer not null default 0 check (attempts between 0 and 20),
  last_error_code text,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  unique(privacy_request_id,job_type,identity_document_id),
  check ((job_type='identity_document_delete' and identity_document_id is not null
            and storage_bucket='identity-private' and object_key is not null)
      or (job_type='profile_anonymise' and identity_document_id is null
            and storage_bucket is null and object_key is null))
);
create index if not exists privacy_erasure_jobs_pending_idx
  on public.privacy_erasure_jobs(status,created_at) where status in ('pending','failed');
create unique index if not exists privacy_erasure_profile_job_uq
  on public.privacy_erasure_jobs(privacy_request_id) where job_type='profile_anonymise';

create table if not exists public.privacy_erasure_job_events (
  id bigint generated always as identity primary key,
  job_id uuid not null references public.privacy_erasure_jobs(id) on delete restrict,
  event_type text not null,
  error_code text,
  created_at timestamptz not null default now()
);

-- New fine-grained permissions: only authorised legal/privacy staff receive them.
insert into public.admin_permission_catalog(permission_key,module_key,description,sensitivity) values
('legal.draft.write','legal','Create and revise unpublished legal document drafts','high_risk'),
('privacy.incidents.read','privacy','Read security and privacy incident records','identity'),
('privacy.incidents.manage','privacy','Create and update security/privacy incident records','high_risk'),
('privacy.retention.read','privacy','Read approved data retention rules','identity'),
('privacy.retention.manage','privacy','Create and revise draft retention rules','high_risk'),
('privacy.retention.approve','privacy','Approve retention rules through maker-checker controls','high_risk'),
('privacy.accesslog.read','privacy','Read sensitive-data access logs','identity'),
('privacy.erase.request','privacy','Request a controlled erasure action','high_risk'),
('privacy.erase.approve','privacy','Approve controlled erasure actions','high_risk')
on conflict(permission_key) do update set description=excluded.description,sensitivity=excluded.sensitivity;

insert into public.admin_role_permissions(role,permission_key)
select 'admin',permission_key from public.admin_permission_catalog
where permission_key in ('legal.draft.write','privacy.erase.request','privacy.incidents.read','privacy.retention.read')
on conflict do nothing;

insert into public.admin_role_permissions(role,permission_key)
select 'super_admin',permission_key from public.admin_permission_catalog
where permission_key in (
  'legal.draft.write','privacy.erase.request','privacy.erase.approve',
  'privacy.incidents.read','privacy.incidents.manage','privacy.retention.read',
  'privacy.retention.manage','privacy.retention.approve','privacy.accesslog.read'
)
on conflict do nothing;

-- Extend the existing maker-checker approval catalogue for privacy erasure.
alter table public.admin_approval_requests
  drop constraint if exists admin_approval_requests_action_key_check;
alter table public.admin_approval_requests add constraint admin_approval_requests_action_key_check
  check (action_key in (
    'refund.execute','payout.execute','deposit.release','dispute.finalize',
    'pricing.publish','valuation.publish','legal.publish','risk.resolve',
    'user.suspend','user.role.grant','privacy.erase'
  ));

create or replace function public.admin_request_approval(
  p_action_key text,p_target_id text,p_request_payload jsonb,p_reason text,p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid(); v_request_permission text; v_target_table text; v_id uuid;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
    raise exception 'Authentication and MFA AAL2 required';
  end if;
  if length(btrim(coalesce(p_reason,'')))<30 or length(btrim(p_reason))>2000 then
    raise exception 'Reason must be 30 to 2000 characters';
  end if;
  if p_request_payload is null or jsonb_typeof(p_request_payload)<>'object' or octet_length(p_request_payload::text)>8192 then
    raise exception 'Invalid approval payload';
  end if;
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
    when 'privacy.erase' then v_request_permission:='privacy.erase.request'; v_target_table:='privacy_requests';
    else raise exception 'Unsupported high-risk action';
  end case;
  if not private.admin_can(v_actor,v_request_permission) then raise exception 'Permission denied'; end if;
  insert into public.admin_approval_requests(action_key,target_table,target_id,request_payload,reason,requested_by,idempotency_key)
  values(p_action_key,v_target_table,left(p_target_id,100),p_request_payload,left(p_reason,2000),v_actor,p_idempotency_key)
  returning id into v_id;
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,outcome,reason,request_id,metadata)
  values(v_actor,'approval_requested','approvals',v_request_permission,v_target_table,left(p_target_id,100),
    'success',left(p_reason,500),p_idempotency_key,jsonb_build_object('approval_id',v_id,'action_key',p_action_key));
  return v_id;
end;
$$;
revoke all on function public.admin_request_approval(text,text,jsonb,text,text) from public,anon;
grant execute on function public.admin_request_approval(text,text,jsonb,text,text) to authenticated;

create or replace function public.admin_decide_approval(
  p_request_id uuid,p_decision text,p_reason text
) returns void language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid(); v_request public.admin_approval_requests%rowtype; v_permission text;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception 'MFA AAL2 required'; end if;
  if p_decision not in ('approved','rejected') or length(btrim(coalesce(p_reason,''))) not between 30 and 2000 then
    raise exception 'Invalid approval decision or reason';
  end if;
  select * into v_request from public.admin_approval_requests where id=p_request_id for update;
  if not found or v_request.status<>'pending' or v_request.expires_at<=now() then raise exception 'Approval is not pending or expired'; end if;
  if v_request.requested_by=v_actor then raise exception 'Maker cannot approve own request'; end if;
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
    when 'privacy.erase' then 'privacy.erase.approve'
    else null end;
  if v_permission is null or not private.admin_can(v_actor,v_permission) then raise exception 'Approval permission denied'; end if;
  update public.admin_approval_requests set status=p_decision,approved_by=v_actor,decision_reason=left(p_reason,2000),decided_at=now()
  where id=p_request_id;
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,outcome,reason,request_id,metadata)
  values(v_actor,'approval_'||p_decision,'approvals',v_permission,v_request.target_table,v_request.target_id,
    'success',left(p_reason,500),p_request_id::text,jsonb_build_object('approval_id',p_request_id,'maker_id',v_request.requested_by,'action_key',v_request.action_key));
end;
$$;
revoke all on function public.admin_decide_approval(uuid,text,text) from public,anon;
grant execute on function public.admin_decide_approval(uuid,text,text) to authenticated;

-- A draft is immutable after publication and its hash is computed by the database.
create or replace function public.admin_save_legal_draft(
  p_document_id uuid,p_document_type text,p_version text,p_title text,p_content_uri text,
  p_content_markdown text,p_requires_acceptance boolean,p_reacceptance_required boolean,p_review_notes text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,private,extensions
as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_hash text;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'legal.draft.write') then raise exception 'Legal draft permission and MFA AAL2 required'; end if;
  if p_document_type not in (
    'terms_conditions','privacy_policy','cookie_policy','marketplace_rules','owner_agreement','reader_agreement',
    'rental_agreement','damage_compensation_policy','cancellation_refund_policy','deposit_policy','non_return_policy',
    'community_guidelines','content_copyright_policy','grievance_policy','identity_verification_notice','referral_terms'
  ) then raise exception 'Unsupported legal document type'; end if;
  if p_version !~ '^[0-9]+\.[0-9]+([.-][A-Za-z0-9_-]+)?$'
    or length(btrim(coalesce(p_title,''))) not between 3 and 160
    or length(coalesce(p_content_markdown,'')) not between 100 and 150000
    or p_content_uri !~ '^docs/legal-drafts/[A-Za-z0-9._/-]+$' then
    raise exception 'Invalid draft metadata or content';
  end if;
  v_hash:=encode(extensions.digest(convert_to(p_content_markdown,'UTF8'),'sha256'),'hex');
  if p_document_id is null then
    insert into public.legal_documents(document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
      content_markdown,review_status,created_by,updated_by,requires_acceptance,reacceptance_required,review_notes)
    values(p_document_type,p_version,p_title,p_content_uri,v_hash,null,null,false,p_content_markdown,'draft',
      v_actor,v_actor,coalesce(p_requires_acceptance,true),coalesce(p_reacceptance_required,true),left(p_review_notes,4000))
    returning id into v_id;
  else
    update public.legal_documents set title=p_title,content_uri=p_content_uri,sha256=v_hash,
      content_markdown=p_content_markdown,review_status='draft',updated_by=v_actor,updated_at=now(),
      requires_acceptance=coalesce(p_requires_acceptance,true),reacceptance_required=coalesce(p_reacceptance_required,true),
      review_notes=left(p_review_notes,4000)
    where id=p_document_id and not is_published and review_status in ('draft','in_review')
      and document_type=p_document_type and version=p_version
    returning id into v_id;
    if v_id is null then raise exception 'Draft not found, immutable or version mismatch'; end if;
  end if;
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,outcome,reason,request_id,metadata)
  values(v_actor,'legal_draft_saved','legal','legal.draft.write','legal_documents',v_id::text,'success',
    left(coalesce(p_review_notes,'Draft saved'),500),gen_random_uuid()::text,jsonb_build_object('version',p_version,'sha256',v_hash));
  return v_id;
end;
$$;
revoke all on function public.admin_save_legal_draft(uuid,text,text,text,text,text,boolean,boolean,text) from public,anon;
grant execute on function public.admin_save_legal_draft(uuid,text,text,text,text,text,boolean,boolean,text) to authenticated;

create or replace function public.admin_submit_legal_draft(p_document_id uuid,p_review_notes text)
returns void language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid();
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'legal.draft.write') then raise exception 'Legal draft permission and MFA required'; end if;
  update public.legal_documents set review_status='in_review',review_notes=left(p_review_notes,4000),
    updated_by=v_actor,updated_at=now()
  where id=p_document_id and not is_published and review_status='draft' and content_markdown is not null;
  if not found then raise exception 'Draft not found or not ready for review'; end if;
end;
$$;
revoke all on function public.admin_submit_legal_draft(uuid,text) from public,anon;
grant execute on function public.admin_submit_legal_draft(uuid,text) to authenticated;

create or replace function public.admin_publish_legal_document(
  p_document_id uuid,p_approval_request_id uuid,p_effective_from timestamptz
) returns void language plpgsql security definer
set search_path=pg_catalog,public,private,extensions
as $$
declare v_actor uuid:=auth.uid(); v_doc public.legal_documents%rowtype; v_approval public.admin_approval_requests%rowtype;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'legal.publish.approve') then raise exception 'Legal publication approval and MFA required'; end if;
  select * into v_doc from public.legal_documents where id=p_document_id for update;
  select * into v_approval from public.admin_approval_requests where id=p_approval_request_id for update;
  if not found or v_doc.id is null or v_approval.id is null or v_approval.action_key<>'legal.publish'
    or v_approval.target_id<>p_document_id::text or v_approval.status<>'approved'
    or v_approval.requested_by=v_approval.approved_by or v_approval.approved_by=v_actor then
    raise exception 'A separate, approved legal publication request is required';
  end if;
  if v_doc.is_published or v_doc.review_status<>'in_review' or v_doc.content_markdown is null
    or v_doc.sha256<>encode(extensions.digest(convert_to(v_doc.content_markdown,'UTF8'),'sha256'),'hex')
    or p_effective_from is null or p_effective_from<now() then
    raise exception 'Document is not publishable or its content hash is invalid';
  end if;
  update public.legal_documents set effective_until=p_effective_from
  where document_type=v_doc.document_type and is_published and effective_until is null;
  update public.legal_documents set is_published=true,review_status='published',
    effective_from=p_effective_from,published_at=now(),approved_by=v_approval.approved_by,
    approved_at=v_approval.decided_at,updated_by=v_actor,updated_at=now()
  where id=p_document_id;
  update public.admin_approval_requests set status='executed',executed_at=now() where id=p_approval_request_id;
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,outcome,request_id,metadata)
  values(v_actor,'legal_document_published','legal','legal.publish.approve','legal_documents',p_document_id::text,
    'success',p_approval_request_id::text,jsonb_build_object('version',v_doc.version,'sha256',v_doc.sha256,'effective_from',p_effective_from));
end;
$$;
revoke all on function public.admin_publish_legal_document(uuid,uuid,timestamptz) from public,anon;
grant execute on function public.admin_publish_legal_document(uuid,uuid,timestamptz) to authenticated;

create or replace function public.record_legal_acceptance(
  p_legal_document_id uuid,p_document_sha256 text,p_acceptance_context text,p_source text,
  p_ip_hash text default null,p_user_agent_hash text default null
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_actor uuid:=auth.uid(); v_doc public.legal_documents%rowtype; v_id uuid;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  select * into v_doc from public.legal_documents where id=p_legal_document_id and is_published
    and effective_from<=now() and (effective_until is null or effective_until>now());
  if not found or v_doc.sha256<>p_document_sha256 or not v_doc.requires_acceptance then
    raise exception 'Document is unavailable or hash mismatch';
  end if;
  if length(btrim(coalesce(p_acceptance_context,''))) not between 2 and 60
    or p_source not in ('web','ios','android') then raise exception 'Invalid acceptance context'; end if;
  insert into public.legal_acceptances(user_id,legal_document_id,accepted_at,acceptance_context,
    ip_hash,user_agent_hash,document_sha256,acceptance_source,consent_notice_version)
  values(v_actor,p_legal_document_id,now(),p_acceptance_context,p_ip_hash,p_user_agent_hash,
    p_document_sha256,p_source,v_doc.version)
  on conflict(user_id,legal_document_id,acceptance_context) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.legal_acceptances
    where user_id=v_actor and legal_document_id=p_legal_document_id and acceptance_context=p_acceptance_context;
  end if;
  return v_id;
end;
$$;
revoke all on function public.record_legal_acceptance(uuid,text,text,text,text,text) from public,anon;
grant execute on function public.record_legal_acceptance(uuid,text,text,text,text,text) to authenticated;

create or replace function public.create_privacy_request(p_request_type text,p_description text)
returns uuid language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_ref text;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if p_request_type not in ('access','correction','erasure','portability','withdraw_consent','restriction','grievance')
    or length(btrim(coalesce(p_description,''))) not between 10 and 5000 then raise exception 'Invalid privacy request'; end if;
  v_ref:='PR-'||to_char(now() at time zone 'Asia/Kolkata','YYYYMMDD')||'-'||upper(substr(gen_random_uuid()::text,1,8));
  insert into public.privacy_requests(requester_id,request_type,description,request_reference,data_scope)
  values(v_actor,p_request_type,left(p_description,5000),v_ref,'{}'::jsonb) returning id into v_id;
  insert into public.privacy_request_events(privacy_request_id,actor_id,event_type,new_status,public_message)
  values(v_id,v_actor,'submitted','received','Your request has been received. We will verify your identity where necessary and provide updates here.');
  return v_id;
end;
$$;
revoke all on function public.create_privacy_request(text,text) from public,anon;
grant execute on function public.create_privacy_request(text,text) to authenticated;

create or replace function public.record_privacy_consent(
  p_purpose_key text,p_action text,p_notice_version text,p_source text
) returns bigint language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_actor uuid:=auth.uid(); v_id bigint;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if p_purpose_key not in ('service_sms','marketing_communications','product_analytics','personalised_recommendations','nonessential_cookies','referral_invitations')
    or p_action not in ('granted','withdrawn') or p_source not in ('web','ios','android')
    or length(btrim(coalesce(p_notice_version,''))) not between 1 and 40 then
    raise exception 'Invalid consent update';
  end if;
  insert into public.privacy_consent_events(user_id,purpose_key,action,notice_version,source,actor_id)
  values(v_actor,p_purpose_key,p_action,p_notice_version,p_source,v_actor) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.record_privacy_consent(text,text,text,text) from public,anon;
grant execute on function public.record_privacy_consent(text,text,text,text) to authenticated;

create or replace function public.admin_update_privacy_request(
  p_request_id uuid,p_status text,p_assigned_to uuid,p_resolution_summary text,p_reason text
) returns void language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid(); v_old public.privacy_requests%rowtype;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'privacy.manage') then raise exception 'Privacy management permission and MFA required'; end if;
  if p_status not in ('received','identity_check','in_progress','awaiting_user','fulfilled','partially_fulfilled','rejected','closed')
    or length(btrim(coalesce(p_reason,'')))<20 then raise exception 'Invalid status or reason'; end if;
  if p_resolution_summary is not null and length(p_resolution_summary)>4000 then raise exception 'Resolution summary too long'; end if;
  select * into v_old from public.privacy_requests where id=p_request_id for update;
  if not found then raise exception 'Privacy request not found'; end if;
  if p_assigned_to is not null and not exists(
    select 1 from public.user_roles where user_id=p_assigned_to and revoked_at is null
      and role in ('admin','super_admin','support_agent')
  ) then raise exception 'Assignee must be active authorised staff'; end if;
  update public.privacy_requests set status=p_status,assigned_to=p_assigned_to,
    resolution_summary=coalesce(left(p_resolution_summary,4000),resolution_summary),
    completed_at=case when p_status in ('fulfilled','partially_fulfilled','rejected','closed') then now() else null end,
    updated_at=now()
  where id=p_request_id;
  insert into public.privacy_request_events(privacy_request_id,actor_id,event_type,old_status,new_status,
    public_message,internal_reason,metadata)
  values(p_request_id,v_actor,'status_changed',v_old.status,p_status,
    case when p_status='fulfilled' then left(coalesce(p_resolution_summary,'Request fulfilled'),1000) else null end,
    left(p_reason,1000),jsonb_build_object('assigned_to',p_assigned_to));
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,outcome,reason,request_id,metadata)
  values(v_actor,'privacy_request_updated','privacy','privacy.manage','privacy_requests',p_request_id::text,
    'success',left(p_reason,500),gen_random_uuid()::text,jsonb_build_object('from_status',v_old.status,'to_status',p_status));
end;
$$;
revoke all on function public.admin_update_privacy_request(uuid,text,uuid,text,text) from public,anon;
grant execute on function public.admin_update_privacy_request(uuid,text,uuid,text,text) to authenticated;

create or replace function public.admin_record_privacy_incident(
  p_incident_reference text,p_detected_at timestamptz,p_severity text,p_data_categories text[],
  p_estimated_subjects integer,p_systems_affected text[],p_factual_summary text,p_containment text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid(); v_id uuid;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'privacy.incidents.manage') then raise exception 'Incident management permission and MFA required'; end if;
  if p_incident_reference !~ '^INC-[A-Z0-9-]{6,40}$' or p_detected_at is null
    or p_severity not in ('low','medium','high','critical')
    or length(btrim(coalesce(p_factual_summary,''))) not between 20 and 8000
    or coalesce(array_length(p_data_categories,1),0)>20
    or coalesce(array_length(p_systems_affected,1),0)>30
    or (p_estimated_subjects is not null and p_estimated_subjects<0) then
    raise exception 'Invalid incident fields';
  end if;
  insert into public.privacy_breach_incidents(incident_reference,detected_at,severity,data_categories,
    estimated_affected_subjects,systems_affected,factual_summary,containment_actions,created_by,updated_by)
  values(p_incident_reference,p_detected_at,p_severity,p_data_categories,p_estimated_subjects,
    p_systems_affected,left(p_factual_summary,8000),left(p_containment,4000),v_actor,v_actor)
  returning id into v_id;
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,outcome,request_id,metadata)
  values(v_actor,'privacy_incident_recorded','privacy','privacy.incidents.manage','privacy_breach_incidents',v_id::text,
    'success',gen_random_uuid()::text,jsonb_build_object('severity',p_severity,'reference',p_incident_reference));
  return v_id;
end;
$$;
revoke all on function public.admin_record_privacy_incident(text,timestamptz,text,text[],integer,text[],text,text) from public,anon;
grant execute on function public.admin_record_privacy_incident(text,timestamptz,text,text[],integer,text[],text,text) to authenticated;

create or replace function public.admin_save_retention_policy(
  p_rule_key text,p_version text,p_data_class text,p_retention_days integer,
  p_rationale text,p_legal_basis_note text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid(); v_id uuid;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'privacy.retention.manage') then raise exception 'Retention management permission and MFA required'; end if;
  if p_retention_days is null or p_retention_days not between 1 and 36500
    or p_version !~ '^[0-9]+\.[0-9]+([.-][A-Za-z0-9_-]+)?$'
    or length(btrim(coalesce(p_rule_key,''))) not between 3 and 80 then raise exception 'Invalid retention rule'; end if;
  insert into public.data_retention_policies(rule_key,version,data_class,retention_days,rationale,legal_basis_note,created_by)
  values(p_rule_key,p_version,p_data_class,p_retention_days,left(p_rationale,2000),left(p_legal_basis_note,2000),v_actor)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.admin_save_retention_policy(text,text,text,integer,text,text) from public,anon;
grant execute on function public.admin_save_retention_policy(text,text,text,integer,text,text) to authenticated;

create or replace function public.admin_approve_retention_policy(p_policy_id uuid,p_effective_from timestamptz,p_reason text)
returns void language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid(); v_policy public.data_retention_policies%rowtype;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'privacy.retention.approve') then raise exception 'Retention approval permission and MFA required'; end if;
  select * into v_policy from public.data_retention_policies where id=p_policy_id for update;
  if not found or v_policy.status<>'draft' or v_policy.created_by=v_actor
    or p_effective_from is null or p_effective_from<now() or length(btrim(coalesce(p_reason,'')))<30 then
    raise exception 'Retention rule cannot be approved';
  end if;
  update public.data_retention_policies set status='active',approved_by=v_actor,approved_at=now(),effective_from=p_effective_from
  where id=p_policy_id;
  update public.data_retention_policies set status='retired',effective_until=p_effective_from
  where rule_key=v_policy.rule_key and status='active' and id<>p_policy_id;
end;
$$;
revoke all on function public.admin_approve_retention_policy(uuid,timestamptz,text) from public,anon;
grant execute on function public.admin_approve_retention_policy(uuid,timestamptz,text) to authenticated;

create or replace function public.admin_queue_privacy_erasure(p_approval_request_id uuid)
returns integer language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare
  v_actor uuid:=auth.uid(); v_approval public.admin_approval_requests%rowtype;
  v_request public.privacy_requests%rowtype; v_count integer:=0;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'privacy.erase.approve') then raise exception 'Erasure approval permission and MFA required'; end if;
  select * into v_approval from public.admin_approval_requests where id=p_approval_request_id for update;
  if not found or v_approval.action_key<>'privacy.erase' or v_approval.status<>'approved'
    or v_approval.requested_by=v_actor then
    raise exception 'Separate approved erasure request required';
  end if;
  select * into v_request from public.privacy_requests
    where id=v_approval.target_id::uuid and request_type='erasure' for update;
  if not found or v_request.status not in ('received','identity_check','in_progress') then raise exception 'Erasure request is not eligible'; end if;
  if v_request.legal_hold or exists(select 1 from public.privacy_legal_holds where subject_user_id=v_request.requester_id and released_at is null) then
    raise exception 'Erasure is blocked by a legal hold';
  end if;
  if exists(select 1 from public.bookings b where (b.reader_id=v_request.requester_id or b.owner_id=v_request.requester_id)
      and b.status::text not in ('completed','cancelled','expired')) then
    raise exception 'Erasure is blocked by an active rental obligation';
  end if;
  insert into public.privacy_erasure_jobs(privacy_request_id,subject_user_id,job_type,identity_document_id,storage_bucket,object_key)
  select v_request.id,d.user_id,'identity_document_delete',d.id,d.storage_bucket,d.object_key
  from public.identity_documents d
  where d.user_id=v_request.requester_id and d.object_deleted_at is null
  on conflict do nothing;
  get diagnostics v_count=row_count;
  insert into public.privacy_erasure_jobs(privacy_request_id,subject_user_id,job_type)
  values(v_request.id,v_request.requester_id,'profile_anonymise')
  on conflict do nothing;
  update public.privacy_requests set status='in_progress',updated_at=now()
  where id=v_request.id;
  insert into public.privacy_request_events(privacy_request_id,actor_id,event_type,new_status,internal_reason,metadata)
  values(v_request.id,v_actor,'erasure_started','in_progress','Approved identity-file deletion and profile anonymisation jobs queued.',
    jsonb_build_object('identity_documents_queued',v_count,'approval_request_id',p_approval_request_id));
  update public.admin_approval_requests set status='executed',executed_at=now() where id=p_approval_request_id;
  return v_count+1;
end;
$$;
revoke all on function public.admin_queue_privacy_erasure(uuid) from public,anon;
grant execute on function public.admin_queue_privacy_erasure(uuid) to authenticated;

create or replace function public.claim_privacy_erasure_jobs(p_limit integer default 20)
returns setof public.privacy_erasure_jobs language plpgsql security definer
set search_path=pg_catalog,public
as $$
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Service role required'; end if;
  return query
  with picked as (
    select j.id from public.privacy_erasure_jobs j
    join public.privacy_requests r on r.id=j.privacy_request_id
    where j.status in ('pending','failed') and j.attempts<5
      and r.status='in_progress' and not r.legal_hold
      and not exists(select 1 from public.privacy_legal_holds h
        where h.subject_user_id=j.subject_user_id and h.released_at is null)
      and not exists(select 1 from public.bookings b
        where (b.reader_id=j.subject_user_id or b.owner_id=j.subject_user_id)
          and b.status::text not in ('completed','cancelled','expired'))
    order by j.created_at limit greatest(1,least(p_limit,50)) for update of j skip locked
  )
  update public.privacy_erasure_jobs j set status='processing',attempts=attempts+1,started_at=now()
  from picked where j.id=picked.id returning j.*;
end;
$$;
revoke all on function public.claim_privacy_erasure_jobs(integer) from public,anon,authenticated;
grant execute on function public.claim_privacy_erasure_jobs(integer) to service_role;

create or replace function public.complete_privacy_erasure_job(p_job_id uuid,p_success boolean,p_error_code text default null)
returns void language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_job public.privacy_erasure_jobs%rowtype;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Service role required'; end if;
  select * into v_job from public.privacy_erasure_jobs where id=p_job_id for update;
  if not found or v_job.status<>'processing' then raise exception 'Erasure job is not processing'; end if;
  if p_success then
    if v_job.job_type='identity_document_delete' then
      update public.identity_documents set object_key='erased/'||id::text,
        object_deleted_at=now(),document_last4=null,provider_reference=null
      where id=v_job.identity_document_id and user_id=v_job.subject_user_id;
    elsif v_job.job_type='profile_anonymise' then
      update public.profiles set display_name='Deleted user',avatar_object_key=null,bio=null,
        preferred_city_id=null,account_status='suspended',updated_at=now()
      where id=v_job.subject_user_id;
    end if;
    update public.privacy_erasure_jobs set status='completed',completed_at=now(),last_error_code=null where id=p_job_id;
    insert into public.privacy_erasure_job_events(job_id,event_type) values(p_job_id,'completed');
  else
    update public.privacy_erasure_jobs set status=case when attempts>=5 then 'blocked' else 'failed' end,
      last_error_code=left(coalesce(p_error_code,'provider_delete_failed'),100) where id=p_job_id;
    insert into public.privacy_erasure_job_events(job_id,event_type,error_code)
    values(p_job_id,'failed',left(coalesce(p_error_code,'provider_delete_failed'),100));
  end if;
  if not exists(select 1 from public.privacy_erasure_jobs where privacy_request_id=v_job.privacy_request_id and status<>'completed') then
    update public.privacy_requests set status='partially_fulfilled',completed_at=now(),
      resolution_summary='Identity document files deleted and profile metadata anonymised. Account authentication identifiers and transaction/legal records are retained pending separate legal and operational review.',
      updated_at=now()
    where id=v_job.privacy_request_id;
    insert into public.privacy_request_events(privacy_request_id,event_type,new_status,internal_reason)
    values(v_job.privacy_request_id,'partially_fulfilled','partially_fulfilled',
      'Identity files deleted and profile anonymised; remaining account, transaction and statutory records are outside this automated job.');
  end if;
end;
$$;
revoke all on function public.complete_privacy_erasure_job(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.complete_privacy_erasure_job(uuid,boolean,text) to service_role;

-- Append-only histories.
create or replace function private.reject_privacy_history_mutation()
returns trigger language plpgsql set search_path=pg_catalog
as $$ begin raise exception 'Privacy and acceptance histories are append-only'; end; $$;
create trigger privacy_request_events_append_only before update or delete on public.privacy_request_events
for each row execute function private.reject_privacy_history_mutation();
create trigger privacy_consent_events_append_only before update or delete on public.privacy_consent_events
for each row execute function private.reject_privacy_history_mutation();
create trigger sensitive_data_access_append_only before update or delete on public.sensitive_data_access_events
for each row execute function private.reject_privacy_history_mutation();
create trigger privacy_erasure_job_events_append_only before update or delete on public.privacy_erasure_job_events
for each row execute function private.reject_privacy_history_mutation();
create trigger legal_acceptances_append_only before update or delete on public.legal_acceptances
for each row execute function private.reject_privacy_history_mutation();

create or replace function private.guard_published_legal_document()
returns trigger language plpgsql set search_path=pg_catalog
as $$
begin
  if tg_op='UPDATE' and old.is_published then
    if new.document_type is distinct from old.document_type
      or new.version is distinct from old.version or new.title is distinct from old.title
      or new.content_uri is distinct from old.content_uri
      or new.sha256 is distinct from old.sha256
      or new.content_markdown is distinct from old.content_markdown
      or new.effective_from is distinct from old.effective_from then
      raise exception 'Published legal document content is immutable; create a new version';
    end if;
  end if;
  return new;
end;
$$;
create trigger legal_documents_published_immutable
before update on public.legal_documents
for each row execute function private.guard_published_legal_document();

-- Direct access to personal requests and security records is denied; the Edge API
-- performs explicit ownership/permission checks and writes sensitive access logs.
alter table public.privacy_requests enable row level security;
alter table public.privacy_request_events enable row level security;
alter table public.privacy_consent_events enable row level security;
alter table public.privacy_breach_incidents enable row level security;
alter table public.data_retention_policies enable row level security;
alter table public.data_retention_runs enable row level security;
alter table public.privacy_legal_holds enable row level security;
alter table public.sensitive_data_access_events enable row level security;
alter table public.privacy_erasure_jobs enable row level security;
alter table public.privacy_erasure_job_events enable row level security;
alter table public.legal_documents enable row level security;
alter table public.legal_acceptances enable row level security;

revoke all on public.privacy_requests,public.privacy_request_events,public.privacy_consent_events,
  public.privacy_breach_incidents,public.data_retention_policies,public.data_retention_runs,
  public.privacy_legal_holds,public.sensitive_data_access_events,public.privacy_erasure_jobs,
  public.privacy_erasure_job_events from anon,authenticated;
grant select on public.privacy_requests,public.privacy_request_events,public.privacy_consent_events,
  public.legal_documents,public.legal_acceptances to authenticated;

create policy privacy_requests_owner_select on public.privacy_requests
  for select to authenticated using (requester_id=auth.uid());
create policy privacy_request_events_owner_select on public.privacy_request_events
  for select to authenticated using (exists(
    select 1 from public.privacy_requests r where r.id=privacy_request_id and r.requester_id=auth.uid()));
create policy privacy_consent_owner_select on public.privacy_consent_events
  for select to authenticated using (user_id=auth.uid());
create policy legal_documents_published_select on public.legal_documents
  for select to authenticated using (is_published=true);
create policy legal_acceptances_owner_select on public.legal_acceptances
  for select to authenticated using (user_id=auth.uid());

commit;

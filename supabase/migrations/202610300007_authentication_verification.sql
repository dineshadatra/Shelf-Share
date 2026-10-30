begin;

-- Registration data is written only by the trusted registration RPC.
alter table public.profiles
  add column if not exists date_of_birth date,
  add column if not exists profile_photo_object_key text;

create table if not exists public.registration_policy_versions (
  id uuid primary key default gen_random_uuid(),
  terms_version text not null,
  privacy_version text not null,
  terms_url text not null,
  privacy_url text not null,
  is_active boolean not null default false,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  unique (terms_version, privacy_version),
  check (terms_url ~ '^https://'),
  check (privacy_url ~ '^https://'),
  check (not is_active or approved_at is not null)
);
create unique index if not exists registration_policy_one_active
  on public.registration_policy_versions ((is_active)) where is_active;

create table if not exists public.registration_acceptances (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete restrict,
  terms_version text not null,
  privacy_version text not null,
  accepted_at timestamptz not null default now(),
  user_agent text,
  unique (user_id, terms_version, privacy_version)
);

create table if not exists public.verification_cases (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete restrict,
  status text not null default 'submitted'
    check (status in ('submitted','under_review','needs_info','resubmission_required','resubmitted','approved','rejected','suspended')),
  assigned_reviewer_id uuid references auth.users(id) on delete restrict,
  submitted_at timestamptz not null default now(),
  assigned_at timestamptz,
  reviewed_at timestamptz,
  decision_reason text,
  requested_information text,
  internal_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists verification_cases_queue_idx
  on public.verification_cases(status, submitted_at desc);
create index if not exists verification_cases_user_idx
  on public.verification_cases(user_id, submitted_at desc);
create unique index if not exists verification_cases_one_open_per_user
  on public.verification_cases(user_id)
  where status in ('submitted','under_review','needs_info');

alter table public.identity_documents
  add column if not exists verification_case_id uuid
    references public.verification_cases(id) on delete restrict;

create table if not exists public.verification_case_files (
  id uuid primary key default gen_random_uuid(),
  verification_case_id uuid not null references public.verification_cases(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  file_kind text not null check (file_kind in ('identity_document','address_evidence','verification_selfie')),
  storage_bucket text not null check (storage_bucket in ('identity-private','verification-selfie-private')),
  object_key text not null,
  created_at timestamptz not null default now(),
  unique (storage_bucket, object_key),
  check (object_key !~ '(^/|[.][.])')
);
create index if not exists verification_case_files_case_idx
  on public.verification_case_files(verification_case_id, file_kind);

-- A separate access ledger records every privileged preview; no file URL is stored.
create table if not exists public.verification_document_access_audit (
  id bigint generated always as identity primary key,
  verification_case_id uuid not null references public.verification_cases(id) on delete restrict,
  document_id uuid not null references public.verification_case_files(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  accessed_at timestamptz not null default now(),
  purpose text not null check (length(btrim(purpose)) between 5 and 500)
);

alter table public.registration_policy_versions enable row level security;
alter table public.registration_acceptances enable row level security;
alter table public.verification_cases enable row level security;
alter table public.verification_case_files enable row level security;
alter table public.verification_document_access_audit enable row level security;
revoke all on public.registration_policy_versions, public.registration_acceptances,
  public.verification_cases, public.verification_case_files,
  public.verification_document_access_audit from anon, authenticated;

-- Authenticated users may read only the active, non-sensitive legal version metadata.
create or replace function public.get_active_registration_policy()
returns table(terms_version text, privacy_version text, terms_url text, privacy_url text)
language sql stable security definer
set search_path = ''
as $$
  select p.terms_version, p.privacy_version, p.terms_url, p.privacy_url
  from public.registration_policy_versions p
  where p.is_active = true and p.approved_at is not null
  limit 1;
$$;
revoke all on function public.get_active_registration_policy() from public, anon;
grant execute on function public.get_active_registration_policy() to anon, authenticated;

-- Separate private bucket for live profile captures. These are not public profile URLs.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('profile-private','profile-private',false,5242880,array['image/jpeg']),
  ('verification-selfie-private','verification-selfie-private',false,5242880,array['image/jpeg'])
on conflict (id) do nothing;

update storage.buckets
set public = false
where id in ('identity-private','profile-private','verification-selfie-private');

create policy profile_private_upload_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'profile-private'
  and (storage.foldername(name))[1] = auth.uid()::text
  and lower(storage.extension(name)) = 'jpg'
);
create policy verification_selfie_upload_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'verification-selfie-private'
  and (storage.foldername(name))[1] = auth.uid()::text
  and lower(storage.extension(name)) = 'jpg'
);
-- There are intentionally no SELECT, UPDATE or DELETE policies for private identity, selfie or profile objects.
-- Admin previews are issued by the verification-admin Edge Function after server-side RBAC.

create or replace function public.complete_registration(
  p_display_name text,
  p_date_of_birth date,
  p_profile_photo_object_key text,
  p_terms_version text,
  p_privacy_version text,
  p_user_agent text default null
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_phone_confirmed_at timestamptz;
  v_is_eligible boolean;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  select u.phone_confirmed_at into v_phone_confirmed_at
  from auth.users u where u.id = v_user_id;
  if v_phone_confirmed_at is null then raise exception 'A verified mobile number is required'; end if;
  if p_display_name is null or length(btrim(p_display_name)) not between 1 and 80 then
    raise exception 'Enter a valid display name';
  end if;
  if p_date_of_birth is null then raise exception 'Date of birth is required'; end if;
  v_is_eligible := p_date_of_birth <= (((now() at time zone 'Asia/Kolkata')::date - interval '18 years')::date);
  if not v_is_eligible then raise exception 'ShelfShare is available only to people aged 18 or older'; end if;
  if p_profile_photo_object_key is null
    or p_profile_photo_object_key !~ ('^' || v_user_id::text || '/profile/[A-Za-z0-9-]+[.]jpg$')
    or not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'profile-private' and o.name = p_profile_photo_object_key
    ) then
    raise exception 'A first-time live camera photo is required';
  end if;
  if not exists (
    select 1 from public.registration_policy_versions p
    where p.is_active and p.approved_at is not null
      and p.terms_version = p_terms_version and p.privacy_version = p_privacy_version
  ) then
    raise exception 'The current approved Terms and Privacy Notice must be accepted';
  end if;
  if exists (select 1 from public.profiles p where p.id = v_user_id) then
    raise exception 'Registration has already been completed';
  end if;

  insert into public.profiles(id, display_name, date_of_birth, profile_photo_object_key)
  values (v_user_id, btrim(p_display_name), p_date_of_birth, p_profile_photo_object_key);

  insert into public.user_verifications(user_id, status, age_eligible, phone_verified_at, policy_version)
  values (v_user_id, 'not_submitted', true, v_phone_confirmed_at, p_terms_version)
  on conflict (user_id) do update set
    age_eligible = true,
    phone_verified_at = excluded.phone_verified_at,
    policy_version = excluded.policy_version;

  insert into public.registration_acceptances(user_id, terms_version, privacy_version, user_agent)
  values (v_user_id, p_terms_version, p_privacy_version, left(p_user_agent, 500));
  insert into public.verification_audit(user_id, actor_user_id, action, metadata)
  values (v_user_id, v_user_id, 'registration_completed',
    jsonb_build_object('terms_version', p_terms_version, 'privacy_version', p_privacy_version));
end;
$$;
revoke all on function public.complete_registration(text,date,text,text,text,text) from public, anon;
grant execute on function public.complete_registration(text,date,text,text,text,text) to authenticated;


-- Sync the verified phone timestamp after Supabase Auth confirms a phone change.
create or replace function public.sync_verified_phone()
returns void
language plpgsql security definer
set search_path = ''
as $func$
declare
  v_user_id uuid := auth.uid();
  v_phone_confirmed_at timestamptz;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  select u.phone_confirmed_at into v_phone_confirmed_at
  from auth.users u where u.id = v_user_id;
  if v_phone_confirmed_at is null then raise exception 'The new mobile number is not confirmed'; end if;
  update public.user_verifications
    set phone_verified_at = v_phone_confirmed_at, updated_at = now()
    where user_id = v_user_id;
  if not found then raise exception 'Complete registration before changing your mobile number'; end if;
  insert into public.verification_audit(user_id, actor_user_id, action, metadata)
  values (v_user_id, v_user_id, 'phone_number_changed',
    jsonb_build_object('phone_verified_at', v_phone_confirmed_at));
end;
$func$;
revoke all on function public.sync_verified_phone() from public, anon;
grant execute on function public.sync_verified_phone() to authenticated;

create or replace function public.submit_identity_verification(
  p_case_id uuid,
  p_document_type public.identity_document_type,
  p_document_object_key text,
  p_document_last4 text default null,
  p_address_object_key text default null,
  p_selfie_object_key text default null
)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_phone_confirmed_at timestamptz;
  v_age_eligible boolean;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  select u.phone_confirmed_at into v_phone_confirmed_at from auth.users u where u.id = v_user_id;
  if v_phone_confirmed_at is null then raise exception 'Phone verification is required'; end if;
  select uv.age_eligible into v_age_eligible from public.user_verifications uv where uv.user_id = v_user_id;
  if v_age_eligible is distinct from true then raise exception 'Complete age-eligible registration first'; end if;
  if not exists (select 1 from public.profiles p where p.id = v_user_id and p.account_status = 'active') then
    raise exception 'An active registered account is required for verification submission';
  end if;
  if p_case_id is null or p_document_type not in ('passport','pan','driving_licence') then
    raise exception 'Select Passport, PAN or Driving Licence';
  end if;
  if p_document_object_key !~ ('^' || v_user_id::text || '/' || p_case_id::text || '/identity[.](jpg|jpeg|png|pdf)$')
    or not exists (select 1 from storage.objects o where o.bucket_id = 'identity-private' and o.name = p_document_object_key) then
    raise exception 'Identity document upload is missing or invalid';
  end if;
  if p_address_object_key is not null and (
    p_address_object_key !~ ('^' || v_user_id::text || '/' || p_case_id::text || '/address[.](jpg|jpeg|png|pdf)$')
    or not exists (select 1 from storage.objects o where o.bucket_id = 'identity-private' and o.name = p_address_object_key)
  ) then raise exception 'Address evidence upload is invalid'; end if;
  if p_selfie_object_key is not null and (
    p_selfie_object_key !~ ('^' || v_user_id::text || '/' || p_case_id::text || '/selfie[.]jpg$')
    or not exists (select 1 from storage.objects o where o.bucket_id = 'verification-selfie-private' and o.name = p_selfie_object_key)
  ) then raise exception 'Verification selfie upload is invalid'; end if;
  if exists (select 1 from public.verification_cases c where c.user_id = v_user_id and c.status in ('submitted','under_review','needs_info')) then
    raise exception 'An active verification case already exists';
  end if;

  update public.verification_cases
    set status = 'resubmitted', updated_at = now()
    where user_id = v_user_id and status = 'resubmission_required';

  insert into public.verification_cases(id, user_id, status)
  values (p_case_id, v_user_id, 'submitted');
  insert into public.identity_documents(
    user_id, verification_user_id, verification_case_id, document_type, object_key, document_last4, status
  ) values (
    v_user_id, v_user_id, p_case_id, p_document_type, p_document_object_key,
    nullif(p_document_last4,''), 'submitted'
  );
  insert into public.verification_case_files(verification_case_id,user_id,file_kind,storage_bucket,object_key)
  values (p_case_id,v_user_id,'identity_document','identity-private',p_document_object_key);
  if p_address_object_key is not null then
    insert into public.verification_case_files(verification_case_id,user_id,file_kind,storage_bucket,object_key)
    values (p_case_id,v_user_id,'address_evidence','identity-private',p_address_object_key);
  end if;
  if p_selfie_object_key is not null then
    insert into public.verification_case_files(verification_case_id,user_id,file_kind,storage_bucket,object_key)
    values (p_case_id,v_user_id,'verification_selfie','verification-selfie-private',p_selfie_object_key);
  end if;

  update public.user_verifications
    set status = 'pending', identity_verified_at = null, address_verified_at = null, reviewed_by = null, reviewed_at = null,
        rejection_reason_code = null
    where user_id = v_user_id;
  insert into public.verification_audit(user_id,actor_user_id,action,to_status,metadata)
  values (v_user_id,v_user_id,'identity_submitted','pending',
    jsonb_build_object('case_id',p_case_id,'document_type',p_document_type));
  return p_case_id;
end;
$$;
revoke all on function public.submit_identity_verification(uuid,public.identity_document_type,text,text,text,text) from public, anon;
grant execute on function public.submit_identity_verification(uuid,public.identity_document_type,text,text,text,text) to authenticated;

create or replace function public.review_verification_case(
  p_case_id uuid,
  p_action text,
  p_reason text default null,
  p_internal_notes text default null,
  p_assignee uuid default null,
  p_address_verified boolean default false
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_case public.verification_cases%rowtype;
  v_from public.verification_status;
  v_to public.verification_status;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if not (private.has_role('verification_reviewer') or private.has_role('admin') or private.has_role('super_admin')) then
    raise exception 'Verification reviewer permission required';
  end if;
  select * into v_case from public.verification_cases where id = p_case_id for update;
  if not found then raise exception 'Verification case not found'; end if;
  if v_case.user_id = v_actor then raise exception 'Reviewers cannot review or approve their own account'; end if;
  select uv.status into v_from from public.user_verifications uv where uv.user_id = v_case.user_id;

  if p_action = 'assign' then
    if p_assignee is null then raise exception 'An active reviewer must be selected'; end if;
    if p_assignee <> v_actor and not (private.has_role('admin') or private.has_role('super_admin')) then
      raise exception 'Reviewers may assign cases only to themselves';
    end if;
    if p_assignee is null or not exists (
      select 1 from public.user_roles r where r.user_id = p_assignee
      and r.role in ('verification_reviewer','admin','super_admin') and r.revoked_at is null
    ) then raise exception 'Assignee is not an active reviewer'; end if;
    update public.verification_cases set assigned_reviewer_id = p_assignee, assigned_at = now(),
      status = case when status = 'submitted' then 'under_review' else status end,
      internal_notes = coalesce(left(p_internal_notes,4000), internal_notes), updated_at = now()
    where id = p_case_id;
    insert into public.verification_audit(user_id,actor_user_id,action,from_status,to_status,metadata)
    values (v_case.user_id,v_actor,'reviewer_assigned',v_from,v_from,jsonb_build_object('case_id',p_case_id,'assignee',p_assignee));
    return;
  end if;

  if p_action not in ('approve','reject','request_info','suspend') then raise exception 'Unsupported review action'; end if;
  if p_reason is null or length(btrim(p_reason)) < 5 then raise exception 'A decision reason of at least five characters is required'; end if;
  if v_case.assigned_reviewer_id is not null and v_case.assigned_reviewer_id <> v_actor
     and not (private.has_role('admin') or private.has_role('super_admin')) then
    raise exception 'This case is assigned to another reviewer';
  end if;
  if v_case.status not in ('submitted','under_review','needs_info') then
    raise exception 'This case is no longer reviewable';
  end if;

  if p_action = 'approve' then
    if not exists (select 1 from public.profiles p where p.id = v_case.user_id and p.account_status = 'active') then
      raise exception 'Suspended or closed accounts require a separate reinstatement decision';
    end if;
    update public.identity_documents set status = 'accepted', reviewed_by = v_actor, reviewed_at = now()
      where verification_case_id = p_case_id;
    if p_address_verified and not exists (
      select 1 from public.verification_case_files f
      where f.verification_case_id = p_case_id and f.file_kind = 'address_evidence'
    ) then raise exception 'Address verification cannot be marked complete without submitted address evidence'; end if;
    update public.user_verifications set status = 'verified', identity_verified_at = now(),
      address_verified_at = case when p_address_verified then now() else address_verified_at end,
      reviewed_by = v_actor, reviewed_at = now(), rejection_reason_code = null
      where user_id = v_case.user_id and age_eligible is true and phone_verified_at is not null;
    if not found then raise exception 'Phone and age eligibility must be complete before approval'; end if;
    update public.verification_cases set status='approved', decision_reason=left(p_reason,1000),
      internal_notes=coalesce(left(p_internal_notes,4000),internal_notes), reviewed_at=now(), updated_at=now()
      where id=p_case_id;
    v_to := 'verified';
  elsif p_action = 'reject' then
    update public.identity_documents set status = 'rejected', reviewed_by = v_actor, reviewed_at = now(),
      rejection_reason_code = 'manual_rejection' where verification_case_id = p_case_id;
    update public.user_verifications set status='rejected', identity_verified_at=null,
      reviewed_by=v_actor, reviewed_at=now(), rejection_reason_code='manual_rejection'
      where user_id=v_case.user_id;
    update public.verification_cases set status='rejected', decision_reason=left(p_reason,1000),
      internal_notes=coalesce(left(p_internal_notes,4000),internal_notes), reviewed_at=now(), updated_at=now()
      where id=p_case_id;
    v_to := 'rejected';
  elsif p_action = 'request_info' then
    update public.user_verifications set status='needs_resubmission', identity_verified_at=null,
      reviewed_by=v_actor, reviewed_at=now(), rejection_reason_code='additional_information_required'
      where user_id=v_case.user_id;
    update public.verification_cases set status='resubmission_required',
      requested_information=left(p_reason,1000), internal_notes=coalesce(left(p_internal_notes,4000),internal_notes),
      reviewed_at=now(), updated_at=now() where id=p_case_id;
    v_to := 'needs_resubmission';
  else
    if not (private.has_role('admin') or private.has_role('super_admin')) then
      raise exception 'Only an administrator can suspend an account';
    end if;
    update public.profiles set account_status='suspended' where id=v_case.user_id;
    update public.user_verifications set status='rejected', identity_verified_at=null,
      reviewed_by=v_actor, reviewed_at=now(), rejection_reason_code='account_suspended'
      where user_id=v_case.user_id;
    update public.verification_cases set status='suspended', decision_reason=left(p_reason,1000),
      internal_notes=coalesce(left(p_internal_notes,4000),internal_notes), reviewed_at=now(), updated_at=now()
      where id=p_case_id;
    v_to := v_from;
  end if;

  insert into public.verification_audit(user_id,actor_user_id,action,from_status,to_status,reason_code,metadata)
  values (v_case.user_id,v_actor,p_action,v_from,v_to,left(p_reason,1000),
    jsonb_build_object('case_id',p_case_id));
end;
$$;
revoke all on function public.review_verification_case(uuid,text,text,text,uuid,boolean) from public, anon;
grant execute on function public.review_verification_case(uuid,text,text,text,uuid,boolean) to authenticated;


-- A member may read only their own latest case summary; private reviewer notes and file keys remain hidden.
create or replace function public.get_my_verification_case()
returns table(
  case_id uuid,
  case_status text,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  decision_reason text,
  requested_information text
)
language sql stable security definer
set search_path = ''
as $func$
  select c.id, c.status, c.submitted_at, c.reviewed_at, c.decision_reason, c.requested_information
  from public.verification_cases c
  where c.user_id = auth.uid()
  order by c.submitted_at desc
  limit 1;
$func$;
revoke all on function public.get_my_verification_case() from public, anon;
grant execute on function public.get_my_verification_case() to authenticated;

-- Staff may read case files only through the Edge Function. Prevent direct exposure of file metadata.
-- Keep the existing user_verifications self-read policy limited to the granted safe columns.
revoke select, insert, update, delete on public.identity_documents,
  public.verification_case_files, public.verification_cases,
  public.verification_document_access_audit from anon, authenticated;
revoke insert, update, delete on public.registration_acceptances from anon, authenticated;
grant select on public.registration_acceptances to authenticated;
create policy registration_acceptance_self_read on public.registration_acceptances
for select to authenticated using (user_id = auth.uid());

-- Append-only audit ledgers.
create or replace function private.reject_verification_audit_mutation()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Verification audit records are append-only';
end;
$$;
drop trigger if exists verification_audit_no_mutation on public.verification_audit;
create trigger verification_audit_no_mutation
before update or delete on public.verification_audit
for each row execute function private.reject_verification_audit_mutation();

drop trigger if exists verification_case_files_no_update on public.verification_case_files;
create trigger verification_case_files_no_update
before update or delete on public.verification_case_files
for each row execute function private.reject_verification_audit_mutation();

commit;

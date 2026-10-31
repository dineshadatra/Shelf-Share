begin;

create table if not exists public.privacy_breach_incident_events (
  id bigint generated always as identity primary key,
  incident_id uuid not null references public.privacy_breach_incidents(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  event_type text not null check (event_type in ('incident_updated','status_changed','notification_recorded','containment_recorded','closed')),
  old_status text,
  new_status text,
  reason text not null check (length(btrim(reason)) between 10 and 2000),
  changed_fields text[] not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists privacy_breach_incident_events_idx
  on public.privacy_breach_incident_events(incident_id,created_at);

create or replace function public.admin_create_legal_version(
  p_source_document_id uuid,p_new_version text,p_new_content_uri text,p_change_reason text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,private,extensions
as $$
declare
  v_actor uuid:=auth.uid();
  v_source public.legal_documents%rowtype;
  v_new_id uuid;
  v_hash text;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'legal.draft.write') then
    raise exception 'Legal draft permission and MFA AAL2 required';
  end if;
  if p_new_version !~ '^[0-9]+\.[0-9]+([.-][A-Za-z0-9_-]+)?$'
    or p_new_content_uri !~ '^docs/legal-drafts/[A-Za-z0-9._/-]+$'
    or length(btrim(coalesce(p_change_reason,''))) not between 20 and 2000 then
    raise exception 'Version, source path and change reason are required';
  end if;
  select * into v_source from public.legal_documents
    where id=p_source_document_id and is_published=true for share;
  if not found or v_source.content_markdown is null then
    raise exception 'A published source document is required to create the next version';
  end if;
  if exists(select 1 from public.legal_documents
    where document_type=v_source.document_type and version=p_new_version) then
    raise exception 'That legal document version already exists';
  end if;
  v_hash:=encode(extensions.digest(convert_to(v_source.content_markdown,'UTF8'),'sha256'),'hex');
  insert into public.legal_documents(
    document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
    content_markdown,review_status,created_by,updated_by,requires_acceptance,reacceptance_required,
    supersedes_document_id,review_notes
  ) values (
    v_source.document_type,p_new_version,v_source.title,p_new_content_uri,v_hash,null,null,false,
    v_source.content_markdown,'draft',v_actor,v_actor,v_source.requires_acceptance,true,
    v_source.id,left(p_change_reason,4000)
  ) returning id into v_new_id;
  insert into public.legal_document_revisions(
    legal_document_id,revision_number,content_markdown,sha256,changed_by,change_note
  ) values(v_new_id,1,v_source.content_markdown,v_hash,v_actor,left(p_change_reason,2000));
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,
    outcome,reason,request_id,metadata)
  values(v_actor,'legal_version_created','legal','legal.draft.write','legal_documents',v_new_id::text,
    'success',left(p_change_reason,500),gen_random_uuid()::text,
    jsonb_build_object('source_document_id',v_source.id,'version',p_new_version,'sha256',v_hash));
  return v_new_id;
end;
$$;
revoke all on function public.admin_create_legal_version(uuid,text,text,text) from public,anon;
grant execute on function public.admin_create_legal_version(uuid,text,text,text) to authenticated;

alter table public.privacy_breach_incident_events enable row level security;
revoke all on public.privacy_breach_incident_events from anon,authenticated;

create or replace function private.reject_privacy_incident_event_mutation()
returns trigger language plpgsql set search_path=pg_catalog
as $$ begin raise exception 'Privacy incident event history is append-only'; end; $$;
create trigger privacy_breach_incident_events_append_only
before update or delete on public.privacy_breach_incident_events
for each row execute function private.reject_privacy_incident_event_mutation();

commit;

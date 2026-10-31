begin;

-- Ensure notifications have renderable content for the client without exposing
-- the private template registry.
alter table public.notifications
  add column if not exists title text,
  add column if not exists body text;

create or replace function private.populate_notification_content()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public
as $$
begin
  if new.title is null or new.body is null then
    select in_app_title,in_app_body into new.title,new.body
    from public.notification_templates where template_key=new.template_key;
  end if;
  return new;
end;
$$;
create trigger notification_content_defaults
before insert on public.notifications
for each row execute function private.populate_notification_content();

-- A verification request may be submitted by inserting the row or by moving
-- an existing not_submitted/needs_resubmission row back into the review queue.
create or replace function private.notify_verification_event()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_reviewer record; v_submission boolean:=false;
begin
  if tg_op='INSERT' then
    v_submission:=new.status in ('pending','under_review');
  elsif new.status is distinct from old.status then
    v_submission:=new.status in ('pending','under_review')
      and old.status in ('not_submitted','rejected','needs_resubmission','expired');
  end if;

  if v_submission then
    for v_reviewer in select ur.user_id from public.user_roles ur
      where ur.role='verification_reviewer' and ur.revoked_at is null
    loop
      perform private.enqueue_notification_event(v_reviewer.user_id,'verification.submitted',new.user_id,
        jsonb_build_object('verification_status',new.status),
        'verification-submitted-reviewer:'||new.user_id::text||':'||v_reviewer.user_id::text||':'||new.updated_at::text);
    end loop;
    perform private.enqueue_notification_event(new.user_id,'verification.submitted',new.user_id,
      jsonb_build_object('verification_status',new.status),
      'verification-submitted-user:'||new.user_id::text||':'||new.updated_at::text);
  elsif tg_op='UPDATE' and new.status is distinct from old.status then
    if new.status='verified' then
      perform private.enqueue_notification_event(new.user_id,'verification.approved',new.user_id,
        jsonb_build_object('verification_status',new.status),
        'verification-approved:'||new.user_id::text||':'||new.updated_at::text);
    elsif new.status in ('rejected','needs_resubmission') then
      perform private.enqueue_notification_event(new.user_id,'verification.rejected',new.user_id,
        jsonb_build_object('verification_status',new.status),
        'verification-rejected:'||new.user_id::text||':'||new.updated_at::text);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists verification_submitter_notification on public.user_verifications;

commit;

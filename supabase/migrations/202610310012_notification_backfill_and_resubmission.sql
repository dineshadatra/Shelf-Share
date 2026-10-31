begin;

update public.notifications n
set title=t.in_app_title,body=t.in_app_body
from public.notification_templates t
where t.template_key=n.template_key and (n.title is null or n.body is null);

create or replace function private.notify_verification_event()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_reviewer record; v_submission boolean:=false; v_event_nonce text:=gen_random_uuid()::text;
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
        'verification-submitted-reviewer:'||new.user_id::text||':'||v_reviewer.user_id::text||':'||v_event_nonce);
    end loop;
    perform private.enqueue_notification_event(new.user_id,'verification.submitted',new.user_id,
      jsonb_build_object('verification_status',new.status),
      'verification-submitted-user:'||new.user_id::text||':'||v_event_nonce);
  elsif tg_op='UPDATE' and new.status is distinct from old.status then
    if new.status='verified' then
      perform private.enqueue_notification_event(new.user_id,'verification.approved',new.user_id,
        jsonb_build_object('verification_status',new.status),
        'verification-approved:'||new.user_id::text||':'||v_event_nonce);
    elsif new.status in ('rejected','needs_resubmission') then
      perform private.enqueue_notification_event(new.user_id,'verification.rejected',new.user_id,
        jsonb_build_object('verification_status',new.status),
        'verification-rejected:'||new.user_id::text||':'||v_event_nonce);
    end if;
  end if;
  return new;
end;
$$;

commit;

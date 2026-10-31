begin;

-- Email and push providers are intentionally absent. Reject opt-in until a channel
-- adapter is implemented so users are not promised a delivery path that does not exist.
create or replace function private.reject_unconfigured_notification_channels()
returns trigger language plpgsql
set search_path=pg_catalog
as $$
begin
  if new.email_enabled or new.push_enabled then
    raise exception 'Email and push notifications are not enabled in this release';
  end if;
  return new;
end;
$$;
create trigger notification_channel_configuration_guard
before insert or update of email_enabled,push_enabled on public.notification_preferences
for each row execute function private.reject_unconfigured_notification_channels();

-- Conversation entries are immutable; corrections are new entries, not edits.
create trigger support_ticket_messages_append_only
before update or delete on public.support_ticket_messages
for each row execute function private.reject_support_history_mutation();

create unique index financial_cost_one_reversal_per_original_uq
  on public.financial_cost_entries(reverses_entry_id)
  where reverses_entry_id is not null;

create or replace function public.reverse_financial_cost_entry(
  p_original_entry_id uuid,p_occurred_at timestamptz,p_reason text,p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare
  v_user uuid:=auth.uid();
  v_original public.financial_cost_entries%rowtype;
  v_id uuid;
begin
  if v_user is null or not public.admin_has_permission('finance.costs.write')
    or coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
    raise exception 'Finance cost permission and MFA AAL2 required';
  end if;
  if length(btrim(coalesce(p_reason,'')))<20
    or length(btrim(coalesce(p_idempotency_key,''))) not between 20 and 160
    or p_occurred_at is null then raise exception 'A reason, date and idempotency key are required'; end if;
  select * into v_original from public.financial_cost_entries
    where id=p_original_entry_id and reverses_entry_id is null for update;
  if not found then raise exception 'Original cost entry not found'; end if;
  if exists(select 1 from public.financial_cost_entries where reverses_entry_id=v_original.id) then
    raise exception 'Cost entry has already been reversed';
  end if;
  insert into public.financial_cost_entries(
    cost_category,amount_paise,occurred_at,city_id,locality_id,vendor,
    source_type,source_reference,reason,idempotency_key,created_by,reverses_entry_id
  ) values (
    v_original.cost_category,v_original.amount_paise,p_occurred_at,v_original.city_id,
    v_original.locality_id,v_original.vendor,'cost_reversal',v_original.source_reference,
    left(p_reason,1000),p_idempotency_key,v_user,v_original.id
  ) returning id into v_id;
  insert into public.admin_audit_logs(actor_id,action,target_table,target_id,reason,before_data,after_data)
  values(v_user,'financial_cost_reversed','financial_cost_entries',v_original.id::text,left(p_reason,1000),
    jsonb_build_object('amount_paise',v_original.amount_paise,'category',v_original.cost_category),
    jsonb_build_object('reversal_entry_id',v_id,'amount_paise',v_original.amount_paise));
  return v_id;
end;
$$;
revoke all on function public.reverse_financial_cost_entry(uuid,timestamptz,text,text) from public,anon;
grant execute on function public.reverse_financial_cost_entry(uuid,timestamptz,text,text) to authenticated;

commit;

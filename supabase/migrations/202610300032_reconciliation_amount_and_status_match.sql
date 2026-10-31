begin;

-- A reconciliation row is MATCHED only if both amount and normalized status agree.
create or replace function public.record_provider_reconciliation(
  p_provider text,p_report_reference text,p_period_start timestamptz,p_period_end timestamptz,p_records jsonb
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare
  v_run uuid; v_record jsonb; v_type text; v_internal text; v_ref text;
  v_expected bigint; v_actual bigint; v_currency char(3); v_status text;
  v_expected_status text; v_match_status text;
  v_matched integer:=0; v_unmatched integer:=0;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_provider is null or p_period_start is null or p_period_end is null or p_period_end<=p_period_start
    or p_records is null or jsonb_typeof(p_records)<>'array' or jsonb_array_length(p_records)>10000 then
    raise exception 'Invalid reconciliation report';
  end if;
  if not exists(select 1 from public.payment_provider_approvals p where p.provider_code=p_provider
    and p.supports_reconciliation and (p.expires_at is null or p.expires_at>now())) then
    raise exception 'Provider reconciliation is not approved';
  end if;
  insert into public.payment_reconciliation_runs(provider,report_reference,period_start,period_end,status)
    values(p_provider,left(coalesce(p_report_reference,''),200),p_period_start,p_period_end,'started')
    returning id into v_run;

  for v_record in select value from jsonb_array_elements(p_records) loop
    v_type:=v_record->>'recordType';
    v_ref:=nullif(v_record->>'providerReference','');
    v_actual:=nullif(v_record->>'amountPaise','')::bigint;
    v_currency:=coalesce(v_record->>'currency','INR')::char(3);
    v_status:=nullif(lower(btrim(v_record->>'status')),'');
    v_internal:=nullif(v_record->>'internalReference','');
    v_expected:=nullif(v_record->>'expectedAmountPaise','')::bigint;
    v_expected_status:=null;
    v_match_status:='manual_review';

    if v_type is null or v_type not in ('payment','refund','payout','deposit','chargeback','settlement')
      or v_currency<>'INR' or (v_actual is not null and v_actual<0) then
      raise exception 'Unsupported reconciliation record';
    end if;

    if v_type='payment' then
      if v_ref is not null then
        select p.id::text,p.amount_paise,p.status::text into v_internal,v_expected,v_expected_status
          from public.payments p where p.provider=p_provider
            and (p.provider_payment_id=v_ref or p.merchant_reference=v_ref) limit 1;
      elsif v_internal is not null then
        select p.id::text,p.amount_paise,p.status::text into v_internal,v_expected,v_expected_status
          from public.payments p where p.provider=p_provider and p.id::text=v_internal limit 1;
      end if;
    elsif v_type='refund' then
      if v_ref is not null then
        select r.id::text,r.amount_paise,r.status into v_internal,v_expected,v_expected_status
          from public.refunds r where r.provider=p_provider and r.provider_refund_id=v_ref limit 1;
      elsif v_internal is not null then
        select r.id::text,r.amount_paise,r.status into v_internal,v_expected,v_expected_status
          from public.refunds r where r.provider=p_provider and r.id::text=v_internal limit 1;
      end if;
    elsif v_type='payout' then
      if v_ref is not null then
        select p.id::text,p.amount_paise,p.status::text into v_internal,v_expected,v_expected_status
          from public.payouts p where p.provider=p_provider and p.provider_transfer_id=v_ref limit 1;
      elsif v_internal is not null then
        select p.id::text,p.amount_paise,p.status::text into v_internal,v_expected,v_expected_status
          from public.payouts p where p.provider=p_provider and p.id::text=v_internal limit 1;
      end if;
    elsif v_type='deposit' then
      if v_ref is not null then
        select d.id::text,d.amount_paise,d.status::text into v_internal,v_expected,v_expected_status
          from public.deposits d where d.provider=p_provider and d.provider_reference=v_ref limit 1;
      elsif v_internal is not null then
        select d.id::text,d.amount_paise,d.status::text into v_internal,v_expected,v_expected_status
          from public.deposits d where d.provider=p_provider and d.id::text=v_internal limit 1;
      end if;
    elsif v_type='chargeback' then
      if v_ref is not null then
        select d.id::text,d.amount_paise,d.status into v_internal,v_expected,v_expected_status
          from public.payment_disputes d where d.provider=p_provider and d.provider_dispute_reference=v_ref limit 1;
      elsif v_internal is not null then
        select d.id::text,d.amount_paise,d.status into v_internal,v_expected,v_expected_status
          from public.payment_disputes d where d.provider=p_provider and d.id::text=v_internal limit 1;
      end if;
    end if;

    if v_internal is null then
      v_match_status:='missing_internal';
    elsif v_actual is null or v_status is null then
      v_match_status:='missing_provider';
    elsif v_expected is distinct from v_actual then
      v_match_status:='amount_mismatch';
    elsif v_type='settlement' then
      v_match_status:='manual_review';
    elsif v_expected_status is null or lower(v_expected_status)<>v_status then
      -- Provider adapters must normalize statuses to ShelfShare's internal
      -- canonical values; an unknown state is not a successful match.
      v_match_status:='status_mismatch';
    else
      v_match_status:='matched';
    end if;

    insert into public.payment_reconciliation_items(
      run_id,record_type,internal_reference,provider_reference,expected_amount_paise,
      provider_amount_paise,currency,match_status,details
    ) values (
      v_run,v_type,v_internal,v_ref,v_expected,v_actual,v_currency,v_match_status,
      jsonb_build_object('provider_status',v_status,'internal_status',v_expected_status,
        'source','provider_adapter','status_comparison','canonical_exact')
    );

    if v_match_status='matched' then v_matched:=v_matched+1; else v_unmatched:=v_unmatched+1; end if;
  end loop;

  update public.payment_reconciliation_runs set matched_count=v_matched,unmatched_count=v_unmatched,
    status=case when v_unmatched=0 then 'completed' else 'partial' end,completed_at=now()
    where id=v_run;
  return v_run;
end;
$$;
revoke all on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.record_provider_reconciliation(text,text,timestamptz,timestamptz,jsonb) to service_role;

commit;

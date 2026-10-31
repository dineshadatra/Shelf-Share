begin;

-- Finance-specific claim decisions replace the legacy broad admin/super-admin gate.
insert into public.admin_permission_catalog(permission_key,module_key,description,sensitivity)
values('claims.decide','claims','Decide evidence-backed rental damage claims','high_risk')
on conflict(permission_key) do update set description=excluded.description,sensitivity=excluded.sensitivity;
insert into public.admin_role_permissions(role,permission_key)
values('finance_operator','claims.decide')
on conflict do nothing;

create or replace function public.decide_rental_damage_claim(
  p_claim_id uuid,p_approved_compensation_paise bigint,p_decision_code text,p_decision_reason text
) returns void language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare
  v_actor uuid:=auth.uid();
  v_claim public.rental_damage_claims%rowtype;
  v_booking public.bookings%rowtype;
  v_reader_responded boolean;
  v_evidence_count integer;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'claims.decide') then
    raise exception 'Finance claim decision permission and MFA AAL2 required';
  end if;
  if p_approved_compensation_paise<0
    or length(btrim(coalesce(p_decision_code,'')))<3
    or length(btrim(coalesce(p_decision_reason,'')))<30 then
    raise exception 'A bounded amount, decision code and reasoned explanation are required';
  end if;
  select * into v_claim from public.rental_damage_claims where id=p_claim_id for update;
  if not found or v_claim.status not in ('submitted','awaiting_response','under_review') then
    raise exception 'Claim is not awaiting decision';
  end if;
  if v_actor in (v_claim.claimant_id,v_claim.respondent_id) then
    raise exception 'A rental participant cannot adjudicate their own claim';
  end if;
  if p_approved_compensation_paise>v_claim.requested_compensation_paise then
    raise exception 'Decision cannot exceed the amount requested';
  end if;
  select * into v_booking from public.bookings where id=v_claim.booking_id;
  select exists(
    select 1 from public.rental_case_messages
    where case_type='claim' and case_id=p_claim_id and sender_id=v_claim.respondent_id
  ) into v_reader_responded;
  if not v_reader_responded and now()<v_claim.response_due_at then
    raise exception 'Respondent response window is still open';
  end if;
  select count(*) into v_evidence_count from public.rental_case_evidence
    where case_type in ('claim','dispute') and case_id in (p_claim_id,v_claim.dispute_id);
  if v_evidence_count<1 then raise exception 'At least one case evidence item is required before decision'; end if;

  update public.rental_damage_claims set
    status=case when p_approved_compensation_paise=0 then 'rejected'
      when p_approved_compensation_paise=requested_compensation_paise then 'approved' else 'partially_approved' end,
    approved_compensation_paise=p_approved_compensation_paise,decision_by=v_actor,
    decision_code=left(p_decision_code,100),decision_reason=left(p_decision_reason,4000),decided_at=now()
  where id=p_claim_id;
  update public.disputes set status='decided',decision_code=left(p_decision_code,100),
    decision_notes=left(p_decision_reason,4000),assigned_to=v_actor,decided_at=now()
  where id=v_claim.dispute_id;

  insert into public.rental_operations_events(booking_id,actor_id,event_type,reason_code,details,idempotency_key)
  values(v_claim.booking_id,v_actor,'damage_claim_decided',p_decision_code,
    jsonb_build_object('claim_id',p_claim_id,'requested_paise',v_claim.requested_compensation_paise,
      'approved_paise',p_approved_compensation_paise,'automatic_deduction',false,'deposit_applied',false),
    'damage-claim-decision:'||p_claim_id::text)
  on conflict(idempotency_key) do nothing;
  insert into public.admin_audit_logs(actor_id,action,target_table,target_id,reason,before_data,after_data)
  values(v_actor,'damage_claim_decided','rental_damage_claims',p_claim_id::text,left(p_decision_reason,1000),
    jsonb_build_object('status',v_claim.status,'approved_compensation_paise',v_claim.approved_compensation_paise),
    jsonb_build_object('status',case when p_approved_compensation_paise=0 then 'rejected'
      when p_approved_compensation_paise=v_claim.requested_compensation_paise then 'approved' else 'partially_approved' end,
      'approved_compensation_paise',p_approved_compensation_paise,'automatic_deduction',false));
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,
    outcome,reason,request_id,metadata)
  values(v_actor,'damage_claim_decided','claims','claims.decide','rental_damage_claims',p_claim_id::text,
    'success',left(p_decision_reason,500),gen_random_uuid()::text,
    jsonb_build_object('approved_compensation_paise',p_approved_compensation_paise,'deposit_applied',false));
  insert into public.notifications(user_id,channel,template_key,payload)
  values(v_claim.claimant_id,'in_app','rental.claim_decided',jsonb_build_object('claim_id',p_claim_id,'approved_compensation_paise',p_approved_compensation_paise)),
    (v_claim.respondent_id,'in_app','rental.claim_decided',jsonb_build_object('claim_id',p_claim_id,'approved_compensation_paise',p_approved_compensation_paise));
end;
$$;
revoke all on function public.decide_rental_damage_claim(uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.decide_rental_damage_claim(uuid,bigint,text,text) to authenticated;

-- Appeals and suspensions are no longer available to the broad admin role.
create or replace function public.decide_rental_appeal(
  p_appeal_id uuid,p_outcome text,p_decision_code text,p_decision_reason text,
  p_revised_compensation_paise bigint default null
) returns void language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare
  v_actor uuid:=auth.uid();
  v_appeal public.rental_appeals%rowtype;
  v_claim public.rental_damage_claims%rowtype;
  v_booking public.bookings%rowtype;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'disputes.finalize.approve') then
    raise exception 'Finance dispute appeal permission and MFA AAL2 required';
  end if;
  if p_outcome not in ('upheld','revised','dismissed')
    or length(btrim(coalesce(p_decision_code,'')))<3
    or length(btrim(coalesce(p_decision_reason,'')))<30 then
    raise exception 'A reasoned appeal outcome is required';
  end if;
  select * into v_appeal from public.rental_appeals where id=p_appeal_id for update;
  if not found or v_appeal.status not in ('submitted','under_review') then
    raise exception 'Appeal is not awaiting review';
  end if;
  select * into v_booking from public.bookings where id=v_appeal.booking_id;
  if v_actor in (v_booking.reader_id,v_booking.owner_id) then
    raise exception 'A rental participant cannot adjudicate their own appeal';
  end if;
  if v_appeal.case_type='claim' then
    select * into v_claim from public.rental_damage_claims where id=v_appeal.case_id for update;
    if not found then raise exception 'Original claim not found'; end if;
    if p_outcome='revised' then
      if p_revised_compensation_paise is null or p_revised_compensation_paise<0
        or p_revised_compensation_paise>v_claim.requested_compensation_paise then
        raise exception 'Revised compensation must be between zero and the evidence-backed requested amount';
      end if;
      update public.rental_damage_claims set
        approved_compensation_paise=p_revised_compensation_paise,
        status=case when p_revised_compensation_paise=0 then 'rejected'
          when p_revised_compensation_paise=requested_compensation_paise then 'approved' else 'partially_approved' end,
        decision_by=v_actor,decision_code=left(p_decision_code,100),
        decision_reason=left(p_decision_reason,4000),decided_at=now()
      where id=v_claim.id;
    elsif p_outcome in ('upheld','dismissed') then
      update public.rental_damage_claims set status=case when approved_compensation_paise=0 then 'rejected'
        when approved_compensation_paise=requested_compensation_paise then 'approved' else 'partially_approved' end
      where id=v_claim.id;
    end if;
  end if;
  if v_appeal.case_type='claim' then
    update public.disputes set status='decided' where id=v_claim.dispute_id;
  else
    update public.disputes set status='decided' where id=v_appeal.case_id;
  end if;
  update public.rental_appeals set status=p_outcome,reviewer_id=v_actor,
    decision_code=left(p_decision_code,100),decision_reason=left(p_decision_reason,4000),decided_at=now()
  where id=p_appeal_id;

  insert into public.rental_operations_events(booking_id,actor_id,event_type,reason_code,details,idempotency_key)
  values(v_appeal.booking_id,v_actor,'appeal_decided',p_decision_code,
    jsonb_build_object('appeal_id',p_appeal_id,'case_type',v_appeal.case_type,'case_id',v_appeal.case_id,
      'outcome',p_outcome,'revised_compensation_paise',p_revised_compensation_paise,
      'automatic_deduction',false,'deposit_applied',false),
    'appeal-decision:'||p_appeal_id::text)
  on conflict(idempotency_key) do nothing;
  insert into public.admin_audit_logs(actor_id,action,target_table,target_id,reason,after_data)
  values(v_actor,'rental_appeal_decided','rental_appeals',p_appeal_id::text,left(p_decision_reason,1000),
    jsonb_build_object('outcome',p_outcome,'decision_code',p_decision_code,'compensation_paise',p_revised_compensation_paise));
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,
    outcome,reason,request_id,metadata)
  values(v_actor,'rental_appeal_decided','disputes','disputes.finalize.approve','rental_appeals',p_appeal_id::text,
    'success',left(p_decision_reason,500),gen_random_uuid()::text,
    jsonb_build_object('outcome',p_outcome,'case_type',v_appeal.case_type));
  insert into public.notifications(user_id,channel,template_key,payload)
  values(v_booking.reader_id,'in_app','rental.appeal_decided',jsonb_build_object('appeal_id',p_appeal_id,'outcome',p_outcome)),
    (v_booking.owner_id,'in_app','rental.appeal_decided',jsonb_build_object('appeal_id',p_appeal_id,'outcome',p_outcome));
end;
$$;
revoke all on function public.decide_rental_appeal(uuid,text,text,text,bigint) from public,anon,authenticated;
grant execute on function public.decide_rental_appeal(uuid,text,text,text,bigint) to authenticated;

create or replace function public.admin_set_user_account_status(
  p_user_id uuid,p_new_status public.account_status,p_reason_code text,p_reason text,p_expires_at timestamptz default null
) returns uuid language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare
  v_actor uuid:=auth.uid();
  v_profile public.profiles%rowtype;
  v_active_count integer;
  v_id uuid;
  v_booking record;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2'
    or not private.admin_can(v_actor,'users.suspend.approve') then
    raise exception 'Super-admin account-status permission and MFA AAL2 required';
  end if;
  if p_new_status not in ('active','restricted','suspended')
    or length(btrim(coalesce(p_reason_code,'')))<3
    or length(btrim(coalesce(p_reason,'')))<20 then
    raise exception 'Valid account status and documented reason are required';
  end if;
  select * into v_profile from public.profiles where id=p_user_id for update;
  if not found then raise exception 'User profile not found'; end if;
  select count(*) into v_active_count from public.bookings
  where (reader_id=p_user_id or owner_id=p_user_id)
    and status in ('owner_accepted','payment_pending','confirmed','collection_pending','active','return_pending','disputed');
  update public.profiles set account_status=p_new_status where id=p_user_id;
  insert into public.user_suspensions(user_id,previous_status,new_status,reason_code,reason,expires_at,actor_id,active_rentals_preserved)
  values(p_user_id,v_profile.account_status,p_new_status,left(p_reason_code,100),left(p_reason,2000),p_expires_at,v_actor,v_active_count)
  returning id into v_id;
  for v_booking in
    select id,case when reader_id=p_user_id then owner_id else reader_id end as other_party
    from public.bookings
    where (reader_id=p_user_id or owner_id=p_user_id)
      and status in ('owner_accepted','payment_pending','confirmed','collection_pending','active','return_pending','disputed')
  loop
    insert into public.rental_operations_events(booking_id,actor_id,event_type,reason_code,details,idempotency_key)
    values(v_booking.id,v_actor,'participant_account_status_changed',p_reason_code,
      jsonb_build_object('suspended_user_id',p_user_id,'new_status',p_new_status::text,'active_obligation_preserved',true),
      'account-status:'||v_id::text||':'||v_booking.id::text)
    on conflict(idempotency_key) do nothing;
    insert into public.notifications(user_id,channel,template_key,payload)
    values(v_booking.other_party,'in_app','safety.participant_account_restricted',
      jsonb_build_object('booking_id',v_booking.id,'support_ticket_required',true));
  end loop;
  insert into public.admin_audit_logs(actor_id,action,target_table,target_id,reason,before_data,after_data)
  values(v_actor,'account_status_changed','profiles',p_user_id::text,left(p_reason,1000),
    jsonb_build_object('account_status',v_profile.account_status::text),
    jsonb_build_object('account_status',p_new_status::text,'active_rentals_preserved',v_active_count,'suspension_id',v_id));
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,
    outcome,reason,request_id,metadata)
  values(v_actor,'account_status_changed','users','users.suspend.approve','profiles',p_user_id::text,
    'success',left(p_reason,500),gen_random_uuid()::text,
    jsonb_build_object('new_status',p_new_status::text,'active_rentals_preserved',v_active_count));
  return v_id;
end;
$$;
revoke all on function public.admin_set_user_account_status(uuid,public.account_status,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.admin_set_user_account_status(uuid,public.account_status,text,text,timestamptz) to authenticated;

-- Moderator actions update data and write immutable audit records in one transaction.
create or replace function public.admin_moderate_content(
  p_module_key text,p_target_id uuid,p_status text,p_reason text
) returns void language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare
  v_actor uuid:=auth.uid();
  v_permission text;
  v_table text;
  v_field text;
  v_old_status text;
  v_actor_owns boolean:=false;
begin
  if v_actor is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
    raise exception 'Authenticated moderator and MFA AAL2 required';
  end if;
  case p_module_key
    when 'catalogue' then
      v_permission:='catalogue.moderate'; v_table:='book_titles'; v_field:='moderation_status';
      if p_status not in ('approved','rejected','pending_review') then raise exception 'Invalid catalogue status'; end if;
      select moderation_status into v_old_status from public.book_titles where id=p_target_id for update;
    when 'copies' then
      v_permission:='inventory.moderate'; v_table:='book_copies'; v_field:='listing_status';
      if p_status not in ('approved','rejected','paused','removed') then raise exception 'Invalid copy status'; end if;
      select listing_status::text,owner_id=v_actor into v_old_status,v_actor_owns from public.book_copies where id=p_target_id for update;
      if v_actor_owns then raise exception 'A copy owner cannot moderate their own listing'; end if;
    when 'community' then
      v_permission:='community.moderate'; v_table:='community_posts'; v_field:='status';
      if p_status not in ('published','hidden','removed','draft') then raise exception 'Invalid community status'; end if;
      select status::text,author_id=v_actor into v_old_status,v_actor_owns from public.community_posts where id=p_target_id for update;
      if v_actor_owns then raise exception 'A post author cannot moderate their own post'; end if;
    when 'reviews' then
      v_permission:='reviews.moderate'; v_table:='reviews'; v_field:='status';
      if p_status not in ('published','hidden','removed','pending_moderation') then raise exception 'Invalid review status'; end if;
      select status,reviewer_id=v_actor or reviewee_id=v_actor into v_old_status,v_actor_owns from public.reviews where id=p_target_id for update;
      if v_actor_owns then raise exception 'A review participant cannot moderate the review'; end if;
    else raise exception 'Unsupported moderation module';
  end case;
  if v_old_status is null then raise exception 'Moderation target not found'; end if;
  if not private.admin_can(v_actor,v_permission) then raise exception 'Moderation permission denied'; end if;
  if length(btrim(coalesce(p_reason,'')))<20 then raise exception 'A reason of at least 20 characters is required'; end if;

  if p_module_key='catalogue' then
    update public.book_titles set moderation_status=p_status where id=p_target_id;
  elsif p_module_key='copies' then
    update public.book_copies set listing_status=p_status::public.listing_status,
      is_available_for_rent=case when p_status='approved' then is_available_for_rent else false end
    where id=p_target_id;
  elsif p_module_key='community' then
    update public.community_posts set status=p_status::public.community_content_status,
      published_at=case when p_status='published' then coalesce(published_at,now()) else published_at end
    where id=p_target_id;
  elsif p_module_key='reviews' then
    update public.reviews set status=p_status,published_at=case when p_status='published' then coalesce(published_at,now()) else published_at end
    where id=p_target_id;
  end if;

  insert into public.admin_audit_logs(actor_id,action,target_table,target_id,reason,before_data,after_data)
  values(v_actor,'admin_moderation_update',v_table,p_target_id::text,left(p_reason,1000),
    jsonb_build_object(v_field,v_old_status),jsonb_build_object(v_field,p_status));
  insert into public.admin_activity_events(actor_id,action,module_key,permission_key,target_table,target_id,
    outcome,reason,request_id,metadata)
  values(v_actor,'content_moderated',p_module_key,v_permission,v_table,p_target_id::text,
    'success',left(p_reason,500),gen_random_uuid()::text,jsonb_build_object('field',v_field,'status',p_status));
end;
$$;
revoke all on function public.admin_moderate_content(text,uuid,text,text) from public,anon;
grant execute on function public.admin_moderate_content(text,uuid,text,text) to authenticated;

commit;

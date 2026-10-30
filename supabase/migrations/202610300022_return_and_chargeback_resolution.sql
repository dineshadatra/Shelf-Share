begin;

create or replace function public.request_book_return(p_booking_id uuid)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid:=auth.uid(); v_booking public.bookings%rowtype;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_actor not in (v_booking.reader_id,v_booking.owner_id) then
    raise exception 'Booking participant required';
  end if;
  if v_booking.status='return_pending' then return; end if;
  if v_booking.status<>'active' then raise exception 'Only an active rental can enter return workflow'; end if;
  update public.bookings set status='return_pending' where id=p_booking_id;
  insert into public.booking_audit_events(booking_id,actor_id,event_type,from_status,to_status,metadata,idempotency_key)
    values(p_booking_id,v_actor,'return_requested','active','return_pending','{}'::jsonb,'return-request:'||p_booking_id::text)
    on conflict(idempotency_key) do nothing;
  insert into public.notifications(user_id,channel,template_key,payload)
    values(case when v_actor=v_booking.reader_id then v_booking.owner_id else v_booking.reader_id end,
      'in_app','booking.return_requested',jsonb_build_object('booking_id',p_booking_id));
end;
$$;
revoke all on function public.request_book_return(uuid) from public,anon;
grant execute on function public.request_book_return(uuid) to authenticated;

create or replace function public.get_my_booking_workspace()
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare v_user uuid:=auth.uid(); v_rows jsonb;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select coalesce(jsonb_agg(x order by (x->>'created_at') desc),'[]'::jsonb) into v_rows
  from (
    select jsonb_build_object(
      'id',b.id,'booking_number',b.booking_number,'status',b.status,
      'reader_id',b.reader_id,'owner_id',b.owner_id,'is_reader',(b.reader_id=v_user),
      'requested_start_at',b.requested_start_at,'requested_end_at',b.requested_end_at,
      'requested_duration_days',b.requested_duration_days,'rent_subtotal_paise',b.rent_subtotal_paise,
      'platform_fee_paise',b.platform_fee_paise,'tax_paise',b.tax_paise,
      'deposit_required_paise',b.deposit_required_paise,'total_due_paise',b.total_due_paise,
      'created_at',b.created_at,'accepted_at',b.accepted_at,'completed_at',b.completed_at,
      'cancellation_reason_code',b.cancellation_reason_code,'title',t.title,'authors',t.authors,
      'copy_id',c.id,'condition',c.condition_summary,'city_id',b.city_id,'locality_id',c.locality_id,
      'handover_location_id',b.requested_handover_location_id,'handover_location',h.name,
      'payment_status',(select p.status from public.payments p where p.booking_id=b.id order by p.created_at desc limit 1),
      'payment_amount_paise',(select p.amount_paise from public.payments p where p.booking_id=b.id order by p.created_at desc limit 1),
      'checkout_url',case when b.reader_id=v_user then
        (select p.provider_checkout_url from public.payments p where p.booking_id=b.id order by p.created_at desc limit 1)
        else null end,
      'owner_agreement_accepted',exists(
        select 1 from public.rental_agreements ra join public.legal_documents ld on ld.id=ra.legal_document_id
        where ra.booking_id=b.id and ra.user_id=b.owner_id and ra.document_version=ld.version
          and ld.document_type='rental_agreement' and ld.is_published and ld.effective_from<=now()
          and (ld.effective_until is null or ld.effective_until>now())
      ),
      'reader_agreement_accepted',exists(
        select 1 from public.rental_agreements ra join public.legal_documents ld on ld.id=ra.legal_document_id
        where ra.booking_id=b.id and ra.user_id=b.reader_id and ra.document_version=ld.version
          and ld.document_type='rental_agreement' and ld.is_published and ld.effective_from<=now()
          and (ld.effective_until is null or ld.effective_until>now())
      ),
      'rental_start_at',b.rental_start_at,'rental_due_at',b.rental_due_at,
      'active_handover',(select jsonb_build_object(
        'id',s.id,'type',s.handover_type,'expires_at',s.expires_at,'status',s.status,
        'created_at',s.created_at,'completed_at',s.completed_at,'initiator_id',s.initiator_id,
        'qr_consumed_at',s.qr_consumed_at,'owner_confirmed',s.owner_confirmed_at is not null,
        'reader_confirmed',s.reader_confirmed_at is not null,
        'owner_condition_confirmed',s.owner_condition_confirmed_at is not null,
        'reader_condition_confirmed',s.reader_condition_confirmed_at is not null,
        'owner_photo_count',(select count(*) from public.rental_condition_photos p where p.handover_session_id=s.id and p.submitted_by=b.owner_id),
        'reader_photo_count',(select count(*) from public.rental_condition_photos p where p.handover_session_id=s.id and p.submitted_by=b.reader_id)
      ) from public.handover_sessions s where s.booking_id=b.id order by s.created_at desc limit 1)
    ) as x
    from public.bookings b
    left join public.book_copies c on c.id=b.requested_copy_id
    left join public.book_titles t on t.id=c.book_title_id
    left join public.handover_locations h on h.id=b.requested_handover_location_id
    where b.reader_id=v_user or b.owner_id=v_user
  ) q;
  return v_rows;
end;
$$;
revoke all on function public.get_my_booking_workspace() from public,anon;
grant execute on function public.get_my_booking_workspace() to authenticated;

-- Chargeback outcomes are provider-sourced events, separate from member reports
-- or internal rental disputes. A win can restore eligibility; a loss stays under
-- reconciliation and never triggers an arbitrary deposit deduction.
create or replace function public.apply_verified_chargeback_resolution(
  p_provider text,p_event_id text,p_payment_id uuid,p_dispute_reference text,
  p_result text,p_amount_paise bigint,p_currency char(3),p_payload_sha256 text
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_payment public.payments%rowtype; v_dispute public.payment_disputes%rowtype; v_count bigint;
begin
  if coalesce(current_setting('role',true),'')<>'service_role' then raise exception 'Trusted backend required'; end if;
  if p_event_id is null or p_payload_sha256 is null or p_payload_sha256 !~ '^[a-f0-9]{64}$'
    or p_result not in ('won','lost') then raise exception 'Invalid verified chargeback resolution'; end if;
  insert into public.payment_events(payment_id,provider,provider_event_id,event_type,signature_valid,payload_sha256)
    values(p_payment_id,p_provider,p_event_id,'chargeback.'||p_result,true,p_payload_sha256)
    on conflict(provider,provider_event_id) do nothing;
  get diagnostics v_count=row_count;
  if v_count=0 then return jsonb_build_object('duplicate',true); end if;
  select * into v_payment from public.payments where id=p_payment_id and provider=p_provider for update;
  if not found or p_currency<>'INR' or p_amount_paise<=0 or p_amount_paise>v_payment.amount_paise then
    update public.payment_events set processing_status='dead_letter',processing_error_code='chargeback_reference_or_amount_mismatch',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','chargeback_reference_or_amount_mismatch');
  end if;
  select * into v_dispute from public.payment_disputes
    where payment_id=p_payment_id and provider=p_provider and provider_dispute_reference=p_dispute_reference
    for update;
  if not found then
    update public.payment_events set processing_status='dead_letter',processing_error_code='chargeback_not_found',processed_at=now()
      where provider=p_provider and provider_event_id=p_event_id;
    return jsonb_build_object('accepted',false,'reason','chargeback_not_found');
  end if;
  if p_result='won' then
    update public.payment_disputes set status='won',closed_at=coalesce(closed_at,now()) where id=v_dispute.id;
    if not exists(select 1 from public.payment_disputes d where d.payment_id=p_payment_id and d.id<>v_dispute.id and d.status not in ('won','closed')) then
      update public.payments set status=case when exists(select 1 from public.refunds r where r.payment_id=p_payment_id and r.status='succeeded')
        then 'partially_refunded'::public.payment_status else 'captured'::public.payment_status end where id=p_payment_id;
      update public.owner_earnings set status='eligible' where booking_id=v_payment.booking_id and status='reconciliation_required';
    end if;
  else
    update public.payment_disputes set status='lost',closed_at=coalesce(closed_at,now()) where id=v_dispute.id;
    update public.payments set status='reconciliation_required' where id=p_payment_id;
    update public.owner_earnings set status='reconciliation_required' where booking_id=v_payment.booking_id;
    update public.bookings set status='disputed' where id=v_payment.booking_id;
  end if;
  update public.payment_events set processing_status='processed',processed_at=now()
    where provider=p_provider and provider_event_id=p_event_id;
  return jsonb_build_object('accepted',true,'result',p_result);
end;
$$;
revoke all on function public.apply_verified_chargeback_resolution(text,text,uuid,text,text,bigint,char,text) from public,anon,authenticated;
grant execute on function public.apply_verified_chargeback_resolution(text,text,uuid,text,text,bigint,char,text) to service_role;

commit;

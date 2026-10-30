begin;

-- Authenticated users may read only their own profile and update a narrow allowlist of fields.
alter table public.profiles enable row level security;
create policy profiles_select_self on public.profiles for select to authenticated using (id = auth.uid());
create policy profiles_update_self on public.profiles for update to authenticated
using (id = auth.uid()) with check (id = auth.uid());
revoke update on public.profiles from authenticated;
grant update (display_name, avatar_object_key, bio, preferred_city_id, locale) on public.profiles to authenticated;

-- Reference data: only active/published records are visible to public clients.
alter table public.cities enable row level security;
create policy cities_read_active on public.cities for select to anon, authenticated using (is_active and status = 'active');
alter table public.localities enable row level security;
create policy localities_read_active on public.localities for select to anon, authenticated using (is_active and exists (
  select 1 from public.cities c where c.id = city_id and c.is_active and c.status = 'active'
));
alter table public.handover_locations enable row level security;
create policy handover_locations_read_active on public.handover_locations for select to anon, authenticated using (status = 'active');
revoke select on public.handover_locations from anon, authenticated;
grant select (id, locality_id, city_id, name, description, public_address, latitude, longitude, opening_hours, status)
  on public.handover_locations to anon, authenticated;

alter table public.user_roles enable row level security;
alter table public.user_verifications enable row level security;
create policy verification_read_self on public.user_verifications for select to authenticated using (user_id = auth.uid());
revoke select on public.user_verifications from authenticated;
grant select (user_id, status, age_eligible, phone_verified_at, identity_verified_at, address_verified_at, policy_version, created_at, updated_at)
  on public.user_verifications to authenticated;
alter table public.identity_documents enable row level security;
alter table public.verification_audit enable row level security;
-- No direct client policies for identity documents, verification history or role assignments.

-- Catalogue
alter table public.book_titles enable row level security;
create policy book_titles_read_approved on public.book_titles for select to anon, authenticated using (moderation_status = 'approved');
alter table public.categories enable row level security;
create policy categories_read_active on public.categories for select to anon, authenticated using (is_active);
alter table public.book_title_categories enable row level security;
create policy title_categories_read_approved on public.book_title_categories for select to anon, authenticated using (
  exists (select 1 from public.book_titles bt where bt.id = book_title_id and bt.moderation_status = 'approved')
);
alter table public.book_copies enable row level security;
create policy book_copies_read_approved on public.book_copies for select to anon, authenticated using (listing_status = 'approved' and is_available_for_rent);
create policy book_copies_owner_read on public.book_copies for select to authenticated using (owner_id = auth.uid());
create policy book_copies_owner_insert on public.book_copies for insert to authenticated with check (
  owner_id = auth.uid() and listing_status = 'draft' and not is_available_for_rent
  and exists (
    select 1 from public.user_verifications v
    where v.user_id = auth.uid() and v.status = 'verified' and v.age_eligible is true
  )
);
create policy book_copies_owner_update on public.book_copies for update to authenticated
using (owner_id = auth.uid()) with check (owner_id = auth.uid());
revoke insert, update on public.book_copies from authenticated;
grant insert (book_title_id, owner_id, city_id, locality_id, owner_reference, condition_summary, description, acquisition_year)
  on public.book_copies to authenticated;
grant update (owner_reference, condition_summary, description, acquisition_year)
  on public.book_copies to authenticated;
alter table public.book_images enable row level security;
create policy book_images_read_approved on public.book_images for select to anon, authenticated using (
  moderation_status = 'approved' and exists (
    select 1 from public.book_copies c where c.id = book_copy_id and c.listing_status = 'approved'
  )
);
alter table public.book_condition_records enable row level security;
alter table public.book_availability_blocks enable row level security;
alter table public.book_pricing enable row level security;
create policy book_pricing_read_current on public.book_pricing for select to anon, authenticated using (
  effective_from <= now() and (effective_until is null or effective_until > now()) and exists (
    select 1 from public.book_copies c where c.id = book_copy_id and c.listing_status = 'approved'
  )
);

alter table public.wishlists enable row level security;
create policy wishlists_owner_all on public.wishlists for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
alter table public.wishlist_items enable row level security;
create policy wishlist_items_owner_all on public.wishlist_items for all to authenticated using (
  exists (select 1 from public.wishlists w where w.id = wishlist_id and w.user_id = auth.uid())
) with check (
  exists (select 1 from public.wishlists w where w.id = wishlist_id and w.user_id = auth.uid())
);
alter table public.book_recommendations enable row level security;
create policy recommendations_read_self on public.book_recommendations for select to authenticated using (user_id = auth.uid());

-- Booking and financial tables: authenticated clients get participant-scoped reads only.
alter table public.bookings enable row level security;
create policy bookings_participant_read on public.bookings for select to authenticated using (reader_id = auth.uid() or owner_id = auth.uid());
alter table public.rental_items enable row level security;
create policy rental_items_participant_read on public.rental_items for select to authenticated using (
  exists (select 1 from public.bookings b where b.id = booking_id and (b.reader_id = auth.uid() or b.owner_id = auth.uid()))
);
alter table public.copy_reservations enable row level security;
alter table public.rental_agreements enable row level security;
create policy rental_agreements_participant_read on public.rental_agreements for select to authenticated using (user_id = auth.uid());
alter table public.rental_condition_photos enable row level security;
create policy rental_photos_submitter_read on public.rental_condition_photos for select to authenticated using (submitted_by = auth.uid());
alter table public.handover_sessions enable row level security;
alter table public.handover_events enable row level security;

alter table public.payments enable row level security;
create policy payments_payer_read on public.payments for select to authenticated using (payer_id = auth.uid());
revoke select on public.payments from authenticated;
grant select (id, booking_id, amount_paise, currency, status, captured_at, created_at)
  on public.payments to authenticated;
alter table public.payment_events enable row level security;
alter table public.deposits enable row level security;
create policy deposits_payer_read on public.deposits for select to authenticated using (payer_id = auth.uid());
revoke select on public.deposits from authenticated;
grant select (id, booking_id, amount_paise, currency, status, created_at, updated_at)
  on public.deposits to authenticated;
alter table public.deposit_ledger enable row level security;
alter table public.deposit_release_requests enable row level security;
alter table public.commission_ledger enable row level security;
alter table public.owner_earnings enable row level security;
create policy owner_earnings_owner_read on public.owner_earnings for select to authenticated using (owner_id = auth.uid());
revoke select on public.owner_earnings from authenticated;
grant select (id, booking_id, gross_rent_paise, commission_paise, tax_withheld_paise, net_payable_paise, status, eligible_at, created_at)
  on public.owner_earnings to authenticated;
alter table public.payouts enable row level security;
create policy payouts_owner_read on public.payouts for select to authenticated using (owner_id = auth.uid());
revoke select on public.payouts from authenticated;
grant select (id, owner_earning_id, amount_paise, currency, status, initiated_at, settled_at, created_at)
  on public.payouts to authenticated;
alter table public.refunds enable row level security;
alter table public.late_fees enable row level security;
alter table public.financial_accounts enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;
-- No direct client writes and no direct client reads for provider payloads, ledgers, or journals.

-- Trust, chat and community
alter table public.disputes enable row level security;
create policy disputes_participant_read on public.disputes for select to authenticated using (
  opened_by = auth.uid() or against_user_id = auth.uid()
);
alter table public.dispute_evidence enable row level security;
alter table public.chat_conversations enable row level security;
alter table public.chat_participants enable row level security;
create policy chat_participants_self_read on public.chat_participants for select to authenticated using (user_id = auth.uid());
alter table public.chat_messages enable row level security;
create policy chat_messages_participant_read on public.chat_messages for select to authenticated using (
  exists (select 1 from public.chat_participants cp where cp.conversation_id = conversation_id and cp.user_id = auth.uid() and cp.left_at is null)
);
create policy chat_messages_participant_insert on public.chat_messages for insert to authenticated with check (
  sender_id = auth.uid() and exists (
    select 1 from public.chat_participants cp where cp.conversation_id = conversation_id and cp.user_id = auth.uid() and cp.left_at is null
  )
);
alter table public.user_reports enable row level security;
create policy user_reports_reporter_read on public.user_reports for select to authenticated using (reporter_id = auth.uid());
create policy user_reports_reporter_insert on public.user_reports for insert to authenticated with check (reporter_id = auth.uid());
alter table public.user_blocks enable row level security;
create policy user_blocks_owner_all on public.user_blocks for all to authenticated using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());

alter table public.reviews enable row level security;
create policy reviews_published_read on public.reviews for select to anon, authenticated using (status = 'published');
create policy reviews_reviewer_read on public.reviews for select to authenticated using (reviewer_id = auth.uid());
create policy reviews_eligible_insert on public.reviews for insert to authenticated with check (reviewer_id = auth.uid() and status = 'pending_moderation');
revoke insert, update, delete on public.reviews from authenticated;
grant insert (rental_item_id, reviewer_id, reviewee_id, rating, review_text) on public.reviews to authenticated;
-- Trigger in prior migration enforces completed rental and both-party relationship.

alter table public.referrals enable row level security;
create policy referrals_participant_read on public.referrals for select to authenticated using (referrer_id = auth.uid() or referred_user_id = auth.uid());
alter table public.referral_rewards enable row level security;
create policy referral_rewards_beneficiary_read on public.referral_rewards for select to authenticated using (beneficiary_id = auth.uid());

alter table public.community_posts enable row level security;
create policy community_posts_published_read on public.community_posts for select to anon, authenticated using (status = 'published');
create policy community_posts_author_read on public.community_posts for select to authenticated using (author_id = auth.uid());
create policy community_posts_author_insert on public.community_posts for insert to authenticated with check (author_id = auth.uid() and status = 'draft');
create policy community_posts_author_update on public.community_posts for update to authenticated using (author_id = auth.uid()) with check (author_id = auth.uid());
revoke insert, update on public.community_posts from authenticated;
grant insert (author_id, title, body) on public.community_posts to authenticated;
grant update (title, body) on public.community_posts to authenticated;
alter table public.community_comments enable row level security;
create policy community_comments_published_read on public.community_comments for select to anon, authenticated using (status = 'published');
create policy community_comments_author_insert on public.community_comments for insert to authenticated with check (author_id = auth.uid());
create policy community_comments_author_update on public.community_comments for update to authenticated using (author_id = auth.uid()) with check (author_id = auth.uid());
alter table public.reading_lists enable row level security;
create policy reading_lists_owner_all on public.reading_lists for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
alter table public.reading_list_items enable row level security;
create policy reading_list_items_owner_all on public.reading_list_items for all to authenticated using (
  exists (select 1 from public.reading_lists rl where rl.id = reading_list_id and rl.owner_id = auth.uid())
) with check (
  exists (select 1 from public.reading_lists rl where rl.id = reading_list_id and rl.owner_id = auth.uid())
);
alter table public.challenges enable row level security;
create policy challenges_published_read on public.challenges for select to anon, authenticated using (status in ('published','active','completed'));
alter table public.challenge_participants enable row level security;
create policy challenge_participants_self_read on public.challenge_participants for select to authenticated using (user_id = auth.uid());
create policy challenge_participants_self_insert on public.challenge_participants for insert to authenticated with check (user_id = auth.uid());

alter table public.book_exchange_requests enable row level security;
create policy exchange_participant_read on public.book_exchange_requests for select to authenticated using (requester_id = auth.uid() or target_owner_id = auth.uid());
alter table public.exchange_transactions enable row level security;
create policy exchange_transaction_participant_read on public.exchange_transactions for select to authenticated using (
  exists (select 1 from public.book_exchange_requests er where er.id = exchange_request_id and (er.requester_id = auth.uid() or er.target_owner_id = auth.uid()))
);

alter table public.notifications enable row level security;
create policy notifications_owner_read on public.notifications for select to authenticated using (user_id = auth.uid());
alter table public.grievance_tickets enable row level security;
create policy grievance_requester_read on public.grievance_tickets for select to authenticated using (requester_id = auth.uid());
create policy grievance_requester_insert on public.grievance_tickets for insert to authenticated with check (requester_id = auth.uid());
alter table public.privacy_requests enable row level security;
create policy privacy_requests_owner_read on public.privacy_requests for select to authenticated using (requester_id = auth.uid());
create policy privacy_requests_owner_insert on public.privacy_requests for insert to authenticated with check (requester_id = auth.uid());
alter table public.legal_documents enable row level security;
create policy legal_documents_published_read on public.legal_documents for select to anon, authenticated using (is_published);
alter table public.legal_acceptances enable row level security;
create policy legal_acceptances_owner_read on public.legal_acceptances for select to authenticated using (user_id = auth.uid());

alter table public.admin_audit_logs enable row level security;
alter table public.risk_alerts enable row level security;
alter table public.pricing_configuration enable row level security;
alter table public.analytics_events enable row level security;
alter table public.daily_business_metrics enable row level security;
alter table public.outbox_events enable row level security;

-- Explicitly revoke all direct writes on sensitive tables from browser roles.
revoke insert, update, delete, truncate on
  public.user_roles, public.user_verifications, public.identity_documents, public.verification_audit,
  public.book_condition_records, public.book_availability_blocks, public.copy_reservations,
  public.rental_agreements, public.rental_condition_photos, public.handover_sessions, public.handover_events,
  public.payments, public.payment_events, public.deposits, public.deposit_ledger, public.deposit_release_requests,
  public.commission_ledger, public.owner_earnings, public.payouts, public.refunds, public.late_fees,
  public.financial_accounts, public.journal_entries, public.journal_lines, public.dispute_evidence,
  public.referral_rewards, public.exchange_transactions, public.admin_audit_logs, public.risk_alerts,
  public.pricing_configuration, public.analytics_events, public.daily_business_metrics, public.outbox_events
from anon, authenticated;


-- Atomic booking creation. This is callable only by the trusted backend/service role.
-- Pricing and hold expiry are explicit inputs from approved server-side policy evaluation.
create or replace function public.create_booking_request(
  p_reader_id uuid,
  p_booking_number text,
  p_copy_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_buffer_before interval,
  p_buffer_after interval,
  p_hold_expires_at timestamptz,
  p_rent_fee_paise bigint,
  p_platform_fee_paise bigint,
  p_tax_paise bigint,
  p_policy_snapshot jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_copy public.book_copies%rowtype;
  v_booking_id uuid;
  v_item_id uuid;
  v_pricing public.book_pricing%rowtype;
  v_reserved tstzrange;
begin
  if p_reader_id is null then raise exception 'Reader identity is required'; end if;
  if p_end_at <= p_start_at then raise exception 'Invalid rental interval'; end if;
  if p_buffer_before < interval '0' or p_buffer_after < interval '0' then raise exception 'Invalid buffer'; end if;
  if p_hold_expires_at <= now() then raise exception 'Reservation hold expiry must be in the future'; end if;
  if p_rent_fee_paise < 0 or p_platform_fee_paise < 0 or p_tax_paise < 0 then raise exception 'Invalid monetary amount'; end if;

  select * into v_copy from public.book_copies where id = p_copy_id for update;
  if not found then raise exception 'Copy not found'; end if;
  if v_copy.owner_id = p_reader_id then raise exception 'Owner cannot rent their own copy'; end if;
  if v_copy.listing_status <> 'approved' or not v_copy.is_available_for_rent then raise exception 'Copy is not bookable'; end if;

  if not exists (select 1 from public.user_verifications uv where uv.user_id = p_reader_id and uv.status = 'verified' and uv.age_eligible is true)
     or not exists (select 1 from public.user_verifications uv where uv.user_id = v_copy.owner_id and uv.status = 'verified' and uv.age_eligible is true) then
    raise exception 'Both parties must be verified and age eligible';
  end if;

  if not exists (select 1 from public.cities c where c.id = v_copy.city_id and c.is_active and c.status = 'active') then
    raise exception 'City is not active for rentals';
  end if;

  select * into v_pricing from public.book_pricing
  where book_copy_id = p_copy_id and effective_from <= now()
    and (effective_until is null or effective_until > now())
  order by effective_from desc limit 1;
  if not found then raise exception 'No active pricing'; end if;

  v_reserved := tstzrange(p_start_at - p_buffer_before, p_end_at + p_buffer_after, '[)');

  if exists (
    select 1 from public.book_availability_blocks b
    where b.book_copy_id = p_copy_id and b.blocked_period && v_reserved
  ) then
    raise exception 'Copy is blocked for the requested interval';
  end if;

  insert into public.bookings (
    booking_number, reader_id, owner_id, city_id, requested_start_at, requested_end_at,
    status, policy_snapshot, rent_subtotal_paise, platform_fee_paise, tax_paise, total_due_paise
  ) values (
    p_booking_number, p_reader_id, v_copy.owner_id, v_copy.city_id, p_start_at, p_end_at,
    'requested', coalesce(p_policy_snapshot, '{}'::jsonb), p_rent_fee_paise,
    p_platform_fee_paise, p_tax_paise, p_rent_fee_paise + p_platform_fee_paise + p_tax_paise
  ) returning id into v_booking_id;

  insert into public.rental_items (
    booking_id, book_copy_id, city_id, pricing_snapshot, rental_fee_paise,
    buffer_before, buffer_after, reserved_period
  ) values (
    v_booking_id, p_copy_id, v_copy.city_id, to_jsonb(v_pricing), p_rent_fee_paise,
    p_buffer_before, p_buffer_after, v_reserved
  ) returning id into v_item_id;

  insert into public.copy_reservations (rental_item_id, booking_id, book_copy_id, reserved_period, status, expires_at)
  values (v_item_id, v_booking_id, p_copy_id, v_reserved, 'hold', p_hold_expires_at);

  return v_booking_id;
exception
  when exclusion_violation then
    raise exception 'Copy is no longer available for the requested interval';
end;
$$;
revoke all on function public.create_booking_request(uuid, text, uuid, timestamptz, timestamptz, interval, interval, timestamptz, bigint, bigint, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.create_booking_request(uuid, text, uuid, timestamptz, timestamptz, interval, interval, timestamptz, bigint, bigint, bigint, jsonb) to service_role;

-- Deposit release RPC: booking-scoped only; no pooled balance and no direct client writes.
create or replace function public.request_deposit_release(p_deposit_id uuid, p_idempotency_key text)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_user uuid := auth.uid();
  v_deposit public.deposits%rowtype;
  v_booking public.bookings%rowtype;
  v_request_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select * into v_deposit from public.deposits where id = p_deposit_id for update;
  if not found then raise exception 'Deposit not found'; end if;
  if v_deposit.payer_id <> v_user then raise exception 'Not deposit owner'; end if;
  if not v_deposit.feature_enabled_at_creation then raise exception 'Deposit release is disabled pending legal/provider approval'; end if;
  select * into v_booking from public.bookings where id = v_deposit.booking_id for update;
  if v_booking.status <> 'completed' then raise exception 'Booking is not closed'; end if;
  if exists (select 1 from public.disputes d where d.booking_id = v_booking.id and d.status <> 'closed') then
    raise exception 'Open dispute blocks deposit release';
  end if;
  if exists (select 1 from public.deposit_release_requests r where r.deposit_id = v_deposit.id and r.status in ('requested','approved','processing','reconciliation_required')) then
    raise exception 'Deposit release already in progress';
  end if;
  if v_deposit.status <> 'held_by_provider' then
    raise exception 'Deposit is not releasable in current state';
  end if;
  insert into public.deposit_release_requests(deposit_id, requested_by, amount_paise, idempotency_key)
  values (v_deposit.id, v_user, v_deposit.amount_paise, p_idempotency_key)
  returning id into v_request_id;
  update public.deposits set status = 'release_pending' where id = v_deposit.id;
  return v_request_id;
end;
$$;
revoke all on function public.request_deposit_release(uuid, text) from public, anon;
grant execute on function public.request_deposit_release(uuid, text) to authenticated;

-- Ensure the booking aggregate matches the actual physical copy; protects service-role paths too.
create or replace function private.enforce_rental_item_booking_consistency()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_booking public.bookings%rowtype; v_copy public.book_copies%rowtype;
begin
  select * into v_booking from public.bookings where id = new.booking_id;
  select * into v_copy from public.book_copies where id = new.book_copy_id;
  if v_booking.owner_id <> v_copy.owner_id or v_booking.city_id <> v_copy.city_id or new.city_id <> v_copy.city_id then
    raise exception 'Booking owner and city must match the physical copy';
  end if;
  if v_booking.reader_id = v_copy.owner_id then
    raise exception 'Owner cannot rent their own copy';
  end if;
  return new;
end;
$$;
create trigger rental_item_booking_consistency
before insert or update on public.rental_items
for each row execute function private.enforce_rental_item_booking_consistency();

-- The availability-block writer must serialize on the same copy row as booking creation.
create or replace function private.lock_copy_for_availability_block()
returns trigger language plpgsql
set search_path = pg_catalog, public
as $$
begin
  perform 1 from public.book_copies where id = new.book_copy_id for update;
  if exists (
    select 1 from public.copy_reservations r
    where r.book_copy_id = new.book_copy_id
      and r.status in ('hold','confirmed','in_use')
      and r.reserved_period && new.blocked_period
  ) then
    raise exception 'Availability block overlaps an active reservation';
  end if;
  return new;
end;
$$;
create trigger availability_block_copy_lock
before insert or update on public.book_availability_blocks
for each row execute function private.lock_copy_for_availability_block();

-- Attach late-created foreign keys.
alter table public.book_condition_records
  add constraint book_condition_records_booking_fk
  foreign key (booking_id) references public.bookings(id) on delete restrict;
alter table public.rental_agreements
  add constraint rental_agreements_legal_document_fk
  foreign key (legal_document_id) references public.legal_documents(id) on delete restrict;

-- Review trigger and role helper already created. Prevent users from changing booking state directly.
revoke insert, update, delete on public.bookings, public.rental_items from anon, authenticated;
revoke insert, update, delete on public.payments, public.refunds, public.payouts, public.deposits from anon, authenticated;

-- Supabase Storage buckets: only listing photos are public. Identity/evidence/support are private.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('book-listing-public','book-listing-public',false,10485760,array['image/jpeg','image/png','image/webp']),
  ('identity-private','identity-private',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf']),
  ('rental-evidence-private','rental-evidence-private',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf']),
  ('support-private','support-private',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do nothing;

-- Private evidence: no anon access. Users can upload to a user-prefixed path; no client read policy is granted.
create policy identity_private_upload_own on storage.objects for insert to authenticated
with check (bucket_id = 'identity-private' and (storage.foldername(name))[1] = auth.uid()::text);
create policy rental_evidence_upload_own on storage.objects for insert to authenticated
with check (bucket_id = 'rental-evidence-private' and (storage.foldername(name))[1] = auth.uid()::text);
create policy support_private_upload_own on storage.objects for insert to authenticated
with check (bucket_id = 'support-private' and (storage.foldername(name))[1] = auth.uid()::text);
-- No private-bucket SELECT policy: retrieval is through audited short-lived signed URLs issued by backend.
-- Listing images are private at rest. The API issues signed URLs only for approved listing images.
create policy listing_images_upload_own on storage.objects for insert to authenticated
with check (bucket_id = 'book-listing-public' and (storage.foldername(name))[1] = auth.uid()::text);

commit;

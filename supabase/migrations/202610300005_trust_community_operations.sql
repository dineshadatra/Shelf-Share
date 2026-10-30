begin;

create table public.disputes (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete restrict,
  opened_by uuid not null references auth.users(id) on delete restrict,
  against_user_id uuid not null references auth.users(id) on delete restrict,
  status public.dispute_status not null default 'open',
  reason_code text not null,
  description text,
  assigned_to uuid references auth.users(id) on delete restrict,
  decision_code text,
  decision_notes text,
  policy_version text,
  opened_at timestamptz not null default now(),
  decided_at timestamptz,
  closed_at timestamptz,
  check (opened_by <> against_user_id)
);
create index disputes_booking_idx on public.disputes(booking_id, opened_at desc);
create index disputes_assignee_idx on public.disputes(assigned_to, status);

create table public.dispute_evidence (
  id uuid primary key default gen_random_uuid(),
  dispute_id uuid not null references public.disputes(id) on delete restrict,
  submitted_by uuid not null references auth.users(id) on delete restrict,
  storage_bucket text not null default 'rental-evidence-private' check (storage_bucket = 'rental-evidence-private'),
  object_key text not null,
  evidence_type text not null,
  description text,
  sha256 text,
  submitted_at timestamptz not null default now(),
  unique (storage_bucket, object_key)
);

create table public.chat_conversations (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid references public.bookings(id) on delete restrict,
  conversation_type text not null default 'booking' check (conversation_type in ('booking','support','community')),
  created_at timestamptz not null default now()
);
create table public.chat_participants (
  conversation_id uuid not null references public.chat_conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete restrict,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  primary key (conversation_id, user_id)
);
create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.chat_conversations(id) on delete restrict,
  sender_id uuid not null references auth.users(id) on delete restrict,
  body text not null check (length(body) between 1 and 5000),
  message_type text not null default 'text' check (message_type in ('text','system','evidence_reference')),
  attachment_object_key text,
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz
);
create index chat_messages_conversation_idx on public.chat_messages(conversation_id, created_at);

create table public.user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete restrict,
  reported_user_id uuid references auth.users(id) on delete restrict,
  target_type text not null check (target_type in ('user','book_copy','message','post','comment','review')),
  target_id uuid not null,
  reason_code text not null,
  description text,
  status text not null default 'open' check (status in ('open','triaged','investigating','actioned','dismissed','closed')),
  assigned_to uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (reported_user_id is null or reported_user_id <> reporter_id)
);
create index user_reports_status_idx on public.user_reports(status, created_at);

create table public.user_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete restrict,
  reason_code text,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  rental_item_id uuid not null references public.rental_items(id) on delete restrict,
  reviewer_id uuid not null references auth.users(id) on delete restrict,
  reviewee_id uuid not null references auth.users(id) on delete restrict,
  rating smallint not null check (rating between 1 and 5),
  review_text text check (review_text is null or length(review_text) <= 2000),
  status text not null default 'pending_moderation' check (status in ('pending_moderation','published','hidden','removed')),
  created_at timestamptz not null default now(),
  published_at timestamptz,
  unique (rental_item_id, reviewer_id),
  check (reviewer_id <> reviewee_id)
);
create index reviews_reviewee_idx on public.reviews(reviewee_id, status, created_at desc);

create or replace function private.enforce_review_completed_rental()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_booking public.bookings%rowtype; v_copy_owner uuid;
begin
  select b.* into v_booking
  from public.bookings b
  join public.rental_items ri on ri.booking_id = b.id
  where ri.id = new.rental_item_id;
  if not found or v_booking.status <> 'completed' then
    raise exception 'Reviews are allowed only after a completed rental';
  end if;
  select owner_id into v_copy_owner from public.book_copies
  where id = (select book_copy_id from public.rental_items where id = new.rental_item_id);
  if not ((new.reviewer_id = v_booking.reader_id and new.reviewee_id = v_booking.owner_id)
       or (new.reviewer_id = v_booking.owner_id and new.reviewee_id = v_booking.reader_id)) then
    raise exception 'Review parties must be the reader and owner of this rental';
  end if;
  if new.reviewee_id <> v_copy_owner then
    raise exception 'Reviewee does not match physical copy owner';
  end if;
  return new;
end;
$$;
create trigger reviews_completed_rental_guard
before insert or update on public.reviews
for each row execute function private.enforce_review_completed_rental();

create table public.referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_id uuid not null references auth.users(id) on delete restrict,
  referred_user_id uuid references auth.users(id) on delete restrict,
  referral_code text not null unique,
  status text not null default 'created' check (status in ('created','qualified','expired','reversed')),
  created_at timestamptz not null default now(),
  qualified_at timestamptz,
  check (referred_user_id is null or referrer_id <> referred_user_id)
);
create unique index referrals_one_referrer_per_referred_uq on public.referrals(referred_user_id) where referred_user_id is not null;

create table public.referral_rewards (
  id uuid primary key default gen_random_uuid(),
  referral_id uuid not null references public.referrals(id) on delete restrict,
  beneficiary_id uuid not null references auth.users(id) on delete restrict,
  reward_type text not null,
  reward_value_paise bigint not null default 0 check (reward_value_paise >= 0),
  status text not null default 'pending' check (status in ('pending','approved','issued','reversed','expired')),
  policy_version text not null,
  created_at timestamptz not null default now()
);

create table public.community_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete restrict,
  title text,
  body text not null check (length(body) between 1 and 10000),
  status public.community_content_status not null default 'draft',
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index community_posts_published_idx on public.community_posts(published_at desc) where status = 'published';

create table public.community_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.community_posts(id) on delete restrict,
  author_id uuid not null references auth.users(id) on delete restrict,
  parent_comment_id uuid references public.community_comments(id) on delete restrict,
  body text not null check (length(body) between 1 and 3000),
  status public.community_content_status not null default 'published',
  created_at timestamptz not null default now()
);
create index community_comments_post_idx on public.community_comments(post_id, created_at);

create table public.reading_lists (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text,
  visibility text not null default 'private' check (visibility in ('private','unlisted','public')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.reading_list_items (
  reading_list_id uuid not null references public.reading_lists(id) on delete cascade,
  book_title_id uuid not null references public.book_titles(id) on delete cascade,
  position integer not null default 0,
  note text,
  primary key (reading_list_id, book_title_id)
);

create table public.challenges (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'draft' check (status in ('draft','published','active','completed','cancelled')),
  created_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);
create table public.challenge_participants (
  challenge_id uuid not null references public.challenges(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  progress_count integer not null default 0 check (progress_count >= 0),
  completed_at timestamptz,
  primary key (challenge_id, user_id)
);

create table public.book_exchange_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete restrict,
  target_owner_id uuid not null references auth.users(id) on delete restrict,
  offered_copy_id uuid not null references public.book_copies(id) on delete restrict,
  requested_copy_id uuid not null references public.book_copies(id) on delete restrict,
  status public.exchange_status not null default 'requested',
  message text,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  check (requester_id <> target_owner_id),
  check (offered_copy_id <> requested_copy_id)
);
create index exchange_requests_target_idx on public.book_exchange_requests(target_owner_id, status, created_at);

create table public.exchange_transactions (
  id uuid primary key default gen_random_uuid(),
  exchange_request_id uuid not null unique references public.book_exchange_requests(id) on delete restrict,
  handover_location_id uuid references public.handover_locations(id) on delete restrict,
  status public.exchange_status not null default 'accepted',
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  channel text not null check (channel in ('in_app','sms','email','push')),
  template_key text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued','sent','delivered','failed','read','cancelled')),
  provider_reference text,
  scheduled_at timestamptz not null default now(),
  sent_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user_unread_idx on public.notifications(user_id, created_at desc) where read_at is null;

create table public.grievance_tickets (
  id uuid primary key default gen_random_uuid(),
  ticket_number text not null unique,
  requester_id uuid not null references auth.users(id) on delete restrict,
  category text not null,
  subject text not null,
  description text not null,
  status public.ticket_status not null default 'open',
  assigned_to uuid references auth.users(id) on delete restrict,
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index grievance_tickets_assignee_idx on public.grievance_tickets(assigned_to, status);

create table public.privacy_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete restrict,
  request_type text not null check (request_type in ('access','correction','erasure','portability','withdraw_consent','restriction')),
  status text not null default 'received' check (status in ('received','identity_check','in_progress','fulfilled','partially_fulfilled','rejected','closed')),
  description text,
  received_at timestamptz not null default now(),
  due_at timestamptz,
  completed_at timestamptz,
  decision_reason text
);
create index privacy_requests_requester_idx on public.privacy_requests(requester_id, received_at desc);

create table public.legal_documents (
  id uuid primary key default gen_random_uuid(),
  document_type text not null,
  version text not null,
  title text not null,
  content_uri text not null,
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  effective_from timestamptz not null,
  effective_until timestamptz,
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  unique (document_type, version),
  check (effective_until is null or effective_until > effective_from)
);
create table public.legal_acceptances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  legal_document_id uuid not null references public.legal_documents(id) on delete restrict,
  accepted_at timestamptz not null default now(),
  acceptance_context text not null,
  ip_hash text,
  user_agent_hash text,
  unique (user_id, legal_document_id, acceptance_context)
);

create table public.admin_audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete restrict,
  action text not null,
  target_table text not null,
  target_id text not null,
  reason text,
  before_data jsonb,
  after_data jsonb,
  request_id text,
  created_at timestamptz not null default now()
);
create index admin_audit_logs_target_idx on public.admin_audit_logs(target_table, target_id, created_at desc);
create index admin_audit_logs_actor_idx on public.admin_audit_logs(actor_id, created_at desc);

create table public.risk_alerts (
  id uuid primary key default gen_random_uuid(),
  subject_user_id uuid references auth.users(id) on delete restrict,
  booking_id uuid references public.bookings(id) on delete restrict,
  alert_type text not null,
  severity text not null check (severity in ('low','medium','high','critical')),
  status text not null default 'open' check (status in ('open','triaged','resolved','false_positive')),
  signal_summary text not null,
  internal_details jsonb not null default '{}'::jsonb,
  assigned_to uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index risk_alerts_open_idx on public.risk_alerts(severity, created_at) where status = 'open';

create table public.pricing_configuration (
  id uuid primary key default gen_random_uuid(),
  config_key text not null,
  scope_type text not null check (scope_type in ('global','city','category')),
  scope_id uuid,
  value jsonb not null,
  version text not null,
  effective_from timestamptz not null,
  effective_until timestamptz,
  approved_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (config_key, scope_type, scope_id, version),
  check (effective_until is null or effective_until > effective_from)
);
create index pricing_configuration_effective_idx on public.pricing_configuration(config_key, effective_from desc);

create table public.analytics_events (
  id bigint generated always as identity primary key,
  anonymous_id text,
  user_id uuid references auth.users(id) on delete set null,
  event_name text not null,
  event_version integer not null default 1,
  city_id uuid references public.cities(id) on delete set null,
  properties jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  ingested_at timestamptz not null default now()
);
create index analytics_events_name_time_idx on public.analytics_events(event_name, occurred_at desc);
create index analytics_events_user_time_idx on public.analytics_events(user_id, occurred_at desc);

create table public.daily_business_metrics (
  metric_date date not null,
  scope_key text not null default 'global',
  city_id uuid references public.cities(id) on delete cascade,
  metric_key text not null,
  metric_value numeric(20,4) not null,
  dimensions jsonb not null default '{}'::jsonb,
  calculated_at timestamptz not null default now(),
  primary key (metric_date, scope_key, metric_key)
);

create table public.outbox_events (
  id uuid primary key default gen_random_uuid(),
  aggregate_type text not null,
  aggregate_id uuid not null,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  idempotency_key text not null unique,
  available_at timestamptz not null default now(),
  published_at timestamptz,
  attempts integer not null default 0 check (attempts >= 0),
  last_error_code text,
  created_at timestamptz not null default now()
);
create index outbox_events_pending_idx on public.outbox_events(available_at) where published_at is null;

create trigger community_posts_updated_at before update on public.community_posts for each row execute function private.set_updated_at();
create trigger reading_lists_updated_at before update on public.reading_lists for each row execute function private.set_updated_at();
create trigger grievance_tickets_updated_at before update on public.grievance_tickets for each row execute function private.set_updated_at();

commit;

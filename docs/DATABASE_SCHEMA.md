# ShelfShare — Production Database Schema

**Status:** Architecture proposal / implementation baseline pending product, legal, payment-provider and security approval  
**Database:** PostgreSQL on Supabase  
**Currency:** INR, integer paise  
**Timezone:** `Asia/Kolkata` for product display; timestamps stored as `timestamptz`  
**Generated:** 30 October 2026

## 1. Design principles

1. **Catalogue metadata is not inventory.** `book_titles` describes an edition/work; `book_copies` describes one physical copy owned by one user.
2. **PostgreSQL is authoritative.** Frontend availability checks are advisory. The database exclusion constraint is the final concurrency guard.
3. **Money is append-only and balanced.** Provider events are immutable; journal entries are immutable; corrections use reversal entries. Money is stored as integer paise.
4. **No wallet or informal escrow.** Deposits are booking-specific provider arrangements, not an account-level spendable balance. Deposit production functionality remains feature-disabled pending written legal and provider approval.
5. **Clients do not write privileged state.** Verification, payment, payout, refund, deposit, risk and admin audit state is server-controlled.
6. **Private evidence stays private.** Identity files and rental evidence use private Storage buckets; database rows hold object keys, not public URLs.
7. **RLS is default-deny.** Explicit policies expose only the minimum user-owned or intentionally public data.
8. **Auditability is additive.** State changes create audit/event records; financial history is not edited in place.
9. **City restrictions are relational.** A booking must match the copy's city; both parties must be eligible and in the supported city scope.
10. **Unapproved policy is not guessed.** Unresolved fee, duration, deposit, cancellation, retention and locality values are configuration gates, not invented constants.

## 2. Schema namespaces

All application tables are in `public` for straightforward Supabase/PostgREST integration. Internal authorization helper functions are in `private`. Supabase-managed `auth`, `storage` and `realtime` schemas remain provider-managed.

## 3. Identity and authorization

### `profiles`
One public-facing account profile per `auth.users` identity. Contains display name, avatar object key, optional email display/contact data and account state. It does **not** contain a client-editable verification flag, role, admin bit, payment status or KYC result.

Key constraints: `id` is both PK and FK to `auth.users(id)`; normalized phone is not duplicated because Supabase Auth owns the verified phone. `account_status` is server-managed.

### `user_roles`
Privileged role assignments (`support_agent`, `verification_reviewer`, `finance_operator`, `moderator`, `admin`, `super_admin`). No self-assignment. Changes are restricted to service role and audited. Role checks use a `SECURITY DEFINER` function with a fixed search path.

### `user_verifications`, `identity_documents`, `verification_audit`
Verification aggregate and evidence metadata. Identity number values should be minimized; if a legal/operational process requires storing a number, store a provider token or encrypted value in a separately managed secret field, not cleartext. Store only a private object key for uploaded evidence. Admin access is narrow and audited. Never expose document object keys through public profile APIs.

### Geography and handover
`cities`, `localities`, `handover_locations` are Admin-curated. Public clients can read only active, published public handover locations. Exact residential addresses are not modeled as public handover points.

## 4. Catalogue and inventory

- `book_titles`: bibliographic metadata and edition identity.
- `categories`, `book_title_categories`: normalized category taxonomy.
- `book_copies`: each physical copy and its owner, city/locality, condition summary, moderation and listing status.
- `book_images`: listing image object keys; private listing image objects served via short-lived signed URLs after moderation and EXIF stripping.
- `book_condition_records`: dated condition assessments.
- `book_availability_blocks`: owner/admin blocks such as maintenance, loss or personal use.
- `book_pricing`: versioned rental pricing, custom duration rules and optional deposit policy reference. Effective dates are immutable snapshots once used by a booking.
- `wishlists`, `wishlist_items`, `book_recommendations`: discovery features. Recommendations are non-authoritative and may be system-generated.

## 5. Booking and handover

`bookings` is the commercial booking aggregate; `rental_items` binds the booking to a specific physical copy and pricing snapshot; `copy_reservations` is the concurrency-control table. Reservation intervals are half-open `[start,end)` and include configured buffers. An exclusion constraint prevents overlapping live reservations for the same copy.

The exact rental clock, owner approval point, custom duration limits, cancellation fees and buffer semantics remain open. The schema therefore stores requested and effective timestamps separately and snapshots policy/configuration identifiers. A booking cannot become active until collection is verified by a valid handover session.

`rental_agreements` snapshots document version and acceptance evidence. `rental_condition_photos`, `handover_sessions` and `handover_events` retain the chain of custody. QR tokens are hashed; never store a reusable raw QR secret.

## 6. Payments and accounting

### Provider-facing transaction records
- `payments`, `payment_events`
- `refunds`, `payouts`, `late_fees`
- `deposits`, `deposit_ledger`
- `commission_ledger`, `owner_earnings`
- `financial_accounts`, `journal_entries`, `journal_lines`

Provider event IDs are unique per provider. Webhook processing is idempotent. Raw webhook payloads should be minimized and stored encrypted or as restricted object references with retention controls.

### Double-entry invariants
Each posted journal entry must balance to zero in a single currency. `journal_lines` are append-only. A reversal is a new journal entry referencing the original. Application code must post an entire journal entry in one database transaction; the deferred constraint trigger checks balance at commit.

`owner_earnings` is an operational projection, not the accounting source of truth. It is updated only by trusted server code and reconciled against journal entries/provider reports.

### Deposits and withdrawal race safety
There is intentionally **no pooled user deposit balance and no generic wallet withdrawal**. Each deposit belongs to exactly one booking. A release request is tied to that booking and is only eligible after the booking is closed, no open dispute/claim exists, and provider/legal feature gates are enabled. `deposit_release_requests` has one active request per deposit and the RPC locks the deposit row with `FOR UPDATE`. A new booking cannot consume, reserve or withdraw another booking's deposit. If the product owner later chooses account-level pooling, that requires a new legal/accounting design and atomic account-balance ledger; it must not be inferred from this schema.

## 7. Trust, community and support

Tables cover disputes/evidence, chat, reports, blocks, reviews, referrals/rewards, community posts/comments/reading lists/challenges, exchange requests/transactions, notifications, grievances, privacy requests, legal documents/acceptances, admin audit logs and risk alerts.

Reviews are linked to a rental item and reviewer; the database trigger checks that the rental is completed and the reviewer is a participant. Product policy must still decide whether both sides can review, blind publication, edit window and moderation workflow.

## 8. Business analytics

`analytics_events` is a pseudonymous event stream for product metrics. `daily_business_metrics` is an Admin/service-role maintained aggregate. Neither table is a substitute for financial ledger reconciliation. Distinguish GMV, platform revenue, provider fees, taxes, refunds, deposits and owner payable.

## 9. Table catalogue and field definitions

The ordered migrations are the executable source of field types, defaults, primary/foreign keys, checks, unique constraints, indexes, triggers and policies. The following groups are implemented:

| Domain | Tables |
|---|---|
| Identity & authorization | `profiles`, `user_roles`, `user_verifications`, `identity_documents`, `verification_audit` |
| Geography | `cities`, `localities`, `handover_locations` |
| Catalogue & inventory | `book_titles`, `categories`, `book_title_categories`, `book_copies`, `book_images`, `book_condition_records`, `book_availability_blocks`, `book_pricing`, `wishlists`, `wishlist_items`, `book_recommendations` |
| Booking & agreements | `bookings`, `rental_items`, `copy_reservations`, `rental_agreements`, `rental_condition_photos`, `handover_sessions`, `handover_events` |
| Finance | `payments`, `payment_events`, `deposits`, `deposit_ledger`, `deposit_release_requests`, `commission_ledger`, `owner_earnings`, `payouts`, `refunds`, `late_fees`, `financial_accounts`, `journal_entries`, `journal_lines` |
| Trust & community | `disputes`, `dispute_evidence`, `chat_conversations`, `chat_participants`, `chat_messages`, `user_reports`, `user_blocks`, `reviews`, `referrals`, `referral_rewards`, `community_posts`, `community_comments`, `reading_lists`, `reading_list_items`, `challenges`, `challenge_participants`, `book_exchange_requests`, `exchange_transactions` |
| Operations & governance | `notifications`, `grievance_tickets`, `privacy_requests`, `legal_documents`, `legal_acceptances`, `admin_audit_logs`, `risk_alerts`, `pricing_configuration`, `analytics_events`, `daily_business_metrics`, `outbox_events` |

## 10. Core invariants enforced in PostgreSQL

- One profile per authenticated user.
- No client-controlled verification or privileged role assignments.
- A physical copy has one owner and one city; copy city must equal locality city.
- A booking's reader and owner are distinct; owner matches copy owner; booking city matches copy city.
- A live copy reservation cannot overlap another live reservation for the same copy.
- Reservation interval uses `[)` semantics; buffer is included in the stored reserved interval.
- One payment attempt has a unique provider reference where supplied; one provider event ID is processed once.
- One deposit per booking in this initial model; no cross-booking balance.
- Deposit release is unique and requires a closed booking with no open dispute/claim.
- Journal entries balance per currency before commit.
- Reviews require a completed rental and a participant reviewer.
- Handover QR secrets are stored only as hashes.
- Identity and condition evidence object keys are private and not readable by ordinary users.
- Admin role assignment and finance operations are server-only and audited.

## 11. Operations and deployment notes

1. Apply migrations in filename order to a fresh Supabase project.
2. Configure private Storage buckets: `identity-private`, `rental-evidence-private`, `support-private`; public listing image delivery is via a separate `book-listing-public` bucket only after image sanitization/moderation.
3. Keep deposit feature flag false until the legal/provider gate is signed.
4. Keep payment and payout state writes on trusted backend/service-role paths only.
5. Do not expose `service_role` or database credentials to browser/mobile clients.
6. Use dedicated backend RPCs for booking creation, handover confirmation, deposit release and journal posting; never expose arbitrary SQL.
7. Set up PITR plus independent encrypted backups; define RPO/RTO and run restore drills.
8. Test RLS with at least two ordinary users, each role, anonymous access, and service-role flows.
9. Treat `SECURITY DEFINER` functions as privileged code: fixed `search_path`, explicit auth/role checks, revoke public execute and grant only intended roles.
10. Validate retention, deletion, legal hold and privacy-request workflows with counsel before launch.

## 12. Known decisions still blocking production

This database does not silently decide the open Product Decision Register items: owner approval timing, identity/address proof policy, deposit custody/product, cancellation/refund tiers, no-show windows, late-fee formula, damage valuation, rental clock semantics, payout schedule/tax allocation, own-copy booking, wishlist/waitlist behavior, launch locality set, review reciprocity/blindness, retention periods, admin role thresholds, chat opening/privacy, listing moderation mode, custom duration bounds, handover venue validation, dispute appeal window, exchange payment model and community MVP scope.

**Important:** This is a proposed production schema, not a claim that the product's PRD or legal/payment policies are approved. The PRD currently remains a Product Discovery Draft.

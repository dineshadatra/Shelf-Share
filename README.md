# ShelfShare — Supabase marketplace backend

This repository contains ShelfShare's PostgreSQL/Supabase schema, business rules and trusted backend runtime for a peer-to-peer physical-book rental marketplace in India.

## Repository contents

- `docs/` — architecture, product rules, privacy/security, India compliance dependencies, database design, rental lifecycle/dispute/safety policies, admin operations and notifications/support/finance analytics.
- `supabase/migrations/` — ordered PostgreSQL/Supabase migrations.
- `supabase/functions/` — Edge Functions for payment initiation/webhooks, QR/OTP handover, private evidence, rental lifecycle, notifications/SMS delivery, customer support, due/SLA sweeps, finance reports and existing finance requests.
- `supabase/tests/unit/` — runnable Node.js unit tests for financial, handover, rental-operations, admin-portal, notification, support and CSV-export invariants.
- `supabase/tests/INTEGRATION_TEST_MATRIX.md` — database/provider sandbox test scenarios.

## Local setup

Requirements: Git, Node.js 22.6+, Supabase CLI. Deno is recommended for Edge Function format/check/lint.

```powershell
git clone --branch feature/booking-payment-deposit-qr https://github.com/dineshadatra/Shelf-Share.git
cd Shelf-Share
npm run test:unit
supabase start
supabase db reset
supabase db lint
supabase test db
```

See [Local Development](docs/LOCAL_DEVELOPMENT.md) for Edge Function serving and deployment commands.

## Rental operations and customer safety

The rental operations layer adds a participant-scoped active-rental dashboard, due/overdue projection, grace-period reminders, controlled extension and rescheduling workflows, early return, cancellation/refund review, no-show incident reporting, evidence-backed damage claims, dispute messages, appeals, user/listing/unsafe-handover reports, block/mute controls and auditable account restrictions. The policy row is inactive by default. Proposed defaults (24-hour grace, reminders at 72/24/0 hours, 48-hour claim response and 72-hour appeal window) must be reviewed and approved before activation.

Late fees are written as `proposed` records only; the scheduler reports `late_fees_charged: 0`. No claim or appeal decision deducts from a deposit or payment method. Paid extensions stay pending until a provider-approved extension pricing/payment route is implemented. Read [Rental Lifecycle, Disputes and Safety](docs/RENTAL_LIFECYCLE_DISPUTES_SAFETY.md) for detailed customer policies and evidence standards.

## Financial safety and provider approval

No commercial payment adapter is registered by default. The provider interface is provider-independent, while real checkout/webhook/refund/payout operations remain disabled until the chosen RBI-authorised payment aggregator has approved ShelfShare's exact marketplace use case and the adapter has passed sandbox testing.

Security-deposit collection/custody remains BLOCKED until the provider, Indian legal counsel and accounting adviser approve the exact funds flow and release/dispute arrangements in writing. The database deposit tables are accounting/workflow records, not proof that money is held.

Never mark payment, refund, deposit release or owner payout successful from a browser redirect, API request acknowledgement or database-only status. Require verified provider confirmation and reconciliation.

## Existing business rules

- INR amounts use integer paise.
- Marketplace commission is 10% of rental fee only; the security deposit is separate.
- Only verified participants can transact.
- Cross-city rentals are not permitted in the current launch policy; reader and physical copy must be in the same enabled city.
- A physical copy cannot have overlapping live reservations.
- Booking confirmation depends on the provider-verified payment event.
- Rental activation requires both parties' authenticated handover confirmation and condition evidence.
- Owner earnings become eligible after verified physical collection, subject to approved marketplace settlement and dispute/chargeback controls.
- Return closure requires return evidence and both-party confirmation (or an audited exception).
- No arbitrary deposit deduction, pooled user wallet or informal escrow.

## Important limits

The Edge Functions are backend scaffolding over the existing SQL RPCs. They do not select a payment vendor, confer regulatory approval, provide a legal opinion, or make the app production-ready. The repository does not include the frontend product application. Run every migration in a disposable Supabase project and complete the database race, webhook, refund, payout, chargeback, storage, RLS and restore tests before production.


## Admin portal and business operations

A separate staff-only console is available in the admin/ directory. It calls the JWT-protected admin-portal Edge Function and uses database-enforced role permissions. The six staff roles separate support, verification review, moderation, finance, general administration and super-admin duties. Identity document access is limited to verification reviewers with MFA AAL2; financial tables are restricted to the finance_operator role. Selected high-risk actions use maker-checker approvals, and admin activity is recorded in an append-only log.

See docs/ADMIN_PORTAL.md for staff module coverage and docs/NOTIFICATIONS_SUPPORT_FINANCIAL_ANALYTICS.md for notification delivery, support/SLA, DLT and financial reporting details. Apply migrations 202610310006_admin_portal_rbac.sql through 202610310012_notification_backfill_and_resubmission.sql in lexical order after the existing migrations. Host the admin/ directory separately over HTTPS and configure ADMIN_PORTAL_ORIGINS for its exact origin.

The portal is a first operational foundation: it includes permission-filtered module views, filters, search, pagination, limited CSV export, manual verification, selected moderation, and approval workflows. Several specialised edit/fulfilment workflows and all provider-side financial execution still require additional integration and staging validation.


## Notifications, support and financial analytics

The notifications/support/financial analytics backend adds event-driven in-app notifications, opt-in SMS preferences and a DLT-gated delivery outbox, support tickets with response history and SLA escalation, and MFA-protected financial analytics CSV exports. SMS remains disabled until ShelfShare has completed Principal Entity registration, registered headers/templates, consent configuration and a tested provider-specific gateway adapter. Email and push adapters are not enabled. See docs/NOTIFICATIONS_SUPPORT_FINANCIAL_ANALYTICS.md for exact event coverage, deployment secrets, DLT gates, SLA defaults, metric definitions and known limits.

Apply migrations 202610310008_notifications_support_financial_analytics.sql, 202610310009_operations_hardening.sql and 202610310010_operations_controls.sql after migrations 006 and 007. Run npm run test:unit, Supabase migration lint and disposable-database/RLS integration tests before production.

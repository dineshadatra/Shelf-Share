# ShelfShare — Supabase marketplace backend

This repository contains ShelfShare's PostgreSQL/Supabase schema, business rules and trusted backend runtime for a peer-to-peer physical-book rental marketplace in India.

## Repository contents

- `docs/` — architecture, product rules, privacy/security, India compliance dependencies, database design and operations.
- `supabase/migrations/` — ordered PostgreSQL/Supabase migrations.
- `supabase/functions/` — Edge Functions for payment initiation/webhooks, QR/OTP handover, private condition evidence, owner settlement requests, deposit release requests and finance refund requests.
- `supabase/tests/unit/` — runnable Node.js unit tests for financial and handover invariants.
- `supabase/tests/INTEGRATION_TEST_MATRIX.md` — database/provider sandbox test scenarios.

## Local setup

Requirements: Git, Node.js 22+, Supabase CLI. Deno is recommended for Edge Function format/check/lint.

```powershell
git clone https://github.com/dineshadatra/Shelf-Share.git
cd Shelf-Share
npm run test:unit
supabase start
supabase db reset
supabase db lint
supabase test db
```

See [Local Development](docs/LOCAL_DEVELOPMENT.md) for Edge Function serving and deployment commands.

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


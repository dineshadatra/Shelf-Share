# ShelfShare database design package

This package contains:
- `docs/DATABASE_SCHEMA.md` — schema rationale, table catalogue, invariants and unresolved decisions.
- `docs/ER_DIAGRAM.md` — Mermaid ER and transaction diagrams.
- `docs/RLS_MATRIX.md` — role/table access matrix.
- `supabase/migrations/` — ordered Supabase/PostgreSQL migrations.
- `supabase/seed.sql` — non-financial demo reference data only.

## Apply

Use a fresh Supabase project and apply migrations in lexical order using Supabase CLI (`supabase db reset` locally, or the project's migration deployment workflow). Review the SQL against the exact Supabase/PostgreSQL version before production.

## Important implementation caveats

1. This is a substantial schema baseline, not a substitute for migration execution, automated tests, security review or legal/provider approval.
2. `create_booking_request` is executable only by `service_role`. The backend must compute price, fee, tax and hold expiry from approved policy, generate the booking number, and pass those values in one trusted call. It does not perform payment capture.
3. The review trigger enforces completed booking and allows either participant to review the other; the exact blind-publication and edit-window policy remains open.
5. `daily_business_metrics` primary key includes JSONB dimensions. PostgreSQL supports btree equality for jsonb, but application metric dimensions must be canonicalized to avoid semantically duplicate JSON objects.
6. `profiles` RLS permits own-row updates only for explicitly granted columns. Verification status lives in `user_verifications`, where no client write policy exists.
7. For Admin workflows, use audited backend endpoints/service-role. Do not add broad admin RLS policies without a role-specific access review.
8. Storage private buckets have no client read policy. Backend must authorize the evidence relationship, issue short-lived signed URLs, and audit access.
9. A Supabase `service_role` bypasses RLS; protect it as a root credential.
10. The SQL has not been run against a live Supabase instance in this package. Execute migrations in a disposable project, run the tests described below, and fix any provider-version-specific issues before production.

## Required pre-production tests

- Apply all migrations to a clean Supabase project.
- Run `supabase db lint` and SQL formatter/linter.
- Concurrency test: two transactions reserve overlapping intervals for one copy; exactly one succeeds.
- Interval test: adjacent `[start,end)` reservations succeed; overlap fails.
- Cross-city test: copy/locality city mismatch rejected by composite FK.
- Owner self-book test: rejected by RPC.
- Verification test: unverified reader/owner cannot book; client cannot mutate verification status.
- Payment test: duplicate provider event ID is rejected; browser client cannot mutate payment state.
- Ledger test: unbalanced journal transaction fails at commit; posted journal line update/delete fails.
- Deposit test: two simultaneous release requests result in one active request; release blocked for active rental/open dispute; no user-level pooled balance exists.
- Review test: nonparticipant and incomplete-rental review inserts fail.
- Storage test: anon cannot read identity/evidence objects; one user cannot upload into another user's folder; private reads only via backend signed URL.
- Role test: authenticated user cannot grant self a role; role revocation is immediately effective.
- Audit test: every admin decision and financial mutation emits an immutable audit/outbox record.
- Restore test: restore DB and private object backups in a separate environment.

## Known hardening work before production

- Add complete backend RPCs for verification review, payment webhook inbox processing, handover confirmation, refunds, payout, dispute resolution, ledger posting and moderation.
- Add append-only enforcement triggers and controlled service-role grants for all financial event/ledger tables.
- Add storage lifecycle/retention and deletion workflows after legal approval.
- Review profile read requirements: current baseline is self-only; public-safe profile cards should be served through a restricted view/RPC rather than widening the base table.
- Reconcile and correct any SQL issues discovered by executing against the selected Supabase project version.

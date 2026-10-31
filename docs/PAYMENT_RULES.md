# Payment Rules — ShelfShare

**Important:** This is a product/ledger specification, not permission to perform payment aggregation. ShelfShare must use an eligible RBI-authorised provider and must not pool/hold customer funds in its ordinary bank account or create an informal wallet/escrow. The application now has a provider-independent adapter contract and a retryable outbox; no concrete adapter is registered or enabled. Payment initiation, deposit collection, release and payouts therefore remain unavailable until the exact peer-to-peer physical-book rental marketplace has written provider, legal and accounting approvals.

## 1. Payment categories

Maintain distinct obligations and ledger accounts for:
- Rental fee.
- Platform commission (10% of rental fee).
- Security deposit (separate; not revenue).
- Extension fee.
- Late fee, only if policy/legal approval enables it.
- Damage/non-return compensation, only after decision and approved payment route.
- Refunds and reversals.
- Provider processing fees.
- Applicable GST and Income-tax withholding.
- Referral reward liability, if campaign is enabled.

## 2. Core invariants

1. All amounts INR integer paise.
2. Backend computes amount; client submits identifiers, not authoritative totals.
3. Store immutable price/tax/policy snapshot per booking.
4. Provider must support intended marketplace vendor onboarding, split settlement, refunds and deposit arrangement in writing.
5. Do not store card credentials, UPI PIN or sensitive payment authentication data.
6. Verify webhook signature and provider event uniqueness.
7. Browser redirect is never proof of payment.
8. A provider event is not a ledger entry until validated and transactionally applied.
9. Refunds cannot exceed captured amount less successful prior refunds.
10. Owner payout is not eligible until verified collection.
11. Commission is 10% of rent only; not deposit.
12. Provider fees and tax are separate; fee allocation is unresolved.
13. Do not retry capture/payout blindly; query provider state first.
14. A failed notification does not change payment truth.
15. Every financial action has idempotency key and immutable ledger entry.

## 3. Payment intent and capture

1. Owner acceptance and both parties’ current rental-agreement acceptance are required before checkout. The trusted transaction creates an internal payment obligation and extends the existing inventory hold.
2. Backend calls provider through adapter using unique merchant reference/idempotency key.
3. Store provider intent reference and expected amount/currency.
4. Accept signed provider webhook or server-to-server status query.
5. Compare merchant reference, amount, currency, booking, event and status.
6. Record event in webhook inbox with unique provider event ID.
7. Transactionally post ledger and update payment state.
8. If provider uses separate authorisation/capture, capture only according to provider-approved product flow; exact model is provider-specific.
9. A successful payment with expired inventory hold triggers reacquisition or refund; never force a conflicting booking.

## 4. Commission and owner proceeds

Reader checkout is the rental fee plus approved tax only. The 10% platform commission is withheld from Owner rent proceeds; it is not added as a second Reader checkout fee. A security deposit, when legally/provider approved, is a separate provider-held obligation and is never part of commission or platform revenue.

Base commercial rule: 10% of rental fee. Formula:
- `gross_rent = approved rental fee`
- `platform_commission = 10% of gross_rent` using approved rounding
- `owner_gross_entitlement = gross_rent - platform_commission`
- `tax_withholding`, `applicable GST`, `provider fees`, `adjustments` are separate lines and require CA/provider sign-off.
- `owner_net_payout` must not be hardcoded until fee allocation and tax treatment are approved.

Owner payout becomes eligible only after the QR/OTP collection workflow is complete and booking enters ACTIVE. Actual settlement timing is determined by approved PA product/contract, not an invented internal wallet.

## 5. Webhook processing

- Verify signature against raw request body.
- Reject invalid signature.
- Persist event ID, provider reference, received time, payload reference and processing state.
- Unique constraint on `(provider_id, provider_event_id)`.
- If duplicate, return success/acknowledgement without repeating side effects.
- If out-of-order, query provider canonical state; do not regress state.
- Use inbox/outbox pattern and aggregate version.
- Retry transient internal processing errors; dead-letter after configured attempts and alert finance.
- Daily reconciliation compares provider reports, payment ledger, refunds, payouts and bank settlement evidence.

## 6. Payment failure scenarios

### Payment fails before capture
- Mark payment FAILED only on definitive provider status.
- Release reservation hold according to configured expiry.
- Notify reader.
- Allow new attempt with new payment attempt ID; retain old attempt.

### Payment succeeds but booking creation/confirmation fails
- Do not create second charge.
- Recheck copy reservation in a transaction.
- If copy still safely available, attach payment to booking and confirm.
- If not available, initiate appropriate refund; mark reconciliation required until confirmed.
- Create support case and notify reader.

### Duplicate webhook
- Unique provider event ID and idempotent ledger posting.
- Return provider acknowledgement.
- No duplicate capture/refund/payout or notifications.

### Browser closed after success
- Webhook/reconciliation updates booking.
- Reader dashboard queries backend status; never relies on redirect.

### Refund failure
- Keep REFUND_PENDING/FAILED; query provider before retry.
- Retry only with same idempotency key where provider supports it.
- Escalate to finance; notify user of delay and next update.
- Do not mark refunded until provider confirms.

### Payout failure
- Keep owner payable liability outstanding; mark FAILED.
- Verify beneficiary details and provider status.
- Retry only after confirming no successful credit occurred.
- Do not create a second payout ID for same payable without reconciliation.

### Chargeback
- Open case, link provider dispute, preserve transaction/handover/return evidence.
- Freeze only the relevant amount/actions if provider rules permit.
- Notify affected parties as appropriate.
- Record outcome and accounting reversal; do not silently debit deposit.

## 7. Refund rules engine

Refund decision must be derived from:
- reason code;
- actor responsible;
- booking state;
- cancellation timing;
- policy version accepted;
- amount actually captured;
- prior refunds;
- provider capabilities;
- any lawful charge/fee retention rule.

The exact cancellation refund tiers are not yet approved. The rules engine must load a versioned configuration and refuse to calculate a production refund if no applicable rule exists.

## 8. Reconciliation and ledger

Use append-only double-entry ledger or equivalent balanced journal. Never update a posted entry in place; reverse with a new entry. Suggested dimensions:
- booking_id, payment_id, deposit_id, payout_id, refund_id;
- obligation type;
- debit/credit account;
- amount/currency;
- provider reference;
- tax classification;
- policy version;
- created/settled timestamps.

Daily reconciliation:
1. Provider collection report vs payment ledger.
2. Provider refund report vs refund ledger.
3. Provider settlement/payout report vs owner payable.
4. Bank statement vs provider settlement.
5. GST/TCS/TDS reports vs tax ledger.
6. Unmatched events into finance queue.

## 9. Configuration and professional approvals

Before production, obtain:
- RBI-authorised PA status and marketplace product approval.
- Provider confirmation for owner sub-merchant onboarding.
- Provider-approved split settlement, hold and payout timings.
- Provider-approved refund/chargeback flow.
- Deposit collection/hold/release legal opinion.
- CA approval for GST, TCS, Income-tax Act 2025 withholding, invoice and fee allocation.
- Legal review of payment, refund and fee disclosures.

## 10. Implemented architecture and deployment gate

The repository provides a provider-independent `MarketplacePaymentProvider` interface. It defines idempotent payment intents, payment status lookup, refunds, transfers, per-booking deposit holds/releases/claims, signed raw-body webhook verification and reconciliation. The provider registry is intentionally empty; no Cashfree, Razorpay or other provider adapter is registered. A public product page or sandbox API capability is not approval for ShelfShare's exact peer-to-peer book-rental marketplace. Obtain written provider approval for the precise model and separate written legal/CA approval before enabling any adapter or provider approval row.

The backend flow is:

1. Reader requests an individual copy. The server calculates the selected rental tier and 10% commission (rent only), validates identity/same-city/availability and creates a short request hold.
2. Owner accepts or declines. Both parties accept the current rental agreement before checkout.
3. Finance-approved tax calculation must be final before the payment attempt. A post-checkout tax update is rejected.
4. Service-role-only payment creation validates the approved provider, Owner marketplace-vendor KYC, policy configuration and hold. The provider call uses merchant reference and idempotency key.
5. Only signed provider webhooks (or a verified provider status query in a reviewed adapter) update terminal payment/refund/payout/deposit statuses. Browser redirects never confirm success.
6. If a capture arrives after the booking or its inventory reservation can no longer be honoured, the booking enters reconciliation and a service-only idempotent full-refund obligation is queued. A later outbox pass submits that refund using provider idempotency; the refund remains pending until provider confirmation.
7. Owner proceeds become eligible after server-verified collection handover. A finance-approved final calculation for tax withholding, provider fee and adjustments is required before payout creation. A provider payout event is the only source of `PAID`.

The worker is `supabase/functions/marketplace-outbox/index.ts`. It leases events with `FOR UPDATE SKIP LOCKED`, uses provider idempotency keys, retries with backoff, and dead-letters after the configured attempt limit. It requires `MARKETPLACE_WORKER_SECRET` (at least 32 characters) in the `x-marketplace-worker-secret` header. The worker is an HTTP Edge Function; a secure scheduled invocation (for example, Supabase Cron/pg_net with the secret stored outside source control) is a separate deployment task and is not created by these migrations. Without that schedule, queued operations are not guaranteed to run automatically.

## 11. Deployment sequence and environment

Apply the database migrations in numeric order through `202610300030_handover_rotation_and_financial_finality.sql` in a staging Supabase project first. Deploy both Edge Functions with the project's supported Supabase CLI:

- `supabase functions deploy marketplace-api --no-verify-jwt`
- `supabase functions deploy marketplace-outbox --no-verify-jwt`

The functions deliberately disable gateway JWT enforcement in `supabase/config.toml` because `marketplace-api` validates the caller with `auth.getUser()` and `marketplace-outbox` validates its dedicated worker secret. Do not expose the Supabase service-role key to the browser. Configure `APP_ORIGIN`, `HANDOVER_TOKEN_PEPPER` (random secret, 32+ characters) and `MARKETPLACE_WORKER_SECRET` (random secret, 32+ characters) as Edge Function secrets; the Supabase platform provides its standard URL/service-role environment to the function runtime. Rotate handover pepper only after active QR/OTP sessions have expired or been invalidated.

No booking timing, duration, tax, cancellation or deposit claim policy is seeded. A trusted operator must configure and approve the versioned configuration row, including request/payment holds, duration semantics, tax-policy reference and deposit claim window, before checkout or deposit release can pass. Finance must record the per-booking tax calculation and per-owner final settlement calculation. Seed approved public handover points and ensure their city matches the copy. Verify the `rental-evidence-private` bucket is private and upload-only for participant-scoped paths.

## 12. Test coverage and verification limits

`tests/security/marketplace-payments.test.mjs` and the existing security suite assert source-level security invariants for duplicate webhook IDs, failed events, browser-closure recovery, booking interval exclusion, cross-city checks, QR single-use/expiry/OTP limits, private evidence, deposit release guards, failed refund/payout states, chargebacks, owner no-show and provider idempotency. GitHub Actions runs security tests, TypeScript/build and lint.

These are static regression tests, not a provider certification, SQL integration test or end-to-end test against a configured Supabase database. The migrations have not been applied to a live/staging project in this work; no two-session race, real webhook signature, bank settlement, provider refund or physical handover has been exercised. Before production, run migration validation and concurrent transaction tests in staging, use a provider-approved sandbox adapter, exercise webhook retry/out-of-order scenarios, and reconcile a full payment/refund/payout/deposit lifecycle against the provider reports.

The exact cancellation/no-show refund matrix, fee allocation, GST/withholding treatment and provider settlement timetable remain approval gates. No automatic no-show fee, damage deduction or deposit confiscation is implemented.

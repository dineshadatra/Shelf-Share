# Deposit Rules — ShelfShare

**Status: BLOCKED pending written legal, provider and accounting approval.** The application stores only workflow references and provider-confirmed events; a database row or displayed locked amount does not prove custody.
The Project Master Context requires a security deposit separate from rental fee and commission, and says deposits remain subject to approved payment-provider arrangements until rental closure. It expressly prohibits informal escrow or a fictional wallet.

## 1. Non-negotiable safeguards

- Deposit is not rent, platform commission, owner earnings or platform revenue.
- Deposit is not available for withdrawal by Owner.
- Deposit is not represented as “escrow” unless the exact custody structure is legally valid and provider-approved.
- ShelfShare must not hold/pool deposit funds in its ordinary operating account or create an unregulated stored-value wallet.
- A database balance is a record, not proof that money is held. The member-facing deposit position is booking-scoped and derives from provider-confirmed ledger events.
- No automatic confiscation or arbitrary deduction.
- No deposit feature in production until signed legal opinion and written PA/bank approval identify who holds the funds, under what account/product, for whose benefit, and how release/application works.

## 2. Deposit lifecycle (conditional design)

`REQUIRED_UNCONFIGURED → COLLECTION_PENDING → HELD_BY_PROVIDER → RELEASE_PENDING → REFUND_PENDING → RELEASED`

Claim branch:
`HELD_BY_PROVIDER → CLAIM_HOLD_PENDING → CLAIM_HOLD → PARTIALLY_APPLIED → REFUND_PENDING → RELEASED`

Failure branch:
`COLLECTION_PENDING/REFUND_PENDING → FAILED → RECONCILIATION_REQUIRED`

These labels are internal workflow states only. They do not assert legal custody or escrow.

## 3. Required booking-time disclosure

Before payment, show:
- deposit amount;
- separate line item from rent and commission;
- provider/custody arrangement in plain language;
- conditions for release;
- claim window and evidence process;
- expected provider refund timing (only if verified);
- what happens if provider refund fails;
- whether any amount may be applied to an approved damage/non-return claim;
- support contact and dispute route.

Do not collect a deposit if the user has not accepted the applicable rental agreement and deposit terms.

## 4. Collection

1. Backend obtains deposit requirement from approved policy snapshot.
2. If provider/legal gate not complete, booking is blocked or deposit is not offered; do not silently substitute an internal balance.
3. Create distinct provider instruction and deposit aggregate.
4. Confirm collection/hold only from signed provider event or status query.
5. Record provider reference, amount, currency, custody/product descriptor and policy version.
6. Do not count deposit as rental GMV, platform commission or owner payable.

## 5. Withdrawal and active rental

The product requirement says deposit is withdrawable only when there is no active rental. Implement withdrawal eligibility as:
- no active rental obligations associated with the account;
- no pending collection/return, damage claim, non-return case, dispute, chargeback or provider hold;
- provider product permits the requested release;
- identity/account is not under lawful restriction.

The implementation is per-booking only. ShelfShare does not aggregate deposits into an account-level wallet or show a pooled withdrawable balance. Each release request is tied to one booking and requires provider-confirmed custody. If the payer has any active rental, an open claim/dispute, or a provider hold, release is rejected with a clear reason. Do not move money merely because the UI shows a balance.

## 6. Release after rental closure

- Verified return and inspection completed.
- No claim within approved claim window, or all claims resolved.
- No provider/legal hold.
- Backend issues provider release/refund request using idempotency key.
- Mark released only on provider confirmation.
- If no approved provider feature exists, do not implement a workaround that makes ShelfShare the custodian.

## 7. Damage/non-return application

- Claim must be submitted with before/after evidence and within approved time.
- Reader receives notice and opportunity to respond.
- Admin issues reasoned proportional decision.
- Only the approved amount may be applied, and only if provider/legal arrangement allows.
- Remaining amount is released/refunded.
- If claim is disputed, hold only where provider contract and law permit; otherwise use a separate lawful claim/payment process.
- Never auto-deduct original purchase price or full deposit.

## 8. Failed refund/release

- Keep `REFUND_PENDING` or `RECONCILIATION_REQUIRED`.
- Query provider before retry.
- Use stable idempotency key.
- Do not claim refund success before provider confirmation.
- Notify user of delay and support reference.
- Finance reconciles provider report and bank settlement.

## 9. Unresolved professional decisions

- Whether deposit is required for every rental or only selected books.
- Deposit calculation formula and maximum.
- Written confirmation that the per-booking custody and release arrangement is supported by the selected PA/bank product.
- Legal holder and account structure.
- PA/bank product and permitted hold duration.
- Whether and how disputed amount can remain held.
- Partial release mechanics.
- GST/income-tax/accounting treatment at collection, application and forfeiture.
- Refund SLA and failed refund escalation.
- Whether withdrawal is possible independently of rental refunds.
- Legal language and disclosure of custody arrangement.

**Release gate:** feature flag remains OFF until Indian lawyer, CA (tax/accounting) and selected PA/bank provide written approvals.

## 10. Implementation status and release gate

Deposit workflow is booking-scoped, not an account wallet. Only a signed provider event can move a record into `HELD_BY_PROVIDER`; provider references and ledger events are required before a position is shown as locked or available. The available amount is zero until return closure, the configured claim window, no open rental dispute, no provider chargeback, no claim and no active/pending rental for that member. Release is an idempotent provider instruction, and the amount is marked released only after a matching provider event. Partial claim application requires an independent finance decision with a reason and a provider-supported application operation.

The implementation is on `feat/frontend-foundation`, not deployed. There is no concrete provider adapter registered, and no live deposit collection/hold/release/deduction is enabled. Apply migrations through `202610300030_handover_rotation_and_financial_finality.sql` only after reviewing and testing the migration chain in a Supabase staging project. A provider-supported custody model and written legal/accounting approvals are prerequisites; a database row or outbox entry is never evidence of funds held by ShelfShare.

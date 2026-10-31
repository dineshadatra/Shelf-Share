# Critical integration test matrix

These are integration/release tests, not assertions that the current unit suite has passed them. Run only in a disposable local Supabase project and a provider sandbox.

| Scenario | Setup / fault injection | Required assertion |
|---|---|---|
| Duplicate webhook | Replay same provider event ID | One side effect and one journal posting |
| Invalid signature | Change raw body or signature | HTTP 4xx; no payment, booking or ledger mutation |
| Failed payment | Provider canonical state FAILED | Booking remains unconfirmed |
| Browser closed after capture | Suppress browser redirect; deliver signed webhook | Booking confirmation comes from provider event |
| Amount mismatch | Provider returns different paise amount | No capture application; reconciliation required |
| Booking race | Two concurrent requests for overlapping period | At most one live reservation |
| Expired hold plus late capture | Expire hold then return successful provider capture | Never confirm conflicting booking; refund/reconcile |
| QR replay | Redeem one token twice | First valid use only; second rejected |
| Expired QR | Redeem after expiry | No session completion |
| QR cross-booking | Use token against another booking | Rejected by session binding |
| OTP brute force | Five invalid OTP submissions | Attempt limit and lockout apply |
| Two-party confirmation | Initiator confirms without counterparty | Booking remains pending |
| Missing handover evidence | Confirm without each party's condition photo | Handover cannot complete |
| Deposit release race | Two simultaneous release requests | At most one request; no double release |
| Active-rental deposit lock | Request release during active rental | Rejected |
| Deposit dispute lock | Open dispute then request release | Rejected |
| Failed refund | Provider returns uncertain/failed status | Keep pending/reconciliation status; not refunded |
| Failed payout | Provider transfer fails | Owner payable remains outstanding; no duplicate transfer |
| Chargeback | Verified chargeback event | Dispute linked; relevant settlement restricted |
| Cross-city booking | Reader city differs from copy city | Request rejected by current launch policy |
| Owner no-show | Reader reports Owner no-show | Incident recorded; no automatic fee/forfeiture |
| Wrong no-show reporter | Owner tries to report their own no-show | Rejected |
| Duplicate refund | Replay same idempotency key | Same refund request; no duplicate movement |
| Due sweep idempotency | Run due scheduler repeatedly at same due threshold | One notification per booking/user/reminder key |
| Grace period | Advance test clock into and past grace period | No overdue state/fee proposal before grace; overdue after grace |
| Late fee cap | Run daily proposal beyond configured maximum | Proposed fees do not exceed approved cap; charged total remains zero |
| Extension approval | Owner approves zero-fee extension under enabled policy | Reservation and due timestamp move atomically |
| Paid extension gate | Owner approves extension where price/payment is required | Request stays approved_pending_payment; original due date remains |
| Reschedule collision | Owner accepts dates overlapping another reservation | Reschedule conflict; original period is unchanged |
| Cancellation with captured rent | Cancel a paid, pre-collection booking | Refund review is queued; no false refunded status |
| Early return | Reader asks for early return | Existing return QR/OTP and two-party evidence flow required |
| Claim without baseline | Submit physical damage claim without collection photos | Rejected |
| Normal wear | Attempt to file normal wear as compensation claim | Category rejected; no claim/fee |
| Respondent opportunity | Admin decides before response or response deadline | Decision rejected |
| Proportional decision | Admin approves more than amount claimed | Rejected |
| No arbitrary deduction | Decide a claim or appeal | No payment/deposit ledger or captured payment is mutated |
| Appeal | Submit and decide appeal | Appeal window, reviewer, outcome and reason are recorded |
| Case evidence IDOR | Submit case evidence with another user's path/case | Rejected |
| Safety report | Report unsafe public handover | Report and risk alert created, support queue notified |
| Block/mute | Block another user or mute a conversation | Only caller's own relationship/preferences change |
| Account suspension | Suspend user with an active rental | New activity blocked; active booking, payment and return obligations remain |

## Database checks

On local Supabase, run:

```powershell
supabase db reset
supabase db lint
supabase test db
```

The migrations include the GiST exclusion constraint for overlapping live reservations, participant/city checks, append-only case evidence and lifecycle audit events. Verify those constraints with concurrent transactions in the disposable project, not only sequential unit tests.

## Provider sandbox tests

Do not use a real-money account. The chosen provider adapter must have written approval for ShelfShare's exact marketplace model. Verify signature validation, idempotency, canonical payment lookup, refund status, payout status, chargebacks, settlement reports and late/out-of-order webhook behaviour. Never infer provider success from an HTTP 200 intent response or browser redirect.

# Critical integration test matrix

These are integration/release tests, not assertions that the current unit suite has passed them. Run only in a disposable local Supabase project and a provider sandbox.

| Scenario | Setup / fault injection | Required assertion |
|---|---|---|
| Duplicate webhook | Replay same provider event ID | One side effect and one journal posting |
| Invalid signature | Change raw body or signature | HTTP 4xx; no payment, booking or ledger mutation |
| Failed payment | Provider canonical state FAILED | Booking remains unconfirmed |
| Browser closed after capture | Suppress redirect; deliver signed webhook | Booking confirmation comes from provider event |
| Amount mismatch | Provider returns different paise amount | No capture application; reconciliation required |
| Booking race | Two concurrent requests for overlapping period | At most one live reservation |
| Expired hold plus late capture | Expire hold then return successful provider capture | Never confirm conflicting booking; refund/reconcile |
| QR replay | Redeem one token twice | First valid use only; second rejected |
| Expired QR | Redeem after expiry | No session completion |
| QR cross-booking | Redeem against another booking | Rejected by session binding |
| OTP brute force | Five invalid OTP submissions | Attempt limit and lockout apply |
| Two-party confirmation | Initiator confirms without counterparty | Booking remains pending |
| Missing evidence | Confirm without each party's condition photo | Handover cannot complete |
| Deposit release race | Two simultaneous release requests | At most one request; no double release |
| Active-rental lock | Request release during active rental | Rejected |
| Deposit dispute lock | Open dispute then request release | Rejected |
| Failed refund | Provider returns uncertain/failed state | Keep pending/reconciliation status; not refunded |
| Failed payout | Provider transfer fails | Owner payable remains outstanding; no duplicate transfer |
| Chargeback | Verified chargeback event | Dispute linked; relevant settlement restricted |
| Cross-city booking | Reader city differs from copy city | Request rejected by current launch policy |
| Owner no-show | Reader reports owner no-show | Incident recorded; no automatic forfeiture inferred |
| Wrong no-show reporter | Owner tries to report their own no-show | Rejected |
| Duplicate refund | Replay same idempotency key | Same refund request; no duplicate movement |

## Database checks

On local Supabase, also run:

```powershell
supabase db reset
supabase db lint
supabase test db
```

The migrations already include the exclusion constraint for overlapping live reservations and participant/city checks. Confirm those with concurrent transactions in the disposable project, not only sequential unit tests.

## Provider sandbox tests

Do not use a real-money account. The chosen provider adapter must have written approval for ShelfShare's exact marketplace model. Verify signature validation, idempotency, canonical payment lookup, refund status, payout status, chargebacks, settlement reports and late/out-of-order webhook behavior. Never infer provider success from an HTTP 200 intent response or browser redirect.

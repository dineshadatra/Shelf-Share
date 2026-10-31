# Booking, Payment, Deposit and QR Runtime

**Implementation status:** backend reference implementation layered over the existing ShelfShare Supabase schema. This code is not a payment-provider approval, payment certification, or production deployment.

## Existing database foundation

This repository already has the principal booking/payment tables and SQL commands in migrations 202610300001 through 202610300020, including:

- owner acceptance and atomic reservation creation;
- payment attempts and unique provider event IDs;
- verified-event application RPC;
- finance-authorised, amount-bounded refund requests;
- per-booking deposit release requests with active-rental/dispute guards;
- owner payout eligibility after verified physical collection;
- short-lived handover sessions, QR/OTP confirmation, and two-party condition-photo checks;
- read-only participant financial history.

The new Edge Functions are trusted command boundaries around those SQL operations. They do not duplicate business rules in the browser.

## Functions

| Function | Authentication | Purpose |
|---|---|---|
| create-payment-intent | Supabase user JWT | Validates renter/booking, approved provider and deposit gate; creates an idempotent payment attempt and provider checkout intent |
| payment-webhook | Provider signature, no user JWT | Verifies raw body, fetches canonical provider status, checks amount/currency/reference, and applies verified event RPC |
| create-handover-session | Supabase user JWT | Creates booking-specific QR/OTP credentials for the authenticated initiator |
| confirm-handover | Supabase user JWT | Separates initiator confirmation from counterparty QR/OTP redemption |
| handover-evidence | Supabase user JWT | Creates private signed-upload URL and validates file signature/size before registering evidence |
| request-deposit-release | Supabase user JWT | Calls booking-scoped release RPC; does not claim funds were released |
| request-owner-settlement | Supabase user JWT | Requests eligible owner payout through existing SQL guard |
| request-finance-refund | Finance/admin JWT | Creates authorized bounded refund request; actual completion requires provider confirmation |

## Provider adapter gate

_shared/payment-provider.ts defines the canonical provider contract. _shared/provider-registry.ts intentionally registers no commercial provider. Razorpay Route and Cashfree Easy Split are candidates, not approved ShelfShare providers. Add an adapter only after written approval for the exact P2P physical-book rental use case, seller onboarding, 10% split, settlement timing, refunds/chargebacks and reconciliation.

The adapter must create intents with stable idempotency, verify webhooks over exact raw bytes, fetch canonical payment status server-to-server, return exact payment ID/merchant reference/amount paise/currency, process refund and payout status, and expose settlement reports. A valid webhook signature alone is not enough to confirm payment.

## Deposit safety

Deposit collection remains BLOCKED. The existing schema records per-booking deposit status and release requests, but does not create a legally valid custody arrangement. create-payment-intent rejects bookings with a non-zero deposit because a separate approved deposit collection adapter is not implemented. There is no pooled user wallet. Do not enable deposits until provider, legal and accounting advisers approve the exact legal holder, funds flow, claim hold, partial application, release and tax treatment in writing.

## QR and evidence

- QR token: 256 bits of cryptographic randomness; only SHA-256 hash is stored.
- OTP fallback: six digits, HMAC-protected at rest with a server secret, SQL attempt limit and lockout.
- Token TTL: read from active approved workflow configuration and bounded to 60–900 seconds.
- One token/session per booking action; SQL atomically consumes it.
- Separate authenticated participants confirm their own side and initial/return condition.
- Both parties must submit at least one private evidence photograph.
- Evidence upload checks JPEG/PNG/WebP magic bytes, 10 MiB maximum and booking/actor/session-scoped object path before SQL registration.

Production deployment should additionally configure object retention, malware scanning, image metadata handling and a documented evidence-access audit process.

## Tests

Run the unit suite with Node.js 22 or newer:

```powershell
npm run test:unit
```

The tests cover monetary rounding, rent-only commission, payment matching, refund bounds, canonical state mapping, city boundary, no-show reporter authority, duplicate event detection and two-party/photo/expiry handover gates.

The full database race and provider-failure matrix still requires a local Supabase instance, disposable test users/copies, and an approved sandbox adapter. See supabase/tests/INTEGRATION_TEST_MATRIX.md.

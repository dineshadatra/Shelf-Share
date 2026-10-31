# Booking Rules — ShelfShare

## 1. Scope and principles

This specification covers requests, inventory reservation, payment confirmation, approved public handover, active rental, extension, return, cancellation, no-show and booking closure.

**Fixed from Project Master Context**
- India; Hyderabad and Bengaluru launch only.
- Locality-based discovery; cross-city rentals prohibited.
- INR and Asia/Kolkata display timezone.
- Rental durations: 3, 7, 15, 30 days and configurable custom durations.
- One physical copy is booked, not merely a book title.
- 10% platform commission on rental fee only.
- Online payment through an eligible marketplace provider.
- Owner settlement eligibility only after verified physical handover.
- Approved public handover points only; no residential address exposure.
- Collection/return require distinct owner and reader confirmation through QR with OTP fallback.
- No double booking; backend/database atomicity is mandatory.

## 2. Eligibility

Before booking, backend validates:
1. Reader account active and age 18+.
2. Mobile OTP verified.
3. Identity status `APPROVED`.
4. Required agreements and current rental agreement accepted.
5. Listing and physical copy `APPROVED` and not paused.
6. Copy owner active and verified.
7. Reader and copy are in same launch city.
8. Handover point enabled and in same permitted locality/city.
9. Rental duration allowed by current configuration.
10. Start/end dates are valid and do not overlap live reservation plus buffer.
11. Price/deposit policy snapshot exists and is active.
12. No account restriction or unresolved eligibility block.

Browse may remain available to unverified users.

## 3. Booking creation

1. Reader selects a specific physical copy and rental dates/duration.
2. Server calculates price and policy snapshot; never trust client-supplied total.
3. Server creates a short-lived inventory hold and booking in one transaction.
4. Payment intent is created via outbox/provider adapter using idempotency key.
5. Booking remains `PAYMENT_PENDING` until provider confirmation.
6. Provider failure/hold expiry releases inventory through an audited transition.
7. If provider reports success after hold expiry, attempt atomic reacquisition. If conflict exists, do not force booking; initiate appropriate refund and support case.

**Implemented flow:** Reader submits a request for one physical copy; the database creates a short-lived request hold and notifies the Owner. The Owner explicitly accepts or declines before payment. Both parties must accept the current published rental agreement. Only then can the trusted backend create a payment attempt and extend the same copy reservation. Owner acceptance is not payment confirmation; booking confirmation is provider-webhook-only. The request hold TTL, maximum request horizon and scheduling policy must be configured before checkout is enabled.

## 4. Price calculation

At booking confirmation snapshot:
- rental fee from Owner price and permitted Admin maximum;
- duration and selected pricing tier;
- platform commission = 10% of rental fee;
- deposit separately;
- applicable taxes/fees separately after CA-approved configuration;
- provider fees separately (payer allocation TBD);
- any delivery/venue charge only if explicitly configured and disclosed.

`platform_commission = round_half_up(rental_fee_paise * 0.10)` using integer arithmetic and approved rounding policy. Do not apply commission to deposit. Preserve exact calculation version.

Do not treat GMV/rental value as platform revenue.

## 5. Reservation intervals and double-booking prevention

- Each physical copy has one or more reservation intervals.
- Use PostgreSQL `tstzrange` half-open intervals `[start,end)` and a GiST exclusion constraint on `(copy_id WITH =, reserved_period WITH &&)` for active reservation states.
- Reserve interval includes configured pre/post buffer.
- A transaction creates booking + reservation hold atomically.
- Payment network call occurs outside DB transaction.
- Webhook success converts hold to confirmed atomically.
- Extension updates due date and reservation interval atomically.
- A delayed payment success cannot override a conflicting interval.
- Availability is derived from reservation/rental/hold/maintenance states; never trust client calendar.
- Hold timeout, buffer, booking horizon and rental-day convention are stored as approved deployment policy; checkout fails closed until configured.

## 6. Handover scheduling and collection

- Only approved public handover points may be selected.
- Both parties agree on location and time.
- Generate one-time short-lived QR token; store token hash, not reusable plaintext.
- Owner and Reader must authenticate independently.
- Owner confirms physical handover; Reader confirms receipt.
- Both acknowledge initial condition evidence.
- One user cannot perform both confirmations.
- Expired/replayed tokens fail; OTP fallback creates a new audited verification event.
- Only server-verified completion changes rental to `ACTIVE`.
- Owner payout becomes eligible only after this verified event, subject to PA settlement rules.

## 7. Due date and rental clock

- Rental clock starts at verified collection timestamp, not payment redirect.
- Due timestamp is computed server-side using the agreed duration semantics. Calendar-day vs exact-hour semantics are not specified in PRD and must be approved before launch.
- Store UTC instants; render Asia/Kolkata.
- Reminders and grace period are configurable.
- A scheduler transitions rental to due/overdue; client clock has no authority.
- Early return is allowed through the normal return protocol; refund of unused days is not specified and remains a policy decision.

## 8. Extension

- Reader submits request before return completion.
- Owner explicitly approves or rejects.
- Backend validates copy interval including buffer and all future reservations.
- Additional rent/commission/tax is calculated from current approved pricing rules and shown before acceptance.
- If payment is required, new due date is not committed until provider confirms payment.
- Deposit increase, if any, is not enabled until legal/provider deposit model approves.
- Failure leaves original due date and reservation interval unchanged.
- An extension is a separate immutable event, not an edit to history.

## 9. Return

- Reader initiates return.
- Both parties schedule approved public point/time.
- One-time token and independent confirmations.
- Capture return condition evidence and both acknowledgements.
- Return timestamp is verified server event.
- Owner inspection follows published inspection window (TBD).
- If no claim, close and make copy available after configured buffer.
- If damage/non-return dispute, copy remains on hold and financial actions follow claim/dispute decision.

## 10. Cancellation and no-show

The exact refund tiers and penalties are unresolved. Implement a versioned policy table with separate scenarios:
- Reader cancellation before payment.
- Reader cancellation after payment but before handover.
- Owner cancellation before handover.
- Owner no-show.
- Reader no-show.
- Mutual reschedule.
- Venue closure/unavailability.
- Safety cancellation.
- Payment failure or delayed confirmation.

No cancellation fee or penalty may be invented at runtime. A policy version must be snapshotted at booking and displayed before payment.

## 11. Booking failure and recovery

- Browser closed: provider webhook/reconciliation updates backend.
- Duplicate webhook: unique event ID and idempotency prevent duplicate effects.
- Payment success but booking row/hold cannot be committed: reconciliation case; no duplicate capture; attempt reacquisition; otherwise refund.
- Booking created but provider intent creation fails: booking moves to recoverable failure; release hold after policy timeout.
- Provider outage: disable new payment starts or show retry; never show confirmed booking.
- Notification failure: does not reverse valid booking; outbox retries.

## 12. Required audit and metrics

Audit every status transition, policy snapshot, dates, copy, user, venue, token, payment reference and reason.

Metrics: search-to-book conversion, booking failure, hold expiry, payment success/failure, handover completion, no-show, cancellation, extension, on-time return, overdue, dispute, refund and locality liquidity.

## 13. Unresolved decisions

Exact duration semantics (calendar day vs elapsed 24 hours); booking request/payment hold TTL; maximum advance booking horizon; buffer; handover window; no-show grace; reschedule count/cutoff; cancellation tiers; unused-day refund; extension cutoff; return inspection window; overdue grace; late fee; refund SLA; provider fee allocation; payout schedule.

## 14. Implemented backend and deployment notes

The current implementation is on `feat/frontend-foundation`; it is not deployed or merged to `main`. Booking creation uses `request_book_booking`, Owner approval uses `accept_book_booking_request`, and `begin_booking_payment` is service-role-only. The Reader and Owner must each accept the current rental agreement. A provider-confirmed capture webhook is the only source of payment success. Reservation creation, payment holds, participant locks, handover completion and deposit-release checks are server-side.

Collection can be resumed from `collection_pending` after an unconsumed QR expires. The initiating participant may replace an unused QR/OTP; once the other participant consumes the token, rotation is rejected and the initiator must complete their own confirmation. Return is Reader-initiated and completes only after both participants, private return-condition photos and the server-side QR/OTP flow are satisfied.

Owner no-show and Reader no-show produce incident records only. Penalties, cancellation fees, refund percentages, compensation and fee retention remain disabled until the versioned cancellation/no-show matrix is approved. Do not invent a no-show financial outcome.

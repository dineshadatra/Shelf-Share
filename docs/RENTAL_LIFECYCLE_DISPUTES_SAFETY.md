# Rental Lifecycle, Disputes and Customer Safety

**Status:** operational workflow and policy draft. The database policy row is inserted inactive. Product, legal and finance owners must approve the specific operating values before enabling reminders, extensions, rescheduling or late fees in production.

## 1. Lifecycle states and active-rental dashboard

The original `bookings.status` remains the transaction/handover state. `rental_lifecycle` is a read projection for due/overdue and return operations; an overdue flag does not rewrite or cancel the booking.

| Lifecycle state | Meaning | User action |
|---|---|---|
| Scheduled | Payment confirmed; collection not yet verified | Attend the agreed public handover |
| Active | Both parties completed collection QR/OTP and condition evidence | Track due date, request extension or early return |
| Due | Due timestamp reached; grace period still running | Return the book; no late fee accrues during grace |
| Overdue | Due timestamp plus approved grace period passed | Return immediately; contact support if there is a genuine issue |
| Return requested | Reader has started the return process | Agree public location/time and complete two-party handover |
| Returned / Completed | Return handover has completed | Inspection/claim window and closeout apply |
| Disputed | A linked case is being reviewed | Use the resolution centre; respond and submit evidence |
| Cancelled | Pre-collection booking cancelled | Any captured payment moves to refund review; it is not treated as refunded |

`get_my_active_rentals()` returns participant-scoped records. `run_rental_due_sweep()` updates due/overdue projection and queues in-app reminders; it does not send SMS directly or change provider payment truth. Connect the scheduler to `rental-due-sweep` using a secret of at least 32 bytes and a trusted schedule.

## 2. Proposed service timing (requires approval)

The initial inactive policy row has a **24-hour grace period** as a proposed default, plus reminder thresholds at 72 hours, 24 hours and the due time. The following are draft defaults only:

- Grace period: 24 hours after the stored rental due timestamp.
- No-show reporting: 24 hours after the scheduled handover time.
- Claim response window: 48 hours.
- Appeal window: 72 hours from the recorded decision.
- Return inspection window: 48 hours.
- Late fee: disabled until an amount, maximum, legal approval and accounting approval are saved.

A policy is not live until an authorised operator sets `is_active=true`, records approver identity/time and has published the matching customer-facing version. Changing timing requires a new policy version; do not silently rewrite a booking's original terms.

## 3. Extensions, early return, rescheduling and cancellation

### Extension

1. Reader asks before the current due time and supplies a reason/new due timestamp.
2. Owner receives an in-app notification and accepts/rejects with a reason.
3. The inventory reservation is checked atomically against future reservations.
4. A zero-fee extension is committed only when the approved policy explicitly permits it.
5. If extra rent is required, the request stays `approved_pending_payment`; neither the due date nor reservation is extended until a provider-approved extension pricing/payment path is implemented and confirmed. Do not treat owner approval as payment.

### Early return

Reader requests early return. The booking moves to the existing return handover flow. Both parties must independently confirm QR/OTP and submit condition evidence; no refund for unused days is assumed by the backend.

### Rescheduling

Available only before physical collection, with Owner approval, the configured cutoff and maximum request count. New dates must retain the same duration and pass the same physical-copy reservation constraint. A collision rejects the reschedule and leaves the original dates unchanged. Any price/refund adjustment requires a separately approved pricing/refund rule.

### Cancellation

A pre-collection cancellation releases the reservation. If payment was captured, the cancellation becomes `refund_review_required` and creates an outbox finance task. It is not marked refunded until a provider confirms a refund. No cancellation penalty, retention or refund percentage is inferred by this module. Active rentals use early return/dispute, not cancellation.

## 4. Late fee control

Late fees are **proposals**, not deductions. The scheduled function calculates one daily proposal after the grace period, using the approved daily amount and maximum; each booking/day is idempotent. It writes `late_fees.status='proposed'` and returns `late_fees_charged: 0`.

To enable late fees, an operator must publish a policy version and set the daily amount, maximum, legal approval reference, accounting approval reference and approver. The customer must have seen and accepted the terms before the rental. A proposed fee can be disputed or waived. No admin may silently debit a deposit, bank account, owner earnings or customer payment method.

## 5. Damage, loss and non-return policy

### Evidence standard for every claim

- Baseline: original listing/collection condition and time-stamped collection photos.
- Return: photos from both parties, actual returned item, and inspection notes.
- Claimant: clear description, date discovered, item/edition/ISBN where relevant, requested amount and repair/replacement estimate/receipt.
- Respondent: access to the claim and ability to respond with their own photos, explanation and counter-estimate.
- Decision: reasoned explanation, evidence list, amount requested, amount allowed and policy version.

Evidence must be stored privately. Only rental participants and specifically authorised case staff may access it. Do not rely on a single party's unsupported assertion where contemporaneous evidence is reasonably available.

### Category outcomes

| Category | Treatment | Compensation principle |
|---|---|---|
| Normal wear and tear | Not a compensable claim. Examples: reasonable reading wear, slight spine creasing, page yellowing from age, minor cover scuffing consistent with the disclosed starting condition | ₹0 claim. Do not charge for ordinary use or pre-existing defects. |
| Minor damage | Small, repairable tear, loose non-critical binding, minor cover damage beyond baseline | Reasonable evidenced repair cost only; no automatic replacement price. |
| Major damage | Material damage that makes the book unsafe/unusable or uneconomic to repair | Prefer documented repair. If genuinely beyond repair, use fair comparable second-hand replacement value adjusted for age, edition and pre-rental condition. |
| Missing pages | Pages/sections missing beyond the disclosed baseline | Verified page/section replacement cost where feasible; replace the book only if repair is not reasonably possible and the missing content materially impairs use. |
| Water damage | Swelling, staining, mould, ink bleed or binding failure caused during the rental | Evidence of the change from baseline plus reasonable drying/repair estimate. Replacement only if not reasonably repairable. |
| Lost book | Reader cannot return the specific physical copy | After approved grace period and reasonable contact attempts, establish loss with case evidence. Use fair second-hand replacement value for comparable edition/condition, less age/depreciation; not the new retail list price by default. |
| Non-return | Book not returned after the due time and approved grace period | Start contact/support workflow first. Non-return is not proof of theft or automatic forfeiture. Escalate to lost-book claim only after documented attempts and review. |
| Wrong book returned | Returned physical item does not match the booked copy | Compare ISBN/edition/identifying marks and collection/return photos. Seek return of the correct item first; compensation must reflect proven loss/cost, not an arbitrary penalty. |

### Proportional valuation formula (policy framework)

Use the lowest substantiated amount that reasonably restores the evidenced loss:

`allowable_compensation = min(verified_repair_cost, fair_second_hand_replacement_value_adjusted_for_condition)`

Where repair is not feasible, use a documented fair replacement valuation. Record the evidence source, comparable edition, age/condition adjustment and any salvage/partial recovery. This is a decision framework, not a fixed tariff. Do not use new retail price, speculative future loss, punitive multiplier or the whole deposit without evidence and a separate lawful/provider-approved funds flow.

Normal wear and tear is always excluded. The claimant must substantiate a change from collection baseline. The respondent must receive notice and reasonable response time. A non-zero decision must explain why the amount is proportionate.

## 6. Resolution centre and appeals

1. Owner submits a claim; the system creates a linked dispute and notifies the Reader.
2. Both participants can read case messages and add evidence. Messages are immutable.
3. Staff wait for respondent response or the configured response deadline.
4. Only authorised Admin/Super Admin can decide a compensation claim. Decisions are bounded by the amount requested and must include a code and a reasoned explanation.
5. A participant may appeal within the policy window. A different authorised reviewer should be assigned where staffing permits.
6. The appeal outcome and any revised amount are recorded as a new auditable decision.
7. **No decision RPC debits a deposit or payment account.** The approved amount is a resolution record. Collection, refund, deposit application or owner compensation needs a separate lawful, provider-approved, user-visible financial operation.

## 7. Safety and abuse controls

- Report a user, physical-copy listing, booking or handover location with severity and details.
- Unsafe handover, harassment, threats and physical-safety reports create a risk alert and an operations outbox item.
- Block prevents future contact/discovery according to frontend policy; it does not cancel a booking or remove active obligations.
- Mute is personal notification preference for a conversation; it does not prevent case notifications or emergency support.
- Safety support creates an urgent in-app grievance ticket. Publish an external phone number only after the company verifies ownership and staffing.
- Account restriction/suspension blocks new activity through existing account checks. It does not delete bookings, erase evidence, cancel payments or abandon active rentals. Existing counterparties receive a support notice and open obligations remain visible to authorised staff.
- Account closure is not allowed while active rental, payment, refund, claim or dispute obligations remain.
- Never publish private home addresses; use approved public handover points.

For immediate physical danger, users should move to a safe public location and contact local emergency services. ShelfShare in-app support is not an emergency-response service.

## 8. Audit and operational ownership

Every cancellation, extension, reschedule, early return, no-show, reminder, claim, response, evidence upload, decision, appeal, block, mute, safety report, suspension and resolution is recorded with actor, timestamp, reason, booking/case reference and idempotency key where applicable. Event and evidence history is append-only. Admin decisions also write admin audit records.

Operations should review an inbox for:

- due/overdue rentals and failed notification delivery;
- extension/reschedule conflicts and pending approvals;
- captured-payment cancellation/refund review;
- no-show/safety reports;
- claims awaiting evidence or response;
- appeals and unresolved safety incidents;
- proposed late fees awaiting user response and finance/legal approval.

## 9. Explicit release gates

- The policy row remains inactive until its customer terms and values are approved.
- Late fees remain disabled until legal and accounting references are supplied.
- Paid extensions remain pending until provider-approved pricing/payment implementation exists.
- No automatic cancellation penalty, deposit deduction, non-return forfeiture or loss compensation is enabled.
- Storage retention, malware scanning, signed evidence access and staff case permissions must be tested before live operation.

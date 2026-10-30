# Cancellation and Rescheduling Policy — Draft for Professional Review

**Status: Draft only. Not legally approved.**
The Project Master Context requires separate treatment for Reader cancellation, Owner cancellation, no-show, rescheduling, venue closure and safety cancellation, but it does not approve exact refund tiers or penalties. The parameters below remain `TBD`.

## 1. General rules

- The booking-specific policy version is displayed before payment and stored with the booking.
- No hidden charges or preselected add-ons.
- Rent, platform commission, deposit, tax and provider fees are separate lines.
- No ordinary off-platform payment.
- Refund is processed through the original eligible provider flow unless law/provider rules require otherwise.
- A refund is complete only when provider confirms it.
- Deposit refund is distinct from rental refund and subject to approved deposit arrangement.
- Do not impose consumer cancellation charges without legal review of the applicable E-Commerce Rules, including symmetry requirements.

## 2. Reader cancellation

### Before payment
- Booking request/payment attempt may be cancelled.
- Release inventory hold.
- No rent captured; any authorisation void handled by provider.
- No cancellation charge unless a lawful disclosed amount applies (not currently approved).

### After payment, before verified collection
- Reader may request cancellation.
- Apply booking's accepted cancellation policy version.
- Calculate refundable rent and any permitted fee separately.
- Deposit, if collected under approved structure, is processed separately.
- Release copy reservation only after cancellation transaction is safely recorded.
- Refund status remains pending until provider confirmation.

### After verified collection
- This is not a pre-rental cancellation. Treat as early return under return workflow.
- Any unused-rental refund is `TBD`; do not promise pro-rata refund unless policy says so.

## 3. Owner cancellation

Before collection:
- Owner cancellation reason required.
- Reader notified promptly.
- Full/partial refund outcome follows approved policy; do not charge an Owner penalty until amount and legality approved.
- Copy reservation released after transaction.
- Record Owner cancellation reliability event.

After collection:
- Owner cannot cancel active rental as if no transaction occurred.
- Safety/urgent issue enters support/dispute workflow; return arranged at approved public point.

## 4. No-show

A no-show is not inferred solely because a QR token expired. Record scheduled time, venue, check-in/attempts, communications and both parties' statements.

### Owner no-show
- Reader reports no-show from booking screen/support.
- System records evidence and enters `NO_SHOW_REVIEW`.
- Support verifies venue/time and contacts Owner.
- If confirmed, booking cancellation/reschedule outcome follows approved policy; Reader refund and any reasonable remedy are calculated under versioned policy.
- Owner reliability signal may be updated after review; repeated cases may trigger human account review.

### Reader no-show
- Owner reports no-show.
- Support verifies evidence and contacts Reader.
- If confirmed, cancellation/refund/fee outcome follows approved policy.
- Do not automatically confiscate deposit or charge arbitrary fee.
- Repeated confirmed no-shows may trigger review.

No-show grace period, contact attempts and fee/refund tiers are TBD.

## 5. Mutual rescheduling

- Either party proposes new time/place through platform.
- Other party explicitly accepts.
- Venue remains approved and same launch city.
- Check copy reservation, venue availability and all applicable time windows.
- Revoke old QR token; issue a new one only after both accept.
- Rescheduling does not alter payment amount unless a disclosed additional charge is approved.
- Record old and new schedule.
- Reschedule count and cutoff are TBD.

## 6. Venue closure or safety issue

- Do not force users to meet at an unapproved/private/isolated location.
- Support proposes another approved public point in the same permitted city/locality.
- If no safe point/time is available, cancel under a separately configured neutral-cancellation rule.
- Refund treatment is TBD but must be transparent and reviewed.
- No reliability penalty should be applied to a party not responsible for venue closure/safety event.

## 7. Payment failure or delayed confirmation

- Definitive payment failure: release hold and mark payment failed.
- Pending payment: retain hold only for configured provider-approved duration.
- Late success after hold expiry: attempt atomic reacquisition; if conflict, refund and support.
- Never mark booking paid from browser redirect.
- Never charge twice due to retry.

## 8. Refund calculation framework

The rules engine should use a table keyed by:
`cancelling_party`, `booking_state`, `time_to_collection`, `reason_code`, `policy_version`, `captured_rent`, `deposit_status`, `provider_fee_treatment`.

The actual percentage/amounts and cutoffs remain TBD. No default production rule should be invented.

## 9. Notifications and records

Notify both parties of cancellation/reschedule proposal, acceptance, decision, refund initiation and provider confirmation. Preserve reason, evidence, policy version, amount calculation and provider references.

## 10. Parameters requiring approval

Reader cancellation tiers; Owner cancellation outcome; no-show grace and proof; reschedule cutoff/count; safety/venue closure refund; unused-day refund; fee retention; refund SLA; provider fee allocation; deposit release timing.

**Professional review:** Indian consumer-law lawyer, CA and selected payment provider.

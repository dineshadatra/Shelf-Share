# Return, Overdue and Non-Return Policy — Draft for Professional Review

**Status: Draft only. Not legally approved.**
This draft follows the PRD requirements for QR-based return, condition evidence, reminders, grace period, late fees, dispute review and proportional compensation. Exact time periods and fee formulas remain TBD.

## 1. Return process

1. Reader initiates return in the active booking.
2. Reader and Owner agree on an approved public handover point/time.
3. Backend validates same city, venue status and rental identity.
4. Backend issues a one-time, short-lived QR token; OTP fallback is available.
5. Owner and Reader independently authenticate and confirm the physical return.
6. Both capture/acknowledge return-condition evidence.
7. Backend verifies distinct actors, token validity and event sequence.
8. Record `returned_at` using server time.
9. Owner inspection occurs within configured inspection window.
10. If accepted/no claim, booking closes after financial/deposit steps and copy becomes available after buffer.
11. If claim, move to damage/dispute workflow; do not automatically deduct deposit.

One person cannot confirm both sides. QR tokens are single-use and replay protected.

## 2. Condition evidence

Compare return evidence with pre-collection baseline:
- front/back cover;
- spine;
- pages and completeness;
- existing defects;
- stains, tears, water damage, writing/highlighting and binding;
- timestamp, booking and copy reference.

Preserve originals and hashes. Do not overwrite baseline evidence.

## 3. Early return

Reader may return before due date using the same protocol. Whether unused days are refunded is unresolved and must be explicitly stated before booking. No pro-rata refund should be inferred.

## 4. Due date and reminders

- Due date is server-calculated from verified collection time and selected duration.
- Duration semantics (exact hours vs calendar days) require product decision.
- Reminder schedule and grace period are Admin-configurable.
- All times shown in Asia/Kolkata; stored as UTC instants.
- Failed SMS should not prevent in-app notice; channel use must respect applicable consent and messaging rules.

## 5. Overdue and late fees

- Rental moves to overdue only after due timestamp plus approved grace period.
- Reader receives overdue notice and clear return instructions.
- Late fee may be charged only if a formula, cap, disclosure, consent/contract and legal/CA treatment are approved.
- Do not silently debit a payment instrument.
- Do not add arbitrary daily fees or compound them without express approved policy.
- Extension request does not pause overdue status unless extension is approved and any required payment succeeds.
- Late-fee formula and maximum are TBD.

## 6. Non-return

If no verified return occurs:
1. System sends due and overdue reminders.
2. After configured threshold, Owner may report non-return.
3. Reader receives a response request and opportunity to provide evidence/status.
4. Support reviews communications, handover record and attempts to arrange return.
5. Admin investigates; safety concerns escalate.
6. Any compensation decision is reasoned and evidence-based.
7. Appeal route is provided.
8. Deposit application, if any, requires approved provider/legal mechanism and cannot be automatic.
9. Account restrictions may be considered under suspension policy, but active obligations and refunds are preserved.

Ordinary non-return is not automatically labelled a criminal offence. Legal escalation is a separate counsel-guided decision based on facts.

## 7. Lost book or irreparable damage

Use the damage valuation framework:
- same edition/current replacement availability;
- reasonable equivalent edition where exact copy unavailable;
- original price if evidenced;
- age and pre-rental condition;
- repairability and actual loss;
- no double recovery.

Do not automatically charge original cover price or full new-book price for an old/damaged copy.

## 8. Disputed return condition

- Owner files claim within `DAMAGE_CLAIM_WINDOW` (TBD).
- Reader receives evidence and `READER_RESPONSE_WINDOW` (TBD).
- Admin reviews baseline and return photos, timestamps, party statements and repair/replacement estimates.
- Decision records findings and calculation.
- Either party may appeal within `DAMAGE_APPEAL_WINDOW` (TBD).
- No automatic deduction while claim is merely submitted.
- Deposit hold only where provider/legal terms allow.

## 9. Copy availability after return

A returned copy remains unavailable while:
- return confirmation incomplete;
- inspection buffer active;
- damage claim/dispute requires quarantine;
- maintenance hold is active.

Only backend derived availability can reopen the copy.

## 10. Notifications and audit

Notify Reader and Owner at return request, schedule, token issue, return confirmation, inspection, overdue, claim, decision and closure. Record each event, actor, policy version, evidence hashes, due/return timestamps and ledger references.

## 11. Parameters requiring approval

Duration semantics; reminder schedule; grace period; late fee formula/cap; inspection window; availability buffer; claim window; response/appeal windows; non-return escalation threshold; compensation valuation; deposit hold/release; early-return refund; refund SLA.

**Professional review:** Indian consumer-law lawyer, CA and selected payment provider.

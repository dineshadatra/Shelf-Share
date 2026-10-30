# User Journeys
## Peer-to-Peer Physical Book Rental Marketplace

This document describes source-derived journeys. Branches that require policy choices are marked OPEN DECISION.

## 1. Guest discovery journey

**Goal:** Find a physical book available nearby without creating an account.

1. Open marketplace.
2. Browse/search by title, author, genre, language or locality.
3. Use list/map discovery.
4. Open copy details: condition, owner-facing public profile information, rental price, deposit requirement, available dates and approved handover options.
5. If the guest attempts to book, prompt registration and verification.

**Rules:** Guest browsing is permitted. Guest wishlist behaviour is OPEN DECISION. Do not expose residential addresses or private identity evidence.

**Failure paths:** No local results → allow date/locality/filter adjustment. Map provider failure → retain list discovery. Listing becomes unavailable → show current status and prevent checkout.

## 2. New user registration and identity verification

**Goal:** Create a secure, verified account.

1. Enter Indian mobile number.
2. Receive SMS OTP.
3. Enter OTP within expiry; resend only after cooldown.
4. Complete first-time live camera photo capture.
5. If camera cannot be used, follow accessible support/fallback process (OPEN DECISION).
6. Review separate Terms, Privacy Policy, Marketplace Rules, Identity Verification Consent and required communication consents.
7. Accept required documents individually; each acceptance is recorded with version/hash/timestamp/user ID.
8. Submit identity document according to preference: Passport; otherwise PAN; otherwise Driving Licence.
9. Identity enters SUBMITTED and UNDER_REVIEW.
10. Admin reviews and approves, rejects or requests more information.
11. User receives decision/status notification.
12. Approved user gains transactional marketplace eligibility.

**Failure paths:** Invalid OTP → retry within limits. OTP abuse → rate limit. Upload error → retry. Additional information → user submits requested evidence. Rejection/suspension → status and appeal/review route per approved policy.

**OPEN DECISIONS:** Whether document submission is mandatory before any account access beyond browsing; address proof; age verification; exact fallback; identity data retention.

## 3. Reader searches and books a copy

**Goal:** Reserve an available local copy.

1. Sign in and verify identity.
2. Search by book and locality/date.
3. Filter by availability, condition, duration, language and handover point.
4. Open a specific physical copy.
5. Review metadata, actual photos, condition, owner, rental price, deposit, dates and terms.
6. Select a supported duration: 3, 7, 15, 30 days or configured custom duration.
7. Backend checks identity, city, availability, buffer, booking conflict and price ceiling.
8. Accept rental agreement.
9. Review itemised rental fee, commission treatment if displayed, deposit and applicable charges.
10. Complete online payment.
11. Backend verifies provider webhook/signature and idempotency.
12. Booking moves through approved payment/booking states.
13. Reader and Owner schedule collection at an approved public point.

**OPEN DECISION:** Does the Owner accept a request before payment, after payment, or is the booking automatically confirmed when payment succeeds? Exact reservation expiry during payment is also OPEN DECISION.

**Failure paths:** Conflict → choose another date/copy. Payment failure → remain unpaid and permit safe retry. Browser closure → backend reconciles provider result. Duplicate webhook → no duplicate charge/state transition. Cross-city selection → reject.

## 4. Owner creates a listing

**Goal:** Make one physical copy rentable.

1. Sign in and complete identity approval.
2. Add or select book metadata.
3. Optionally use ISBN lookup to prefill metadata.
4. Create a physical copy record.
5. Upload actual photos and declare lawful ownership/authority.
6. Record condition and any existing damage.
7. Set rental price and deposit requirement.
8. Backend validates price against configured maximum.
9. Submit listing for publication/moderation.
10. Configure availability calendar.
11. Maintain availability and respond to booking/handover requests.

**Failure paths:** Prohibited reproduction → reject. Pricing above ceiling → explain allowed range. Missing photo/evidence → request completion. Metadata lookup unavailable → manual entry.

## 5. Collection and rental activation

**Goal:** Transfer physical possession with reliable evidence.

1. Payment is confirmed by provider-backed backend state.
2. Both parties select an approved public handover point and schedule.
3. Backend creates unique short-lived QR token.
4. Owner authenticates and confirms Owner-side handover.
5. Reader authenticates and confirms Reader-side collection.
6. Both inspect the copy and acknowledge initial condition evidence.
7. Backend verifies token, participants, sequence, expiry and anti-replay conditions.
8. Booking becomes ACTIVE.
9. Owner settlement becomes eligible under payment-provider rules.

**Failure paths:** QR expired → issue a new authorised token. QR replay → reject and log. One party absent → no activation; follow no-show/reschedule policy. One person attempts both confirmations → reject. Venue closes → approved reschedule/cancellation path.

## 6. Active rental and extension

**Goal:** Keep rental status, due date and communication accurate.

1. Reader sees active rental and due date.
2. Platform sends configured reminders.
3. Reader may request extension.
4. Owner reviews request.
5. Backend checks future availability and buffer.
6. Reader completes any required extension payment.
7. Backend confirms payment and updates due date.
8. If extension is denied or payment fails, original due date remains unchanged.

**OPEN DECISIONS:** Extension request cut-off, maximum number/length of extensions, extension pricing and reminder cadence.

## 7. Return and completion

**Goal:** Return the book and close rental.

1. Reader initiates/schedules return.
2. Both parties select an approved public handover point.
3. Authenticated QR/OTP flow confirms each party's action independently.
4. Parties capture return condition: front, back, spine, pages and new damage.
5. Both acknowledge evidence or record disagreement.
6. If no dispute, rental moves through RETURNED to COMPLETED.
7. Deposit is released/refunded according to approved provider/legal mechanism.
8. Eligible reviews become available.

**Failure paths:** Reader late → overdue/grace process. Owner absent → no-show policy. New damage alleged → dispute workflow. Book not returned → non-return process.

## 8. Cancellation, no-show and rescheduling

**Goal:** Apply fair, transparent outcomes.

1. Reader or Owner selects cancellation/no-show/reschedule reason.
2. System records time, actor, booking state and available evidence.
3. Approved policy determines refund, deposit, fee, compensation and account impact.
4. Payment/refund operation is executed by provider.
5. Backend reconciles outcome and updates booking state.
6. Both parties receive status and next steps.
7. Safety-related cases may be escalated.

**OPEN DECISION:** Policy matrix, cut-offs, no-show evidence, reschedule limits and monetary outcomes. Do not implement guessed percentages.

## 9. Damage dispute

**Goal:** Resolve alleged damage proportionately.

1. Owner or Reader opens dispute and describes issue.
2. Submit before/after images and relevant messages.
3. Other party receives notification and response opportunity.
4. Admin reviews original condition, return condition, age, edition, replacement availability, repairability and actual damage.
5. Admin records findings and policy basis.
6. Decision and any provider-supported adjustment/refund are processed.
7. Parties are notified and may appeal.
8. Case closes with audit trail.

**Rules:** Normal wear and tear is not automatically damage. Do not automatically charge original purchase price or confiscate deposit.

## 10. Non-return journey

1. Due date passes.
2. Reminder and approved grace period apply.
3. Owner may initiate non-return case.
4. Reader receives notice and response opportunity.
5. Admin reviews timeline, handover evidence, communications and submitted evidence.
6. Admin records outcome under approved policy.
7. Compensation, if justified, is proportional and provider/legal compliant.
8. Appeal path remains available.
9. Account restrictions must consider active obligations and fairness.

**Rule:** Ordinary non-return is not automatically characterised as a criminal offence.

## 11. Owner earnings and payout

1. Owner completes verified collection handover.
2. Backend marks settlement eligibility under provider rules.
3. Finance view displays gross rental fee, 10% commission, provider fees/taxes where applicable, adjustments and net settlement as defined by accounting policy.
4. Provider processes settlement.
5. Platform records provider status and reconciles it.
6. Failed payout creates an exception and support workflow.

**OPEN DECISIONS:** Provider, settlement schedule, KYC/vendor onboarding, fees, withholding and tax display.

## 12. Admin identity review

1. Admin signs in with privileged account.
2. Opens assigned verification queue.
3. Accesses private evidence only if authorised.
4. Checks submission and policy requirements.
5. Approves, rejects or requests more information with reason.
6. System records actor, timestamp, status, reason and document version.
7. User receives notification.
8. Reviewer cannot bypass audit or grant themselves broader access.

## 13. Admin dispute and safety review

1. Case enters queue from report, damage, non-return, fraud alert or grievance.
2. Admin confirms scope and access permission.
3. Reviews timeline, evidence, counter-evidence and prior actions.
4. Requests information if needed.
5. Records reasoned decision under approved policy.
6. Executes permitted status/financial action through controlled workflow.
7. Notifies affected parties.
8. Handles appeal or escalation.
9. Closes case with audit trail.

## 14. Community and exchange journey

1. Registered user creates post/comment/list/challenge or joins club.
2. Other users engage under community rules.
3. Users can report, block or mute.
4. Moderator reviews flagged content and records action.
5. Book exchange requires separate mutual approval by both parties.
6. Any physical exchange uses approved public handover points and safety workflow.

**OPEN DECISIONS:** Whether community is part of MVP, eligibility rules, moderation staffing, exchange liability and whether chat opens before booking.

## 15. Journey-wide service principles

- Do not expose residential addresses or private identity evidence.
- Do not treat frontend status as authoritative for payment or booking.
- Do not activate a rental before complete two-party handover verification.
- Do not allow a single party to confirm both sides.
- Make every important state change visible to affected users.
- Provide reasoned, auditable admin decisions and an appeal path where specified.
- Do not silently invent financial policy.

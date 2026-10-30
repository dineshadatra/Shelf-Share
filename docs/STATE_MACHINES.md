# State Machines and Business Rules — ShelfShare

**Status:** Engineering specification derived from the ShelfShare Project Master Context. Policy values that the source has not decided are explicitly marked `TBD / CONFIGURABLE`; this document does not silently turn proposals into approved policy.
**Timezone:** `Asia/Kolkata`; money currency `INR`.
**Initial cities:** Hyderabad and Bengaluru only; no cross-city rentals.
**Actors:** Reader, Owner, Admin, System, Payment Provider, SMS Provider, Approved Handover Venue (venue is a location, not an account role).

## 1. Global invariants

1. One account may act as Reader and Owner; permissions are contextual to the action.
2. Only users aged 18+ and identity-verified users may list, book, transact or receive payouts. Unverified users may browse.
3. Mobile OTP is the authentication method. Email OTP is not permitted for registration/login. Email may be optional for receipts/recovery.
4. First-registration profile photograph is camera-captured; gallery upload is not an alternative. Provide accessible fallback/support.
5. Identity documents are privately stored and manually reviewed by authorised Admins. Preference: Passport, else PAN, else Driving Licence. PAN is not address proof.
6. Physical books only. Book metadata and each physical copy are separate entities. ISBN/cover image does not prove ownership.
7. Only approved public handover points; never expose residential addresses or direct users to isolated locations.
8. INR only; Hyderabad and Bengaluru locality-based discovery; cross-city rental forbidden.
9. Platform commission is 10% of rental fee. Deposit is separate. Do not calculate commission on deposit.
10. Do not hardcode rental caps, grace periods, late fees, buffers, cancellation amounts or damage values; use versioned Admin configuration after policy/legal approval.
11. Reader pays online through an eligible marketplace provider. Owner settlement eligibility occurs only after verified physical collection. Actual settlement must follow the provider's approved product and contract.
12. Do not create informal escrow, unregulated wallet or platform custody. Deposit collection/hold/release remains disabled until provider and legal approval.
13. Backend is authoritative. Frontend status, QR screenshots, browser redirect and client clocks are never sufficient proof of a financial or physical event.
14. Every state change is an append-only audit event with actor, server timestamp, correlation ID, prior state, next state, reason, source and related evidence.
15. External events are idempotent. Duplicate webhook, QR replay or retry must not duplicate money movement or state transitions.
16. All money is represented in integer paise. Never use floating point for money.
17. A copy cannot have overlapping confirmed/reserved rental intervals. Database transaction safety is mandatory.
18. Rental becomes ACTIVE only after both distinct parties have authenticated and confirmed collection and condition evidence has been acknowledged.
19. Extension changes due date only after Owner approval, conflict check and any required additional payment is confirmed.
20. Return closure requires return handover evidence and both-party confirmation, or an Admin-reviewed exception.
21. No arbitrary damage deductions or automatic deposit confiscation.
22. No automatic assertion that ordinary non-return is a criminal offence.
23. Community/chat requires report, block, mute and moderation controls.
24. Reviews are permitted only after a completed rental.
25. All policies and agreements are versioned. Record version, hash, accepted timestamp, user ID and relevant transaction ID.

## 2. State machine conventions

- `TBD` means the PRD/master context requires the workflow but does not settle the value.
- A timeout is evaluated by server-side scheduled jobs; clients cannot move a state by waiting locally.
- Terminal states are immutable except through a new compensating transaction or a separately audited Admin correction.
- Admin override must require reason, permission, evidence and audit record; it must not rewrite history.
- State machine status and payment ledger status are separate aggregates. Booking state must never be used as a substitute for money ledger state.

## 3. State machines

### SM-01 — User verification

**States:** `NOT_STARTED`, `DRAFT`, `SUBMITTED`, `UNDER_REVIEW`, `ADDITIONAL_INFORMATION_REQUIRED`, `APPROVED`, `REJECTED`, `SUSPENDED`, `REVERIFICATION_REQUIRED`.

**Transitions**
- `NOT_STARTED → DRAFT`: User starts verification; backend confirms mobile OTP and 18+ eligibility gate.
- `DRAFT → SUBMITTED`: User uploads selected identity evidence and submits declarations/consents; validate required fields, file type/size, consent version and private storage.
- `SUBMITTED → UNDER_REVIEW`: System queues; authorised Admin claims review.
- `UNDER_REVIEW → APPROVED`: Admin approves; verify document legibility, identity consistency, age and required address check; record reviewer and evidence reference.
- `UNDER_REVIEW → ADDITIONAL_INFORMATION_REQUIRED`: Admin requests specific missing/unclear evidence; notify user.
- `ADDITIONAL_INFORMATION_REQUIRED → SUBMITTED`: User supplies requested information.
- `UNDER_REVIEW → REJECTED`: Admin records reason and appeal/retry instructions.
- `APPROVED → REVERIFICATION_REQUIRED`: Admin/system policy trigger (document expiry, material identity change, risk signal or periodic review); trigger must be explainable and audited.
- `REVERIFICATION_REQUIRED → UNDER_REVIEW`: User resubmits.
- Any nonterminal state `→ SUSPENDED`: authorised Admin for suspected fraud, legal request or safety concern; reason and scope required.
- `SUSPENDED → UNDER_REVIEW` or `APPROVED`: authorised Admin after review; reinstatement must be reasoned.

**Invalid:** User self-approves; automated model approves in place of required manual review; PAN treated as address proof; unverified user lists/books/gets paid/transacts; Admin edits submitted evidence without trace.

**Payment consequence:** No financial transaction, booking, listing activation or payout until `APPROVED`. Suspension blocks new financial activity; existing active rentals follow SM-20 and active-rental obligations.

**Notifications:** submission receipt; review started; additional info request; approval/rejection; suspension/reinstatement; re-verification reminder.

**Audit:** consent version/hash, document metadata/hash, reviewer, decision, reason, timestamp, access log, status transition.

**Retry/failure:** upload retry via signed/private upload; preserve draft; rate limit submissions; Admin queue retry; do not create duplicate verification cases on network retry.

### SM-02 — Book listing

**States:** `DRAFT`, `SUBMITTED`, `UNDER_REVIEW`, `NEEDS_CHANGES`, `APPROVED`, `PAUSED_BY_OWNER`, `PAUSED_BY_ADMIN`, `REJECTED`, `ARCHIVED`.

**Transitions**
- Owner creates `DRAFT`; must be verified, 18+, and declare lawful ownership/authority.
- `DRAFT → SUBMITTED`: metadata, copy condition, actual photos, price, deposit requirement (if legally/provider enabled), locality and availability supplied.
- `SUBMITTED → UNDER_REVIEW`: System queues moderation.
- `UNDER_REVIEW → APPROVED`: Admin confirms listing/copy policy; copy becomes eligible for availability only if all other controls pass.
- `UNDER_REVIEW → NEEDS_CHANGES`: Admin requests corrections.
- `NEEDS_CHANGES → SUBMITTED`: Owner updates.
- `UNDER_REVIEW → REJECTED`: Admin records policy reason.
- `APPROVED ↔ PAUSED_BY_OWNER`: Owner pauses/unpauses only if no conflicting confirmed rental; cannot pause to evade an accepted booking.
- `APPROVED → PAUSED_BY_ADMIN`: Admin safety, IP, fraud or policy hold.
- `PAUSED_BY_ADMIN → APPROVED` or `REJECTED`: Admin decision.
- `APPROVED/PAUSED/REJECTED → ARCHIVED`: Owner/admin archive subject to active rental obligations.

**Invalid:** listing without verified owner; no copy-specific photos/condition; listing counterfeit/photocopy; listing residential address; Owner edits listing price/condition retroactively for an active booking; archiving erases rental evidence.

**Payment consequence:** Listing state alone never moves funds. Price/configuration snapshot is copied to booking at confirmation.

**Notifications:** submission, changes requested, approval/rejection, pause, safety/IP hold.

**Audit:** metadata changes, price changes, condition/photo hashes, reviewer and reason, ownership declaration, publication state.

**Retry/failure:** photo upload retry; preserve draft; moderation queue retry; Admin escalation for overdue queue.

### SM-03 — Physical copy availability

**States (derived, not manually edited):** `UNLISTED`, `AVAILABLE`, `HELD_PENDING_PAYMENT`, `BOOKED`, `HANDOVER_DUE`, `RENTED`, `RETURN_PENDING`, `DISPUTED_HOLD`, `MAINTENANCE_HOLD`, `UNAVAILABLE`.

**Transitions**
- Listing approved and no active/held interval → `AVAILABLE`.
- Atomic booking reservation → `HELD_PENDING_PAYMENT`.
- Payment confirmed and booking valid → `BOOKED`.
- Handover scheduled window begins → `HANDOVER_DUE`.
- Verified collection → `RENTED`.
- Return initiated → `RETURN_PENDING`.
- Return evidence accepted → `AVAILABLE` after configured cleaning/inspection buffer.
- Damage/dispute/non-return → `DISPUTED_HOLD`.
- Owner/Admin marks copy unusable → `MAINTENANCE_HOLD` or `UNAVAILABLE`.
- Hold resolved and no overlapping reservation → `AVAILABLE`.
- Listing archived → `UNLISTED` after obligations close.

**Invalid:** manually setting AVAILABLE while active rental/overlapping reservation exists; two overlapping confirmed/held intervals; availability inferred only from frontend calendar.

**Payment consequence:** Availability reservation is not itself a capture. Payment is separately recorded; expired reservation triggers provider cancellation/void/refund as applicable.

**Notifications:** booking hold, confirmed booking, unavailable conflict, return/inspection closure.

**Audit:** each availability interval, reservation expiry, manual hold, conflict rejection.

**Retry/failure:** recompute derived state from booking/rental/hold aggregates; scheduled reconciliation detects stale derived values.

### SM-04 — Booking

**States:** `REQUESTED`, `PAYMENT_PENDING`, `PAYMENT_CONFIRMED`, `HANDOVER_SCHEDULED`, `HANDOVER_PENDING`, `ACTIVE`, `EXTENSION_REQUESTED`, `EXTENDED`, `RETURN_REQUESTED`, `RETURN_PENDING`, `OVERDUE`, `DISPUTED`, `CANCELLED`, `REFUND_PENDING`, `REFUNDED`, `COMPLETED`, `FAILED`, `EXPIRED`.

**Transitions**
- Reader requests dates/duration → `REQUESTED`; system validates verified parties, city/locality, availability, duration and policy version.
- `REQUESTED → PAYMENT_PENDING`: server creates idempotent payment intent and inventory hold.
- `PAYMENT_PENDING → PAYMENT_CONFIRMED`: signed provider event/reconciliation confirms payment.
- `PAYMENT_PENDING → FAILED/EXPIRED`: definitive failure or hold expiry; release inventory and reconcile any late success.
- `PAYMENT_CONFIRMED → HANDOVER_SCHEDULED`: both parties select approved public venue/time.
- `HANDOVER_SCHEDULED → HANDOVER_PENDING`: handover window opens and one party starts authenticated QR/OTP protocol.
- `HANDOVER_PENDING → ACTIVE`: both distinct users confirm collection and initial condition; see SM-07.
- `ACTIVE → EXTENSION_REQUESTED → EXTENDED`: SM-09 approval/payment/conflict checks succeed.
- `ACTIVE/EXTENDED → RETURN_REQUESTED → RETURN_PENDING`: return initiated and return handover started.
- `ACTIVE/EXTENDED → OVERDUE`: due date plus configured grace policy passes without accepted return.
- `RETURN_PENDING → COMPLETED`: return accepted and financial obligations resolved; or `DISPUTED` if condition/non-return issue.
- Any pre-active state → `CANCELLED` under policy; refund state handled separately.
- `CANCELLED → REFUND_PENDING → REFUNDED` where money was collected.
- `ACTIVE/OVERDUE/RETURN_PENDING → DISPUTED`: valid claim opened.
- `DISPUTED → COMPLETED` after resolution and return closure.
- `DISPUTED → REFUND_PENDING` only where decision requires refund.
- Admin may mark `FAILED` only with evidence of irrecoverable creation/processing failure and compensation path.

**Invalid:** direct client state update; ACTIVE without two-party collection; COMPLETED without return/exception and ledger closure; booking payment status inferred from redirect; cancel an active rental as if no handover occurred.

**Payment consequence:** Booking transitions trigger commands to payment/deposit/payout aggregates; never directly mutate ledger balances.

**Notifications:** each material transition to relevant parties; reminder schedule configurable.

**Audit:** actor, previous/next state, reason, booking version, policy snapshot, dates, copy ID, provider refs.

**Retry/failure:** optimistic version check; idempotency key; outbox event; reconcile delayed provider events; manual Admin repair uses compensating event.

### SM-05 — Payment

**States:** `CREATED`, `INITIATED`, `PENDING`, `AUTHORIZED`, `CAPTURED`, `FAILED`, `CANCELLED`, `PARTIALLY_REFUNDED`, `REFUND_PENDING`, `REFUNDED`, `CHARGEBACK_OPEN`, `CHARGEBACK_WON`, `CHARGEBACK_LOST`, `RECONCILIATION_REQUIRED`.

**Transitions**
- Backend creates payment record/intent `CREATED → INITIATED`.
- Provider returns pending → `PENDING`.
- Authorisation event → `AUTHORIZED`; capture event/reconciliation → `CAPTURED`.
- Definitive failure → `FAILED`.
- Cancel before capture → `CANCELLED` or provider void.
- Refund request → `REFUND_PENDING`; successful provider refund → `REFUNDED` or `PARTIALLY_REFUNDED`.
- Chargeback notification → `CHARGEBACK_OPEN`; provider/bank decision → `CHARGEBACK_WON/LOST`.
- Inconsistent/missing webhook or ledger/provider mismatch → `RECONCILIATION_REQUIRED`; resolve only via provider query/settlement evidence.

**Invalid:** trusting browser success; treating an HTTP 200 create-intent response as payment; multiple captures for one obligation; refund greater than captured amount less prior refunds; duplicate webhook creates duplicate ledger entry.

**Payment consequences:** rent, deposit, extension, late fee and damage compensation must be distinct obligation types and ledger entries. Commission is 10% of rental fee only, based on booking snapshot. Provider fees and tax are separate entries.

**Notifications:** payment initiated, success/failure, refund requested/success/failure, chargeback opened/closed.

**Audit:** provider event ID, signature verification result, raw payload reference (secure), idempotency key, amount, currency, provider reference, ledger postings.

**Retry/failure:** retry provider status query, not capture blindly; exponential backoff; dead-letter queue; reconciliation job; manual review for unresolved mismatch.

### SM-06 — Deposit

**States:** `NOT_REQUIRED`, `REQUIRED_UNCONFIGURED`, `COLLECTION_PENDING`, `HELD_BY_PROVIDER`, `RELEASE_PENDING`, `PARTIALLY_APPLIED`, `CLAIM_HOLD_PENDING`, `CLAIM_HOLD`, `REFUND_PENDING`, `RELEASED`, `REFUNDED`, `FAILED`, `RECONCILIATION_REQUIRED`.

**Transitions**
- Booking config requires deposit but legal/provider approval absent → `REQUIRED_UNCONFIGURED`; booking cannot enter payment.
- Approved provider flow creates collection → `COLLECTION_PENDING`.
- Provider confirms funds held in approved arrangement → `HELD_BY_PROVIDER`.
- Rental closes without claim → `RELEASE_PENDING → REFUND_PENDING → RELEASED/REFUNDED` as provider semantics define.
- Valid claim → `CLAIM_HOLD_PENDING → CLAIM_HOLD` only if provider contract permits; undisputed amount handling requires policy/provider approval.
- Admin decision authorises proportional application → `PARTIALLY_APPLIED` or final applied amount; remaining eligible amount refunded.
- Failure/mismatch → `FAILED/RECONCILIATION_REQUIRED`.

**Invalid:** platform claims funds are escrowed without approved structure; owner withdraws deposit; deposit used to pay rent/commission without explicit policy and provider approval; automatic forfeiture; duplicate refund/application.

**Payment consequence:** Deposit is separate from rent, commission and owner payout. It is not platform revenue. A database status does not prove custody. Deposit feature is disabled until legal/provider release gate.

**Notifications:** deposit required and amount before checkout; collection confirmed; hold reason; release/refund status; claim and decision.

**Audit:** provider reference, legal structure version, amount, custody state, hold/release reason, claim decision, ledger event.

**Retry/failure:** query provider state; no speculative release; manual reconciliation queue.

### SM-07 — Physical collection

**States:** `NOT_SCHEDULED`, `SCHEDULED`, `TOKEN_ISSUED`, `OWNER_CONFIRMED`, `READER_CONFIRMED`, `CONDITION_ACKNOWLEDGED`, `COLLECTED`, `NO_SHOW_REVIEW`, `CANCELLED`, `EXPIRED`.

**Transitions**
- Confirmed booking → `SCHEDULED` at approved public point.
- Both parties have agreed time/place → one-time short-lived token `TOKEN_ISSUED`.
- Owner authenticated and confirms physical handover → `OWNER_CONFIRMED`.
- Reader authenticated and confirms receipt → `READER_CONFIRMED`.
- Both separately acknowledge initial condition evidence → `CONDITION_ACKNOWLEDGED`.
- Backend verifies all distinct actor/device/time/token constraints → `COLLECTED`; booking rental becomes ACTIVE.
- Window expires → `NO_SHOW_REVIEW`; apply no-show process, do not infer which party failed without evidence.
- Parties reschedule → return to `SCHEDULED` with old token revoked.
- Safety/location issue → `CANCELLED` or reschedule per policy.

**Invalid:** same account confirms both sides; expired/replayed token; token reused; owner confirmation alone activates rental; location not approved; residential address displayed.

**Payment consequence:** Owner settlement becomes eligible only after `COLLECTED`; provider settlement still subject to provider-approved timing and tax deductions.

**Notifications:** schedule confirmation, token issuance, reminders, both confirmation steps, expiry/no-show review.

**Audit:** token hash, issuance/expiry, venue ID, server timestamp, actor IDs, condition evidence hashes, device/risk metadata minimised.

**Retry/failure:** OTP fallback; issue new token after revoking old; venue closure path; support-assisted exception requires independent evidence and Admin audit.

### SM-08 — Active rental

**States:** `ACTIVE`, `DUE_SOON`, `OVERDUE`, `RETURN_INITIATED`, `DISPUTED`, `CLOSED`.

**Transitions**
- `COLLECTED → ACTIVE`.
- Scheduler `ACTIVE → DUE_SOON` at configured reminder threshold.
- Scheduler `ACTIVE/DUE_SOON → OVERDUE` after due timestamp plus configured grace period.
- Reader initiates return → `RETURN_INITIATED`.
- Valid extension → due date updated; state remains active or `DUE_SOON` recalculated.
- Claim/non-return issue → `DISPUTED`.
- Return closure and financial resolution → `CLOSED`.

**Invalid:** changing due date without extension state; owner unilaterally marks returned; client clock controls overdue; closing while unresolved dispute/return.

**Payment consequence:** late fee, if any, is calculated only under published configured policy; never silently debit a payment method. Damage/non-return compensation is separate.

**Notifications:** due-soon, due date, overdue, return instructions, dispute updates.

**Audit:** actual collected timestamp, due timestamp, grace-policy version, extensions, reminders, status.

**Retry/failure:** scheduler is idempotent; recompute on each run; timezone-safe server timestamps.

### SM-09 — Extension

**States:** `NOT_REQUESTED`, `REQUESTED`, `OWNER_APPROVED`, `OWNER_REJECTED`, `AVAILABILITY_CHECKED`, `PAYMENT_PENDING`, `APPROVED`, `EXPIRED`, `CANCELLED`.

**Transitions**
- Reader requests new due date while rental active → `REQUESTED`.
- Owner approves/rejects → `OWNER_APPROVED/OWNER_REJECTED`.
- On approval, server checks no overlapping reservation and buffer → `AVAILABILITY_CHECKED`.
- If extra charge required by pricing snapshot, create payment → `PAYMENT_PENDING`; successful confirmation → `APPROVED`.
- If no extra charge, approve after availability check.
- Only `APPROVED` changes due date and copy interval atomically.
- Request expires/cancelled before approval → terminal state.

**Invalid:** owner approval alone changes due date; extension overlaps another reservation; extension after return completed; payment pending treated as approved.

**Payment consequence:** incremental rental fee and 10% commission snapshot computed under approved pricing configuration; deposit delta only if approved provider/legal policy requires it.

**Notifications:** request, owner decision, payment due/success/failure, new due date.

**Audit:** old/new due date, approver, availability result, pricing and policy versions, payment reference.

**Retry/failure:** concurrent extension and booking conflicts resolved by transaction/constraint; failed payment leaves original due date unchanged.

### SM-10 — Return

**States:** `NOT_STARTED`, `REQUESTED`, `SCHEDULED`, `TOKEN_ISSUED`, `OWNER_CONFIRMED`, `READER_CONFIRMED`, `CONDITION_RECORDED`, `RETURNED`, `INSPECTION_PENDING`, `ACCEPTED`, `DISPUTED`, `CLOSED`.

**Transitions**
- Reader initiates return → `REQUESTED`.
- Both select approved venue/time → `SCHEDULED`.
- Backend issues one-time token → `TOKEN_ISSUED`.
- Owner and Reader independently confirm receipt/return → `OWNER_CONFIRMED`, `READER_CONFIRMED`.
- Both capture/acknowledge return condition → `CONDITION_RECORDED`.
- Backend verifies → `RETURNED`.
- Owner inspection → `INSPECTION_PENDING`; accepted → `ACCEPTED`; claim → `DISPUTED`.
- After financial/deposit resolution → `CLOSED`.

**Invalid:** return marked complete by one party only (unless documented Admin exception); condition evidence overwritten; owner delays inspection indefinitely to retain deposit; copy available before accepted return/inspection buffer.

**Payment consequence:** late-fee and deposit-release logic begins from verified return timestamp and claim status, subject to approved policy/provider arrangement.

**Notifications:** return request, schedule, QR, reminders, return confirmed, inspection result, claim.

**Audit:** return timestamp, venue, both actor confirmations, photos, condition acknowledgements, inspection and dispute record.

**Retry/failure:** OTP fallback; lost phone process; Admin exception with evidence and second-person review.

### SM-11 — Damage claim

**States:** `NONE`, `SUBMITTED`, `EVIDENCE_PENDING`, `UNDER_REVIEW`, `COUNTER_EVIDENCE_PENDING`, `ASSESSMENT_PENDING`, `DECIDED`, `APPEAL_OPEN`, `CLOSED`, `WITHDRAWN`.

**Transitions**
- Owner submits within policy claim window → `SUBMITTED`.
- System validates booking, return event and evidence → `EVIDENCE_PENDING` if incomplete, otherwise `UNDER_REVIEW`.
- Reader submits response/counter-evidence → `COUNTER_EVIDENCE_PENDING`.
- Admin assesses normal wear, pre-existing damage, age, edition, repairability, replacement availability and evidence → `ASSESSMENT_PENDING`.
- Admin issues reasoned decision → `DECIDED`.
- Either party appeals within configured period → `APPEAL_OPEN`; independent Admin/reviewer decides.
- Decision final and compensation/refund processed → `CLOSED`.
- Claim withdrawn → `WITHDRAWN`.

**Invalid:** automatic deduction; claim without rental evidence; charging original cover price automatically; claim on pre-existing damage; reviewer with conflict of interest.

**Payment consequence:** approved amount may be applied only through provider-approved deposit/compensation flow and explicit terms; otherwise use separate on-platform payment request if legally/provider approved. Never debit without authorisation.

**Notifications:** claim submitted, response deadline, evidence request, decision, appeal, financial result.

**Audit:** before/after evidence, file hashes, submissions, reviewer, valuation factors, calculation, decision reasons, appeal.

**Retry/failure:** upload retries; deadline reminders; escalation for reviewer backlog; no claim auto-wins due to technical upload failure.

### SM-12 — Non-return

**States:** `NOT_APPLICABLE`, `DUE`, `GRACE_PERIOD`, `OVERDUE_NOTICE`, `OWNER_REPORTED`, `READER_RESPONSE_PENDING`, `UNDER_REVIEW`, `RETURN_CONFIRMED`, `COMPENSATION_DECIDED`, `DISPUTED`, `CLOSED`.

**Transitions**
- Due timestamp passes → `DUE`; after configured grace → `GRACE_PERIOD` then `OVERDUE_NOTICE`.
- Owner reports non-return with evidence → `OWNER_REPORTED`.
- Reader may respond with location/status/evidence → `READER_RESPONSE_PENDING`.
- Admin reviews reminders, communications, return evidence and safety concerns → `UNDER_REVIEW`.
- Verified return → `RETURN_CONFIRMED`.
- If unresolved, reasoned compensation decision → `COMPENSATION_DECIDED`; appeal/dispute path remains available.
- Resolution → `CLOSED`.

**Invalid:** system automatically labels criminal conduct; deposit automatically confiscated; owner independently charges replacement value; account permanently banned without review.

**Payment consequence:** late fees only if configured, disclosed and lawful; compensation only after evidence and decision. Deposit application subject to approved custody model.

**Notifications:** due reminders, overdue, owner report, response request, review decision, resolution.

**Audit:** due/grace configuration, contacts, evidence, attempts to arrange return, decision and payment entries.

**Retry/failure:** retry notifications through alternate channel where consented; Admin safety escalation; keep account restriction separate from rental obligations.

### SM-13 — Dispute

**States:** `OPEN`, `EVIDENCE_COLLECTION`, `RESPONSE_PENDING`, `UNDER_REVIEW`, `DECISION_PENDING`, `DECIDED`, `APPEAL_OPEN`, `RESOLVED`, `CLOSED`.

**Transitions**
- Eligible party opens dispute with reason and booking link → `OPEN`.
- System freezes only actions that must be frozen under policy/provider arrangement; gathers evidence → `EVIDENCE_COLLECTION`.
- Other party invited to respond → `RESPONSE_PENDING`.
- Both submissions/timeout → `UNDER_REVIEW`.
- Reviewer drafts outcome → `DECISION_PENDING`.
- Admin issues reasoned decision → `DECIDED`.
- Appeal within configured window → `APPEAL_OPEN`.
- Appeal decision or no appeal after window → `RESOLVED`.
- Required refund/compensation/return/payout actions complete → `CLOSED`.

**Invalid:** one party sees private identity documents; party edits submitted evidence; dispute status itself moves funds; conflicted reviewer decides without recusal.

**Payment consequence:** payment/deposit hold only where provider contract and legal model permit. Disputed amount and undisputed amount should be separately tracked.

**Notifications:** dispute opened, response requested, evidence deadline, decision, appeal, closure.

**Audit:** case history, evidence hashes, reviewer assignments, conflicts, decision and linked ledger transactions.

**Retry/failure:** escalation to second reviewer; preserve case if notification fails; do not auto-decide solely because one party misses a message.

### SM-14 — Refund

**States:** `NOT_REQUIRED`, `ELIGIBLE`, `REQUESTED`, `SUBMITTED_TO_PROVIDER`, `PENDING`, `SUCCEEDED`, `FAILED`, `PARTIALLY_SUCCEEDED`, `RECONCILIATION_REQUIRED`, `CLOSED`.

**Transitions**
- Policy/cancellation/decision determines refundable amount → `ELIGIBLE`.
- Backend creates idempotent refund request → `REQUESTED`.
- Provider accepts → `SUBMITTED_TO_PROVIDER/PENDING`.
- Provider confirms → `SUCCEEDED` or `PARTIALLY_SUCCEEDED`.
- Definitive failure → `FAILED`; retry only after provider status query and failure classification.
- Provider/ledger mismatch → `RECONCILIATION_REQUIRED`.
- All amounts reconciled → `CLOSED`.

**Invalid:** refund > captured amount minus prior successful refunds; duplicate refund; refund to unrelated destination absent provider/legal process; marking success on request acceptance alone.

**Payment consequence:** refund amount, fee retention and deposit refund are separate components. Policy determines treatment; provider confirms settlement.

**Notifications:** refund eligibility, initiation, pending, success/failure and expected next step.

**Audit:** reason, policy version, original payment, amount, provider refund ID, attempts, result and reconciliation.

**Retry/failure:** idempotency key per refund instruction; query before retry; dead-letter and Admin reconciliation.

### SM-15 — Owner payout

**States:** `NOT_ELIGIBLE`, `ELIGIBLE_AFTER_COLLECTION`, `PAYOUT_PENDING`, `SUBMITTED`, `PROCESSING`, `PAID`, `FAILED`, `ON_HOLD`, `REVERSED`, `RECONCILIATION_REQUIRED`.

**Transitions**
- Verified collection → `ELIGIBLE_AFTER_COLLECTION`.
- Tax/KYC/provider eligibility and dispute checks pass → `PAYOUT_PENDING`.
- Provider payout instruction → `SUBMITTED/PROCESSING`.
- Provider confirms credit → `PAID`.
- Failure → `FAILED`; retry only after provider query.
- Risk/legal/dispute/provider hold → `ON_HOLD`.
- Provider reversal → `REVERSED`.
- Ledger mismatch → `RECONCILIATION_REQUIRED`.

**Invalid:** payout before verified handover; payout to unverified bank account; commission computed on deposit; frontend-triggered payout; duplicate payout.

**Payment consequence:** gross rent, 10% commission, taxes/TDS, provider fees and owner net payable are separately recorded. Actual net formula must be CA/provider approved; do not assume which party bears gateway fee.

**Notifications:** eligible, pending, paid, failed, on hold, reversed.

**Audit:** rental event, payout instruction, beneficiary token, gross/commission/tax/fee/net breakdown, provider references.

**Retry/failure:** idempotent payout ID; provider status query; no duplicate transfer; manual finance review.

### SM-16 — Book exchange

**States:** `DRAFT`, `PUBLISHED`, `REQUESTED`, `COUNTERPROPOSED`, `MUTUALLY_ACCEPTED`, `HANDOVER_SCHEDULED`, `HANDOVER_PENDING`, `EXCHANGED`, `CANCELLED`, `DISPUTED`, `CLOSED`.

**Transitions**
- User creates exchange offer with copy IDs and terms → `DRAFT → PUBLISHED`.
- Another verified user requests → `REQUESTED`.
- Offer owner accepts/counterproposes → `MUTUALLY_ACCEPTED` only after both explicitly accept exact copy/terms.
- Schedule approved public venue → `HANDOVER_SCHEDULED`.
- Both parties independently confirm QR handover and condition → `EXCHANGED`.
- Return/reciprocal obligations if any are represented explicitly in offer; otherwise exchange is not complete until both transfers recorded.
- Cancel before handover → `CANCELLED`.
- Condition/ownership issue → `DISPUTED`.
- Resolution → `CLOSED`.

**Invalid:** unilateral exchange; same user confirms both sides; hidden cash/rent outside exchange terms; exchange of unapproved/pirated copies.

**Payment consequence:** no rental commission unless a separately defined paid rental is created. Any deposit/fee for exchange is TBD and disabled absent approved design.

**Notifications:** request, counterproposal, acceptance, schedule, handover and dispute.

**Audit:** offer versions, copy IDs, exact accepted terms, handover evidence and dispute.

**Retry/failure:** token expiry and reschedule; revoke stale tokens; preserve accepted offer version.

### SM-17 — Referral reward

**States:** `NOT_ELIGIBLE`, `INVITED`, `SIGNUP_ATTRIBUTED`, `QUALIFICATION_PENDING`, `QUALIFIED`, `REWARD_PENDING`, `REWARDED`, `REJECTED`, `REVERSED`, `EXPIRED`.

**Transitions**
- Referrer generates unique code/link → `INVITED`.
- New user signs up and attribution validated → `SIGNUP_ATTRIBUTED`.
- Anti-fraud and qualifying action criteria (TBD) checked → `QUALIFICATION_PENDING`.
- Admin/system validates eligibility → `QUALIFIED`.
- Reward ledger instruction → `REWARD_PENDING → REWARDED`.
- Fraud/chargeback/cancellation within policy → `REJECTED/REVERSED`.
- Time window expires → `EXPIRED`.

**Invalid:** self-referral, duplicate identity/device/payment instrument abuse where prohibited by approved policy, reward on signup alone unless policy says so, duplicate reward.

**Payment consequence:** reward type/value/cap and accounting/tax treatment are TBD; no reward liability is created until campaign configuration is published and qualification is met.

**Notifications:** invite, attribution, qualification, reward, rejection/reversal.

**Audit:** referrer, invitee, attribution, campaign version, fraud reason, reward ledger entry.

**Retry/failure:** idempotent reward grant; reconciliation for provider failure; manual review for false positives.

### SM-18 — Community moderation

**States:** `DRAFT`, `PUBLISHED`, `REPORTED`, `UNDER_REVIEW`, `HIDDEN_PENDING_REVIEW`, `REMOVED`, `RESTORED`, `USER_RESTRICTED`, `CLOSED`.

**Transitions**
- Author publishes → `PUBLISHED` after content validation.
- User reports/block/mute → report creates case; content `REPORTED`.
- Moderator claims → `UNDER_REVIEW`.
- Urgent safety risk → `HIDDEN_PENDING_REVIEW` under defined criteria.
- Moderator decides → `REMOVED` or `RESTORED`.
- Repeat/severe violation → `USER_RESTRICTED` or account suspension workflow.
- Appeal → separate review and `RESTORED`/`REMOVED`.
- Close with reasons.

**Invalid:** report automatically proves violation; moderator exposes reporter identity; moderation silently deletes evidence; automated system imposes unreviewable permanent ban.

**Payment consequence:** none directly; restriction may block future transactions while active rental obligations remain handled separately.

**Notifications:** report receipt, action notice to affected author as appropriate, appeal result.

**Audit:** content version/hash, report category, moderator, decision, reason, appeal and action timestamp.

**Retry/failure:** moderation queue SLA configurable; urgent queue fallback; preserve evidence privately.

### SM-19 — Customer support / grievance

**States:** `OPEN`, `ACKNOWLEDGED`, `ASSIGNED`, `WAITING_FOR_USER`, `WAITING_FOR_PROVIDER`, `ESCALATED`, `RESOLVED`, `REOPENED`, `CLOSED`.

**Transitions**
- User creates ticket → `OPEN`, issue category and transaction reference validated.
- System issues ticket/copy → `ACKNOWLEDGED`.
- Assign agent → `ASSIGNED`.
- Request details/provider update → waiting states.
- SLA/risk threshold or unresolved complaint → `ESCALATED`.
- Agent resolves with reason and action → `RESOLVED`.
- User replies within configured reopen period → `REOPENED`.
- Closure after confirmation or policy timer → `CLOSED`.

**Invalid:** deleting complaint; closing without response; support agent changes ledger directly; consumer grievance SLA conflated with IT Rules grievance SLA.

**Payment consequence:** support ticket does not itself refund/charge/payout; it creates approved commands to relevant aggregates.

**Notifications:** ticket receipt, copy, assignment, requested info, escalation, resolution and closure.

**Audit:** complaint copy, category, SLA clock, owner, communications, decisions and linked state changes.

**Retry/failure:** outbound channel retries; retain in-app ticket; escalate if statutory timer approaches; preserve separate legal timers.

### SM-20 — Account suspension

**States:** `ACTIVE`, `RESTRICTED`, `SUSPENDED`, `UNDER_APPEAL`, `REINSTATEMENT_PENDING`, `REINSTATED`, `CLOSED`.

**Transitions**
- Risk/admin action → `RESTRICTED` (limited actions) or `SUSPENDED` (blocked actions) with reason/scope.
- User appeals → `UNDER_APPEAL`.
- Admin reviews → `REINSTATEMENT_PENDING` or remain suspended/closed.
- Approved → `REINSTATED`.
- User requests closure → `CLOSED` only after legally required records and active rentals/financial obligations are handled.
- Emergency temporary suspension may occur under approved safety policy; prompt human review follows.

**Invalid:** suspension erases active rentals, deposits, payout liabilities, complaints or evidence; suspension automatically forfeits deposit; permanent suspension without reason/appeal route except legally compelled restriction.

**Payment consequence:** block new transactions and listings; do not automatically stop lawful refund/return/payout obligations. Existing active rental obligations must be managed safely; provider funds held only under approved terms.

**Notifications:** restriction/suspension, reason to extent safe/legal, appeal route, review decision, reinstatement.

**Audit:** trigger, actor, scope, evidence, duration/review date, appeal and decision.

**Retry/failure:** idempotent restriction; Admin emergency access; scheduled review of temporary holds; separate access control from financial ledger.

## 4. Database-level booking safety

### 4.1 Recommended PostgreSQL model

Use one row per physical copy reservation interval, not a frontend-only calendar. Store interval as a half-open range `[start_at, end_at)` in UTC (`timestamptz`), with local display in Asia/Kolkata. Buffer time is incorporated into the reserved interval according to a versioned policy.

Example PostgreSQL migration (adapt names/types to project schema):

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE copy_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  copy_id uuid NOT NULL REFERENCES physical_book_copies(id),
  booking_id uuid NOT NULL UNIQUE REFERENCES bookings(id),
  reserved_period tstzrange NOT NULL,
  reservation_status text NOT NULL CHECK (
    reservation_status IN ('HELD', 'CONFIRMED', 'ACTIVE', 'RETURN_PENDING', 'RELEASED')
  ),
  hold_expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (NOT isempty(reserved_period)),
  CHECK (lower_inc(reserved_period) AND NOT upper_inc(reserved_period))
);

ALTER TABLE copy_reservations
ADD CONSTRAINT no_overlapping_live_copy_reservations
EXCLUDE USING gist (
  copy_id WITH =,
  reserved_period WITH &&
)
WHERE (reservation_status IN ('HELD','CONFIRMED','ACTIVE','RETURN_PENDING'));
```

The exclusion constraint is the final concurrency guard. It rejects overlapping intervals even if two API requests race. A `HELD` row must be changed to `RELEASED` in a transaction after hold expiry; do not delete it because audit history matters.

### 4.2 Atomic booking transaction

In one database transaction:
1. Authenticate Reader and verify approved identity/18+.
2. Lock/check physical copy and listing state (`SELECT ... FOR UPDATE`).
3. Validate city/locality and same-city constraint.
4. Validate requested duration, pricing policy and buffer.
5. Insert booking in `PAYMENT_PENDING` and a `HELD` reservation with short `hold_expires_at`.
6. Create internal payment instruction/outbox event with unique idempotency key.
7. Commit.
8. Call provider asynchronously; do not hold a DB transaction open during network call.
9. On verified payment success, atomically change reservation `HELD → CONFIRMED`, booking `PAYMENT_CONFIRMED`; if hold already expired or conflict exists, route to reconciliation/refund and never force-overlap.
10. On definitive failure/expiry, mark reservation `RELEASED` and booking `FAILED/EXPIRED`.

If the provider succeeds after reservation expiry, the system must not silently allocate a now-conflicted copy. Attempt an atomic reacquisition; if unavailable, initiate a full/appropriate refund and alert support.

### 4.3 Concurrency and idempotency
- Use provider idempotency keys for payment/refund/payout commands.
- Use unique constraints on provider event IDs and merchant reference IDs.
- Process webhooks through inbox table; persist raw event reference, verify signature, then transactionally update aggregate and ledger.
- Use transactional outbox for notifications/provider commands.
- Use optimistic version column for booking aggregate (`UPDATE ... WHERE id=? AND version=?`).
- Exclusion constraint is mandatory; advisory locks may improve UX but are not a replacement.
- Reservation expiry job must be idempotent and lock row before release.
- Extension must update reservation interval in same transaction as extension approval and due date update; exclusion constraint rejects conflicts.
- Return/inspection buffer is also represented in reservation interval until copy is available again.

### 4.4 Critical invariant tests
- Two simultaneous requests for same copy/overlapping intervals: exactly one succeeds.
- Non-overlapping requests: both succeed.
- Adjacent half-open intervals: `[10:00, 12:00)` and `[12:00, 14:00)` do not overlap unless buffer added.
- Extension concurrent with next booking: exactly one interval update wins; no overlap.
- Expired hold + delayed successful payment: no double booking; refund/reacquisition path.
- Duplicate webhook: one ledger posting and one transition.
- App/browser closed after payment: webhook/reconciliation still updates booking.
- Admin pause cannot create availability while active reservation exists.

## 5. Event and audit model

Every transition should emit a domain event with:
`event_id`, `aggregate_type`, `aggregate_id`, `aggregate_version`, `event_type`, `actor_type`, `actor_id`, `occurred_at`, `recorded_at`, `correlation_id`, `causation_id`, `idempotency_key`, `reason_code`, `policy_version`, `metadata_reference`.

Keep sensitive identity data and private documents out of general audit payloads; store secure references and access logs.

## 6. Configurations that remain unresolved

Do not ship invented values for:
- payment hold duration;
- owner response window (if booking approval is introduced);
- handover appointment window and no-show grace;
- reschedule cutoff and count;
- cancellation refund tiers;
- grace period for late return;
- late fee formula/cap;
- claim filing and response windows;
- damage valuation weights/cap;
- non-return escalation timeline;
- referral qualifying event/reward/cap;
- community moderation SLAs;
- suspension review period;
- payout schedule and gateway fee allocation;
- deposit amount formula, custody, hold/release and dispute mechanism;
- inspection buffer;
- custom rental duration bounds.

These must be approved in versioned Admin configuration after legal, CA and payment-provider review.

# Feature Catalog
## Peer-to-Peer Physical Book Rental Marketplace

**Priority definitions**
- **P0:** Required for a safe, viable initial marketplace launch.
- **P1:** Important marketplace capability; may follow the first controlled launch.
- **P2:** Enhancement or growth feature; defer unless explicitly promoted.

Priorities are product recommendations inferred from the source requirements, not previously approved commitments. OPEN DECISION items remain unapproved regardless of priority.

## Common acceptance conventions
- All money values are represented in INR and calculated server-side.
- All sensitive actions are authorised server-side.
- All state changes are validated against an explicit state machine.
- All critical operations are auditable.
- User-visible status must derive from trusted backend/provider state.
- Error messages must not expose private data or internal risk signals.

---

## F-001 — Mobile number registration and OTP authentication
**Priority:** P0  
**Roles:** Guest, registered user  
**Description:** Register and authenticate using Indian mobile number OTP. Email OTP is not used for login or registration.  
**Preconditions:** User can provide a supported mobile number; SMS provider is configured.  
**Main workflow:** Enter number → request OTP → validate OTP → establish secure session → continue first-registration steps.  
**Alternatives:** Resend after cooldown; recover access using approved account recovery flow; change number with re-verification.  
**Failures:** Invalid/expired OTP, rate limit, SMS provider failure, excessive attempts, duplicate/account conflict, session failure.  
**Acceptance criteria:**
- OTP has configurable expiry, resend cooldown and attempt limits.
- Server validates OTP; client cannot mark a number verified.
- Rate limiting and abuse controls apply by relevant identifiers.
- Sessions are securely issued, renewed and revoked.
- Email OTP is not offered as authentication.
- Mobile-number changes require re-verification and audit.
**Dependencies:** SMS/DLT provider, authentication design, privacy/legal notices.

## F-002 — Mandatory first-registration live profile photograph
**Priority:** P0  
**Roles:** New user  
**Description:** Require a camera-captured live profile photograph on first registration; no gallery-upload substitute for this mandatory capture.  
**Preconditions:** OTP-verified account; camera-capable device or accessible fallback route.  
**Main workflow:** Explain purpose → request camera permission → capture image live → preview/retake → submit → store with access controls.  
**Alternatives:** Accessible support process when camera is unavailable or inaccessible. Exact fallback is OPEN DECISION.  
**Failures:** Permission denied, camera unavailable, upload interrupted, invalid file, poor capture, user abandons.  
**Acceptance criteria:**
- First-time registration cannot complete without an accepted capture or approved fallback.
- Gallery picker is not presented as an equivalent route.
- Image is stored securely and public avatar is separate from private identity evidence.
- Purpose, access and retention are disclosed.
- Capture failure does not trap users; support route is available.
**Dependencies:** Device camera APIs, secure storage, accessibility review, privacy policy.

## F-003 — Identity verification submission and manual review
**Priority:** P0  
**Roles:** User, authorised verification Admin  
**Description:** Collect identity evidence and require manual administrator review. Document preference: Passport; PAN if no passport; Driving Licence if neither passport nor PAN is available.  
**Preconditions:** Authenticated user; notice and consent workflow available.  
**Main workflow:** Select document → submit evidence → status SUBMITTED/UNDER_REVIEW → authorised reviewer examines → approve/reject/request information → notify user.  
**Alternatives:** Additional information, resubmission, suspension, reverification.  
**Failures:** Unreadable/unsupported evidence, storage failure, unauthorised access, duplicate identity alert, reviewer conflict.  
**Acceptance criteria:**
- All listed statuses are supported: NOT_STARTED, DRAFT, SUBMITTED, UNDER_REVIEW, ADDITIONAL_INFORMATION_REQUIRED, APPROVED, REJECTED, SUSPENDED, REVERIFICATION_REQUIRED.
- Only authorised reviewers can access evidence and decide.
- Every decision includes actor, timestamp and reason.
- Unverified users can browse but cannot list, book or perform financial transactions.
- PAN is not treated as address proof.
- Retention and deletion controls follow approved policy.
**Dependencies:** Identity provider/manual operations, secure private storage, legal review, address-proof decision.

## F-004 — Registration agreements and versioned consent
**Priority:** P0  
**Roles:** User, Admin  
**Description:** Separate, unchecked acceptance controls for Terms and Conditions, Privacy Policy, User and Marketplace Rules, Identity Verification Consent, and required notifications/relevant communication consents.  
**Preconditions:** Current document versions published.  
**Main workflow:** Present documents → user opens/reviews → separately accepts required items → store version, hash, timestamp and user ID.  
**Alternatives:** Decline/exit; later reaccept materially changed terms.  
**Failures:** Missing acceptance, version changes during submission, unavailable document, hash mismatch.  
**Acceptance criteria:**
- Required controls are separate and unchecked by default.
- Consent record stores document version, hash, timestamp and user ID.
- Materially changed terms trigger renewed acceptance as legally approved.
- Downloadable copies are available.
- Draft legal content is labelled as pending lawyer review.
**Dependencies:** Legal documents, consent taxonomy, document versioning.

## F-005 — Per-rental agreement acceptance
**Priority:** P0  
**Roles:** Reader, Owner  
**Description:** Require acceptance of relevant rental agreement before each rental.  
**Preconditions:** Verified user, eligible copy and current agreement version.  
**Main workflow:** Checkout displays agreement → user accepts → acceptance is linked to booking and version.  
**Alternatives:** User declines and booking does not proceed; agreement update triggers new acceptance where required.  
**Failures:** Agreement unavailable, version race, acceptance not persisted.  
**Acceptance criteria:** Agreement acceptance is explicit, versioned, timestamped and associated with the rental; downloadable copy is available.  
**Dependencies:** F-004, booking flow, legal review.

## F-006 — Book metadata catalogue
**Priority:** P0  
**Roles:** Owner, Admin  
**Description:** Maintain metadata separately from physical copies: title, author, ISBN, publisher, edition, publication year, language, genre and description.  
**Preconditions:** Verified Owner for owner-created records; admin catalogue controls.  
**Main workflow:** Search/create metadata → validate fields → save metadata → associate one or more physical copies.  
**Alternatives:** ISBN lookup/autofill; manual entry where ISBN is absent.  
**Failures:** Duplicate metadata, lookup provider failure, invalid ISBN, incomplete required fields.  
**Acceptance criteria:** Metadata and physical-copy records are distinct; metadata does not prove ownership; duplicate detection and field validation exist.  
**Dependencies:** Database model, ISBN metadata provider, category taxonomy.

## F-007 — Physical copy listing and ownership declaration
**Priority:** P0  
**Roles:** Verified Owner, Admin  
**Description:** Create a unique rentable physical-copy record with owner, condition, actual photographs, rental price, deposit requirement, availability and rental history.  
**Preconditions:** Owner identity approved; book metadata exists.  
**Main workflow:** Add copy → capture details/photos → declare lawful ownership/authority → set price/deposit → validate → publish or moderation queue.  
**Alternatives:** Save draft; submit additional evidence; edit/relist.  
**Failures:** Prohibited copy, missing evidence, pricing over ceiling, invalid photo, moderation rejection.  
**Acceptance criteria:**
- Each physical copy has unique ID and owner association.
- Owner declaration is recorded.
- Pirated photocopies, counterfeit books and unauthorised reproductions are prohibited.
- ISBN/cover image is never treated as ownership proof.
- Listing state and moderation history are auditable.
**Dependencies:** F-003, F-006, storage, pricing configuration, moderation policy.

## F-008 — Book condition evidence
**Priority:** P0  
**Roles:** Owner, Reader, Admin  
**Description:** Capture condition before and after each rental, including front cover, back cover, spine, pages, existing damage and additional damage.  
**Preconditions:** Copy exists; rental reaches relevant handover/return stage.  
**Main workflow:** Capture photos and descriptions → timestamp and associate with rental → both parties review/acknowledge applicable evidence.  
**Alternatives:** OTP-assisted confirmation; additional evidence during dispute.  
**Failures:** Missing image, upload failure, party disagreement, evidence tampering concern.  
**Acceptance criteria:** Evidence is timestamped, rental-linked, access-controlled and preserved for dispute review; normal wear and tear is distinguishable from reported damage.  
**Dependencies:** Storage, F-015 handover, F-019 return/dispute, retention policy.

## F-009 — Pricing and deposit configuration
**Priority:** P0  
**Roles:** Admin, Owner, Reader  
**Description:** Admin-configurable maximum rental pricing based on book value, category, condition and duration; owner chooses price up to maximum. Deposit is separate.  
**Preconditions:** Approved pricing policy and valuation inputs.  
**Main workflow:** Admin configures rules → system computes maximum → owner sets allowed price/deposit → reader sees itemised checkout.  
**Alternatives:** Admin revises rules; listing requires updated price.  
**Failures:** Missing valuation inputs, rule conflict, stale configuration, price outside allowed range.  
**Acceptance criteria:** No business rate is hardcoded; server validates price; commission is 10% of rental fee; deposit is not included in the commission base unless policy is explicitly changed and approved.  
**Dependencies:** Valuation policy, payment provider, tax/accounting review. Exact formulas and deposit bands are OPEN DECISION.

## F-010 — Locality-based discovery, search and map
**Priority:** P0  
**Roles:** Guest, verified user  
**Description:** Discover books by locality, map, title, author, category, language, condition, availability and duration.  
**Preconditions:** Published listing; configured locality and location data.  
**Main workflow:** Enter search/location/dates → view matching copies → inspect details and handover options.  
**Alternatives:** No results, broaden locality/date, map/list toggle.  
**Failures:** Location permission denied, map provider unavailable, stale availability, invalid locality.  
**Acceptance criteria:** Results respect same-city rule, locality availability and publication status; residential addresses are never exposed; map/list results are consistent.  
**Dependencies:** F-006/F-007, maps/data provider, locality configuration.

## F-011 — Wishlist and waitlist
**Priority:** P1  
**Roles:** Registered Reader  
**Description:** Save desired books and optionally join a waitlist for unavailable copies/titles.  
**Preconditions:** Account exists; feature eligibility approved.  
**Main workflow:** Save title/copy → manage wishlist → join waitlist → notify when eligible availability appears.  
**Alternatives:** Remove item, leave waitlist, notification preference changes.  
**Failures:** Duplicate entry, listing removed, no eligible local copy.  
**Acceptance criteria:** Private by default; waitlist notification does not reserve a copy; availability is rechecked before booking.  
**Dependencies:** F-010, notification service, privacy controls. Wishlist access for unverified users is OPEN DECISION.

## F-012 — Rule-based recommendations
**Priority:** P2  
**Roles:** Registered user  
**Description:** Recommend books using approved, explainable rules such as declared interests, category and local availability.  
**Preconditions:** Recommendation inputs and privacy policy approved.  
**Main workflow:** Apply rules → rank eligible local copies → display reason/filters.  
**Alternatives:** No recommendations; user adjusts interests.  
**Failures:** Sparse data, stale inventory, inappropriate recommendation.  
**Acceptance criteria:** Recommendations never bypass availability, location or eligibility rules; avoid sensitive inference; user controls and explanation are documented.  
**Dependencies:** F-010, catalogue, privacy review.

## F-013 — Availability calendar and conflict-free booking
**Priority:** P0  
**Roles:** Reader, Owner, backend  
**Description:** Manage copy availability, duration options (3, 7, 15, 30 days and configurable custom durations), buffers and atomic booking confirmation.  
**Preconditions:** Verified Reader; eligible listed copy; configured pricing and duration rules.  
**Main workflow:** Select dates/duration → server checks calendar, buffer and conflicts → reserve/confirm through approved booking state machine.  
**Alternatives:** Choose another date/copy; waitlist.  
**Failures:** Concurrent request, stale calendar, owner blocks dates, payment delay, reservation timeout.  
**Acceptance criteria:** Concurrent tests prove no double-booking; server is authoritative; buffer and duration rules are configurable; cross-city booking is rejected.  
**Dependencies:** F-009, F-010, payment state machine, database transaction/locking strategy.

## F-014 — Booking lifecycle, extension and early return
**Priority:** P0  
**Roles:** Reader, Owner, backend  
**Description:** Implement booking state machine and lifecycle events, extension requests, early return, overdue reminders and grace period.  
**Preconditions:** Booking exists in valid state.  
**Main workflow:** State transition is requested → backend validates actor, current state, payment and availability → event is recorded → parties notified.  
**Alternatives:** Extension denied; early return; overdue; dispute; cancellation/refund.  
**Failures:** Invalid transition, duplicate request, payment failure, conflict, stale webhook.  
**Acceptance criteria:** Listed primary and additional states are supported; all transitions are authorised and auditable; extension changes due date only after owner approval, availability check and payment confirmation.  
**Dependencies:** F-013, F-016, F-017, notification service. Owner acceptance semantics and transition table are OPEN DECISION.

## F-015 — Public handover scheduling and QR/OTP confirmation
**Priority:** P0  
**Roles:** Reader, Owner, Admin  
**Description:** Schedule collection/return only at approved public handover points. Two parties independently authenticate and confirm.  
**Preconditions:** Payment confirmed; approved handover point available; booking eligible.  
**Main workflow:** Schedule → generate unique short-lived QR → Owner authenticates/confirms → Reader authenticates/confirms → both acknowledge condition evidence → backend verifies sequence → ACTIVE.  
**Alternatives:** OTP fallback; reschedule; location closure; safety cancellation.  
**Failures:** Expired/replayed QR, one party absent, duplicate scan, invalid location, user attempts both confirmations.  
**Acceptance criteria:** One-time anti-replay tokens; OTP fallback; one user cannot confirm both sides; residential addresses and isolated locations are prohibited; ACTIVE only after complete backend-verified sequence.  
**Dependencies:** F-008, F-013/F-014, identity/authentication, location admin controls.

## F-016 — Marketplace payments, commission and owner settlement
**Priority:** P0  
**Roles:** Reader, Owner, Finance Admin, backend  
**Description:** Collect rental fee online, calculate 10% platform commission, and settle owner only after verified handover under provider rules.  
**Preconditions:** Eligible marketplace provider selected and vendor onboarding/configuration completed.  
**Main workflow:** Create payment intent/order → provider checkout → signed webhook verification → ledger entry → verified handover → settlement eligibility → provider settlement → reconciliation.  
**Alternatives:** Retry, delayed webhook, refund, payout failure, chargeback.  
**Failures:** Duplicate/delayed webhook, browser closed, signature invalid, provider outage, booking creation failure, payout rejected.  
**Acceptance criteria:** Frontend never sets payment success; signed webhooks and idempotency are enforced; transaction ledger and reconciliation exist; commission base is rental fee only; provider supports marketplace settlements and required flows.  
**Dependencies:** Provider selection/legal approval, F-013, F-015, finance ledger, tax review.

## F-017 — Security deposit lifecycle
**Priority:** P0  
**Roles:** Reader, Owner, Finance Admin, backend  
**Description:** Handle deposit separately from rental fee and commission according to a legally and provider-approved arrangement.  
**Preconditions:** Provider explicitly supports approved deposit mechanism; policy and legal review complete.  
**Main workflow:** Show deposit terms → obtain required authorisation/collection → track provider-backed status → resolve return/dispute → release/refund/adjust only under approved decision and provider process.  
**Alternatives:** Deposit withdrawal conflict, failed release, dispute hold where legally/provider-supported.  
**Failures:** Provider does not support model, release fails, chargeback, unsupported hold/custody, inconsistent ledger.  
**Acceptance criteria:** No fake wallet or informal escrow; no automatic confiscation; deposit remains distinct from rental fee and commission; every movement is provider-backed and auditable.  
**Dependencies:** Provider/legal decision, damage and cancellation policy, F-016, F-019. Entire custody/release model is OPEN DECISION.

## F-018 — Cancellation, no-show and rescheduling
**Priority:** P0  
**Roles:** Reader, Owner, Admin  
**Description:** Apply separate outcomes for reader/owner cancellation, no-show, mutual rescheduling, location closure, safety cancellation and payment failure.  
**Preconditions:** Booking in a cancellable/reschedulable state.  
**Main workflow:** Initiate event → collect reason/evidence → apply approved policy → update booking/payment/deposit/fees → notify parties.  
**Alternatives:** Mutual reschedule; admin intervention; safety escalation.  
**Failures:** Duplicate cancellation, policy version mismatch, refund failure, disputed no-show evidence.  
**Acceptance criteria:** Each event has defined status, rental refund, deposit outcome, fee, compensation, account consequence and notification; no arbitrary amounts are invented.  
**Dependencies:** Cancellation policy approval, F-016/F-017, notification service.

## F-019 — Return, damage, non-return and dispute resolution
**Priority:** P0  
**Roles:** Reader, Owner, Trust & Safety Admin  
**Description:** Complete return with condition evidence; handle damage/non-return through evidence-based investigation and appeal.  
**Preconditions:** Active/overdue rental; approved return point and process.  
**Main workflow:** Schedule return → two-party authenticated confirmation → capture return condition → compare with initial condition → complete or open dispute → collect evidence/counter-evidence → admin decision → appeal path.  
**Alternatives:** Reader disputes claim; owner submits additional evidence; non-return enters overdue/grace workflow.  
**Failures:** No-show, lost book, incomplete evidence, disagreement, evidence upload failure, unresolved case.  
**Acceptance criteria:** Before/after evidence linked to rental; normal wear distinguished; no automatic deposit confiscation; compensation is proportional and documented; original purchase price is not automatically charged; non-return is not automatically labelled criminal.  
**Dependencies:** F-008, F-014/F-015, F-017, approved damage/non-return policy.

## F-020 — Private chat, reports and blocking
**Priority:** P1  
**Roles:** Registered users, Moderation Admin  
**Description:** Provide private owner-reader chat and user/listing reporting, blocking and muting.  
**Preconditions:** Account and interaction eligibility; chat policy approved.  
**Main workflow:** Open permitted conversation → exchange messages → report/block/mute as needed → moderator reviews reports.  
**Alternatives:** Conversation unavailable due to block/suspension; safety escalation.  
**Failures:** Abuse, spam, message delivery failure, harassment, unauthorised contact disclosure.  
**Acceptance criteria:** Access is limited to eligible parties; moderation and reporting are available; block/mute is enforced; private residential addresses/contact details are not exposed by default.  
**Dependencies:** Booking/listing relationship policy, moderation, privacy and retention policy. Chat eligibility and contact-sharing rules are OPEN DECISION.

## F-021 — Ratings and reviews
**Priority:** P1  
**Roles:** Reader, Owner, Moderation Admin  
**Description:** Allow ratings/reviews only after completed rentals.  
**Preconditions:** Rental state COMPLETED.  
**Main workflow:** Invite eligible party → submit rating/review → moderation/report process → publish according to policy.  
**Alternatives:** Edit window, report, moderation removal.  
**Failures:** Duplicate review, abusive content, review manipulation.  
**Acceptance criteria:** Only eligible completed rentals can generate reviews; duplicate and fake review controls exist; moderation is auditable.  
**Dependencies:** F-014/F-019, moderation policy.

## F-022 — Reading community, clubs and book exchange
**Priority:** P2  
**Roles:** Registered users, Community Admin  
**Description:** Posts, comments, lists, challenges, local reading clubs and mutual-approval book exchange.  
**Preconditions:** Community rules, moderation and privacy model approved.  
**Main workflow:** Create content/join club → interact → report/block → moderator action. Exchange follows separate mutual-approval workflow.  
**Alternatives:** Content removal, club closure, exchange declined.  
**Failures:** Harassment, spam, prohibited content, unsafe meetup, exchange disagreement.  
**Acceptance criteria:** Reporting, blocking and moderation are present; exchange requires mutual approval and does not bypass rental safety/payment rules; no unapproved handover point.  
**Dependencies:** F-020, approved community policy, public handover controls.

## F-023 — Referrals, promotions, bundles and reading lists
**Priority:** P2  
**Roles:** Registered users, Growth Admin  
**Description:** Referral rewards with anti-fraud checks, controlled first-rental promotions, book bundles and reading lists.  
**Preconditions:** Reward budget, eligibility and terms approved.  
**Main workflow:** Publish campaign → evaluate eligibility → apply reward/discount → record cost and fraud checks.  
**Alternatives:** Ineligible referral, revoked fraudulent reward, campaign expiry.  
**Failures:** Self-referral, duplicate accounts, abuse, budget exhaustion, pricing conflict.  
**Acceptance criteria:** Eligibility and limits are configurable; referral rewards and promotions are included in unit economics; abuse is reviewable; discounts do not bypass price floors/ceilings unless explicitly approved.  
**Dependencies:** Pricing, payments, fraud controls, legal terms.

## F-024 — Fraud detection and account lifecycle controls
**Priority:** P0  
**Roles:** Trust & Safety Admin, user, backend  
**Description:** Flag suspicious accounts, duplicate identity, OTP abuse, repeated no-shows/damage claims and suspicious listings; support suspension/reinstatement.  
**Preconditions:** Approved risk rules and authorised reviewers.  
**Main workflow:** Rule detects signal → create private alert → reviewer investigates → documented action → notify user as appropriate → manage active rental obligations.  
**Alternatives:** Dismiss alert, request information, temporary restriction, appeal/reinstate.  
**Failures:** False positive, reviewer conflict, incomplete active rental handling, unauthorised risk disclosure.  
**Acceptance criteria:** Rules are transparent/reviewable; sensitive risk signals are not public; automated flags do not make unreviewable final decisions; active-rental obligations are addressed on suspension.  
**Dependencies:** Identity, booking, dispute, moderation and audit systems; risk policy.

## F-025 — Admin console and configuration
**Priority:** P0  
**Roles:** Admin with scoped permissions  
**Description:** Manage users, verification, listings, categories, cities/localities, approved handover points, pricing, bookings, payments, deposits, commission, payouts, refunds, disputes, claims, late fees, referrals, moderation, grievances, privacy requests, legal documents, audit and analytics.  
**Preconditions:** Secure admin provisioning and permission model.  
**Main workflow:** Admin authenticates → sees permitted queue/module → performs action → backend validates permission → audit event recorded.  
**Alternatives:** Escalate, request approval, reject action, emergency restriction under policy.  
**Failures:** Privilege escalation, unauthorised evidence access, accidental financial action, audit failure.  
**Acceptance criteria:** Least privilege; no shared admin accounts; sensitive actions require appropriate role/approval; all decisions and changes are auditable; secure admin provisioning.  
**Dependencies:** Role matrix, audit architecture, operational SOPs.

## F-026 — Notifications and reminders
**Priority:** P0  
**Roles:** All relevant users, Admin  
**Description:** Deliver OTP, verification, listing, booking, payment, handover, due-date, overdue, dispute, payout, moderation and community notifications.  
**Preconditions:** Event occurs; valid contact/consent preferences; provider configured.  
**Main workflow:** Domain event → notification policy selects channel/template → provider delivery → status/retry tracking.  
**Alternatives:** Retry, fallback channel where approved, in-app notification.  
**Failures:** Provider outage, invalid destination, duplicate event, consent restriction, DLT rejection.  
**Acceptance criteria:** Notifications are event-driven and idempotent; OTP SMS meets provider/DLT rules; transactional and promotional consent are distinguished; delivery failure is observable.  
**Dependencies:** SMS/email/push providers, consent matrix, template approval.

## F-027 — Dashboards and financial/operational analytics
**Priority:** P1  
**Roles:** Reader, Owner, Admin, Finance Admin  
**Description:** Role-specific dashboards and business analytics.  
**Preconditions:** Valid source events and metric definitions.  
**Main workflow:** User opens dashboard → backend returns role-authorised aggregates → filters/report exports as permitted.  
**Alternatives:** Empty state, date/locality filter, delayed data notice.  
**Failures:** Stale aggregates, permission leakage, inconsistent financial totals.  
**Acceptance criteria:** Reader sees rentals/due dates/payments/deposit status/disputes/reviews; Owner sees copies/availability/bookings/earnings/settlements/commission/payouts/performance; Admin sees operational, financial, trust and compliance queues. GTV is not labelled revenue.  
**Dependencies:** Event/ledger model, metric definitions, privacy controls.

## F-028 — Grievances, privacy requests and legal document management
**Priority:** P0  
**Roles:** User, Grievance/Privacy Admin  
**Description:** Provide grievance and privacy request workflows and manage versioned legal documents.  
**Preconditions:** Contact/escalation ownership and legally reviewed policies.  
**Main workflow:** User submits request → case logged → assigned → response/action recorded → closure and audit.  
**Alternatives:** Escalation, identity verification for request, additional information.  
**Failures:** Missed deadline, unauthorised disclosure, incomplete deletion/retention conflict.  
**Acceptance criteria:** Request status and owner are tracked; access is restricted; relevant timelines and retention rules are configured only after legal approval.  
**Dependencies:** Legal review, privacy architecture, admin console.

## F-029 — Financial reconciliation and operational recovery
**Priority:** P0  
**Roles:** Finance Admin, Operations Admin, backend  
**Description:** Reconcile provider transactions and recover safely from delayed/duplicate webhooks, failed refunds/payouts, chargebacks and booking/payment inconsistencies.  
**Preconditions:** Provider integration and auditable transaction ledger.  
**Main workflow:** Ingest signed event/provider report → idempotently update ledger → compare provider and platform records → create exception → investigate and resolve.  
**Alternatives:** Retry provider operation, manual review, escalate.  
**Failures:** Mismatch, missing webhook, duplicate event, provider report delay, unresolved chargeback.  
**Acceptance criteria:** Exceptions are visible; retries are safe; reconciliation history is retained; financial state cannot be silently edited; manual adjustments require permission and reason.  
**Dependencies:** F-016/F-017, provider reports/API, ledger and audit.

## F-030 — Locality, city and handover-point administration
**Priority:** P0  
**Roles:** Location Admin, users  
**Description:** Add, disable and modify cities, localities and approved public handover points without code changes.  
**Preconditions:** Admin permission; location verification and operational approval.  
**Main workflow:** Admin creates/edits location → verifies public status and details → enables location → discovery and scheduling use active configuration.  
**Alternatives:** Temporarily close point, disable locality, reassign scheduled handovers.  
**Failures:** Incorrect coordinates/details, unsafe/closed venue, conflicting scheduled handovers.  
**Acceptance criteria:** Configuration is data-driven; inactive points cannot be newly booked; existing bookings receive a controlled reschedule/cancellation path; no CCTV claim unless verified.  
**Dependencies:** Map provider, operational partner validation, F-015 and F-018.

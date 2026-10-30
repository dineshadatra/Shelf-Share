# Product Requirements Document (PRD)
## Peer-to-Peer Physical Book Rental Marketplace — India

**Document status:** Product discovery draft  
**Version:** 1.0  
**Source of truth:** Project Master Context supplied by the product owner  
**Initial markets:** Hyderabad, Telangana and Bengaluru, Karnataka  
**Currency / timezone:** INR / Asia-Kolkata  
**Development status:** Not authorised to begin application development from this document alone

---

## 1. Product vision

Create a trusted, locality-based marketplace that enables people to rent physical books from other people at affordable prices, while allowing book owners to earn from books they already own. The platform must make discovery, booking, payment, physical handover, reading, return and dispute resolution safe and auditable.

The product is a two-sided marketplace, not a conventional online bookstore. A single verified account may act as both Reader and Owner. Admins operate the marketplace, review identity submissions, moderate activity and oversee financial and safety workflows.

## 2. Business objectives

1. Create local supply and demand for rentable physical books in Hyderabad and Bengaluru.
2. Make book discovery and rental convenient through locality-based search, availability and approved public handover points.
3. Enable owners to earn rental income with transparent platform commission and settlement rules.
4. Protect readers and owners through identity review, condition evidence, two-party handover confirmation and dispute workflows.
5. Establish auditable payment, deposit, refund, payout and reconciliation processes using an eligible marketplace payment provider.
6. Build repeat engagement through wishlists, recommendations, reviews, reading communities, clubs and referrals.
7. Provide administrators with controls for pricing, localities, handover points, verification, moderation, disputes and compliance operations.
8. Measure marketplace liquidity and unit economics without confusing gross rental transaction value with platform revenue.

**Success measures to baseline and approve:** active rentable copies by locality; search-to-book conversion; completed rentals; repeat rental rate; cancellation and dispute rates; on-time return rate; owner activation; average rental value; platform commission; net contribution; locality-level supply-demand balance. Numerical targets are OPEN DECISION.

## 3. Target customers

### 3.1 Readers
People who want temporary, affordable access to physical books rather than buying every title. They discover nearby copies, book a permitted rental period, pay online, collect at an approved public point and return the copy.

### 3.2 Owners
People who lawfully own or are authorised to rent physical books and want to earn from copies that are otherwise unused. They create copy listings, set prices within platform limits, manage availability, complete handovers and receive eligible settlements.

### 3.3 Administrators and operations staff
Authorised personnel responsible for identity review, listings, pricing configuration, locations, payment operations, disputes, fraud and safety cases, moderation, grievances, privacy requests and auditability.

### 3.4 Ecosystem partners
Marketplace payment provider, SMS/DLT provider, identity verification provider, map/data provider, approved public handover venue partners, reading clubs and community partners. Their commercial and technical terms are external dependencies.

## 4. User personas

Personas below are role-based working models, not claims about validated research.

| Persona | Goal | Needs | Main concerns |
|---|---|---|---|
| Local Reader | Read a book affordably for a limited period | Nearby availability, clear total price, reliable collection and return | Book condition, privacy, refunds, safety |
| Book Owner | Earn from idle physical copies | Simple listing, control over availability and price, reliable settlement | Damage, non-return, no-shows, payout transparency |
| Dual-role Member | Rent books and list own books | One account with both reader and owner capabilities | Clear role switching and unified history |
| Verification Admin | Review identity submissions | Secure evidence access, queue, decision history | Data minimisation, errors, unauthorised access |
| Marketplace Operations Admin | Keep marketplace running | Configuration, transaction visibility, reconciliation and support tools | Fraud, failed payments, operational consistency |
| Trust & Safety Admin | Resolve reports and disputes | Evidence, case history, escalation and appeals | Fairness, safety, abuse and audit trail |

## 5. Product scope

### 5.1 In scope for the product definition
- Physical books only.
- Initial launch in selected localities of Hyderabad and Bengaluru.
- Same-city rentals only; cross-city rentals prohibited initially.
- Reader, Owner and Admin capabilities.
- Indian mobile OTP authentication; optional email for receipts/account recovery.
- Mandatory first-registration live camera-captured profile photograph, with accessible support fallback.
- Manual identity verification by authorised administrators.
- Separate registration consents and per-rental agreement acceptance.
- Book metadata and separately managed physical copies.
- Listing, availability, discovery, booking, payment, deposit, handover, active rental, extension, return, completion and dispute workflows.
- Public approved handover points and two-party QR/OTP confirmation.
- Reviews only after completed rentals.
- Dashboards, notifications, reporting, moderation, fraud controls and audit logs.
- Compliance-readiness workflows and professional review dependencies.

### 5.2 Explicitly out of scope for initial launch unless approved
- Cross-city rentals.
- E-books, audiobooks, digital lending or downloadable copyrighted content.
- Unapproved residential or isolated handover locations.
- Informal off-platform payment as the normal booking process.
- A platform-created wallet or representation of an unregulated escrow arrangement.
- Automated identity approval or unreviewable automated fraud decisions.
- Automatic deposit confiscation or arbitrary damage deductions.

### 5.3 Later / phased features
Reading community, book exchange, referrals, clubs, bundles, waitlists, advanced recommendations, promotions and reliability indicators are in the master context but require launch-phase prioritisation.

## 6. Product roles and permissions

A user account may hold Reader and Owner capabilities concurrently. Admin privileges are separate, explicitly provisioned and least-privilege.

| Capability | Guest | Unverified user | Verified Reader | Verified Owner | Admin |
|---|---:|---:|---:|---:|---:|
| Browse public listings | Yes | Yes | Yes | Yes | Yes |
| Search/map/filter | Yes | Yes | Yes | Yes | Yes |
| Wishlist | No / OPEN DECISION | OPEN DECISION | Yes | Yes | Yes |
| Submit identity verification | No | Yes | Re-verification only | Re-verification only | Review |
| Book/pay | No | No | Yes | Yes | Only via controlled support process / OPEN DECISION |
| List/manage own copies | No | No | Optional | Yes | Moderate/configure |
| Confirm own handover side | No | No | Yes | Yes | No impersonation |
| Chat/report/block | Limited / OPEN DECISION | OPEN DECISION | Yes | Yes | Moderation access |
| Review completed rental | No | No | Yes | Yes | Moderate |
| Manage users/configuration | No | No | No | No | Permission-specific |
| View private identity evidence | No | Own submission status only | Own submission status only | Own submission status only | Authorised reviewers only |
| View payment provider data | No | Own transactions | Own transactions | Own settlements | Finance-authorised roles |

**Permission principle:** Frontend visibility is not authorisation. Every sensitive operation must be authorised server-side and enforced by database policies or trusted backend functions.

## 7. User journeys

### 7.1 Registration and verification
1. Visitor opens registration.
2. Enters Indian mobile number and completes OTP.
3. System validates OTP expiry, resend cooldown, attempt limits and rate limits.
4. First-time user captures a live profile photograph using the camera; gallery upload is not an alternative for this mandatory capture.
5. User reviews and separately accepts required legal/marketplace documents and consent notices.
6. User submits identity evidence according to the stated document preference.
7. Verification enters SUBMITTED / UNDER_REVIEW.
8. Authorised admin approves, rejects or requests additional information.
9. User receives status notification.
10. Until approved, user may browse but cannot list, book or perform financial transactions.

**OPEN DECISION:** Whether any subset of registration can be saved before all consents and identity evidence are complete, and what the exact accessible camera fallback process is.

### 7.2 Reader rental journey
1. Verified Reader searches by title, author, genre, locality, language, date and duration.
2. Reader views copy-specific condition, owner, price, deposit, availability and approved handover options.
3. Reader selects a copy and rental dates/duration.
4. Backend checks eligibility, same-city restriction, availability, booking conflicts, price rules and buffer.
5. Reader accepts the rental agreement and sees an itemised checkout.
6. Reader pays through the selected marketplace payment provider.
7. Backend confirms payment from verified provider evidence/webhook, not frontend status.
8. Reader and Owner schedule collection at an approved public handover point.
9. Both parties complete authenticated QR/OTP collection steps and acknowledge condition evidence.
10. Rental becomes ACTIVE only after backend verifies the complete sequence.
11. Reader receives due-date and return reminders.
12. Return is scheduled and both parties complete return confirmation and condition evidence.
13. Disputes, if any, are routed to resolution; otherwise rental is completed and deposit is handled according to approved policy/provider arrangement.
14. Eligible review becomes available after completion.

### 7.3 Owner listing and rental journey
1. Verified Owner adds book metadata or uses ISBN lookup to prefill metadata.
2. Owner creates a physical copy record, uploads actual photographs, declares lawful ownership/authority, records condition and sets rental price/deposit.
3. Backend validates listing against admin pricing and category rules.
4. Listing is published or queued for moderation according to configured policy.
5. Owner configures availability.
6. Owner receives booking request/payment status and accepts or declines only where the booking design requires owner approval (OPEN DECISION).
7. Owner schedules public handover.
8. Owner authenticates and confirms their side of collection; cannot confirm the Reader's side.
9. Rental activates only after the complete sequence.
10. Owner receives eligible settlement under provider rules after verified handover.
11. Owner and Reader complete return workflow.
12. Owner can initiate a documented dispute with evidence when justified.

### 7.4 Admin verification and dispute journeys
Admins work from queues with role-specific access. They inspect submitted evidence, record reasoned decisions, request additional information, maintain audit logs, and notify affected users. Dispute admins review both parties' evidence and counter-evidence, apply approved policies, document decisions and provide appeal handling.

## 8. Functional requirements

The detailed feature specifications and acceptance criteria are in `FEATURE_CATALOG.md`. The functional requirement groups are:

| Group | Requirements |
|---|---|
| Identity & access | Mobile OTP, sessions, first-use live photo, identity submission, manual review, age eligibility, account lifecycle |
| Consent & legal | Versioned terms/privacy/rules/consents, per-rental agreement, downloadable copies, renewed consent on material change |
| Catalogue | Metadata, physical copy records, ownership declaration, photographs, condition, ISBN autofill, prohibited-copy controls |
| Discovery | Locality search, map, filters, wishlist, recommendations, waitlist |
| Booking | Availability, conflict prevention, duration options, buffer, booking state machine, extension, early return, overdue |
| Payments | Marketplace provider, online collection, commission, deposit handling, refunds, owner settlements, webhook/reconciliation |
| Handover | Approved public points, scheduling, QR/OTP, separate party confirmations, evidence, anti-replay |
| Returns & disputes | Return evidence, damage assessment, non-return, grace period, dispute, appeals, compensation |
| Engagement | Chat, ratings/reviews, community, exchange, referrals, clubs, bundles and promotions |
| Trust & safety | Reports, blocks, moderation, fraud alerts, account suspension/reinstatement, safety centre |
| Admin & operations | Verification, catalogue, locations, pricing, transaction operations, disputes, grievances, privacy requests, audit |
| Analytics | Marketplace, financial, operational, safety and locality liquidity metrics |
| Notifications | OTP, transactional, reminders, status updates, disputes, payouts and community moderation events |

## 9. Non-functional requirements

| ID | Requirement | Acceptance / verification |
|---|---|---|
| NFR-001 | Security by design | Threat model, security tests, least privilege, server-side authorisation and RLS policies reviewed |
| NFR-002 | Privacy and data minimisation | Purpose notices, restricted evidence access, retention/deletion rules and privacy request workflow approved |
| NFR-003 | Financial integrity | Idempotent payment processing, immutable/auditable ledger events, reconciliation and no frontend-trusted payment state |
| NFR-004 | Booking consistency | Concurrent booking tests prove no double-booking under race conditions |
| NFR-005 | Availability | Service-level target OPEN DECISION; monitoring and incident procedures required |
| NFR-006 | Performance | Page/API latency targets and load profile OPEN DECISION; establish measurable budgets before launch |
| NFR-007 | Scalability | Locality/city configuration must not require code changes; database and service design support growth |
| NFR-008 | Accessibility | Camera fallback, keyboard and screen-reader usability, readable contrast and accessible error states; target standard OPEN DECISION |
| NFR-009 | Reliability | Retry-safe jobs, webhook replay handling, backups, restore tests and rollback procedures |
| NFR-010 | Observability | Structured logs, metrics, tracing/error monitoring, alerting and audit logs without leaking sensitive data |
| NFR-011 | Maintainability | Modular code, migrations, documented APIs, meaningful Git history and review workflow |
| NFR-012 | Testability | Unit, integration, end-to-end, security, performance and recovery tests |
| NFR-013 | Data integrity | Foreign keys, constraints, valid state transitions, uniqueness and referential integrity |
| NFR-014 | Interoperability | Provider abstraction for SMS, payment, identity and maps; current API capabilities verified before integration |
| NFR-015 | Localisation | INR formatting, Asia/Kolkata business time, Indian mobile number handling; additional languages OPEN DECISION |
| NFR-016 | Auditability | Administrative decisions and financial state changes attributable, timestamped and tamper-resistant to an approved design |
| NFR-017 | Compatibility | Supported browser/device matrix OPEN DECISION; responsive web experience required by product direction |
| NFR-018 | Data retention | Retention periods for identity, payment, evidence, chat and audit records OPEN DECISION, subject to legal review |

## 10. Business rules

1. Physical books only at initial launch.
2. One account can be both Reader and Owner.
3. Initial launch markets are Hyderabad and Bengaluru; cities/localities/handover points are admin-configurable.
4. Cross-city rentals are prohibited initially.
5. Currency is INR and timezone is Asia/Kolkata.
6. Platform commission is 10% of rental fee; deposit is separate and commission is not stated to apply to deposit.
7. Reader pays online through an eligible marketplace provider.
8. Owner settlement is eligible only after verified physical handover and remains subject to provider rules.
9. Do not simulate escrow or a legally held wallet using an application balance.
10. Rental durations include 3, 7, 15 and 30 days plus configurable custom durations.
11. Owner price cannot exceed administrator-configured maximum pricing rules based on book value, category, condition and duration.
12. Admin rates and policy values must be configurable, not hardcoded.
13. Ordinary off-platform payment is not part of the normal booking flow.
14. No arbitrary damage deductions.
15. Unverified users may browse but cannot list, book or perform financial transactions.
16. First-registration profile photograph must be live camera-captured; provide accessible support fallback.
17. Identity review is manual by authorised admin.
18. PAN is not address proof; address verification necessity is unresolved.
19. ISBN or cover image does not prove ownership.
20. Owner must declare lawful ownership/authority to rent.
21. Pirated photocopies, counterfeits and unauthorised reproductions are prohibited.
22. No double-booking; booking confirmation must be atomic.
23. Extension requires owner approval, availability check and payment confirmation before due-date change.
24. Only approved public handover points; never expose residential addresses or recommend isolated places.
25. Both parties must independently authenticate and confirm their handover side.
26. A single user cannot confirm both parties' actions.
27. Rental becomes ACTIVE only after backend verifies complete collection sequence.
28. Capture condition before and after rental with timestamp, rental association and user confirmation.
29. Reviews are allowed only after completed rentals.
30. Deposits are not automatically confiscated.
31. Damage compensation must be evidence-based and consider condition, age, edition, replacement availability, repairability and actual damage.
32. Fraud signals must be transparent and reviewable; sensitive risk signals are not public.
33. Initial marketplace eligibility is 18+.
34. Gross rental transaction value is not platform revenue.

## 11. Booking and rental state model

Primary sequence:

`REQUESTED → PAYMENT_PENDING → PAYMENT_CONFIRMED → HANDOVER_SCHEDULED → HANDOVER_PENDING → ACTIVE → RETURN_REQUESTED → RETURN_PENDING → RETURNED → COMPLETED`

Additional states:

`EXTENSION_REQUESTED`, `EXTENDED`, `OVERDUE`, `DISPUTED`, `CANCELLED`, `REFUND_PENDING`, `REFUNDED`.

The exact allowed transitions, who may trigger them, terminal-state rules and treatment of cancellation/dispute from each state must be specified in implementation design after approval. Invalid transitions must be rejected server-side.

## 12. Payment and deposit requirements

- Provider must explicitly support marketplace/vendor onboarding, settlements, refunds and the proposed deposit arrangement.
- Provider abstraction is required.
- Use signed webhooks, idempotency keys, transaction reconciliation and auditable ledgers.
- Handle duplicate/delayed webhooks, browser closure after payment, failed payments/refunds/payouts, chargebacks, booking creation failures and deposit withdrawal conflicts.
- Never trust client-reported payment status.
- Deposit is separate from rental fee and commission.
- Legal and provider-approved custody/authorisation/release model must be confirmed before enabling deposits.
- A displayed deposit balance must represent actual provider-backed status, not a fictional wallet liability.

## 13. Cancellation, refund and no-show requirements

Separate policies are required for:
- Reader cancellation.
- Owner cancellation.
- Owner no-show.
- Reader no-show.
- Mutual rescheduling.
- Handover point closure.
- Safety-related cancellation.
- Failed/delayed payment.

For each event, policy must define booking state, rental fee refund, deposit outcome, any permitted fee, owner compensation if any, account consequences, evidence and notification. Amounts, cut-offs and time windows are OPEN DECISION. No default percentage is inferred.

## 14. Damage and non-return requirements

- Capture front cover, back cover, spine, pages and existing damage before rental; repeat at return.
- Distinguish ordinary wear and tear from damage.
- Permit both parties to submit descriptions, photographs, messages and counter-evidence.
- Admin investigation and documented decision required.
- Compensation must be proportional and evidence-based.
- Do not automatically charge original purchase price.
- Do not automatically confiscate deposit.
- Non-return workflow includes reminders, grace period, owner dispute, reader response, investigation, appeal and resolution notification.
- Do not automatically characterise ordinary non-return as a criminal offence.

## 15. Fraud and safety requirements

Detect or flag suspicious accounts, duplicate identity alerts, OTP abuse, repeated no-shows, repeated damage claims and suspicious listings. Provide report user/listing, block/mute, safety centre, moderation, suspension/reinstatement and handling of active-rental obligations. Risk decisions must be reviewable; no public disclosure of sensitive risk signals.

## 16. Admin responsibilities

- User and identity verification queue.
- Additional-information and rejection workflows.
- Listing/copy moderation and prohibited content handling.
- Categories, cities, localities and approved public handover points.
- Pricing ceilings, valuation and condition policy configuration.
- Bookings, payment/deposit/refund/payout operations and reconciliation.
- Disputes, damage claims, non-return and appeals.
- Referrals, promotions, reviews and community moderation.
- Grievances, privacy requests and legal documents.
- Risk alerts, suspension/reinstatement and active rental handling.
- Audit logs, analytics and business reporting.
- Secure role assignment and privileged-access review.

## 17. Notifications

Notification events include:
- OTP sent, resend availability, invalid/expired OTP.
- Registration completion and consent/document version change.
- Identity submission, under review, additional information, approval, rejection, suspension and reverification.
- Listing submission, approval/rejection, booking request/status and availability changes.
- Payment pending/success/failure, refund status, deposit status, payout status and reconciliation exception where user action is needed.
- Handover scheduling, reminders, QR expiry, collection confirmation and return scheduling.
- Due-date reminders, overdue, grace-period milestones and extension request/decision.
- Cancellation, rescheduling, no-show and handover-point closure.
- Damage claim, dispute opened, response requested, decision and appeal.
- Chat, review eligibility, report outcome and account action.
- Community moderation, referral reward and promotion eligibility.

Channels, quiet hours, retry policy, language, mandatory vs optional communications and consent mapping are OPEN DECISION. OTP SMS must use a compliant provider and DLT requirements.

## 18. Reporting and analytics

### Financial
Gross rental transaction value, commission, gateway fees, refunds, applicable taxes, SMS costs, identity verification costs, referral rewards, support costs and net contribution.

### Marketplace
Repeat rental rate, booking conversion, active books/copies, active users, rental completion rate, cancellation rate, dispute rate, average rental value and locality-level liquidity.

### Operations and trust
Verification queue age, verification outcomes, handover completion, no-show rates, overdue rates, dispute resolution time, damage claims, fraud alerts and moderation actions.

**Definitions required:** metric formulas, attribution windows, exclusions, reporting timezone, cohort definitions and privacy thresholds are OPEN DECISION. Gross rental transaction value must not be reported as platform revenue.

## 19. Legal and compliance dependencies

The product must maintain compliance-readiness workflows and obtain professional review for:
- Company incorporation and local registrations.
- Consumer Protection Act and E-Commerce Rules, including the amendment scheduled in the source context for 1 January 2027.
- DPDP Act and phased DPDP Rules requirements.
- GST and marketplace obligations.
- Current income-tax withholding obligations.
- RBI-regulated payment-provider arrangements.
- TRAI DLT requirements for SMS.
- IT Act and Intermediary Rules applicability.
- Copyright and book reproduction.
- Telangana and Karnataka local business requirements.
- Grievance officer and consumer complaints.
- Trademark and brand protection.

No feature is proof of legal compliance by itself. Legal documents are drafts until reviewed by an Indian lawyer. Exact applicability, commencement dates, retention obligations, consent basis and role allocation must be validated against current official sources by qualified counsel before launch.

## 20. Launch assumptions

- Two initial cities only, with locality-by-locality rollout.
- Physical books only.
- Same-city rentals only.
- 18+ eligibility.
- Mobile OTP is the authentication channel.
- Manual identity approval is required before marketplace transactions.
- Public approved handover points are mandatory.
- Marketplace payment provider is required; provider not yet selected.
- Pricing and policy values are admin-configurable.
- Web-first responsive product is assumed from the proposed stack; native app scope is not established.
- No numerical launch targets, service levels, operating hours, staffing model or locality list has been approved.

## 21. Contradictions, ambiguities and open decisions

The source is broadly coherent but underspecified in several operationally critical areas. The complete register is in `OPEN_DECISIONS.md`. Key items:
- Whether bookings are automatically confirmed after payment or require owner acceptance.
- Whether identity documents are mandatory at registration or may be submitted after browsing.
- Address verification approach and evidence, since PAN is not address proof.
- Deposit collection, custody, release, refund and dispute handling.
- Cancellation/no-show/refund amounts and cut-offs.
- Late-fee calculation, cap and grace period.
- Owner settlement timing and provider conditions.
- Rental duration start/end calculation and custom-duration rules.
- Who bears gateway fees, taxes and withholding.
- Whether owner may rent their own listed book as a Reader.
- Chat access and contact-detail sharing policy.
- Initial launch feature subset and operational staffing.

No unresolved policy is silently filled in by this PRD.

## 22. Product completeness assessment

**Assessment: Product concept and feature breadth are well defined; launch-ready operational policy is not yet complete.**

Strengths:
- Clear two-sided marketplace model and initial geography.
- Strong safety principles around public handovers and two-party confirmation.
- Recognition of marketplace payment complexity and prohibition on fake escrow.
- Detailed lifecycle coverage for condition evidence, disputes and non-return.
- Security, privacy, auditability and legal dependencies are explicitly recognised.

Gaps blocking a build-ready baseline:
- Payment/deposit provider and legal custody design.
- Detailed pricing, cancellation, refund, late-fee and damage policies.
- Booking acceptance semantics and exact state-transition authority.
- Identity/address verification policy and data retention.
- Launch MVP scope, targets, service levels and operations ownership.
- Notification channel/consent matrix and support escalation model.

**Recommendation:** Approve the product direction and role model first; resolve P0 decisions before architecture and implementation planning. Product discovery documentation is the current deliverable; application development has not started.

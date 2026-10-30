# Requirements Traceability Matrix
## Peer-to-Peer Physical Book Rental Marketplace

**Purpose:** Trace source requirements to documented features, business rules and acceptance evidence.  
**Status:** Requirements are documented, not implemented. Test references below describe required test coverage, not completed tests.

## 1. Traceability legend

- **Source area:** Section heading/number in Project Master Context.
- **Feature IDs:** See `FEATURE_CATALOG.md`.
- **Business rules:** See `BUSINESS_RULES.md`.
- **Verification:** Evidence required before a requirement can be marked implemented/accepted.
- **Status:** `DOCUMENTED — NOT IMPLEMENTED` unless otherwise approved.

## 2. Requirement traceability

| Source requirement | Requirement summary | Feature IDs | Business rule IDs | Required verification evidence | Status |
|---|---|---|---|---|---|
| Master Context §1–2 | Three roles; dual Reader/Owner account; initial Hyderabad/Bengaluru locality scope; no cross-city | F-010, F-025, F-030 | BR-001–007 | Role/permission tests; city/locality configuration test; cross-city booking rejection | DOCUMENTED — NOT IMPLEMENTED |
| §3 | 10% commission; separate deposit; online payment; settlement after verified handover; duration options; configurable price ceiling | F-009, F-013, F-016, F-017 | BR-050–058, BR-070–079 | Fee calculation tests; provider capability sign-off; pricing rule tests; ledger reconciliation | DOCUMENTED — NOT IMPLEMENTED |
| §4 | Indian mobile OTP; no email OTP; rate limits; live first-registration photo; manual identity verification; statuses; unverified restrictions | F-001, F-002, F-003 | BR-010–021 | OTP abuse tests; camera capture/fallback accessibility test; reviewer permission test; unverified action denial | DOCUMENTED — NOT IMPLEMENTED |
| §5 | Separate unchecked consents; version/hash/timestamp/user; rental agreement; downloadable documents; renewed consent | F-004, F-005, F-028 | BR-030–035 | Consent persistence/version tests; mandatory acceptance tests; downloadable copy validation | DOCUMENTED — NOT IMPLEMENTED |
| §6 | Metadata separated from physical copies; unique copy; lawful ownership declaration; prohibit pirated/counterfeit copies | F-006, F-007 | BR-040–044 | Data model constraints; listing workflow tests; prohibited listing moderation tests | DOCUMENTED — NOT IMPLEMENTED |
| §7 | Before/after condition evidence; damage framework; normal wear distinction; no automatic original-price charge | F-008, F-019 | BR-045–046, BR-100–108 | Evidence completeness tests; reviewer decision audit; damage policy test cases | DOCUMENTED — NOT IMPLEMENTED |
| §8 | Availability calendar; conflict-free booking; atomic confirmation; buffer; extension; early return; overdue/grace/late fee | F-013, F-014, F-018, F-019 | BR-060–069 | Concurrent booking test; extension approval/payment tests; due-date boundary tests | DOCUMENTED — NOT IMPLEMENTED |
| §9 | State machine; duplicate/delayed webhooks; failures; chargebacks; idempotency; provider abstraction; no frontend trust | F-014, F-016, F-017, F-029 | BR-066–079 | State-transition tests; signed webhook tests; replay/idempotency tests; reconciliation scenarios | DOCUMENTED — NOT IMPLEMENTED |
| §10 | Approved public handover points; QR/OTP; two-party confirmations; anti-replay; no residential address | F-015, F-030 | BR-080–088 | QR expiry/replay tests; actor separation tests; location allowlist tests; no ACTIVE before complete sequence | DOCUMENTED — NOT IMPLEMENTED |
| §11 | Separate cancellation/no-show/reschedule/safety/location/payment outcomes | F-018 | BR-090–093 | Approved policy matrix; scenario-based refund and state tests | DOCUMENTED — NOT IMPLEMENTED |
| §12 | Resolution centre; evidence/counter-evidence; investigation; proportional compensation; appeal; no automatic confiscation/criminal label | F-019, F-028 | BR-100–108 | Dispute workflow tests; role separation; appeal test; compensation audit | DOCUMENTED — NOT IMPLEMENTED |
| §13 | Discovery, map, wishlist, recommendations, chat, reviews, history, earnings, photos, QR, reminders, referrals, community, exchange, filters, ISBN, bundles, reliability, locality, waitlist, clubs, promotions | F-006, F-008, F-010, F-011, F-012, F-015, F-020, F-021, F-022, F-023, F-027 | BR-110–116 | Feature-specific acceptance tests; moderation and privacy tests; phase approval | DOCUMENTED — NOT IMPLEMENTED |
| §14 | Fraud detection, duplicate identity, OTP abuse, no-show/damage patterns, reporting, blocking, safety, suspension/reinstatement, 18+ | F-001, F-003, F-020, F-024 | BR-005, BR-110–116 | Risk rule review; false-positive appeal test; active-rental suspension test; age gate test | DOCUMENTED — NOT IMPLEMENTED |
| §15 | Reader, Owner and Admin dashboards with operational/financial details | F-025, F-027, F-029 | BR-120–123 | Role-based dashboard data tests; financial reconciliation; access control tests | DOCUMENTED — NOT IMPLEMENTED |
| §16 | GTV, commission, fees, refunds, taxes, costs, net contribution, marketplace metrics; GTV not revenue | F-027, F-029 | BR-120–123 | Metric definition catalogue; finance reconciliation; dashboard label review | DOCUMENTED — NOT IMPLEMENTED |
| §17 | Legal/compliance readiness areas and lawyer review; current official sources | F-004, F-005, F-016, F-017, F-026, F-028 | BR-030–035, BR-070–079 | Legal counsel sign-off; provider due diligence; compliance checklist with evidence | DOCUMENTED — NOT IMPLEMENTED |
| §18 | React/TypeScript/Vite/Tailwind/shadcn; Supabase/Postgres/Auth/Storage/Realtime/Edge; provider abstractions | F-001, F-016, F-026, F-029 | BR-130–137 | Architecture review; provider capability validation; integration contract tests | DOCUMENTED — NOT IMPLEMENTED |
| §19 | RLS, server auth, least privilege, IDOR/privilege protection, secure uploads, QR replay, webhook validation, audit, rate limits, secrets, backups | F-001, F-003, F-008, F-015, F-016, F-024, F-025, F-029 | BR-130–137 | Threat model; RLS tests; penetration/security tests; secret scan; restore test | DOCUMENTED — NOT IMPLEMENTED |
| §20 | Dev/stage/prod, migrations, automated/integration/E2E/security/performance tests, monitoring, reconciliation, backup/restore, rollback, docs, Git reviews | F-025, F-029 | BR-130–137 | CI pipeline evidence; migration test; E2E suite; rollback and restore drill; review records | DOCUMENTED — NOT IMPLEMENTED |

## 3. Feature-to-test acceptance coverage

| Feature ID | Minimum test groups required | Critical negative cases |
|---|---|---|
| F-001 | Unit, integration, security, SMS provider | OTP brute force, expired/reused OTP, resend abuse, session theft |
| F-002 | Device/E2E, accessibility, privacy | Gallery substitution, permission denial, insecure public storage |
| F-003 | Workflow, security, audit | Unauthorised reviewer, unverified booking, evidence leakage |
| F-004–005 | Unit, E2E, audit | Missing consent, stale version, altered hash, bypassed rental agreement |
| F-006–007 | Unit, integration, moderation | Duplicate copy, false ownership proof, prohibited listing |
| F-008 | E2E, storage security, audit | Evidence overwrite, cross-rental access, missing timestamp |
| F-009 | Unit, financial | Price above ceiling, deposit included in commission base |
| F-010–012 | Search, map, privacy, E2E | Cross-city result, residential address leakage, stale inventory |
| F-013 | Concurrency, integration, load | Simultaneous booking, stale calendar, buffer bypass |
| F-014 | State-machine, integration | Invalid transition, duplicate transition, unauthorised actor |
| F-015 | E2E, security, replay | QR replay, expired token, one actor confirms both sides |
| F-016–017 | Provider sandbox, webhook, ledger, reconciliation | Forged webhook, duplicate webhook, unsupported deposit, payout mismatch |
| F-018 | Policy scenario, payment integration | Wrong refund, repeated cancellation, no-show misclassification |
| F-019 | E2E, dispute, evidence, audit | Automatic deposit confiscation, unreviewed damage claim, missing appeal |
| F-020–023 | Moderation, privacy, fraud | Harassment, fake review, referral abuse, exchange bypass |
| F-024 | Risk rule, reviewer workflow, appeal | False positive, public risk signal, suspension without active-rental plan |
| F-025 | RBAC, security, audit | Privilege escalation, shared admin access, unlogged financial action |
| F-026 | Provider, retry, consent | Duplicate notification, promotional message without consent, DLT rejection |
| F-027 | Data correctness, RBAC, finance | GTV labelled revenue, cross-user data leakage, stale balances |
| F-028 | Privacy, grievance workflow, audit | Unauthorised disclosure, missed ownership, deletion/retention conflict |
| F-029 | Reconciliation, recovery, idempotency | Silent ledger edit, duplicate refund, unreconciled provider state |
| F-030 | Admin workflow, location, E2E | Inactive venue selectable, false CCTV claim, existing booking orphaned |

## 4. Release gates

### Gate A — Product decisions
- P0 OPEN DECISION items resolved or explicitly deferred with a safe disabled state.
- MVP scope and initial localities approved.
- Commercial model and payment/deposit provider feasibility confirmed.

### Gate B — Legal and provider readiness
- Indian legal counsel reviews terms, privacy, marketplace policies, deposits, taxes and applicable regulatory obligations.
- Payment provider confirms marketplace onboarding, settlements, refunds and deposit support in writing.
- SMS provider/DLT registration and templates approved.
- Identity verification and retention design approved.

### Gate C — Security and operational readiness
- RLS and server-side permissions tested.
- Admin roles and evidence access reviewed.
- Booking concurrency and QR anti-replay tests pass.
- Payment webhook/idempotency/reconciliation tests pass.
- Backup restore and rollback drills completed.
- Support, grievance and dispute operations staffed and documented.

### Gate D — Pilot launch
- Approved localities and public handover points validated.
- Pilot users, owners, copy inventory and support process ready.
- Metrics and thresholds approved.
- Incident response and escalation ownership confirmed.

## 5. Change control

Any change to a source requirement must update:
1. `PRD.md` requirement and scope.
2. `FEATURE_CATALOG.md` affected feature and acceptance criteria.
3. `BUSINESS_RULES.md` affected policy.
4. `USER_JOURNEYS.md` affected journey.
5. `OPEN_DECISIONS.md` approval status and rationale.
6. This traceability matrix and associated test evidence.

A requirement is not complete merely because a UI screen exists. Completion requires implementation, server-side enforcement where relevant, tests, operational ownership and evidence.

# Business Rules
## Peer-to-Peer Physical Book Rental Marketplace

**Status:** Source-derived rules plus clearly labelled OPEN DECISION items.  
**Rule principle:** No unresolved financial, legal or safety policy is to be inferred in code.

## 1. Marketplace eligibility and geography

| ID | Rule |
|---|---|
| BR-001 | Initial launch scope is Hyderabad and Bengaluru. |
| BR-002 | Locality-level availability is required; admins can add/disable/modify cities, localities and approved handover points without code changes. |
| BR-003 | Cross-city rentals are prohibited initially. |
| BR-004 | Currency is INR; business timezone is Asia/Kolkata. |
| BR-005 | Initial marketplace eligibility is 18+. Age-verification method and evidence are OPEN DECISION. |
| BR-006 | Physical books only at initial launch. |
| BR-007 | One account may act as both Reader and Owner. |

## 2. Authentication and verification

| ID | Rule |
|---|---|
| BR-010 | Indian mobile OTP is required for registration/authentication. |
| BR-011 | Email OTP must not be used for login or registration. Email may be optional for receipts/account recovery. |
| BR-012 | OTP expiry, resend cooldown, attempt limits and rate limiting are required. |
| BR-013 | Mobile number changes require re-verification. |
| BR-014 | First-time registration requires a live camera-captured profile photograph; gallery upload is not an equivalent alternative. |
| BR-015 | Provide an accessible support/fallback process when camera access is unavailable. Exact procedure is OPEN DECISION. |
| BR-016 | Public avatar and private identity evidence must be stored separately. |
| BR-017 | Identity review is manual by an authorised Admin. |
| BR-018 | Document preference is Passport, then PAN if no passport, then Driving Licence if neither Passport nor PAN is available. |
| BR-019 | PAN is not address proof. Additional address verification is unresolved. |
| BR-020 | Unverified users may browse but cannot list, book, receive payouts or perform financial transactions. |
| BR-021 | Identity status set: NOT_STARTED, DRAFT, SUBMITTED, UNDER_REVIEW, ADDITIONAL_INFORMATION_REQUIRED, APPROVED, REJECTED, SUSPENDED, REVERIFICATION_REQUIRED. |

## 3. Consent and legal documents

| ID | Rule |
|---|---|
| BR-030 | Separate, unchecked acceptance controls are required for Terms and Conditions, Privacy Policy, User and Marketplace Rules, Identity Verification Consent, and required notification/relevant communication consents. |
| BR-031 | Consent record stores accepted document version, hash, timestamp and user ID. |
| BR-032 | Each rental requires acceptance of the relevant rental agreement. |
| BR-033 | Legal documents must be downloadable. |
| BR-034 | Materially changed terms trigger appropriate renewed acceptance. |
| BR-035 | AI-generated legal documents are drafts pending review by an Indian lawyer. |

## 4. Books and listings

| ID | Rule |
|---|---|
| BR-040 | Book metadata is separate from each physical copy. |
| BR-041 | Each copy has unique ID, owner, condition, actual photographs, price, deposit requirement, availability calendar and rental history. |
| BR-042 | Owner must declare lawful ownership or authority to rent the copy. |
| BR-043 | Pirated photocopies, counterfeit books and unauthorised reproductions are prohibited. |
| BR-044 | ISBN or cover image is not proof of ownership. |
| BR-045 | Condition evidence includes front cover, back cover, spine, pages, existing damage and additional damage. |
| BR-046 | Evidence is timestamped, associated with rental and subject to user confirmation. |

## 5. Pricing and fees

| ID | Rule |
|---|---|
| BR-050 | Platform commission is 10% of rental fee. |
| BR-051 | Security deposit is separate from rental fee and commission. |
| BR-052 | Owner may set price only up to admin-configured maximum pricing rules based on book value, category, condition and duration. |
| BR-053 | Admin pricing rates and thresholds are configurable; do not hardcode business rates. |
| BR-054 | Rental duration options are 3, 7, 15 and 30 days plus configurable custom durations. |
| BR-055 | No arbitrary damage deductions. |
| BR-056 | Ordinary off-platform payment is not part of the normal booking process. |
| BR-057 | Applicable taxes, gateway fee allocation, withholding and fee presentation require legal/accounting decision. |
| BR-058 | Gross rental transaction value must not be treated as platform revenue. |

## 6. Booking and availability

| ID | Rule |
|---|---|
| BR-060 | Owner availability calendar controls when a copy may be rented. |
| BR-061 | A copy must never be double-booked. Confirmation must be atomic/backend-controlled. |
| BR-062 | Configurable buffer time applies between rentals. |
| BR-063 | Extensions require Owner approval, availability check and payment confirmation before due-date change. |
| BR-064 | Early return is supported. Its effect on price/refund is OPEN DECISION. |
| BR-065 | Overdue reminders, grace period and configurable late fees are required; exact durations and formulas are OPEN DECISION. |
| BR-066 | Booking/payment status is controlled by backend and trusted provider evidence, not client state. |
| BR-067 | Primary state sequence: REQUESTED → PAYMENT_PENDING → PAYMENT_CONFIRMED → HANDOVER_SCHEDULED → HANDOVER_PENDING → ACTIVE → RETURN_REQUESTED → RETURN_PENDING → RETURNED → COMPLETED. |
| BR-068 | Additional states: EXTENSION_REQUESTED, EXTENDED, OVERDUE, DISPUTED, CANCELLED, REFUND_PENDING, REFUNDED. |
| BR-069 | Exact transition permissions and whether Owner approval is required before payment/confirmation are OPEN DECISION. |

## 7. Payment, deposit and settlement

| ID | Rule |
|---|---|
| BR-070 | Reader pays online through an eligible marketplace payment provider. |
| BR-071 | Provider must explicitly support intended marketplace vendor onboarding, settlements, refunds and deposit arrangements. |
| BR-072 | Provider abstraction is required to permit replacement. |
| BR-073 | Owner settlement eligibility begins only after verified physical handover and remains subject to provider rules. |
| BR-074 | Do not implement informal escrow or represent a database balance as legally held wallet funds. |
| BR-075 | Use signed webhooks, idempotency keys, transaction reconciliation and auditable ledgers. |
| BR-076 | Handle duplicate/delayed webhooks, browser closure, failed payment/refund/payout, chargebacks, booking creation failure and deposit withdrawal conflicts. |
| BR-077 | Never trust frontend payment status. |
| BR-078 | Deposit custody, authorisation/collection, release, refund, dispute hold and permitted adjustment must be approved by provider and legal counsel before implementation. |
| BR-079 | Deposits must not be automatically confiscated. |

## 8. Handover and return

| ID | Rule |
|---|---|
| BR-080 | Handover is only at approved public handover points. |
| BR-081 | Never reveal residential addresses or recommend isolated meeting places. |
| BR-082 | Collection and return support QR-based confirmation. |
| BR-083 | Collection sequence requires payment confirmed, scheduling, short-lived QR, Owner authenticated confirmation, Reader authenticated confirmation, both condition acknowledgements and backend sequence verification. |
| BR-084 | Rental becomes ACTIVE only after complete verified sequence. |
| BR-085 | Return follows a similar two-party authenticated sequence and condition evidence. |
| BR-086 | Use one-time tokens, anti-replay controls and OTP fallback. |
| BR-087 | One user must not confirm both parties' actions. |
| BR-088 | Do not claim a location is CCTV-monitored unless verified. |

## 9. Cancellation, refunds and no-show

| ID | Rule |
|---|---|
| BR-090 | Separate rules are required for Reader cancellation, Owner cancellation, Owner no-show, Reader no-show, mutual rescheduling, handover location closure, safety cancellation and failed/delayed payment. |
| BR-091 | Each outcome must define booking status, rental fee refund, deposit outcome, fee, account consequence and evidence requirements. |
| BR-092 | Refund percentages, cut-offs, no-show fees, owner compensation and rescheduling limits are OPEN DECISION. |
| BR-093 | Refund failure must be tracked and reconciled; booking cannot be marked refunded solely from a client action. |

## 10. Damage and non-return

| ID | Rule |
|---|---|
| BR-100 | Capture condition before and after each rental. |
| BR-101 | Distinguish normal wear and tear from damage. |
| BR-102 | Compensation considers evidenced original purchase price, current replacement availability, edition, age, existing condition, repairability and actual damage. |
| BR-103 | Do not automatically charge original purchase price for every damage claim. |
| BR-104 | Both parties may submit written descriptions, before/after photographs, messages and counter-evidence. |
| BR-105 | Admin investigation, documented decision and appeal process are required. |
| BR-106 | Do not automatically confiscate deposits. |
| BR-107 | Do not automatically label ordinary non-return a criminal offence. |
| BR-108 | Grace period, late-fee formula/cap, evidence standards, valuation methodology and appeal timelines are OPEN DECISION. |

## 11. Community and trust

| ID | Rule |
|---|---|
| BR-110 | Community and chat must support reporting, blocking and moderation. |
| BR-111 | Ratings/reviews are allowed only after completed rentals. |
| BR-112 | Book exchange requires separate mutual-approval workflow. |
| BR-113 | Referrals require anti-fraud checks; first-rental promotions have controlled eligibility. |
| BR-114 | Risk rules must be transparent and reviewable; sensitive risk signals are not public. |
| BR-115 | Do not make unreviewable automated decisions. |
| BR-116 | Account suspension/reinstatement must address active rental obligations. |

## 12. Financial analytics

| ID | Rule |
|---|---|
| BR-120 | Track gross rental transaction value, platform commission, gateway fees, refunds, applicable taxes, SMS costs, identity verification costs, referral rewards, support costs and net contribution. |
| BR-121 | Track repeat rental rate, booking conversion, active books, active users, completion, cancellation, dispute, average rental value and locality liquidity. |
| BR-122 | Metric definitions and formulas must be documented. |
| BR-123 | Gross rental transaction value is not platform revenue. |

## 13. Technical and operational controls

| ID | Rule |
|---|---|
| BR-130 | Row Level Security and server-side authorisation are required. |
| BR-131 | Least privilege and secure admin provisioning are required. |
| BR-132 | Protect against IDOR, privilege escalation, injection, XSS/CSRF where applicable and insecure uploads. |
| BR-133 | Service-role keys and provider secrets must never be exposed in frontend code. |
| BR-134 | Backups, restore testing, monitoring, rollback and incident procedures are required. |
| BR-135 | Git branches, meaningful commits and review workflow are required. |
| BR-136 | Maintain requirement-to-implementation-and-test traceability. |
| BR-137 | If a provider, credential, legal decision or external approval is missing, document blocker and build only a safe integration boundary; never pretend integration works. |

## 14. OPEN DECISION register summary

- OD-001: Booking confirmation and Owner acceptance semantics.
- OD-002: Identity submission timing and exact eligibility gate.
- OD-003: Address verification evidence and need.
- OD-004: Deposit custody, collection, release and dispute mechanism.
- OD-005: Cancellation/refund/no-show matrix and cut-offs.
- OD-006: Late fee, grace period, cap and calculation.
- OD-007: Damage valuation and compensation matrix.
- OD-008: Rental clock, due date, timezone and custom-duration calculation.
- OD-009: Early-return pricing/refund.
- OD-010: Owner payout timing and provider requirements.
- OD-011: Gateway fee, taxes and withholding allocation.
- OD-012: Owner renting own listed copy.
- OD-013: Chat access, contact exchange and retention.
- OD-014: Wishlist/waitlist eligibility and reservation semantics.
- OD-015: MVP launch feature scope.
- OD-016: Launch localities, handover points and operating capacity.
- OD-017: Numerical success targets, SLA and performance budgets.
- OD-018: Notification channels, consent, quiet hours and language.
- OD-019: Age verification method.
- OD-020: Camera-unavailable accessibility fallback.
- OD-021: Identity/evidence/chat/audit data retention periods.
- OD-022: Admin roles, dual approval and financial action controls.
- OD-023: Metric formulas and reporting definitions.
- OD-024: Supported devices/browsers and accessibility conformance target.
- OD-025: Company operating model, support hours and grievance ownership.

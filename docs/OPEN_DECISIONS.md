# Open Decisions and Product Approval Register
## Peer-to-Peer Physical Book Rental Marketplace

**Purpose:** Record unresolved choices that must not be silently invented.  
**Status key:** OPEN = product owner decision required; LEGAL = qualified counsel/provider confirmation required; OPS = operational validation required.  
**Priority meaning:** P0 blocks safe launch/build baseline; P1 affects important scope or experience; P2 can be deferred.

## Decision register

| ID | Priority | Topic | What the source establishes | What remains unresolved / decision required | Impact |
|---|---|---|---|---|---|
| OD-001 | P0 | Booking acceptance | Booking state machine includes REQUESTED and PAYMENT_PENDING; payment must be confirmed | Does Owner approve before payment, after payment, or is booking automatic after payment? Can Owner decline after payment? | Booking state machine, payment/refund and UX |
| OD-002 | P0 | Identity submission gate | Unverified users can browse but cannot list/book/financially transact; manual review required | Must identity evidence be submitted during registration, or can user browse with incomplete profile and submit only before first transaction? | Onboarding, data collection and conversion |
| OD-003 | P0 | Address verification | Passport/PAN/DL preference; PAN is not address proof | Is separate address verification required? Which acceptable evidence and provider? | Fraud, privacy and verification operations |
| OD-004 | P0 | Deposit legal/provider model | Deposit separate from rent/commission; no fake escrow/wallet; provider must support arrangement | Is deposit collected, authorised, tokenised or otherwise handled? Who holds it? When/how released? Can any amount be held during dispute? | Provider selection, legal risk and payment architecture |
| OD-005 | P0 | Cancellation/refund matrix | Separate scenarios are required | Define cut-off windows, refund percentage/amount, fee treatment, owner compensation, deposit outcome and account consequence for every scenario | Financial policy, support and provider integration |
| OD-006 | P0 | No-show rules | Reader and Owner no-show cases must be separate | Define evidence, waiting window, fee/refund, reschedule eligibility and repeat-offender consequence | Fairness and disputes |
| OD-007 | P0 | Late fees and grace | Grace period and configurable late fees required | Define grace duration, fee formula, frequency, cap, maximum overdue period and exceptions | Pricing, notifications and disputes |
| OD-008 | P0 | Damage valuation | Evidence-based factors and proportional compensation required | Define valuation methodology, depreciation, repair estimate, evidence threshold, decision authority and cap | Deposit, dispute and legal risk |
| OD-009 | P0 | Rental clock | Durations 3/7/15/30 days plus custom | Does clock start at verified collection time? Calendar days or exact 24-hour periods? Due-time convention? Holidays/time zone? | Availability, reminders and late fees |
| OD-010 | P0 | Early return | Early return supported | Is any rental fee refunded? If yes, formula and minimum charge? Does early return free calendar immediately? | Revenue and availability |
| OD-011 | P0 | Owner settlement timing | Settlement eligibility only after verified physical handover, subject to provider rules | Exact settlement schedule, reserve/hold, failed payout handling and owner KYC requirements | Provider and finance |
| OD-012 | P0 | Payment fees and taxes | Track gateway fees, applicable taxes and withholding | Who bears gateway fees? How are GST and current withholding obligations handled and displayed? | Unit economics, checkout and accounting |
| OD-013 | P1 | Owner renting own copy | One account can be Reader and Owner | Can a user book a copy they own/listed? Likely should be prevented, but this is not stated. | Abuse prevention and data model |
| OD-014 | P1 | Wishlist/waitlist | Wishlist and waitlists listed as features | Can guests save? Is waitlist title-based or copy-based? Does notification reserve a copy? How is queue order determined? | Discovery and notifications |
| OD-015 | P0 | MVP feature scope | Broad feature set is specified | Which features are launch-critical versus later? Community, exchange, chat, referrals, clubs and recommendations could materially expand MVP. | Delivery timeline and cost |
| OD-016 | P0 | Launch localities | Hyderabad and Bengaluru; locality-based rollout | Which exact localities, venue partners, hours and operational coverage are approved? | Supply, demand and safety |
| OD-017 | P0 | Success targets | Metrics are listed | Set numerical launch goals, target supply, conversion, repeat rate, completion, dispute ceiling and contribution margin. | Go/no-go and analytics |
| OD-018 | P1 | Notifications | Many event types and DLT SMS requirement | Which channels (SMS/email/in-app/push), language, quiet hours, retry policy and transactional/promotional consent model? | Provider cost and compliance |
| OD-019 | P0 | Age verification | Marketplace eligibility 18+ | Which reliable method/evidence establishes age? Is identity document DOB sufficient? | Eligibility and privacy |
| OD-020 | P0 | Camera fallback | Live camera photo mandatory; accessible fallback/support required | Define accessible alternatives, manual support, device limitations and whether staff-assisted capture is available. | Accessibility and onboarding |
| OD-021 | P0 | Data retention | Appropriate notice, security and retention controls required | Retention/deletion periods for identity documents, profile photos, condition evidence, chats, payment records, audit and backups. | Privacy/legal architecture |
| OD-022 | P0 | Admin roles and approvals | Authorised admin review and admin console required | Define role names, evidence access, financial permissions, maker-checker/dual approval thresholds and emergency access. | Privilege and fraud risk |
| OD-023 | P1 | Analytics definitions | Metrics listed | Define exact formula, attribution, exclusions, cohort, time basis and reconciliation source for every metric. | Reporting integrity |
| OD-024 | P1 | Accessibility and compatibility | Accessible camera fallback; responsive stack implied | Choose accessibility conformance target, supported browsers/devices and minimum camera capabilities. | QA and design |
| OD-025 | P0 | Operations model | Admin responsibilities and grievance workflows listed | Define support hours, response SLAs, staffing, escalation owner, venue operations and incident coverage. | Launch readiness |
| OD-026 | P1 | Chat and contact privacy | Private owner-reader chat required | When does chat open? Can phone/email be shared? How are off-platform payment attempts handled? Retention and moderation access? | Safety and privacy |
| OD-027 | P1 | Owner listing moderation | Listing/copy moderation required | Is every listing pre-moderated or only risk-flagged? Which content rules and review SLAs? | Supply activation |
| OD-028 | P1 | Custom durations | Custom durations supported | Who can configure them, allowed minimum/maximum and pricing/availability calculation? | Pricing and booking |
| OD-029 | P1 | Buffer time | Configurable buffer required | Is buffer before, after or both? Does it vary by locality, copy or handover point? | Calendar correctness |
| OD-030 | P1 | Handover point validation | Only approved public points; configurable | Who verifies public access, opening hours, safety and continued availability? What if venue withdraws? | Operations and safety |
| OD-031 | P1 | Deposit/claim timeline | Deposit subject to agreed arrangement until rental closure | What is rental closure if dispute is open? Can undisputed portion be released? Provider/legal confirmation required. | Cash flow and disputes |
| OD-032 | P1 | Dispute appeals | Appeal process required | Appeal window, reviewer independence, number of appeals, escalation and finality. | Trust operations |
| OD-033 | P1 | Reviews | Only after completed rentals | Are both parties allowed to review? Are reviews simultaneous/double-blind? Edit window and moderation criteria? | Reputation system |
| OD-034 | P2 | Community launch | Posts, comments, lists, challenges and clubs included | Which community features are in first release? Moderation staffing and content policy? | Scope and safety |
| OD-035 | P2 | Book exchange | Separate mutual approval workflow | Is exchange in initial launch? Does it include any payment/deposit? How are condition and disputes handled? | Product/legal scope |
| OD-036 | P2 | Referrals/promotions | Anti-fraud and controlled eligibility required | Reward type, budget, eligibility, expiry, reversal and tax treatment. | Economics and fraud |
| OD-037 | P1 | Reliability indicators | Owner/reader reliability indicators listed | Which signals are public, explainable and appealable? Avoid exposing sensitive risk signals. | Reputation and fairness |
| OD-038 | P1 | Book bundles | Bundles and reading lists listed | Is bundle one booking or multiple copy bookings? Combined deposits, dates and partial returns? | Booking complexity |
| OD-039 | P1 | Book value evidence | Pricing based partly on book value | Which value source is accepted and how is age/depreciation handled? | Pricing and compensation |
| OD-040 | P1 | Currency/locale | INR and Asia/Kolkata | Additional languages and regional number/date formatting requirements? | UX and notifications |

## Contradictions and ambiguities identified

### A. No direct contradiction, but a critical state-machine ambiguity
The source gives a primary flow beginning with REQUESTED and then PAYMENT_PENDING, but does not say whether Owner acceptance happens before payment or whether payment itself confirms the booking. This must be resolved before implementation.

### B. Identity document preference versus address verification
Passport/PAN/Driving Licence preference is stated, while the source correctly notes PAN is not address proof and asks whether additional address verification is needed. The required verification standard is therefore incomplete.

### C. Deposit treatment versus dispute closure
Deposit remains subject to agreed arrangements until rental closure, while damage and non-return disputes may continue after return. The exact point at which the deposit can be released, partially released or held is not defined and depends on provider/legal capabilities.

### D. Owner settlement after handover versus cancellation/refund cases
Owner settlement eligibility starts after verified handover, but the source does not define chargeback, post-handover cancellation, early return or dispute-related settlement reversals/reserves.

### E. Mandatory live photo versus accessibility
A live camera capture is mandatory, with an accessible fallback/support process. The fallback is not specified. Product must not quietly substitute gallery upload because that would change the stated requirement.

### F. Broad feature set versus initial launch
The source includes a large community, referral, exchange and growth scope but does not assign phases. MVP scope is unresolved.

### G. Required notification consent versus transactional messages
Registration asks for required notifications and relevant communication consents. The distinction between essential service messages and optional promotional communications needs legal review and explicit preference design.

### H. Rental duration and late-fee calculation
Duration options are given, but start/end boundary, due time, grace period and late-fee formula are absent.

## Approval order recommended

1. **Commercial and money movement:** OD-001, OD-004, OD-005, OD-006, OD-007, OD-008, OD-010, OD-011, OD-012.
2. **Identity, privacy and safety:** OD-002, OD-003, OD-019, OD-020, OD-021, OD-022.
3. **Operational launch:** OD-015, OD-016, OD-017, OD-025, OD-030.
4. **Product experience:** OD-009, OD-013, OD-014, OD-018, OD-026 through OD-040.

## Approval record template

| Decision ID | Product owner decision | Approved by | Date | Notes / policy version |
|---|---|---|---|---|
| OD-001 | OPEN | | | |
| OD-004 | OPEN | | | |
| OD-005 | OPEN | | | |
| OD-015 | OPEN | | | |
| OD-016 | OPEN | | | |
| OD-019 | OPEN | | | |

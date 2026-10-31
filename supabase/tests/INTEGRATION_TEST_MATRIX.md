# Critical integration test matrix

These are integration/release tests, not assertions that the current unit suite has passed them. Run only in a disposable local Supabase project and a provider sandbox.

| Scenario | Setup / fault injection | Required assertion |
|---|---|---|
| Duplicate webhook | Replay same provider event ID | One side effect and one journal posting |
| Invalid signature | Change raw body or signature | HTTP 4xx; no payment, booking or ledger mutation |
| Failed payment | Provider canonical state FAILED | Booking remains unconfirmed |
| Browser closed after capture | Suppress browser redirect; deliver signed webhook | Booking confirmation comes from provider event |
| Amount mismatch | Provider returns different paise amount | No capture application; reconciliation required |
| Booking race | Two concurrent requests for overlapping period | At most one live reservation |
| Expired hold plus late capture | Expire hold then return successful provider capture | Never confirm conflicting booking; refund/reconcile |
| QR replay | Redeem one token twice | First valid use only; second rejected |
| Expired QR | Redeem after expiry | No session completion |
| QR cross-booking | Use token against another booking | Rejected by session binding |
| OTP brute force | Five invalid OTP submissions | Attempt limit and lockout apply |
| Two-party confirmation | Initiator confirms without counterparty | Booking remains pending |
| Missing handover evidence | Confirm without each party's condition photo | Handover cannot complete |
| Deposit release race | Two simultaneous release requests | At most one request; no double release |
| Active-rental deposit lock | Request release during active rental | Rejected |
| Deposit dispute lock | Open dispute then request release | Rejected |
| Failed refund | Provider returns uncertain/failed status | Keep pending/reconciliation status; not refunded |
| Failed payout | Provider transfer fails | Owner payable remains outstanding; no duplicate transfer |
| Chargeback | Verified chargeback event | Dispute linked; relevant settlement restricted |
| Cross-city booking | Reader city differs from copy city | Request rejected by current launch policy |
| Owner no-show | Reader reports Owner no-show | Incident recorded; no automatic fee/forfeiture |
| Wrong no-show reporter | Owner tries to report their own no-show | Rejected |
| Duplicate refund | Replay same idempotency key | Same refund request; no duplicate movement |
| Due sweep idempotency | Run due scheduler repeatedly at same due threshold | One notification per booking/user/reminder key |
| Grace period | Advance test clock into and past grace period | No overdue state/fee proposal before grace; overdue after grace |
| Late fee cap | Run daily proposal beyond configured maximum | Proposed fees do not exceed approved cap; charged total remains zero |
| Extension approval | Owner approves zero-fee extension under enabled policy | Reservation and due timestamp move atomically |
| Paid extension gate | Owner approves extension where price/payment is required | Request stays approved_pending_payment; original due date remains |
| Reschedule collision | Owner accepts dates overlapping another reservation | Reschedule conflict; original period is unchanged |
| Cancellation with captured rent | Cancel a paid, pre-collection booking | Refund review is queued; no false refunded status |
| Early return | Reader asks for early return | Existing return QR/OTP and two-party evidence flow required |
| Claim without baseline | Submit physical damage claim without collection photos | Rejected |
| Normal wear | Attempt to file normal wear as compensation claim | Category rejected; no claim/fee |
| Respondent opportunity | Admin decides before response or response deadline | Decision rejected |
| Proportional decision | Admin approves more than amount claimed | Rejected |
| No arbitrary deduction | Decide a claim or appeal | No payment/deposit ledger or captured payment is mutated |
| Appeal | Submit and decide appeal | Appeal window, reviewer, outcome and reason are recorded |
| Case evidence IDOR | Submit case evidence with another user's path/case | Rejected |
| Safety report | Report unsafe public handover | Report and risk alert created, support queue notified |
| Block/mute | Block another user or mute a conversation | Only caller's own relationship/preferences change |
| Block enforcement | Sender tries to message a participant who blocked them, or whom they blocked | Message insert is rejected by DB trigger; active rental obligations remain intact |
| Account suspension | Suspend user with an active rental | New activity blocked; active booking, payment and return obligations remain |

## Database checks

On local Supabase, run:

```powershell
supabase db reset
supabase db lint
supabase test db
```

The migrations include the GiST exclusion constraint for overlapping live reservations, participant/city checks, append-only case evidence and lifecycle audit events. Verify those constraints with concurrent transactions in the disposable project, not only sequential unit tests.

## Provider sandbox tests

Do not use a real-money account. The chosen provider adapter must have written approval for ShelfShare's exact marketplace model. Verify signature validation, idempotency, canonical payment lookup, refund status, payout status, chargebacks, settlement reports and late/out-of-order webhook behaviour. Never infer provider success from an HTTP 200 intent response or browser redirect.

## Notifications, support and financial analytics

Run these after applying migrations 202610310008 through 202610310012 in a disposable Supabase project. Use provider mocks, never real customer phone numbers or live SMS credentials.

| Scenario | Setup / fault injection | Required assertion |
|---|---|---|
| OTP isolation | Request Supabase Auth phone OTP | Auth owns delivery; OTP value never appears in notifications, event payloads, delivery jobs or logs |
| Default preferences | Create a new auth user | In-app enabled; service/marketing SMS, email and push disabled |
| Consent provenance | Enable SMS without source/version | RPC rejects |
| Separate service/marketing consent | Enable only service SMS | Service notifications can queue; community/marketing notifications cannot |
| Consent revoke before send | Queue SMS, revoke preference, then run dispatcher | Job remains cancelled and gateway receives no request |
| Consent race | Pause worker before its pre-send check, revoke consent, resume worker | notification_delivery_job_sendable returns false; gateway receives no request |
| Unconfirmed phone | Opt into SMS without a confirmed auth phone | No delivery job is claimed |
| DLT template disabled | Enable user consent but leave template disabled or missing PE/header/content ID | No SMS job is queued or sent |
| DLT variable injection | Put unapproved variable, OTP-like variable, newline or markup in payload | Template renderer rejects delivery |
| Provider retry | Mock 5xx/timeouts and run worker repeatedly | Backoff applied; max attempts dead-letter; no duplicate job |
| Provider success | Return provider reference and actual costPaise | Job marked sent; provider reference stored; one SMS cost entry |
| Missing provider cost | Return success without costPaise | No fabricated SMS cost is inserted |
| Duplicate domain event | Replay same booking/payment/dispute event transition | One event per dedupe key and no duplicate channel delivery |
| Verification resubmission | Move rejected/needs_resubmission verification back to pending | Applicant and active verification reviewers are notified |
| Community notification | Comment on another user's published post | Post author notified; no author self-notification; drafts do not trigger activity |
| Handover notifications | Complete collection and return handover sessions | Both reader and owner notified with correct handover/return event |
| Booking notifications | Insert, accept and decline booking requests | Owner receives request; reader receives accepted/rejected outcome |
| Support ticket creation | Create ticket using an inactive/unknown category | Rejected; valid category creates one ticket, first message and history entry |
| Support ticket privacy | Request another user's ticket/messages as a customer | RLS denies access; internal notes are never visible to requesters |
| Internal note | Requester attempts internal note | Rejected; support staff can add internal note |
| Assignment permissions | Assign ticket to inactive/non-support user | Rejected |
| Status workflow | Move open -> in_progress -> waiting_user -> resolved -> closed | Every transition recorded; timestamps set; closed ticket cannot receive replies |
| Resolution reply | Staff sends public resolution reply then resolves ticket | Requester gets update; public response visible; history records resolution |
| SLA first response | Advance test clock beyond first response due | Ticket marked breached/escalated and priority increased |
| SLA resolution | Advance test clock beyond resolution due | Ticket escalated once and internal system note recorded |
| Finance role separation | Read finance analytics as admin/support agent | Permission denied |
| Finance MFA | Read analytics or record cost without AAL2 | Permission denied |
| Finance period boundaries | Capture transactions around local midnight on either boundary | Included according to Asia/Kolkata calendar date |
| GTV and refunds | Capture rent, separately collect deposit, then refund part | GTV excludes deposit and booked tax; refund shown separately |
| Cost evidence | Record gateway/verification/referral/support cost without reason/source/idempotency | Rejected |
| Cost idempotency | Replay same cost idempotency key | Same single entry; no duplicate expense |
| Cost reversal | Reverse same cost twice | Second reversal rejected; report nets the dated reversal |
| Referral issue-time | Create reward then issue it on another date | Report assigns reward expenditure to issued_at, not original creation date |
| Conversion/repeat | Create requests and captures in different date cohorts; complete repeat rentals | Ratios match documented numerator/denominator and date basis |
| Locality report | Capture rentals for physical copies in different localities | Each booking groups under the copy locality and city |
| CSV formula injection | Include strings starting with =, +, - or @ in a report value | Export prefixes formula-like cells and quotes all CSV fields |
| Finance report privacy | Download report with multiple customers | CSV contains only aggregate values, no names, phones, emails or user IDs |

The initial support SLA values in the migration are proposed defaults only. Validate the configured thresholds with the support owner before publishing them as customer-facing service commitments. DLT, consent and message-category checks must be approved with the chosen telecom provider and Indian legal counsel before enabling any SMS template.

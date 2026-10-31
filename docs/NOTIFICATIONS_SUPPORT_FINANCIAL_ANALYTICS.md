# ShelfShare Notifications, Support and Financial Analytics

## Scope and release posture

This increment adds an event log and delivery outbox to the existing notifications table, user-controlled in-app/SMS preferences, a staff-operated support workflow using the existing grievance ticket records, and an MFA-gated finance analytics/report endpoint. It is backend functionality: the repository still has no consumer-facing product UI for the preference and support screens.

The initial SMS configuration is intentionally disabled. No provider credentials, DLT sender registration, DLT content templates or telemarketer chain were supplied for this environment. No SMS should be sent until the registration and provider-specific integration steps below are completed.

## Notification events

Registered event keys cover:
- Authentication OTP (auth.otp, handled by Supabase Auth rather than copied into application notifications).
- Verification submitted, approved and rejected.
- Listing approved and rejected.
- Booking requested, accepted and rejected.
- Payment succeeded and failed.
- Collection reminder, handover confirmation, due-date reminder, overdue notice, extension request and return confirmation.
- Dispute opened and updated, refund updated and payout updated.
- Referral reward, community activity and grievance/support ticket updates.

Domain triggers create notification event records for verification, listing, booking, payment, handover, extension, dispute, refund, payout, referral, community-comment and grievance status changes. The existing rental due sweep continues to create the in-app due/overdue entries; a bridge records those events in the new outbox so opted-in service SMS can be scheduled too. Collection reminders are emitted on the booking transition to collection_pending.

Community activity presently notifies the author of a published post when a comment is added. It is not yet a general follower/subscription notification service.

### Channels and preferences

notification_preferences is created with:
- In-app notifications enabled by default.
- Service SMS disabled by default.
- Marketing/community SMS disabled by default.
- Email and push disabled and not deliverable in this increment.

Users change preferences with customer-operations actions get-notification-preferences and update-notification-preferences. SMS opt-in requires a source and consent-version string, and an append-only consent history is retained. Revocation cancels pending and processing SMS jobs; the dispatcher rechecks consent immediately before calling the gateway.

Transactional/service and marketing/community SMS flags are separate. Community notifications are categorised as marketing and need the marketing opt-in. A booking or rental service update is not automatically a marketing message; legal and telecom-provider review must confirm the correct registered message category for each template.

### India SMS / DLT release gate

TRAI's sender guidance says bulk SMS senders must complete Principal Entity registration, header assignment and content-template registration, and transmit the PE ID, header and content ID to the telecom service provider; consent template registration and consumer consent apply where required. Commercial communications require the prescribed consent acquisition. The TRAI direction on pre-tagging of variable fields must also be followed for applicable SMS templates.

Before enabling a ShelfShare SMS template:
1. Register ShelfShare as a Principal Entity with the relevant Access Provider/TSP and complete the telemarketer/aggregator chain.
2. Obtain an approved header and register the exact template in the right message category (service, transactional or promotional, as legally applicable).
3. Capture the DLT PE ID, header, content-template ID and telemarketer chain in the private DLT configuration/template records.
4. Configure the exact registered body and the list of pre-tagged variable names/types. The worker rejects unapproved, missing, unsafe, duplicated or excessive variables.
5. Where commercial/marketing consent is required, retain the registered consent evidence and confirm it matches the user's explicit preference state. The app currently records an explicit opt-in separately for service SMS and marketing SMS; counsel/TSP must confirm the final consent category and whether a particular service template requires the same mechanism.
6. Obtain counsel and TSP confirmation before enabling sms_enabled=true.

Official references:
- TRAI Advice to Senders: https://www.trai.gov.in/advice-to-senders
- TRAI Manage Your Consent: https://trai.gov.in/manage-your-consent
- TRAI Direction on pre-tagging SMS variables: https://www.trai.gov.in/notifications/press-release/trai-issues-direction-mandate-pre-tagging-variables-sms-content

Supabase Auth continues to own OTP creation and verification. Do not place OTP values in notifications, notification_events, template variables, analytics or logs. Configure the Auth SMS provider and its registered OTP template separately; auth.otp is descriptive only and is not dispatched by this worker.

### SMS provider contract

Deploy notification-dispatch as a scheduler-only endpoint, with:
- NOTIFICATION_DISPATCH_SECRET (at least 32 characters).
- SMS_GATEWAY_URL (HTTPS endpoint).
- SMS_GATEWAY_API_KEY.

The configured endpoint is expected to accept a JSON POST containing to, message, senderHeader, principalEntityId, telemarketerChain, contentTemplateId and clientReference, using bearer authentication. A successful response must contain providerReference; an optional integer costPaise records the actual provider-reported SMS cost. This is a narrow adapter contract, not a claim that a specific aggregator uses this payload. Implement and test a vendor-specific translation/response adapter before production. Phone numbers and message bodies are never written to application logs.

The notification_dlt_config singleton and notification_templates DLT fields are private backend configuration. There are no active template rows or sender values seeded by this migration. The dispatcher will fail closed while a template is disabled or any required DLT field is missing.

Email and push are not dispatched by this release; their preference flags are locked off by the current database contract. Add independently reviewed provider adapters before enabling those channels.

## Support workflow

Support reuses grievance_tickets so support cases and grievance requests do not diverge. The database adds:
- Controlled ticket categories (booking, payment, deposit, account, verification, listing, safety, privacy, other).
- Priority (low, normal, high, urgent) and the existing status set (open, in_progress, waiting_user, resolved, closed).
- Requester/staff/system message history and staff-only internal notes.
- Append-only status, priority, assignment and SLA history.
- First-response and resolution due times, actual first response, SLA breach and escalation timestamps.
- An assignment requirement that the assigned user has active support-management permission.

Customer-facing actions on customer-operations:
- create-ticket
- my-tickets
- reply-ticket
- notifications
- mark-read
- get-notification-preferences
- update-notification-preferences

Staff actions:
- support-queue
- manage-ticket (requires MFA AAL2 and a support/grievance permission)
- support-export (MFA AAL2; exports ticket operations fields, not message contents)

The initial SLA policy is a proposed starting point only:

| Priority | First response | Resolution |
|---|---:|---:|
| Low | 24 hours | 7 days |
| Normal | 8 hours | 3 days |
| High | 2 hours | 24 hours |
| Urgent | 30 minutes | 4 hours |

These are configurable database policy values, not regulatory or contractual guarantees. Operations should calibrate them to staffing and publish the final customer-facing SLA. support-sla-sweep invokes run_support_sla_sweep; schedule it regularly with SUPPORT_SLA_SWEEP_SECRET (at least 32 characters). It marks breaches, raises priority, assigns an available support staff member where possible, and records an internal escalation note.

Ticket closure and resolution are support-staff actions. Requesters can reply while a ticket is open/resolved, which reopens a resolved ticket to in_progress; a closed ticket cannot receive additional replies through the RPC. The history remains append-only.

## Financial analytics and downloadable reports

get_admin_financial_analytics(from,to) is available only to a finance_operator with finance.analytics.read and MFA AAL2. The financial-report Edge Function returns a CSV download for date ranges up to 367 inclusive days. It includes summary metrics, daily performance and locality performance. The export excludes direct customer identifiers.

All values are integer paise unless a field is a percentage/count/date. Definitions:
- Gross rental transaction value: base rental subtotal on bookings with a captured payment in the selected capture-date period. Security deposits and booked tax are excluded. It is gross of subsequent refunds.
- Commission: rows in commission_ledger created during the period.
- Gateway, SMS, verification and support costs: append-only cost entries recorded from provider invoices/receipts or other evidence. SMS cost is auto-recorded only when the provider response returns an actual costPaise; missing costs are not imputed.
- Referral expenditure: referral reward values whose issue timestamp falls in the period, plus recorded referral operating costs. Existing issued rewards are backfilled with creation time because the original issue timestamp was not stored; post-migration issuance uses the actual transition time.
- Refunds: completed/succeeded refund amounts, shown separately. They are not automatically subtracted from commission because refund principal may include rental proceeds and the system cannot assume how much platform revenue was reversed.
- Booked tax: the booking tax component for captured bookings. It is an operational amount only, not a tax-liability calculation, GST return, tax invoice register or filing.
- Net contribution before other overheads: commission less recorded gateway, SMS, verification, referral reward/operating and support costs. It is not accounting profit, cash balance, contribution after all overheads or statutory revenue.
- Repeat rental rate: readers with two or more completed bookings divided by readers with at least one completed booking in the selected completion-date period.
- Booking conversion: bookings created in the selected request-date period that have a captured payment divided by all bookings created in that request-date period. It is cohort-based and may include a later payment capture.
- Average rental value: gross rental transaction value divided by paid bookings.
- Active books now: current physical copies whose listing is approved and available for rent, independent of the selected historical period.
- Locality performance: paid bookings and gross rental transaction value grouped by the locality of the physical copy.

Finance cost entries use record_financial_cost, require finance.costs.write and MFA AAL2, and retain source reference/reason/idempotency metadata. Cost rows are immutable; use reverse_financial_cost_entry to create one evidenced, audited reversal rather than editing history. Populate gateway, verification, referral and support costs from actual invoices/receipts/approved accounting feeds. Do not invent or estimate amounts to make a dashboard appear complete.

## Deployment checklist

1. Apply 202610310008_notifications_support_financial_analytics.sql through 202610310012_notification_backfill_and_resubmission.sql in lexical order after migrations 006 and 007, in a disposable/staging Supabase project first.
2. Deploy customer-operations and financial-report with JWT verification enabled.
3. Deploy notification-dispatch and support-sla-sweep with JWT verification disabled; protect them with their independent 32-character scheduler secrets.
4. Configure APP_ORIGIN/CUSTOMER_APP_ORIGINS, FINANCE_REPORT_ORIGINS and ADMIN_PORTAL_ORIGINS to exact HTTPS origins. Do not use wildcard origins for browser APIs.
5. Configure SMS provider credentials and DLT records only after provider adapter, templates and consent policy are approved.
6. Enrol MFA for finance operators and support managers. Validate RBAC and RLS with requester, support agent, finance operator, general admin and unauthenticated sessions.
7. Configure schedulers, then test retry/dead-letter behavior, consent revocation during queue processing, SLA escalation, ticket reopening/closure, report values and CSV formula injection.
8. Review metric definitions, accounting mappings, tax treatment, privacy retention and message classification with the finance owner, Indian legal counsel and the chosen telecom provider.

No production deployment, live SMS delivery, provider reconciliation import or live database migration is performed by this code change.

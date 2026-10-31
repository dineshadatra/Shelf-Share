# ShelfShare Admin Portal and Business Operations

## What is included

A standalone staff-only admin console is delivered in the admin folder, alongside a JWT-protected Supabase Edge Function and database-enforced staff permissions. The repository does not have an existing consumer web frontend, so this console is independently hosted and is not exposed as a public consumer route.

The portal provides a permission-filtered dashboard, all 32 requested operational module views, server-side search and exact status/city/date filters where applicable, pagination, low-sensitivity CSV export, admin activity tracking, manual identity verification, catalogue/copy/community/review moderation, staff role controls, a high-risk approval queue, a support-ticket queue with conversation/history and SLA fields, and a finance-operator analytics screen with IST date filters and downloadable CSV reports.

## Role model

The existing six roles are retained:

| Role | Access |
|---|---|
| support_agent | Safe user/booking/dispute summaries, customer support and grievance queues, limited privacy-request metadata |
| verification_reviewer | Manual verification, identity-document decisions and private document access after MFA step-up |
| moderator | Book catalogue and physical-copy moderation, community posts and reviews, risk summaries |
| finance_operator | Payments, deposits, commission, payouts, refunds, damage-claim decisions, reconciliation and maker-checker finance operations |
| admin | General marketplace operations, user restriction requests, catalogue/geography, pricing/valuation drafts, community, support, privacy, legal and audit summaries |
| super_admin | General admin operations plus role management and selected approval rights; no identity-document or finance access by default |

Roles are mapped to explicit permission keys in admin_permission_catalog and admin_role_permissions. Hiding a menu item is not authorization: the Edge Function checks the permission before every data read/action, and sensitive SQL RPCs independently check the JWT permission and MFA assurance level.

## Identity and financial separation

- The ordinary verification queue never returns identity document object keys, bucket names, signed links or file contents.
- Opening a private identity document requires the verification_reviewer role, identity.documents.read, MFA assurance level AAL2 and a reason. The signed URL expires after 60 seconds. Every access is recorded.
- The admin and super_admin roles do not inherit identity document permission.
- Financial tables are not available to general admin users. The finance_operator role receives only the explicitly mapped financial permissions.
- Claim decisions are restricted to finance_operator, require MFA AAL2, evidence, a respondent response opportunity and exclusion of rental participants. The decision creates an audit record and does not deduct from a deposit.
- Refund, payout, deposit release, dispute finalization, policy publication, account restrictions and risk resolution enter a maker-checker approval queue. A requester cannot approve their own request.
- Approval does not itself execute a provider payment, refund, payout or deposit release. Provider execution and webhook/reconciliation confirmation are separate trusted operations.
- Account restriction RPCs require super-admin permission and MFA AAL2. General admins can request but cannot execute suspension.
- Staff role grant/revoke is super-admin only, self-assignment is blocked, and every change is audited.

## Activity tracking and exports

Every dashboard view, module list, CSV export, denied permission request, identity-document access, verification decision, content moderation and approval request/decision records the actor, action, module, permission, target, outcome, reason, request correlation ID and redacted metadata. Admin activity history is append-only. High-risk domain changes also write the existing admin audit log.

General admin-portal CSV export is limited to catalogue metadata, categories, geography and aggregate non-financial analytics; it is not enabled for user records, identity data, payments, deposits, payouts, refunds, disputes, evidence, referrals or support cases. A separate support-ticket export is available to support/grievance staff after MFA AAL2 and includes operations fields only, not message bodies. Financial analytics is a separate finance_operator-only endpoint after MFA AAL2 and exports aggregate finance metrics, locality and daily summaries. CSV cells are quoted and formula injection is neutralized. Ordinary pages default to 25 rows and cap at 100. Exports cap at 1,000 rows.

## Deployment

1. Apply all migrations to a disposable/staging Supabase project in filename order, including 202610310006_admin_portal_rbac.sql through 202610310012_notification_backfill_and_resubmission.sql.
2. Deploy supabase/functions/admin-portal, customer-operations, financial-report, notification-dispatch and support-sla-sweep. Keep JWT verification enabled for admin-portal, customer-operations and financial-report; disable it only for the two scheduler-only workers. Configure SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY, ADMIN_PORTAL_ORIGINS, FINANCE_REPORT_ORIGINS, CUSTOMER_APP_ORIGINS, NOTIFICATION_DISPATCH_SECRET, SUPPORT_SLA_SWEEP_SECRET, SMS_GATEWAY_URL and SMS_GATEWAY_API_KEY. Use exact HTTPS origins.
3. Host the admin folder as a separate HTTPS static site. The browser uses only the Supabase public anon key. Never embed the service-role key in the frontend.
4. Staff sign in using phone OTP on an existing account. New account creation is disabled. Enrol a verified TOTP authenticator in Supabase Auth before using high-risk actions.
5. Have an existing super-admin grant staff roles via the audited role RPCs. Role changes require AAL2 MFA.
6. Run Node unit tests, Supabase migration lint, RLS/Storage tests and disposable-project integration tests before production.

## Important implementation limits / release gates

This is the first working admin foundation, not a claim that every operational workflow is complete. All requested modules have permission-filtered list views. The current UI implements selected workflows: manual verification, short-lived identity-document access, catalogue/copy/community/review moderation, maker-checker request/decision, user restriction requests, staff role management, support ticket assignment/status/replies/internal notes and aggregate finance reporting. The customer-facing app is still absent, so user notification-preference and ticket-creation/reply screens must be integrated into that app. Geography/category CRUD, full legal-document publishing, referral campaign editing, privacy-request fulfilment, provider refund/payout/deposit execution, reconciliation file imports, financial ledger adjustments and rich drill-down analytics still need dedicated forms/RPCs and external-system integration. Provider transactions remain intentionally unavailable from the browser.

The migrations have not been applied to a live Supabase project in this task. Validate PostgreSQL syntax/dependencies, role mappings, RLS, storage policies, MFA configuration, CORS origin configuration, function deployment and transaction behavior in a fresh staging project. This code is not a substitute for an independent security review, legal approvals or payment-provider onboarding.

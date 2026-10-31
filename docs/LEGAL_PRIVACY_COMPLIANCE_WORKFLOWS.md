# Legal Documents, Privacy and Compliance Workflows

**Release state:** Implemented draft workflow — NOT LEGAL-APPROVED, NOT PUBLISHED, NOT A COMPLIANCE CERTIFICATION.

This document describes the legal/privacy implementation and the decisions required before production use. It is an engineering and legal-operations working document, not legal advice or a legal opinion.

## 1. Legal draft register

The branch includes sixteen Markdown drafts under \`docs/legal-drafts/\`:

| Key | Draft |
|---|---|
| \`terms_conditions\` | Terms and Conditions |
| \`privacy_policy\` | Privacy Policy |
| \`cookie_policy\` | Cookie Policy — applicability review |
| \`marketplace_rules\` | User and Marketplace Rules |
| \`owner_agreement\` | Owner Agreement |
| \`reader_agreement\` | Reader Agreement |
| \`rental_agreement\` | Rental Agreement |
| \`damage_compensation_policy\` | Damage and Compensation Policy |
| \`cancellation_refund_policy\` | Cancellation and Refund Policy |
| \`deposit_policy\` | Deposit Policy |
| \`non_return_policy\` | Non-Return Policy |
| \`community_guidelines\` | Community Guidelines |
| \`content_copyright_policy\` | Content and Copyright Policy |
| \`grievance_policy\` | Grievance Policy |
| \`identity_verification_notice\` | Identity Verification Notice |
| \`referral_terms\` | Referral Terms |

Every file begins with **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**. All are seeded into \`public.legal_documents\` as version \`0.1-draft\`, \`review_status='draft'\`, \`is_published=false\`, and \`effective_from=NULL\`. No user is asked to accept these drafts and none is currently a live contract or policy.

The drafts contain placeholders such as the legal entity name, address, grievance officer, contact details, policy windows, vendor locations and product decisions. Complete them against ShelfShare's actual company, commercial, operational and technical model.

## 2. Versioning, review, publication and download

The database stores the rendered Markdown content and SHA-256 of its exact UTF-8 bytes. The hash is recalculated by PostgreSQL on every save. \`legal_document_revisions\` retains immutable numbered snapshots with hash, actor, timestamp and change note. A published document's title, version, source path, content and hash cannot be edited; create a new version instead.

Publication sequence:

1. A staff member with \`legal.draft.write\` and MFA AAL2 edits a draft. Each save creates a new immutable revision.
2. Submit the draft for review; status becomes \`in_review\`.
3. Record external Indian counsel's name, review date and a reference to the written advice/engagement. This is an internal staff attestation, not independent verification of the lawyer or advice.
4. A staff member with \`legal.publish.request\` creates a \`legal.publish\` approval request.
5. A different authorised reviewer with \`legal.publish.approve\` and MFA AAL2 approves it through the Approvals module.
6. The publication action verifies the approved maker-checker request, counsel-review fields and stored content hash, sets the effective date and closes the prior version's effective period.
7. Only the effective published version is returned to end users. Published Markdown downloads are sent with \`Cache-Control: no-store\` and an \`X-Document-SHA256\` header.

The public Edge Function actions are \`current-legal-documents\`, \`download-legal-document\` and \`accept-legal-document\`. Current-document results include whether the signed-in user has accepted that exact hash, or a prior version where \`reacceptance_required=false\`. Material changes default to renewed acceptance.

The staff editor saves to the database and creates immutable database revisions; it does not commit to GitHub automatically. Download changed Markdown and commit the corresponding source file to \`docs/legal-drafts/\` through the normal Git review process. When creating the next version, use a new version number and a new source path.

**Acceptance evidence:** user ID, document ID, document SHA-256, version (via document row), acceptance context, source, database timestamp and optional hashed request metadata. Raw IP address and user-agent values are not stored by this implementation. The acceptance RPC requires the currently effective published document and exact hash. Acceptance is append-only and idempotent for the same user/document/context.

**Reacceptance integration limit:** the API exposes current accepted/missing state and the exact acceptance operation. The consumer-facing frontend is not in this repository, and the new status has not yet been wired as a database precondition in every booking, payment, listing or community command. The product frontend must block the affected action until required current acceptances are recorded; backend command guards should be added before enabling production transactions.

## 3. India legal review — do not use this as a compliance conclusion

As at 31 October 2026, the Digital Personal Data Protection Act, 2023 has a phased commencement notification. The commencement notification is G.S.R. 843(E), dated 13 November 2025. Certain institutional/procedural provisions commenced on publication; the one-year provisions are scheduled for 13 November 2026; a substantial set of processing, notice and data-principal-rights provisions is scheduled for 13 May 2027. The DPDP Rules, 2025 are also phased. Check the official Gazette, MeitY material, any corrigenda and subsequent orders immediately before relying on any date or provision.

This timing does **not** mean ShelfShare can ignore privacy, security, consumer, contract, intermediary, telecom, payment or tax obligations currently in force. Counsel should assess, at minimum:

- DPDP Act and DPDP Rules commencement/transition; lawful purposes, notices, consent where applicable, data-principal requests, children's data, security safeguards, breach notices, processor contracts, cross-border transfers and retention.
- Information Technology Act, 2000 and applicable intermediary rules if ShelfShare hosts user-generated content or qualifies as an intermediary; grievance and content takedown procedures.
- Consumer Protection Act, 2019 and Consumer Protection (E-Commerce) Rules, 2020, including the actual marketplace role, disclosures, returns/refunds, grievance officer and seller/marketplace duties.
- Copyright Act, 1957 and a rights-holder notice/counter-notice process for user-generated content and book listings.
- Applicable telecom commercial communication rules (including DLT registration and consent/template requirements) for SMS.
- Payment aggregator/provider terms and RBI requirements for marketplace collections, deposits, refunds and settlements.
- GST, income-tax, TDS/TCS and record-keeping treatment for the actual commercial flows.
- Any state-specific consumer, contract, police/safety or other requirements.

Official reference points to verify at review time: the DPDP Act, 2023; Ministry of Electronics and Information Technology (MeitY) notification G.S.R. 843(E), 13 November 2025; Digital Personal Data Protection Rules, 2025 and published corrigenda; and the 2026 Removal of Difficulties Order. The commencement schedule must be rechecked before the final policy is approved.

## 4. Privacy request workflows

Existing \`privacy_requests\` is extended with request reference, assignment, identity-check time, status, data scope, resolution summary, legal-hold flag and timestamps. Events are append-only.

Supported request types: access, correction, erasure/deletion, portability, consent withdrawal, restriction and privacy grievance. A user can submit and track their own requests. Staff can search the queue, review the case and event history, verify identity, assign a permitted staff reviewer, update status and record a resolution.

### Access and portability
\`download-my-data\` creates an authenticated JSON export of account profile/contact data, verification status, bookings, payment metadata, deposits and deposit-ledger activity, legal acceptances, consent history, notification preferences, in-app notifications, privacy/grievance requests and support-ticket metadata. The export excludes raw identity files, payment-card/bank credentials, gateway webhook payloads, internal staff notes and fraud signals, and legally privileged material. A matching open access/portability request can be marked fulfilled by including its ID in the export action. The export is a scoped account download, not a guarantee that every system record or third-party record is included.

### Correction
The implemented staff correction route requires an open correction request and verified requester identity. It only edits profile display name, bio, preferred city and locale. Authentication email/phone changes must use the account's verified recovery/change flow. Other data classes need additional field-specific correction handlers.

### Consent withdrawal
An append-only purpose ledger supports marketing communications, service SMS, product analytics, personalised recommendations, non-essential cookies and referral invitations. Service/marketing SMS withdrawal is synchronised with existing notification preferences and queued-SMS cancellation. Other purposes are recorded, but their downstream feature gates and third-party processor effects must be integrated and tested before those purposes are enabled. Essential service processing must not be falsely represented as optional consent.

### Grievance
A privacy-specific grievance can be submitted through \`privacy_requests\`; operational support/grievance tickets remain available through the existing support system. Counsel must confirm the required acknowledgement/resolution periods and external escalation details and populate the live policy.

## 5. Breach/incident register

\`privacy_breach_incidents\` records detection time, severity, affected data categories/systems, estimated people, factual summary, containment, risk and notification assessment, authority/user notification references, root cause and remediation. Updates are recorded in append-only \`privacy_breach_incident_events\` and admin audit history.

This is an incident register, not an automatic breach-detection, regulator-notification or affected-user-notification service. An incident commander and Indian counsel must assess actual notification obligations and deadlines for the facts and rules in force. Do not set a notice timestamp until a notice was actually submitted or sent.

## 6. Data retention, legal holds and erasure

No universal retention period is assumed or seeded. \`data_retention_policies\` stores draft and approved rules by data class, duration, rationale and legal basis. A separate staff member must approve a draft rule; an active rule requires a period, effective date and approval. The table \`data_retention_runs\` is an audit/run record foundation. **There is no automated general-purpose retention sweeper in this increment.** Do not infer that rows are deleted just because a policy is active.

Legal holds are recorded per person/data class, with source and reason. They block the current automated erasure queue while active. Active rental obligations also block erasure queueing and are rechecked by the worker before claiming a job.

For a verified erasure request, a maker with \`privacy.erase.request\` creates a \`privacy.erase\` approval request. A different authorised approver with MFA AAL2 must approve it. A separate queue action creates jobs only for:
- deleting source files from the private \`identity-private\` Supabase Storage bucket; and
- anonymising selected profile fields (display name becomes “Deleted user”; avatar, bio and preferred city are cleared; account status is suspended).

The scheduler-only \`privacy-erasure-worker\` is authenticated by \`PRIVACY_ERASURE_WORKER_SECRET\`, claims service-role jobs, deletes private objects and reports completion. Failed jobs retry up to the configured attempt limit and then become blocked.

**Important boundary:** this worker does not delete Supabase Auth email/phone or the auth user, booking/rental contracts, payment/deposit/commission ledgers, tax/accounting records, dispute/claim evidence, support/grievance records, legal acceptances, consent/incident records or legally required logs. The request is marked \`partially_fulfilled\` with this scope explained. Additional deletion/anonymisation handlers require per-data-class impact analysis, foreign-key strategy, legal retention review, provider coordination and explicit tests. Do not manually delete those records to make a request appear complete.

## 7. Sensitive-data access logs

\`sensitive_data_access_events\` records actor, subject, data class, resource reference, purpose, outcome, request correlation ID, timestamp and limited metadata. Identity-document access through the existing admin portal, privacy request detail, own-data exports, legal draft reads, incident reads and access-log reads write an event. Event history is append-only. Raw document images and object keys are not copied into the access log.

A log entry is not proof that the full downstream processor/viewer path is secure. Monitor access logs and test that failed log writes cause sensitive operations to fail closed.

## 8. Edge Function deployment

Apply migrations in lexical order through:

- \`202610310013_legal_privacy_compliance_workflows.sql\`
- \`202610310014_seed_legal_document_drafts.sql\`
- \`202610310015_legal_versioning_and_incident_history.sql\`

Deploy:
- \`legal-privacy-operations\` with JWT verification enabled.
- \`privacy-erasure-worker\` with JWT verification disabled and its shared secret configured; do not expose it to a browser or public caller.

Required runtime secrets: \`SUPABASE_URL\`, \`SUPABASE_ANON_KEY\`, \`SUPABASE_SERVICE_ROLE_KEY\`, exact HTTPS \`CUSTOMER_APP_ORIGINS\`, and \`PRIVACY_ERASURE_WORKER_SECRET\` (at least 32 characters). The staff console also requires its existing \`ADMIN_PORTAL_ORIGINS\`.

Do not put the service-role key or worker secret in client code. Use the service-role client only in trusted Edge Functions.

## 9. Release blockers and acceptance tests

Before publishing any policy or enabling the workflows, complete:
- Indian counsel review of all 16 documents and the actual contracting-party, marketplace, payment/deposit, grievance, privacy, retention and tax models.
- Production data map and processor/subprocessor inventory with hosting regions and cross-border flow assessment.
- Field-by-field lawful purpose/basis mapping and consent/withdrawal propagation tests.
- Cookie/SDK inventory on each production web/mobile build; publish the cookie policy only if the technologies are actually present and accurately described.
- User-side screens for current documents, version comparison, read/download, clear affirmative acceptance, reacceptance, privacy requests, data download, correction and consent withdrawal.
- Booking/payment/listing command guards that enforce current required legal acceptance server-side; this increment exposes the acceptance state/API but does not yet gate every business command.
- Retention-period sign-off by legal, tax, accounting, support and security owners; implement/test each data-class deletion/anonymisation task before scheduling.
- Breach response tabletop and statutory notification assessment.
- RLS, storage, hash-integrity, MFA, maker-checker, legal-hold and active-rental concurrency tests in a disposable Supabase project.
- Deno type check, Supabase migration lint, unit tests, database integration tests and backup/restore testing.

No migration has been applied to a live Supabase project as part of this code change. No legal document is published or legally approved by this implementation.

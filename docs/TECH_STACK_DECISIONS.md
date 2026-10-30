# Technology Stack Decisions — ShelfShare

**Decision posture:** Retain the preferred stack as the default, with conditions. Vendor names below are candidates, not selections. Capability claims must be reconfirmed against current official documentation, contract, geography, pricing and underwriting before procurement.

## 1. Decision summary

| Layer | Preferred | Decision | Rationale / caveat |
|---|---|---|---|
| Frontend | React + TypeScript + Vite | Keep | Mature ecosystem, typed modules, flexible hosting |
| UI | Tailwind + shadcn/ui | Keep | Fast consistent UI; accessibility responsibility remains with product team |
| Routing | React Router | Keep | Route/layout separation for public/member/admin |
| Server state | TanStack Query | Keep | Cache/invalidation; never authoritative for money |
| Forms | React Hook Form + Zod | Keep | Strong validation UX; repeat validation on server |
| Backend platform | Supabase | Conditional keep | PostgreSQL/Auth/Storage/Realtime/Functions reduce ops; test limits, region, recovery and function runtime |
| Database | PostgreSQL | Strong keep | Transactions, exclusion constraints, RLS, JSONB, PostGIS option |
| Auth | Supabase Auth phone OTP | Conditional | Verify custom SMS integration, DLT, limits, MFA/admin needs and recovery flows |
| Server API | Supabase Edge Functions + SQL RPC | Keep with boundaries | Good for provider adapters and commands; long-running work should be async worker |
| Storage | Supabase Storage | Conditional keep | Private buckets/signed URLs; independently verify backup/retention and image processing |
| Realtime | Supabase Realtime | Conditional keep | Chat/presence/UI updates; not source of truth |
| Search | PostgreSQL FTS initially | Keep initially | Sufficient for launch; external search only after relevance/scale evidence |
| Maps | MapLibre renderer + Mappls/Google/OSM provider | Conditional | Renderer is not data provider; terms, geocoding quality and cost decide vendor |
| SMS | DLT provider adapter; MSG91/Gupshup/Exotel candidates | No vendor selected | Must test DLT templates, deliverability, OTP integration and pricing |
| Payments | Marketplace PA adapter; Razorpay Route/Cashfree Easy Split candidates | No vendor selected | Need written approval for marketplace, split settlement, owner KYC, refunds, payouts and deposit model |
| Identity | Provider adapter; HyperVerge/Signzy/DigiLocker-linked workflow candidates | No vendor selected | Document coverage, consent, manual review, security and deletion terms |
| Hosting | Vercel/Cloudflare Pages or equivalent | No vendor selected | Compare India latency, data processing, security, cost, deployment |
| Monitoring | Sentry/OpenTelemetry-compatible stack | Evaluate | Redaction, region, retention, alert routing and cost |
| Tests | Vitest, Testing Library, Playwright | Adopt | Unit, component and browser E2E coverage |

## 2. Why modular monolith, not microservices

Launch scope is a two-city marketplace with interdependent booking, inventory, payment, collection, rental, return and dispute transitions. Distributed transactions would increase failure modes and operational burden. Use modules, clear interfaces, event/outbox boundaries and independent deployability as future option. Extract a service only when a measured bottleneck or team/regulatory boundary justifies it.

## 3. Supabase suitability and caveats

Supabase is suitable for a managed PostgreSQL-first launch because it provides database, authentication, object storage, realtime and serverless functions in one platform. It does not automatically solve:
- domain-level authorization;
- provider marketplace settlement;
- deposit custody;
- durable background processing at all workload durations;
- full-text relevance at large scale;
- independent backup/restore guarantees;
- compliance obligations.

Before committing:
- confirm project region availability and contractual data processing;
- confirm Auth phone provider/custom SMS integration supports India DLT templates and rate limits;
- verify Edge Function runtime, execution duration, concurrency and outbound network constraints;
- verify Realtime quotas and delivery semantics;
- verify storage object backup/restore separately from database;
- test PITR/backup plan and conduct restore drill;
- load-test PostgreSQL connection pooling, RLS policies and exclusion constraint contention.

If requirements exceed managed function limits, add a separate container worker/API while retaining PostgreSQL.

## 4. Payments: candidate evaluation

### Razorpay Route
Candidate for marketplace/platform use. Verify current onboarding eligibility, linked accounts, transfers, settlements, reversals, refunds, settlement holds, chargebacks, reporting and business-category acceptance. Do not assume deposit custody is supported.

### Cashfree Easy Split
Candidate for marketplace split settlements. Verify current eligibility, vendor onboarding/KYC, split instructions, refunds/reversals, delayed settlement, payout timing, reconciliation reports and supported business model. Do not assume deposit custody is supported.

### Selection rule
Run an RFP and proof-of-concept with actual ShelfShare business details. Obtain written answers and legal review. Select only if provider explicitly supports the intended model and the company is approved. Keep provider adapter and canonical internal ledger whichever vendor is selected.

## 5. SMS/OTP candidate evaluation

MSG91, Gupshup and Exotel are candidates only. Evaluate:
- Indian DLT registration and template workflow;
- OTP/transactional route support and sender ID;
- delivery and latency by operator/circle;
- retry/delivery receipt API;
- Supabase Auth custom provider compatibility or webhook-based custom OTP;
- abuse controls, fraud analytics and rate limiting;
- data processing, retention and security;
- commercial minimums and support SLA.

Never let provider OTP success substitute for KYC approval.

## 6. Identity provider evaluation

Evaluate providers such as HyperVerge and Signzy, plus permitted DigiLocker-based flows where eligible. Criteria:
- Passport, PAN and Driving Licence support per product need;
- age/DOB extraction and verification confidence;
- authenticity/liveness checks if required;
- India legal and data-processing posture;
- consent and purpose limitation;
- manual review integration;
- API/webhook reliability and auditability;
- evidence deletion and retention controls;
- pricing per verification and failure;
- false positive/false negative handling and appeal.

Do not make automated approval the final decision; manual Admin review remains the business requirement.

## 7. Maps

MapLibre GL JS is a renderer, not a geocoding/tile provider. Candidate data providers:
- Mappls: assess India-specific addresses, localities, POI and commercial terms.
- Google Maps Platform: assess coverage, Places/geocoding/directions quality, billing, caching/display restrictions and privacy.
- OSM-based provider: assess data completeness, tile usage policy, geocoding service limits, commercial SLA and attribution.

Use provider-neutral `MapsProvider`; do not scrape public OSM tile infrastructure for production. Keep approved handover point registry in ShelfShare DB.

## 8. Search and analytics evolution

Start with PostgreSQL full-text search, trigram indexes and locality filters. Consider dedicated search service only when measured relevance, typo tolerance, faceting or load requires it. Start analytics with curated views/materialised views; export pseudonymised events to warehouse when operational queries begin competing with OLTP.

## 9. Decision gates

No vendor is approved until:
- official current docs reviewed;
- written commercial/technical confirmation obtained;
- security/privacy/DPA review completed;
- India eligibility and use case confirmed;
- sandbox POC passes;
- failure/reconciliation tests pass;
- pricing and exit/export strategy documented.


## 10. Official-document capability check (reviewed 30 October 2026)

This is a documentation-level capability check, not a provider approval, sandbox test or commercial commitment.

### Supabase
- Supabase Auth documents a **Send SMS Auth Hook** that allows a custom SMS provider, so the architecture can retain Supabase Auth while routing OTP delivery through an India DLT-capable adapter. Confirm hook signing, plan availability and operational behavior in the actual project. [Auth Hooks](https://supabase.com/docs/guides/auth/auth-hooks)
- Hosted Edge Functions are suitable for short API commands and webhook ingress, but current documented limits include 256 MB memory, 2 seconds CPU time per request and wall-clock limits of 150 seconds on Free / 400 seconds on paid plans. Long-running reconciliation, media processing and durable retry workloads should use a separate worker/queue rather than depend on Edge Function execution. [Edge Function limits](https://supabase.com/docs/guides/functions/limits)
- Supabase Storage documents RLS-based access policies, signed time-limited URLs for private buckets and image transformation. Signed URLs cannot be individually revoked before expiry, so keep expiry short for identity/dispute evidence and use object/key rotation or deletion for emergency invalidation. [Storage access control](https://supabase.com/docs/guides/storage/security/access-control) · [Serving assets](https://supabase.com/docs/guides/storage/serving/downloads) · [Storage overview](https://supabase.com/docs/guides/storage)
- Supabase Realtime supports Broadcast, Presence and Postgres Changes. Supabase's database-change guidance recommends Broadcast for scalability/security over simpler Postgres Changes for production subscriptions. Use Broadcast for chat/live events and persist messages in PostgreSQL; do not treat transient broadcast delivery as durable state. [Realtime](https://supabase.com/docs/guides/realtime) · [Subscribing to database changes](https://supabase.com/docs/guides/realtime/subscribing-to-database-changes)

**Decision:** Supabase remains a suitable initial platform with a separate worker for long-running/retryable work and explicit testing of region, quotas, storage recovery and RLS.

### Razorpay Route
Official Route material describes Linked Accounts, splitting customer payments across third parties, transfers, deferred/custom-delay settlement, reversals, refunds and settlement/reconciliation reporting. The current Route documentation also states that access is subject to eligibility/compliance requirements and asks the business to submit written confirmation describing the use case; its linked-account documentation describes refund capabilities. This is a meaningful functional match for a marketplace payout workflow, but does **not** establish ShelfShare eligibility, deposit custody or that the exact proposed rental flow is approved. Obtain written underwriting and product approval before selection. [About Route](https://tfs.np.razorpay.in/docs/payments/route) · [Linked Accounts](https://tfs.np.razorpay.in/docs/payments/route/linked-account) · [Route Dashboard / eligibility](https://tfs.np.razorpay.in/docs/payments/route/dashboard)

### Cashfree Easy Split
Official Easy Split documentation describes vendor management, static split and split-after-payment APIs, on-demand transfers, refunds, vendor settlement details and reconciliation APIs. Cashfree's product description says Easy Split is integrated with Cashfree Payment Gateway and supports commission deduction and vendor settlement. This is also a functional match for marketplace splitting, but current onboarding eligibility, hold/delay rules, refunds/reversals, owner KYC and ShelfShare's exact business category need written confirmation. It is not evidence of a legally valid deposit escrow. [Easy Split API overview](https://www.cashfree.com/docs/api-reference/payments/latest/split/easy-split-overview) · [Easy Split product overview](https://www.cashfree.com/easy-split/split-payment-gateway/)

**Payment decision:** Keep both Route and Easy Split as RFP candidates. Do not select based on feature pages alone. Compare contractual eligibility, owner onboarding, settlement timing, refunds, chargebacks, reconciliation, fees and legal deposit treatment in a sandbox and written provider review.

### MSG91
MSG91's current documentation provides SendOTP, VerifyOTP, ResendOTP and analytics/log endpoints. Its India DLT help material describes use of DLT Template IDs and variable format. This supports an OTP delivery candidate evaluation, but ShelfShare must verify its own Principal Entity/telemarketer/template/sender registrations, exact OTP template approvals, operator delivery and integration with Supabase's Send SMS Hook. [MSG91 OTP API](https://docs.msg91.com/otp) · [SendOTP endpoint](https://docs.msg91.com/otp/sendotp) · [DLT debugging checklist](https://msg91.com/help/dlt-registration-in-india/dlt-debugging-checklist)

**SMS decision:** MSG91 is a concrete first candidate for a sandbox test; it is not selected until DLT registration and delivery tests pass. Keep a second provider adapter possible for resilience.

### MapLibre
MapLibre GL JS is a TypeScript/WebGL browser renderer for vector tiles and style documents. It is not itself a geocoder, tile hosting service, POI database or routing API. Keep it as the rendering library and separately procure/validate map data services. [MapLibre GL JS introduction](https://maplibre.org/maplibre-gl-js/docs/)

**Maps decision:** MapLibre is suitable as the client renderer. No geocoding/tile provider is selected. Mappls, Google Maps Platform and a commercial OSM-derived service require a separate India locality/POI quality, licensing, privacy, quota and cost test.

### Not yet verified
The official-document review above does not establish the capabilities of any identity/KYC vendor, Mappls, Google Maps billing/terms for this use case, hosting provider, email/push provider or monitoring vendor. Those remain procurement work items; no claims of provider support are made for them.

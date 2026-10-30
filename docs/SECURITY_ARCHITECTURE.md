# Security Architecture — ShelfShare

## 1. Security objectives

Protect user identity, physical safety, money movement, book inventory, private communications and dispute evidence. Prevent IDOR, privilege escalation, double booking, webhook spoofing, QR replay, financial duplication, data leakage and abusive marketplace behaviour.

## 2. Trust boundaries

1. Public browser/mobile client — untrusted.
2. CDN/WAF and application API — authenticated ingress; still validate every command.
3. Edge Functions/service runtime — trusted only with least-privilege service identity.
4. PostgreSQL — authoritative transactional boundary with RLS, constraints and audit.
5. Private object storage — separate access boundary for identity/evidence.
6. Payment/SMS/KYC/maps providers — external processors; never implicitly trusted.
7. Admin console — privileged client; all actions re-authorised server-side.
8. Analytics/monitoring — restricted secondary systems; no unnecessary sensitive PII.

## 3. Identity and access

- Mobile OTP authentication; no email OTP.
- OTP TTL, one-time use, attempt limits, resend cooldown, IP/phone/device throttles and anti-enumeration responses.
- Session rotation/revocation and mobile number re-verification.
- Identity approval is a distinct manual process; OTP does not mean KYC approved.
- Admin accounts provisioned separately with least privilege and stronger authentication/MFA where supported.
- Use permission-scoped roles and maker-checker for financial/configuration changes.
- Break-glass access time-limited, justified and audited.
- Account suspension must preserve active rental, refund and financial obligations.

## 4. Authorization and RLS

- Enable RLS on every client-exposed table; default deny.
- Every Edge Function verifies authenticated subject and role/relationship.
- Never rely on frontend route guards.
- Private identity files are not directly readable by users/admins without case-scoped authorization.
- Booking data is visible only to participants and specifically authorised operations roles.
- Owners may modify only their own copies/listings; cannot modify booking evidence.
- Readers cannot change price, owner payout or copy status.
- Ledger writes are service-only and append-only.
- Admin role changes and financial actions require separate permissions and audit.

## 5. Payment security

- No payment secrets in frontend.
- Verify provider webhook signature over raw body.
- Deduplicate provider event IDs and merchant references.
- Stable idempotency keys for payment/refund/payout.
- Compare provider amount/currency/reference to expected obligation.
- Reconcile daily; unmatched amounts alert finance.
- No client-supplied amount or status is authoritative.
- Separate rent, deposit, commission, tax, fees, refunds and payout ledger entries.
- No arbitrary direct debit or automatic deposit forfeiture.
- No deposit custody feature until legal/provider approval.
- Store only provider tokens/references needed; no raw card or UPI PIN data.

## 6. Booking and QR safety

- PostgreSQL exclusion constraint prevents overlapping live reservations.
- Atomic reservation and extension transactions.
- Half-open intervals and configured buffers.
- QR contains opaque, random, short-lived one-time token; database stores token hash.
- Bind token to booking, action, venue, expiry and intended participant.
- Owner and Reader confirmations must be from distinct authenticated accounts.
- Token is consumed atomically; replay rejected.
- OTP fallback produces an audited independent confirmation.
- Do not expose home addresses; only approved public venue records.
- Device/IP signals are risk inputs, not unreviewable proof.

## 7. Identity and evidence protection

- Private object buckets; short-lived signed URLs.
- Encrypt in transit and at rest; validate storage provider's encryption/key controls.
- Malware scan and file type/magic-byte validation.
- Strip EXIF from public listing images; preserve evidence originals securely.
- Log every sensitive evidence access.
- Minimise KYC provider payload; purpose/consent recorded.
- Retention and deletion schedule approved by counsel; backups and legal holds considered.
- Public avatar and private identity evidence are separate assets.

## 8. Application security

- Zod/schema validation at client and server; server is authoritative.
- Parameterised SQL; no string-built SQL.
- CSP, HSTS, secure cookies/session handling, strict CORS and CSRF controls where applicable.
- XSS-safe rendering and sanitisation for user-generated content.
- SSRF protections for metadata/URL import integrations.
- File upload limits and content scanning.
- Dependency pinning, lockfile, SCA, SAST and secret scanning.
- Rate limits for login, booking, chat, reports, uploads and referral endpoints.
- Protect admin APIs from IDOR and mass assignment.
- Error responses must not reveal private records or provider secrets.

## 9. Privacy and analytics

- Separate public profile, private identity and operational evidence.
- Avoid precise home location collection; locality is sufficient for discovery.
- Do not send identity document numbers, phone numbers or exact venue/route data to analytics.
- Pseudonymise identifiers; restrict exports and retention.
- User access/deletion requests handled through documented workflow, subject to legal retention.
- Review DPDP obligations and phased commencement with counsel; do not claim compliance by implementation alone.

## 10. Threat model and controls

| Threat | Control |
|---|---|
| Double booking race | GiST exclusion constraint + atomic transaction |
| Forged payment webhook | Signature verification, event dedupe, provider reconciliation |
| Duplicate payout/refund | Idempotency, unique merchant reference, status query before retry |
| QR screenshot replay | One-time short-lived token, participant binding, atomic consume |
| Owner/Reader collusion or impersonation | Distinct account confirmations, evidence, anomaly review |
| IDOR | RLS + server relationship checks + object-level authorization |
| Admin privilege escalation | Separate provisioning, least privilege, maker-checker, audit |
| Identity document leakage | Private storage, scoped signed URLs, access logs |
| OTP bombing/SMS pumping | Rate limits, velocity controls, provider fraud tools |
| Fake damage claim | Baseline/return evidence, counter-evidence, independent review |
| Account suspension abuse | Reason, review, appeal, active obligations preserved |
| Supply/listing fraud | Manual moderation, ownership declaration, reporting and review |

## 11. Security operations

- Security incident runbook and contact tree.
- Key rotation and provider credential revocation.
- Backup restore and forensic preservation.
- Vulnerability disclosure/contact channel.
- Periodic access review and admin recertification.
- Penetration test before public launch and after material payment/auth changes.
- RLS policy tests and authorization regression suite.

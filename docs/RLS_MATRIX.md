# ShelfShare — Row-Level Security Matrix

**Default:** RLS enabled on every application table. No broad `authenticated` write policy is used for privileged or financial tables. Supabase `service_role` bypasses RLS and must remain backend-only.

Legend: **R** read, **C** create, **U** update, **D** delete, **—** no client access. “Participant” means an authenticated booking/conversation participant. Admin access is role-specific and should be granted through backend APIs with audit logging, not blanket direct table access.

| Table group | Anonymous | Authenticated owner/user | Booking participant | Support/moderator | Verification reviewer | Finance operator | Admin/service |
|---|---:|---:|---:|---:|---:|---:|---:|
| Published cities/localities | R | R | R | R | R | R | CRUD |
| Active public handover locations | R | R | R | R | R | R | CRUD |
| Profiles | Public-safe projection only | R public-safe; U own allowlisted fields | R participant-safe | R minimum | R minimum | — | audited |
| User roles | — | — | — | — | — | — | service-only |
| User verification aggregate | — | R own status only | — | — | R/U via backend | — | service-only |
| Identity documents and verification audit | — | — | — | — | restricted backend only | — | service-only |
| Book titles/categories | R published | R | R | R | R | R | CRUD |
| Book copies/listings | R approved/active | C/U own draft and listing fields | R relevant listing | R | — | — | audited |
| Images/condition evidence | public listing images only | own listing images | evidence for own rental only | restricted | — | — | service-only |
| Book pricing | R active price | R; U own draft price within limits | R snapshot | R | — | R | audited |
| Wishlists | — | R/C/U/D own | — | — | — | — | service-only |
| Recommendations | — | R own | — | — | — | — | service-only |
| Bookings/rental items/reservations | — | R reader/owner scoped; C via RPC | R | support API only | — | R minimum | service-only |
| Agreements/handover | — | R own booking docs/events | R | restricted | — | — | service-only |
| Payments/payment events/refunds | — | R own redacted status | — | support API redacted | — | R/U via finance backend | service-only |
| Deposits/deposit ledger/release | — | R own redacted status | — | — | — | restricted | service-only |
| Commission/earnings/payouts/journal | — | R owner earnings/payout summary only | — | — | — | restricted backend | service-only |
| Disputes/evidence | — | R own dispute; submit evidence via RPC | R relevant case | assigned case only | — | relevant financial case | service-only |
| Chat | — | — | R/C messages; no participant edits | moderation workflow | — | — | service-only |
| Reports/blocks | — | C own report/block; R own blocks | — | assigned report | — | — | service-only |
| Reviews | R published | C eligible review; R published | R relevant review | moderation | — | — | service-only |
| Referrals/rewards | — | R own; referral create via RPC | — | — | — | reward ledger restricted | service-only |
| Community content | R published | R; C/U/D own content | — | moderation | — | — | service-only |
| Exchanges | — | R own; C request | R accepted exchange | support case only | — | — | service-only |
| Notifications | — | R own; mark read via RPC | — | — | — | — | service-only |
| Grievances/privacy requests | — | C/R own; append message via RPC | — | assigned ticket | — | assigned finance ticket | service-only |
| Legal documents/acceptances | R current public docs | R docs; C acceptance via RPC | R accepted version | — | — | — | service-only |
| Admin audit/risk alerts/config | — | — | — | scoped via backend | scoped via backend | scoped via backend | service-only |
| Analytics | — | — | — | aggregate-only | — | finance aggregates | service-only |

## Security implementation notes

- The migrations intentionally enable RLS but avoid granting direct table access for many high-risk writes. The backend uses narrowly scoped RPCs and service-role operations.
- Never ship `service_role`, `postgres` credentials or provider secrets to clients.
- `profiles` does not expose identity numbers, phone auth metadata, verification evidence keys or internal risk scores.
- The `is_staff()` helper reads `user_roles` in a fixed-search-path `SECURITY DEFINER` function. Users cannot grant themselves a role.
- Supabase Storage policies must be tested separately. The migration creates private buckets for identity, rental evidence and support. No public read policy exists for them.
- If admin UI uses direct PostgREST reads, add explicit role- and case-scoped SELECT policies after the admin role model and audit workflow are approved. Do not use a blanket `is_admin()` policy for every sensitive table.
- RLS is not a substitute for field-level API response shaping. Use backend DTOs that omit sensitive columns.

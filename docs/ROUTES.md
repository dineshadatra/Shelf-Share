# ShelfShare Frontend Routes

**Status:** Frontend route map / implementation preview  
**Router:** React Router  
**Route source:** `src/App.tsx`

## 1. Route inventory

| Route | Page | Layout | Intended access | Current implementation |
|---|---|---|---|---|
| `/` | Home | Public | Public | Editorial landing; search navigates to Discover |
| `/discover` | Discover Books | Public | Public | Sample catalogue; title/author/category/city filters and sorting |
| `/books/:id` | Book Details | Public | Public | Sample detail page; unknown ID currently falls back to first sample record |
| `/login` | Login | Auth | Public | Phone form; OTP service not connected |
| `/register` | Registration | Auth | Public | Mobile-first registration preview; no account created |
| `/verification` | Verification | Member | Signed-in user in intended product | Manual-review explainer; no upload/review workflow |
| `/reader` | Reader Dashboard | Member | Eligible Reader in intended product | Visual preview, no account data |
| `/owner` | Owner Dashboard | Owner workspace | Eligible Owner in intended product | Visual preview, no listings/bookings/payouts |
| `/owner/list-book` | List a Book | Owner workspace | Verified Owner in intended product | Form layout; listing disabled |
| `/wishlist` | Wishlist | Member | Signed-in user in intended product | Empty state; no saved-list persistence |
| `/rentals` | Rental History | Member | Booking participant in intended product | Active/upcoming/past tabs with empty states |
| `/community` | Community | Public | Public read; authenticated write in intended product | Editorial sample posts; social actions unavailable |
| `/chat` | Chat | Member | Booking participants in intended product | Empty state; no message transport |
| `/notifications` | Notifications | Member | Signed-in user in intended product | Empty state; no delivery channel |
| `/profile` | Profile | Member | Signed-in user in intended product | Profile preview; cannot save changes |
| `/admin/login` | Admin Login | Auth | Separately provisioned Admin | Form only; no authentication |
| `/admin` | Admin Dashboard | Admin | Authorised Admin only in intended product | Unprotected design preview; no live data |

Unknown paths resolve to the Not Found page.

## 2. Access model required before production

Route rendering is not authorization. This frontend has no connected authentication provider or server-side role data yet. Before production:
1. Add a session-aware auth provider and route loaders/guards for signed-in routes.
2. Resolve eligibility from trusted backend data, never client-editable state.
3. Enforce Reader/Owner verification at server commands, including list/book/booking/payment actions.
4. Keep Admin accounts separately provisioned and protect each Admin API with least-privilege RBAC, MFA, audit and maker-checker requirements.
5. Keep service-role keys and provider secrets out of browser bundles.
6. Use RLS and backend object-level checks for every record; route guards are UX only.

## 3. Navigation map

- Public: Home → Discover → Book Details → Login/Register.
- Reader: Overview, Discover, Wishlist, Rental History, Chat, Notifications, Profile and Verification.
- Owner: Overview, List a Book, Rental Activity, Chat, Profile and Verification.
- Admin: Admin Login → Admin Dashboard (visual route only; not currently gated).

## 4. Route-to-service dependencies

| Capability | Routes | Backend dependency |
|---|---|---|
| OTP authentication | Login, Registration | Supabase Auth phone OTP + approved India SMS provider |
| Profile photo capture | Registration | Browser camera capture, consent, private image storage and abuse review |
| Identity verification | Verification, Reader/Owner, List Book | Private storage, case API, reviewer workflow, audit and status resolution |
| Catalogue and inventory | Discover, Book Details, List Book | Catalogue search, locality filtering, copy moderation, availability and pricing APIs |
| Booking and rentals | Book Details, Reader, Owner, Rental History | Atomic booking RPC, payment orchestration, collection/return workflows |
| Money | Owner, Rental History, Admin | Provider adapter, signed webhook inbox, append-only ledger, refunds and payouts |
| Trust and safety | Community, Chat, Admin | Report/block/moderation/dispute APIs and audited Admin permissions |
| Notifications | Notifications and transactional journeys | Preferences, outbox and approved SMS/email/push adapters |

## 5. Non-functional route requirements

- Every route must handle loading, empty, error, unauthorized and unavailable states.
- Preserve query string on Discover for search intent.
- Use deep-link-safe SPA hosting fallback to `index.html`.
- Add page metadata, canonical URLs and structured metadata to public book pages when real catalogue data exists.
- Admin routes must not be deployed until backend authorization and operations review pass.

# ShelfShare Frontend Routes

**Status:** Implemented frontend flows backed by Supabase RPCs and Edge Functions; runtime deployment remains environment-dependent.  
**Router:** React Router  
**Route source:** `src/App.tsx`

## 1. Route inventory

| Route | Page | Layout | Access | Current implementation |
|---|---|---|---|---|
| `/` | Home | Public | Public | Landing page with search entry points. |
| `/discover` | Discover Books | Public | Public | Live approved-copy search, filters, sorting, pagination, locality map, opt-in distance search, weekend availability, rule-based recommendations and bundles. |
| `/books/:id` | Book Details | Public | Public | Live approved physical-copy detail, approved photographs, condition/damage disclosures, rental rates and advisory date availability check; waitlist and wishlist actions require sign-in. |
| `/login` | Login | Auth | Public | Supabase mobile-number SMS OTP login. |
| `/register` | Registration | Auth | Public | Phone OTP, adult eligibility, first-time camera photo and versioned legal acceptance; account completion remains blocked until an approved active terms/privacy version is configured. |
| `/verification` | Verification | Member | Signed-in user | Private identity evidence submission and manual-review status workflow. |
| `/reader` | Reader Dashboard | Member | Signed-in user | Reader workspace preview; booking workflows are separate. |
| `/owner` | Owner Dashboard | Owner workspace | Signed-in user | Live physical-copy listings, moderation decisions, availability blocks and owner-created bundles. Listing actions require active verified and age-eligible status. |
| `/owner/list-book` | List a Book | Owner workspace | Signed-in user; server requires verified, age-eligible owner for save/submit | Draft/edit form, ISBN metadata lookup with manual fallback, copy photos, condition/damage, price evidence, rental rates, locality and owner declaration. |
| `/wishlist` | Wishlist | Member | Signed-in user | Persistent saved editions, city waitlists and in-app availability notices. |
| `/rentals` | Rental History | Member | Signed-in user | Rental workspace; booking and payment workflows are separate. |
| `/community` | Community | Member | Signed-in user | Community UI; some social actions remain preview-only. |
| `/chat` | Chat | Member | Signed-in user | Chat UI; message transport is not part of the catalogue feature. |
| `/notifications` | Notifications | Member | Signed-in user | Notification workspace; external SMS/email/push delivery is not implemented by the catalogue waitlist workflow. |
| `/profile` | Profile | Member | Signed-in user | Profile view and verified phone-change flow. |
| `/admin/login` | Admin Login | Auth | Public entry; access still depends on provisioned staff role | Uses the same phone/SMS OTP authentication, not a separate email login. |
| `/admin` | Admin Dashboard | Admin | Server-checked staff role | Admin workspace. |
| `/admin/verifications` | Identity Review Queue | Admin | Server-checked verification reviewer/admin role | Separate identity-review API and private document preview controls. |
| `/admin/listings` | Listing Moderation Queue | Admin | Server-checked marketplace moderator/admin role | Copy photo/evidence preview, audit history and approve/reject/suspend/remove actions. |
| `/admin/bundles` | Bundle Moderation Queue | Admin | Server-checked marketplace moderator/admin role | Separate bundle approval/rejection/suspension/removal flow. |

Unknown paths resolve to the Not Found page.

## 2. Authorization and privacy boundaries

Route guards are user-experience controls, not the final security boundary. The catalogue and identity workflows also enforce permissions in Supabase RPCs, Row Level Security and Edge Functions.

- Listing save and submit operations require an authenticated owner with an active account, verified identity and server-computed age eligibility. The owner must explicitly declare lawful ownership or authority to rent; ISBN metadata and purchase-price evidence are not ownership proof.
- A catalogue edition (`book_titles`) is separate from each physical copy (`book_copies`). Multiple copies may share one edition but have separate owner, condition, photographs, price, availability and moderation state.
- Public search and book details expose only approved, available copies and approved catalogue metadata. Requested deposits and original purchase-price amounts are not exposed in public discovery.
- Copy photographs and original-price evidence are stored in private buckets. Moderator previews are generated through the Edge Function using short-lived signed URLs after an access-audit write succeeds. Internal reviewer notes are not returned to owners.
- Listing and bundle reviewers cannot decide their own submissions. Moderator access does not grant identity-document access; the identity-review workflow has separate roles and APIs.
- Location permission is requested only after a user chooses the location action. Browsing by city and locality works without location permission. Map markers use operations-maintained locality-centre coordinates, not owner/home GPS or exact handover points.
- Availability checks are advisory. Booking must repeat conflict checks atomically before creating a reservation or hold.

## 3. Catalogue and listing services

| Capability | Routes | Backend dependency |
|---|---|---|
| ISBN metadata autofill | List a Book | `catalogue-api` `isbn_lookup` action, Open Library Books API, checksum validation and 30-day metadata cache; manual entry remains available. |
| Listing drafts and edits | Owner, List a Book | `save_book_listing`, owner-scoped listing RPCs and private copy-photo storage. |
| Listing submission | List a Book | `submit_book_listing`; requires a versioned owner declaration and at least two actual copy photographs. |
| Listing moderation | Admin Listings | `catalogue-api` staff authorization and `review_book_listing`; moderation events are audited. |
| Discovery | Discover | `catalogue-api` `discover` action backed by `search_book_listings`; server-bounded pagination and filters. |
| Detail and images | Book Details | `catalogue-api` `listing_detail`; only approved images are signed for public display. |
| Availability | Discover, Book Details, Owner | Availability RPCs/API plus owner block and active reservation overlap checks. |
| Wishlist and waitlist | Book Details, Wishlist | Authenticated wishlist/waitlist RPCs and in-app availability notifications. |
| Bundles | Discover, Owner, Admin Bundles | Owner-scoped bundle creation, independent bundle moderation and public approved-bundle query. |

## 4. Deployment requirements and known limits

Apply migrations in order through `202610300019_bundle_approval_validation.sql`, deploy the `catalogue-api` Edge Function, set its `APP_ORIGIN` secret, and verify that both listing-photo and price-evidence storage buckets are private. The Vite client must contain only the Supabase URL and anon key; never expose the service-role key in browser code.

Operations must seed active cities, localities and genres, and maintain approximate locality map coordinates. Marketplace moderator roles must be provisioned through a trusted administrative process. The ISBN provider guard is currently per Edge Function isolate; use a shared rate limiter before high-volume production traffic.

Deposit amounts can be recorded as private draft/review context, but deposit collection and custody remain disabled until separate legal, payment-provider and operational approvals exist. Waitlist notifications are in-app only; they do not send SMS, email or push notifications and do not reserve a copy. Bundles do not yet have aggregate bundle pricing or atomic multi-copy checkout. Listing moderation has role checks and an audit trail but does not yet implement reviewer assignment or maker-checker separation.

The repository's security tests and CI workflow cover static regression checks, type/build and lint. A successful CI run does not apply database migrations, deploy Edge Functions, configure Supabase providers/storage, seed locality data or replace end-to-end testing against a configured Supabase project.

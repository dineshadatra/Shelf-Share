# Book Catalogue, Listings and Discovery

**Implementation branch:** `feat/frontend-foundation`  
**Scope:** book-edition catalogue, owner physical-copy listings, moderation, discovery, wishlist, waitlist, bundles and locality-based map display.

## 1. Data model

ShelfShare deliberately separates the catalogue edition from the physical item offered for rental.

- `book_titles` stores bibliographic metadata: ISBN-13, title, authors, publisher, edition, publication year, language, description, cover reference and catalogue moderation status.
- `book_copies` stores one actual physical copy and its owner, city/locality, condition, listing state and rentable flag.
- `book_images` stores photos belonging to one physical copy. Photos are private in Supabase Storage; the `book-listing-public` bucket name is historical and the bucket is created with `public=false`.
- `book_pricing` stores the active rental price schedule in paise.
- `book_copy_listing_details` stores existing damage, original purchase-price context/evidence reference and the requested deposit amount.
- `book_ownership_declarations` stores the owner's versioned statement that they lawfully own the copy or have authority to rent it.
- `book_listing_moderation_events` and `book_bundle_moderation_events` retain decision history.
- `book_availability_blocks` and `copy_reservations` remain the source of availability conflicts.
- `book_waitlist_entries` and `book_waitlist_notifications` manage title/city waitlists and in-app availability notices.
- `book_bundles` and `book_bundle_items` represent owner-curated multi-copy sets.

Multiple copies of one edition should reuse a `book_titles` row and create a separate `book_copies` row for every lendable physical copy. An ISBN identifies bibliographic metadata; it does not prove possession, ownership or the authority to lend.

## 2. Owner listing lifecycle

An owner must have an active account, completed identity verification and server-computed age eligibility before the listing RPCs accept a new or submitted listing.

1. Owner enters an ISBN-10 or ISBN-13, or enters catalogue metadata manually.
2. Optional ISBN lookup returns Open Library metadata. The user can edit every returned field.
3. Owner describes the physical copy, condition and existing damage, selects a city/locality, enters rental prices and adds actual photos.
4. Owner confirms one of two declarations: lawful owner or authorised to rent, then accepts the statement.
5. The draft is saved by `save_book_listing`. It remains non-discoverable.
6. Owner uploads at least two actual copy photographs and submits through `submit_book_listing`.
7. Listing becomes `pending_review` and is hidden from the public search.
8. A moderator approves, rejects, suspends or removes it. The owner cannot decide their own case.
9. Approval makes it discoverable only while its owner remains active, verified and age eligible. A future verification/account restriction pauses existing listings through the existing verification-loss triggers.
10. An owner can pause an approved listing. Editing a rejected or paused copy returns it to draft; it must be resubmitted and reviewed again.

The server, not the browser, validates owner status, the declaration, required photos, location, active prices and listing state. The browser cannot write moderation status or mark a listing approved.

## 3. Photos and purchase evidence

Actual physical-copy photos are uploaded to the private `book-listing-public` bucket using a path scoped to the authenticated owner and copy. The upload form accepts JPEG, PNG and WebP. The frontend re-encodes images to JPEG, limits the longest edge and drops embedded image metadata before upload. Submission requires two or more non-rejected photos.

Purchase-price evidence is optional and stored in the private `listing-evidence-private` bucket. Its purpose is limited to moderation context; neither a receipt nor the original price is accepted as proof of ownership. Reviewers open photos or price evidence only through the Edge Function, which records an access audit before returning a 60-second signed URL. The public listing/search payload never includes raw Storage object keys.

## 4. Deposit policy

The interface may record a requested deposit amount for internal draft/review context. Database constraint `deposit_feature_enabled = false` prevents enabling deposits through this listing path. No deposit is collected, charged, held, released or represented to a renter as payable. Enabling deposits needs separate approved legal, payment-provider, custody, reconciliation and dispute policies.

## 5. ISBN metadata provider

The selected provider is the Open Library Books API. The frontend validates ISBN-10/ISBN-13 checksums and normalizes ISBN-10 to ISBN-13. It then calls `catalogue-api` action `isbn_lookup`; the Edge Function validates again, checks the private `book_metadata_cache`, calls Open Library on cache miss, and caches a successful response for 30 days. Provider errors and missing records preserve the manual-entry path.

Open Library metadata is a suggestion, not authoritative proof. Owners must review it and manually correct errors. The Edge Function currently has an in-memory per-isolate one-request-per-second guard, not a global distributed quota. Add a shared rate limiter and monitor provider responses before high-volume launch.

Provider references:
- Open Library Books API: https://openlibrary.org/dev/docs/api/books
- Open Library API usage guidance: https://openlibrary.org/developers/api

## 6. Discovery and recommendation

`search_book_listings` is executable by the service role through `catalogue-api`, not directly by anonymous/authenticated clients. It only returns copies whose listing and catalogue edition are approved, whose copy is marked available, and whose city/locality are active.

The server-side filters include free-text title/author/ISBN/publisher/description search, exact author/ISBN, city/locality, genre, language, edition, condition, INR price range, rental duration and requested date range. Paging is bounded. Optional browser geolocation is requested only after the user presses “Use my location”; declining it leaves city/locality search fully available.

Distance and map display use only the operations-maintained locality-centre coordinates. They are not owner/home coordinates, exact meetup locations or live member tracking. Map results link to OpenStreetMap and display locality points only. Locality coordinates are optional; the map explains when they are not configured.

The current “Recommended” sort is a simple deterministic score based on selected city, locality, genre and title matches. It is not machine learning and should not be described as AI personalization. The search Edge Function uses service-role access, so the wishlist-based score in the underlying SQL is not currently personalized to the signed-in reader. That can be added later through a carefully scoped authenticated personalization signal.

The weekend action selects the next Saturday/Sunday window using India time and submits it as an availability filter. Exact availability is checked against owner blocks and active reservations; a result is advisory only and does not create a hold or booking.

## 7. Availability, waitlists and notifications

Owners may add/remove future personal-use or maintenance blocks through owner-scoped RPCs. They cannot delete booking-generated or past blocks through this UI. The availability check is read-only; the booking flow must still repeat all conflict checks atomically when creating a reservation.

A verified reader can join a waitlist for a title in a city and optional locality/date window. When a copy becomes available, the database matcher checks:
- the same catalogue title and city;
- requested locality, when selected;
- requested dates against owner blocks and active reservations;
- that the copy is approved and marked available.

It creates an in-app notification and changes the waitlist entry to `notified`. Triggers run when listings become available, when an eligible waitlist entry is created, when owner blocks are removed, and when active reservations transition to released/expired/cancelled. This implementation does **not** send SMS, email, push notifications or guarantee that an item remains available after a notification; a member must still re-check and book.

## 8. Bundles

An owner may create a bundle of two to five approved, available copies that they own in the same city. New bundles enter `pending_review`. Moderators review/approve/reject/suspend/remove bundles separately from individual copy listings. Bundle decision history is append-only. Public bundle results include only approved bundles and still-approved/available copies.

The current UI supports selecting existing copies and submitting the bundle. It does not yet provide bundle-specific aggregate pricing, discounted bundle checkout or multi-copy atomic reservation; do not advertise those as implemented.

## 9. Roles and access boundaries

- A marketplace `moderator`, `admin` or `super_admin` can review listings and bundles through `catalogue-api`.
- A `verification_reviewer`, `admin` or `super_admin` can access the separate identity-review workflow.
- Marketplace moderator access does not automatically grant access to private identity documents.
- A reviewer cannot preview or decide their own listing/bundle.
- Private image/evidence preview access is audited before creating short-lived signed URLs.
- Search and detail Edge actions only expose approved/available marketplace records.
- The service-role key remains an Edge secret and must never be added to Vite environment variables or frontend source.

## 10. Migration and deployment

Apply database migrations in order, including the prior identity/security migrations and this catalogue sequence:

- `202610300009_catalogue_listings_discovery.sql`
- `202610300010_catalogue_workflows_hardening.sql`
- `202610300011_catalogue_listing_fixes.sql`
- `202610300012_catalogue_moderation_audit_fixes.sql`
- `202610300013_isbn_metadata_cache.sql`
- `202610300014_bundles_and_waitlist_notifications.sql`
- `202610300015_waitlist_reservation_release.sql`
- `202610300016_catalogue_moderation_photo_and_bundle_fixes.sql`
- `202610300017_waitlist_current_availability_check.sql`

Deploy the `catalogue-api` Edge Function and set the `APP_ORIGIN` secret to the deployed ShelfShare frontend origin. Supabase URL, anon key and service-role key are runtime-provided Edge Function secrets; only the URL and anon key belong in Vite's public environment.

Before enabling owners:
- Confirm the `book-listing-public` and `listing-evidence-private` buckets exist and both remain private.
- Confirm the active city/locality catalogue includes the launch markets. Operations must maintain locality map-centre coordinates; do not use user or owner GPS as a substitute.
- Provision marketplace moderator roles through the trusted admin process; do not allow users to self-assign roles.
- Add at least two actual copy images per submitted listing.
- Review Open Library provider behaviour and implement a shared rate limit for production scale.
- Keep deposit collection disabled until it has separate legal/payment approval.
- Review the address/meetup policy and approved public handover-point process before booking launch.

## 11. Validation status and known limits

This change adds Node static security regression tests in `tests/security/catalogue-listing.test.mjs` and relies on the existing frontend CI workflow for security tests, build and lint. The repository changes have not yet been verified by a successful CI run in this work session. Database migrations have not been applied to a Supabase project, Edge Functions have not been deployed, and no end-to-end test against live Supabase has been completed. Treat this as implementation code awaiting migration/runtime validation, not as a production deployment confirmation.

The in-memory ISBN request guard is per Edge Function isolate. Availability search is advisory, not a reservation. Listing and bundle moderation are role-gated but do not yet implement reviewer assignment/maker-checker separation. Locality map centres must be supplied by operations. These limitations should be resolved or explicitly accepted before production launch.

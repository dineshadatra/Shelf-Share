import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = async (path) => readFile(new URL(path, import.meta.url), "utf8");
const listingSql = await read("../../supabase/migrations/202610300009_catalogue_listings_discovery.sql");
const hardeningSql = await read("../../supabase/migrations/202610300010_catalogue_workflows_hardening.sql");
const fixesSql = await read("../../supabase/migrations/202610300011_catalogue_listing_fixes.sql");
const auditSql = await read("../../supabase/migrations/202610300012_catalogue_moderation_audit_fixes.sql");
const cacheSql = await read("../../supabase/migrations/202610300013_isbn_metadata_cache.sql");
const bundleWaitlistSql = await read("../../supabase/migrations/202610300014_bundles_and_waitlist_notifications.sql");
const reservationReleaseSql = await read("../../supabase/migrations/202610300015_waitlist_reservation_release.sql");
const moderationFixSql = await read("../../supabase/migrations/202610300016_catalogue_moderation_photo_and_bundle_fixes.sql");
const currentAvailabilitySql = await read("../../supabase/migrations/202610300017_waitlist_current_availability_check.sql");
const ownerDeclarationSql = await read("../../supabase/migrations/202610300018_backend_owner_declaration_acceptance.sql");
const bundleOwnerUi = await read("../../src/pages/owner-dashboard-page.tsx");
const bundleAdminUi = await read("../../src/pages/admin-bundle-queue-page.tsx");
const api = await read("../../supabase/functions/catalogue-api/index.ts");
const isbn = await read("../../src/lib/catalogue.ts");
const listingUi = await read("../../src/pages/list-book-page.tsx");
const discoveryUi = await read("../../src/pages/discover-page.tsx");
const detailUi = await read("../../src/pages/book-details-page.tsx");
const ownerUi = await read("../../src/pages/owner-dashboard-page.tsx");
const wishlistUi = await read("../../src/pages/wishlist-page.tsx");
const adminUi = await read("../../src/pages/admin-listing-queue-page.tsx");
const guards = await read("../../src/components/auth/protected-route.tsx");

test("catalogue edition and each physical copy are separate records", () => {
  assert.match(listingSql, /public\.book_titles/);
  assert.match(listingSql, /public\.book_copies/);
  assert.match(listingSql, /book_title_id/);
  assert.match(listingSql, /insert into public\.book_copies/);
});

test("ISBN metadata never substitutes for an owner declaration", () => {
  assert.match(listingSql, /book_ownership_declarations/);
  assert.match(listingSql, /lawful_owner/);
  assert.match(listingSql, /authorised_to_rent/);
  assert.match(listingSql, /A lawful ownership\/rental-authority declaration is required/);
  assert.match(listingSql, /Ownership\/rental-authority declaration is required/);
  assert.match(listingUi, /ISBN metadata, purchase price and publisher records identify a book edition or transaction; none is accepted as proof of ownership/);
});

test("listing save and submission enforce active identity verification", () => {
  assert.match(listingSql, /uv\.status = 'verified'/);
  assert.match(listingSql, /uv\.age_eligible is true/);
  assert.match(listingSql, /p\.account_status = 'active'/);
  assert.match(listingSql, /At least two actual photographs/);
  assert.match(auditSql, /moderation_status in \('pending_review','approved'\)/);
  assert.match(listingSql, /listing_status='pending_review'/);
});

test("listing moderation is server-side, role-gated and disallows self-approval", () => {
  assert.match(hardeningSql, /private\.has_role\('moderator'\)/);
  assert.match(hardeningSql, /v_bundle\.owner_id=auth\.uid\(\)/);
  assert.match(listingSql, /A moderator cannot approve or decide their own listing/);
  assert.match(api, /userClient\.rpc\("review_book_listing"/);
  assert.match(api, /Marketplace moderator permission required/);
});

test("public discovery reads only approved and available copies through Edge API", () => {
  assert.match(listingSql, /c\.listing_status='approved' and c\.is_available_for_rent/);
  assert.match(listingSql, /t\.moderation_status='approved'/);
  assert.match(api, /service\.rpc\("search_book_listings"/);
  assert.match(api, /intIn\(payload\.page_size, 12, 1, 24\)/);
});

test("private image and original-price evidence previews are audited before signing", () => {
  assert.match(api, /preview_image/);
  assert.match(api, /book_listing_image_access_audit/);
  assert.match(api, /preview_price_evidence/);
  assert.match(api, /book_listing_evidence_access_audit/);
  assert.match(api, /if \(auditError\) return reply\(500/);
  assert.match(api, /createSignedUrl\(image\.object_key, 60\)/);
  assert.match(api, /createSignedUrl\(objectKey, 60\)/);
  assert.match(auditSql, /reject_append_only_mutation/);
});

test("the browser never receives service role keys or raw evidence storage keys", () => {
  assert.doesNotMatch(listingUi, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.doesNotMatch(discoveryUi, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(api, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(api, /const imageRows = \(images\.data \?\? \[\]\)\.map/);
});

test("ISBN-10 and ISBN-13 checksums are validated with manual fallback", () => {
  assert.match(isbn, /normalizeIsbn/);
  assert.match(isbn, /isbn13CheckDigit/);
  assert.match(isbn, /fetchOpenLibraryMetadata/);
  assert.match(api, /No catalogue record was found/);
  assert.match(listingUi, /Enter the book details manually/);
});

test("actual listing photographs are re-encoded before upload", () => {
  assert.match(isbn, /createImageBitmap/);
  assert.match(isbn, /canvas\.toBlob/);
  assert.match(listingUi, /sanitiseListingPhoto/);
  assert.match(listingUi, /book-listing-public/);
});

test("deposit collection remains disabled", () => {
  assert.match(listingSql, /deposit_feature_enabled boolean not null default false check \(deposit_feature_enabled = false\)/);
  assert.match(listingUi, /Deposit custody, collection and release remain disabled/);
});

test("availability checks compare owner blocks and active reservations", () => {
  assert.match(api, /check_availability/);
  assert.match(api, /book_availability_blocks/);
  assert.match(api, /copy_reservations/);
  assert.match(ownerUi, /create_owner_availability_block/);
  assert.match(ownerUi, /get_my_book_availability_blocks/);
});

test("location access is opt-in and discovery remains searchable by city/locality", () => {
  assert.match(discoveryUi, /navigator\.geolocation\.getCurrentPosition/);
  assert.match(discoveryUi, /Use my location/);
  assert.match(discoveryUi, /Browse by city or locality/);
  assert.match(discoveryUi, /available_from/);
  assert.match(discoveryUi, /radius_km/);
});

test("wishlist and waitlist operations are tied to the authenticated user", () => {
  assert.match(hardeningSql, /toggle_book_wishlist/);
  assert.match(listingSql, /join_book_waitlist/);
  assert.match(listingSql, /leave_book_waitlist/);
  assert.match(wishlistUi, /leave_book_waitlist/);
  assert.match(detailUi, /join_book_waitlist/);
});

test("bundles require same-owner approved copies in one city", () => {
  assert.match(listingSql, /create_book_bundle/);
  assert.match(listingSql, /All bundle copies must be approved listings owned by you in the same city/);
  assert.match(api, /get_public_book_bundles/);
});

test("moderation route and identity-document route use separate role gates", () => {
  assert.match(guards, /moderationOnly/);
  assert.match(guards, /moderator_me/);
  assert.match(guards, /verification-admin/);
});

test("ISBN lookup is user-initiated, backend proxied and cached", () => {
  assert.match(api, /action === "isbn_lookup"/);
  assert.match(api, /book_metadata_cache/);
  assert.match(api, /expires_at/);
  assert.match(api, /30 \* 24 \* 60 \* 60 \* 1000/);
  assert.match(cacheSql, /enable row level security/);
  assert.match(cacheSql, /from public,anon,authenticated/);
  assert.match(isbn, /functions.invoke\("catalogue-api"/);
});

test("listing approval never re-approves previously rejected photos", () => {
  assert.match(moderationFixSql, /moderation_status='pending_review'/);
  assert.match(moderationFixSql, /moderation_status in \('pending_review','approved'\)/);
});

test("public discovery strips original purchase price and requested deposit", () => {
  assert.match(api, /requested_deposit_paise: _depositNotPublic/);
  assert.match(api, /original_price_paise: _purchasePriceNotPublic/);
});

test("waitlists create in-app notices for newly available matching copies", () => {
  assert.match(bundleWaitlistSql, /book_waitlist_notifications/);
  assert.match(bundleWaitlistSql, /queue_waitlist_notifications_for_copy/);
  assert.match(bundleWaitlistSql, /preferred_locality_id/);
  assert.match(bundleWaitlistSql, /reserved_period/);
  assert.match(reservationReleaseSql, /reservation_release_notify_waitlist/);
  assert.match(reservationReleaseSql, /released','expired','cancelled/);
  assert.match(wishlistUi, /mark_book_waitlist_notification_read/);
});

test("bundle creation and moderation are separate from copy approval", () => {
  assert.match(bundleOwnerUi, /create_book_bundle/);
  assert.match(bundleAdminUi, /admin_bundle_queue/);
  assert.match(bundleAdminUi, /moderate_bundle/);
  assert.match(bundleWaitlistSql, /book_bundle_moderation_events/);
});

test("public bundles disappear when one included physical copy is unavailable", () => {
  assert.match(moderationFixSql, /not bc\.is_available_for_rent/);
  assert.match(moderationFixSql, /bc\.listing_status<>'approved'/);
});

test("public book detail is readable before the authenticated Edge API branch", () => {
  assert.ok(api.indexOf('action === "listing_detail"') < api.indexOf("getAuthenticatedUser(req)"));
});

test("ISBN search accepts ISBN-10 by normalizing it before discovery RPC", () => {
  assert.match(discoveryUi, /normalizeIsbn\(isbn\)/);
  assert.match(discoveryUi, /submittedFilters/);
});

test("undated waitlists only receive notices when the copy is free now", () => {
  assert.match(currentAvailabilitySql, /w\.requested_start_at is null/);
  assert.match(currentAvailabilitySql, /blocked_period @> now\(\)/);
  assert.match(currentAvailabilitySql, /reserved_period @> now\(\)/);
});

test("backend refuses listing saves without explicit owner declaration acceptance", () => {
  assert.match(ownerDeclarationSql, /p_declaration_accepted is distinct from true/);
  assert.match(ownerDeclarationSql, /save_book_listing_unchecked_legacy/);
  assert.match(ownerDeclarationSql, /revoke all on function public\.save_book_listing_unchecked_legacy/);
  assert.match(listingUi, /p_declaration_accepted:accepted/);
});

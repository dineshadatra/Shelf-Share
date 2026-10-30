import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL(path, import.meta.url), "utf8");
const [enumMigration, baseFinance, baseBooking, finance, booking, financeEvents, disputes, outbox, api, worker, adapter, bookDetails, rentals, scanner, config] = await Promise.all([
  read("../../supabase/migrations/202610300020_booking_payments_handover.sql"),
  read("../../supabase/migrations/202610300004_finance_ledger.sql"),
  read("../../supabase/migrations/202610300003_booking_handover.sql"),
  read("../../supabase/migrations/202610300021_financial_events_deposit_claims_reconciliation.sql"),
  read("../../supabase/migrations/202610300023_booking_payments_handover_core.sql"),
  read("../../supabase/migrations/202610300024_rental_disputes_and_provider_deposit_holds.sql"),
  read("../../supabase/migrations/202610300026_dispute_resolution_and_claim_hold_release.sql"),
  read("../../supabase/migrations/202610300025_marketplace_outbox_and_return_guard.sql"),
  read("../../supabase/functions/marketplace-api/index.ts"),
  read("../../supabase/functions/marketplace-outbox/index.ts"),
  read("../../supabase/functions/_shared/payment-provider.ts"),
  read("../../src/pages/book-details-page.tsx"),
  read("../../src/pages/rental-history-page.tsx"),
  read("../../src/components/marketplace/qr-code-scanner.tsx"),
  read("../../supabase/config.toml")
]);

const functionBody = (source, name, nextName = "\nrevoke all on function") => {
  const start = source.indexOf("create or replace function " + name);
  assert.ok(start >= 0, "missing SQL function: " + name);
  const end = source.indexOf(nextName, start);
  assert.ok(end > start, "missing end marker for SQL function: " + name);
  return source.slice(start, end);
};

test("the new enum value is isolated before migrations use it", () => {
  assert.match(enumMigration, /^alter type public\.booking_status add value if not exists 'owner_accepted';\s*$/);
  assert.doesNotMatch(enumMigration, /\bbegin;|\bcommit;/i);
  assert.match(booking, /status='owner_accepted'/);
});

test("each new migration has one transaction and balanced dollar delimiters", () => {
  for (const [name, source] of [["021", finance], ["023", booking], ["024", financeEvents], ["025", outbox], ["026", disputes]]) {
    assert.equal((source.match(/^begin;$/gim) ?? []).length, 1, name + " begins once");
    assert.equal((source.match(/^commit;$/gim) ?? []).length, 1, name + " commits once");
    assert.equal((source.match(/\$\$/g) ?? []).length % 2, 0, name + " dollar-quote delimiters are balanced");
    assert.doesNotMatch(source, /^\s*as \$\s*$/m, name + " has no malformed dollar quote");
  }
});

test("booking request inserts request, rental item and copy hold atomically and is idempotent", () => {
  const fn = functionBody(booking, "public.request_book_booking(");
  assert.match(fn, /request_idempotency_key=p_idempotency_key/);
  assert.match(fn, /for update/);
  assert.match(fn, /insert into public.bookings/);
  assert.match(fn, /insert into public.rental_items/);
  assert.match(fn, /insert into public.copy_reservations/);
  assert.match(fn, /v_cfg\.request_hold_seconds/);
  assert.match(fn, /excluded|exclusion_violation/);
});

test("booking eligibility enforces identity, same-city and approved public handover point", () => {
  const fn = functionBody(booking, "private.assert_booking_request_identity(");
  assert.match(fn, /v_reader\.preferred_city_id is distinct from p_copy\.city_id/);
  assert.match(fn, /v\.status='verified'/);
  assert.match(fn, /v\.age_eligible is true/);
  assert.match(fn, /v\.phone_verified_at is not null/);
  assert.match(fn, /h\.status='active' and h\.city_id=p_copy\.city_id/);
});

test("server calculates 10 percent commission on rent only using paise", () => {
  const fn = functionBody(booking, "public.request_book_booking(");
  assert.match(fn, /v_commission:=floor\(v_rent::numeric\*0\.10\+0\.5\)::bigint/);
  assert.match(fn, /commission_rate_bps',1000/);
  assert.doesNotMatch(fn, /commission.*deposit_required_paise/i);
});

test("owner acceptance and both rental agreement acceptances precede payment", () => {
  const accept = functionBody(booking, "public.accept_book_booking_request(");
  const readerAccept = functionBody(booking, "public.accept_booking_agreement(");
  const pay = functionBody(booking, "public.begin_booking_payment(");
  assert.match(accept, /v_booking\.owner_id<>v_actor/);
  assert.match(accept, /rental_agreement/);
  assert.match(readerAccept, /v_booking\.reader_id<>v_actor/);
  assert.match(pay, /Only an Owner-accepted booking can be paid/);
  assert.match(pay, /Both parties must accept the current rental agreement/);
  assert.match(pay, /status in \('created','pending','authorized'\)/);
});

test("provider approval, seller onboarding and CA tax approval gate checkout", () => {
  const pay = functionBody(booking, "public.begin_booking_payment(");
  assert.match(pay, /marketplace_model='peer_to_peer_physical_book_rental'/);
  assert.match(pay, /payment_provider_approvals/);
  assert.match(pay, /provider_vendor_accounts/);
  assert.match(pay, /kyc_status='verified'/);
  assert.match(pay, /tax_calculated_at is null/);
  assert.match(pay, /tax_approval_reference is null/);
  assert.match(adapter, /No provider is registered/);
  assert.match(api, /No approved and deployed adapter is registered/);
});

test("webhook uses raw-body signature validation and verified server-side payment event application", () => {
  assert.match(api, /const rawBody = await req\.text\(\)/);
  assert.match(api, /adapter\.verifyWebhook\(rawBody, req\.headers\)/);
  assert.match(api, /apply_verified_payment_event/);
  assert.doesNotMatch(api, /window\.location.*payment_success/i);
});

test("duplicate payment events are idempotent and amount mismatches are dead-lettered", () => {
  const fn = functionBody(booking, "public.apply_verified_payment_event(");
  assert.match(fn, /unique|on conflict\(provider,provider_event_id\) do nothing/i);
  assert.match(fn, /if v_inserted=0 then return jsonb_build_object\('duplicate',true/);
  assert.match(fn, /amount_or_reference_mismatch/);
  assert.match(fn, /captured_inventory_conflict/);
  assert.match(fn, /refund_after_inventory_conflict/);
});

test("capture confirmation does not use browser state and only accepts provider-captured evidence", () => {
  const fn = functionBody(booking, "public.apply_verified_payment_event(");
  const handover = functionBody(booking, "public.create_handover_session_secure(");
  assert.match(fn, /status='captured'/);
  assert.match(fn, /status='confirmed'/);
  assert.match(handover, /v_booking\.status<>'confirmed'/);
  assert.match(handover, /p\.status='captured'/);
});

test("refund and payout terminal success states require verified provider events", () => {
  const refund = functionBody(finance, "public.apply_verified_refund_event(");
  const payout = functionBody(finance, "public.apply_verified_payout_event(");
  assert.match(refund, /refund\.succeeded/);
  assert.match(payout, /transfer\.succeeded/);
  assert.match(payout, /owner_earnings set status='paid'/);
  assert.match(booking, /settlement_calculated_at is null/);
  assert.match(booking, /provider_vendor_accounts/);
});

test("deposit is a per-booking provider-backed ledger, not an account wallet", () => {
  assert.match(baseFinance, /create table public\.deposits/);
  assert.match(baseFinance, /create table public\.deposit_ledger/);
  assert.match(finance, /create table if not exists public\.deposit_claims/);
  assert.match(finance, /get_my_deposit_positions/);
  assert.match(finance, /feature_enabled_at_creation/);
  assert.match(finance, /Provider-confirmed/);
  assert.match(finance, /public\.deposit_ledger/);
  assert.doesNotMatch(finance, /create table public\.member_wallets|create table public\.wallet_balances/i);
});

test("deposit release is blocked by claim window, active rentals and open disputes", () => {
  const fn = functionBody(finance, "public.request_deposit_release(");
  assert.match(fn, /deposit_claim_window_seconds/);
  assert.match(fn, /completed_at/);
  assert.match(fn, /status<>'closed'/);
  assert.match(fn, /active rental/);
  assert.match(fn, /provider_code=v_deposit\.provider/);
  assert.match(fn, /supports_deposit_release/);
  assert.match(worker, /deposit\.provider_reference/);
  assert.match(disputes, /v_deposit\.status not in \('held_by_provider','partially_applied','claim_hold'\)/);
});

test("deposit deductions require an approved claim and provider event", () => {
  const fn = functionBody(finance, "public.apply_verified_deposit_event(");
  assert.match(fn, /v_claim\.status<>'approved'/);
  assert.match(fn, /decision_amount_paise/);
  assert.match(fn, /deposit\.amount_applied/);
  assert.match(fn, /supports_deposit_application/);
  assert.match(fn, /deposit_ledger/);
});

test("opening a dispute blocks settlement and queues, but does not assert, a provider deposit hold", () => {
  const open = functionBody(financeEvents, "public.open_booking_dispute(");
  const hold = functionBody(financeEvents, "public.apply_verified_deposit_event(");
  assert.match(open, /status='disputed'/);
  assert.match(open, /owner_earnings set status='reconciliation_required'/);
  assert.match(open, /deposit_dispute_hold_requested/);
  assert.match(open, /deposit_ledger/);
  assert.match(hold, /deposit\.dispute_hold/);
  assert.match(hold, /supports_deposit_dispute_hold/);
  assert.match(disputes, /booking_status_before_dispute/);
  assert.match(disputes, /resolve_booking_dispute/);
});

test("QR handover is single-use, expiry-bound, participant-separated and OTP rate limited", () => {
  const create = functionBody(booking, "public.create_handover_session_secure(");
  const verify = functionBody(booking, "public.confirm_handover_qr_or_otp(");
  const complete = functionBody(booking, "private.complete_handover_if_ready(");
  assert.match(create, /qr_token_hash/);
  assert.match(create, /p_expires_at>now\(\)\+interval '15 minutes'/);
  assert.match(verify, /p_actor_id=v_session\.initiator_id/);
  assert.match(verify, /qr_consumed_at is not null/);
  assert.match(verify, /otp_attempts=otp_attempts\+1/);
  assert.match(verify, /interval '15 minutes'/);
  assert.match(complete, /owner_confirmed_at is null/);
  assert.match(complete, /reader_confirmed_at is null/);
  assert.match(complete, /v_owner_photos<1 or v_reader_photos<1/);
});

test("private condition photographs are scoped to the booking participant", () => {
  const photo = functionBody(booking, "public.register_handover_condition_photo(");
  assert.match(baseBooking, /storage_bucket text not null default 'rental-evidence-private'/);
  assert.match(photo, /p_actor_id::text/);
  assert.match(photo, /booking_id::text/);
  assert.match(photo, /handover_session_id/);
  assert.match(api, /rental-evidence-private/);
  assert.doesNotMatch(api, /createPublicUrl/);
});

test("returns are reader-initiated and must complete via two-party handover", () => {
  const fn = functionBody(outbox, "public.request_book_return(");
  assert.match(fn, /v_booking\.reader_id<>v_actor/);
  assert.match(rentals, /invoke\("request_return"/);
  assert.match(rentals, /handover_type:type/);
  assert.match(rentals, /booking.status==="confirmed"\?"collection":"return"/);
  assert.match(rentals, /Upload.*return condition/i);
});

test("provider outbox retries with leases, idempotency and bounded dead-letter behavior", () => {
  assert.match(outbox, /for update skip locked/);
  assert.match(outbox, /dead_letter_at/);
  assert.match(outbox, /v_event\.attempts>=20/);
  assert.match(worker, /claim_marketplace_outbox_events/);
  assert.match(worker, /finish_marketplace_outbox_event/);
  assert.match(worker, /x-marketplace-worker-secret/);
  assert.match(worker, /adapter\.createPaymentIntent/);
  assert.match(worker, /adapter\.createRefund/);
  assert.match(worker, /adapter\.createTransfer/);
  assert.match(worker, /adapter\.holdDepositForDispute/);
});

test("browser booking page submits a request only and never treats availability as a reservation", () => {
  assert.match(bookDetails, /action:"request_booking"/);
  assert.match(bookDetails, /payment_started: false|payment has been started/i);
  assert.match(bookDetails, /approved public handover point/i);
  assert.match(bookDetails, /This check does not reserve the copy/);
});

test("frontend renders local QR and supports camera scanner with OTP fallback", () => {
  assert.match(rentals, /QRCodeSVG/);
  assert.match(scanner, /BrowserQRCodeReader/);
  assert.match(rentals, /Scan participant QR/);
  assert.match(rentals, /OTP fallback/);
  assert.match(rentals, /provider-confirmed payment/);
});

test("marketplace edge endpoints are deployed without gateway JWT enforcement because handlers validate credentials", () => {
  assert.match(config, /\[functions\.marketplace-api\][\s\S]*?verify_jwt = false/);
  assert.match(config, /\[functions\.marketplace-outbox\][\s\S]*?verify_jwt = false/);
});

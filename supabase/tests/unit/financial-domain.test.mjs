import test from "node:test";
import assert from "node:assert/strict";
import {
  calculateCommissionPaise,
  calculateOwnerGrossPaise,
  assertProviderPaymentMatches,
  assertRefundWithinCaptured,
  providerEventForState,
  assertSameCityBooking,
  assertNoShowReporter,
  isDuplicateWebhook,
} from "../../functions/_shared/domain.ts";

test("10 percent commission is calculated only from rent in integer paise", () => {
  const rent = 200_000n;
  const commission = calculateCommissionPaise(rent, 1000);
  assert.equal(commission, 20_000n);
  assert.equal(calculateOwnerGrossPaise(rent, commission), 180_000n);
  // Deposit is intentionally not an input to the commission function.
});

test("commission uses half-up integer rounding", () => {
  assert.equal(calculateCommissionPaise(105n, 1000), 11n);
  assert.equal(calculateCommissionPaise(104n, 1000), 10n);
});

test("provider amount, currency and merchant reference must all match", () => {
  assertProviderPaymentMatches(
    { amountPaise: "200000", currency: "INR", merchantReference: "SS-123" },
    { amountPaise: 200000, currency: "INR", merchantReference: "SS-123" },
  );
  assert.throws(() => assertProviderPaymentMatches(
    { amountPaise: "200000", currency: "INR", merchantReference: "SS-123" },
    { amountPaise: "200001", currency: "INR", merchantReference: "SS-123" },
  ), /amount_mismatch/u);
  assert.throws(() => assertProviderPaymentMatches(
    { amountPaise: "200000", currency: "INR", merchantReference: "SS-123" },
    { amountPaise: "200000", currency: "USD", merchantReference: "SS-123" },
  ), /currency_mismatch/u);
});

test("refund cannot exceed captured less successful or pending refunds", () => {
  assertRefundWithinCaptured(10_000n, 2_000n, 8_000n);
  assert.throws(() => assertRefundWithinCaptured(10_000n, 2_000n, 8_001n), /refund_exceeds/u);
});

test("only final canonical provider states map to financial events", () => {
  assert.equal(providerEventForState("CAPTURED"), "payment.captured");
  assert.equal(providerEventForState("FAILED"), "payment.failed");
  assert.equal(providerEventForState("PENDING"), null);
  assert.equal(providerEventForState("AUTHORIZED"), null);
});

test("cross-city rentals are rejected", () => {
  assertSameCityBooking("hyderabad", "hyderabad");
  assert.throws(() => assertSameCityBooking("hyderabad", "bengaluru"), /cross_city/u);
});

test("owner no-show and reader no-show reports must come from the other party", () => {
  assertNoShowReporter("owner_no_show", "reader-1", "reader-1", "owner-1");
  assertNoShowReporter("reader_no_show", "owner-1", "reader-1", "owner-1");
  assert.throws(() => assertNoShowReporter("owner_no_show", "owner-1", "reader-1", "owner-1"), /other_booking_party/u);
});

test("provider event IDs are detectable as duplicates", () => {
  const seen = new Set(["evt-1"]);
  assert.equal(isDuplicateWebhook("evt-1", seen), true);
  assert.equal(isDuplicateWebhook("evt-2", seen), false);
});

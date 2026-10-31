export type CanonicalPaymentState = "PENDING" | "AUTHORIZED" | "CAPTURED" | "FAILED" | "CANCELLED" | "CHARGEBACK_OPEN";

export function calculateCommissionPaise(rentPaise: bigint, rateBasisPoints = 1000): bigint {
  if (rentPaise <= 0n) throw new Error("rental_amount_must_be_positive");
  if (!Number.isInteger(rateBasisPoints) || rateBasisPoints < 0 || rateBasisPoints > 10_000) {
    throw new Error("invalid_commission_rate");
  }
  return (rentPaise * BigInt(rateBasisPoints) + 5_000n) / 10_000n;
}

export function calculateOwnerGrossPaise(rentPaise: bigint, commissionPaise: bigint): bigint {
  if (rentPaise < 0n || commissionPaise < 0n || commissionPaise > rentPaise) {
    throw new Error("invalid_owner_earnings_calculation");
  }
  return rentPaise - commissionPaise;
}

export function assertProviderPaymentMatches(expected: {
  amountPaise: string | number | bigint;
  currency: string;
  merchantReference: string;
}, actual: {
  amountPaise: string | number | bigint;
  currency: string;
  merchantReference: string;
}): void {
  if (BigInt(expected.amountPaise) !== BigInt(actual.amountPaise)) throw new Error("provider_amount_mismatch");
  if (expected.currency !== actual.currency || expected.currency !== "INR") throw new Error("provider_currency_mismatch");
  if (expected.merchantReference !== actual.merchantReference) throw new Error("provider_merchant_reference_mismatch");
}

export function assertRefundWithinCaptured(capturedPaise: bigint, refundedPaise: bigint, requestedPaise: bigint): void {
  if (capturedPaise < 0n || refundedPaise < 0n || requestedPaise <= 0n || refundedPaise + requestedPaise > capturedPaise) {
    throw new Error("refund_exceeds_unrefunded_capture");
  }
}

export function providerEventForState(state: CanonicalPaymentState): string | null {
  switch (state) {
    case "CAPTURED": return "payment.captured";
    case "FAILED": return "payment.failed";
    case "CANCELLED": return "payment.cancelled";
    case "CHARGEBACK_OPEN": return "chargeback.opened";
    case "PENDING":
    case "AUTHORIZED": return null;
  }
}

export function assertSameCityBooking(readerCityId: string, listingCityId: string): void {
  if (!readerCityId || !listingCityId || readerCityId !== listingCityId) {
    throw new Error("cross_city_rental_not_permitted");
  }
}

export function mayCompleteHandover(input: {
  now: number;
  expiresAt: number;
  tokenConsumed: boolean;
  ownerConfirmed: boolean;
  readerConfirmed: boolean;
  ownerConditionConfirmed: boolean;
  readerConditionConfirmed: boolean;
  ownerPhotoCount: number;
  readerPhotoCount: number;
}): boolean {
  return input.now < input.expiresAt && input.tokenConsumed
    && input.ownerConfirmed && input.readerConfirmed
    && input.ownerConditionConfirmed && input.readerConditionConfirmed
    && input.ownerPhotoCount >= 1 && input.readerPhotoCount >= 1;
}

export function assertNoShowReporter(
  incidentType: "owner_no_show" | "reader_no_show",
  reporterId: string,
  readerId: string,
  ownerId: string,
): void {
  const valid = incidentType === "owner_no_show"
    ? reporterId === readerId
    : reporterId === ownerId;
  if (!valid) throw new Error("only_the_other_booking_party_may_report_this_no_show");
}

export function isDuplicateWebhook(providerEventId: string, seenEventIds: ReadonlySet<string>): boolean {
  if (!providerEventId) throw new Error("provider_event_id_required");
  return seenEventIds.has(providerEventId);
}

export function assertIdempotencyKey(value: string | null | undefined): string {
  if (!value || value.length < 16 || value.length > 128 || !/^[A-Za-z0-9._:-]+$/u.test(value)) {
    throw new Error("valid_idempotency_key_required");
  }
  return value;
}

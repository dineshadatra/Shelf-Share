/**
 * Provider-independent marketplace payment contract.
 *
 * There is intentionally no concrete adapter registered in this repository.
 * A provider must first approve ShelfShare's exact peer-to-peer physical-book
 * rental marketplace, vendor onboarding/split-settlement/refund model and,
 * separately, the deposit custody/release/dispute model in writing.
 */
export type Currency = "INR";

export type ProviderIntentRequest = {
  merchantReference: string;
  idempotencyKey: string;
  amountPaise: number;
  currency: Currency;
  payerReference: string;
  vendorReference: string;
  metadata: Record<string, string>;
  returnUrl: string;
};

export type ProviderIntent = {
  providerOrderReference: string;
  checkoutUrl: string | null;
  status: "created" | "pending";
  expiresAt: string | null;
};

export type ProviderPaymentSnapshot = {
  merchantReference: string;
  providerPaymentReference: string;
  amountPaise: number;
  currency: Currency;
  status: "pending" | "authorized" | "captured" | "failed" | "cancelled" | "disputed";
  occurredAt: string | null;
};

export type ProviderRefundRequest = {
  providerPaymentReference: string;
  merchantReference: string;
  refundReference: string;
  idempotencyKey: string;
  amountPaise: number;
  currency: Currency;
  reasonCode: string;
};

export type ProviderRefundSnapshot = {
  providerRefundReference: string;
  amountPaise: number;
  currency: Currency;
  status: "pending" | "succeeded" | "failed";
};

export type ProviderTransferRequest = {
  vendorReference: string;
  merchantReference: string;
  transferReference: string;
  idempotencyKey: string;
  amountPaise: number;
  currency: Currency;
};

export type ProviderTransferSnapshot = {
  providerTransferReference: string;
  amountPaise: number;
  currency: Currency;
  status: "pending" | "paid" | "failed" | "reversed";
};

export type ProviderDepositHoldRequest = {
  payerReference: string;
  merchantReference: string;
  depositReference: string;
  idempotencyKey: string;
  amountPaise: number;
  currency: Currency;
  custodyDescriptor: string;
  policyVersion: string;
};

export type ProviderDepositSnapshot = {
  providerDepositReference: string;
  amountPaise: number;
  currency: Currency;
  status: "pending" | "held" | "released" | "refunded" | "claim_held" | "partially_applied" | "failed";
};

export type VerifiedProviderEvent = {
  eventId: string;
  eventType: string;
  merchantReference: string | null;
  providerPaymentReference: string | null;
  providerRefundReference: string | null;
  providerTransferReference: string | null;
  providerDepositReference: string | null;
  providerDisputeReference: string | null;
  providerClaimReference?: string | null;
  amountPaise: number;
  currency: Currency;
  occurredAt: string | null;
  payloadSha256: string;
};

export type ProviderReconciliationRecord = {
  recordType: "payment" | "refund" | "payout" | "deposit" | "chargeback" | "settlement";
  internalReference: string | null;
  providerReference: string | null;
  amountPaise: number | null;
  currency: Currency;
  status: string;
  occurredAt: string | null;
};

export interface MarketplacePaymentProvider {
  readonly providerCode: string;
  readonly productCode: string;

  createPaymentIntent(request: ProviderIntentRequest): Promise<ProviderIntent>;
  fetchPayment(merchantReference: string): Promise<ProviderPaymentSnapshot>;

  createRefund(request: ProviderRefundRequest): Promise<ProviderRefundSnapshot>;
  fetchRefund(refundReference: string): Promise<ProviderRefundSnapshot>;

  createTransfer(request: ProviderTransferRequest): Promise<ProviderTransferSnapshot>;
  fetchTransfer(transferReference: string): Promise<ProviderTransferSnapshot>;

  createDepositHold(request: ProviderDepositHoldRequest): Promise<ProviderDepositSnapshot>;
  releaseDeposit(depositReference: string, idempotencyKey: string): Promise<ProviderDepositSnapshot>;
  holdDepositForDispute(depositReference: string, disputeReference: string, idempotencyKey: string): Promise<ProviderDepositSnapshot>;
  applyDepositClaim(depositReference: string, amountPaise: number, claimReference: string, idempotencyKey: string): Promise<ProviderDepositSnapshot>;

  verifyWebhook(rawBody: string, headers: Headers): Promise<VerifiedProviderEvent | null>;
  fetchReconciliation(periodStart: string, periodEnd: string): Promise<ProviderReconciliationRecord[]>;
}

/**
 * No provider is registered until written product-level approval is obtained.
 * Do not infer approval from environment variables or a successful test API call.
 */
const adapters = new Map<string, MarketplacePaymentProvider>();

export function getMarketplacePaymentProvider(providerCode: string): MarketplacePaymentProvider | null {
  return adapters.get(providerCode) ?? null;
}

export function getRegisteredPaymentProviderCodes(): string[] {
  return [...adapters.keys()];
}

/**
 * This registration hook is used by a separately reviewed provider adapter
 * module. It is not exposed to browser clients or runtime configuration.
 */
export function registerMarketplacePaymentProvider(adapter: MarketplacePaymentProvider): void {
  const code = adapter.providerCode.trim().toLowerCase();
  if (!/^[a-z0-9_-]{2,40}$/.test(code)) throw new Error("Invalid payment provider code");
  if (adapters.has(code)) throw new Error("Payment provider adapter is already registered");
  adapters.set(code, adapter);
}

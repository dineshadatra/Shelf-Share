export interface PaymentIntentInput {
  merchantReference: string;
  amountPaise: string;
  currency: "INR";
  idempotencyKey: string;
  customerReference: string;
  metadata: Record<string, string>;
}

export interface PaymentIntentResult {
  providerOrderId: string;
  checkoutUrl: string;
}

export interface NormalizedWebhookEvent {
  providerEventId: string;
  merchantReference: string;
  providerPaymentId: string;
  receivedEventType: string;
  disputeReference?: string;
}

export interface ProviderPaymentSnapshot {
  providerPaymentId: string;
  merchantReference: string;
  amountPaise: string;
  currency: string;
  state: "PENDING" | "AUTHORIZED" | "CAPTURED" | "FAILED" | "CANCELLED" | "CHARGEBACK_OPEN";
  disputeReference?: string;
}

export interface RefundInstruction {
  providerPaymentId: string;
  amountPaise: string;
  merchantRefundReference: string;
  idempotencyKey: string;
  reasonCode: string;
}

export interface RefundResult { providerRefundId: string; status: string }
export interface PayoutInstruction {
  providerVendorReference: string;
  amountPaise: string;
  merchantPayoutReference: string;
  idempotencyKey: string;
}
export interface PayoutResult { providerTransferId: string; status: string }

export interface MarketplacePaymentProvider {
  createPaymentIntent(input: PaymentIntentInput): Promise<PaymentIntentResult>;
  verifyWebhook(rawBody: Uint8Array, headers: Headers): Promise<NormalizedWebhookEvent>;
  fetchPaymentStatus(providerPaymentId: string): Promise<ProviderPaymentSnapshot>;
  createRefund(input: RefundInstruction): Promise<RefundResult>;
  fetchRefundStatus(providerRefundId: string): Promise<{ status: string }>;
  createPayout(input: PayoutInstruction): Promise<PayoutResult>;
  fetchPayoutStatus(providerTransferId: string): Promise<{ status: string }>;
}

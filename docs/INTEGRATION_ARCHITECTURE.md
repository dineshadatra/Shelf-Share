# Integration Architecture — ShelfShare

## 1. Provider adapter principles

All integrations sit behind internal ports/interfaces. Domain modules consume canonical commands/results, never vendor SDK types. Each adapter owns authentication, signatures, mapping, retry classification, idempotency and provider-specific reconciliation.

## 2. Payment provider interface

```ts
export interface MarketplacePaymentProvider {
  createPaymentIntent(input: {
    merchantReference: string;
    amountPaise: number;
    currency: "INR";
    customerRef: string;
    idempotencyKey: string;
    metadata: Record<string, string>;
  }): Promise<PaymentIntentResult>;

  fetchPaymentStatus(providerPaymentId: string): Promise<PaymentStatus>;
  capturePayment?(providerPaymentId: string, amountPaise: number, key: string): Promise<CaptureResult>;
  createRefund(input: {
    providerPaymentId: string;
    amountPaise: number;
    merchantRefundReference: string;
    idempotencyKey: string;
    reasonCode: string;
  }): Promise<RefundResult>;
  fetchRefundStatus(providerRefundId: string): Promise<RefundStatus>;
  onboardOwner(input: OwnerOnboardingInput): Promise<OwnerOnboardingResult>;
  createPayout(input: PayoutInstruction): Promise<PayoutResult>;
  fetchPayoutStatus(providerPayoutId: string): Promise<PayoutStatus>;
  verifyWebhook(rawBody: Uint8Array, headers: Headers): Promise<VerifiedProviderEvent>;
  fetchSettlementReport(range: DateRange): Promise<SettlementReport>;
}
```

The optional capture method exists only for providers whose flow separates authorisation/capture. Provider implementation must not fabricate unsupported operations.

## 3. SMS OTP interface

```ts
export interface SmsOtpProvider {
  sendOtp(input: {
    phoneE164: string;
    templateId: string;
    variables: Record<string, string>;
    idempotencyKey: string;
  }): Promise<{ messageId: string; status: "QUEUED" | "SENT" }>;

  getDeliveryStatus(messageId: string): Promise<DeliveryStatus>;
  verifyWebhook(rawBody: Uint8Array, headers: Headers): Promise<SmsDeliveryEvent>;
  healthCheck(): Promise<boolean>;
}
```

If Supabase Auth owns OTP generation, integrate its supported custom SMS hook/provider contract. If custom OTP is required, use secure random generation, hash at rest, strict TTL, one-time consume, attempt limits and abuse throttling. Do not create two independent OTP authorities.

## 4. Identity verification interface

```ts
export interface IdentityVerificationProvider {
  createSession(input: {
    subjectRef: string;
    purpose: "AGE_AND_IDENTITY_VERIFICATION";
    allowedDocuments: ("PASSPORT" | "PAN" | "DRIVING_LICENCE")[];
    callbackUrl: string;
  }): Promise<{ sessionId: string; hostedUrl?: string }>;

  fetchResult(providerReference: string): Promise<ProviderKycResult>;
  verifyWebhook(rawBody: Uint8Array, headers: Headers): Promise<VerifiedKycEvent>;
  deleteEvidence(providerReference: string): Promise<DeletionResult>;
}
```

Provider signals feed the manual review queue. Provider status cannot directly set the user to `APPROVED`.

## 5. Maps interface

```ts
export interface MapsProvider {
  autocomplete(query: string, cityCode: string): Promise<PlaceSuggestion[]>;
  geocode(placeId: string): Promise<GeocodedPlace>;
  reverseGeocode(lat: number, lng: number): Promise<LocalityResult>;
  getDirections?(from: LatLng, to: LatLng, mode: "walking" | "driving"): Promise<RouteResult>;
  getTileConfiguration(): PublicMapConfiguration;
}
```

Keep map rendering in MapLibre. Only show approved venue coordinates and locality-level public discovery. Never geocode or publish a user's home address for rental discovery.

## 6. Notification interface

```ts
export interface NotificationProvider {
  send(input: {
    recipient: string;
    channel: "SMS" | "EMAIL" | "PUSH";
    templateKey: string;
    locale: string;
    variables: Record<string, string>;
    idempotencyKey: string;
  }): Promise<{ providerMessageId: string; status: string }>;

  fetchStatus(providerMessageId: string): Promise<NotificationDeliveryStatus>;
  verifyWebhook(rawBody: Uint8Array, headers: Headers): Promise<NotificationEvent>;
}
```

In-app notifications are persisted in ShelfShare PostgreSQL and are not delegated to an external provider.

## 7. File storage interface

```ts
export interface FileStorageProvider {
  createUpload(input: {
    objectKey: string;
    bucket: "PUBLIC_LISTING" | "PRIVATE_IDENTITY" | "PRIVATE_EVIDENCE";
    contentType: string;
    maxBytes: number;
    expiresInSeconds: number;
  }): Promise<SignedUpload>;

  createDownload(input: {
    objectKey: string;
    expiresInSeconds: number;
    purpose: string;
  }): Promise<SignedDownload>;

  deleteObject(objectKey: string): Promise<void>;
  getMetadata(objectKey: string): Promise<StoredObjectMetadata>;
}
```

Every upload is finalised by a trusted backend validation step. Private buckets never issue public URLs.

## 8. Integration sequence and reliability

1. Domain command writes intent/outbox record in PostgreSQL.
2. Worker claims outbox record with lease.
3. Adapter calls provider with stable idempotency key.
4. Provider response is stored as integration attempt, not assumed final financial truth.
5. Signed webhook or server status query confirms final state.
6. Inbox deduplicates provider event.
7. Domain transaction applies state transition and ledger posting.
8. Notification outbox event is emitted.
9. Scheduled reconciliation compares provider report to internal journal.

## 9. Webhook security

- HTTPS only.
- Verify signature on exact raw request bytes before JSON transformation.
- Validate timestamp/replay window if provider supports it.
- Store provider event ID with unique constraint.
- Reject invalid signatures and alert.
- Do not trust IP allowlisting alone.
- Apply event only to matching merchant reference, amount, currency and expected aggregate state.
- Handle out-of-order events through canonical provider status fetch.
- Persist redacted event payload/reference; restrict raw payload access.
- Return provider-required acknowledgement only after durable inbox persistence.

## 10. Provider selection checklist

For each provider record:
- legal entity and India eligibility;
- product approval for marketplace model;
- API and webhook version;
- sandbox/live differences;
- rate limits and availability SLA;
- data location/subprocessors;
- encryption and security assurance;
- retention/deletion;
- commercial pricing and taxes;
- support/escalation;
- settlement/refund/reversal semantics;
- export and termination process;
- evidence from sandbox tests and written provider responses.

No provider is selected in this architecture document.

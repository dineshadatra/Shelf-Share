# ShelfShare Edge Functions

These functions are trusted backend command boundaries over the existing SQL RPCs. They use Supabase Auth for user identity and a service-role client only inside server code. Never expose the service-role key to the browser.

## Provider registration

No commercial adapter is registered by default. This is intentional. Implement MarketplacePaymentProvider in a new file under _shared/providers/, add provider-specific signature verification over raw bytes, canonical payment lookup, idempotency, refund/payout and settlement-report calls, then register it in the Edge Function entrypoints that need it. Do not add an adapter until written provider approval covers ShelfShare's exact marketplace model.

create-payment-intent returns a service-unavailable error while no adapter is registered. It does not create an internal payment attempt before the adapter is available. payment-webhook also fails closed when the provider adapter is absent.

## Rental operations

- rental-operations is a JWT-authenticated RPC façade for dashboard, extension, reschedule, early-return, cancellation, no-show, claim, resolution-centre, appeal, safety-report, block, mute and suspension actions. Database RPCs enforce participant/admin permissions.
- case-evidence issues a case-scoped private signed-upload URL and finalises uploaded evidence only after actor, booking, case path, size and file signature validation.
- rental-due-sweep is a scheduler-only endpoint authenticated with x-rental-sweep-secret. It queues in-app due/overdue notifications and optional late-fee proposals. It does not send messages directly or collect/deduct fees.

The rental_operation_policy row is inserted inactive. Late fees require an approver plus legal/accounting reference strings and still remain proposed, not charged. Paid extension requests remain pending until a payment-capable extension workflow is enabled.

## Required secrets

- SUPABASE_URL
- SUPABASE_ANON_KEY
- SUPABASE_SERVICE_ROLE_KEY
- HANDOVER_OTP_HMAC_SECRET (at least 32 bytes)
- RENTAL_SWEEP_SECRET (at least 32 bytes)
- PAYMENT_PROVIDER_CODE (only after provider adapter and approval are in place)
- APP_ORIGIN (production frontend origin)

Set secrets with supabase secrets set; never commit a .env file.

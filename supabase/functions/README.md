# ShelfShare Edge Functions

These functions are trusted backend command boundaries over the existing SQL RPCs. They use Supabase Auth for user identity and a service-role client only inside server code. Never expose the service-role key to the browser.

## Provider registration

No commercial adapter is registered by default. This is intentional. Implement MarketplacePaymentProvider in a new file under _shared/providers/, add provider-specific signature verification over raw bytes, canonical payment lookup, idempotency, refund/payout and settlement-report calls, then register it in the Edge Function entrypoints that need it. Do not add an adapter until written provider approval covers ShelfShare's exact marketplace model.

create-payment-intent returns a service-unavailable error while no adapter is registered. It does not create an internal payment attempt before the adapter is available. payment-webhook also fails closed when the provider adapter is absent.

## Required secrets

- SUPABASE_URL
- SUPABASE_ANON_KEY
- SUPABASE_SERVICE_ROLE_KEY
- HANDOVER_OTP_HMAC_SECRET (at least 32 bytes)
- PAYMENT_PROVIDER_CODE (only after provider adapter and approval are in place)
- APP_ORIGIN (production frontend origin)

Set secrets with supabase secrets set; never commit a .env file.

# Local Development — Booking / Payments / QR

## Requirements

- Git for Windows.
- Node.js 22 or newer (unit tests use Node's built-in test runner and type stripping).
- Supabase CLI for local database and Edge Function testing.
- Deno is recommended for deno fmt, deno lint and deno check.

## Clone the feature branch

```powershell
git clone --branch feature/booking-payment-deposit-qr https://github.com/dineshadatra/Shelf-Share.git
cd Shelf-Share
```

## Run unit tests

```powershell
npm run test:unit
```

## Start local Supabase

```powershell
supabase start
supabase db reset
supabase db lint
```

Copy .env.example to .env.local, then use the local API URL, anon key and service-role key printed by supabase status. Set HANDOVER_OTP_HMAC_SECRET to a random secret of at least 32 bytes. Never use production credentials in local development.

## Serve Edge Functions

```powershell
supabase functions serve --env-file .env.local
```

In a second terminal, invoke an authenticated function using a local Supabase user access token. The payment intent endpoint returns 503 provider_adapter_not_implemented until an approved provider adapter has been written and registered. This is expected and is the safe default.

## Database and function deployment

Review the full diff first. Apply migrations to a disposable database before a shared/staging project:

```powershell
supabase db reset
supabase test db
supabase functions deploy create-payment-intent
supabase functions deploy payment-webhook
supabase functions deploy create-handover-session
supabase functions deploy confirm-handover
supabase functions deploy handover-evidence
supabase functions deploy request-deposit-release
supabase functions deploy request-owner-settlement
supabase functions deploy request-finance-refund
```

Do not deploy secrets or turn on provider approval flags until the provider contract, legal opinion and accounting configuration have been approved.

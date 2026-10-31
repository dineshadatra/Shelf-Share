# ShelfShare — Supabase marketplace backend

ShelfShare is a peer-to-peer physical-book rental marketplace backend built on PostgreSQL and Supabase.

## Repository contents

- docs/ — architecture, product rules, security/privacy, database design, operations and the admin portal guide.
- supabase/migrations/ — ordered PostgreSQL/Supabase migrations.
- supabase/functions/ — trusted Edge Functions for payments, QR handover, private evidence, rental operations and admin operations.
- supabase/tests/unit/ — Node.js tests for core marketplace domains and admin portal safeguards.
- admin/ — separate staff-only static admin console, not part of the public consumer application.

## Local setup

Requirements: Git, Node.js 22.6+, Supabase CLI, and Deno recommended for Edge Function checks.

    git clone --branch feature/booking-payment-deposit-qr https://github.com/dineshadatra/Shelf-Share.git
    cd Shelf-Share
    npm run test:unit
    supabase start
    supabase db reset
    supabase db lint
    supabase test db

See docs/LOCAL_DEVELOPMENT.md and docs/ADMIN_PORTAL.md.

## Admin portal

Host the admin/ directory separately over HTTPS. It signs staff in with phone OTP and calls the JWT-protected admin-portal Edge Function. Permissions are database-enforced. Identity document access requires verification_reviewer plus MFA AAL2. Finance operations are restricted to the finance_operator permission group. Selected high-risk actions use maker-checker approval. General admins cannot open identity documents or read finance tables.

Apply migrations in lexical order to a staging database first. Configure the admin portal CORS origin and the Edge Function secrets. Review docs/ADMIN_PORTAL.md for implementation coverage and release gates.

## Financial safety

No commercial payment adapter is enabled by default. Real payment collection, deposit custody, refunds and payouts remain gated on the exact payment-provider marketplace approval, legal and accounting sign-off, verified webhooks and reconciliation. Never mark a provider transaction successful from a browser redirect or a database-only status.

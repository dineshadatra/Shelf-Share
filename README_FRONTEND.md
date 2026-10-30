# ShelfShare frontend foundation

This folder contains the initial React application foundation on the `feat/frontend-foundation` branch. It is additive: the existing product, architecture, legal and Supabase database files remain in place.

## Local setup

Requirements: Node.js LTS and npm.

```bash
npm install
npm run dev
```

Open the local Vite URL printed in the terminal.

## Validation commands

```bash
npm run build
npm run lint
```

The production build runs TypeScript project checks followed by Vite.

## Main folders

- `src/pages/` — route-level screens.
- `src/layouts/` — public, authentication, member and admin layouts.
- `src/components/ui/` — reusable UI primitives.
- `src/components/books/` — reusable book presentation.
- `src/components/navigation/` — public and workspace navigation.
- `src/styles/` — design tokens and global responsive styles.
- `docs/DESIGN_SYSTEM.md` — visual language, tokens and component inventory.
- `docs/ROUTES.md` — route inventory and backend dependencies.

## Important status

The catalogue data and image URLs are illustrative preview data. Authentication, OTP delivery, profile photo capture, identity-document upload/review, listing submission, booking, payment, deposit, payout, messaging delivery, notifications, community writes and Admin actions are not connected to backend services. The Admin route is not protected and must not be exposed with real data until backend authorization, MFA and audit controls are implemented.

The current PRD and database design remain proposals; this frontend does not approve open product, legal or payment decisions.

# ShelfShare Design System

**Status:** Frontend foundation / visual proposal  
**Brand direction:** Premium, warm, editorial, book-focused, local and trustworthy  
**Implementation:** React + TypeScript + Vite, Tailwind CSS v4, shadcn/ui-compatible local primitives built on Radix UI

## 1. Design principles

1. **Editorial, not promotional.** Book-jacket proportions, expressive serif display typography and quiet layouts replace generic gradients and loud marketing patterns.
2. **Warmth with restraint.** Paper-like off-white surfaces, forest-green accents, muted stone borders and restrained brass details.
3. **Trust through clarity.** Identity, safety, policy and transaction states are explicit. Never imply that an unavailable backend action completed.
4. **Local by design.** City and neighbourhood inform discovery; private home addresses are not exposed.
5. **Mobile first.** Compact navigation, touch-friendly controls, clear forms and responsive grids.
6. **Accessible defaults.** Semantic elements, visible labels, keyboard focus indicators, Radix interaction primitives and reduced-motion handling.

## 2. Design tokens

Source: `src/styles/tokens.css`.

| Token | Value | Use |
|---|---|---|
| `--background` | `#F7F6F1` | Warm paper app background |
| `--card` | `#FFFEFA` | Cards, dialogs and form surfaces |
| `--foreground` | `#202B25` | Primary text |
| `--primary` | `#285641` | Forest-green actions and links |
| `--secondary` | `#E9EEE7` | Quiet green-tinted surfaces |
| `--muted` | `#EEEEE8` | Muted fills |
| `--muted-foreground` | `#727B72` | Secondary text |
| `--accent` | `#E8DFCE` | Warm-paper accent |
| `--accent-strong` | `#B58B55` | Small editorial highlight |
| `--destructive` | `#B84C42` | Destructive/error actions |
| `--border` | `#E5E4DC` | Dividers and outlines |
| `--ring` | `#6C9277` | Keyboard focus ring |
| `--radius` | `12px` | Inputs and compact surfaces |
| `--radius-lg` | `20px` | Large cards and panels |

Keep semantic tokens centralised. Avoid introducing one-off hex values in page components.

## 3. Typography

- **Display:** Playfair Display, 500–700. Page titles, campaign statements and editorial book titles.
- **Body/UI:** DM Sans, 400–700. Paragraphs, labels, navigation, controls and dense data.
- **Brand/UI accent:** Manrope for the compact wordmark and selected UI accents.
- Fonts are currently requested from Google Fonts in `index.html`. Production should review font privacy/performance and consider self-hosting.
- Use responsive `clamp()` for display sizes; body text is generally 12–15px in this compact initial UI. Critical policy text must be enlarged where accessibility testing requires.
- Keep heading line-height around 1.1–1.2 and body copy around 1.6–1.8.

## 4. Spacing, shape and elevation

Use an 8px base rhythm with 4px exceptions: 4, 8, 12, 16, 24, 32, 40, 48, 64 and 80. Inputs are 46px high; desktop actions are at least 42px. Expand touch targets as needed to satisfy accessibility review. Cards use 14–20px corners; fields use 10–12px. Shadows are soft and reserved for hover, menus and layered objects.

## 5. Component inventory

| Component | Source | Behaviour / use |
|---|---|---|
| Button | `src/components/ui/button.tsx` | Primary, secondary, outline, ghost, danger and link; sm/md/lg/icon and full-width |
| Input | `src/components/ui/input.tsx` | Label, hint, error and native input attributes |
| Card | `src/components/ui/card.tsx` | Header, title, description, content and footer |
| Badge | `src/components/ui/badge.tsx` | Neutral, green, amber, rose and blue states |
| Dialog | `src/components/ui/dialog.tsx` | Radix modal, focus handling and escape dismissal |
| Dropdown | `src/components/ui/dropdown-menu.tsx` | Radix keyboard-accessible menu |
| Table | `src/components/ui/table.tsx` | Responsive overflow wrapper and semantic table |
| Tabs | `src/components/ui/tabs.tsx` | Radix tablist, keyboard navigation and panels |
| Toast | `src/components/ui/toast.tsx` | Sonner toast exports; message must reflect actual outcome |
| Skeleton | `src/components/ui/skeleton.tsx` | Loading placeholder; never substitute for an error |
| EmptyState | `src/components/ui/empty-state.tsx` | Icon, title, description and optional action |
| Alert | `src/components/ui/alert.tsx` | Informational, warning and success communication |
| BookCover / BookCard | `src/components/books/` | Consistent book-jacket presentation and metadata |
| BrandMark | `src/components/brand/brand-mark.tsx` | Text-plus-book brand lockup |
| SiteHeader | `src/components/navigation/site-header.tsx` | Public desktop/mobile navigation |
| DashboardSidebar | `src/components/navigation/dashboard-sidebar.tsx` | Reader, Owner and Admin navigation |
| MobileBottomNav | `src/components/navigation/mobile-bottom-nav.tsx` | Compact workspace navigation |

These are local shadcn/ui-compatible primitives, not a claim that every shadcn/ui component has been installed. Radix primitives are used for interactions where keyboard and focus behaviour matter.

## 6. Responsive behaviour

- Desktop: max content width 1160px; four-column book cards at wide widths; persistent workspace sidebar.
- Tablet: two/three-column catalogue; dashboard sidebar collapses; public navigation switches to a mobile menu.
- Mobile: two-column book cards, stacked auth layouts, fixed workspace bottom navigation and single-column multi-step forms.
- Breakpoints: 1050px, 820px and 560px in `src/styles/index.css`.
- Respect safe-area bottom inset and `prefers-reduced-motion`.

## 7. Imagery and catalogue content

Current pages use remote Unsplash images as temporary visual assets and a sample catalogue in `src/lib/mock-data.ts`. These are not production catalogue records, rights-cleared assets or availability claims. Before launch, replace them with approved listing photos and legally usable catalogue cover art. Treat uploaded images as untrusted until validated.

## 8. Form and state design

- Keep visible labels; placeholders are supplementary.
- Use telephone input semantics and numeric keypad hints for mobile sign-in.
- OTP stays unavailable until Supabase Auth and an approved India SMS provider are integrated.
- A live profile photo is a first-registration requirement in product context; camera capture is not implemented in this preview.
- Identity document upload is not implemented; private storage and authorised review must be connected first.
- Use verification statuses only when supplied by trusted backend data.
- Place error text beside its control and preserve input where safe.
- Show loading only while a real asynchronous operation is underway.

## 9. Truthfulness boundaries

This frontend foundation does not implement live authentication/OTP, account creation, camera capture/upload, KYC review, listing creation, reservations, payments, deposits, payouts, message delivery, notifications, moderation or Admin actions. Sample content is visibly identified. Disabled actions remain disabled where activation would imply unsupported functionality.

The Admin routes are design previews and are **not protected**. Do not deploy them with real data until backend authorization, MFA, audited Admin APIs and route access checks are implemented.

## 10. Quality gates

Before release:
- Run typecheck, production build and lint in CI.
- Add Vitest and React Testing Library tests; add Playwright E2E for key journeys.
- Test keyboard-only navigation, screen-reader names, focus visibility, reduced motion and contrast.
- Test all routes, empty/error/loading states, image failures and mobile layouts.
- Replace sample content and remote imagery.
- Integrate real APIs through typed clients and test against a staging environment.

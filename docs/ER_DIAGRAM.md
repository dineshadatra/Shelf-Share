# ShelfShare — Entity Relationship Diagrams

The diagrams show logical relationships. Some one-to-many relationships are omitted from the overview to keep it readable; the migrations define the complete model.

## 1. Identity, geography and inventory

```mermaid
erDiagram
  AUTH_USERS ||--|| PROFILES : has
  AUTH_USERS ||--o{ USER_ROLES : assigned
  PROFILES ||--o| USER_VERIFICATIONS : undergoes
  USER_VERIFICATIONS ||--o{ IDENTITY_DOCUMENTS : includes
  USER_VERIFICATIONS ||--o{ VERIFICATION_AUDIT : history
  CITIES ||--o{ LOCALITIES : contains
  LOCALITIES ||--o{ HANDOVER_LOCATIONS : hosts
  CITIES ||--o{ BOOK_COPIES : contains
  LOCALITIES ||--o{ BOOK_COPIES : locates
  PROFILES ||--o{ BOOK_COPIES : owns
  BOOK_TITLES ||--o{ BOOK_COPIES : instantiated_as
  BOOK_TITLES ||--o{ BOOK_TITLE_CATEGORIES : tagged
  CATEGORIES ||--o{ BOOK_TITLE_CATEGORIES : classifies
  BOOK_COPIES ||--o{ BOOK_IMAGES : pictured
  BOOK_COPIES ||--o{ BOOK_CONDITION_RECORDS : inspected
  BOOK_COPIES ||--o{ BOOK_AVAILABILITY_BLOCKS : blocked
  BOOK_COPIES ||--o{ BOOK_PRICING : priced
```

## 2. Booking, reservations, handover and finance

```mermaid
erDiagram
  PROFILES ||--o{ BOOKINGS : reader
  BOOK_COPIES ||--o{ RENTAL_ITEMS : rented
  BOOKINGS ||--|{ RENTAL_ITEMS : contains
  BOOK_COPIES ||--o{ COPY_RESERVATIONS : reserved
  BOOKINGS ||--o{ COPY_RESERVATIONS : reserves
  BOOKINGS ||--o{ RENTAL_AGREEMENTS : accepts
  BOOKINGS ||--o{ HANDOVER_SESSIONS : handover
  HANDOVER_SESSIONS ||--o{ HANDOVER_EVENTS : records
  BOOKINGS ||--o{ PAYMENTS : charged
  PAYMENTS ||--o{ PAYMENT_EVENTS : observed
  BOOKINGS ||--o| DEPOSITS : deposit
  DEPOSITS ||--o{ DEPOSIT_LEDGER : movements
  DEPOSITS ||--o{ DEPOSIT_RELEASE_REQUESTS : released
  BOOKINGS ||--o{ REFUNDS : refunded
  BOOKINGS ||--o{ COMMISSION_LEDGER : commission
  BOOKINGS ||--o| OWNER_EARNINGS : payable
  OWNER_EARNINGS ||--o{ PAYOUTS : paid
  FINANCIAL_ACCOUNTS ||--o{ JOURNAL_LINES : posts
  JOURNAL_ENTRIES ||--|{ JOURNAL_LINES : contains
```

## 3. Trust, community and operations

```mermaid
erDiagram
  BOOKINGS ||--o{ DISPUTES : contested
  DISPUTES ||--o{ DISPUTE_EVIDENCE : supported
  BOOKINGS ||--o{ CHAT_CONVERSATIONS : contextual
  CHAT_CONVERSATIONS ||--o{ CHAT_PARTICIPANTS : includes
  CHAT_CONVERSATIONS ||--o{ CHAT_MESSAGES : contains
  PROFILES ||--o{ USER_REPORTS : files
  PROFILES ||--o{ USER_BLOCKS : blocks
  RENTAL_ITEMS ||--o{ REVIEWS : reviewed
  PROFILES ||--o{ REFERRALS : refers
  REFERRALS ||--o{ REFERRAL_REWARDS : rewards
  PROFILES ||--o{ COMMUNITY_POSTS : authors
  COMMUNITY_POSTS ||--o{ COMMUNITY_COMMENTS : receives
  PROFILES ||--o{ READING_LISTS : creates
  READING_LISTS ||--o{ READING_LIST_ITEMS : contains
  CHALLENGES ||--o{ CHALLENGE_PARTICIPANTS : includes
  PROFILES ||--o{ BOOK_EXCHANGE_REQUESTS : requests
  BOOK_EXCHANGE_REQUESTS ||--o| EXCHANGE_TRANSACTIONS : accepted_as
  PROFILES ||--o{ NOTIFICATIONS : receives
  PROFILES ||--o{ GRIEVANCE_TICKETS : opens
  PROFILES ||--o{ PRIVACY_REQUESTS : submits
  LEGAL_DOCUMENTS ||--o{ LEGAL_ACCEPTANCES : accepted
  PROFILES ||--o{ ADMIN_AUDIT_LOGS : actor
  PROFILES ||--o{ RISK_ALERTS : subject
```

## 4. Critical booking reservation constraint

```mermaid
flowchart TD
  A[Reader submits booking request] --> B[Backend begins transaction]
  B --> C[Lock and validate copy, users, city and policy]
  C --> D[Insert booking and rental item]
  D --> E[Insert copy reservation with [start,end) range]
  E --> F{Exclusion constraint passes?}
  F -- Yes --> G[Commit and return pending booking]
  F -- No --> H[Rollback; return slot unavailable]
  G --> I[Create payment attempt in separate trusted step]
```

The exclusion constraint on `(copy_id WITH =, reserved_period WITH &&)` is the final guard against concurrent overlapping reservations. Availability reads are never a lock.

## 5. Critical financial journal constraint

```mermaid
flowchart TD
  A[Trusted backend requests posting] --> B[Begin transaction]
  B --> C[Insert journal header]
  C --> D[Insert debit and credit lines]
  D --> E[Deferred balance check at commit]
  E --> F{Sum per currency equals zero?}
  F -- Yes --> G[Commit immutable journal]
  F -- No --> H[Reject transaction]
  G --> I[Update operational projections]
  I --> J[Reconcile to provider report]
```

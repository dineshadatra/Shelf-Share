# Cookie and Similar Technologies Policy — Applicability Review

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Applicability gate
This policy is a draft conditional on a verified cookie/SDK inventory. The web and mobile applications must first inventory cookies, local storage, session storage, SDK identifiers, pixels, analytics tags, embedded media and third-party scripts. Do not publish this policy or claim consent is implemented until the inventory and actual consent manager are verified.

## 2. Technologies and purposes
For each technology record: name/provider, first- or third-party status, purpose, data collected, storage/access duration, domain, destination, whether essential, and how it is disabled. Proposed classes are strictly necessary (authentication, security, load balancing, basket/booking state), preferences, analytics, and advertising/marketing. Do not classify analytics or advertising as essential merely for convenience.

## 3. User choice
Where consent is required, non-essential technologies must remain off until a valid choice is captured. Provide equally accessible accept/reject controls, granular settings, a persistent way to change or withdraw choices, and a record of notice version, categories, timestamp and source. Essential technologies should be described separately. Do not use pre-ticked boxes or dark patterns.

## 4. Third-party technologies
List each provider and link to its privacy notice. Explain that third-party providers may process information under their own terms. Disable unapproved third-party scripts and review changes before deployment.

## 5. Retention and contact
State verified lifetimes and deletion behaviour after the inventory is completed. Contact [PRIVACY CONTACT] for questions.

## Release checklist
Attach a dated cookie/SDK scan for production domains and mobile builds; map technologies to purposes; test consent in a clean browser/device; verify rejection blocks non-essential tags; verify withdrawal stops future reads/writes; document any legal basis other than consent; and obtain counsel approval. If the product does not use non-essential cookies or similar technologies, state that fact accurately and keep a short notice rather than implying a full cookie banner is present.

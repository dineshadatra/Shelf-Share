begin;

-- Seed legal text from version-controlled Markdown. All rows remain unpublished drafts.
insert into public.legal_documents(
 document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
 content_markdown,review_status,requires_acceptance,reacceptance_required
) values (
 'terms_conditions','0.1-draft','Terms and Conditions','docs/legal-drafts/01-terms-and-conditions.md',
 encode(extensions.digest(convert_to($doc$# Terms and Conditions

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Contracting entity and scope
These terms govern access to ShelfShare, a proposed marketplace through which users may list, discover, rent and return books and participate in community features. “ShelfShare”, “we” and “us” mean [FULL LEGAL ENTITY NAME], a [COMPANY TYPE] organised under the laws of India, with registered office at [ADDRESS], CIN/GSTIN [DETAILS]. Do not publish until these details are verified.

## 2. Marketplace role
Counsel must determine and describe whether ShelfShare acts solely as an intermediary/marketplace, an agent, a contracting marketplace operator, or another legal model for each transaction. Identify who owns each book, who supplies the rental, who receives payments, who bears consumer obligations, and the scope of platform agency. Do not state that ShelfShare is “only an intermediary” unless the actual conduct and contracts support that conclusion.

## 3. Eligibility and accounts
Users must provide accurate information, control their account, keep authentication factors secure and promptly report unauthorised access. Age eligibility, minors, guardian consent and identity verification thresholds are [COUNSEL/PRODUCT DECISION]. One person must not create deceptive duplicate accounts or impersonate another person.

## 4. Listings and transactions
Owners must have authority to list each physical copy and accurately describe condition, edition, annotations and defects. A listing is not a booking. A rental is formed only when the platform records the required acceptance and payment/booking state described in the Rental Agreement. Availability, price, service fees, taxes, deposits, collection and return terms must be displayed before confirmation.

## 5. Payments, deposits and fees
Use only the authorised payment flow. Rental charges, refundable security deposits, platform commission, gateway charges, taxes and refunds must be separately disclosed. The platform must not imply that a deposit is revenue. Settlement, payment holds, refund timing and chargeback handling are subject to the applicable provider rules and the transaction terms shown at checkout.

## 6. Prohibited conduct and enforcement
Fraud, theft, non-return, harassment, unlawful content, counterfeit or infringing material, manipulation of reviews, payment circumvention and misuse of identity information are prohibited. Moderation, suspension, appeals and evidence handling must follow published policies and applicable law.

## 7. User content and platform rights
Users retain rights in their content and grant only the limited licence needed to host, display, moderate and operate the service. Copyright notices and counter-notices follow the Content and Copyright Policy and applicable law.

## 8. Disputes, liability and termination
Set out complaint routes, governing law, venue, arbitration (if any), consumer remedies, liability allocation and termination consequences only after counsel resolves the marketplace model and mandatory consumer protections. No clause should waive non-waivable statutory rights.

## 9. Changes and acceptance
Record the exact document version, SHA-256 hash, acceptance context and UTC timestamp for affirmative acceptance. Material changes require renewed acceptance before affected functionality is used. Keep prior versions available for the required record period.

## 10. Notices and contact
Legal notices: [LEGAL EMAIL]. Grievances: [GRIEVANCE OFFICER NAME, DESIGNATION, POSTAL ADDRESS, EMAIL AND PHONE]. Registered office: [ADDRESS].

## Counsel decisions required
Confirm marketplace classification; Consumer Protection (E-Commerce) Rules obligations; intermediary requirements if applicable; payment aggregator/escrow implications; GST invoices; liability and indemnity; dispute resolution; minors; mandatory disclosures; language/localisation; and any state-specific requirements.
$doc$,'UTF8'),'sha256'),'hex'),
 null,null,false,$doc$# Terms and Conditions

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Contracting entity and scope
These terms govern access to ShelfShare, a proposed marketplace through which users may list, discover, rent and return books and participate in community features. “ShelfShare”, “we” and “us” mean [FULL LEGAL ENTITY NAME], a [COMPANY TYPE] organised under the laws of India, with registered office at [ADDRESS], CIN/GSTIN [DETAILS]. Do not publish until these details are verified.

## 2. Marketplace role
Counsel must determine and describe whether ShelfShare acts solely as an intermediary/marketplace, an agent, a contracting marketplace operator, or another legal model for each transaction. Identify who owns each book, who supplies the rental, who receives payments, who bears consumer obligations, and the scope of platform agency. Do not state that ShelfShare is “only an intermediary” unless the actual conduct and contracts support that conclusion.

## 3. Eligibility and accounts
Users must provide accurate information, control their account, keep authentication factors secure and promptly report unauthorised access. Age eligibility, minors, guardian consent and identity verification thresholds are [COUNSEL/PRODUCT DECISION]. One person must not create deceptive duplicate accounts or impersonate another person.

## 4. Listings and transactions
Owners must have authority to list each physical copy and accurately describe condition, edition, annotations and defects. A listing is not a booking. A rental is formed only when the platform records the required acceptance and payment/booking state described in the Rental Agreement. Availability, price, service fees, taxes, deposits, collection and return terms must be displayed before confirmation.

## 5. Payments, deposits and fees
Use only the authorised payment flow. Rental charges, refundable security deposits, platform commission, gateway charges, taxes and refunds must be separately disclosed. The platform must not imply that a deposit is revenue. Settlement, payment holds, refund timing and chargeback handling are subject to the applicable provider rules and the transaction terms shown at checkout.

## 6. Prohibited conduct and enforcement
Fraud, theft, non-return, harassment, unlawful content, counterfeit or infringing material, manipulation of reviews, payment circumvention and misuse of identity information are prohibited. Moderation, suspension, appeals and evidence handling must follow published policies and applicable law.

## 7. User content and platform rights
Users retain rights in their content and grant only the limited licence needed to host, display, moderate and operate the service. Copyright notices and counter-notices follow the Content and Copyright Policy and applicable law.

## 8. Disputes, liability and termination
Set out complaint routes, governing law, venue, arbitration (if any), consumer remedies, liability allocation and termination consequences only after counsel resolves the marketplace model and mandatory consumer protections. No clause should waive non-waivable statutory rights.

## 9. Changes and acceptance
Record the exact document version, SHA-256 hash, acceptance context and UTC timestamp for affirmative acceptance. Material changes require renewed acceptance before affected functionality is used. Keep prior versions available for the required record period.

## 10. Notices and contact
Legal notices: [LEGAL EMAIL]. Grievances: [GRIEVANCE OFFICER NAME, DESIGNATION, POSTAL ADDRESS, EMAIL AND PHONE]. Registered office: [ADDRESS].

## Counsel decisions required
Confirm marketplace classification; Consumer Protection (E-Commerce) Rules obligations; intermediary requirements if applicable; payment aggregator/escrow implications; GST invoices; liability and indemnity; dispute resolution; minors; mandatory disclosures; language/localisation; and any state-specific requirements.
$doc$,'draft',true,true
) on conflict(document_type,version) do nothing;

insert into public.legal_documents(
 document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
 content_markdown,review_status,requires_acceptance,reacceptance_required
) values (
 'privacy_policy','0.1-draft','Privacy Policy','docs/legal-drafts/02-privacy-policy.md',
 encode(extensions.digest(convert_to($doc$# Privacy Policy

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Who is responsible
The proposed data controller/data fiduciary is [FULL LEGAL ENTITY NAME], [REGISTERED ADDRESS], contact [PRIVACY CONTACT]. Roles of payment providers, verification vendors, hosting providers and other processors must be documented in a current vendor register.

## 2. Data categories
Depending on features used, ShelfShare may process account and contact details; authentication and security records; identity-verification status and private identity documents; book listings, ownership and locality information; bookings, payment references, deposits, refunds and payout records; handover evidence; support, grievance and dispute records; community posts, messages and reviews; referral records; device, diagnostic, fraud-prevention and access-log data. Do not collect full payment credentials or government identifiers unless a documented necessity and lawful basis have been approved.

## 3. Purposes and legal basis
For each field and purpose, maintain a data inventory and purpose-to-lawful-basis map. Proposed purposes include account security, verification, matching, rental fulfilment, collection/return coordination, payment processing, customer support, fraud prevention, legal claims, service communications and optional analytics/marketing. Distinguish processing necessary to perform a requested service or comply with law from processing based on consent. Do not bundle optional marketing or analytics consent with essential service access.

## 4. Sharing and processors
Disclose categories of recipients: payment providers, SMS/telecom providers, identity-verification providers, cloud hosting/storage, customer-support providers, analytics vendors and competent authorities where legally required. Name material processors where required. Describe purpose, data categories, locations, safeguards and transfer arrangements. Do not promise that data never leaves India until hosting/vendor regions are verified.

## 5. Retention and deletion
Keep personal data only for an approved, documented purpose and retention period. A deletion request may be delayed or limited where an active rental, payment reconciliation, tax/accounting obligation, safety investigation, dispute, fraud prevention or legal hold requires preservation. Explain what is erased, anonymised or retained and why. Retention periods in the schedule are not approved until counsel and business owners sign them off.

## 6. Rights and requests
Provide routes to request access, correction, erasure/deletion, withdrawal of consent and grievance redressal, subject to applicable law and lawful exceptions. Acknowledge receipt, verify requester identity proportionately, track the case, explain any partial refusal and record completion. [INSERT COUNSEL-APPROVED STATUTORY TIMELINES AND APPEAL ROUTE.]

## 7. Security and incidents
Use least-privilege access, MFA for sensitive data, private storage, short-lived signed URLs, encryption in transit/at rest where supported, audit trails, vendor controls and incident response. Describe breach notification only in the form and time required by the rules in force; do not promise a fixed deadline until counsel confirms it.

## 8. Children and sensitive data
State whether minors are permitted. If services are directed to or knowingly used by children, obtain legal review of parental/guardian consent, age assurance and restrictions on tracking/targeted advertising. Identity documents require a separate notice and minimisation controls.

## 9. Changes and contact
Version, effective date and SHA-256 hash are displayed with this policy. Material changes trigger renewed acceptance or consent where required. Contact [PRIVACY CONTACT] and [GRIEVANCE OFFICER].

## Counsel and product sign-off
Complete a data map, processor contracts, cross-border transfer map, lawful-basis assessment, children's-data assessment, retention schedule, breach playbook, rights timetable and notice translations. Confirm commencement and transitional rules under the DPDP Act and Rules before publication.
$doc$,'UTF8'),'sha256'),'hex'),
 null,null,false,$doc$# Privacy Policy

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Who is responsible
The proposed data controller/data fiduciary is [FULL LEGAL ENTITY NAME], [REGISTERED ADDRESS], contact [PRIVACY CONTACT]. Roles of payment providers, verification vendors, hosting providers and other processors must be documented in a current vendor register.

## 2. Data categories
Depending on features used, ShelfShare may process account and contact details; authentication and security records; identity-verification status and private identity documents; book listings, ownership and locality information; bookings, payment references, deposits, refunds and payout records; handover evidence; support, grievance and dispute records; community posts, messages and reviews; referral records; device, diagnostic, fraud-prevention and access-log data. Do not collect full payment credentials or government identifiers unless a documented necessity and lawful basis have been approved.

## 3. Purposes and legal basis
For each field and purpose, maintain a data inventory and purpose-to-lawful-basis map. Proposed purposes include account security, verification, matching, rental fulfilment, collection/return coordination, payment processing, customer support, fraud prevention, legal claims, service communications and optional analytics/marketing. Distinguish processing necessary to perform a requested service or comply with law from processing based on consent. Do not bundle optional marketing or analytics consent with essential service access.

## 4. Sharing and processors
Disclose categories of recipients: payment providers, SMS/telecom providers, identity-verification providers, cloud hosting/storage, customer-support providers, analytics vendors and competent authorities where legally required. Name material processors where required. Describe purpose, data categories, locations, safeguards and transfer arrangements. Do not promise that data never leaves India until hosting/vendor regions are verified.

## 5. Retention and deletion
Keep personal data only for an approved, documented purpose and retention period. A deletion request may be delayed or limited where an active rental, payment reconciliation, tax/accounting obligation, safety investigation, dispute, fraud prevention or legal hold requires preservation. Explain what is erased, anonymised or retained and why. Retention periods in the schedule are not approved until counsel and business owners sign them off.

## 6. Rights and requests
Provide routes to request access, correction, erasure/deletion, withdrawal of consent and grievance redressal, subject to applicable law and lawful exceptions. Acknowledge receipt, verify requester identity proportionately, track the case, explain any partial refusal and record completion. [INSERT COUNSEL-APPROVED STATUTORY TIMELINES AND APPEAL ROUTE.]

## 7. Security and incidents
Use least-privilege access, MFA for sensitive data, private storage, short-lived signed URLs, encryption in transit/at rest where supported, audit trails, vendor controls and incident response. Describe breach notification only in the form and time required by the rules in force; do not promise a fixed deadline until counsel confirms it.

## 8. Children and sensitive data
State whether minors are permitted. If services are directed to or knowingly used by children, obtain legal review of parental/guardian consent, age assurance and restrictions on tracking/targeted advertising. Identity documents require a separate notice and minimisation controls.

## 9. Changes and contact
Version, effective date and SHA-256 hash are displayed with this policy. Material changes trigger renewed acceptance or consent where required. Contact [PRIVACY CONTACT] and [GRIEVANCE OFFICER].

## Counsel and product sign-off
Complete a data map, processor contracts, cross-border transfer map, lawful-basis assessment, children's-data assessment, retention schedule, breach playbook, rights timetable and notice translations. Confirm commencement and transitional rules under the DPDP Act and Rules before publication.
$doc$,'draft',true,true
) on conflict(document_type,version) do nothing;

insert into public.legal_documents(
 document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
 content_markdown,review_status,requires_acceptance,reacceptance_required
) values (
 'cookie_policy','0.1-draft','Cookie Policy (Applicability Review)','docs/legal-drafts/03-cookie-policy-if-applicable.md',
 encode(extensions.digest(convert_to($doc$# Cookie and Similar Technologies Policy — Applicability Review

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
$doc$,'UTF8'),'sha256'),'hex'),
 null,null,false,$doc$# Cookie and Similar Technologies Policy — Applicability Review

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
$doc$,'draft',false,true
) on conflict(document_type,version) do nothing;

insert into public.legal_documents(
 document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
 content_markdown,review_status,requires_acceptance,reacceptance_required
) values (
 'marketplace_rules','0.1-draft','User and Marketplace Rules','docs/legal-drafts/04-user-and-marketplace-rules.md',
 encode(extensions.digest(convert_to($doc$# User and Marketplace Rules

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Honest participation
Use your real account, provide accurate contact and eligibility information, and keep listing, condition, availability and locality details current. Do not create fake listings, fake bookings, fake reviews or misleading identities.

## 2. Book ownership and listings
Only list a physical copy you own or are authorised to lend. Do not list stolen, counterfeit, recalled or unlawfully obtained books. Disclose missing pages, water damage, writing, highlights, odour, binding damage, edition differences and other material condition facts. Obtain permission for photographs and remove personal information from images.

## 3. Booking and fulfilment
Do not treat a request as accepted until the platform records acceptance. Pay through approved channels. Do not ask another user to bypass platform checkout, share payment credentials or move a transaction off-platform to avoid fees or safeguards. Follow the displayed collection, handover, due-date and return instructions.

## 4. Safety and prohibited behaviour
No threats, harassment, hate, stalking, doxxing, discrimination, sexual harassment, coercion, fraud, theft, extortion, impersonation, unauthorised surveillance or unsafe meeting arrangements. Use public, approved handover locations and report immediate safety concerns to local emergency services and ShelfShare.

## 5. Community and reviews
Post lawful, relevant and respectful content. Reviews must reflect genuine experiences and must not be purchased, manipulated, retaliatory or disclose another person's private data. Report suspected infringements through the platform.

## 6. Enforcement and appeals
ShelfShare may investigate, preserve relevant evidence, restrict content or accounts proportionately, and refer matters to competent authorities where legally required. Users should receive a reason and an appeal route unless doing so is legally restricted or would compromise safety/investigation.

## 7. Updates
These rules form part of the marketplace terms. Version, effective date and hash are recorded. Material rule changes may require renewed acceptance.
$doc$,'UTF8'),'sha256'),'hex'),
 null,null,false,$doc$# User and Marketplace Rules

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Honest participation
Use your real account, provide accurate contact and eligibility information, and keep listing, condition, availability and locality details current. Do not create fake listings, fake bookings, fake reviews or misleading identities.

## 2. Book ownership and listings
Only list a physical copy you own or are authorised to lend. Do not list stolen, counterfeit, recalled or unlawfully obtained books. Disclose missing pages, water damage, writing, highlights, odour, binding damage, edition differences and other material condition facts. Obtain permission for photographs and remove personal information from images.

## 3. Booking and fulfilment
Do not treat a request as accepted until the platform records acceptance. Pay through approved channels. Do not ask another user to bypass platform checkout, share payment credentials or move a transaction off-platform to avoid fees or safeguards. Follow the displayed collection, handover, due-date and return instructions.

## 4. Safety and prohibited behaviour
No threats, harassment, hate, stalking, doxxing, discrimination, sexual harassment, coercion, fraud, theft, extortion, impersonation, unauthorised surveillance or unsafe meeting arrangements. Use public, approved handover locations and report immediate safety concerns to local emergency services and ShelfShare.

## 5. Community and reviews
Post lawful, relevant and respectful content. Reviews must reflect genuine experiences and must not be purchased, manipulated, retaliatory or disclose another person's private data. Report suspected infringements through the platform.

## 6. Enforcement and appeals
ShelfShare may investigate, preserve relevant evidence, restrict content or accounts proportionately, and refer matters to competent authorities where legally required. Users should receive a reason and an appeal route unless doing so is legally restricted or would compromise safety/investigation.

## 7. Updates
These rules form part of the marketplace terms. Version, effective date and hash are recorded. Material rule changes may require renewed acceptance.
$doc$,'draft',true,true
) on conflict(document_type,version) do nothing;

insert into public.legal_documents(
 document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
 content_markdown,review_status,requires_acceptance,reacceptance_required
) values (
 'owner_agreement','0.1-draft','Book Owner Agreement','docs/legal-drafts/05-owner-agreement.md',
 encode(extensions.digest(convert_to($doc$# Book Owner Agreement

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Owner status and authority
The owner confirms they own the listed copy or hold sufficient authority to lend it. They must not list a copy subject to a restriction that prohibits lending. The owner must accurately identify edition, language, condition, availability and any defects.

## 2. Listing and valuation
The owner authorises ShelfShare to display the listing and relevant photographs for marketplace operation. Any suggested valuation is indicative only, not a guarantee of sale or replacement value. Pricing, rental fee, platform commission, gateway charge, tax and deposit treatment must be shown before a booking is accepted.

## 3. Booking and handover
The owner must respond to requests within the displayed period, honour accepted bookings, attend the agreed safe handover location, verify handover through the approved QR/OTP process, and provide accurate condition evidence. The owner must not retain unnecessary identity or payment data about the reader.

## 4. Return and disputes
The owner must inspect the returned copy promptly, compare condition evidence fairly and raise damage/non-return concerns within the stated review period. Normal wear disclosed in the listing is not automatically compensable. No unilateral deposit deduction is permitted; any claim follows the Damage and Compensation Policy and dispute process.

## 5. Payments and tax
Payouts are subject to successful collection/return milestones, dispute holds, provider settlement, verification and applicable law. The owner is responsible for accurate tax information and their own tax obligations, subject to invoices/withholding information the platform is required to provide. [COUNSEL: clarify marketplace withholding/TCS/GST obligations.]

## 6. Prohibited conduct
No discrimination, unsafe handovers, false condition claims, off-platform payment solicitation, retaliation, misuse of reader data or repeated cancellation after acceptance.

## 7. Suspension and termination
Set out grounds, notice, appeal, outstanding booking completion, payout holds and records retention. Termination does not extinguish accrued rights or legal obligations.
$doc$,'UTF8'),'sha256'),'hex'),
 null,null,false,$doc$# Book Owner Agreement

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Owner status and authority
The owner confirms they own the listed copy or hold sufficient authority to lend it. They must not list a copy subject to a restriction that prohibits lending. The owner must accurately identify edition, language, condition, availability and any defects.

## 2. Listing and valuation
The owner authorises ShelfShare to display the listing and relevant photographs for marketplace operation. Any suggested valuation is indicative only, not a guarantee of sale or replacement value. Pricing, rental fee, platform commission, gateway charge, tax and deposit treatment must be shown before a booking is accepted.

## 3. Booking and handover
The owner must respond to requests within the displayed period, honour accepted bookings, attend the agreed safe handover location, verify handover through the approved QR/OTP process, and provide accurate condition evidence. The owner must not retain unnecessary identity or payment data about the reader.

## 4. Return and disputes
The owner must inspect the returned copy promptly, compare condition evidence fairly and raise damage/non-return concerns within the stated review period. Normal wear disclosed in the listing is not automatically compensable. No unilateral deposit deduction is permitted; any claim follows the Damage and Compensation Policy and dispute process.

## 5. Payments and tax
Payouts are subject to successful collection/return milestones, dispute holds, provider settlement, verification and applicable law. The owner is responsible for accurate tax information and their own tax obligations, subject to invoices/withholding information the platform is required to provide. [COUNSEL: clarify marketplace withholding/TCS/GST obligations.]

## 6. Prohibited conduct
No discrimination, unsafe handovers, false condition claims, off-platform payment solicitation, retaliation, misuse of reader data or repeated cancellation after acceptance.

## 7. Suspension and termination
Set out grounds, notice, appeal, outstanding booking completion, payout holds and records retention. Termination does not extinguish accrued rights or legal obligations.
$doc$,'draft',true,true
) on conflict(document_type,version) do nothing;

insert into public.legal_documents(
 document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
 content_markdown,review_status,requires_acceptance,reacceptance_required
) values (
 'reader_agreement','0.1-draft','Reader Agreement','docs/legal-drafts/06-reader-agreement.md',
 encode(extensions.digest(convert_to($doc$# Reader Agreement

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Account and eligibility
The reader must provide accurate information, complete verification requirements applicable to the requested booking and keep contact details current. Age limits and any additional eligibility checks are [COUNSEL/PRODUCT DECISION].

## 2. Booking and price
The reader reviews the physical copy details, condition, rental period, due date, collection/return location, rental charge, refundable deposit, platform fee and taxes before requesting/confirming. A booking exists only at the platform state described at checkout and in the Rental Agreement.

## 3. Use and care
Use the book for lawful personal reading. Do not sell, lend onward, pledge, alter, remove pages, damage, mark or commercially reproduce it without permission. Keep it secure and protect it from water, fire, pets, children and other reasonably foreseeable risks.

## 4. Collection and return
Use the approved QR/OTP handover process, verify the item and recorded condition, keep handover confirmation, and return it by the due date at the agreed location. Do not hand the item to an unverified third party or use an unapproved courier unless the owner and platform approve that method.

## 5. Late return, loss and damage
Notify ShelfShare promptly if the book is lost, damaged, stolen or cannot be returned. Any late fees, compensation and deposit treatment must follow the separately disclosed policies and a documented review. No amount may be charged twice for the same loss.

## 6. Cancellations, refunds and disputes
Cancellation eligibility, refund calculation, processing time and dispute procedure are set out in the Cancellation and Refund Policy. Payment-provider processing time may vary. Statutory consumer rights are not waived.

## 7. Privacy and conduct
Use owner contact details only to fulfil the rental. Do not harass, dox, threaten, discriminate or misuse the book owner's information.
$doc$,'UTF8'),'sha256'),'hex'),
 null,null,false,$doc$# Reader Agreement

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Account and eligibility
The reader must provide accurate information, complete verification requirements applicable to the requested booking and keep contact details current. Age limits and any additional eligibility checks are [COUNSEL/PRODUCT DECISION].

## 2. Booking and price
The reader reviews the physical copy details, condition, rental period, due date, collection/return location, rental charge, refundable deposit, platform fee and taxes before requesting/confirming. A booking exists only at the platform state described at checkout and in the Rental Agreement.

## 3. Use and care
Use the book for lawful personal reading. Do not sell, lend onward, pledge, alter, remove pages, damage, mark or commercially reproduce it without permission. Keep it secure and protect it from water, fire, pets, children and other reasonably foreseeable risks.

## 4. Collection and return
Use the approved QR/OTP handover process, verify the item and recorded condition, keep handover confirmation, and return it by the due date at the agreed location. Do not hand the item to an unverified third party or use an unapproved courier unless the owner and platform approve that method.

## 5. Late return, loss and damage
Notify ShelfShare promptly if the book is lost, damaged, stolen or cannot be returned. Any late fees, compensation and deposit treatment must follow the separately disclosed policies and a documented review. No amount may be charged twice for the same loss.

## 6. Cancellations, refunds and disputes
Cancellation eligibility, refund calculation, processing time and dispute procedure are set out in the Cancellation and Refund Policy. Payment-provider processing time may vary. Statutory consumer rights are not waived.

## 7. Privacy and conduct
Use owner contact details only to fulfil the rental. Do not harass, dox, threaten, discriminate or misuse the book owner's information.
$doc$,'draft',true,true
) on conflict(document_type,version) do nothing;

insert into public.legal_documents(
 document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
 content_markdown,review_status,requires_acceptance,reacceptance_required
) values (
 'rental_agreement','0.1-draft','Book Rental Agreement','docs/legal-drafts/07-rental-agreement.md',
 encode(extensions.digest(convert_to($doc$# Book Rental Agreement

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Parties and transaction record
This agreement applies to each accepted rental between the verified owner identified in the booking record and the reader identified in that record. ShelfShare's contractual role and any agency relationship must be finalised by Indian counsel and must match actual payment and fulfilment operations.

## 2. Book and agreed terms
The booking record is the authoritative schedule for title, edition, physical-copy identifier, declared condition, rental start/end, due date, collection/return method, location, rental fee, deposit, platform fee and applicable tax. The user must be shown the full schedule before acceptance.

## 3. Possession and title
Ownership remains with the owner. The reader receives temporary possession solely for the agreed rental. No sale, transfer of title or right to sub-lend is created.

## 4. Handover evidence
Collection and return are recorded through the platform's QR/OTP process and relevant timestamped condition evidence. Each party should review the evidence at the handover. The platform must not imply an identity document is proof of book condition or ownership.

## 5. Care, return and overdue status
The reader must take reasonable care and return the same physical copy by the due date using the agreed method. Any extension must be requested and accepted in the application before the original due date. A reminder is not an extension.

## 6. Damage, loss and non-return
Claims require relevant before/after evidence, opportunity to respond, a reasoned decision and an appeal route. Normal wear and pre-existing defects are excluded. Compensation must be proportionate, evidenced, capped by the applicable policy/actual permitted loss and not charged twice. Deposit deductions require the separately disclosed decision process.

## 7. Payment, deposit and refunds
Rental fees and security deposits are separate ledger entries. Deposits are refundable subject only to a permitted, evidence-based deduction or legal hold. Refunds and payouts follow provider processes and do not remove statutory remedies.

## 8. Disputes and governing terms
The Damage, Deposit, Non-Return, Cancellation and Refund policies apply as schedules. Governing law, jurisdiction and dispute resolution wording require counsel approval; mandatory consumer rights remain unaffected.
$doc$,'UTF8'),'sha256'),'hex'),
 null,null,false,$doc$# Book Rental Agreement

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Parties and transaction record
This agreement applies to each accepted rental between the verified owner identified in the booking record and the reader identified in that record. ShelfShare's contractual role and any agency relationship must be finalised by Indian counsel and must match actual payment and fulfilment operations.

## 2. Book and agreed terms
The booking record is the authoritative schedule for title, edition, physical-copy identifier, declared condition, rental start/end, due date, collection/return method, location, rental fee, deposit, platform fee and applicable tax. The user must be shown the full schedule before acceptance.

## 3. Possession and title
Ownership remains with the owner. The reader receives temporary possession solely for the agreed rental. No sale, transfer of title or right to sub-lend is created.

## 4. Handover evidence
Collection and return are recorded through the platform's QR/OTP process and relevant timestamped condition evidence. Each party should review the evidence at the handover. The platform must not imply an identity document is proof of book condition or ownership.

## 5. Care, return and overdue status
The reader must take reasonable care and return the same physical copy by the due date using the agreed method. Any extension must be requested and accepted in the application before the original due date. A reminder is not an extension.

## 6. Damage, loss and non-return
Claims require relevant before/after evidence, opportunity to respond, a reasoned decision and an appeal route. Normal wear and pre-existing defects are excluded. Compensation must be proportionate, evidenced, capped by the applicable policy/actual permitted loss and not charged twice. Deposit deductions require the separately disclosed decision process.

## 7. Payment, deposit and refunds
Rental fees and security deposits are separate ledger entries. Deposits are refundable subject only to a permitted, evidence-based deduction or legal hold. Refunds and payouts follow provider processes and do not remove statutory remedies.

## 8. Disputes and governing terms
The Damage, Deposit, Non-Return, Cancellation and Refund policies apply as schedules. Governing law, jurisdiction and dispute resolution wording require counsel approval; mandatory consumer rights remain unaffected.
$doc$,'draft',true,true
) on conflict(document_type,version) do nothing;

insert into public.legal_documents(
 document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
 content_markdown,review_status,requires_acceptance,reacceptance_required
) values (
 'damage_compensation_policy','0.1-draft','Damage and Compensation Policy','docs/legal-drafts/08-damage-and-compensation-policy.md',
 encode(extensions.digest(convert_to($doc$# Damage and Compensation Policy

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Purpose and principles
This policy provides a fair, evidence-led process for alleged damage or loss of a rented book. It is not a penalty schedule. Any compensation must be proportionate to substantiated loss, avoid double recovery and comply with consumer and contract law.

## 2. Condition record
At listing and collection, record the same physical copy, visible condition, missing pages, writing, stains, tears, binding and other disclosed defects. Use clear, date/time-stamped images where appropriate and avoid capturing unrelated people or personal documents. At return, record comparable evidence from reasonable angles.

## 3. What may be claimed
A claim may cover verified repair cost or reasonable replacement value where repair is not practical, subject to age, edition availability, prior condition, depreciation, salvage and evidence. Ordinary wear consistent with disclosed use is not compensable. Pre-existing damage and inherent defects are excluded.

## 4. Procedure
The owner submits a claim within [COUNSEL-APPROVED CLAIM WINDOW], with evidence and itemised amount. The reader receives the claim and a fair opportunity to respond. A reviewer with no conflict of interest evaluates both sides, records findings and gives reasons. Conflicts and appeals are escalated to an independent reviewer.

## 5. Deposit treatment and payment
A deposit is not automatically forfeited. Any deduction requires an approved decision, itemised reasons and an amount not exceeding justified loss or the agreed disclosed cap. Refund the undisputed balance. No double recovery from deposit, direct payment, insurance and separate compensation.

## 6. Appeals and records
Provide an appeal path and time limit approved by counsel. Preserve only the evidence required for the case and approved retention period; restrict access and log every sensitive view.
$doc$,'UTF8'),'sha256'),'hex'),
 null,null,false,$doc$# Damage and Compensation Policy

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Purpose and principles
This policy provides a fair, evidence-led process for alleged damage or loss of a rented book. It is not a penalty schedule. Any compensation must be proportionate to substantiated loss, avoid double recovery and comply with consumer and contract law.

## 2. Condition record
At listing and collection, record the same physical copy, visible condition, missing pages, writing, stains, tears, binding and other disclosed defects. Use clear, date/time-stamped images where appropriate and avoid capturing unrelated people or personal documents. At return, record comparable evidence from reasonable angles.

## 3. What may be claimed
A claim may cover verified repair cost or reasonable replacement value where repair is not practical, subject to age, edition availability, prior condition, depreciation, salvage and evidence. Ordinary wear consistent with disclosed use is not compensable. Pre-existing damage and inherent defects are excluded.

## 4. Procedure
The owner submits a claim within [COUNSEL-APPROVED CLAIM WINDOW], with evidence and itemised amount. The reader receives the claim and a fair opportunity to respond. A reviewer with no conflict of interest evaluates both sides, records findings and gives reasons. Conflicts and appeals are escalated to an independent reviewer.

## 5. Deposit treatment and payment
A deposit is not automatically forfeited. Any deduction requires an approved decision, itemised reasons and an amount not exceeding justified loss or the agreed disclosed cap. Refund the undisputed balance. No double recovery from deposit, direct payment, insurance and separate compensation.

## 6. Appeals and records
Provide an appeal path and time limit approved by counsel. Preserve only the evidence required for the case and approved retention period; restrict access and log every sensitive view.
$doc$,'draft',true,true
) on conflict(document_type,version) do nothing;

insert into public.legal_documents(
 document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
 content_markdown,review_status,requires_acceptance,reacceptance_required
) values (
 'cancellation_refund_policy','0.1-draft','Cancellation and Refund Policy','docs/legal-drafts/09-cancellation-and-refund-policy.md',
 encode(extensions.digest(convert_to($doc$# Cancellation and Refund Policy

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Pre-booking disclosure
Before payment, show rental price, any platform/service fee, security deposit, tax, cancellation windows, refund method and expected processing range. Distinguish a cancellation fee from a payment-provider charge and state who receives each amount.

## 2. Reader cancellation
Set clear rules for cancellation before owner acceptance, after acceptance but before collection, after collection, and following owner failure to fulfil. State the exact refund or non-refundable component for each stage only after legal and commercial approval. Do not impose an unfair or disproportionate forfeiture.

## 3. Owner cancellation and platform failure
If an owner cancels an accepted booking or cannot provide the listed copy, the default draft position is a full refund of amounts collected for the unfulfilled rental, including refundable deposits, unless counsel approves another lawful, clearly disclosed outcome. Do not penalise a reader for platform/provider failure.

## 4. Refund process
Refunds are initiated to the original payment method where supported. Show request date, amount, status, provider reference and failure route. A payment gateway's processing time may differ; avoid guarantees the platform cannot control. Never describe a refund as complete until provider confirmation is received.

## 5. Disputes and statutory rights
Provide an accessible complaint route for incorrect deductions, duplicate charges, failed refunds and unauthorised payments. The policy does not limit statutory consumer remedies or chargeback rights.

## 6. Version and acceptance
The version in force at booking time and its hash must be retained with the booking. Material changes should not retrospectively alter an existing booking.
$doc$,'UTF8'),'sha256'),'hex'),
 null,null,false,$doc$# Cancellation and Refund Policy

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Pre-booking disclosure
Before payment, show rental price, any platform/service fee, security deposit, tax, cancellation windows, refund method and expected processing range. Distinguish a cancellation fee from a payment-provider charge and state who receives each amount.

## 2. Reader cancellation
Set clear rules for cancellation before owner acceptance, after acceptance but before collection, after collection, and following owner failure to fulfil. State the exact refund or non-refundable component for each stage only after legal and commercial approval. Do not impose an unfair or disproportionate forfeiture.

## 3. Owner cancellation and platform failure
If an owner cancels an accepted booking or cannot provide the listed copy, the default draft position is a full refund of amounts collected for the unfulfilled rental, including refundable deposits, unless counsel approves another lawful, clearly disclosed outcome. Do not penalise a reader for platform/provider failure.

## 4. Refund process
Refunds are initiated to the original payment method where supported. Show request date, amount, status, provider reference and failure route. A payment gateway's processing time may differ; avoid guarantees the platform cannot control. Never describe a refund as complete until provider confirmation is received.

## 5. Disputes and statutory rights
Provide an accessible complaint route for incorrect deductions, duplicate charges, failed refunds and unauthorised payments. The policy does not limit statutory consumer remedies or chargeback rights.

## 6. Version and acceptance
The version in force at booking time and its hash must be retained with the booking. Material changes should not retrospectively alter an existing booking.
$doc$,'draft',true,true
) on conflict(document_type,version) do nothing;

insert into public.legal_documents(
 document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
 content_markdown,review_status,requires_acceptance,reacceptance_required
) values (
 'deposit_policy','0.1-draft','Security Deposit Policy','docs/legal-drafts/10-deposit-policy.md',
 encode(extensions.digest(convert_to($doc$# Security Deposit Policy

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Nature of the deposit
A security deposit is a refundable amount collected to secure limited, disclosed obligations under a particular rental. It is separate from rental revenue, platform commission, gateway charges and tax. ShelfShare must confirm its legal/payment-provider model for holding, safeguarding and returning deposits before launch.

## 2. Amount and disclosure
Show the deposit amount, calculation method, collection timing, refund timing, permitted deductions and dispute mechanism before the reader confirms a booking. Do not describe the deposit as a fee or revenue.

## 3. Holding and use
The deposit must be tracked separately by booking and not treated as free operating cash. Access to deposit funds and release authority must be role-restricted and audited. No deposit is forfeited automatically because a booking is late, cancelled or disputed.

## 4. Refund
After confirmed return and the inspection/review period, release the deposit promptly, subject only to an evidenced, permitted claim or legal hold. Refund the undisputed amount even where a claim concerns only part of the deposit, where operationally and legally possible.

## 5. Deductions
A deduction requires notice, evidence, reader response opportunity, a reasoned decision and appeal. The amount must be proportionate and must not exceed the justified loss or disclosed cap. Do not double-charge.

## 6. Disputes and unclaimed amounts
Define procedures for contested claims, failed payouts, stale accounts, unclaimed balances and insolvency/segregation risks with legal/payment-provider advice. No automatic transfer of unclaimed deposits to platform revenue.
$doc$,'UTF8'),'sha256'),'hex'),
 null,null,false,$doc$# Security Deposit Policy

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Nature of the deposit
A security deposit is a refundable amount collected to secure limited, disclosed obligations under a particular rental. It is separate from rental revenue, platform commission, gateway charges and tax. ShelfShare must confirm its legal/payment-provider model for holding, safeguarding and returning deposits before launch.

## 2. Amount and disclosure
Show the deposit amount, calculation method, collection timing, refund timing, permitted deductions and dispute mechanism before the reader confirms a booking. Do not describe the deposit as a fee or revenue.

## 3. Holding and use
The deposit must be tracked separately by booking and not treated as free operating cash. Access to deposit funds and release authority must be role-restricted and audited. No deposit is forfeited automatically because a booking is late, cancelled or disputed.

## 4. Refund
After confirmed return and the inspection/review period, release the deposit promptly, subject only to an evidenced, permitted claim or legal hold. Refund the undisputed amount even where a claim concerns only part of the deposit, where operationally and legally possible.

## 5. Deductions
A deduction requires notice, evidence, reader response opportunity, a reasoned decision and appeal. The amount must be proportionate and must not exceed the justified loss or disclosed cap. Do not double-charge.

## 6. Disputes and unclaimed amounts
Define procedures for contested claims, failed payouts, stale accounts, unclaimed balances and insolvency/segregation risks with legal/payment-provider advice. No automatic transfer of unclaimed deposits to platform revenue.
$doc$,'draft',true,true
) on conflict(document_type,version) do nothing;

insert into public.legal_documents(
 document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
 content_markdown,review_status,requires_acceptance,reacceptance_required
) values (
 'non_return_policy','0.1-draft','Non-Return and Overdue Book Policy','docs/legal-drafts/11-non-return-policy.md',
 encode(extensions.digest(convert_to($doc$# Non-Return and Overdue Book Policy

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Due date and reminders
Each booking displays a specific due date/time and approved return method. Courtesy reminders do not change the due date. The reader must request and obtain approval for an extension through the platform.

## 2. Overdue contact
After the due time, send proportionate service reminders through permitted channels. Do not threaten, shame, publicly identify, contact unrelated persons or disclose the rental to an employer/family member. Respect notification preferences except where a lawful service communication basis applies.

## 3. Escalation
If the copy is not returned, contact the reader privately, offer a reasonable route to arrange return, and escalate according to a counsel-approved schedule. Staff must review delivery failures, emergencies, safety concerns and disputed due dates before enforcement.

## 4. Loss or suspected theft
A non-return is not automatically proof of theft or criminal intent. Preserve transaction and handover evidence, offer the reader a chance to explain, assess recovery/replacement options, and refer to authorities only where facts and legal advice justify it. Do not publish allegations.

## 5. Charges and deposit
Any late fee must be disclosed before booking, reasonable, legally reviewed and calculated transparently. Replacement compensation requires evidence of actual loss and must account for condition, depreciation and availability. No duplicate late fee, replacement fee and deposit deduction for the same loss.

## 6. Appeal and privacy
Provide a dispute/appeal route. Limit retention and access to case evidence to staff with a need to know, log each access and delete/anonymise when no longer lawfully needed.
$doc$,'UTF8'),'sha256'),'hex'),
 null,null,false,$doc$# Non-Return and Overdue Book Policy

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Due date and reminders
Each booking displays a specific due date/time and approved return method. Courtesy reminders do not change the due date. The reader must request and obtain approval for an extension through the platform.

## 2. Overdue contact
After the due time, send proportionate service reminders through permitted channels. Do not threaten, shame, publicly identify, contact unrelated persons or disclose the rental to an employer/family member. Respect notification preferences except where a lawful service communication basis applies.

## 3. Escalation
If the copy is not returned, contact the reader privately, offer a reasonable route to arrange return, and escalate according to a counsel-approved schedule. Staff must review delivery failures, emergencies, safety concerns and disputed due dates before enforcement.

## 4. Loss or suspected theft
A non-return is not automatically proof of theft or criminal intent. Preserve transaction and handover evidence, offer the reader a chance to explain, assess recovery/replacement options, and refer to authorities only where facts and legal advice justify it. Do not publish allegations.

## 5. Charges and deposit
Any late fee must be disclosed before booking, reasonable, legally reviewed and calculated transparently. Replacement compensation requires evidence of actual loss and must account for condition, depreciation and availability. No duplicate late fee, replacement fee and deposit deduction for the same loss.

## 6. Appeal and privacy
Provide a dispute/appeal route. Limit retention and access to case evidence to staff with a need to know, log each access and delete/anonymise when no longer lawfully needed.
$doc$,'draft',true,true
) on conflict(document_type,version) do nothing;

insert into public.legal_documents(
 document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
 content_markdown,review_status,requires_acceptance,reacceptance_required
) values (
 'community_guidelines','0.1-draft','Community Guidelines','docs/legal-drafts/12-community-guidelines.md',
 encode(extensions.digest(convert_to($doc$# Community Guidelines

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Be respectful
Treat readers, owners, authors and community members respectfully. Disagreement about books and opinions is welcome; abuse, threats, targeted harassment, hate, intimidation and discrimination are not.

## 2. No harmful or unlawful content
Do not post threats, sexual exploitation, child sexual abuse material, non-consensual intimate imagery, doxxing, private identity/payment data, scams, malware, impersonation or content that unlawfully promotes violence. Immediate safety threats should be reported to appropriate authorities.

## 3. Authenticity and manipulation
Do not buy or sell reviews, manipulate ratings, coordinate fake engagement, impersonate authors/owners or misrepresent a rental experience. Disclose incentives and referral relationships where required.

## 4. Copyright and attribution
Post only content you own or are authorised to use. Short quotations/reviews must comply with applicable copyright exceptions; attribution alone does not create permission. Report infringement using the Content and Copyright Policy.

## 5. Moderation
ShelfShare may hide, label, restrict or remove content under a published moderation process. It should preserve relevant evidence, explain decisions where safe and lawful, provide an appeal route and apply rules consistently. No automated system should be the sole basis for a serious user sanction without appropriate review.

## 6. Reporting and appeals
Use [IN-APP REPORT ROUTE] or contact [GRIEVANCE CONTACT]. Include the content link and a concise explanation; do not upload unrelated identity documents.
$doc$,'UTF8'),'sha256'),'hex'),
 null,null,false,$doc$# Community Guidelines

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Be respectful
Treat readers, owners, authors and community members respectfully. Disagreement about books and opinions is welcome; abuse, threats, targeted harassment, hate, intimidation and discrimination are not.

## 2. No harmful or unlawful content
Do not post threats, sexual exploitation, child sexual abuse material, non-consensual intimate imagery, doxxing, private identity/payment data, scams, malware, impersonation or content that unlawfully promotes violence. Immediate safety threats should be reported to appropriate authorities.

## 3. Authenticity and manipulation
Do not buy or sell reviews, manipulate ratings, coordinate fake engagement, impersonate authors/owners or misrepresent a rental experience. Disclose incentives and referral relationships where required.

## 4. Copyright and attribution
Post only content you own or are authorised to use. Short quotations/reviews must comply with applicable copyright exceptions; attribution alone does not create permission. Report infringement using the Content and Copyright Policy.

## 5. Moderation
ShelfShare may hide, label, restrict or remove content under a published moderation process. It should preserve relevant evidence, explain decisions where safe and lawful, provide an appeal route and apply rules consistently. No automated system should be the sole basis for a serious user sanction without appropriate review.

## 6. Reporting and appeals
Use [IN-APP REPORT ROUTE] or contact [GRIEVANCE CONTACT]. Include the content link and a concise explanation; do not upload unrelated identity documents.
$doc$,'draft',true,true
) on conflict(document_type,version) do nothing;

insert into public.legal_documents(
 document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
 content_markdown,review_status,requires_acceptance,reacceptance_required
) values (
 'content_copyright_policy','0.1-draft','Content and Copyright Policy','docs/legal-drafts/13-content-and-copyright-policy.md',
 encode(extensions.digest(convert_to($doc$# Content and Copyright Policy

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. User rights and licence
Users retain ownership of content they upload, subject to third-party rights. They grant ShelfShare a limited, non-exclusive, worldwide, royalty-free licence for the duration needed to host, store, reproduce, display, format, back up, moderate and distribute that content within the service and its promotion as expressly chosen by the user. The licence ends as specified after deletion, subject to backups, legal claims and records retention.

## 2. User warranties
Users warrant they own or are authorised to upload listing photographs, descriptions, reviews, community posts, excerpts and other content. They must not upload pirated scans, complete e-books, unauthorised cover art, publisher extracts beyond lawful use, or personal information about others without authority.

## 3. Copyright complaint
A rights holder or authorised agent should submit: contact details; identification of the work; exact allegedly infringing URL/content; explanation of rights and alleged infringement; good-faith statement; accuracy/authority declaration; signature and supporting evidence. Route notices to [DESIGNATED COPYRIGHT CONTACT]. Verify the notice and promptly restrict access where required by applicable law.

## 4. Counter-notice and restoration
Where legally available, notify the uploader, provide a structured counter-notice route and follow any statutory waiting period, court order or safe-harbour conditions. Do not promise restoration when prohibited by law or court order.

## 5. Repeat infringement and appeals
Adopt a proportionate repeat-infringer policy after counsel confirms the applicable intermediary obligations. Keep an internal record of notices, actions and appeals with restricted access and defined retention.

## 6. No legal conclusion
This policy is a process draft. Counsel must map the Information Technology Act, applicable intermediary rules, Copyright Act, e-commerce requirements and the actual platform's role before release.
$doc$,'UTF8'),'sha256'),'hex'),
 null,null,false,$doc$# Content and Copyright Policy

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. User rights and licence
Users retain ownership of content they upload, subject to third-party rights. They grant ShelfShare a limited, non-exclusive, worldwide, royalty-free licence for the duration needed to host, store, reproduce, display, format, back up, moderate and distribute that content within the service and its promotion as expressly chosen by the user. The licence ends as specified after deletion, subject to backups, legal claims and records retention.

## 2. User warranties
Users warrant they own or are authorised to upload listing photographs, descriptions, reviews, community posts, excerpts and other content. They must not upload pirated scans, complete e-books, unauthorised cover art, publisher extracts beyond lawful use, or personal information about others without authority.

## 3. Copyright complaint
A rights holder or authorised agent should submit: contact details; identification of the work; exact allegedly infringing URL/content; explanation of rights and alleged infringement; good-faith statement; accuracy/authority declaration; signature and supporting evidence. Route notices to [DESIGNATED COPYRIGHT CONTACT]. Verify the notice and promptly restrict access where required by applicable law.

## 4. Counter-notice and restoration
Where legally available, notify the uploader, provide a structured counter-notice route and follow any statutory waiting period, court order or safe-harbour conditions. Do not promise restoration when prohibited by law or court order.

## 5. Repeat infringement and appeals
Adopt a proportionate repeat-infringer policy after counsel confirms the applicable intermediary obligations. Keep an internal record of notices, actions and appeals with restricted access and defined retention.

## 6. No legal conclusion
This policy is a process draft. Counsel must map the Information Technology Act, applicable intermediary rules, Copyright Act, e-commerce requirements and the actual platform's role before release.
$doc$,'draft',true,true
) on conflict(document_type,version) do nothing;

insert into public.legal_documents(
 document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
 content_markdown,review_status,requires_acceptance,reacceptance_required
) values (
 'grievance_policy','0.1-draft','Grievance Redressal Policy','docs/legal-drafts/14-grievance-policy.md',
 encode(extensions.digest(convert_to($doc$# Grievance Redressal Policy

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Contact and appointment
Grievance Officer: [FULL NAME], [DESIGNATION], [LEGAL ENTITY], postal address [ADDRESS], email [EMAIL], phone [PHONE]. Appoint and publish only after verifying the responsible entity and applicable statutory requirements.

## 2. What may be reported
Users may report account access issues, unsafe handovers, fraud, listings, payment/deposit errors, refunds, non-return, damage claims, harassment, community content, privacy/consent requests, identity-document handling and accessibility issues.

## 3. How to complain
Provide the booking/listing/ticket reference, a clear description, relevant dates and requested resolution. Do not send full identity documents, passwords, OTPs or payment credentials by email. Use the secure in-app channel for supporting evidence.

## 4. Acknowledgement and resolution
ShelfShare records the complaint, assigns a priority, acknowledges receipt, provides a reference number, keeps a response history and communicates progress. Statutory acknowledgement/resolution periods and escalation routes must be inserted only after counsel confirms the correct rule for each complaint type.

## 5. Appeals and external remedies
Explain escalation to a senior reviewer and any applicable consumer commission, cybercrime, telecom, data protection or other competent authority. Do not imply that internal resolution removes a person's statutory rights.

## 6. Privacy and records
Limit access to staff with a need to know, separate internal notes from public replies, log sensitive access and retain case files only under an approved schedule.
$doc$,'UTF8'),'sha256'),'hex'),
 null,null,false,$doc$# Grievance Redressal Policy

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Contact and appointment
Grievance Officer: [FULL NAME], [DESIGNATION], [LEGAL ENTITY], postal address [ADDRESS], email [EMAIL], phone [PHONE]. Appoint and publish only after verifying the responsible entity and applicable statutory requirements.

## 2. What may be reported
Users may report account access issues, unsafe handovers, fraud, listings, payment/deposit errors, refunds, non-return, damage claims, harassment, community content, privacy/consent requests, identity-document handling and accessibility issues.

## 3. How to complain
Provide the booking/listing/ticket reference, a clear description, relevant dates and requested resolution. Do not send full identity documents, passwords, OTPs or payment credentials by email. Use the secure in-app channel for supporting evidence.

## 4. Acknowledgement and resolution
ShelfShare records the complaint, assigns a priority, acknowledges receipt, provides a reference number, keeps a response history and communicates progress. Statutory acknowledgement/resolution periods and escalation routes must be inserted only after counsel confirms the correct rule for each complaint type.

## 5. Appeals and external remedies
Explain escalation to a senior reviewer and any applicable consumer commission, cybercrime, telecom, data protection or other competent authority. Do not imply that internal resolution removes a person's statutory rights.

## 6. Privacy and records
Limit access to staff with a need to know, separate internal notes from public replies, log sensitive access and retain case files only under an approved schedule.
$doc$,'draft',true,true
) on conflict(document_type,version) do nothing;

insert into public.legal_documents(
 document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
 content_markdown,review_status,requires_acceptance,reacceptance_required
) values (
 'identity_verification_notice','0.1-draft','Identity Verification Notice','docs/legal-drafts/15-identity-verification-notice.md',
 encode(extensions.digest(convert_to($doc$# Identity Verification Notice

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Why verification is requested
ShelfShare may request limited identity or eligibility verification to protect users, reduce fraud, confirm age/eligibility where necessary, support safe handovers and comply with legal or payment-provider requirements. Each data element and verification step must have a documented purpose and lawful basis.

## 2. What may be processed
Depending on the approved flow: name, date-of-birth/age result, contact verification status, document type, masked document suffix, verification provider reference, outcome and reviewer/audit history. Full document images should be collected only when necessary and must be stored in a private bucket with restricted staff access and short-lived signed access.

## 3. Alternatives and consequences
Explain accepted documents, alternatives, failure/retry route, manual review and consequences of not completing verification. Do not claim that government ID is universally mandatory unless legally or operationally justified and disclosed. Do not collect Aadhaar or other government identity data in a way that breaches applicable UIDAI restrictions; obtain specialised counsel advice before any Aadhaar flow.

## 4. Sharing and storage
Identify the verification provider, hosting/storage region, subprocessors, retention period and deletion process. The reviewer should see only the minimum necessary fields. No public URL or general admin role may access source documents.

## 5. Rights, retention and contact
Explain how to access/correct/delete data or raise a grievance, subject to legal holds and obligations. State the approved retention period; do not invent a period. Contact [PRIVACY CONTACT].

## 6. Separate notice and acceptance
Present this notice before collecting documents. Capture notice version, purpose, source, timestamp and any required consent separately from general terms acceptance. Obtain counsel approval for the lawful basis and age assurance model.
$doc$,'UTF8'),'sha256'),'hex'),
 null,null,false,$doc$# Identity Verification Notice

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Why verification is requested
ShelfShare may request limited identity or eligibility verification to protect users, reduce fraud, confirm age/eligibility where necessary, support safe handovers and comply with legal or payment-provider requirements. Each data element and verification step must have a documented purpose and lawful basis.

## 2. What may be processed
Depending on the approved flow: name, date-of-birth/age result, contact verification status, document type, masked document suffix, verification provider reference, outcome and reviewer/audit history. Full document images should be collected only when necessary and must be stored in a private bucket with restricted staff access and short-lived signed access.

## 3. Alternatives and consequences
Explain accepted documents, alternatives, failure/retry route, manual review and consequences of not completing verification. Do not claim that government ID is universally mandatory unless legally or operationally justified and disclosed. Do not collect Aadhaar or other government identity data in a way that breaches applicable UIDAI restrictions; obtain specialised counsel advice before any Aadhaar flow.

## 4. Sharing and storage
Identify the verification provider, hosting/storage region, subprocessors, retention period and deletion process. The reviewer should see only the minimum necessary fields. No public URL or general admin role may access source documents.

## 5. Rights, retention and contact
Explain how to access/correct/delete data or raise a grievance, subject to legal holds and obligations. State the approved retention period; do not invent a period. Contact [PRIVACY CONTACT].

## 6. Separate notice and acceptance
Present this notice before collecting documents. Capture notice version, purpose, source, timestamp and any required consent separately from general terms acceptance. Obtain counsel approval for the lawful basis and age assurance model.
$doc$,'draft',true,true
) on conflict(document_type,version) do nothing;

insert into public.legal_documents(
 document_type,version,title,content_uri,sha256,effective_from,effective_until,is_published,
 content_markdown,review_status,requires_acceptance,reacceptance_required
) values (
 'referral_terms','0.1-draft','Referral Programme Terms','docs/legal-drafts/16-referral-terms.md',
 encode(extensions.digest(convert_to($doc$# Referral Programme Terms

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Eligibility
The referral programme is available only to users who meet the eligibility conditions shown in the relevant campaign. Employees, agents, related accounts, self-referrals and fraud-linked accounts may be excluded under a clear published rule reviewed by counsel.

## 2. Referral attribution
A referral is attributed only through the approved link/code and platform record. Users must not create multiple accounts, use false identities, spam contacts, misrepresent rewards or manipulate bookings.

## 3. Qualifying activity
Each campaign must state the qualifying action, minimum eligible booking value, payment/return completion condition, attribution window, cap, expiry and exclusions. Merely signing up or submitting an unaccepted booking does not earn a reward unless the campaign explicitly says so.

## 4. Reward
Specify whether the reward is a discount, fee credit or non-cash benefit. State value, issue timing, expiry, redemption limits, refund/cancellation reversal and tax treatment. Do not promise cash where none is offered. Do not change a live campaign retrospectively except as permitted and clearly disclosed.

## 5. Fraud and cancellation
ShelfShare may review suspected abuse, but should give affected users an explanation and appeal route where practicable. Rewards may be withheld or reversed only under disclosed, lawful conditions and with a recorded reason.

## 6. Privacy and marketing
Do not upload contacts or send invitations to a person's address book without a separate lawful basis and required consent. Referral communications must comply with applicable telecom/marketing rules. Do not bundle marketing consent with participation.

## 7. Campaign schedule
The campaign-specific terms displayed before participation form part of these terms. Retain the version and hash shown to the participant.
$doc$,'UTF8'),'sha256'),'hex'),
 null,null,false,$doc$# Referral Programme Terms

> **DRAFT FOR INDIAN LEGAL COUNSEL — NOT APPROVED FOR PUBLICATION**
>
> Draft version: 0.1-draft
> Effective date: Not set. A date may be inserted only after legal approval and publication.
> Owner: [SHELFShare LEGAL ENTITY NAME]
> Last updated: 31 October 2026
>
> This is a product/legal-operations working draft, not legal advice, a legal opinion, or a representation that this text is enforceable or compliant. It must not be shown as an accepted live policy before Indian counsel has reviewed the actual product, entity, payment flows, data flows, tax position, consumer-law obligations and applicable rules.

## 1. Eligibility
The referral programme is available only to users who meet the eligibility conditions shown in the relevant campaign. Employees, agents, related accounts, self-referrals and fraud-linked accounts may be excluded under a clear published rule reviewed by counsel.

## 2. Referral attribution
A referral is attributed only through the approved link/code and platform record. Users must not create multiple accounts, use false identities, spam contacts, misrepresent rewards or manipulate bookings.

## 3. Qualifying activity
Each campaign must state the qualifying action, minimum eligible booking value, payment/return completion condition, attribution window, cap, expiry and exclusions. Merely signing up or submitting an unaccepted booking does not earn a reward unless the campaign explicitly says so.

## 4. Reward
Specify whether the reward is a discount, fee credit or non-cash benefit. State value, issue timing, expiry, redemption limits, refund/cancellation reversal and tax treatment. Do not promise cash where none is offered. Do not change a live campaign retrospectively except as permitted and clearly disclosed.

## 5. Fraud and cancellation
ShelfShare may review suspected abuse, but should give affected users an explanation and appeal route where practicable. Rewards may be withheld or reversed only under disclosed, lawful conditions and with a recorded reason.

## 6. Privacy and marketing
Do not upload contacts or send invitations to a person's address book without a separate lawful basis and required consent. Referral communications must comply with applicable telecom/marketing rules. Do not bundle marketing consent with participation.

## 7. Campaign schedule
The campaign-specific terms displayed before participation form part of these terms. Retain the version and hash shown to the participant.
$doc$,'draft',false,true
) on conflict(document_type,version) do nothing;

commit;

# India Compliance Research — ShelfShare
## Legal, Tax, Payments, Privacy and Operating Requirements

**Research cut-off:** 30 October 2026  
**Geography:** India; initial operational scope Hyderabad, Telangana and Bengaluru, Karnataka  
**Business model assumed:** A company-operated digital marketplace that connects individual book owners with readers for paid rental of lawfully owned physical books. The platform may collect rental consideration and platform commission through a third-party payment provider. It may wish to collect refundable security deposits, but no custody structure is approved.  
**Status:** Research and issue-spotting only. Not legal, tax, accounting or regulatory advice.

> **Critical:** The product is not cleared to operate merely because these requirements are documented. An Indian lawyer, CA, CS and the selected RBI-authorised payment provider must validate the structure before launch.

---

## 1. Executive summary

### 1.1 Likely operating structure
- The Consumer Protection (E-Commerce) Rules, 2020 define e-commerce entities broadly and Rule 4(1)(a) requires an e-commerce entity to be a company incorporated under the Companies Act or within the specified foreign-company categories. If ShelfShare operates the marketplace as an e-commerce entity, an Indian **Private Limited Company** is the practical default structure to evaluate.
- The marketplace must comply with E-Commerce Rules even if individual owners supply the books and the platform describes itself as an intermediary.
- ShelfShare should use an appropriately authorised payment aggregator with marketplace/vendor onboarding and compliant settlement functionality. It should not independently pool, hold or transfer customer funds as a payment aggregation business unless separately authorised and structured under RBI requirements.
- A refundable security deposit is not automatically an escrow, wallet or ordinary marketplace settlement. Do not implement platform custody until the provider and Indian counsel confirm a lawful and contractually supported structure.
- GST classification of commercial book rentals, marketplace commission and the platform's e-commerce-operator status needs a CA opinion. A public-library lending exemption should not be assumed to cover a private P2P commercial marketplace.
- For payments after 1 April 2026, the Income-tax Act, 2025 applies. The e-commerce operator withholding provision is now section 393(1), Table Sl. No. 8(v), not old section 194-O numbering. It provides 0.1% on gross amounts, subject to the specific individual/HUF exemption in section 393(4), Table Sl. No. 11.
- DPDP implementation is phased. Several core Act provisions and Rules 3, 5–16, 22 and 23 are scheduled to commence 18 months after 13 November 2025, i.e. 13 May 2027. Rule 4 and specified Act provisions commence one year after publication, i.e. 13 November 2026. ShelfShare should build to the complete framework now rather than wait for the final commencement dates.
- SMS OTP and bulk service/transactional messaging should be designed with TRAI TCCCPR 2018 and the telecom provider's DLT registration, header, template and consent requirements.
- A P2P platform with listings, reviews, chat and community content may be an intermediary under the IT Act. Safe-harbour protection is conditional on applicable due diligence and response obligations.
- Commercial rental of lawfully acquired physical books requires specialist copyright advice. Section 14 of the Copyright Act expressly gives commercial-rental rights for computer programs, cinematograph films and sound recordings, while the literary-work clause is worded differently. Do not assume the result for a paid physical-book rental marketplace without counsel's written opinion.

## 2. Business entity and incorporation

### 2.1 Applicable source and provision
**Consumer Protection (E-Commerce) Rules, 2020, Rule 4(1)(a):** An e-commerce entity must be a company incorporated under the Companies Act, 1956/2013, or fall within the specified foreign-company categories. Rule 4(1)(b) requires a resident nodal person of contact or alternate senior designated functionary.

Official government explanation: [PIB — Rules for E-Commerce Entities Under Consumer Protection Act (18 Sep 2020)](https://www.pib.gov.in/Pressreleaseshare.aspx?PRID=1656161). The notified Rules are available from the [Department of Consumer Affairs official E-Commerce Rules PDF](https://consumeraffairs.nic.in/sites/default/files/E%20commerce%20rules_0.pdf).

### 2.2 Applicability to ShelfShare
ShelfShare is intended to own/manage an electronic platform through which third-party owners offer rentals to readers. It is therefore likely to be an e-commerce entity and marketplace e-commerce entity. The company requirement should be treated as a launch gate, subject to counsel confirming the precise model.

### 2.3 Recommended structure
**Indian Private Limited Company** is the leading option to evaluate because:
- it aligns with Rule 4's company requirement for an e-commerce entity;
- it provides a familiar structure for equity ownership, investment, contracts and employee hiring;
- it can enter platform, payment-provider, SMS, identity-verification and venue-partner contracts;
- it supports clearer separation between company funds and user transaction records.

An LLP, partnership or proprietorship should not be assumed to satisfy Rule 4's company requirement for the e-commerce entity. A CS/lawyer should confirm the legal entity and operating structure before incorporation.

### 2.4 MCA incorporation route
MCA's SPICe+ linked filing process uses MCA V3. The MCA FAQs list SPICe+ Part A/Part B and linked forms including e-MOA, e-AOA, INC-9 and AGILE-PRO-S.

Official source: [MCA SPICe+ and Linked Filings FAQs](https://www.mca.gov.in/content/dam/mca/pdf/SPICEplus-and-linked-filings-FAQs-V3-20230122.pdf); [MCA portal](https://www.mca.gov.in/).

**CS review required:** name availability, objects clause, registered office, directors/subscribers, DIN/DSC, MOA/AOA, declarations, stamp duty, PAN/TAN, AGILE-PRO-S linked registrations, annual filings and ongoing Companies Act obligations.

**Recommended action:** incorporate ShelfShare's operating company only after checking name clearance, trademark strategy, founders/shareholding, registered office and intended business objects with a CS.

---

## 3. Consumer Protection Act and E-Commerce Rules

### 3.1 Applicable law
- Consumer Protection Act, 2019.
- Consumer Protection (E-Commerce) Rules, 2020, notified 23 July 2020, G.S.R. 462(E).
- CCPA guidelines/advisories, including Guidelines for Prevention and Regulation of Dark Patterns, 2023.
- Consumer Protection (E-Commerce) (Amendment) Rules, 2026, effective 1 January 2027.

Official sources:
- [Consumer Protection (E-Commerce) Rules, 2020 — Department of Consumer Affairs PDF](https://consumeraffairs.nic.in/sites/default/files/E%20commerce%20rules_0.pdf)
- [PIB — E-Commerce Rules 2020 overview](https://www.pib.gov.in/Pressreleaseshare.aspx?PRID=1656161)
- [CCPA Dark Patterns Guidelines, 2023 — official PDF](https://consumeraffairs.nic.in/sites/default/files/The%20Guidelines%20for%20Prevention%20and%20Regulation%20of%20Dark%20Patterns%2C%202023.pdf)
- [CCPA advisory on marketplace seller information](https://consumeraffairs.nic.in/sites/default/files/file-uploads/latestnews/Advisory%20CCPA.pdf)

### 3.2 2020 Rules — key provisions

| Provision | Legal requirement (high-level) | ShelfShare applicability / product consequence |
|---|---|---|
| Rule 2 | Scope includes goods/services bought or sold over digital/electronic networks and marketplace/inventory models | A digital P2P rental marketplace is likely in scope; rental is a service arrangement even though the underlying object is a physical book |
| Rule 4(1) | E-commerce entity company structure and resident nodal contact | Incorporate suitable company; appoint resident nodal functionary |
| Rule 4(2) | Prominent legal entity name, address, website and customer-care/grievance contact details | Public legal/contact page and accessible support details |
| Rule 4(3) | No unfair trade practices | Honest listing, pricing, cancellation, deposit and refund disclosures |
| Rule 4(4)–(5) | Grievance mechanism and officer; acknowledgement within 48 hours; redress within one month | Case/ticket system, published officer details, SLA monitoring |
| Rule 4(8) | Consumer cancellation charges cannot be imposed unless similar charges are borne by entity if it unilaterally cancels for any reason | Cancellation policy needs legal review for symmetry and unfairness |
| Rule 4(9) | Consent to purchase must be explicit and affirmative; no automatic/pre-ticked consent | Checkout and registration acceptance must be unselected by default |
| Rule 4(10) | Accepted refunds to be effected within reasonable or legally prescribed time | Refund ledger, provider SLA and user-visible status |
| Rule 5(1) | Marketplace seeking IT Act section 79 safe harbour must comply with section 79 and applicable intermediary due diligence | Platform must not rely on a blanket “we are only an intermediary” disclaimer |
| Rule 5(2) | Obtain seller undertaking that descriptions/images/content are accurate | Owner listing declaration and accuracy undertaking |
| Rule 5(3) | Disclose seller information, complaint ticket, return/refund/payment details, ranking parameters and other prescribed details | Show owner/seller identity and contact details as legally required; public display design needs privacy-law balancing; show refund terms and ranking logic |
| Rule 5(4) | Disclose differentiated treatment among sellers/items in terms | Explain paid promotion, ranking and other preferential treatment |
| Rule 5(5) | Maintain records to identify repeat infringing sellers in specified contexts | Repeat infringer tracking and copyright/trademark takedown workflow |
| Rule 6 | Seller duties include no unfair trade practices, written platform contract, grievance officer, truthful ads and prescribed listing/price/return information | Owner agreement, seller declarations, copy condition, full price breakup, refund and grievance information |

The detailed Rule 4/5/6 text should be checked against the latest amended consolidated Rules by counsel before launch. The Department's official PDF is the primary source; third-party legal explainer pages may help navigate but are not controlling.

### 3.3 CCPA and dark patterns
CCPA's Guidelines for Prevention and Regulation of Dark Patterns, 2023 took effect on publication (30 November 2023). They cover deceptive interface/UX patterns that impair consumer choice, including practices such as false urgency, basket sneaking, confirm shaming, forced action, subscription traps, interface interference, bait and switch, drip pricing, disguised ads, nagging, trick wording, SaaS billing and rogue malware.

**ShelfShare controls**
- Do not preselect deposits, add-ons, insurance/protection or marketing consent.
- Show all mandatory fees and deposit separately before payment.
- Do not hide cancellation/refund conditions until after checkout.
- Avoid false scarcity or fabricated demand counters.
- Make subscription cancellation and account deletion accessible if subscriptions are later introduced.
- Mark sponsored/promoted listings clearly.
- Keep price comparisons and discounts accurate.

The 2026 E-Commerce amendment additionally requires an annual dark-pattern self-audit and prominent compliance certificate, as summarised in the official PIB release below.

### 3.4 January 1, 2027 amendment readiness

The Department of Consumer Affairs' 2026 amendment is scheduled to come into force **1 January 2027**. The official PIB release dated 10 September 2026 describes the main changes.

Official source: [PIB — Government amends E-Commerce Rules; effective 1 January 2027](https://www.pib.gov.in/PressReleasePage.aspx?PRID=2308759).

Key changes described in the official release:
1. Every e-commerce entity must become a partner in the National Consumer Helpline convergence process.
2. Grievance officer must acknowledge a complaint within 48 hours, provide the complainant a copy of the complaint as recorded, and redress within one month.
3. Search results must not be manipulated in a misleading way or in a way adverse to relevance.
4. Sponsored listings must be clearly and prominently disclosed.
5. A price reduction announcement must show the reduced price and prior price; the prior price is the lowest price during the preceding 30 days.
6. Dark-pattern guidelines apply with annual self-audit and prominent compliance certificate.
7. Marketplace seller/product information must be disclosed to support informed decisions, including applicable returns/refunds, warranty, delivery and payment details.
8. Consumer information cannot be used for specified purposes without express and affirmative consent.
9. Bundled fees for services unrelated to the e-commerce platform are restricted, subject to specified membership/loyalty exception.
10. Importer and country-of-origin details apply where imported goods are offered.

**ShelfShare actions before 1 January 2027**
- Design grievance intake to generate and preserve a copy of the user's complaint.
- Prepare NCH partnership onboarding and internal escalation.
- Document organic ranking parameters and relative importance.
- Label sponsored/paid placements distinctly.
- Implement a price-history record sufficient to evidence the preceding 30-day lowest prior price when a discount is announced.
- Conduct and document a dark-pattern self-audit; prepare a compliance certificate process.
- Keep consumer-data use purposes and affirmative consent separate.
- Avoid unrelated bundled fees.

**Legal review required:** obtain and review the full Gazette notification G.S.R. 789(E), dated 9 September 2026, not only the PIB summary, before finalising the implementation checklist. A public transcription is available at [Gazette Tracker — 2026 amendment](https://gazettetracker.com/g/CG-DL-E-10092026-276125); verify it against the official Gazette record.

---

## 4. GST and marketplace TCS

### 4.1 Main legal framework
- Central Goods and Services Tax Act, 2017.
- Section 2(44) / 2(45): electronic commerce and electronic commerce operator definitions.
- Section 24: compulsory registration categories, including e-commerce operators and specified suppliers.
- Section 52: TCS by e-commerce operator on net value of taxable supplies made through it by other suppliers where consideration is collected by the operator.
- Relevant CGST/IGST/State GST notifications and GST Council changes.

Official sources:
- [CBIC GST Acts — Section 52](https://taxinformation.cbic.gov.in/content-page/explore-act/1000325/1000001)
- [CBIC Sectoral FAQs](https://cbic-gst.gov.in/hindi/sectoral-faq.html)
- [PIB — GST TCS rate reduction from 10 July 2024](https://www.pib.gov.in/PressReleasePage.aspx?PRID=2087659&lang=2&reg=48)
- [GST Portal](https://www.gst.gov.in/)

### 4.2 TCS rate
From 10 July 2024, the notified TCS rate under section 52 was reduced:
- Intra-State: 0.25% CGST + 0.25% SGST/UTGST = 0.5% total.
- Inter-State: 0.5% IGST.

Official government summary: PIB release on Notification No. 15/2024-Central Tax, Notification No. 01/2024-UT Tax and Notification No. 01/2024-Integrated Tax, all dated 10 July 2024.

**Important:** TCS is not a flat levy on every amount processed by a website. Section 52 applies to the net value of taxable supplies made through the ECO by other suppliers where consideration is collected by the ECO, subject to statutory conditions and exclusions. Refunds/returns and exempt/non-taxable supplies affect the calculation.

CBIC FAQs state that TCS does not arise on a supply that is not taxable. The FAQ also discusses exempt/zero-rated books as goods. That does not settle the tax treatment of **renting** a physical book.

### 4.3 Book rental GST classification — open CA opinion
A physical book sale and a paid rental of a physical book are different transactions. Do not assume a nil GST rate for printed books automatically applies to rental consideration.

The GST exemption schedule includes services of **public libraries** by way of lending books/publications/knowledge-enhancing content. ShelfShare is planned as a private commercial P2P marketplace; it must not assume it qualifies as a public library or that its owners qualify for that exemption.

Source: [CBIC Services Rate Booklet — public library lending entry](https://cbic-gst.gov.in/pdf/services-booklet-03July2017.pdf).

**CA must determine:**
- HSN/SAC classification and GST rate for a commercial physical-book rental by individual owners.
- Whether each owner is a supplier of taxable rental services and whether registration is required.
- Whether a particular statutory exemption applies.
- GST on ShelfShare's 10% marketplace commission/platform fee.
- Whether a convenience fee, delivery fee, late fee, damage recovery or cancellation fee is consideration for a taxable supply.
- Whether the security deposit is outside taxable value until appropriated, and the tax consequences if any part is forfeited/applied.
- Place-of-supply and intra-/inter-State classification.
- Whether the platform's ECO registration is compulsory under section 24(x) and state-wise registration requirements.
- Treatment of owners below threshold and any available exemption/notification for suppliers through an ECO.
- Invoicing, credit notes, returns, GSTR-8, TCS reconciliation and books/ledger treatment.

### 4.4 Registration and operational implication
CBIC FAQs explain that an e-commerce operator liable under the relevant provisions may require compulsory registration, and that suppliers making supplies through an ECO required to collect TCS can face registration consequences, subject to exceptions and notified relaxations.

**Do not configure GST based on a simple “books are nil-rated” assumption.** The commercial rental classification must be signed off by a CA before money is collected.

---

## 5. Income-tax withholding on owner payouts

### 5.1 Critical 2026 law change
The Income-tax Act, 2025 (Act 30 of 2025) came into force on **1 April 2026**, subject to its provisions. The Income Tax Department's transition FAQ says payments/credits on or after 1 April 2026 are governed by the new Act; old section references should not be quoted for new-period transactions.

Official sources:
- [Income-tax Act, 2025, as amended by Finance Act 2026](https://www.incometaxindia.gov.in/documents/d/guest/income_tax_act_2025_as_amended_by_fa_act_2026-pdf)
- [Income Tax Department — TDS compliance / transition FAQ](https://www.incometax.gov.in/iec/foportal/help/all-topics/e-filing-services/tds-compliance-faq)
- [Income Tax Department — Section 393](https://www.incometaxindia.gov.in/w/section-393-5)

### 5.2 E-commerce operator withholding
For payment/credit from 1 April 2026:
- Income-tax Act, 2025, section 393(1), Table Sl. No. 8(v), covers sums on account of sale of goods or provision of services by an e-commerce participant facilitated by an e-commerce operator.
- Rate: 0.1% of gross amount of sale/services.
- Table threshold: Nil.
- The operator is treated as person responsible for paying the participant.
- Direct payment by recipient to participant may also be deemed payment/credit by operator for this purpose.

A specific no-deduction condition appears in section 393(4), Table Sl. No. 11, where the participant is an individual/HUF, the gross amount during the tax year does not exceed ₹5,00,000, and the participant furnishes PAN or Aadhaar to the operator.

**Applicability:** If individual book owners are treated as resident e-commerce participants providing rental services through ShelfShare, section 393 may apply to owner payouts. CA must confirm the character of the rental transaction, gross amount base, tax-year aggregation, participant type, PAN/Aadhaar exception, timing, deposit treatment and any CBDT guidance.

### 5.3 Tax operations
Before launch, CA should configure:
- TAN and tax deduction/collection registrations as applicable.
- Owner PAN collection and validation.
- Individual/HUF/business classification.
- Annual gross payout aggregation and threshold monitoring.
- Deduction at earlier of credit/payment as applicable.
- TDS deposit, return filing, certificates, corrections and reconciliation under the Income-tax Act, 2025 and rules.
- Correct new section/table references in filings for post-1 April 2026 payments.
- Reconciliation between gross rental amount, platform commission, refunds, deposits and net payouts.

Do not use the old label “section 194-O” for post-1 April 2026 payment events without a transition explanation. It may be used historically for pre-1 April 2026 periods.

---

## 6. RBI payment aggregation, settlement and deposits

### 6.1 Applicable RBI framework
RBI's Guidelines on Regulation of Payment Aggregators and Payment Gateways (17 March 2020, updated 17 November 2020) distinguish:
- **Payment Aggregator (PA):** receives/pools customer payments and transfers them to merchants after a period.
- **Payment Gateway (PG):** provides technology to route/process payments without handling funds.

The RBI guidelines state non-bank PAs require RBI authorisation under the Payment and Settlement Systems Act, 2007. They require non-bank PAs to maintain customer funds in a scheduled commercial bank escrow account, with specified settlement, permitted credits/debits, merchant onboarding, reconciliation and grievance controls. The guidelines also state that marketplaces providing PA services had to separate that activity from marketplace business and seek authorisation if they wished to continue as PA.

Official source: [RBI — Guidelines on Regulation of Payment Aggregators and Payment Gateways, 17 March 2020](https://www.rbi.org.in/Scripts/NotificationUser.aspx?Id=11822).

### 6.2 ShelfShare recommended approach
**Use a third-party RBI-authorised PA** with an approved marketplace / sub-merchant / split-settlement product and written approval for the intended rental flow.

Do not:
- pool customer funds in ShelfShare's ordinary operating bank account for onward transfer to owners;
- create a database balance and call it a wallet;
- advertise an “escrow” unless funds are held in a legally valid and provider-approved escrow arrangement;
- use an ordinary payment gateway account as a substitute for marketplace settlement authorisation;
- hold owner proceeds or renter deposits outside the PA's approved product and settlement terms.

### 6.3 Due diligence questions for payment providers
Obtain written responses:
1. Are individual book owners eligible sub-merchants/marketplace sellers?
2. Can owners be onboarded with KYC and bank-account verification?
3. Can the provider split rent, platform commission, taxes and provider fees?
4. What are settlement triggers and permitted holds?
5. Can settlement be delayed until verified physical handover? Is that permitted by provider policy and RBI settlement framework?
6. Can a refundable security deposit be collected and held pending return? Under what exact account, legal and product structure?
7. Can a deposit remain held through an open damage/non-return dispute?
8. How are partial refunds, failed refunds, chargebacks and reversals handled?
9. Does the provider support UPI, cards and net banking for this model?
10. Does it support vendor payouts, failed payout recovery and reconciliation reports?
11. What are merchant categories, prohibited uses, reserves, rolling holds, transaction limits and fees?
12. Does the provider require ShelfShare to be the merchant of record or disclose the owner as supplier?
13. What is the treatment of deposit amounts in the provider's settlement and reporting files?
14. Does the provider expressly approve this P2P rental use case?

### 6.4 Deposit model — unresolved and high risk
A refundable security deposit is not automatically the same as a PA escrow account. The RBI PA escrow framework is for the authorised PA's payment aggregation and merchant settlement activity. ShelfShare must not assume it can use that framework to operate its own deposit custody or wallet.

**Possible structures to discuss, not recommendations until validated:**
- provider-managed deposit collection/hold/release product specifically approved for marketplace rentals;
- payment instrument authorisation/mandate model if available and contractually permitted;
- a separate regulated arrangement advised by counsel and accepted by the bank/provider.

Do not select a structure based only on competitor terms. Lumo and GoRent publicly describe holding deposits/escrow, but that does not establish ShelfShare's eligibility or legal authority.

**Release gate:** no deposit collection in production until written provider confirmation and Indian legal opinion.

---

## 7. DPDP Act and Rules — phased commencement

### 7.1 Official notifications
- Digital Personal Data Protection Act, 2023.
- Commencement notification S.O. 843(E), dated 13 November 2025.
- Digital Personal Data Protection Rules, 2025, G.S.R. 846(E), dated 13 November 2025.

Official Gazette sources:
- [DPDP Act commencement notification — MeitY PDF](https://www.meity.gov.in/static/uploads/2025/11/c56ceae6c383460ca69577428d36828b.pdf)
- [DPDP Rules 2025 — MeitY Gazette PDF](https://www.meity.gov.in/static/uploads/2025/11/53450e6e5dc0bfa85ebd78686cadad39.pdf)
- [MeitY Data Protection Framework](https://www.meity.gov.in/data-protection-framework)

### 7.2 Commencement timeline (calculated from Gazette publication 13 November 2025)

| Instrument / provision group | Commencement stated in notification | Calendar date | Position on 30 Oct 2026 |
|---|---|---|---|
| DPDP Act sections 1(2), 2, 18–26, 35, 38–43 and section 44(1),(3) | Publication date | 13 Nov 2025 | In force |
| DPDP Act section 6(9) and section 27(1)(d) | One year after publication | 13 Nov 2026 | Not yet in force on research cut-off; imminent |
| DPDP Act sections 3–5, section 6(1)–(8),(10), sections 7–17, section 27 except clause (d), sections 28–34, 36, 37 and section 44(2) | 18 months after publication | 13 May 2027 | Future commencement |
| DPDP Rules 1, 2 and 17–21 | Publication date | 13 Nov 2025 | In force |
| DPDP Rule 4 | One year after publication | 13 Nov 2026 | Not yet in force on research cut-off; imminent |
| DPDP Rules 3, 5–16, 22 and 23 | 18 months after publication | 13 May 2027 | Future commencement |

### 7.3 Practical obligations to design for
When the relevant substantive provisions commence, ShelfShare is likely to act as a Data Fiduciary for user account, identity, location, chat, rental, payment metadata and platform activity data. Vendors such as cloud hosting, SMS, identity and analytics providers may be Data Processors, depending on the actual arrangement.

Design now for:
- clear, standalone privacy notice with itemised data and specific purposes;
- valid consent where consent is the lawful basis, and a withdrawal mechanism as easy as giving consent;
- purpose limitation and data minimisation;
- Data Principal rights request intake and response workflow;
- grievance redressal;
- processor contracts and vendor security controls;
- reasonable security safeguards, encryption, access control, logging and backup;
- personal data breach response and notification;
- retention schedule and deletion/anonymisation;
- special treatment for children under 18;
- additional obligations if notified as a Significant Data Fiduciary.

### 7.4 ShelfShare data inventory requiring review
| Data | Why collected | Risk / control |
|---|---|---|
| Mobile number and OTP logs | Authentication | Rate limit; protect logs; do not store raw OTP longer than necessary |
| Live profile photo | Mandatory first registration per product spec | Separate from identity evidence; purpose notice, access and retention |
| Passport/PAN/DL evidence | Identity verification | Private encrypted storage; strict reviewer access; retention/deletion policy |
| Address/location/locality | Discovery, approved handover and eligibility | Do not publish residential address; minimise precision |
| Payment and payout metadata | Transactions, refunds and settlements | Provider tokenisation; no card/UPI PIN storage |
| Condition photographs | Handover, return and disputes | Restrict to parties/admins; evidence integrity and retention |
| Chat and community posts | User communication/community | Reporting, moderation, retention and lawful access procedures |
| Fraud/risk flags | Abuse prevention | Reviewable, private, limited access; avoid unreviewable automated adverse decisions |
| Support/grievance records | Consumer and privacy complaints | Role-based access, audit, response deadlines |

### 7.5 Children and age gate
The product's 18+ policy is helpful but does not itself prove age. DPDP child protections apply to a child under 18, including verifiable parental consent and restrictions on tracking/behavioural monitoring/targeted advertising, subject to statutory provisions and exemptions. Decide an age-verification method with counsel and avoid collecting children's data unnecessarily.

### 7.6 Breach notification and retention
The Rules contain breach-notification requirements including notice to the Board without delay and detailed information within 72 hours (subject to the rule's text and extension mechanism). The detailed rule set is scheduled for 13 May 2027. Do not treat that as a reason to postpone incident response planning.

The Rules also include retention provisions for specified categories of Data Fiduciaries and logs; applicability must be checked against the exact schedule/category. Do not apply a one-year or three-year retention period indiscriminately to every ShelfShare record.

---

## 8. TRAI DLT and SMS

### 8.1 Applicable framework
Telecom Commercial Communications Customer Preference Regulations (TCCCPR), 2018 and related directions / telecom access-provider Codes of Practice.

TRAI's official sender guidance says entities using telecom resources for bulk OTP, transactional, service or commercial messages must complete relevant Principal Entity registration, header assignment, content template registration, pass PE/header/content IDs through the delivery chain and register consent templates/acquire consent where applicable.

Official sources:
- [TRAI Advice to Senders](https://www.trai.gov.in/advice-to-senders)
- [TRAI TCCCPR 2018](https://www.trai.gov.in/tcccpr)

### 8.2 ShelfShare applicability
ShelfShare plans mobile OTP, booking notices, handover reminders, overdue reminders, payout notices and promotional messages. The SMS provider should confirm message category and DLT treatment for each template.

### 8.3 Implementation checklist
- Register ShelfShare as Principal Entity with the chosen access provider/telemarketer arrangement.
- Register headers and content templates.
- Ensure OTP, transactional, service and promotional templates are classified correctly.
- Obtain and record consent where required for promotional communications.
- Do not send promotional content in service templates to bypass consent/preferences.
- Maintain template versioning and delivery logs.
- Validate sender IDs and template variables before production.
- Contract with a DLT-capable SMS provider; provider onboarding does not remove ShelfShare's responsibilities as sender/PE.

---

## 9. IT Act, 2000 and Intermediary Guidelines

### 9.1 Applicability
ShelfShare may store or transmit user-generated listings, photos, chat, reviews, posts and comments. It may therefore qualify as an intermediary under section 2(1)(w) of the Information Technology Act, 2000 for some functions. Whether it qualifies for section 79 safe harbour and which provisions apply must be assessed by counsel based on its actual role and degree of control.

### 9.2 Relevant framework
- Information Technology Act, 2000, including sections 2(1)(w), 69A and 79.
- Information Technology (Intermediary Guidelines and Digital Media Ethics Code) Rules, 2021, as amended.

Official source: [MeitY — Intermediary Rules PDF (updated 28 Oct 2022)](https://www.meity.gov.in/static/uploads/2024/02/IT-Intermediary-Rules-2021-updated-on-28.10.2022.pdf).

### 9.3 General intermediary due diligence
Rule 3 includes obligations such as prominently publishing user rules, regulations, privacy policy and user agreement; informing users not to host/share specified unlawful content; and maintaining a grievance mechanism. Rule 3(2) provides grievance officer complaint handling requirements, including acknowledgement within 24 hours and resolution within 15 days for the general grievance mechanism, with special shorter timelines for specified content complaints.

### 9.4 ShelfShare actions
- Publish user terms, privacy policy, prohibited-content rules and reporting channels.
- Provide report listing/user/post/message controls.
- Operate a grievance officer process with rule-specific timers.
- Maintain records of notices, action taken, reasons and escalations.
- Have a repeat-infringer and copyright/trademark notice-and-takedown process.
- Preserve relevant evidence only under lawful and documented retention rules.
- Have a process for valid court/government orders.
- Do not promise immunity merely because content is user-generated.

**Threshold caveat:** Additional duties for significant social media intermediaries and other specialised classes should not be assumed to apply to a small marketplace at launch. Reassess if user scale, public communication functionality or regulatory classification changes.

---

## 10. Copyright and physical book rental

### 10.1 Relevant statutory provisions
Copyright Act, 1957:
- Section 13: copyright subsists in original literary, dramatic, musical and artistic works, films and sound recordings.
- Section 14(a): for literary works other than computer programs, the exclusive rights include reproduction, issuing copies to the public not being copies already in circulation, public performance/communication, translation and adaptation.
- Section 14(b), (d), (e): expressly refer to commercial rental of computer programs, cinematograph films and sound recordings.
- Section 51: infringement provisions include specified unauthorised acts and dealings with infringing copies.

Official sources:
- [Copyright Act — Chapter III / Section 14](https://copyright.gov.in/Copyright_Act_1957/chapter_iii.html)
- [Copyright Act — Chapter XI / Section 51](https://copyright.gov.in/Copyright_Act_1957/chapter_xi.html)
- [Copyright Act — definitions](https://copyright.gov.in/Copyright_Act_1957/chapter_i.html)

### 10.2 Issue requiring specialist opinion
Section 14(a) for literary works is worded differently from the express commercial-rental right for computer programs, films and sound recordings. This textual distinction is relevant, but it is not by itself a complete legal conclusion that every commercial rental of a lawfully acquired physical book is permitted or prohibited.

A lawyer specialising in copyright should provide a written opinion on:
- commercial rental of lawfully acquired physical copies by individuals;
- whether exhaustion/first-sale principles apply to repeated rental as distinct from resale;
- platform exposure as marketplace/intermediary;
- photocopied course packs, pirated copies and counterfeit editions;
- use of book cover images, publisher metadata and catalogue images;
- library or publisher licensing, if needed;
- notices, takedown, repeat-infringer handling and evidence preservation.

### 10.3 Operational controls
- Owner declares lawful ownership or authority to rent.
- Prohibit pirated photocopies, counterfeit copies and unauthorised reproductions.
- ISBN and cover image do not prove ownership.
- Prefer actual owner-captured photographs of the physical copy.
- Do not host scans, PDFs, excerpts or downloadable copies of books unless separately licensed.
- Provide IP complaint and takedown process.
- Preserve listing and seller evidence needed for repeat-infringer identification.

---

## 11. Local registrations — Telangana and Karnataka

### 11.1 Shops and Commercial Establishments
- Telangana: Telangana Shops and Establishments Act, 1988.
- Karnataka: Karnataka Shops and Commercial Establishments Act, 1961.

Official sources:
- [India Code — Telangana Shops and Establishments Act, 1988](https://www.indiacode.nic.in/indiacode/handle/123456789/8549?view_type=browse)
- [India Code — Karnataka Shops and Commercial Establishments Act, 1961](https://www.indiacode.nic.in/handle/123456789/7609?locale=hi)
- [Telangana State Services — Labour Department registration](https://www.telangana.gov.in/services/state-services/)

**Applicability:** If ShelfShare has an office, branch, support centre or other covered commercial establishment in Hyderabad or Bengaluru, state Shops and Establishments registration and employment-condition obligations may apply. Exact coverage, exemptions, deadlines, employee thresholds and online process must be checked with the respective state Labour Department/CS. A purely remote/virtual operation still needs fact-specific review.

### 11.2 Other local and employment registrations
Depending on actual premises, employees and activities, evaluate:
- municipal trade licence / local-body permissions;
- signage, fire, occupancy and building-use approvals for physical premises;
- professional tax registration and payroll deductions;
- EPFO/ESI and labour registrations when statutory thresholds/conditions are met;
- POSH Internal Committee requirements when employee threshold is met;
- contract labour registrations/licences if outsourced staffing arrangement triggers them;
- GST registrations in states where required;
- local handover-venue agreements and safety approvals.

Do not assume the platform needs a municipal trade licence merely because it has an app; do not assume no licence is needed if it maintains a physical office or operational centre.

### 11.3 NSWS
Use the National Single Window System's Know Your Approvals module to identify central/state approvals based on actual business details. NSWS itself says its list is indicative and not a legal opinion or substitute for independent advice.

Official sources:
- [NSWS Know Your Approvals](https://www.nsws.gov.in/portal/investor-decision)
- [NSWS About](https://www.nsws.gov.in/about-us)

---

## 12. Trademark and brand protection

### 12.1 Applicable framework
Trade Marks Act, 1999; Trade Marks Rules, 2017; Nice Classification.

Official sources:
- [IP India — Search Existing Trademarks](https://ipindia.gov.in/trade-marks-before-you-apply-search-existing-trademarks)
- [IP India — Trademark basics](https://ipindia.gov.in/page-content/basics-of-trademarks)
- [IP India — Filing process](https://ipindia.gov.in/application-workflow/trademark-filing-process)
- [IP India — Official fees](https://ipindia.gov.in/pages/trade-marks/learn/forms-and-official-fees)
- [IP India — Trade Marks Rules, 2017](https://ipindia.gov.in/tm-rules-2017)

### 12.2 ShelfShare classes to investigate
A trademark agent should confirm descriptions and classes. Potentially relevant service classes:
- Class 35: online marketplace, advertising, business/intermediary services.
- Class 41: education, library and book-related cultural/reading services.
- Class 42: SaaS, software/platform development and technology services.
- Class 9: downloadable mobile application/software, if the mark is used for downloadable app goods.

These are candidate classes, not a final classification opinion. The correct scope depends on the actual services and goods offered.

### 12.3 Recommended process
1. Search exact “ShelfShare”, phonetic variants, spacing/plural variants and similar marks.
2. Search relevant classes and broader classes where conflicts may arise.
3. Search company names, domains, app stores and common-law use.
4. Obtain trademark agent clearance opinion.
5. File word mark before or alongside logo mark as advised.
6. Use TM-A; track examination, objection, publication and opposition.
7. Keep evidence of use and renewal dates.

IP India states registered marks are valid for 10 years from application and renewable for further 10-year periods. Current e-filing fee shown by IP India is ₹4,500 per mark per class for individual/startup/small enterprise and ₹9,000 for others; verify current fee at filing.

**Important:** This research does not confirm that “ShelfShare” is available or registrable. A live official trademark search and professional clearance are still required.

---

## 13. Consumer grievance, National Consumer Helpline and support

### 13.1 E-Commerce Rules
Publish the marketplace grievance officer's name, designation and contact details; provide a grievance mechanism, ticket tracking and seller information required by the Rules. The 2020 Rules state acknowledgement within 48 hours and redress within one month. The 2027 amendment requires a copy of the complaint as recorded and NCH convergence partnership.

### 13.2 Separate IT Rules timeline
If intermediary rules apply, the general Rule 3 grievance process includes acknowledgement within 24 hours and resolution within 15 days, with specified content complaint timelines. Do not collapse the Consumer Rules and IT Rules into one SLA; build separate legal timers and escalation routes.

### 13.3 ShelfShare support system
- Complaint intake with ticket ID and timestamp.
- Distinguish consumer grievance, privacy request, payment dispute, book-condition dispute, safety report and IP complaint.
- Provide named grievance contact.
- Store copy of complaint and response history.
- Track statutory and internal SLA separately.
- Escalate to NCH and relevant consumer forum process as advised.
- Publish support hours and emergency/safety contact process.

---

## 14. Summary of mandatory vs recommended controls

| Topic | Mandatory / likely statutory | Recommended product control |
|---|---|---|
| Entity | Company form under E-Commerce Rules if ShelfShare is an e-commerce entity | Private Limited structure, CS-led incorporation |
| E-commerce disclosures | Legal name/address/contact/grievance details and marketplace seller/payment/refund/ranking disclosures | Dedicated compliance footer and listing transparency |
| Consumer grievances | Rule-based grievance officer and timelines | Ticketing, case analytics, escalation matrix |
| 2027 readiness | NCH partnership, complaint copy, search/sponsored listing/pricing/dark-pattern duties per amended rules | Pre-launch self-audit and product review gate |
| GST | ECO registration/TCS and tax on taxable supplies as applicable | CA-approved tax engine and seller tax classification |
| Income tax | Section 393 withholding if applicable to owner payouts | PAN/Aadhaar and annual participant payout ledger |
| Payments | RBI PA requirements apply if platform performs PA functions | Use authorised PA and prohibit direct fund pooling |
| Deposit | No automatic authority to hold deposits; provider/legal model required | Disable deposits until written approvals |
| DPDP | Phased obligations according to commencement notifications | Implement full framework early |
| SMS | TCCCPR/DLT sender and template requirements for applicable bulk SMS | Centralised template registry and consent mapping |
| IT Act | Intermediary due diligence/safe harbour conditions if applicable | Reporting, takedown, audit and repeat infringer workflow |
| Copyright | Copyright Act rights and infringement controls | Written opinion on commercial physical-book rental |
| Local | State establishment and local approvals if factual triggers are met | NSWS KYA and state counsel review |
| Trademark | No universal obligation to register before launch; rights and infringement risks apply | File after clearance, secure domains/handles |

---

## 15. Professional sign-off required before launch

### Indian lawyer
- E-Commerce Rules applicability and 2027 amendment interpretation.
- Contract structure between ShelfShare, owners and readers.
- Consumer cancellation/refund/damage policies.
- Deposit custody and PA/provider terms.
- IT Act intermediary status and safe harbour.
- Copyright opinion on commercial rental of lawfully acquired physical books.
- DPDP notices, consent, data rights, breach and retention.
- Local licences and grievance obligations.

### Chartered Accountant (CA)
- GST registration and classification of book rental, platform commission, fees, deposits, late fees and damage recoveries.
- Section 52 GST TCS applicability/rate/calculation.
- Income-tax Act 2025 section 393 withholding on owner payouts.
- Tax invoices, credit notes, GSTR filings, TDS returns, TAN and reconciliation.
- Accounting treatment of deposits, refunds, commission, owner payable and provider settlements.

### Company Secretary (CS)
- Company form and incorporation.
- MCA SPICe+ filing, MOA/AOA objects and statutory registers.
- Board/shareholder approvals, annual filings and corporate governance.
- Registered office and state establishment registrations.
- Related-party, founder shareholding and future investment documentation.

### Payment provider / banking counsel
- Written approval for marketplace P2P rental category.
- Individual owner onboarding and settlement.
- Deposit hold/collection/release and disputes.
- Refunds, chargebacks, payout reserves and reconciliation.
- Confirmation that ShelfShare is not independently performing regulated PA activity.

---

## 16. Research limitations

- This is a desk-research snapshot as at 30 October 2026, not a legal opinion.
- The 2026 E-Commerce Amendment is summarised from the official PIB release; obtain and verify the full Gazette notification G.S.R. 789(E) before implementation.
- GST rate/classification for private book rental was not conclusively determined; CA opinion is mandatory.
- No provider has been selected or approved for ShelfShare's deposit workflow.
- No state-specific legal opinion has been obtained for Hyderabad/Bengaluru premises, venue partnerships or employment setup.
- No trademark search has been run for ShelfShare; availability is unconfirmed.

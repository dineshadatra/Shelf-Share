# Damage and Compensation Policy — Draft for Professional Review

**Status: Draft only. Not legally approved.**
This is a proposed customer-facing policy framework. All time windows, valuation parameters, caps and payment mechanics marked `TBD` require business approval and review by an Indian lawyer, CA and payment provider.

## 1. Purpose

Protect Owners' physical copies while treating Readers fairly. Distinguish normal wear and tear, pre-existing damage, accidental damage, severe damage and non-return. No arbitrary or automatic deduction is permitted.

## 2. Condition evidence

Before collection:
- Owner provides actual photos of front cover, back cover, spine, representative pages and existing defects.
- Reader reviews and acknowledges the evidence at collection.
- Evidence is timestamped, linked to the physical copy and booking, and stored with integrity metadata.

At return:
- Both parties capture comparable photos.
- Record page count/completeness where relevant, stains, tears, water damage, missing pages, writing/highlighting, binding and cover condition.
- Existing damage must not be claimed again.
- Preserve original files and hashes; no destructive editing.

## 3. Normal wear and tear

Examples that may qualify as normal wear (subject to baseline condition and context):
- minor handling marks;
- slight edge/corner wear consistent with ordinary reading;
- modest page ageing;
- minor spine softening from ordinary use without structural failure.

Examples that are not automatically normal:
- water/liquid damage;
- missing or torn pages;
- detached covers/binding;
- substantial stains, mould or smoke damage;
- unauthorised writing, highlighting or cutting;
- missing inserts/material parts;
- damage that makes the book materially less usable or unsafe.

These examples are not exhaustive. Admin must assess actual condition and evidence.

## 4. Claim submission

- Owner submits a claim within `DAMAGE_CLAIM_WINDOW` (TBD) after verified return/inspection.
- Claim includes reason, before/after evidence, description, requested remedy and any repair/replacement estimate.
- System checks booking, return event and claim window.
- Reader receives notice and `READER_RESPONSE_WINDOW` (TBD) to submit counter-evidence.
- No automatic deposit deduction on claim creation.

## 5. Assessment factors

Authorised reviewer considers:
1. Pre-rental condition and recorded defects.
2. Quality/comparability of before/after evidence.
3. Actual extent and location of damage.
4. Whether normal wear and tear.
5. Repairability and reasonable repair cost.
6. Current availability and cost of same edition or equivalent replacement.
7. Original purchase price where evidenced.
8. Age, edition, rarity and prior condition.
9. Whether book remains usable.
10. Contribution of either party and any handover/transport incident evidence.

Do not automatically charge original cover price or full replacement value for every claim. Do not treat a new edition as equivalent without reason.

## 6. Possible outcomes

- No damage / normal wear: claim rejected; no compensation.
- Minor repairable damage: reasonable evidenced repair cost, subject to policy cap (TBD).
- Material but repairable damage: assessed repair cost and any substantiated loss in value, avoiding double recovery.
- Irreparable damage: fair current replacement cost for same/equivalent copy, adjusted for age and pre-rental condition; cap and depreciation method require approval.
- Missing book/non-return: use separate non-return process, not a damage shortcut.
- Insufficient evidence: claim rejected or returned for additional evidence; do not presume liability.

The policy must define whether Owner may keep a damaged book and receive compensation, or must return/transfer it. Avoid double recovery.

## 7. Decision and appeal

- Admin reviewer records evidence, factors, calculation and reasons.
- Parties receive decision and appeal route.
- Appeal reviewed by a different authorised reviewer where feasible.
- Appeal window `DAMAGE_APPEAL_WINDOW` (TBD).
- No reviewer with conflict of interest.
- Preserve all submissions and decision history.

## 8. Collection of approved compensation

- Do not debit a saved payment method without valid authority.
- Deposit application is possible only if the provider/legal custody model permits and user accepted valid terms.
- Otherwise use a separately approved on-platform payment request or civil recovery process as advised by counsel.
- Do not make arbitrary deductions from owner payout.
- Any refund of undisputed deposit balance follows provider-confirmed process.

## 9. Fraud and misuse

Repeated false claims, evidence manipulation or harassment may be referred to trust/safety review. Risk signals must be reviewable and not publicly exposed. Do not automatically suspend permanently without human review and appeal route.

## 10. Policy parameters requiring approval

`DAMAGE_CLAIM_WINDOW`, `READER_RESPONSE_WINDOW`, `DAMAGE_APPEAL_WINDOW`, repair-cost cap, replacement valuation method, depreciation method, reviewer SLA, evidence minimums, deposit application permissions and refund timing are all TBD.

**Professional review:** Indian consumer-law lawyer; CA for tax/accounting; payment provider for deposit/compensation flow.

import test from "node:test";
import assert from "node:assert/strict";
import {
  assessDueState,
  calculateLateFeeProposal,
  assertProportionalCompensation,
  assertClaimCanBeSubmitted,
  cancellationDisposition,
  shouldPreserveActiveRentalsOnSuspension,
  assertCaseParticipant,
  assertValidDamageDecision,
} from "../../functions/_shared/rental-ops.ts";

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
const DUE = Date.UTC(2026, 0, 1, 12, 0, 0);

test("rental remains active before due time", () => {
  assert.deepEqual(assessDueState(DUE, DUE - 1, 24), {
    state: "active", graceEndsAt: DUE + DAY, overdueDays: 0,
  });
});

test("grace period is not overdue", () => {
  assert.equal(assessDueState(DUE, DUE + 24 * HOUR, 24).state, "due");
});

test("overdue starts only after grace period", () => {
  assert.deepEqual(assessDueState(DUE, DUE + 24 * HOUR + 1, 24), {
    state: "overdue", graceEndsAt: DUE + DAY, overdueDays: 1,
  });
});

test("overdue day count rounds partial days up", () => {
  assert.equal(assessDueState(DUE, DUE + DAY + DAY + 1, 24).overdueDays, 2);
});

test("invalid grace period is rejected", () => {
  assert.throws(() => assessDueState(DUE, DUE, 169), /invalid_grace_period/u);
});

test("late fee proposals are capped at remaining policy maximum", () => {
  assert.equal(calculateLateFeeProposal(500n, 1200n, 900n), 300n);
  assert.equal(calculateLateFeeProposal(500n, 1200n, 1200n), 0n);
});

test("negative late fee values are rejected", () => {
  assert.throws(() => calculateLateFeeProposal(-1n, 100n, 0n), /negative_late_fee_amount/u);
});

test("damage compensation cannot exceed the documented claim", () => {
  assertValidDamageDecision(2500n, 2000n);
  assert.throws(() => assertValidDamageDecision(2500n, 2501n), /decision_exceeds_claimed_amount/u);
});

test("decision requires evidence, respondent opportunity and a reason", () => {
  assertProportionalCompensation({
    requestedPaise: 5000n, approvedPaise: 2000n,
    hasCaseEvidence: true, respondentHadOpportunity: true,
    reason: "Repair estimate and before/after condition evidence support this proportionate amount.",
  });
  assert.throws(() => assertProportionalCompensation({
    requestedPaise: 5000n, approvedPaise: 2000n,
    hasCaseEvidence: false, respondentHadOpportunity: true, reason: "A sufficiently long decision explanation is present.",
  }), /case_evidence_required/u);
});

test("lost book claim cannot be filed before grace expires", () => {
  assert.throws(() => assertClaimCanBeSubmitted({
    category: "lost_book", now: DUE + DAY, dueAt: DUE, gracePeriodHours: 24,
    hasCollectionBaseline: true, hasReturnedBook: false,
  }), /grace_period_not_expired/u);
});

test("minor damage claim requires collection baseline evidence", () => {
  assert.throws(() => assertClaimCanBeSubmitted({
    category: "minor_damage", now: DUE + DAY, dueAt: DUE, gracePeriodHours: 24,
    hasCollectionBaseline: false, hasReturnedBook: true,
  }), /initial_condition_evidence_required/u);
});

test("normal wear has no compensable claim category", () => {
  assert.throws(() => assertClaimCanBeSubmitted({
    category: "normal_wear", now: DUE + DAY, dueAt: DUE, gracePeriodHours: 24,
    hasCollectionBaseline: true, hasReturnedBook: true,
  }), /invalid_claim_category/u);
});

test("cancellation with captured payment requires refund review", () => {
  assert.equal(cancellationDisposition("captured"), "cancel_with_refund_review");
  assert.equal(cancellationDisposition("none"), "cancel_without_refund_review");
});

test("suspension does not erase active-rental obligations", () => {
  assert.equal(shouldPreserveActiveRentalsOnSuspension(3), true);
});

test("only booking participants can respond to a rental case", () => {
  assertCaseParticipant("reader-1", "reader-1", "owner-1");
  assert.throws(() => assertCaseParticipant("other-user", "reader-1", "owner-1"), /rental_case_participant_required/u);
});

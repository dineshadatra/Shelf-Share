export type RentalLifecycleState =
  | "scheduled"
  | "active"
  | "due"
  | "overdue"
  | "return_requested"
  | "returned"
  | "completed"
  | "cancelled"
  | "disputed";

export type ClaimCategory =
  | "minor_damage"
  | "major_damage"
  | "missing_pages"
  | "water_damage"
  | "lost_book"
  | "non_return"
  | "wrong_book_returned";

export interface DueAssessment {
  state: "active" | "due" | "overdue";
  graceEndsAt: number;
  overdueDays: number;
}

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

export function assessDueState(dueAt: number, now: number, gracePeriodHours: number): DueAssessment {
  if (!Number.isFinite(dueAt) || !Number.isFinite(now) || dueAt <= 0 || now <= 0) {
    throw new Error("invalid_rental_timestamps");
  }
  if (!Number.isInteger(gracePeriodHours) || gracePeriodHours < 0 || gracePeriodHours > 168) {
    throw new Error("invalid_grace_period");
  }
  const graceEndsAt = dueAt + gracePeriodHours * HOUR_MS;
  if (now < dueAt) return { state: "active", graceEndsAt, overdueDays: 0 };
  if (now <= graceEndsAt) return { state: "due", graceEndsAt, overdueDays: 0 };
  return {
    state: "overdue",
    graceEndsAt,
    overdueDays: Math.max(1, Math.ceil((now - graceEndsAt) / DAY_MS)),
  };
}

export function calculateLateFeeProposal(
  dailyFeePaise: bigint,
  maximumFeePaise: bigint,
  alreadyProposedPaise: bigint,
): bigint {
  if (dailyFeePaise < 0n || maximumFeePaise < 0n || alreadyProposedPaise < 0n) {
    throw new Error("negative_late_fee_amount");
  }
  if (dailyFeePaise === 0n || maximumFeePaise === 0n) return 0n;
  const remaining = maximumFeePaise > alreadyProposedPaise
    ? maximumFeePaise - alreadyProposedPaise
    : 0n;
  return dailyFeePaise < remaining ? dailyFeePaise : remaining;
}

export function assertProportionalCompensation(input: {
  requestedPaise: bigint;
  approvedPaise: bigint;
  hasCaseEvidence: boolean;
  respondentHadOpportunity: boolean;
  reason: string;
}): void {
  if (input.requestedPaise < 0n || input.approvedPaise < 0n || input.approvedPaise > input.requestedPaise) {
    throw new Error("compensation_exceeds_documented_claim");
  }
  if (!input.hasCaseEvidence) throw new Error("case_evidence_required");
  if (!input.respondentHadOpportunity) throw new Error("respondent_response_window_not_complete");
  if (input.reason.trim().length < 30) throw new Error("reasoned_decision_required");
}

export function assertClaimCanBeSubmitted(input: {
  category: ClaimCategory;
  now: number;
  dueAt: number | null;
  gracePeriodHours: number;
  hasCollectionBaseline: boolean;
  hasReturnedBook: boolean;
}): void {
  const allowedCategories: ClaimCategory[] = [
    "minor_damage", "major_damage", "missing_pages", "water_damage",
    "lost_book", "non_return", "wrong_book_returned",
  ];
  if (!allowedCategories.includes(input.category)) throw new Error("invalid_claim_category");
  const needsBaseline = ["minor_damage", "major_damage", "missing_pages", "water_damage", "wrong_book_returned"].includes(input.category);
  if (needsBaseline && !input.hasCollectionBaseline) throw new Error("initial_condition_evidence_required");
  if (input.category === "non_return" || input.category === "lost_book") {
    if (input.dueAt === null) throw new Error("rental_due_date_required");
    const graceEndsAt = input.dueAt + input.gracePeriodHours * HOUR_MS;
    if (input.now <= graceEndsAt) throw new Error("grace_period_not_expired");
  }
  if (input.category === "wrong_book_returned" && !input.hasReturnedBook) {
    throw new Error("returned_item_evidence_required");
  }
}

export function cancellationDisposition(paymentState: "none" | "captured" | "partially_refunded" | "refunded"):
  "cancel_without_refund_review" | "cancel_with_refund_review" {
  return paymentState === "none" ? "cancel_without_refund_review" : "cancel_with_refund_review";
}

export function shouldPreserveActiveRentalsOnSuspension(activeRentalCount: number): boolean {
  if (!Number.isInteger(activeRentalCount) || activeRentalCount < 0) {
    throw new Error("invalid_active_rental_count");
  }
  // Suspension blocks new transactions but does not erase existing contracts or safety obligations.
  return true;
}

export function assertCaseParticipant(actorId: string, readerId: string, ownerId: string): void {
  if (!actorId || (actorId !== readerId && actorId !== ownerId)) {
    throw new Error("rental_case_participant_required");
  }
}

export function assertValidDamageDecision(requestedPaise: bigint, approvedPaise: bigint): void {
  if (requestedPaise < 0n || approvedPaise < 0n || approvedPaise > requestedPaise) {
    throw new Error("decision_exceeds_claimed_amount");
  }
}

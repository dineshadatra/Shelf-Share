import { requireUser } from "../_shared/supabase.ts";
import { assertIdempotencyKey } from "../_shared/domain.ts";
import { errorResponse, jsonResponse, readJson, requirePost } from "../_shared/http.ts";

interface Body {
  action: string;
  approve?: boolean;
  bookingId?: string;
  requestId?: string;
  caseId?: string;
  caseType?: "claim" | "dispute";
  userId?: string;
  conversationId?: string;
  targetType?: "user" | "book_copy" | "booking" | "handover_location";
  targetId?: string;
  reportType?: string;
  severity?: string;
  status?: string;
  reason?: string;
  reasonCode?: string;
  description?: string;
  newStartAt?: string;
  newEndAt?: string;
  newDueAt?: string;
  mutedUntil?: string | null;
  grounds?: string;
  message?: string;
  claimCategory?: string;
  requestedCompensationPaise?: string;
  approvedCompensationPaise?: string;
  decisionCode?: string;
  decisionReason?: string;
  outcome?: string;
  revisedCompensationPaise?: string;
  expiresAt?: string | null;
  idempotencyKey?: string;
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const moneyPattern = /^\d{1,14}$/u;
const datePattern = /^\d{4}-\d{2}-\d{2}T/u;

function uuid(value: string | undefined, label: string): string {
  if (!value || !uuidPattern.test(value)) throw new Error(`invalid_${label}`);
  return value;
}

function requiredText(value: string | undefined, label: string, minimum = 3, maximum = 4000): string {
  const normalized = value?.trim();
  if (!normalized || normalized.length < minimum || normalized.length > maximum) throw new Error(`invalid_${label}`);
  return normalized;
}

function money(value: string | undefined, label: string): string {
  if (!value || !moneyPattern.test(value)) throw new Error(`invalid_${label}`);
  return value;
}

function dateTime(value: string | undefined, label: string): string {
  if (!value || !datePattern.test(value) || Number.isNaN(Date.parse(value))) throw new Error(`invalid_${label}`);
  return new Date(value).toISOString();
}

Deno.serve(async (request) => {
  const methodError = requirePost(request);
  if (methodError) return methodError;

  try {
    const { user, client } = await requireUser(request);
    const body = await readJson<Body>(request);
    if (!body.action) return jsonResponse({ error: "action_required" }, 400);

    let rpcName: string;
    let rpcArgs: Record<string, unknown>;

    switch (body.action) {
      case "dashboard": {
        const { data, error } = await client.rpc("get_my_active_rentals");
        if (error) throw error;
        return jsonResponse({ rentals: data ?? [] });
      }
      case "early-return":
        rpcName = "request_rental_early_return";
        rpcArgs = {
          p_booking_id: uuid(body.bookingId, "booking_id"),
          p_reason: requiredText(body.reason, "reason", 5, 1000),
          p_idempotency_key: assertIdempotencyKey(body.idempotencyKey),
        };
        break;
      case "extension-request":
        rpcName = "request_rental_extension";
        rpcArgs = {
          p_booking_id: uuid(body.bookingId, "booking_id"),
          p_requested_due_at: dateTime(body.newDueAt, "new_due_at"),
          p_reason: requiredText(body.reason, "reason", 5, 1000),
          p_idempotency_key: assertIdempotencyKey(body.idempotencyKey),
        };
        break;
      case "extension-response":
        rpcName = "respond_rental_extension";
        if (typeof body.approve !== "boolean") throw new Error("approve_boolean_required");
        rpcArgs = {
          p_request_id: uuid(body.requestId, "request_id"),
          p_approve: body.approve,
          p_reason: requiredText(body.reason, "reason", 5, 1000),
        };
        break;
      case "reschedule-request":
        rpcName = "request_rental_reschedule";
        rpcArgs = {
          p_booking_id: uuid(body.bookingId, "booking_id"),
          p_new_start_at: dateTime(body.newStartAt, "new_start_at"),
          p_new_end_at: dateTime(body.newEndAt, "new_end_at"),
          p_reason: requiredText(body.reason, "reason", 5, 1000),
          p_idempotency_key: assertIdempotencyKey(body.idempotencyKey),
        };
        break;
      case "reschedule-response":
        rpcName = "respond_rental_reschedule";
        if (typeof body.approve !== "boolean") throw new Error("approve_boolean_required");
        rpcArgs = {
          p_request_id: uuid(body.requestId, "request_id"),
          p_approve: body.approve,
          p_reason: requiredText(body.reason, "reason", 5, 1000),
        };
        break;
      case "cancel":
        rpcName = "request_booking_cancellation";
        rpcArgs = {
          p_booking_id: uuid(body.bookingId, "booking_id"),
          p_reason_code: requiredText(body.reasonCode, "reason_code", 3, 100),
          p_description: requiredText(body.description, "description", 10, 2000),
          p_idempotency_key: assertIdempotencyKey(body.idempotencyKey),
        };
        break;
      case "no-show":
        rpcName = "report_rental_no_show";
        rpcArgs = {
          p_booking_id: uuid(body.bookingId, "booking_id"),
          p_incident_type: body.reportType,
          p_description: requiredText(body.description, "description", 10, 2000),
        };
        break;
      case "damage-claim":
        rpcName = "submit_rental_damage_claim";
        rpcArgs = {
          p_booking_id: uuid(body.bookingId, "booking_id"),
          p_claim_category: body.claimCategory,
          p_description: requiredText(body.description, "description", 30, 4000),
          p_requested_compensation_paise: money(body.requestedCompensationPaise ?? "0", "requested_compensation_paise"),
        };
        break;
      case "case-message":
        rpcName = "post_rental_case_message";
        rpcArgs = {
          p_case_type: body.caseType,
          p_case_id: uuid(body.caseId, "case_id"),
          p_body: requiredText(body.message, "message", 1, 5000),
        };
        break;
      case "appeal":
        rpcName = "submit_rental_appeal";
        rpcArgs = {
          p_case_type: body.caseType,
          p_case_id: uuid(body.caseId, "case_id"),
          p_grounds: requiredText(body.grounds, "grounds", 20, 4000),
        };
        break;
      case "decide-claim":
        rpcName = "decide_rental_damage_claim";
        rpcArgs = {
          p_claim_id: uuid(body.caseId, "claim_id"),
          p_approved_compensation_paise: money(body.approvedCompensationPaise ?? "0", "approved_compensation_paise"),
          p_decision_code: requiredText(body.decisionCode, "decision_code", 3, 100),
          p_decision_reason: requiredText(body.decisionReason, "decision_reason", 30, 4000),
        };
        break;
      case "decide-appeal":
        rpcName = "decide_rental_appeal";
        rpcArgs = {
          p_appeal_id: uuid(body.caseId, "appeal_id"),
          p_outcome: body.outcome,
          p_decision_code: requiredText(body.decisionCode, "decision_code", 3, 100),
          p_decision_reason: requiredText(body.decisionReason, "decision_reason", 30, 4000),
          p_revised_compensation_paise: body.revisedCompensationPaise === undefined
            ? null : money(body.revisedCompensationPaise, "revised_compensation_paise"),
        };
        break;
      case "report-safety":
        rpcName = "report_rental_safety_issue";
        rpcArgs = {
          p_target_type: body.targetType,
          p_target_id: uuid(body.targetId, "target_id"),
          p_report_type: body.reportType,
          p_description: requiredText(body.description, "description", 10, 4000),
          p_severity: body.severity ?? "medium",
        };
        break;
      case "block-user":
        rpcName = "block_marketplace_user";
        rpcArgs = {
          p_blocked_user_id: uuid(body.userId, "user_id"),
          p_reason: body.reason?.slice(0, 100) ?? null,
        };
        break;
      case "mute-chat":
        rpcName = "set_chat_mute";
        rpcArgs = {
          p_conversation_id: uuid(body.conversationId, "conversation_id"),
          p_muted_until: body.mutedUntil ? dateTime(body.mutedUntil, "muted_until") : null,
          p_reason: body.reason?.slice(0, 500) ?? null,
        };
        break;
      case "safety-ticket":
        rpcName = "create_safety_support_ticket";
        rpcArgs = {
          p_subject: requiredText(body.reason, "subject", 5, 200),
          p_description: requiredText(body.description, "description", 20, 4000),
          p_booking_id: body.bookingId ? uuid(body.bookingId, "booking_id") : null,
        };
        break;
      case "suspend-user":
        rpcName = "admin_set_user_account_status";
        rpcArgs = {
          p_user_id: uuid(body.userId, "user_id"),
          p_new_status: body.status,
          p_reason_code: requiredText(body.reasonCode, "reason_code", 3, 100),
          p_reason: requiredText(body.reason, "reason", 20, 2000),
          p_expires_at: body.expiresAt ? dateTime(body.expiresAt, "expires_at") : null,
        };
        break;
      case "resolve-safety-report":
        rpcName = "admin_resolve_rental_safety_report";
        rpcArgs = {
          p_report_id: uuid(body.caseId, "report_id"),
          p_status: body.status,
          p_resolution_code: requiredText(body.decisionCode, "resolution_code", 3, 100),
          p_resolution_reason: requiredText(body.decisionReason, "resolution_reason", 20, 2000),
        };
        break;
      default:
        return jsonResponse({ error: "unsupported_action" }, 400);
    }

    const { data, error } = await client.rpc(rpcName, rpcArgs);
    if (error) throw error;
    return jsonResponse({ ok: true, action: body.action, result: data ?? null, actorId: user.id });
  } catch (error) {
    const message = error instanceof Error ? error.message : "unexpected_error";
    const status = message.includes("authentication") || message.includes("session") ? 401
      : message.includes("permission") || message.includes("participant") || message.includes("Only the") ? 403
      : message.includes("conflict") || message.includes("already") || message.includes("not enabled") ? 409 : 400;
    return errorResponse(error, status);
  }
});

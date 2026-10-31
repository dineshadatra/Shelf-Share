import { createAdminClient, requireUser } from "../_shared/supabase.ts";
import { assertIdempotencyKey } from "../_shared/domain.ts";
import { errorResponse, jsonResponse, readJson, requirePost } from "../_shared/http.ts";

interface Body { paymentId: string; amountPaise: string; reasonCode: string }
Deno.serve(async (request) => {
  const methodError = requirePost(request);
  if (methodError) return methodError;
  try {
    const { user } = await requireUser(request);
    const body = await readJson<Body>(request);
    const idempotencyKey = assertIdempotencyKey(request.headers.get("idempotency-key"));
    if (!body.paymentId || !/^\d+$/u.test(body.amountPaise) || BigInt(body.amountPaise) <= 0n
      || !body.reasonCode || body.reasonCode.trim().length < 4) return jsonResponse({ error: "invalid_refund_request" }, 400);
    const admin = createAdminClient();
    const { data: roles, error: roleError } = await admin.from("user_roles")
      .select("role").eq("user_id", user.id).is("revoked_at", null);
    if (roleError) throw new Error("finance_role_lookup_failed");
    if (!(roles ?? []).some((row) => ["finance_operator", "admin", "super_admin"].includes(row.role))) {
      return jsonResponse({ error: "finance_permission_required" }, 403);
    }
    const { data, error } = await admin.rpc("create_finance_refund", {
      p_actor_id: user.id,
      p_payment_id: body.paymentId,
      p_amount_paise: body.amountPaise,
      p_reason_code: body.reasonCode.trim().slice(0, 100),
      p_idempotency_key: idempotencyKey,
    });
    if (error) return jsonResponse({ error: "refund_not_eligible_or_exceeds_unrefunded_capture" }, 409);
    return jsonResponse({ refundId: data, status: "REQUESTED_PROVIDER_CONFIRMATION_REQUIRED" }, 202);
  } catch (error) {
    const message = error instanceof Error ? error.message : "unexpected_error";
    return errorResponse(error, message.includes("authentication") ? 401 : 400);
  }
});

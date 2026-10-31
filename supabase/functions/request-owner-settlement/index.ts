import { requireUser } from "../_shared/supabase.ts";
import { assertIdempotencyKey } from "../_shared/domain.ts";
import { errorResponse, jsonResponse, readJson, requirePost } from "../_shared/http.ts";

interface Body { earningId: string }
Deno.serve(async (request) => {
  const methodError = requirePost(request);
  if (methodError) return methodError;
  try {
    const { client } = await requireUser(request);
    const body = await readJson<Body>(request);
    const idempotencyKey = assertIdempotencyKey(request.headers.get("idempotency-key"));
    const providerCode = Deno.env.get("PAYMENT_PROVIDER_CODE");
    if (!providerCode || !body.earningId) return jsonResponse({ error: "approved_provider_and_earning_required" }, 503);
    const { data, error } = await client.rpc("create_owner_payout_request", {
      p_earning_id: body.earningId,
      p_provider: providerCode,
      p_idempotency_key: idempotencyKey,
    });
    if (error) return jsonResponse({ error: "owner_settlement_not_eligible_or_provider_not_approved" }, 409);
    return jsonResponse({ payoutId: data, status: "PENDING_PROVIDER_CONFIRMATION" }, 202);
  } catch (error) {
    const message = error instanceof Error ? error.message : "unexpected_error";
    return errorResponse(error, message.includes("authentication") ? 401 : 400);
  }
});

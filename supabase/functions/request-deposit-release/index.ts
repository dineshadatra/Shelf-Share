import { requireUser } from "../_shared/supabase.ts";
import { assertIdempotencyKey } from "../_shared/domain.ts";
import { errorResponse, jsonResponse, readJson, requirePost } from "../_shared/http.ts";

interface Body { depositId: string }
Deno.serve(async (request) => {
  const methodError = requirePost(request);
  if (methodError) return methodError;
  try {
    const { client } = await requireUser(request);
    const body = await readJson<Body>(request);
    const idempotencyKey = assertIdempotencyKey(request.headers.get("idempotency-key"));
    if (!body.depositId) return jsonResponse({ error: "deposit_id_required" }, 400);
    const { data, error } = await client.rpc("request_deposit_release", {
      p_deposit_id: body.depositId,
      p_idempotency_key: idempotencyKey,
    });
    if (error) return jsonResponse({ error: "deposit_release_not_eligible_or_feature_disabled" }, 409);
    return jsonResponse({ releaseRequestId: data, status: "REQUESTED_PROVIDER_CONFIRMATION_REQUIRED" }, 202);
  } catch (error) {
    const message = error instanceof Error ? error.message : "unexpected_error";
    return errorResponse(error, message.includes("authentication") ? 401 : 400);
  }
});

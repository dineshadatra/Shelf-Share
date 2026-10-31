import { createAdminClient } from "../_shared/supabase.ts";
import { errorResponse, jsonResponse, requirePost } from "../_shared/http.ts";

function constantTimeEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) mismatch |= a[i] ^ b[i];
  return mismatch === 0;
}

Deno.serve(async (request) => {
  const methodError = requirePost(request);
  if (methodError) return methodError;
  const expected = Deno.env.get("RENTAL_SWEEP_SECRET");
  const supplied = request.headers.get("x-rental-sweep-secret") ?? "";
  if (!expected || new TextEncoder().encode(expected).length < 32 || !constantTimeEqual(expected, supplied)) {
    return jsonResponse({ error: "scheduler_authentication_failed" }, 401);
  }
  try {
    const admin = createAdminClient();
    const { data, error } = await admin.rpc("run_rental_due_sweep", { p_now: new Date().toISOString() });
    if (error) throw error;
    return jsonResponse({ ok: true, result: data });
  } catch (error) {
    return errorResponse(error, 500);
  }
});

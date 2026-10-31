import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function response(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff"
  }});
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return response({ error: "method_not_allowed" }, 405);
  const configuredSecret = Deno.env.get("PRIVACY_ERASURE_WORKER_SECRET");
  const suppliedSecret = request.headers.get("x-privacy-worker-secret") ?? "";
  if (!configuredSecret || configuredSecret.length < 32 ||
      suppliedSecret.length !== configuredSecret.length ||
      !timingSafeEqual(suppliedSecret, configuredSecret)) {
    return response({ error: "worker_authentication_failed" }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return response({ error: "server_configuration_missing" }, 500);
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  const { data: jobs, error: claimError } = await admin.rpc("claim_privacy_erasure_jobs", { p_limit: 20 });
  if (claimError) return response({ error: "erasure_job_claim_failed" }, 500);
  let completed = 0;
  let failed = 0;
  for (const job of jobs ?? []) {
    try {
      if (job.job_type === "identity_document_delete") {
        if (job.storage_bucket !== "identity-private" || !job.object_key ||
            job.object_key.startsWith("/") || job.object_key.includes("..")) {
          throw new Error("invalid_identity_object_reference");
        }
        const { error: storageError } = await admin.storage.from("identity-private").remove([job.object_key]);
        if (storageError) throw new Error("private_storage_delete_failed");
      } else if (job.job_type !== "profile_anonymise") {
        throw new Error("unsupported_erasure_job_type");
      }

      const { error: completeError } = await admin.rpc("complete_privacy_erasure_job", {
        p_job_id: job.id, p_success: true, p_error_code: null
      });
      if (completeError) throw new Error("erasure_job_completion_failed");
      completed++;
    } catch (error) {
      const code = error instanceof Error ? error.message : "erasure_job_failed";
      await admin.rpc("complete_privacy_erasure_job", {
        p_job_id: job.id, p_success: false, p_error_code: code
      });
      failed++;
    }
  }
  return response({ claimed: (jobs ?? []).length, completed, failed }, 200);
});

function timingSafeEqual(a: string, b: string): boolean {
  let mismatch = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let i = 0; i < length; i++) mismatch |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0);
  return mismatch === 0;
}

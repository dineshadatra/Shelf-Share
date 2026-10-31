import { createAdminClient } from "../_shared/supabase.ts";
import { errorResponse, jsonResponse, requirePost } from "../_shared/http.ts";
import { renderApprovedSmsTemplate, type DltVariablePolicy } from "../_shared/notifications.ts";

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
  const expected = Deno.env.get("NOTIFICATION_DISPATCH_SECRET") ?? "";
  const supplied = request.headers.get("x-notification-dispatch-secret") ?? "";
  if (expected.length < 32 || !constantTimeEqual(expected, supplied)) {
    return jsonResponse({ error: "scheduler_authentication_failed" }, 401);
  }

  const gatewayUrl = Deno.env.get("SMS_GATEWAY_URL") ?? "";
  const gatewayKey = Deno.env.get("SMS_GATEWAY_API_KEY") ?? "";
  if (!gatewayUrl.startsWith("https://") || !gatewayKey) {
    return jsonResponse({ error: "sms_provider_not_configured" }, 503);
  }

  try {
    const admin = createAdminClient();
    const { data: jobs, error } = await admin.rpc("claim_notification_delivery_jobs", { p_limit: 50 });
    if (error) throw error;
    let sent = 0;
    let failed = 0;

    for (const job of jobs ?? []) {
      try {
        const { data: sendable, error: sendableError } = await admin.rpc("notification_delivery_job_sendable", {
          p_job_id: job.job_id
        });
        if (sendableError) throw sendableError;
        if (sendable !== true) {
          await admin.from("notification_delivery_jobs").update({
            status: "cancelled", claimed_at: null, updated_at: new Date().toISOString()
          }).eq("id", job.job_id).eq("status", "processing");
          await admin.from("notifications").update({ status: "cancelled" })
            .eq("id", job.notification_id).eq("status", "queued");
          continue;
        }
        const { data: template, error: templateError } = await admin.from("notification_templates")
          .select("dlt_variable_policy,sms_enabled,sms_content_template_id,sms_header")
          .eq("template_key", job.template_key).single();
        if (templateError || !template?.sms_enabled ||
            template.sms_content_template_id !== job.sms_content_template_id ||
            template.sms_header !== job.sms_header) {
          throw new Error("sms_template_configuration_mismatch");
        }
        const policy = template.dlt_variable_policy as DltVariablePolicy[];
        const message = renderApprovedSmsTemplate(job.sms_body_template, job.payload ?? {}, policy);
        const response = await fetch(gatewayUrl, {
          method: "POST",
          headers: {
            "Authorization": "Bearer " + gatewayKey,
            "Content-Type": "application/json",
            "Accept": "application/json"
          },
          body: JSON.stringify({
            to: job.phone,
            message,
            senderHeader: job.sms_header,
            principalEntityId: job.principal_entity_id,
            telemarketerChain: job.telemarketer_chain,
            contentTemplateId: job.sms_content_template_id,
            clientReference: job.job_id
          }),
          signal: AbortSignal.timeout(15000)
        });
        const result = await response.json().catch(() => ({}));
        if (!response.ok || !result?.providerReference) {
          throw new Error("sms_provider_rejected_request");
        }
        const cost = Number.isSafeInteger(result.costPaise) && result.costPaise > 0
          ? result.costPaise as number : null;
        const { error: completeError } = await admin.rpc("complete_notification_delivery", {
          p_job_id: job.job_id,
          p_status: "sent",
          p_provider_reference: String(result.providerReference).slice(0, 200),
          p_error_code: null,
          p_cost_paise: cost
        });
        if (completeError) throw completeError;
        sent++;
      } catch (error) {
        const { error: completeError } = await admin.rpc("complete_notification_delivery", {
          p_job_id: job.job_id,
          p_status: "failed",
          p_provider_reference: null,
          p_error_code: error instanceof Error ? error.message.slice(0, 100) : "provider_error",
          p_cost_paise: null
        });
        if (completeError) throw completeError;
        failed++;
      }
    }
    return jsonResponse({ ok: true, claimed: jobs?.length ?? 0, sent, failed });
  } catch (error) {
    return errorResponse(error, 500);
  }
});

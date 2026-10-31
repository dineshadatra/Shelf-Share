import { createAdminClient } from "../_shared/supabase.ts";
import { assertProviderPaymentMatches, providerEventForState } from "../_shared/domain.ts";
import { sha256Hex } from "../_shared/crypto.ts";
import { getPaymentProvider } from "../_shared/provider-registry.ts";
import { errorResponse, jsonResponse } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);
  try {
    const providerCode = new URL(request.url).searchParams.get("provider");
    if (!providerCode) return jsonResponse({ error: "provider_required" }, 400);
    const provider = getPaymentProvider(providerCode);
    const rawBody = new Uint8Array(await request.arrayBuffer());
    if (rawBody.length === 0 || rawBody.length > 1_000_000) return jsonResponse({ error: "invalid_webhook_size" }, 400);

    // Adapter verifies signature over the exact raw request bytes.
    const event = await provider.verifyWebhook(rawBody, request.headers);
    if (!event.providerEventId || !event.merchantReference || !event.providerPaymentId) {
      return jsonResponse({ error: "invalid_verified_event_envelope" }, 400);
    }
    const admin = createAdminClient();
    const { data: payment, error: paymentError } = await admin.from("payments")
      .select("id,booking_id,provider,merchant_reference,provider_payment_id,amount_paise,currency,status")
      .eq("provider", providerCode).eq("merchant_reference", event.merchantReference).maybeSingle();
    if (paymentError) throw new Error("payment_lookup_failed");
    if (!payment) return jsonResponse({ error: "unknown_merchant_reference" }, 404);

    // A valid signature is necessary but not sufficient: fetch canonical provider state.
    const snapshot = await provider.fetchPaymentStatus(event.providerPaymentId);
    assertProviderPaymentMatches({
      amountPaise: payment.amount_paise,
      currency: payment.currency,
      merchantReference: payment.merchant_reference,
    }, {
      amountPaise: snapshot.amountPaise,
      currency: snapshot.currency,
      merchantReference: snapshot.merchantReference,
    });
    if (snapshot.providerPaymentId !== event.providerPaymentId) throw new Error("provider_payment_reference_mismatch");

    const normalizedEventType = providerEventForState(snapshot.state);
    if (!normalizedEventType) return jsonResponse({ accepted: true, pending: true, paymentId: payment.id }, 202);
    if (snapshot.state === "CHARGEBACK_OPEN" && !snapshot.disputeReference && !event.disputeReference) {
      throw new Error("provider_dispute_reference_required");
    }

    const payloadSha256 = await sha256Hex(rawBody);
    const { data: result, error: applyError } = await admin.rpc("apply_verified_payment_event", {
      p_provider: providerCode,
      p_event_id: event.providerEventId,
      p_payment_id: payment.id,
      p_event_type: normalizedEventType,
      p_amount_paise: snapshot.amountPaise,
      p_currency: "INR",
      p_provider_payment_id: snapshot.providerPaymentId,
      p_payload_sha256: payloadSha256,
      p_provider_dispute_reference: snapshot.disputeReference ?? event.disputeReference ?? null,
    });
    if (applyError) throw new Error("verified_payment_event_application_failed");
    return jsonResponse({ accepted: true, result }, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : "unexpected_error";
    const status = message.includes("adapter_not_implemented") || message.includes("provider_not_configured") ? 503
      : message.includes("mismatch") || message.includes("invalid") ? 400 : 500;
    return errorResponse(error, status);
  }
});

import { createAdminClient, requireUser } from "../_shared/supabase.ts";
import { assertIdempotencyKey } from "../_shared/domain.ts";
import { getPaymentProvider } from "../_shared/provider-registry.ts";
import { errorResponse, jsonResponse, readJson, requirePost } from "../_shared/http.ts";

interface Body { bookingId: string }

Deno.serve(async (request) => {
  const methodError = requirePost(request);
  if (methodError) return methodError;

  try {
    const { user } = await requireUser(request);
    const body = await readJson<Body>(request);
    if (!body.bookingId || !/^[0-9a-f-]{36}$/iu.test(body.bookingId)) return jsonResponse({ error: "invalid_booking_id" }, 400);
    const idempotencyKey = assertIdempotencyKey(request.headers.get("idempotency-key"));
    const providerCode = Deno.env.get("PAYMENT_PROVIDER_CODE");
    const provider = getPaymentProvider(providerCode);
    const admin = createAdminClient();

    const { data: booking, error: bookingError } = await admin.from("bookings")
      .select("id,reader_id,owner_id,status,rent_subtotal_paise,tax_paise,deposit_required_paise,city_id")
      .eq("id", body.bookingId).maybeSingle();
    if (bookingError) throw new Error("booking_lookup_failed");
    if (!booking || booking.reader_id !== user.id) return jsonResponse({ error: "booking_not_found" }, 404);
    if (booking.status !== "owner_accepted" && booking.status !== "payment_pending") {
      return jsonResponse({ error: "booking_not_ready_for_payment" }, 409);
    }
    if (BigInt(String(booking.deposit_required_paise ?? 0)) > 0n) {
      return jsonResponse({ error: "security_deposit_disabled_pending_written_provider_and_legal_approval" }, 409);
    }

    const { data: approvals, error: approvalError } = await admin.from("payment_provider_approvals")
      .select("provider_code,enabled_for_rent,expires_at,provider_approval_reference,marketplace_approval_reference,legal_approval_reference,accounting_approval_reference")
      .eq("provider_code", providerCode ?? "").eq("enabled_for_rent", true);
    if (approvalError) throw new Error("provider_approval_lookup_failed");
    const approval = (approvals ?? []).find((row) => !row.expires_at || new Date(row.expires_at).getTime() > Date.now());
    if (!approval || !approval.provider_approval_reference || !approval.marketplace_approval_reference
      || !approval.legal_approval_reference || !approval.accounting_approval_reference) {
      return jsonResponse({ error: "provider_marketplace_approval_missing" }, 503);
    }

    // A retry must reuse the same payment row and merchant reference.
    const { data: existing, error: existingError } = await admin.from("payments")
      .select("id,booking_id,payer_id,provider,idempotency_key,merchant_reference,amount_paise,currency,status,provider_order_id")
      .eq("idempotency_key", idempotencyKey).maybeSingle();
    if (existingError) throw new Error("payment_attempt_lookup_failed");
    if (existing && (existing.booking_id !== booking.id || existing.payer_id !== user.id || existing.provider !== providerCode)) {
      return jsonResponse({ error: "idempotency_key_conflict" }, 409);
    }

    let payment = existing;
    if (!payment) {
      const merchantReference = `SS-RENT-${crypto.randomUUID()}`;
      const { data: createdId, error: createError } = await admin.rpc("begin_booking_payment", {
        p_booking_id: booking.id,
        p_provider: providerCode,
        p_idempotency_key: idempotencyKey,
        p_merchant_reference: merchantReference,
      });
      if (createError || !createdId) throw new Error("payment_attempt_creation_failed");
      const { data: createdPayment, error: readError } = await admin.from("payments")
        .select("id,booking_id,payer_id,provider,idempotency_key,merchant_reference,amount_paise,currency,status,provider_order_id")
        .eq("id", createdId).single();
      if (readError || !createdPayment) throw new Error("payment_attempt_readback_failed");
      payment = createdPayment;
    }

    if (payment.status === "captured") {
      return jsonResponse({ paymentId: payment.id, status: "CAPTURED", verified: true });
    }
    const intent = await provider.createPaymentIntent({
      merchantReference: payment.merchant_reference,
      amountPaise: String(payment.amount_paise),
      currency: "INR",
      idempotencyKey: `shelfshare-payment-${payment.id}`,
      customerReference: user.id,
      metadata: { bookingId: booking.id, paymentId: payment.id, purpose: "RENTAL" },
    });

    const { error: updateError } = await admin.from("payments").update({
      provider_order_id: intent.providerOrderId,
      provider_status: "intent_created",
    }).eq("id", payment.id);
    if (updateError) {
      // The provider idempotency key makes a retry safe. Do not assert payment success.
      return jsonResponse({ error: "provider_intent_created_but_local_update_failed", paymentId: payment.id, retryable: true }, 503);
    }

    return jsonResponse({
      paymentId: payment.id,
      status: "PENDING_PROVIDER_CONFIRMATION",
      checkoutUrl: intent.checkoutUrl,
      verified: false,
    }, 201);
  } catch (error) {
    const message = error instanceof Error ? error.message : "unexpected_error";
    const status = message.includes("authentication") || message.includes("session") ? 401
      : message.includes("adapter_not_implemented") || message.includes("provider_not_configured") ? 503
      : message.includes("idempotency") ? 400 : 500;
    return errorResponse(error, status);
  }
});

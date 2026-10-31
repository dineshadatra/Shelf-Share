import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { getMarketplacePaymentProvider } from "../_shared/payment-provider.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const workerSecret = Deno.env.get("MARKETPLACE_WORKER_SECRET") ?? "";
const appOrigin = Deno.env.get("APP_ORIGIN") ?? "";

const json = (status: number, body: Record<string, unknown>) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
});
const str = (value: unknown) => typeof value === "string" ? value : "";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });
  if (workerSecret.length < 32 || req.headers.get("x-marketplace-worker-secret") !== workerSecret) {
    return json(401, { error: "Invalid worker credential" });
  }

  const service = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  let limit = 20;
  try {
    const body = await req.json();
    if (Number.isInteger(body?.limit)) limit = Math.max(1, Math.min(50, body.limit));
  } catch { /* Use the safe default batch size. */ }

  const { data: events, error: claimError } = await service.rpc("claim_marketplace_outbox_events", {
    p_limit: limit, p_lease_seconds: 120,
  });
  if (claimError) return json(500, { error: "Could not claim marketplace outbox events" });

  let completed = 0;
  let retried = 0;
  const results: Array<{ event_id: string; status: string; error?: string }> = [];

  for (const event of events ?? []) {
    const eventId = str(event.event_id);
    const eventType = str(event.event_type);
    const payload = (event.payload ?? {}) as Record<string, unknown>;
    const providerCode = str(payload.provider).toLowerCase();

    try {
      const adapter = getMarketplacePaymentProvider(providerCode);
      if (!adapter) throw new Error("provider_adapter_unavailable");

      if (eventType === "payment_intent_requested") {
        const paymentId = str(payload.payment_id);
        const { data: payment, error } = await service.from("payments")
          .select("id,booking_id,payer_id,provider,idempotency_key,merchant_reference,amount_paise,currency")
          .eq("id", paymentId).maybeSingle();
        if (error || !payment) throw new Error("payment_not_found");
        if (payment.provider !== adapter.providerCode) throw new Error("provider_mismatch");
        const { data: booking } = await service.from("bookings").select("owner_id").eq("id", payment.booking_id).maybeSingle();
        const { data: approval } = await service.from("payment_provider_approvals").select("id,enabled_for_rent")
          .eq("provider_code", providerCode).eq("enabled_for_rent", true)
          .eq("marketplace_model", "peer_to_peer_physical_book_rental").maybeSingle();
        if (!booking || !approval) throw new Error("marketplace_approval_or_booking_missing");
        const { data: vendor } = await service.from("provider_vendor_accounts").select("provider_vendor_reference")
          .eq("provider_approval_id", approval.id).eq("user_id", booking.owner_id).eq("kyc_status", "verified").maybeSingle();
        if (!vendor) throw new Error("owner_vendor_kyc_missing");
        const intent = await adapter.createPaymentIntent({
          merchantReference: payment.merchant_reference,
          idempotencyKey: payment.idempotency_key,
          amountPaise: payment.amount_paise,
          currency: payment.currency,
          payerReference: payment.payer_id,
          vendorReference: vendor.provider_vendor_reference,
          metadata: { bookingId: payment.booking_id, paymentId: payment.id },
          returnUrl: appOrigin + "/rentals",
        });
        const { error: updateError } = await service.from("payments").update({
          provider_order_id: intent.providerOrderReference,
          provider_status: intent.status,
          provider_checkout_url: intent.checkoutUrl,
        }).eq("id", payment.id);
        if (updateError) throw new Error("payment_reference_persist_failed");
      } else if (eventType === "refund_after_unreserved_capture" || eventType === "refund_after_inventory_conflict") {
        const paymentId = str(payload.payment_id);
        if (!paymentId) throw new Error("late_capture_payment_id_missing");
        const reason = eventType === "refund_after_unreserved_capture"
          ? "captured_without_active_reservation"
          : "captured_inventory_conflict";
        const { error } = await service.rpc("queue_captured_payment_refund", {
          p_payment_id: paymentId,
          p_reason_code: reason,
          p_idempotency_key: "auto-capture-refund:" + str(event.idempotency_key),
        });
        if (error) throw new Error("late_capture_refund_queue_failed");
        // The queued refund_requested event is processed by a subsequent worker
        // pass. This event only guarantees that a refund obligation now exists.
      } else if (eventType === "refund_requested") {
        const refundId = str(payload.refund_id);
        const { data: refund } = await service.from("refunds").select("id,booking_id,payment_id,provider,idempotency_key,amount_paise,reason_code,provider_refund_id")
          .eq("id", refundId).maybeSingle();
        if (!refund) throw new Error("refund_not_found");
        const { data: payment } = await service.from("payments").select("provider_payment_id,merchant_reference")
          .eq("id", refund.payment_id).maybeSingle();
        if (!payment) throw new Error("refund_payment_not_found");
        const result = await adapter.createRefund({
          providerPaymentReference: payment.provider_payment_id ?? "",
          merchantReference: payment.merchant_reference ?? refund.payment_id,
          refundReference: refund.id,
          idempotencyKey: refund.idempotency_key,
          amountPaise: refund.amount_paise,
          currency: "INR",
          reasonCode: refund.reason_code,
        });
        const { error } = await service.rpc("attach_refund_provider_reference", {
          p_refund_id: refund.id, p_provider_reference: result.providerRefundReference,
        });
        if (error) throw new Error("refund_reference_persist_failed");
      } else if (eventType === "owner_payout_requested") {
        const payoutId = str(payload.payout_id);
        const { data: payout } = await service.from("payouts").select("id,owner_earning_id,owner_id,provider,idempotency_key,amount_paise,currency,provider_transfer_id")
          .eq("id", payoutId).maybeSingle();
        if (!payout) throw new Error("payout_not_found");
        const { data: approval } = await service.from("payment_provider_approvals").select("id,enabled_for_rent")
          .eq("provider_code", providerCode).eq("enabled_for_rent", true).maybeSingle();
        const { data: vendor } = await service.from("provider_vendor_accounts").select("provider_vendor_reference")
          .eq("provider_approval_id", approval?.id ?? "").eq("user_id", payout.owner_id).eq("kyc_status", "verified").maybeSingle();
        if (!vendor) throw new Error("owner_vendor_kyc_missing");
        const result = await adapter.createTransfer({
          vendorReference: vendor.provider_vendor_reference,
          merchantReference: payout.id,
          transferReference: payout.id,
          idempotencyKey: payout.idempotency_key,
          amountPaise: payout.amount_paise,
          currency: payout.currency,
        });
        const { error } = await service.rpc("attach_payout_provider_reference", {
          p_payout_id: payout.id, p_provider_reference: result.providerTransferReference,
        });
        if (error) throw new Error("payout_reference_persist_failed");
      } else if (eventType === "deposit_collection_requested") {
        const depositId = str(payload.deposit_id);
        const { data: deposit } = await service.from("deposits")
          .select("id,booking_id,payer_id,provider,provider_reference,amount_paise,currency,policy_version,custody_descriptor,status,feature_enabled_at_creation")
          .eq("id", depositId).maybeSingle();
        if (!deposit || !deposit.feature_enabled_at_creation || deposit.status !== "collection_pending") {
          throw new Error("deposit_collection_not_eligible");
        }
        const result = await adapter.createDepositHold({
          payerReference: deposit.payer_id,
          merchantReference: "SSDEP-" + deposit.id,
          depositReference: deposit.id,
          idempotencyKey: "deposit-hold-" + deposit.id,
          amountPaise: deposit.amount_paise,
          currency: deposit.currency,
          custodyDescriptor: deposit.custody_descriptor ?? "",
          policyVersion: deposit.policy_version ?? "",
        });
        const { error } = await service.rpc("attach_deposit_provider_reference", {
          p_deposit_id: deposit.id, p_provider_reference: result.providerDepositReference,
        });
        if (error) throw new Error("deposit_reference_persist_failed");
      } else if (eventType === "deposit_release_requested") {
        const depositId = str(event.aggregate_id);
        const requestId = str(payload.release_request_id ?? payload.request_id);
        const { data: deposit } = await service.from("deposits").select("provider_reference,status,provider")
          .eq("id", depositId).maybeSingle();
        const { data: release } = await service.from("deposit_release_requests").select("id,amount_paise,idempotency_key,status")
          .eq("id", requestId).maybeSingle();
        if (!deposit?.provider_reference || !release || release.status === "released") throw new Error("deposit_release_not_eligible");
        const result = await adapter.releaseDeposit(deposit.provider_reference, release.amount_paise, release.idempotency_key);
        if (result.amountPaise !== release.amount_paise || result.currency !== "INR") throw new Error("deposit_release_amount_mismatch");
      } else if (eventType === "deposit_dispute_hold_requested") {
        const depositId = str(payload.deposit_id);
        const disputeId = str(payload.dispute_id);
        const { data: deposit } = await service.from("deposits").select("provider_reference,status,provider,amount_paise")
          .eq("id", depositId).maybeSingle();
        if (!deposit?.provider_reference || deposit.status !== "claim_hold_pending" || !disputeId) {
          throw new Error("deposit_dispute_hold_not_eligible");
        }
        const result = await adapter.holdDepositForDispute(
          deposit.provider_reference, disputeId, str(event.idempotency_key),
        );
        if (result.amountPaise !== deposit.amount_paise || result.currency !== "INR") {
          throw new Error("deposit_dispute_hold_amount_mismatch");
        }
      } else if (eventType === "deposit_claim_application_requested") {
        const depositId = str(event.aggregate_id);
        const claimId = str(payload.claim_id);
        const { data: deposit } = await service.from("deposits").select("provider_reference,status,provider")
          .eq("id", depositId).maybeSingle();
        const { data: claim } = await service.from("deposit_claims").select("decision_amount_paise,status")
          .eq("id", claimId).maybeSingle();
        if (!deposit?.provider_reference || !claim || claim.status !== "approved" || !claim.decision_amount_paise) {
          throw new Error("deposit_claim_not_eligible");
        }
        const result = await adapter.applyDepositClaim(
          deposit.provider_reference, claim.decision_amount_paise, claimId, str(event.idempotency_key),
        );
        if (result.currency !== "INR") throw new Error("deposit_claim_currency_mismatch");
      } else {
        throw new Error("unsupported_outbox_event");
      }

      const { error: finishError } = await service.rpc("finish_marketplace_outbox_event", {
        p_event_id: eventId, p_succeeded: true, p_error_code: null,
      });
      if (finishError) throw new Error("outbox_completion_failed");
      completed++;
      results.push({ event_id: eventId, status: "published" });
    } catch (error) {
      const errorCode = error instanceof Error ? error.message : "provider_operation_failed";
      await service.rpc("finish_marketplace_outbox_event", {
        p_event_id: eventId, p_succeeded: false, p_error_code: errorCode,
      });
      retried++;
      results.push({ event_id: eventId, status: "retry_scheduled", error: errorCode });
    }
  }

  return json(200, { claimed: (events ?? []).length, published: completed, retry_scheduled: retried, results });
});

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { getMarketplacePaymentProvider } from "../_shared/payment-provider.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const allowedOrigin = Deno.env.get("APP_ORIGIN") ?? "http://localhost:5173";
const handoverPepper = Deno.env.get("HANDOVER_TOKEN_PEPPER") ?? "";

const corsHeaders = {
  "Access-Control-Allow-Origin": allowedOrigin,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

type Json = Record<string, unknown>;
type AuthResult = { user: { id: string; phone?: string } | null; userClient: SupabaseClient | null; error: string | null };

function reply(status: number, body: Json) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function text(value: unknown, max = 200): string | null {
  if (typeof value !== "string") return null;
  const v = value.trim();
  return v.length ? v.slice(0, max) : null;
}

function positiveInteger(value: unknown, max = 1000000000): number | null {
  const n = Number(value);
  return Number.isSafeInteger(n) && n > 0 && n <= max ? n : null;
}

function encodeBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/g, "");
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

async function hashHandoverSecret(value: string): Promise<string> {
  if (handoverPepper.length < 32) throw new Error("Handover token service is not configured");
  return await sha256Hex(handoverPepper + ":" + value);
}

async function getAuthenticatedUser(req: Request): Promise<AuthResult> {
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return { user: null, userClient: null, error: "Authentication required" };
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error } = await userClient.auth.getUser();
  if (error || !user) return { user: null, userClient: null, error: "Invalid session" };
  return { user: { id: user.id, phone: user.phone }, userClient, error: null };
}

async function hasRole(service: SupabaseClient, userId: string, allowed: string[]) {
  const { data, error } = await service.from("user_roles").select("role")
    .eq("user_id", userId).is("revoked_at", null).in("role", allowed);
  if (error) throw new Error("Unable to validate staff permission");
  return (data ?? []).length > 0;
}

async function getMyBooking(userClient: SupabaseClient, userId: string, bookingId: string) {
  const { data, error } = await userClient.rpc("get_my_booking_workspace");
  if (error) throw error;
  const rows = Array.isArray(data) ? data as Json[] : [];
  const row = rows.find((x) => x.id === bookingId);
  if (!row || (row.reader_id !== userId && row.owner_id !== userId)) throw new Error("Booking not found");
  return row;
}

async function handleWebhook(req: Request): Promise<Response> {
  const providerCode = text(req.headers.get("x-shelfshare-provider"), 40)?.toLowerCase();
  if (!providerCode) return reply(400, { error: "Provider header is required" });
  const adapter = getMarketplacePaymentProvider(providerCode);
  if (!adapter) return reply(503, { error: "No approved and deployed adapter is registered for this provider" });
  const rawBody = await req.text();
  let event;
  try {
    event = await adapter.verifyWebhook(rawBody, req.headers);
  } catch {
    return reply(401, { error: "Webhook signature could not be verified" });
  }
  if (!event) return reply(401, { error: "Invalid webhook signature or payload" });

  const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const payloadSha256 = await sha256Hex(rawBody);
  const eventType = event.eventType;

  if (["chargeback.won", "chargeback.lost", "dispute.won", "dispute.lost"].includes(eventType)) {
    const { data: payment } = await service.from("payments").select("id,merchant_reference,provider_payment_id")
      .eq("provider", providerCode)
      .or(event.merchantReference ? "merchant_reference.eq." + event.merchantReference : "provider_payment_id.eq." + event.providerPaymentReference)
      .maybeSingle();
    if (!payment || !event.providerDisputeReference) return reply(404, { error: "Chargeback or payment reference not found" });
    const { data, error } = await service.rpc("apply_verified_chargeback_resolution", {
      p_provider: providerCode, p_event_id: event.eventId, p_payment_id: payment.id,
      p_dispute_reference: event.providerDisputeReference,
      p_result: eventType.endsWith(".won") ? "won" : "lost",
      p_amount_paise: event.amountPaise, p_currency: event.currency, p_payload_sha256: payloadSha256,
    });
    if (error) return reply(500, { error: "Verified chargeback resolution could not be applied; provider may retry" });
    return reply(200, { accepted: true, result: data });
  }

  if (eventType.startsWith("payment.") || eventType === "order.paid" || eventType === "order.failed"
    || eventType === "chargeback.opened" || eventType === "dispute.opened") {
    let query = service.from("payments").select("id,merchant_reference,provider_payment_id,amount_paise,currency")
      .eq("provider", providerCode);
    if (event.merchantReference) query = query.eq("merchant_reference", event.merchantReference);
    else if (event.providerPaymentReference) query = query.eq("provider_payment_id", event.providerPaymentReference);
    else return reply(400, { error: "Webhook does not contain a payment reference" });
    const { data: payment, error } = await query.maybeSingle();
    if (error || !payment) return reply(404, { error: "Payment reference not found; event requires reconciliation" });
    const { data, error: applyError } = await service.rpc("apply_verified_payment_event", {
      p_provider: providerCode, p_event_id: event.eventId, p_payment_id: payment.id,
      p_event_type: eventType, p_amount_paise: event.amountPaise, p_currency: event.currency,
      p_provider_payment_id: event.providerPaymentReference, p_payload_sha256: payloadSha256,
      p_provider_dispute_reference: event.providerDisputeReference,
    });
    if (applyError) return reply(500, { error: "Verified payment event could not be applied; provider may retry" });
    return reply(200, { accepted: true, result: data });
  }

  if (eventType.startsWith("refund.")) {
    const { data: refund, error } = await service.from("refunds").select("id")
      .eq("provider", providerCode).eq("provider_refund_id", event.providerRefundReference).maybeSingle();
    if (error || !refund) return reply(404, { error: "Refund reference not found; event requires reconciliation" });
    const { data, error: applyError } = await service.rpc("apply_verified_refund_event", {
      p_provider: providerCode, p_event_id: event.eventId, p_refund_id: refund.id,
      p_event_type: eventType, p_provider_refund_id: event.providerRefundReference,
      p_amount_paise: event.amountPaise, p_currency: event.currency, p_payload_sha256: payloadSha256,
    });
    if (applyError) return reply(500, { error: "Verified refund event could not be applied; provider may retry" });
    return reply(200, { accepted: true, result: data });
  }

  if (eventType.startsWith("transfer.") || eventType.startsWith("payout.") || eventType === "settlement.completed") {
    const { data: payout, error } = await service.from("payouts").select("id")
      .eq("provider", providerCode).eq("provider_transfer_id", event.providerTransferReference).maybeSingle();
    if (error || !payout) return reply(404, { error: "Payout reference not found; event requires reconciliation" });
    const { data, error: applyError } = await service.rpc("apply_verified_payout_event", {
      p_provider: providerCode, p_event_id: event.eventId, p_payout_id: payout.id,
      p_event_type: eventType, p_provider_transfer_id: event.providerTransferReference,
      p_amount_paise: event.amountPaise, p_currency: event.currency, p_payload_sha256: payloadSha256,
    });
    if (applyError) return reply(500, { error: "Verified payout event could not be applied; provider may retry" });
    return reply(200, { accepted: true, result: data });
  }

  if (eventType.startsWith("deposit.")) {
    const { data: deposit, error } = await service.from("deposits").select("id")
      .eq("provider", providerCode).eq("provider_reference", event.providerDepositReference).maybeSingle();
    if (error || !deposit) return reply(404, { error: "Deposit reference not found; event requires reconciliation" });
    const providerClaimReference = text(event.providerClaimReference, 80);
    const claimId = providerClaimReference && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(providerClaimReference)
      ? providerClaimReference : null;
    const { data, error: applyError } = await service.rpc("apply_verified_deposit_event", {
      p_provider: providerCode, p_event_id: event.eventId, p_deposit_id: deposit.id,
      p_event_type: eventType, p_provider_reference: event.providerDepositReference,
      p_amount_paise: event.amountPaise, p_currency: event.currency, p_payload_sha256: payloadSha256,
      p_claim_id: claimId,
    });
    if (applyError) return reply(500, { error: "Verified deposit event could not be applied; provider may retry" });
    return reply(200, { accepted: true, result: data });
  }

  return reply(200, { accepted: true, ignored: true });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const pathname = new URL(req.url).pathname;
  if (pathname.endsWith("/webhook")) {
    if (req.method !== "POST") return reply(405, { error: "Method not allowed" });
    return await handleWebhook(req);
  }
  if (req.method !== "POST") return reply(405, { error: "Method not allowed" });
  const origin = req.headers.get("origin");
  if (origin && origin !== allowedOrigin) return reply(403, { error: "Origin not allowed" });

  let payload: Json;
  try { payload = await req.json() as Json; } catch { return reply(400, { error: "Invalid JSON body" }); }
  const auth = await getAuthenticatedUser(req);
  if (!auth.user || !auth.userClient) return reply(401, { error: auth.error ?? "Authentication required" });
  const user = auth.user;
  const userClient = auth.userClient;
  const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const action = text(payload.action, 60);

  try {
    if (action === "request_booking") {
      const copyId = text(payload.copy_id, 64);
      const locationId = text(payload.handover_location_id, 64);
      const startAt = text(payload.start_at, 80);
      const endAt = text(payload.end_at, 80);
      const days = positiveInteger(payload.duration_days, 90);
      const idempotency = text(payload.idempotency_key, 128);
      if (!copyId || !locationId || !startAt || !endAt || !days || !idempotency || idempotency.length < 16
        || !Number.isFinite(Date.parse(startAt)) || !Number.isFinite(Date.parse(endAt))) {
        return reply(400, { error: "A copy, approved handover point, dates, duration and idempotency key are required" });
      }
      const { data, error } = await userClient.rpc("request_book_booking", {
        p_copy_id: copyId, p_handover_location_id: locationId, p_start_at: startAt,
        p_end_at: endAt, p_duration_days: days, p_message: text(payload.message, 500),
        p_idempotency_key: idempotency,
      });
      if (error) return reply(400, { error: error.message });
      return reply(201, { booking_id: data, status: "requested", payment_started: false });
    }

    if (action === "booking_configuration") {
      const { data, error } = await service.from("booking_workflow_configuration")
        .select("rental_duration_mode,configuration_version,handover_ttl_seconds,is_active")
        .eq("id", true).eq("is_active", true).maybeSingle();
      if (error) return reply(500, { error: "Unable to load booking policy" });
      if (!data) return reply(409, { error: "Booking is not enabled until approved timing policy is configured" });
      return reply(200, { rental_duration_mode: data.rental_duration_mode,
        configuration_version: data.configuration_version, handover_ttl_seconds: data.handover_ttl_seconds });
    }

    if (action === "my_bookings") {
      const { data, error } = await userClient.rpc("get_my_booking_workspace");
      if (error) return reply(400, { error: error.message });
      return reply(200, { bookings: data ?? [] });
    }

    if (action === "my_financial_history") {
      const { data, error } = await userClient.rpc("get_my_financial_history");
      if (error) return reply(400, { error: error.message });
      const { data: deposits, error: depositError } = await userClient.rpc("get_my_deposit_positions");
      if (depositError) return reply(400, { error: depositError.message });
      return reply(200, { transactions: data ?? [], deposits: deposits ?? [] });
    }

    if (action === "owner_accept") {
      const bookingId = text(payload.booking_id, 64);
      if (!bookingId) return reply(400, { error: "Booking identifier is required" });
      await getMyBooking(userClient, user.id, bookingId);
      const { error } = await userClient.rpc("accept_book_booking_request", { p_booking_id: bookingId });
      if (error) return reply(400, { error: error.message });
      return reply(200, { accepted: true, status: "owner_accepted", payment_started: false });
    }

    if (action === "owner_decline") {
      const bookingId = text(payload.booking_id, 64);
      const reason = text(payload.reason, 500);
      if (!bookingId || !reason || reason.length < 5) return reply(400, { error: "Booking and decline reason are required" });
      await getMyBooking(userClient, user.id, bookingId);
      const { error } = await userClient.rpc("decline_book_booking_request", { p_booking_id: bookingId, p_reason: reason });
      if (error) return reply(400, { error: error.message });
      return reply(200, { declined: true, status: "cancelled" });
    }

    if (action === "begin_payment") {
      const bookingId = text(payload.booking_id, 64);
      const providerCode = text(payload.provider, 40)?.toLowerCase();
      if (!bookingId || !providerCode) return reply(400, { error: "Booking and provider are required" });
      const booking = await getMyBooking(userClient, user.id, bookingId);
      if (booking.is_reader !== true) return reply(403, { error: "Only the requesting reader may start payment" });
      const adapter = getMarketplacePaymentProvider(providerCode);
      if (!adapter) return reply(503, { error: "Online payment is unavailable until an approved provider adapter is deployed" });
      const { data: approval } = await service.from("payment_provider_approvals").select("id,enabled_for_rent,provider_approval_reference,marketplace_approval_reference,legal_approval_reference,accounting_approval_reference")
        .eq("provider_code", providerCode).eq("enabled_for_rent", true)
        .eq("marketplace_model", "peer_to_peer_physical_book_rental").maybeSingle();
      if (!approval || !approval.provider_approval_reference || !approval.marketplace_approval_reference
        || !approval.legal_approval_reference || !approval.accounting_approval_reference) {
        return reply(403, { error: "Provider approval for ShelfShare's exact rental marketplace is not active" });
      }
      const { data: paymentId, error: beginError } = await service.rpc("begin_booking_payment", {
        p_booking_id: bookingId, p_provider: providerCode,
        p_idempotency_key: "shelfshare-payment-" + crypto.randomUUID(),
        p_merchant_reference: "SSPAY-" + crypto.randomUUID(),
      });
      if (beginError) return reply(409, { error: beginError.message });
      const { data: payment, error: paymentError } = await service.from("payments")
        .select("id,amount_paise,currency,idempotency_key,merchant_reference,provider_order_id")
        .eq("id", paymentId).maybeSingle();
      if (paymentError || !payment) return reply(500, { error: "Payment attempt could not be read" });
      const { data: vendor } = await service.from("provider_vendor_accounts").select("provider_vendor_reference")
        .eq("provider_approval_id", approval.id).eq("user_id", booking.owner_id).eq("kyc_status", "verified").maybeSingle();
      if (!vendor) return reply(409, { error: "Owner marketplace vendor onboarding is not complete" });
      try {
        const intent = await adapter.createPaymentIntent({
          merchantReference: payment.merchant_reference,
          idempotencyKey: payment.idempotency_key,
          amountPaise: payment.amount_paise,
          currency: payment.currency,
          payerReference: user.id,
          vendorReference: vendor.provider_vendor_reference,
          metadata: { bookingId, paymentId: payment.id },
          returnUrl: allowedOrigin + "/rentals",
        });
        await service.from("payments").update({
          provider_order_id: intent.providerOrderReference,
          provider_status: intent.status,
        }).eq("id", payment.id);
        return reply(202, { payment_id: payment.id, booking_id: bookingId, status: "payment_pending", checkout_url: intent.checkoutUrl });
      } catch {
        await service.from("payments").update({ provider_status: "intent_creation_uncertain" }).eq("id", payment.id);
        return reply(202, { payment_id: payment.id, booking_id: bookingId, status: "payment_pending", message: "Payment initiation is being reconciled. Do not create another payment attempt." });
      }
    }

    if (action === "record_booking_tax_calculation") {
      const allowed = await hasRole(service, user.id, ["finance_operator", "admin", "super_admin"]);
      if (!allowed) return reply(403, { error: "Finance permission required" });
      const bookingId = text(payload.booking_id, 64);
      const tax = Number(payload.tax_paise);
      const version = text(payload.policy_version, 80);
      const reference = text(payload.calculation_reference, 200);
      if (!bookingId || !Number.isSafeInteger(tax) || tax < 0 || !version || !reference || reference.length < 5) {
        return reply(400, { error: "Approved tax calculation details are required" });
      }
      const { error } = await service.rpc("record_booking_tax_calculation", {
        p_actor_id: user.id, p_booking_id: bookingId, p_tax_paise: tax,
        p_policy_version: version, p_calculation_reference: reference,
      });
      if (error) return reply(400, { error: error.message });
      return reply(200, { recorded: true, tax_calculated: true });
    }

    if (action === "record_owner_settlement_calculation") {
      const allowed = await hasRole(service, user.id, ["finance_operator", "admin", "super_admin"]);
      if (!allowed) return reply(403, { error: "Finance permission required" });
      const earningId = text(payload.earning_id, 64);
      const tax = Number(payload.tax_withheld_paise);
      const providerFee = Number(payload.provider_fee_paise);
      const adjustment = Number(payload.adjustment_paise ?? 0);
      const net = Number(payload.net_payable_paise);
      const version = text(payload.policy_version, 80);
      if (!earningId || ![tax, providerFee, adjustment, net].every(Number.isSafeInteger)
        || tax < 0 || providerFee < 0 || !version) return reply(400, { error: "Final settlement calculation is incomplete" });
      const { error } = await service.rpc("record_owner_settlement_calculation", {
        p_actor_id: user.id, p_earning_id: earningId, p_tax_withheld_paise: tax,
        p_provider_fee_paise: providerFee, p_adjustment_paise: adjustment,
        p_net_payable_paise: net, p_policy_version: version,
      });
      if (error) return reply(400, { error: error.message });
      return reply(200, { calculated: true, eligible_for_payout: true });
    }

    if (action === "configure_deposit") {
      const allowed = await hasRole(service, user.id, ["finance_operator", "admin", "super_admin"]);
      if (!allowed) return reply(403, { error: "Finance permission required" });
      const bookingId = text(payload.booking_id, 64);
      const providerCode = text(payload.provider, 40)?.toLowerCase();
      const amount = positiveInteger(payload.amount_paise);
      const policyVersion = text(payload.policy_version, 80);
      const custody = text(payload.custody_descriptor, 500);
      if (!bookingId || !providerCode || !amount || !policyVersion || !custody) return reply(400, { error: "Approved deposit configuration is incomplete" });
      const { data, error } = await service.rpc("configure_booking_deposit", {
        p_booking_id: bookingId, p_provider: providerCode, p_amount_paise: amount,
        p_policy_version: policyVersion, p_custody_descriptor: custody,
      });
      if (error) return reply(400, { error: error.message });
      return reply(201, { deposit_id: data, status: "collection_pending", provider_confirmed: false });
    }

    if (action === "begin_deposit_collection") {
      const allowed = await hasRole(service, user.id, ["finance_operator", "admin", "super_admin"]);
      if (!allowed) return reply(403, { error: "Finance permission required" });
      const depositId = text(payload.deposit_id, 64);
      if (!depositId) return reply(400, { error: "Deposit identifier is required" });
      const { data: deposit, error } = await service.from("deposits")
        .select("id,provider,amount_paise,currency,policy_version,custody_descriptor,status,booking_id")
        .eq("id", depositId).maybeSingle();
      if (error || !deposit || deposit.status !== "collection_pending" || !deposit.feature_enabled_at_creation) {
        return reply(404, { error: "An enabled deposit collection was not found" });
      }
      const adapter = getMarketplacePaymentProvider(deposit.provider);
      if (!adapter) return reply(503, { error: "No approved deposit adapter is registered" });
      const { data: approval } = await service.from("payment_provider_approvals").select("id,enabled_for_deposits")
        .eq("provider_code", deposit.provider).eq("enabled_for_deposits", true).maybeSingle();
      if (!approval) return reply(403, { error: "Provider deposit custody is not approved" });
      const { data: payer } = await service.from("bookings").select("reader_id").eq("id", deposit.booking_id).maybeSingle();
      if (!payer) return reply(404, { error: "Booking not found" });
      const result = await adapter.createDepositHold({
        payerReference: payer.reader_id, merchantReference: "SSDEP-" + deposit.id,
        depositReference: deposit.id, idempotencyKey: "deposit-hold-" + deposit.id,
        amountPaise: deposit.amount_paise, currency: deposit.currency,
        custodyDescriptor: deposit.custody_descriptor ?? "", policyVersion: deposit.policy_version ?? "",
      });
      await service.rpc("attach_deposit_provider_reference", { p_deposit_id: deposit.id, p_provider_reference: result.providerDepositReference });
      return reply(202, { deposit_id: deposit.id, status: "collection_pending", provider_status: result.status, provider_confirmed: false });
    }

    if (action === "request_refund") {
      const allowed = await hasRole(service, user.id, ["finance_operator", "admin", "super_admin"]);
      if (!allowed) return reply(403, { error: "Finance permission required" });
      const paymentId = text(payload.payment_id, 64);
      const amount = positiveInteger(payload.amount_paise);
      const reason = text(payload.reason_code, 100);
      const idempotency = text(payload.idempotency_key, 128);
      if (!paymentId || !amount || !reason || !idempotency || idempotency.length < 16) return reply(400, { error: "Refund request is incomplete" });
      const { data: payment } = await service.from("payments").select("provider,provider_payment_id,merchant_reference,booking_id")
        .eq("id", paymentId).maybeSingle();
      if (!payment) return reply(404, { error: "Payment not found" });
      const adapter = getMarketplacePaymentProvider(payment.provider);
      if (!adapter) return reply(503, { error: "No approved provider refund adapter is registered" });
      const { data: refundId, error } = await service.rpc("create_finance_refund", {
        p_actor_id: user.id, p_payment_id: paymentId, p_amount_paise: amount,
        p_reason_code: reason, p_idempotency_key: idempotency,
      });
      if (error) return reply(400, { error: error.message });
      const result = await adapter.createRefund({
        providerPaymentReference: payment.provider_payment_id ?? "",
        merchantReference: payment.merchant_reference ?? paymentId,
        refundReference: refundId, idempotencyKey: idempotency,
        amountPaise: amount, currency: "INR", reasonCode: reason,
      });
      await service.rpc("attach_refund_provider_reference", { p_refund_id: refundId, p_provider_reference: result.providerRefundReference });
      return reply(202, { refund_id: refundId, status: "pending", provider_status: result.status, provider_confirmed: false });
    }

    if (action === "request_payout") {
      const earningId = text(payload.earning_id, 64);
      const providerCode = text(payload.provider, 40)?.toLowerCase();
      const idempotency = text(payload.idempotency_key, 128);
      if (!earningId || !providerCode || !idempotency || idempotency.length < 16) return reply(400, { error: "Payout request is incomplete" });
      const adapter = getMarketplacePaymentProvider(providerCode);
      if (!adapter) return reply(503, { error: "No approved marketplace payout adapter is registered" });
      const { data: payoutId, error } = await userClient.rpc("create_owner_payout_request", {
        p_earning_id: earningId, p_provider: providerCode, p_idempotency_key: idempotency,
      });
      if (error) return reply(400, { error: error.message });
      const { data: payout } = await service.from("payouts").select("id,owner_id,amount_paise,currency,owner_earning_id")
        .eq("id", payoutId).maybeSingle();
      if (!payout || payout.owner_id !== user.id) return reply(404, { error: "Payout request not found" });
      const { data: approval } = await service.from("payment_provider_approvals").select("id")
        .eq("provider_code", providerCode).eq("enabled_for_rent", true).maybeSingle();
      const { data: vendor } = await service.from("provider_vendor_accounts").select("provider_vendor_reference")
        .eq("provider_approval_id", approval?.id ?? "").eq("user_id", user.id).eq("kyc_status", "verified").maybeSingle();
      if (!vendor) return reply(409, { error: "Marketplace seller onboarding is not verified" });
      const result = await adapter.createTransfer({
        vendorReference: vendor.provider_vendor_reference, merchantReference: payout.id,
        transferReference: payout.id, idempotencyKey: idempotency,
        amountPaise: payout.amount_paise, currency: payout.currency,
      });
      await service.rpc("attach_payout_provider_reference", { p_payout_id: payoutId, p_provider_reference: result.providerTransferReference });
      return reply(202, { payout_id: payoutId, status: "processing", provider_status: result.status, provider_confirmed: false });
    }

    if (action === "start_handover") {
      const bookingId = text(payload.booking_id, 64);
      const handoverType = text(payload.handover_type, 20);
      if (!bookingId || !handoverType || !["collection", "return"].includes(handoverType)) return reply(400, { error: "Booking and handover type are required" });
      await getMyBooking(userClient, user.id, bookingId);
      if (handoverPepper.length < 32) return reply(503, { error: "One-time handover credential service is not configured" });
      const { data: config } = await service.from("booking_workflow_configuration").select("handover_ttl_seconds")
        .eq("id", true).eq("is_active", true).maybeSingle();
      if (!config) return reply(503, { error: "Approved handover timing policy is not configured" });
      const tokenBytes = new Uint8Array(32);
      crypto.getRandomValues(tokenBytes);
      const qrToken = encodeBase64Url(tokenBytes);
      const otpBytes = new Uint32Array(1);
      crypto.getRandomValues(otpBytes);
      const otp = String(otpBytes[0] % 1000000).padStart(6, "0");
      const [tokenHash, otpHash] = await Promise.all([hashHandoverSecret(qrToken), hashHandoverSecret(otp)]);
      const expiresAt = new Date(Date.now() + Math.min(Math.max(config.handover_ttl_seconds, 60), 900) * 1000).toISOString();
      const { data: sessionId, error } = await service.rpc("create_handover_session_secure", {
        p_booking_id: bookingId, p_handover_type: handoverType, p_actor_id: user.id,
        p_qr_token_hash: tokenHash, p_otp_hash: otpHash, p_expires_at: expiresAt,
      });
      if (error) return reply(409, { error: error.message });
      return reply(201, { session_id: sessionId, handover_type: handoverType, qr_token: qrToken, otp, expires_at: expiresAt });
    }

    if (action === "confirm_handover") {
      const sessionId = text(payload.session_id, 64);
      const token = text(payload.qr_token, 256);
      const otp = text(payload.otp, 12);
      if (!sessionId || (!token && !otp) || !Boolean(payload.condition_acknowledged)) return reply(400, { error: "Session, QR token or OTP, and condition acknowledgement are required" });
      const [tokenHash, otpHash] = await Promise.all([
        token ? hashHandoverSecret(token) : Promise.resolve(null),
        otp ? hashHandoverSecret(otp) : Promise.resolve(null),
      ]);
      const { data, error } = await service.rpc("confirm_handover_qr_or_otp", {
        p_session_id: sessionId, p_actor_id: user.id, p_token_hash: tokenHash, p_otp_hash: otpHash,
        p_condition_acknowledged: true,
      });
      if (error) return reply(400, { error: error.message });
      if (data !== true) return reply(202, { verified: false, status: "awaiting_other_confirmation_or_photos" });
      return reply(200, { verified: true, completed: true });
    }

    if (action === "confirm_handover_initiator") {
      const sessionId = text(payload.session_id, 64);
      if (!sessionId || !Boolean(payload.condition_acknowledged)) return reply(400, { error: "Session and condition acknowledgement are required" });
      const { data, error } = await service.rpc("confirm_handover_initiator", {
        p_session_id: sessionId, p_actor_id: user.id, p_condition_acknowledged: true,
      });
      if (error) return reply(400, { error: error.message });
      return reply(data === true ? 200 : 202, { completed: data === true, status: data === true ? "completed" : "awaiting_other_confirmation_or_photos" });
    }

    if (action === "register_handover_photo") {
      const sessionId = text(payload.session_id, 64);
      const objectKey = text(payload.object_key, 500);
      const sha = text(payload.sha256, 64);
      const caption = text(payload.caption, 300);
      if (!sessionId || !objectKey || !objectKey.startsWith(user.id + "/") || (sha && !/^[a-f0-9]{64}$/.test(sha))) return reply(400, { error: "Invalid condition evidence reference" });
      const { data: session } = await service.from("handover_sessions").select("booking_id,expires_at,status")
        .eq("id", sessionId).maybeSingle();
      if (!session || session.status === "completed" || Date.parse(session.expires_at) <= Date.now()) return reply(410, { error: "Handover session expired" });
      const expectedPrefix = user.id + "/" + session.booking_id + "/" + sessionId + "/";
      if (!objectKey.startsWith(expectedPrefix)) return reply(403, { error: "Evidence object path is not scoped to this participant and booking" });
      const folder = expectedPrefix.slice(0, -1);
      const filename = objectKey.slice(expectedPrefix.length);
      const { data: storedObjects, error: storageError } = await service.storage
        .from("rental-evidence-private").list(folder, { search: filename, limit: 10 });
      if (storageError || !(storedObjects ?? []).some((x) => x.name === filename)) {
        return reply(404, { error: "Uploaded private evidence was not found" });
      }
      const { data, error } = await service.rpc("register_handover_condition_photo", {
        p_session_id: sessionId, p_actor_id: user.id, p_object_key: objectKey,
        p_sha256: sha, p_caption: caption,
      });
      if (error) return reply(400, { error: error.message });
      return reply(201, { photo_id: data, registered: true });
    }

    if (action === "request_deposit_release") {
      const depositId = text(payload.deposit_id, 64);
      const idempotency = text(payload.idempotency_key, 128);
      if (!depositId || !idempotency || idempotency.length < 16) return reply(400, { error: "Deposit and idempotency key are required" });
      const { data: deposit } = await service.from("deposits").select("id,provider,provider_reference,status")
        .eq("id", depositId).eq("payer_id", user.id).maybeSingle();
      if (!deposit || !deposit.provider_reference || !["held_by_provider", "partially_applied"].includes(deposit.status)) {
        return reply(409, { error: "No provider-confirmed releasable deposit was found" });
      }
      const adapter = getMarketplacePaymentProvider(deposit.provider);
      if (!adapter) return reply(503, { error: "No approved deposit-release adapter is registered" });
      const { data, error } = await userClient.rpc("request_deposit_release", { p_deposit_id: depositId, p_idempotency_key: idempotency });
      if (error) return reply(400, { error: error.message });
      const { data: request } = await service.from("deposit_release_requests").select("amount_paise").eq("id", data).maybeSingle();
      const release = await adapter.releaseDeposit(deposit.provider_reference, request?.amount_paise ?? deposit.amount_paise, idempotency);
      return reply(202, { release_request_id: data, amount_paise: request?.amount_paise ?? null,
        status: "release_pending", provider_status: release.status, provider_confirmed: false });
    }

    if (action === "submit_deposit_claim") {
      const depositId = text(payload.deposit_id, 64);
      const amount = positiveInteger(payload.amount_paise);
      const reason = text(payload.reason_code, 80);
      const description = text(payload.description, 3000);
      if (!depositId || !amount || !reason || !description || description.length < 20) return reply(400, { error: "Deposit claim details are incomplete" });
      const { data, error } = await userClient.rpc("submit_deposit_claim", {
        p_deposit_id: depositId, p_amount_paise: amount, p_reason_code: reason, p_description: description,
      });
      if (error) return reply(400, { error: error.message });
      return reply(201, { claim_id: data, status: "submitted" });
    }

    if (action === "decide_deposit_claim") {
      const allowed = await hasRole(service, user.id, ["finance_operator", "admin", "super_admin"]);
      if (!allowed) return reply(403, { error: "Finance reviewer permission required" });
      const claimId = text(payload.claim_id, 64);
      const decision = text(payload.decision, 10);
      const amount = payload.amount_paise == null ? null : Number(payload.amount_paise);
      const reason = text(payload.reason, 2000);
      if (!claimId || !decision || !reason || reason.length < 10 || (amount !== null && (!Number.isSafeInteger(amount) || amount < 0))) return reply(400, { error: "Claim decision details are incomplete" });
      const { error } = await userClient.rpc("decide_deposit_claim", {
        p_claim_id: claimId, p_decision: decision, p_amount_paise: amount, p_reason: reason,
      });
      if (error) return reply(400, { error: error.message });
      return reply(200, { decided: true, decision });
    }

    if (action === "request_deposit_claim_application") {
      const allowed = await hasRole(service, user.id, ["finance_operator", "admin", "super_admin"]);
      if (!allowed) return reply(403, { error: "Finance reviewer permission required" });
      const claimId = text(payload.claim_id, 64);
      const idempotency = text(payload.idempotency_key, 128);
      if (!claimId || !idempotency || idempotency.length < 16) return reply(400, { error: "Claim and idempotency key are required" });
      const { data: claim } = await service.from("deposit_claims").select("id,deposit_id,decision_amount_paise,status")
        .eq("id", claimId).maybeSingle();
      if (!claim || claim.status !== "approved" || !claim.decision_amount_paise) return reply(409, { error: "An approved deposit claim is required" });
      const { data: deposit } = await service.from("deposits").select("provider,provider_reference")
        .eq("id", claim.deposit_id).maybeSingle();
      if (!deposit?.provider_reference) return reply(409, { error: "Provider-confirmed deposit reference is missing" });
      const adapter = getMarketplacePaymentProvider(deposit.provider);
      if (!adapter) return reply(503, { error: "No approved deposit-claim adapter is registered" });
      const { data, error } = await userClient.rpc("request_deposit_claim_application", {
        p_claim_id: claimId, p_idempotency_key: idempotency,
      });
      if (error) return reply(400, { error: error.message });
      const result = await adapter.applyDepositClaim(deposit.provider_reference, claim.decision_amount_paise, claimId, idempotency);
      return reply(202, { outbox_event_id: data, status: "claim_hold_pending", provider_status: result.status, provider_confirmed: false });
    }

    if (action === "request_return") {
      const bookingId = text(payload.booking_id, 64);
      if (!bookingId) return reply(400, { error: "Booking identifier is required" });
      await getMyBooking(userClient, user.id, bookingId);
      const { error } = await userClient.rpc("request_book_return", { p_booking_id: bookingId });
      if (error) return reply(400, { error: error.message });
      return reply(200, { requested: true, status: "return_pending" });
    }

    if (action === "payment_capabilities") {
      const { data: approvals, error } = await service.from("payment_provider_approvals")
        .select("provider_code,enabled_for_rent,enabled_for_deposits,supports_refunds,supports_reconciliation,expires_at")
        .eq("enabled_for_rent", true);
      if (error) return reply(500, { error: "Unable to load payment capability status" });
      const items = (approvals ?? []).map((item) => ({
        provider: item.provider_code,
        adapter_registered: Boolean(getMarketplacePaymentProvider(item.provider_code)),
        approved: !item.expires_at || Date.parse(item.expires_at) > Date.now(),
        deposits_approved: item.enabled_for_deposits === true,
      }));
      return reply(200, { providers: items, checkout_available: items.some((x) => x.adapter_registered && x.approved) });
    }

    if (action === "open_dispute") {
      const bookingId = text(payload.booking_id, 64);
      const reasonCode = text(payload.reason_code, 80);
      const description = text(payload.description, 4000);
      if (!bookingId || !reasonCode || !description || description.length < 20) {
        return reply(400, { error: "Booking, dispute reason and a detailed description are required" });
      }
      const { data, error } = await userClient.rpc("open_booking_dispute", {
        p_booking_id: bookingId, p_reason_code: reasonCode, p_description: description,
      });
      if (error) return reply(400, { error: error.message });
      return reply(201, { dispute_id: data, status: "open",
        deposit_hold_requested: true, deposit_hold_confirmed: false,
        message: "Dispute opened. Any permitted provider deposit hold will be confirmed separately by a signed provider event." });
    }

    if (action === "report_incident") {
      const bookingId = text(payload.booking_id, 64);
      const incidentType = text(payload.incident_type, 40);
      const description = text(payload.description, 2000);
      if (!bookingId || !incidentType || !description || description.length < 10) return reply(400, { error: "Incident details are incomplete" });
      const { data, error } = await userClient.rpc("report_booking_incident", {
        p_booking_id: bookingId, p_incident_type: incidentType, p_description: description,
      });
      if (error) return reply(400, { error: error.message });
      return reply(201, { incident_id: data, status: "open" });
    }

    if (action === "reconcile_provider") {
      const allowed = await hasRole(service, user.id, ["finance_operator", "admin", "super_admin"]);
      if (!allowed) return reply(403, { error: "Finance permission required" });
      const providerCode = text(payload.provider, 40)?.toLowerCase();
      const start = text(payload.period_start, 80);
      const end = text(payload.period_end, 80);
      if (!providerCode || !start || !end || !Number.isFinite(Date.parse(start)) || !Number.isFinite(Date.parse(end)) || Date.parse(end) <= Date.parse(start)) {
        return reply(400, { error: "Provider reconciliation period is invalid" });
      }
      const adapter = getMarketplacePaymentProvider(providerCode);
      if (!adapter) return reply(503, { error: "No approved provider reconciliation adapter is registered" });
      const records = await adapter.fetchReconciliation(start, end);
      const { data, error } = await service.rpc("record_provider_reconciliation", {
        p_provider: providerCode, p_report_reference: "api:" + start + ":" + end,
        p_period_start: start, p_period_end: end, p_records: records.map((x) => ({
          recordType: x.recordType, internalReference: x.internalReference, providerReference: x.providerReference,
          expectedAmountPaise: null, amountPaise: x.amountPaise, currency: x.currency, status: x.status,
        })),
      });
      if (error) return reply(400, { error: error.message });
      return reply(201, { reconciliation_run_id: data, received_records: records.length });
    }

    return reply(400, { error: "Unsupported marketplace action" });
  } catch (error) {
    return reply(500, { error: error instanceof Error ? error.message : "Marketplace request failed" });
  }
});

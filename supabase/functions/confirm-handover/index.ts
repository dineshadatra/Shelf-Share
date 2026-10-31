import { createAdminClient, requireUser } from "../_shared/supabase.ts";
import { hmacSha256Hex, sha256Hex } from "../_shared/crypto.ts";
import { errorResponse, jsonResponse, readJson, requirePost } from "../_shared/http.ts";

interface Body {
  sessionId: string;
  conditionAcknowledged: boolean;
  qrToken?: string;
  otp?: string;
}

Deno.serve(async (request) => {
  const methodError = requirePost(request);
  if (methodError) return methodError;
  try {
    const { user } = await requireUser(request);
    const body = await readJson<Body>(request);
    if (!body.sessionId || body.conditionAcknowledged !== true) return jsonResponse({ error: "invalid_confirmation" }, 400);
    const admin = createAdminClient();
    const { data: session, error: sessionError } = await admin.from("handover_sessions")
      .select("id,booking_id,initiator_id,expires_at,status").eq("id", body.sessionId).maybeSingle();
    if (sessionError) throw new Error("handover_session_lookup_failed");
    if (!session || new Date(session.expires_at).getTime() <= Date.now()) return jsonResponse({ error: "handover_session_expired_or_missing" }, 404);
    const { data: booking, error: bookingError } = await admin.from("bookings")
      .select("id,reader_id,owner_id").eq("id", session.booking_id).single();
    if (bookingError || ![booking.reader_id, booking.owner_id].includes(user.id)) return jsonResponse({ error: "booking_participant_required" }, 403);

    let completed = false;
    if (user.id === session.initiator_id) {
      const { data, error } = await admin.rpc("confirm_handover_initiator", {
        p_session_id: session.id,
        p_actor_id: user.id,
        p_condition_acknowledged: true,
      });
      if (error) throw new Error("initiator_confirmation_failed");
      completed = data === true;
    } else {
      const hasQr = typeof body.qrToken === "string" && body.qrToken.length >= 32;
      const hasOtp = typeof body.otp === "string" && /^\d{6}$/u.test(body.otp);
      if (hasQr === hasOtp) return jsonResponse({ error: "provide_exactly_one_qr_token_or_otp" }, 400);
      const tokenHash = hasQr ? await sha256Hex(body.qrToken!) : null;
      const otpSecret = Deno.env.get("HANDOVER_OTP_HMAC_SECRET");
      if (hasOtp && (!otpSecret || new TextEncoder().encode(otpSecret).length < 32)) return jsonResponse({ error: "otp_fallback_not_configured" }, 503);
      const otpHash = hasOtp ? await hmacSha256Hex(otpSecret!, body.otp!) : null;
      const { data, error } = await admin.rpc("confirm_handover_qr_or_otp", {
        p_session_id: session.id,
        p_actor_id: user.id,
        p_token_hash: tokenHash,
        p_otp_hash: otpHash,
        p_condition_acknowledged: true,
      });
      if (error) throw new Error("counterparty_verification_failed");
      completed = data === true;
    }

    return jsonResponse({
      sessionId: session.id,
      completed,
      status: completed ? "COMPLETED" : "AWAITING_OTHER_PARTY_OR_EVIDENCE",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "unexpected_error";
    const status = message.includes("authentication") || message.includes("session") ? 401
      : message.includes("participant") ? 403 : 400;
    return errorResponse(error, status);
  }
});

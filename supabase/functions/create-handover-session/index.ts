import { createAdminClient, requireUser } from "../_shared/supabase.ts";
import { hmacSha256Hex, randomOtp, randomToken, sha256Hex } from "../_shared/crypto.ts";
import { errorResponse, jsonResponse, readJson, requirePost } from "../_shared/http.ts";

interface Body { bookingId: string; type: "collection" | "return" }

Deno.serve(async (request) => {
  const methodError = requirePost(request);
  if (methodError) return methodError;
  try {
    const { user } = await requireUser(request);
    const body = await readJson<Body>(request);
    if (!body.bookingId || !["collection", "return"].includes(body.type)) return jsonResponse({ error: "invalid_request" }, 400);
    const admin = createAdminClient();
    const { data: booking, error: bookingError } = await admin.from("bookings")
      .select("id,reader_id,owner_id,status").eq("id", body.bookingId).maybeSingle();
    if (bookingError) throw new Error("booking_lookup_failed");
    if (!booking || ![booking.reader_id, booking.owner_id].includes(user.id)) return jsonResponse({ error: "booking_not_found" }, 404);

    const { data: config, error: configError } = await admin.from("booking_workflow_configuration")
      .select("handover_ttl_seconds").eq("id", true).eq("is_active", true).maybeSingle();
    if (configError) throw new Error("handover_configuration_lookup_failed");
    if (!config) return jsonResponse({ error: "approved_booking_configuration_required" }, 503);

    const otpSecret = Deno.env.get("HANDOVER_OTP_HMAC_SECRET");
    if (!otpSecret || new TextEncoder().encode(otpSecret).length < 32) {
      return jsonResponse({ error: "handover_otp_secret_must_be_at_least_32_bytes" }, 503);
    }
    const qrToken = randomToken(32);
    const otp = randomOtp();
    const qrHash = await sha256Hex(qrToken);
    const otpHash = await hmacSha256Hex(otpSecret, otp);
    const ttlSeconds = Math.max(60, Math.min(Number(config.handover_ttl_seconds) || 300, 900));
    const expiresAt = new Date(Date.now() + ttlSeconds * 1000).toISOString();

    const { data: sessionId, error: createError } = await admin.rpc("create_handover_session_secure", {
      p_booking_id: booking.id,
      p_handover_type: body.type,
      p_actor_id: user.id,
      p_qr_token_hash: qrHash,
      p_otp_hash: otpHash,
      p_expires_at: expiresAt,
    });
    if (createError || !sessionId) throw new Error("handover_session_creation_failed");

    // These credentials are returned once to the authenticated initiator only.
    // Do not log them, persist them in analytics, or include them in notifications.
    return jsonResponse({
      sessionId,
      type: body.type,
      expiresAt,
      qrPayload: { sessionId, token: qrToken },
      fallbackOtp: otp,
      showOtpOnlyToInitiator: true,
    }, 201);
  } catch (error) {
    const message = error instanceof Error ? error.message : "unexpected_error";
    const status = message.includes("authentication") || message.includes("session") ? 401
      : message.includes("configuration") || message.includes("secret") ? 503 : 400;
    return errorResponse(error, status);
  }
});

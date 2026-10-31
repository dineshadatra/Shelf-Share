import { createAdminClient, requireUser } from "../_shared/supabase.ts";
import { randomToken, sha256Hex } from "../_shared/crypto.ts";
import { errorResponse, jsonResponse, readJson, requirePost } from "../_shared/http.ts";

const BUCKET = "rental-evidence-private";
const MAX_BYTES = 10 * 1024 * 1024;
const ALLOWED = new Set(["image/jpeg", "image/png", "image/webp"]);

interface Body {
  operation: "sign" | "finalize";
  sessionId: string;
  objectKey?: string;
  caption?: string;
  contentType?: string;
}

function detectedImageType(bytes: Uint8Array): string | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47
    && bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a) return "image/png";
  if (bytes.length >= 12 && String.fromCharCode(...bytes.slice(0, 4)) === "RIFF"
    && String.fromCharCode(...bytes.slice(8, 12)) === "WEBP") return "image/webp";
  return null;
}

Deno.serve(async (request) => {
  const methodError = requirePost(request);
  if (methodError) return methodError;
  try {
    const { user } = await requireUser(request);
    const body = await readJson<Body>(request);
    if (!body.sessionId || !["sign", "finalize"].includes(body.operation)) return jsonResponse({ error: "invalid_request" }, 400);
    const admin = createAdminClient();
    const { data: session, error: sessionError } = await admin.from("handover_sessions")
      .select("id,booking_id,expires_at,status").eq("id", body.sessionId).maybeSingle();
    if (sessionError || !session || session.status === "completed" || new Date(session.expires_at).getTime() <= Date.now()) {
      return jsonResponse({ error: "active_handover_session_required" }, 409);
    }
    const { data: booking, error: bookingError } = await admin.from("bookings")
      .select("reader_id,owner_id").eq("id", session.booking_id).single();
    if (bookingError || !booking || ![booking.reader_id, booking.owner_id].includes(user.id)) {
      return jsonResponse({ error: "booking_participant_required" }, 403);
    }

    if (body.operation === "sign") {
      if (!body.contentType || !ALLOWED.has(body.contentType)) return jsonResponse({ error: "unsupported_image_type" }, 400);
      const extension = body.contentType === "image/jpeg" ? "jpg" : body.contentType === "image/png" ? "png" : "webp";
      const objectKey = [user.id, session.booking_id, session.id, randomToken(18) + "." + extension].join("/");
      const { data, error } = await admin.storage.from(BUCKET).createSignedUploadUrl(objectKey, { upsert: false });
      if (error || !data) throw new Error("evidence_upload_url_creation_failed");
      return jsonResponse({ bucket: BUCKET, path: objectKey, token: data.token, signedUrl: data.signedUrl, maxBytes: MAX_BYTES }, 201);
    }

    if (!body.objectKey) return jsonResponse({ error: "object_key_required" }, 400);
    const prefix = [user.id, session.booking_id, session.id, ""].join("/");
    if (!body.objectKey.startsWith(prefix) || body.objectKey.includes("..") || body.objectKey.startsWith("/")) {
      return jsonResponse({ error: "invalid_evidence_object_key" }, 403);
    }
    const { data: file, error: downloadError } = await admin.storage.from(BUCKET).download(body.objectKey);
    if (downloadError || !file) return jsonResponse({ error: "uploaded_evidence_not_found" }, 404);
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (bytes.byteLength === 0 || bytes.byteLength > MAX_BYTES) return jsonResponse({ error: "evidence_size_invalid" }, 400);
    const contentType = detectedImageType(bytes);
    if (!contentType || !ALLOWED.has(contentType)) return jsonResponse({ error: "evidence_file_signature_invalid" }, 400);
    const digest = await sha256Hex(bytes);
    const { data: photoId, error: registerError } = await admin.rpc("register_handover_condition_photo", {
      p_session_id: session.id,
      p_actor_id: user.id,
      p_object_key: body.objectKey,
      p_sha256: digest,
      p_caption: (body.caption ?? "").slice(0, 300),
    });
    if (registerError || !photoId) throw new Error("evidence_registration_failed");
    return jsonResponse({ photoId, sha256: digest, contentType, bytes: bytes.byteLength }, 201);
  } catch (error) {
    const message = error instanceof Error ? error.message : "unexpected_error";
    const status = message.includes("authentication") || message.includes("session") ? 401
      : message.includes("participant") ? 403 : 400;
    return errorResponse(error, status);
  }
});

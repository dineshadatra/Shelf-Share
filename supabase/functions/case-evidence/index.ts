import { createAdminClient, requireUser } from "../_shared/supabase.ts";
import { randomToken, sha256Hex } from "../_shared/crypto.ts";
import { errorResponse, jsonResponse, readJson, requirePost } from "../_shared/http.ts";

const BUCKET = "rental-evidence-private";
const MAX_BYTES = 10 * 1024 * 1024;
const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "application/pdf"]);

interface Body {
  operation: "sign" | "finalize";
  caseType: "claim" | "dispute";
  caseId: string;
  objectKey?: string;
  contentType?: string;
  evidenceType?: string;
  description?: string;
}

function detectFileType(bytes: Uint8Array): string | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47
    && bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a) return "image/png";
  if (bytes.length >= 12 && String.fromCharCode(...bytes.slice(0, 4)) === "RIFF"
    && String.fromCharCode(...bytes.slice(8, 12)) === "WEBP") return "image/webp";
  if (bytes.length >= 5 && String.fromCharCode(...bytes.slice(0, 5)) === "%PDF-") return "application/pdf";
  return null;
}

Deno.serve(async (request) => {
  const methodError = requirePost(request);
  if (methodError) return methodError;
  try {
    const { user } = await requireUser(request);
    const body = await readJson<Body>(request);
    if (!body.caseId || !["claim", "dispute"].includes(body.caseType) || !["sign", "finalize"].includes(body.operation)) {
      return jsonResponse({ error: "invalid_case_evidence_request" }, 400);
    }

    const admin = createAdminClient();
    const table = body.caseType === "claim" ? "rental_damage_claims" : "disputes";
    const { data: caseRecord, error: caseError } = await admin.from(table)
      .select("id,booking_id").eq("id", body.caseId).maybeSingle();
    if (caseError || !caseRecord) return jsonResponse({ error: "case_not_found" }, 404);
    const { data: booking, error: bookingError } = await admin.from("bookings")
      .select("reader_id,owner_id").eq("id", caseRecord.booking_id).single();
    if (bookingError || !booking || ![booking.reader_id, booking.owner_id].includes(user.id)) {
      return jsonResponse({ error: "case_participant_required" }, 403);
    }

    if (body.operation === "sign") {
      if (!body.contentType || !ALLOWED_TYPES.has(body.contentType)) return jsonResponse({ error: "unsupported_evidence_type" }, 400);
      const extension = body.contentType === "image/jpeg" ? "jpg"
        : body.contentType === "image/png" ? "png"
        : body.contentType === "image/webp" ? "webp" : "pdf";
      const objectKey = `${user.id}/${caseRecord.booking_id}/${body.caseType}/${caseRecord.id}/${randomToken(18)}.${extension}`;
      const { data, error } = await admin.storage.from(BUCKET).createSignedUploadUrl(objectKey, { upsert: false });
      if (error || !data) throw new Error("case_evidence_upload_url_failed");
      return jsonResponse({ bucket: BUCKET, path: objectKey, token: data.token, signedUrl: data.signedUrl, maxBytes: MAX_BYTES }, 201);
    }

    if (!body.objectKey) return jsonResponse({ error: "object_key_required" }, 400);
    const prefix = `${user.id}/${caseRecord.booking_id}/${body.caseType}/${caseRecord.id}/`;
    if (!body.objectKey.startsWith(prefix) || body.objectKey.includes("..") || body.objectKey.startsWith("/")) {
      return jsonResponse({ error: "evidence_path_not_authorized" }, 403);
    }
    const { data: file, error: downloadError } = await admin.storage.from(BUCKET).download(body.objectKey);
    if (downloadError || !file) return jsonResponse({ error: "evidence_file_not_found" }, 404);
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (bytes.byteLength === 0 || bytes.byteLength > MAX_BYTES) return jsonResponse({ error: "evidence_size_invalid" }, 400);
    const contentType = detectFileType(bytes);
    if (!contentType || !ALLOWED_TYPES.has(contentType) || (body.contentType && body.contentType !== contentType)) {
      await admin.storage.from(BUCKET).remove([body.objectKey]);
      return jsonResponse({ error: "evidence_file_signature_invalid" }, 400);
    }
    const digest = await sha256Hex(bytes);
    const { data: evidenceId, error: registerError } = await admin.rpc("register_rental_case_evidence", {
      p_case_type: body.caseType,
      p_case_id: caseRecord.id,
      p_actor_id: user.id,
      p_object_key: body.objectKey,
      p_evidence_type: body.evidenceType ?? "supporting_document",
      p_description: (body.description ?? "").slice(0, 1000),
      p_sha256: digest,
    });
    if (registerError || !evidenceId) throw new Error("case_evidence_registration_failed");
    return jsonResponse({ evidenceId, sha256: digest, contentType, bytes: bytes.byteLength }, 201);
  } catch (error) {
    const message = error instanceof Error ? error.message : "unexpected_error";
    const status = message.includes("authentication") || message.includes("session") ? 401
      : message.includes("participant") ? 403 : 400;
    return errorResponse(error, status);
  }
});

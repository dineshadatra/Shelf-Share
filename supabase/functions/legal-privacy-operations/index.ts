import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Body = Record<string, unknown> & { action?: string };

function json(data: unknown, status = 200, origin = ""): Response {
  const headers = new Headers({
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer"
  });
  if (origin) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set("Vary", "Origin");
    headers.set("Access-Control-Allow-Headers", "authorization, apikey, content-type, x-client-info");
    headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  }
  return new Response(JSON.stringify(data), { status, headers });
}
function textValue(value: unknown, field: string, min = 1, max = 5000): string {
  if (typeof value !== "string") throw new Error("invalid_" + field);
  const result = value.trim();
  if (result.length < min || result.length > max) throw new Error("invalid_" + field);
  return result;
}
function uuidValue(value: unknown, field: string): string {
  const result = textValue(value, field, 36, 36);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(result)) {
    throw new Error("invalid_" + field);
  }
  return result;
}
function tokenClaims(token: string): Record<string, unknown> {
  const part = token.split(".")[1];
  if (!part) throw new Error("invalid_session_token");
  const normalized = part.replace(/-/gu, "+").replace(/_/gu, "/");
  return JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")));
}
function errorStatus(error: unknown): number {
  const message = error instanceof Error ? error.message : "";
  if (/authentication|invalid jwt|session required/iu.test(message)) return 401;
  if (/permission|mfa|aal2|access denied|not authorized|role required/iu.test(message)) return 403;
  if (/not found/iu.test(message)) return 404;
  if (/already|conflict|pending|immutable|blocked|cannot be approved/iu.test(message)) return 409;
  return 400;
}
function csvSafe(value: unknown): string {
  let text = value === null || value === undefined ? "" :
    typeof value === "object" ? JSON.stringify(value) : String(value);
  if (/^[\s]*[=+\-@]/u.test(text)) text = "'" + text;
  return '"' + text.replace(/"/gu, '""') + '"';
}
function toCsv(rows: Record<string, unknown>[], fields: string[]): string {
  return [fields.map(csvSafe).join(","), ...rows.map(row => fields.map(field => csvSafe(row[field])).join(","))].join("\r\n");
}
function makeKey(prefix: string): string {
  return (prefix + "-" + crypto.randomUUID()).slice(0, 120);
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("Origin") ?? "";
  const allowed = [
    Deno.env.get("CUSTOMER_APP_ORIGINS") ?? "",
    Deno.env.get("ADMIN_PORTAL_ORIGINS") ?? "",
    Deno.env.get("APP_ORIGIN") ?? ""
  ].flatMap(value => value.split(",")).map(value => value.trim()).filter(Boolean);
  const allowedOrigin = origin && allowed.includes(origin) ? origin : "";
  if (request.method === "OPTIONS") {
    if (!allowedOrigin) return json({ error: "origin_not_allowed" }, 403);
    return new Response(null, { status: 204, headers: {
      "Access-Control-Allow-Origin": allowedOrigin,
      "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Max-Age": "600",
      "Vary": "Origin"
    }});
  }
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405, allowedOrigin);
  if (origin && !allowedOrigin) return json({ error: "origin_not_allowed" }, 403);

  let actorId: string | null = null;
  let admin: ReturnType<typeof createClient> | null = null;
  let actorClient: ReturnType<typeof createClient> | null = null;
  const requestId = crypto.randomUUID();
  try {
    const authorization = request.headers.get("Authorization") ?? "";
    const accessToken = authorization.replace(/^Bearer\s+/iu, "");
    if (!accessToken) throw new Error("authentication_required");
    const claims = tokenClaims(accessToken);
    if (claims.role !== "authenticated") throw new Error("authenticated_user_required");

    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anon || !service) throw new Error("server_configuration_missing");
    actorClient = createClient(url, anon, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: authorization } }
    });
    const { data: authData, error: authError } = await actorClient.auth.getUser();
    if (authError || !authData.user) throw new Error("authentication_required");
    actorId = authData.user.id;
    admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });

    const raw = await request.text();
    if (raw.length > 180000) throw new Error("request_body_too_large");
    const body = JSON.parse(raw) as Body;
    const action = textValue(body.action, "action", 2, 50);
    const claimsAal = claims.aal;
    const requireAal2 = () => {
      if (claimsAal !== "aal2") throw new Error("step_up_mfa_aal2_required");
    };
    const hasPermission = async (permission: string): Promise<boolean> => {
      const { data, error } = await actorClient!.rpc("admin_has_permission", { p_permission_key: permission });
      if (error) throw error;
      return data === true;
    };
    const requirePermission = async (permission: string) => {
      if (!await hasPermission(permission)) throw new Error("permission_denied:" + permission);
    };
    const logSensitive = async (
      dataClass: string, table: string, resourceId: string, subjectUserId: string | null,
      purpose: string, outcome = "success", metadata: Record<string, unknown> = {}
    ) => {
      const { error } = await admin!.from("sensitive_data_access_events").insert({
        actor_id: actorId, subject_user_id: subjectUserId, data_class: dataClass,
        resource_table: table, resource_id: resourceId, purpose: purpose.slice(0, 1000),
        outcome, request_id: requestId, metadata
      });
      if (error) throw new Error("sensitive_access_log_failed");
    };
    const audit = async (activity: string, targetTable: string, targetId: string, reason: string, metadata: Record<string, unknown> = {}) => {
      const { error } = await admin!.from("admin_activity_events").insert({
        actor_id: actorId, action: activity, module_key: "privacy_legal",
        permission_key: null, target_table: targetTable, target_id: targetId,
        outcome: "success", reason: reason.slice(0, 500), request_id: requestId, metadata
      });
      if (error) throw new Error("admin_activity_write_failed");
    };

    // User-facing legal documents: only published versions are visible or downloadable.
    if (action === "current-legal-documents") {
      const now = new Date().toISOString();
      const { data: docs, error: docError } = await admin.from("legal_documents")
        .select("id,document_type,version,title,sha256,effective_from,effective_until,requires_acceptance,reacceptance_required")
        .eq("is_published", true).lte("effective_from", now)
        .order("document_type").order("effective_from", { ascending: false });
      if (docError) throw docError;
      const current = (docs ?? []).filter((doc: { effective_until: string | null }) =>
        !doc.effective_until || doc.effective_until > now);
      const { data: acceptances, error: acceptanceError } = await admin.from("legal_acceptances")
        .select("legal_document_id,document_sha256,accepted_at,acceptance_context")
        .eq("user_id", actorId);
      if (acceptanceError) throw acceptanceError;
      const accepted = new Map((acceptances ?? []).map((item: { legal_document_id: string; document_sha256: string }) =>
        [item.legal_document_id + ":" + item.document_sha256, true]));
      return json({ documents: current.map((doc: { id: string; sha256: string; requires_acceptance: boolean }) => ({
        ...doc, accepted: accepted.has(doc.id + ":" + doc.sha256)
      })) }, 200, allowedOrigin);
    }

    if (action === "download-legal-document") {
      const id = uuidValue(body.documentId, "document_id");
      const { data: doc, error } = await admin.from("legal_documents")
        .select("id,document_type,version,title,sha256,content_markdown,is_published")
        .eq("id", id).eq("is_published", true).maybeSingle();
      if (error || !doc) throw new Error("published_document_not_found");
      const content = String(doc.content_markdown ?? "");
      const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(content));
      const actualHash = Array.from(new Uint8Array(digest)).map(v => v.toString(16).padStart(2, "0")).join("");
      if (actualHash !== doc.sha256) throw new Error("legal_document_hash_mismatch");
      const headers = new Headers({
        "Content-Type": "text/markdown; charset=utf-8",
        "Content-Disposition": 'attachment; filename="shelfshare-' + String(doc.document_type) + "-v" + String(doc.version).replace(/[^a-z0-9._-]/giu, "_") + '.md"',
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "no-referrer",
        "X-Document-SHA256": actualHash
      });
      if (allowedOrigin) {
        headers.set("Access-Control-Allow-Origin", allowedOrigin);
        headers.set("Vary", "Origin");
      }
      return new Response(content, { status: 200, headers });
    }

    if (action === "accept-legal-document") {
      const id = uuidValue(body.documentId, "document_id");
      const hash = textValue(body.sha256, "sha256", 64, 64);
      const context = textValue(body.context, "context", 2, 60);
      const source = textValue(body.source, "source", 2, 10);
      const { data, error } = await actorClient.rpc("record_legal_acceptance", {
        p_legal_document_id: id, p_document_sha256: hash, p_acceptance_context: context,
        p_source: source, p_ip_hash: null, p_user_agent_hash: null
      });
      if (error) throw error;
      return json({ accepted: true, acceptanceId: data, acceptedAt: new Date().toISOString(), documentSha256: hash }, 200, allowedOrigin);
    }

    if (action === "create-privacy-request") {
      const type = textValue(body.requestType, "request_type", 4, 30);
      const description = textValue(body.description, "description", 10, 5000);
      const { data, error } = await actorClient.rpc("create_privacy_request", {
        p_request_type: type, p_description: description
      });
      if (error) throw error;
      return json({ created: true, requestId: data }, 201, allowedOrigin);
    }

    if (action === "my-privacy-requests") {
      const { data, error } = await admin.from("privacy_requests")
        .select("id,request_reference,request_type,status,description,received_at,updated_at,completed_at,due_at,resolution_summary")
        .eq("requester_id", actorId).order("received_at", { ascending: false }).limit(100);
      if (error) throw error;
      return json({ requests: data ?? [] }, 200, allowedOrigin);
    }

    if (action === "record-consent") {
      const purpose = textValue(body.purpose, "purpose", 3, 50);
      const consentAction = textValue(body.consentAction, "consent_action", 3, 20);
      const noticeVersion = textValue(body.noticeVersion, "notice_version", 1, 40);
      const source = textValue(body.source, "source", 2, 10);
      const { data, error } = await actorClient.rpc("record_privacy_consent", {
        p_purpose_key: purpose, p_action: consentAction,
        p_notice_version: noticeVersion, p_source: source
      });
      if (error) throw error;
      if (consentAction === "withdrawn" && purpose === "marketing_communications") {
        const { error: prefError } = await admin.from("notification_preferences")
          .update({ sms_marketing_enabled: false }).eq("user_id", actorId);
        if (prefError && !/0 rows|not found/iu.test(prefError.message)) throw prefError;
      }
      return json({ recorded: true, consentEventId: data, purpose, action: consentAction }, 200, allowedOrigin);
    }

    if (action === "my-consent-history") {
      const { data, error } = await admin.from("privacy_consent_events")
        .select("id,purpose_key,action,notice_version,source,recorded_at")
        .eq("user_id", actorId).order("recorded_at", { ascending: false }).limit(200);
      if (error) throw error;
      return json({ events: data ?? [] }, 200, allowedOrigin);
    }

    // Staff queue and case detail.
    if (action === "privacy-queue") {
      await requirePermission("privacy.read");
      const limit = Math.max(1, Math.min(Number(body.limit ?? 100), 200));
      let query = admin.from("privacy_requests")
        .select("id,request_reference,requester_id,request_type,status,assigned_to,received_at,updated_at,identity_verified_at,completed_at,due_at,legal_hold")
        .order("received_at", { ascending: true }).limit(limit);
      if (typeof body.status === "string" && body.status !== "all") query = query.eq("status", body.status);
      if (typeof body.requestType === "string" && body.requestType !== "all") query = query.eq("request_type", body.requestType);
      const { data, error } = await query;
      if (error) throw error;
      return json({ requests: data ?? [] }, 200, allowedOrigin);
    }

    if (action === "privacy-detail") {
      await requirePermission("privacy.manage"); requireAal2();
      const id = uuidValue(body.requestId, "request_id");
      const { data: item, error: requestError } = await admin.from("privacy_requests").select("*").eq("id", id).maybeSingle();
      if (requestError || !item) throw new Error("privacy_request_not_found");
      const { data: events, error: eventError } = await admin.from("privacy_request_events")
        .select("id,event_type,old_status,new_status,public_message,internal_reason,metadata,created_at")
        .eq("privacy_request_id", id).order("created_at");
      if (eventError) throw eventError;
      await logSensitive("privacy_request", "privacy_requests", id, item.requester_id, "Review privacy request case and fulfilment history");
      return json({ request: item, events: events ?? [] }, 200, allowedOrigin);
    }

    if (action === "privacy-update") {
      await requirePermission("privacy.manage"); requireAal2();
      const id = uuidValue(body.requestId, "request_id");
      const status = textValue(body.status, "status", 4, 30);
      const assignedTo = body.assignedTo === null || body.assignedTo === "" ? null : uuidValue(body.assignedTo, "assigned_to");
      const resolution = body.resolutionSummary === undefined ? null : textValue(body.resolutionSummary, "resolution_summary", 5, 4000);
      const reason = textValue(body.reason, "reason", 20, 2000);
      const { error } = await actorClient.rpc("admin_update_privacy_request", {
        p_request_id: id, p_status: status, p_assigned_to: assignedTo,
        p_resolution_summary: resolution, p_reason: reason
      });
      if (error) throw error;
      await audit("privacy_request_updated", "privacy_requests", id, reason, { status, assigned: Boolean(assignedTo) });
      return json({ updated: true }, 200, allowedOrigin);
    }

    if (action === "privacy-export") {
      await requirePermission("privacy.read"); requireAal2();
      const { data, error } = await admin.from("privacy_requests")
        .select("request_reference,request_type,status,received_at,updated_at,completed_at,assigned_to,legal_hold")
        .order("received_at", { ascending: false }).limit(1000);
      if (error) throw error;
      const fields = ["request_reference","request_type","status","received_at","updated_at","completed_at","assigned_to","legal_hold"];
      await audit("privacy_requests_exported", "privacy_requests", "aggregate", "Privacy request operations export", { rows: data?.length ?? 0 });
      return new Response(toCsv((data ?? []) as Record<string, unknown>[], fields), { status: 200, headers: {
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition": 'attachment; filename="shelfshare-privacy-requests.csv"',
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
        "Access-Control-Allow-Origin": allowedOrigin,
        "Vary": "Origin"
      }});
    }

    // Legal document administration.
    if (action === "legal-list") {
      await requirePermission("legal.read");
      const { data, error } = await admin.from("legal_documents")
        .select("id,document_type,version,title,sha256,review_status,is_published,effective_from,effective_until,requires_acceptance,reacceptance_required,created_at,updated_at,approved_at,counsel_reviewed_at")
        .order("document_type").order("created_at", { ascending: false }).limit(300);
      if (error) throw error;
      return json({ documents: data ?? [] }, 200, allowedOrigin);
    }

    if (action === "legal-draft-detail") {
      await requirePermission("legal.draft.write"); requireAal2();
      const id = uuidValue(body.documentId, "document_id");
      const { data: doc, error } = await admin.from("legal_documents")
        .select("id,document_type,version,title,content_uri,sha256,content_markdown,review_status,requires_acceptance,reacceptance_required,review_notes")
        .eq("id", id).eq("is_published", false).maybeSingle();
      if (error || !doc) throw new Error("legal_draft_not_found");
      await logSensitive("legal_document_draft", "legal_documents", id, null, "Read unpublished legal policy draft");
      return json({ document: doc }, 200, allowedOrigin);
    }

    if (action === "legal-save-draft") {
      await requirePermission("legal.draft.write"); requireAal2();
      const id = body.documentId ? uuidValue(body.documentId, "document_id") : null;
      const documentType = textValue(body.documentType, "document_type", 3, 60);
      const version = textValue(body.version, "version", 3, 40);
      const title = textValue(body.title, "title", 3, 160);
      const path = textValue(body.contentUri, "content_uri", 10, 180);
      const markdown = textValue(body.contentMarkdown, "content_markdown", 100, 150000);
      const requiresAcceptance = body.requiresAcceptance !== false;
      const reacceptanceRequired = body.reacceptanceRequired !== false;
      const notes = body.reviewNotes === undefined ? "" : textValue(body.reviewNotes, "review_notes", 0, 4000);
      const { data, error } = await actorClient.rpc("admin_save_legal_draft", {
        p_document_id: id, p_document_type: documentType, p_version: version,
        p_title: title, p_content_uri: path, p_content_markdown: markdown,
        p_requires_acceptance: requiresAcceptance, p_reacceptance_required: reacceptanceRequired,
        p_review_notes: notes
      });
      if (error) throw error;
      await audit("legal_draft_saved", "legal_documents", String(data), "Legal draft saved", { documentType, version });
      return json({ saved: true, documentId: data }, 200, allowedOrigin);
    }

    if (action === "legal-submit-review") {
      await requirePermission("legal.draft.write"); requireAal2();
      const id = uuidValue(body.documentId, "document_id");
      const notes = textValue(body.reviewNotes, "review_notes", 20, 4000);
      const { error } = await actorClient.rpc("admin_submit_legal_draft", { p_document_id: id, p_review_notes: notes });
      if (error) throw error;
      return json({ submitted: true }, 200, allowedOrigin);
    }

    if (action === "legal-request-publish") {
      await requirePermission("legal.publish.request"); requireAal2();
      const id = uuidValue(body.documentId, "document_id");
      const reason = textValue(body.reason, "reason", 30, 2000);
      const idempotencyKey = textValue(body.idempotencyKey, "idempotency_key", 20, 120);
      const { data: document, error: readError } = await admin.from("legal_documents")
        .select("version,sha256,review_status,is_published").eq("id", id).maybeSingle();
      if (readError || !document || document.is_published || document.review_status !== "in_review") {
        throw new Error("legal_document_not_ready_for_publication");
      }
      const { data, error } = await actorClient.rpc("admin_request_approval", {
        p_action_key: "legal.publish", p_target_id: id,
        p_request_payload: { version: document.version, sha256: document.sha256 },
        p_reason: reason, p_idempotency_key: idempotencyKey
      });
      if (error) throw error;
      return json({ approvalRequestId: data }, 201, allowedOrigin);
    }

    if (action === "legal-publish") {
      await requirePermission("legal.publish.approve"); requireAal2();
      const id = uuidValue(body.documentId, "document_id");
      const approvalId = uuidValue(body.approvalRequestId, "approval_request_id");
      const effectiveFrom = textValue(body.effectiveFrom, "effective_from", 20, 40);
      const { error } = await actorClient.rpc("admin_publish_legal_document", {
        p_document_id: id, p_approval_request_id: approvalId, p_effective_from: effectiveFrom
      });
      if (error) throw error;
      return json({ published: true, documentId: id }, 200, allowedOrigin);
    }

    // Incident and retention workflows.
    if (action === "incident-list") {
      await requirePermission("privacy.incidents.read"); requireAal2();
      const { data, error } = await admin.from("privacy_breach_incidents")
        .select("id,incident_reference,detected_at,severity,status,data_categories,estimated_affected_subjects,systems_affected,created_at,updated_at")
        .order("detected_at", { ascending: false }).limit(200);
      if (error) throw error;
      await logSensitive("breach_incident", "privacy_breach_incidents", "list", null, "Read privacy/security incident register");
      return json({ incidents: data ?? [] }, 200, allowedOrigin);
    }

    if (action === "incident-create") {
      await requirePermission("privacy.incidents.manage"); requireAal2();
      const reference = textValue(body.incidentReference, "incident_reference", 10, 50);
      const detectedAt = textValue(body.detectedAt, "detected_at", 20, 40);
      const severity = textValue(body.severity, "severity", 3, 20);
      const categories = Array.isArray(body.dataCategories) ? body.dataCategories.map(x => textValue(x, "data_category", 2, 60)) : [];
      const systems = Array.isArray(body.systemsAffected) ? body.systemsAffected.map(x => textValue(x, "system", 2, 80)) : [];
      const estimated = body.estimatedSubjects === null || body.estimatedSubjects === undefined ? null : Number(body.estimatedSubjects);
      const summary = textValue(body.factualSummary, "factual_summary", 20, 8000);
      const containment = body.containment === undefined ? "" : textValue(body.containment, "containment", 0, 4000);
      const { data, error } = await actorClient.rpc("admin_record_privacy_incident", {
        p_incident_reference: reference, p_detected_at: detectedAt, p_severity: severity,
        p_data_categories: categories, p_estimated_subjects: estimated,
        p_systems_affected: systems, p_factual_summary: summary, p_containment: containment
      });
      if (error) throw error;
      return json({ created: true, incidentId: data }, 201, allowedOrigin);
    }

    if (action === "incident-update") {
      await requirePermission("privacy.incidents.manage"); requireAal2();
      const id = uuidValue(body.incidentId, "incident_id");
      const reason = textValue(body.reason, "reason", 20, 2000);
      const allowedFields = ["status","containment_actions","risk_assessment","notification_assessment",
        "authority_notification_reference","affected_user_notification_at","authority_notification_at","root_cause","remediation","closed_at"];
      const patch: Record<string, unknown> = { updated_by: actorId, updated_at: new Date().toISOString() };
      for (const field of allowedFields) {
        if (body[field] !== undefined) patch[field] = body[field];
      }
      if (typeof patch.status === "string" && !["detected","triage","contained","investigating","notified","remediating","closed"].includes(patch.status)) {
        throw new Error("invalid_incident_status");
      }
      if (Object.keys(patch).length <= 2) throw new Error("incident_update_fields_required");
      const { error } = await admin.from("privacy_breach_incidents").update(patch).eq("id", id);
      if (error) throw error;
      await audit("privacy_incident_updated", "privacy_breach_incidents", id, reason, { fields: Object.keys(patch) });
      return json({ updated: true }, 200, allowedOrigin);
    }

    if (action === "retention-list") {
      await requirePermission("privacy.retention.read"); requireAal2();
      const { data, error } = await admin.from("data_retention_policies")
        .select("id,rule_key,version,data_class,retention_days,rationale,legal_basis_note,status,created_by,approved_by,approved_at,effective_from,effective_until")
        .order("data_class").order("created_at", { ascending: false }).limit(300);
      if (error) throw error;
      return json({ policies: data ?? [] }, 200, allowedOrigin);
    }

    if (action === "retention-save") {
      await requirePermission("privacy.retention.manage"); requireAal2();
      const ruleKey = textValue(body.ruleKey, "rule_key", 3, 80);
      const version = textValue(body.version, "version", 3, 40);
      const dataClass = textValue(body.dataClass, "data_class", 3, 40);
      const days = Number(body.retentionDays);
      const rationale = textValue(body.rationale, "rationale", 20, 2000);
      const basis = textValue(body.legalBasisNote, "legal_basis_note", 10, 2000);
      const { data, error } = await actorClient.rpc("admin_save_retention_policy", {
        p_rule_key: ruleKey, p_version: version, p_data_class: dataClass,
        p_retention_days: days, p_rationale: rationale, p_legal_basis_note: basis
      });
      if (error) throw error;
      return json({ saved: true, policyId: data }, 201, allowedOrigin);
    }

    if (action === "retention-approve") {
      await requirePermission("privacy.retention.approve"); requireAal2();
      const id = uuidValue(body.policyId, "policy_id");
      const effectiveFrom = textValue(body.effectiveFrom, "effective_from", 20, 40);
      const reason = textValue(body.reason, "reason", 30, 2000);
      const { error } = await actorClient.rpc("admin_approve_retention_policy", {
        p_policy_id: id, p_effective_from: effectiveFrom, p_reason: reason
      });
      if (error) throw error;
      return json({ approved: true }, 200, allowedOrigin);
    }

    if (action === "privacy-access-log") {
      await requirePermission("privacy.accesslog.read"); requireAal2();
      const limit = Math.max(1, Math.min(Number(body.limit ?? 100), 300));
      const { data, error } = await admin.from("sensitive_data_access_events")
        .select("id,actor_id,subject_user_id,data_class,resource_table,resource_id,purpose,outcome,request_id,accessed_at")
        .order("accessed_at", { ascending: false }).limit(limit);
      if (error) throw error;
      await logSensitive("privacy_request", "sensitive_data_access_events", "list", null, "Read sensitive data access audit log");
      return json({ events: data ?? [] }, 200, allowedOrigin);
    }

    if (action === "privacy-hold-create") {
      await requirePermission("privacy.manage"); requireAal2();
      const userId = uuidValue(body.userId, "user_id");
      const dataClass = textValue(body.dataClass, "data_class", 2, 60);
      const reason = textValue(body.reason, "reason", 20, 2000);
      const sourceReference = body.sourceReference ? textValue(body.sourceReference, "source_reference", 2, 100) : null;
      const { data, error } = await admin.from("privacy_legal_holds")
        .insert({ subject_user_id: userId, data_class: dataClass, reason, source_reference: sourceReference, created_by: actorId })
        .select("id").single();
      if (error) throw error;
      await audit("privacy_legal_hold_created", "privacy_legal_holds", data.id, reason, { dataClass });
      return json({ created: true, holdId: data.id }, 201, allowedOrigin);
    }

    if (action === "privacy-hold-release") {
      await requirePermission("privacy.manage"); requireAal2();
      const id = uuidValue(body.holdId, "hold_id");
      const reason = textValue(body.reason, "reason", 20, 2000);
      const { error } = await admin.from("privacy_legal_holds").update({
        released_by: actorId, released_at: new Date().toISOString()
      }).eq("id", id).is("released_at", null);
      if (error) throw error;
      await audit("privacy_legal_hold_released", "privacy_legal_holds", id, reason);
      return json({ released: true }, 200, allowedOrigin);
    }

    if (action === "privacy-erase-request") {
      await requirePermission("privacy.erase.request"); requireAal2();
      const id = uuidValue(body.requestId, "request_id");
      const reason = textValue(body.reason, "reason", 30, 2000);
      const { data: item, error: readError } = await admin.from("privacy_requests")
        .select("id,request_type,status").eq("id", id).maybeSingle();
      if (readError || !item || item.request_type !== "erasure") throw new Error("erasure_request_not_found");
      const { data, error } = await actorClient.rpc("admin_request_approval", {
        p_action_key: "privacy.erase", p_target_id: id,
        p_request_payload: { scope: ["identity_document_delete","profile_anonymise"], requestId: id },
        p_reason: reason, p_idempotency_key: makeKey("privacy-erase")
      });
      if (error) throw error;
      return json({ approvalRequestId: data }, 201, allowedOrigin);
    }

    if (action === "privacy-erase-execute") {
      await requirePermission("privacy.erase.approve"); requireAal2();
      const id = uuidValue(body.approvalRequestId, "approval_request_id");
      const { data, error } = await actorClient.rpc("admin_queue_privacy_erasure", { p_approval_request_id: id });
      if (error) throw error;
      return json({ queuedJobs: data }, 200, allowedOrigin);
    }

    return json({ error: "unsupported_action", requestId }, 400, allowedOrigin);
  } catch (error) {
    const message = error instanceof Error ? error.message : "unexpected_error";
    return json({ error: message, requestId }, errorStatus(error), allowedOrigin);
  }
});

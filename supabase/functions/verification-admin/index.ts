import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";

const url = Deno.env.get("SUPABASE_URL")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const allowedOrigin = Deno.env.get("APP_ORIGIN") ?? "http://localhost:5173";
const corsHeaders = {
  "Access-Control-Allow-Origin": allowedOrigin,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin"
};

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" }
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply(405, { error: "Method not allowed" });
  const origin = req.headers.get("origin");
  if (origin && origin !== allowedOrigin) return reply(403, { error: "Origin not allowed" });

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return reply(401, { error: "Authentication required" });

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false }
  });
  const service = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false }
  });

  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) return reply(401, { error: "Invalid session" });

  const { data: roleRows, error: roleError } = await service
    .from("user_roles")
    .select("role")
    .eq("user_id", user.id)
    .is("revoked_at", null);
  if (roleError) return reply(500, { error: "Unable to check staff permissions" });
  const roles = (roleRows ?? []).map((row) => row.role as string);
  const allowedRoles = ["verification_reviewer", "admin", "super_admin"];
  if (!roles.some((role) => allowedRoles.includes(role))) {
    return reply(403, { error: "Verification reviewer permission required" });
  }

  let payload: Record<string, unknown>;
  try { payload = await req.json(); } catch { return reply(400, { error: "Invalid JSON body" }); }
  const action = payload.action;

  if (action === "me") return reply(200, { authorized: true, roles });

  if (action === "list") {
    const { data: cases, error } = await service
      .from("verification_cases")
      .select("id,user_id,status,assigned_reviewer_id,submitted_at,assigned_at,reviewed_at,decision_reason,requested_information,internal_notes")
      .in("status", ["submitted", "under_review", "needs_info", "resubmission_required"])
      .order("submitted_at", { ascending: true })
      .limit(100);
    if (error) return reply(500, { error: "Unable to load verification queue" });
    const userIds = [...new Set((cases ?? []).map((item) => item.user_id))];
    const { data: profiles } = userIds.length
      ? await service.from("profiles").select("id,display_name,date_of_birth,account_status").in("id", userIds)
      : { data: [] };
    const profileById = new Map((profiles ?? []).map((profile) => [profile.id, profile]));
    const { data: auditRows } = userIds.length
      ? await service.from("verification_audit")
          .select("id,user_id,actor_user_id,action,from_status,to_status,reason_code,created_at,metadata")
          .in("user_id", userIds)
          .order("created_at", { ascending: false })
          .limit(500)
      : { data: [] };
    const caseIds = (cases ?? []).map((item) => item.id);
    const { data: documentAccessRows } = caseIds.length
      ? await service.from("verification_document_access_audit")
          .select("id,verification_case_id,document_id,actor_user_id,accessed_at,purpose")
          .in("verification_case_id", caseIds)
          .order("accessed_at", { ascending: false })
          .limit(500)
      : { data: [] };
    const enriched = await Promise.all((cases ?? []).map(async (item) => {
      const { data: authUser } = await service.auth.admin.getUserById(item.user_id);
      const phone = authUser.user?.phone ?? "";
      const maskedPhone = phone.length > 4 ? `•••• •••• ${phone.slice(-4)}` : "Unavailable";
      const { data: docs } = await service
        .from("identity_documents")
        .select("id,document_type,document_last4,status,submitted_at")
        .eq("verification_case_id", item.id);
      const fileKinds = await service.from("verification_case_files")
        .select("id,file_kind")
        .eq("verification_case_id", item.id);
      return {
        ...item,
        display_name: profileById.get(item.user_id)?.display_name ?? "Member",
        date_of_birth: profileById.get(item.user_id)?.date_of_birth ?? null,
        account_status: profileById.get(item.user_id)?.account_status ?? "unknown",
        masked_phone: maskedPhone,
        documents: docs ?? [],
        file_kinds: fileKinds.data ?? [],
        audit_history: (auditRows ?? [])
          .filter((entry) => (entry.metadata as Record<string, unknown> | null)?.case_id === item.id || entry.action === "registration_completed")
          .filter((entry) => entry.user_id === item.user_id),
        document_access_history: (documentAccessRows ?? []).filter((entry) => entry.verification_case_id === item.id)
      };
    }));
    return reply(200, { cases: enriched });
  }

  if (action === "preview") {
    const caseId = String(payload.case_id ?? "");
    const fileId = String(payload.file_id ?? "");
    const purpose = String(payload.purpose ?? "").trim();
    if (!caseId || !fileId || purpose.length < 5) {
      return reply(400, { error: "Case, file and a review purpose are required" });
    }
    const { data: file, error: fileError } = await service
      .from("verification_case_files")
      .select("id,verification_case_id,user_id,storage_bucket,object_key")
      .eq("id", fileId)
      .eq("verification_case_id", caseId)
      .maybeSingle();
    if (fileError || !file) return reply(404, { error: "Verification file not found" });
    const { data: verificationCase } = await service.from("verification_cases")
      .select("user_id")
      .eq("id", caseId)
      .maybeSingle();
    if (!verificationCase || file.user_id !== verificationCase.user_id) {
      return reply(404, { error: "Verification file not found" });
    }
    if (file.user_id === user.id) return reply(403, { error: "Reviewers cannot preview their own verification file" });
    const { data: signed, error: signedError } = await service.storage
      .from(file.storage_bucket)
      .createSignedUrl(file.object_key, 60);
    if (signedError || !signed?.signedUrl) return reply(500, { error: "Unable to create secure preview" });
    const { error: auditError } = await service.from("verification_document_access_audit").insert({
      verification_case_id: caseId,
      document_id: fileId,
      actor_user_id: user.id,
      purpose: purpose.slice(0, 500)
    });
    if (auditError) return reply(500, { error: "Access audit could not be recorded; preview blocked" });
    return reply(200, { signed_url: signed.signedUrl, expires_in_seconds: 60 });
  }

  if (action === "assign" || action === "decision") {
    const caseId = String(payload.case_id ?? "");
    const rpcArgs = {
      p_case_id: caseId,
      p_action: action === "assign" ? "assign" : String(payload.decision ?? ""),
      p_reason: typeof payload.reason === "string" ? payload.reason : null,
      p_internal_notes: typeof payload.internal_notes === "string" ? payload.internal_notes : null,
      p_assignee: typeof payload.assignee_id === "string" ? payload.assignee_id : null
    };
    const { error } = await userClient.rpc("review_verification_case", rpcArgs);
    if (error) return reply(400, { error: error.message });
    return reply(200, { success: true });
  }

  return reply(400, { error: "Unsupported action" });
});

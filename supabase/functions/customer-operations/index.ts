import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildCsv } from "../_shared/notifications.ts";

type Body = {
  action?: string;
  notificationId?: string;
  inAppEnabled?: boolean;
  smsServiceEnabled?: boolean;
  smsMarketingEnabled?: boolean;
  emailEnabled?: boolean;
  pushEnabled?: boolean;
  consentSource?: string;
  consentVersion?: string;
  category?: string;
  subject?: string;
  description?: string;
  priority?: string;
  ticketId?: string;
  message?: string;
  internal?: boolean;
  status?: string;
  assignedTo?: string | null;
  reason?: string;
  limit?: number;
};

function json(body: unknown, status = 200, origin = ""): Response {
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
  return new Response(JSON.stringify(body), { status, headers });
}
function csvResponse(content: string, filename: string, origin: string): Response {
  return new Response(content, { status: 200, headers: {
    "Content-Type": "text/csv; charset=utf-8",
    "Content-Disposition": 'attachment; filename="' + filename + '"',
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Access-Control-Allow-Origin": origin,
    "Vary": "Origin"
  }});
}
function tokenClaims(token: string): Record<string, unknown> {
  const part = token.split(".")[1];
  if (!part) throw new Error("invalid_session_token");
  const normalized = part.replace(/-/gu, "+").replace(/_/gu, "/");
  return JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")));
}
function textValue(value: unknown, field: string, min = 1, max = 5000): string {
  if (typeof value !== "string") throw new Error("invalid_" + field);
  const result = value.trim();
  if (result.length < min || result.length > max) throw new Error("invalid_" + field);
  return result;
}
function errorStatus(error: unknown): number {
  const message = error instanceof Error ? error.message : "";
  if (/authentication|invalid jwt|session required/iu.test(message)) return 401;
  if (/permission|mfa|aal2|access denied|not authorized/iu.test(message)) return 403;
  if (/not found/iu.test(message)) return 404;
  if (/closed|already|conflict|pending/iu.test(message)) return 409;
  return 400;
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("Origin") ?? "";
  const allowed = (Deno.env.get("CUSTOMER_APP_ORIGINS") ?? Deno.env.get("ADMIN_PORTAL_ORIGINS") ?? Deno.env.get("APP_ORIGIN") ?? "")
    .split(",").map(value => value.trim()).filter(Boolean);
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

  try {
    const authorization = request.headers.get("Authorization") ?? "";
    const accessToken = authorization.replace(/^Bearer\s+/iu, "");
    if (!accessToken) return json({ error: "authentication_required" }, 401, allowedOrigin);
    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    if (!url || !anon) throw new Error("server_configuration_missing");

    const client = createClient(url, anon, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: authorization } }
    });
    const { data: authData, error: authError } = await client.auth.getUser();
    if (authError || !authData.user) throw new Error("authentication_required");
    const rawBody = await request.text();
    if (rawBody.length > 20000) throw new Error("request_body_too_large");
    const body = JSON.parse(rawBody) as Body;
    const action = textValue(body.action, "action", 2, 40);
    const requireSupportPermission = async () => {
      const [{ data: supportPermission, error: supportError }, { data: grievancePermission, error: grievanceError }] = await Promise.all([
        client.rpc("admin_has_permission", { p_permission_key: "support.manage" }),
        client.rpc("admin_has_permission", { p_permission_key: "grievances.manage" })
      ]);
      if (supportError || grievanceError) throw new Error("support_permission_check_failed");
      if (supportPermission !== true && grievancePermission !== true) throw new Error("support_management_permission_denied");
    };

    if (action === "notifications") {
      const limit = Math.max(1, Math.min(Number(body.limit ?? 50), 100));
      const { data, error } = await client.from("notifications")
        .select("id,template_key,title,body,payload,status,scheduled_at,sent_at,read_at,created_at")
        .eq("user_id", authData.user.id).eq("channel", "in_app")
        .order("created_at", { ascending: false }).limit(limit);
      if (error) throw error;
      return json({ notifications: data ?? [] }, 200, allowedOrigin);
    }

    if (action === "mark-read") {
      const notificationId = textValue(body.notificationId, "notification_id", 36, 36);
      const { error } = await client.rpc("mark_notification_read", { p_notification_id: notificationId });
      if (error) throw error;
      return json({ ok: true }, 200, allowedOrigin);
    }

    if (action === "get-notification-preferences") {
      const { data, error } = await client.rpc("get_my_notification_preferences");
      if (error) throw error;
      return json({ preferences: data }, 200, allowedOrigin);
    }

    if (action === "update-notification-preferences") {
      if (typeof body.inAppEnabled !== "boolean" ||
          typeof body.smsServiceEnabled !== "boolean" ||
          typeof body.smsMarketingEnabled !== "boolean") {
        throw new Error("notification_preferences_required");
      }
      const { data, error } = await client.rpc("update_notification_preferences", {
        p_in_app_enabled: body.inAppEnabled,
        p_sms_service_enabled: body.smsServiceEnabled,
        p_sms_marketing_enabled: body.smsMarketingEnabled,
        p_email_enabled: body.emailEnabled === true,
        p_push_enabled: body.pushEnabled === true,
        p_consent_source: body.consentSource ?? null,
        p_consent_version: body.consentVersion ?? null
      });
      if (error) throw error;
      return json({ preferences: data }, 200, allowedOrigin);
    }

    if (action === "create-ticket") {
      const { data, error } = await client.rpc("create_support_ticket", {
        p_category: textValue(body.category, "category", 2, 40),
        p_subject: textValue(body.subject, "subject", 4, 160),
        p_description: textValue(body.description, "description", 10, 5000),
        p_priority: body.priority ?? "normal"
      });
      if (error) throw error;
      return json({ ticketId: data }, 201, allowedOrigin);
    }

    if (action === "reply-ticket") {
      const { data, error } = await client.rpc("reply_support_ticket", {
        p_ticket_id: textValue(body.ticketId, "ticket_id", 36, 36),
        p_body: textValue(body.message, "message", 1, 5000),
        p_internal: body.internal === true
      });
      if (error) throw error;
      return json({ messageId: data }, 201, allowedOrigin);
    }

    if (action === "my-tickets") {
      const { data: tickets, error } = await client.from("grievance_tickets")
        .select("id,ticket_number,category,subject,status,priority,created_at,updated_at,first_response_due_at,resolution_due_at,first_response_at,sla_breached_at,escalated_at,resolved_at,closed_at")
        .eq("requester_id", authData.user.id).order("created_at", { ascending: false }).limit(50);
      if (error) throw error;
      const ids = (tickets ?? []).map((ticket: { id: string }) => ticket.id);
      let messages: unknown[] = [];
      let history: unknown[] = [];
      if (ids.length) {
        const [{ data: messageData, error: messageError }, { data: historyData, error: historyError }] = await Promise.all([
          client.from("support_ticket_messages")
            .select("id,ticket_id,author_type,body,created_at")
            .in("ticket_id", ids).eq("is_internal", false).order("created_at", { ascending: true }).limit(500),
          client.from("support_ticket_history")
            .select("id,ticket_id,event_type,old_status,new_status,old_priority,new_priority,created_at")
            .in("ticket_id", ids).order("created_at", { ascending: true }).limit(500)
        ]);
        if (messageError || historyError) throw messageError ?? historyError;
        messages = messageData ?? [];
        history = historyData ?? [];
      }
      return json({ tickets: tickets ?? [], messages, history }, 200, allowedOrigin);
    }

    if (action === "support-categories") {
      const { data, error } = await client.from("support_ticket_categories")
        .select("category_key,label,sort_order").eq("is_active", true).order("sort_order");
      if (error) throw error;
      return json({ categories: data ?? [] }, 200, allowedOrigin);
    }

    if (action === "ticket-detail") {
      await requireSupportPermission();
      const ticketId = textValue(body.ticketId, "ticket_id", 36, 36);
      const [{ data: ticket, error: ticketError }, { data: messages, error: messagesError }, { data: history, error: historyError }] = await Promise.all([
        client.from("grievance_tickets").select("*").eq("id", ticketId).single(),
        client.from("support_ticket_messages").select("id,author_id,author_type,body,is_internal,created_at").eq("ticket_id", ticketId).order("created_at"),
        client.from("support_ticket_history").select("id,actor_id,event_type,old_status,new_status,old_priority,new_priority,old_assignee,new_assignee,reason,created_at").eq("ticket_id", ticketId).order("created_at")
      ]);
      if (ticketError || messagesError || historyError) throw ticketError ?? messagesError ?? historyError;
      return json({ ticket, messages: messages ?? [], history: history ?? [] }, 200, allowedOrigin);
    }

    if (action === "support-queue") {
      await requireSupportPermission();
      const limit = Math.max(1, Math.min(Number(body.limit ?? 100), 200));
      let query = client.from("grievance_tickets")
        .select("id,ticket_number,requester_id,category,subject,description,status,priority,assigned_to,created_at,updated_at,first_response_due_at,resolution_due_at,first_response_at,sla_breached_at,escalated_at,resolved_at,closed_at");
      if (!body.status || body.status === "open") query = query.not("status", "in", '("resolved","closed")');
      else if (body.status !== "all") query = query.eq("status", body.status);
      if (body.category) query = query.eq("category", body.category);
      if (body.priority) query = query.eq("priority", body.priority);
      if (body.assignedTo) query = query.eq("assigned_to", body.assignedTo);
      const { data, error } = await query.order("created_at", { ascending: true }).limit(limit);
      if (error) throw error;
      const rank: Record<string, number> = { urgent: 4, high: 3, normal: 2, low: 1 };
      const ordered = (data ?? []).sort((left: { priority: string }, right: { priority: string }) =>
        (rank[right.priority] ?? 0) - (rank[left.priority] ?? 0));
      return json({ tickets: ordered }, 200, allowedOrigin);
    }

    if (action === "manage-ticket") {
      const claims = tokenClaims(accessToken);
      if (claims.aal !== "aal2") throw new Error("step_up_mfa_aal2_required");
      const { error } = await client.rpc("manage_support_ticket", {
        p_ticket_id: textValue(body.ticketId, "ticket_id", 36, 36),
        p_status: body.status,
        p_priority: body.priority,
        p_assigned_to: body.assignedTo ?? null,
        p_reason: textValue(body.reason, "reason", 15, 1000)
      });
      if (error) throw error;
      return json({ ok: true }, 200, allowedOrigin);
    }

    if (action === "support-export") {
      await requireSupportPermission();
      const claims = tokenClaims(accessToken);
      if (claims.aal !== "aal2") throw new Error("step_up_mfa_aal2_required");
      const limit = Math.max(1, Math.min(Number(body.limit ?? 1000), 1000));
      const { data, error } = await client.from("grievance_tickets")
        .select("ticket_number,category,subject,status,priority,assigned_to,created_at,first_response_due_at,resolution_due_at,first_response_at,sla_breached_at,escalated_at,resolved_at,closed_at")
        .order("created_at", { ascending: false }).limit(limit);
      if (error) throw error;
      const fields = ["ticket_number","category","subject","status","priority","assigned_to",
        "created_at","first_response_due_at","resolution_due_at","first_response_at",
        "sla_breached_at","escalated_at","resolved_at","closed_at"];
      return csvResponse(buildCsv((data ?? []) as Record<string, unknown>[], fields),
        "shelfshare-support-tickets.csv", allowedOrigin);
    }

    return json({ error: "unsupported_action" }, 400, allowedOrigin);
  } catch (error) {
    const message = error instanceof Error ? error.message : "request_failed";
    return json({ error: message.slice(0, 180) }, errorStatus(error), allowedOrigin);
  }
});

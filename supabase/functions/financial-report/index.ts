import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildCsv } from "../_shared/notifications.ts";

function constantTimeEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) mismatch |= a[i] ^ b[i];
  return mismatch === 0;
}
function json(body: unknown, status: number, origin: string): Response {
  return new Response(JSON.stringify(body), { status, headers: {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "Access-Control-Allow-Origin": origin,
    "Vary": "Origin",
    "X-Content-Type-Options": "nosniff"
  }});
}
function claimsFrom(token: string): Record<string, unknown> {
  const part = token.split(".")[1];
  if (!part) throw new Error("invalid_session_token");
  const normalized = part.replace(/-/gu, "+").replace(/_/gu, "/");
  return JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")));
}
function validDate(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/u.test(value) &&
    !Number.isNaN(Date.parse(value)) && new Date(value).toISOString().slice(0,10) === value;
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("Origin") ?? "";
  const allowed = (Deno.env.get("FINANCE_REPORT_ORIGINS") ?? Deno.env.get("ADMIN_PORTAL_ORIGINS") ?? "")
    .split(",").map(value => value.trim()).filter(Boolean);
  const allowedOrigin = origin && allowed.includes(origin) ? origin : "";
  if (request.method === "OPTIONS") {
    if (!allowedOrigin) return json({ error: "origin_not_allowed" },403,"");
    return new Response(null,{status:204,headers:{
      "Access-Control-Allow-Origin":allowedOrigin,
      "Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info",
      "Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin"
    }});
  }
  if (request.method !== "POST") return json({error:"method_not_allowed"},405,allowedOrigin);
  if (origin && !allowedOrigin) return json({error:"origin_not_allowed"},403,"");

  try {
    const authorization = request.headers.get("Authorization") ?? "";
    const token = authorization.replace(/^Bearer\s+/iu,"");
    if (!token) throw new Error("authentication_required");
    if (claimsFrom(token).aal !== "aal2") throw new Error("step_up_mfa_aal2_required");
    const body = await request.json() as { from?: unknown; to?: unknown; format?: unknown };
    if (!validDate(body.from) || !validDate(body.to)) throw new Error("invalid_report_dates");
    const from = new Date(body.from + "T00:00:00Z");
    const to = new Date(body.to + "T00:00:00Z");
    const rangeDays = (to.getTime() - from.getTime()) / 86400000;
    if (rangeDays < 0 || rangeDays > 366) throw new Error("report_range_exceeds_366_days");

    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    if (!url || !anon) throw new Error("server_configuration_missing");
    const client = createClient(url,anon,{
      auth:{persistSession:false,autoRefreshToken:false},
      global:{headers:{Authorization:authorization}}
    });
    const {data:userResult,error:userError}=await client.auth.getUser();
    if(userError || !userResult.user) throw new Error("authentication_required");
    const {data:allowedRead,error:permissionError}=await client.rpc("admin_has_permission",{
      p_permission_key:"finance.analytics.read"
    });
    if(permissionError) throw permissionError;
    if(allowedRead!==true) throw new Error("finance_analytics_permission_denied");
    const {data,error}=await client.rpc("get_admin_financial_analytics",{
      p_from:body.from,p_to:body.to
    });
    if(error) throw error;
    if (body.format === "json") {
      return json({
        period: data?.period,
        summary: data?.summary,
        locality_performance: data?.locality_performance ?? [],
        daily_performance: data?.daily_performance ?? []
      }, 200, allowedOrigin);
    }
    if (body.format !== undefined && body.format !== "csv") throw new Error("invalid_report_format");

    const summary = (data?.summary ?? {}) as Record<string, unknown>;
    const summaryRows = Object.entries(summary).map(([metric,value])=>({section:"summary",metric,value}));
    const localityRows = (data?.locality_performance ?? []).map((row: Record<string,unknown>)=>({
      section:"locality",metric:row.locality,value:row.paid_bookings,
      city:row.city,gross_rental_value_paise:row.gross_rental_value_paise
    }));
    const dailyRows = (data?.daily_performance ?? []).map((row: Record<string,unknown>)=>({
      section:"daily",metric:row.date,value:row.paid_bookings,
      city:"",gross_rental_value_paise:row.gross_rental_value_paise
    }));
    const rows = [...summaryRows,...localityRows,...dailyRows];
    const csv = buildCsv(rows,["section","metric","value","city","gross_rental_value_paise"]);
    return new Response(csv,{status:200,headers:{
      "Content-Type":"text/csv; charset=utf-8",
      "Content-Disposition":'attachment; filename="shelfshare-financial-'+body.from+'-'+body.to+'.csv"',
      "Cache-Control":"no-store","X-Content-Type-Options":"nosniff",
      ...(allowedOrigin?{"Access-Control-Allow-Origin":allowedOrigin,"Vary":"Origin"}:{})
    }});
  } catch(error) {
    const message=error instanceof Error?error.message:"report_failed";
    const status=/authentication/iu.test(message)?401:/permission|aal2/iu.test(message)?403:400;
    return json({error:message.slice(0,180)},status,allowedOrigin);
  }
});

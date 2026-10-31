const configuredOrigin = Deno.env.get("APP_ORIGIN") ?? "http://localhost:3000";

// Never reflect an arbitrary Origin header. Production must set APP_ORIGIN to
// the exact ShelfShare application origin; local development defaults to Vite.
export const corsHeaders = (_requestOrigin?: string | null) => ({
  "Access-Control-Allow-Origin": configuredOrigin,
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, idempotency-key, x-provider-signature, x-provider-timestamp",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(), "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

export function handleOptions(request: Request): Response | null {
  if (request.method !== "OPTIONS") return null;
  return new Response("ok", { headers: corsHeaders(request.headers.get("origin")) });
}

export function requirePost(request: Request): Response | null {
  if (request.method === "OPTIONS") return handleOptions(request);
  if (request.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);
  return null;
}

export async function readJson<T>(request: Request): Promise<T> {
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().includes("application/json")) throw new Error("content_type_must_be_application_json");
  const text = await request.text();
  if (text.length > 32_000) throw new Error("request_too_large");
  return JSON.parse(text) as T;
}

export function errorResponse(error: unknown, status = 400): Response {
  const message = error instanceof Error ? error.message : "unexpected_error";
  // Never serialize provider payloads, request bodies, or stack traces to clients.
  return jsonResponse({ error: message }, status);
}

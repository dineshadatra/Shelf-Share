import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2.49.1";

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`missing_environment_variable:${name}`);
  return value;
}

export function createAdminClient(): SupabaseClient {
  return createClient(requiredEnv("SUPABASE_URL"), requiredEnv("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

export function createUserClient(authorization: string): SupabaseClient {
  return createClient(requiredEnv("SUPABASE_URL"), requiredEnv("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

export async function requireUser(request: Request): Promise<{ user: User; client: SupabaseClient }> {
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) throw new Error("authentication_required");
  const client = createUserClient(authorization);
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) throw new Error("invalid_or_expired_session");
  return { user: data.user, client };
}

export function requireServiceRoleEnvironment(): void {
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
}

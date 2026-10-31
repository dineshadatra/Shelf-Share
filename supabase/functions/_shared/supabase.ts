import { createClient, type SupabaseClient, type User } from "https://esm.sh/@supabase/supabase-js@2";
const url = Deno.env.get("SUPABASE_URL");
const anon = Deno.env.get("SUPABASE_ANON_KEY");
const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!url || !anon || !service) throw new Error("Supabase environment is not configured");
export function createAdminClient():SupabaseClient {
 return createClient(url!,service!,{auth:{persistSession:false,autoRefreshToken:false}});
}
export async function requireUser(request:Request):Promise<{user:User;client:SupabaseClient}> {
 const auth=request.headers.get("Authorization");
 if(!auth?.startsWith("Bearer "))throw new Error("Authentication required");
 const client=createClient(url!,anon!,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data,error}=await client.auth.getUser();
 if(error||!data.user)throw new Error("Invalid or expired user session");
 return {user:data.user,client};
}

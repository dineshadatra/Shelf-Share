import { createClient } from "@supabase/supabase-js";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey);
export const supabase = isSupabaseConfigured
  ? createClient(supabaseUrl!, supabaseAnonKey!, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: false,
        flowType: "pkce"
      },
      global: { headers: { "X-Client-Info": "shelfshare-web" } }
    })
  : null;

export function normaliseIndianPhone(input: string): string {
  const digits = input.replace(/\\D/g, "");
  const national = digits.startsWith("91") && digits.length === 12 ? digits.slice(2) : digits;
  if (!/^[6-9]\\d{9}$/.test(national)) {
    throw new Error("Enter a valid 10-digit Indian mobile number.");
  }
  return `+91${national}`;
}

export function userFacingAuthError(error: unknown): string {
  if (error instanceof Error) {
    const message = error.message.toLowerCase();
    if (message.includes("rate limit") || message.includes("too many")) return "Too many attempts. Please wait before trying again.";
    if (message.includes("expired") || message.includes("token")) return "That code is invalid or expired. Request a fresh OTP.";
    if (message.includes("captcha")) return "Complete the security check and try again.";
    return error.message;
  }
  return "Something went wrong. Please try again.";
}

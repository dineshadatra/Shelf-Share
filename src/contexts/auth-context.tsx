import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import type { Session, User } from "@supabase/supabase-js";
import { isSupabaseConfigured, supabase } from "@/lib/supabase";

type VerificationSummary = {
  status: string;
  age_eligible: boolean | null;
  phone_verified_at: string | null;
  identity_verified_at: string | null;
  address_verified_at: string | null;
};

type VerificationCaseSummary = {
  case_id: string;
  case_status: string;
  submitted_at: string;
  reviewed_at: string | null;
  decision_reason: string | null;
  requested_information: string | null;
};

type AuthState = {
  configured: boolean;
  loading: boolean;
  session: Session | null;
  user: User | null;
  verification: VerificationSummary | null;
  verificationCase: VerificationCaseSummary | null;
  refreshVerification: () => Promise<void>;
  signOut: () => Promise<void>;
};

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);
  const [verification, setVerification] = useState<VerificationSummary | null>(null);
  const [verificationCase, setVerificationCase] = useState<VerificationCaseSummary | null>(null);

  const refreshVerification = useCallback(async () => {
    if (!supabase) return;
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      setVerification(null);
      setVerificationCase(null);
      return;
    }
    const { data, error } = await supabase
      .from("user_verifications")
      .select("status,age_eligible,phone_verified_at,identity_verified_at,address_verified_at")
      .eq("user_id", user.id)
      .maybeSingle();
    if (error) {
      setVerification(null);
      setVerificationCase(null);
      return;
    }
    setVerification(data as VerificationSummary | null);
    const { data: caseRows } = await supabase.rpc("get_my_verification_case");
    setVerificationCase((caseRows?.[0] as VerificationCaseSummary | undefined) ?? null);
  }, []);

  useEffect(() => {
    if (!supabase) {
      setLoading(false);
      return;
    }
    let mounted = true;
    supabase.auth.getSession().then(async ({ data }) => {
      if (!mounted) return;
      setSession(data.session);
      if (data.session) await refreshVerification();
      if (mounted) setLoading(false);
    });
    const { data: listener } = supabase.auth.onAuthStateChange((event, nextSession) => {
      if (!mounted) return;
      setSession(nextSession);
      if (event === "SIGNED_OUT") { setVerification(null); setVerificationCase(null); }
      if (event === "SIGNED_IN" || event === "TOKEN_REFRESHED" || event === "USER_UPDATED") {
        queueMicrotask(() => { void refreshVerification(); });
      }
    });
    return () => {
      mounted = false;
      listener.subscription.unsubscribe();
    };
  }, [refreshVerification]);

  const value = useMemo<AuthState>(() => ({
    configured: isSupabaseConfigured,
    loading,
    session,
    user: session?.user ?? null,
    verification,
    verificationCase,
    refreshVerification,
    signOut: async () => {
      if (!supabase) throw new Error("Supabase is not configured.");
      const { error } = await supabase.auth.signOut({ scope: "local" });
      if (error) throw error;
      setSession(null);
      setVerification(null);
      setVerificationCase(null);
    }
  }), [loading, session, verification, verificationCase, refreshVerification]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const value = useContext(AuthContext);
  if (!value) throw new Error("useAuth must be used inside AuthProvider");
  return value;
}

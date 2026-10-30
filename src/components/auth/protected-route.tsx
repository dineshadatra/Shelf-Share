import { useEffect, useState, type ReactNode } from "react";
import { Navigate, useLocation } from "react-router-dom";
import { useAuth } from "@/contexts/auth-context";
import { supabase } from "@/lib/supabase";
import { Alert } from "@/components/ui/alert";

export function ProtectedRoute({ children, staffOnly = false, moderationOnly = false }: { children: ReactNode; staffOnly?: boolean; moderationOnly?: boolean }) {
  const { configured, loading, user } = useAuth();
  const location = useLocation();
  const [profileExists, setProfileExists] = useState<boolean | null>(null);
  const [accountStatus, setAccountStatus] = useState<string | null>(null);
  const [checkingProfile, setCheckingProfile] = useState(true);
  const [staffAllowed, setStaffAllowed] = useState<boolean | null>(staffOnly || moderationOnly ? null : true);
  const [checkingStaff, setCheckingStaff] = useState(staffOnly || moderationOnly);

  useEffect(() => {
    let active = true;
    if (!user || !supabase) {
      setProfileExists(null);
      setAccountStatus(null);
      setCheckingProfile(false);
      return;
    }
    setCheckingProfile(true);
    supabase.from("profiles").select("id,account_status").eq("id", user.id).maybeSingle()
      .then(({ data, error }) => {
        if (!active) return;
        setProfileExists(!error && Boolean(data?.id));
        setAccountStatus(!error && data?.account_status ? data.account_status : null);
        setCheckingProfile(false);
      }, () => {
        if (!active) return;
        setProfileExists(false);
        setAccountStatus(null);
        setCheckingProfile(false);
      });
    return () => { active = false; };
  }, [user?.id]);

  useEffect(() => {
    let active = true;
    if ((!staffOnly && !moderationOnly) || !user || !supabase) {
      setCheckingStaff(false);
      if ((staffOnly || moderationOnly) && !user) setStaffAllowed(false);
      return;
    }
    setCheckingStaff(true);
    const endpoint = moderationOnly ? "catalogue-api" : "verification-admin";
    const action = moderationOnly ? "moderator_me" : "me";
    Promise.resolve(supabase.functions.invoke(endpoint, { body: { action } }))
      .then(({ data, error }) => {
        if (!active) return;
        setStaffAllowed(!error && data?.authorized === true);
      })
      .catch(() => { if (active) setStaffAllowed(false); })
      .finally(() => { if (active) setCheckingStaff(false); });
    return () => { active = false; };
  }, [staffOnly, moderationOnly, user?.id]);

  if (!configured) return <main className="page-container" style={{ paddingBlock: 60 }}>
    <Alert tone="warning" title="Authentication is not configured">
      Add VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY to your local .env file, then restart the development server.
    </Alert>
  </main>;
  if (loading || checkingProfile || (Boolean(user) && profileExists === null) || checkingStaff) return <div className="page-container" style={{ paddingBlock: 80 }}>Checking your secure account…</div>;
  if (!user) return <Navigate to={staffOnly ? "/admin/login" : "/login"} replace state={{ from: location.pathname }} />;
  if (!profileExists) return <Navigate to="/register?resume=1" replace />;
  if (accountStatus !== "active") return <main className="page-container" style={{ paddingBlock: 60 }}><Alert tone="warning" title="Account access is restricted">Your ShelfShare account is not active. Contact ShelfShare support for next steps.</Alert></main>;
  if ((staffOnly || moderationOnly) && !staffAllowed) return <Navigate to="/" replace />;
  return <>{children}</>;
}

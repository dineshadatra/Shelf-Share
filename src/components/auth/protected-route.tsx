import { useEffect, useState, type ReactNode } from "react";
import { Navigate, useLocation } from "react-router-dom";
import { useAuth } from "@/contexts/auth-context";
import { supabase } from "@/lib/supabase";
import { Alert } from "@/components/ui/alert";

export function ProtectedRoute({ children, staffOnly = false }: { children: ReactNode; staffOnly?: boolean }) {
  const { configured, loading, user } = useAuth();
  const location = useLocation();
  const [profileExists, setProfileExists] = useState<boolean | null>(null);
  const [checkingProfile, setCheckingProfile] = useState(true);
  const [staffAllowed, setStaffAllowed] = useState<boolean | null>(staffOnly ? null : true);
  const [checkingStaff, setCheckingStaff] = useState(staffOnly);

  useEffect(() => {
    let active = true;
    if (!user || !supabase) {
      setProfileExists(null);
      setCheckingProfile(false);
      return;
    }
    setCheckingProfile(true);
    supabase.from("profiles").select("id").eq("id", user.id).maybeSingle()
      .then(({ data, error }) => {
        if (!active) return;
        setProfileExists(!error && Boolean(data?.id));
      })
      .finally(() => { if (active) setCheckingProfile(false); });
    return () => { active = false; };
  }, [user?.id]);

  useEffect(() => {
    let active = true;
    if (!staffOnly || !user || !supabase) {
      setCheckingStaff(false);
      if (staffOnly && !user) setStaffAllowed(false);
      return;
    }
    setCheckingStaff(true);
    supabase.functions.invoke("verification-admin", { body: { action: "me" } })
      .then(({ data, error }) => {
        if (!active) return;
        setStaffAllowed(!error && data?.authorized === true);
      })
      .catch(() => { if (active) setStaffAllowed(false); })
      .finally(() => { if (active) setCheckingStaff(false); });
    return () => { active = false; };
  }, [staffOnly, user?.id]);

  if (!configured) {
    return <main className="page-container" style={{ paddingBlock: 60 }}>
      <Alert tone="warning" title="Authentication is not configured">
        Add VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY to your local .env file, then restart the development server.
      </Alert>
    </main>;
  }
  if (loading || checkingProfile || checkingStaff) return <div className="page-container" style={{ paddingBlock: 80 }}>Checking your secure account…</div>;
  if (!user) return <Navigate to={staffOnly ? "/admin/login" : "/login"} replace state={{ from: location.pathname }} />;
  if (!profileExists) return <Navigate to="/register?resume=1" replace />;
  if (staffOnly && !staffAllowed) return <Navigate to="/" replace />;
  return <>{children}</>;
}

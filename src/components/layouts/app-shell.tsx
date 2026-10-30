import type { ReactNode } from "react";
import { DashboardSidebar } from "@/components/navigation/dashboard-sidebar";
import { MobileBottomNav } from "@/components/navigation/mobile-bottom-nav";
import { Bell, ChevronDown, LogOut } from "lucide-react";
import { Link, useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/contexts/auth-context";
import { toast } from "sonner";

export function AppShell({ children, mode = "reader", title = "Workspace" }: {
  children: ReactNode; mode?: "reader" | "owner" | "admin"; title?: string
}) {
  const { signOut } = useAuth();
  const navigate = useNavigate();
  const logout = async () => {
    try { await signOut(); navigate("/login", { replace: true }); }
    catch { toast.error("Unable to end the session. Please retry."); }
  };
  return <div className="workspace">
    <DashboardSidebar mode={mode}/>
    <div className="workspace-main">
      <header className="workspace-topbar">
        <div><span className="workspace-breadcrumb">ShelfShare /</span> {title}</div>
        <div className="workspace-user-actions">
          <Link to="/notifications" aria-label="Notifications"><Bell size={18}/></Link>
          <Link to="/profile" className="workspace-user"><span className="avatar initials">SS</span><span>My account</span><ChevronDown size={14}/></Link>
          <Button size="sm" variant="ghost" className="workspace-signout" onClick={() => void logout()}><LogOut size={15}/> Sign out</Button>
        </div>
      </header>
      <main className="workspace-content">{children}</main>
    </div>
    <MobileBottomNav/>
  </div>;
}

import { Link } from "react-router-dom";
import { AlertTriangle, BookOpen, ClipboardCheck, Flag, Users, WalletCards } from "lucide-react";
import { AdminLayout } from "@/layouts/admin-layout";
import { PageHeading } from "./page-helpers";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";

export default function AdminDashboardPage() {
  return <AdminLayout>
    <PageHeading eyebrow="SHELFShare OPERATIONS" title="Marketplace overview." description="A single place for trust, listings and operational health." action={<div className="admin-header-actions"><Button asChild variant="outline"><Link to="/admin/listings"><BookOpen size={16}/> Listing queue</Link></Button><Button asChild variant="outline"><Link to="/admin/bundles"><BookOpen size={16}/> Bundle queue</Link></Button><Button asChild><Link to="/admin/verifications"><ClipboardCheck size={16}/> Verification queue</Link></Button></div>}/>
    <Alert tone="info">This area is protected by a server-verified staff role. All privileged data and document actions are re-authorised by the backend.</Alert>
    <div className="stats-grid admin-stats">
      <Card><CardContent><span className="stat-icon"><Users size={18}/></span><span className="stat-label">Members</span><strong className="stat-value">—</strong><small>Metrics API not connected</small></CardContent></Card>
      <Card><CardContent><span className="stat-icon"><BookOpen size={18}/></span><span className="stat-label">Listings pending</span><strong className="stat-value">—</strong><small>Metrics API not connected</small></CardContent></Card>
      <Card><CardContent><span className="stat-icon"><ClipboardCheck size={18}/></span><span className="stat-label">Verifications</span><strong className="stat-value">Open queue</strong><small>Manual review workflow</small></CardContent></Card>
      <Card><CardContent><span className="stat-icon"><WalletCards size={18}/></span><span className="stat-label">Payouts</span><strong className="stat-value">—</strong><small>Finance integration disabled</small></CardContent></Card>
    </div>
    <div className="admin-operations-grid">
      <Card><CardContent><h3>Marketplace listings</h3><EmptyState icon={<BookOpen size={24}/>} title="Moderate physical copy listings" description="Check title metadata, ownership declaration, condition disclosures and actual copy photos."/><Button asChild variant="outline"><Link to="/admin/listings">Go to listing queue</Link></Button></CardContent></Card>
      <Card><CardContent><h3>Trust & safety queue</h3><EmptyState icon={<Flag size={24}/>} title="Review member verification" description="Open the queue to inspect private evidence through audited, short-lived previews."/><Button asChild variant="outline"><Link to="/admin/verifications">Go to verification queue</Link></Button></CardContent></Card>
      <Card><CardContent><h3>Risk signals</h3><EmptyState icon={<AlertTriangle size={24}/>} title="Risk data not connected" description="Risk alerts and moderation signals are not available in this release."/></CardContent></Card>
    </div>
  </AdminLayout>;
}

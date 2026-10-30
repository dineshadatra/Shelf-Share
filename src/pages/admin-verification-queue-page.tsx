import { useCallback, useEffect, useState } from "react";
import { ClipboardCheck, Eye, RefreshCw, ShieldAlert } from "lucide-react";
import { AdminLayout } from "@/layouts/admin-layout";
import { PageHeading } from "./page-helpers";
import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { supabase, userFacingAuthError } from "@/lib/supabase";
import { useAuth } from "@/contexts/auth-context";

type CaseItem = {
  id: string; user_id: string; status: string; assigned_reviewer_id: string | null;
  submitted_at: string; reviewed_at: string | null; decision_reason: string | null;
  requested_information: string | null; internal_notes: string | null; display_name: string;
  date_of_birth: string | null; account_status: string; masked_phone: string;
  documents: Array<{ id: string; document_type: string; document_last4: string | null; status: string }>;
  file_kinds: Array<{ id: string; file_kind: string }>;
  audit_history: Array<{ id: number; actor_user_id: string | null; action: string; reason_code: string | null; created_at: string; from_status: string | null; to_status: string | null }>;
  document_access_history: Array<{ id: number; actor_user_id: string; accessed_at: string; purpose: string; document_id: string }>;
};

export default function AdminVerificationQueuePage() {
  const { user } = useAuth();
  const [cases, setCases] = useState<CaseItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [busyId, setBusyId] = useState("");

  const load = useCallback(async () => {
    if (!supabase) return;
    setLoading(true); setError("");
    const { data, error: invokeError } = await supabase.functions.invoke("verification-admin", { body: { action: "list" } });
    if (invokeError) setError(userFacingAuthError(invokeError));
    else setCases((data?.cases ?? []) as CaseItem[]);
    setLoading(false);
  }, []);

  useEffect(() => { void load(); }, [load]);

  const preview = async (item: CaseItem, fileId: string) => {
    if (!supabase) return;
    const purpose = window.prompt("Why are you opening this private file? This reason is audited.", "Manual identity review");
    if (!purpose || purpose.trim().length < 5) return;
    const { data, error: invokeError } = await supabase.functions.invoke("verification-admin", {
      body: { action: "preview", case_id: item.id, file_id: fileId, purpose }
    });
    if (invokeError || !data?.signed_url) { setError(userFacingAuthError(invokeError ?? new Error("Preview unavailable"))); return; }
    window.open(data.signed_url, "_blank", "noopener,noreferrer");
    setError("");
  };

  const assignReviewer = async (item: CaseItem, assigneeId: string) => {
    if (!supabase) return;
    setBusyId(item.id); setError("");
    const { error: invokeError } = await supabase.functions.invoke("verification-admin", {
      body: { action: "assign", case_id: item.id, assignee_id: assigneeId }
    });
    if (invokeError) setError(userFacingAuthError(invokeError));
    await load(); setBusyId("");
  };

  const assignToMe = (item: CaseItem) => {
    if (user) void assignReviewer(item, user.id);
  };

  const assignToOther = (item: CaseItem) => {
    const assigneeId = window.prompt("Enter the UUID of an active verification reviewer.");
    if (assigneeId && assigneeId.trim()) void assignReviewer(item, assigneeId.trim());
  };

  const decide = async (item: CaseItem, decision: "approve" | "reject" | "request_info" | "suspend") => {
    if (!supabase) return;
    const prompts = { approve: "Reviewer note (optional)", reject: "Reason for rejection (shown to the member)", request_info: "What additional information is required?", suspend: "Reason for account suspension" };
    const reason = window.prompt(prompts[decision], "");
    if (reason === null || (decision !== "approve" && reason.trim().length < 5)) return;
    const notes = window.prompt("Internal reviewer notes (optional)", "") ?? "";
    const hasAddressEvidence = item.file_kinds.some((file) => file.file_kind === "address_evidence");
    const addressVerified = decision === "approve" && hasAddressEvidence
      ? window.confirm("Confirm that the submitted address evidence has been reviewed and accepted.")
      : false;
    setBusyId(item.id); setError("");
    const { error: invokeError } = await supabase.functions.invoke("verification-admin", {
      body: { action: "decision", case_id: item.id, decision, reason: reason || "Approved after manual review", internal_notes: notes, address_verified: addressVerified }
    });
    if (invokeError) setError(userFacingAuthError(invokeError));
    await load(); setBusyId("");
  };

  return <AdminLayout>
    <PageHeading eyebrow="TRUST OPERATIONS" title="Identity review queue" description="Review identity submissions, assign reviewers and record auditable decisions." action={<Button variant="outline" onClick={() => void load()}><RefreshCw size={15}/> Refresh</Button>}/>
    {error && <Alert tone="warning">{error}</Alert>}
    <Alert tone="info"><ShieldAlert size={16}/> Private document access is audited. Do not download, copy or share evidence outside the approved review purpose.</Alert>
    {loading ? <div className="surface admin-case-empty">Loading secure verification queue…</div> :
      cases.length === 0 ? <div className="surface admin-case-empty"><ClipboardCheck size={26}/><strong>No pending verification cases</strong><p>The queue is currently clear.</p></div> :
      <div className="admin-case-list">{cases.map((item) => <article className="surface admin-case" key={item.id}>
        <div className="admin-case-head"><div><span className="eyebrow">CASE {item.id.slice(0,8).toUpperCase()}</span><h2>{item.display_name}</h2><p>{item.masked_phone} · DOB {item.date_of_birth ?? "Not supplied"} · Account {item.account_status}</p></div><Badge tone={item.status === "rejected" ? "rose" : "amber"}>{item.status.replaceAll("_"," ")}</Badge></div>
        <div className="admin-case-meta"><span>Submitted: {new Date(item.submitted_at).toLocaleString("en-IN")}</span><span>Reviewed: {item.reviewed_at ? new Date(item.reviewed_at).toLocaleString("en-IN") : "Pending"}</span><span>Assigned reviewer: {item.assigned_reviewer_id ?? "Unassigned"}</span></div>
        <div className="admin-document-list">{item.documents.map((doc) => {
          const file = item.file_kinds.find((entry) => entry.file_kind === "identity_document");
          return <div key={doc.id}><strong>{doc.document_type.replaceAll("_"," ")} {doc.document_last4 ? `··${doc.document_last4}` : ""}</strong><Button size="sm" variant="outline" disabled={!file || busyId === item.id} onClick={() => file && void preview(item,file.id)}><Eye size={14}/> Secure preview</Button></div>;
        })}{item.file_kinds.filter((file) => file.file_kind !== "identity_document").map((file) => <div key={file.id}><strong>{file.file_kind.replaceAll("_"," ")}</strong><Button size="sm" variant="outline" disabled={busyId === item.id} onClick={() => void preview(item,file.id)}><Eye size={14}/> Secure preview</Button></div>)}</div>
        {item.requested_information && <Alert tone="warning">Information requested: {item.requested_information}</Alert>}
        {item.decision_reason && <p className="admin-case-reason">Previous decision: {item.decision_reason}</p>}
        {item.internal_notes && <p className="admin-case-reason">Internal notes: {item.internal_notes}</p>}
        {(item.audit_history.length > 0 || item.document_access_history.length > 0) && <details className="admin-audit-history">
          <summary>Audit history ({item.audit_history.length + item.document_access_history.length})</summary>
          <ol>{item.audit_history.map((entry) => <li key={`decision-${entry.id}`}><strong>{entry.action.replaceAll("_"," ")}</strong><span>{new Date(entry.created_at).toLocaleString("en-IN")} · {entry.actor_user_id ?? "System"}</span>{entry.reason_code && <small>{entry.reason_code}</small>}</li>)}
            {item.document_access_history.map((entry) => <li key={`access-${entry.id}`}><strong>Private file preview</strong><span>{new Date(entry.accessed_at).toLocaleString("en-IN")} · {entry.actor_user_id}</span><small>{entry.purpose}</small></li>)}</ol>
        </details>}
        <div className="admin-case-actions">
          <Button size="sm" variant="outline" disabled={busyId === item.id} onClick={() => assignToMe(item)}>Assign to me</Button>
          <Button size="sm" variant="ghost" disabled={busyId === item.id} onClick={() => assignToOther(item)}>Assign reviewer…</Button>
          <Button size="sm" disabled={busyId === item.id} onClick={() => void decide(item,"approve")}>Approve</Button>
          <Button size="sm" variant="outline" disabled={busyId === item.id} onClick={() => void decide(item,"request_info")}>Request information</Button>
          <Button size="sm" variant="danger" disabled={busyId === item.id} onClick={() => void decide(item,"reject")}>Reject</Button>
          <Button size="sm" variant="danger" disabled={busyId === item.id} onClick={() => void decide(item,"suspend")}>Suspend account</Button>
        </div>
      </article>)}</div>}
  </AdminLayout>;
}

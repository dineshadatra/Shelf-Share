import { useEffect, useState } from "react";
import { FileCheck2, LockKeyhole, ShieldCheck } from "lucide-react";
import { MemberLayout } from "@/layouts/member-layout";
import { PageHeading } from "./page-helpers";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { LiveCameraCapture } from "@/components/auth/live-camera-capture";
import { useAuth } from "@/contexts/auth-context";
import { supabase, userFacingAuthError } from "@/lib/supabase";

const MAX_FILE_SIZE = 10 * 1024 * 1024;
const acceptedTypes = ["image/jpeg", "image/png", "application/pdf"];

export default function VerificationPage() {
  const { user, verification, verificationCase, refreshVerification } = useAuth();
  const [documentType, setDocumentType] = useState<"passport" | "pan" | "driving_licence">("passport");
  const [documentFile, setDocumentFile] = useState<File | null>(null);
  const [addressFile, setAddressFile] = useState<File | null>(null);
  const [selfieFile, setSelfieFile] = useState<File | null>(null);
  const [documentLast4, setDocumentLast4] = useState("");
  const [showSelfie, setShowSelfie] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  useEffect(() => { void refreshVerification(); }, [refreshVerification]);

  const validateFile = (file: File | null, label: string) => {
    if (!file) throw new Error(`Select your ${label}.`);
    if (!acceptedTypes.includes(file.type)) throw new Error(`${label} must be JPG, PNG or PDF.`);
    if (file.size > MAX_FILE_SIZE) throw new Error(`${label} must be 10 MB or smaller.`);
  };

  const submit = async () => {
    setError(""); setNotice("");
    if (!supabase || !user) return;
    try {
      validateFile(documentFile, "identity document");
      if (addressFile) validateFile(addressFile, "address evidence");
      if (selfieFile && (selfieFile.type !== "image/jpeg" || selfieFile.size > 5 * 1024 * 1024)) throw new Error("Verification selfie must be a JPEG camera capture under 5 MB.");
      const caseId = crypto.randomUUID();
      const extension = documentFile!.type === "application/pdf" ? "pdf" : documentFile!.type === "image/png" ? "png" : "jpg";
      const documentKey = `${user.id}/${caseId}/identity.${extension}`;
      const { error: documentUploadError } = await supabase.storage.from("identity-private").upload(documentKey, documentFile!, { contentType: documentFile!.type, upsert: false });
      if (documentUploadError) throw documentUploadError;

      let addressKey: string | null = null;
      if (addressFile) {
        const addressExtension = addressFile.type === "application/pdf" ? "pdf" : addressFile.type === "image/png" ? "png" : "jpg";
        addressKey = `${user.id}/${caseId}/address.${addressExtension}`;
        const { error: addressUploadError } = await supabase.storage.from("identity-private").upload(addressKey, addressFile, { contentType: addressFile.type, upsert: false });
        if (addressUploadError) throw addressUploadError;
      }

      let selfieKey: string | null = null;
      if (selfieFile) {
        selfieKey = `${user.id}/${caseId}/selfie.jpg`;
        const { error: selfieUploadError } = await supabase.storage.from("verification-selfie-private").upload(selfieKey, selfieFile, { contentType: "image/jpeg", upsert: false });
        if (selfieUploadError) throw selfieUploadError;
      }

      const { error: submitError } = await supabase.rpc("submit_identity_verification", {
        p_case_id: caseId, p_document_type: documentType, p_document_object_key: documentKey,
        p_document_last4: documentLast4.trim() || null, p_address_object_key: addressKey, p_selfie_object_key: selfieKey
      });
      if (submitError) throw submitError;
      await refreshVerification();
      setNotice("Your identity submission was received. An authorised reviewer must approve it before listing or renting.");
      setDocumentFile(null); setAddressFile(null); setSelfieFile(null); setDocumentLast4("");
    } catch (reason) { setError(userFacingAuthError(reason)); }
    finally { setBusy(false); }
  };

  const status = verification?.status ?? "not_submitted";
  const statusLabel = status.replaceAll("_", " ");
  const canSubmit = ["not_submitted", "rejected", "needs_resubmission", "expired"].includes(status);

  return <MemberLayout title="Verification">
    <PageHeading eyebrow="ACCOUNT TRUST" title="Verify your identity" description="Identity documents are private and reviewed manually by authorised ShelfShare staff."/>
    <div className="verification-grid">
      <section className="surface verification-panel">
        <div className="verification-status"><span className="verification-icon"><ShieldCheck/></span><div><strong>{statusLabel.charAt(0).toUpperCase() + statusLabel.slice(1)}</strong><p>{status === "verified" ? "Your identity has been approved." : "You can browse while your verification is pending. Listing and renting remain blocked until verified."}</p></div><Badge tone={status === "verified" ? "green" : status === "rejected" ? "rose" : "amber"}>{statusLabel}</Badge></div>
        {error && <Alert tone="warning">{error}</Alert>}{notice && <Alert tone="success">{notice}</Alert>}
        {verificationCase?.requested_information && <Alert tone="warning" title="Additional information requested">{verificationCase.requested_information}</Alert>}
        {verificationCase?.decision_reason && <Alert tone="info" title="Reviewer decision">{verificationCase.decision_reason}</Alert>}
        {verificationCase && <p className="verification-case-meta">Submitted {new Date(verificationCase.submitted_at).toLocaleString("en-IN")}{verificationCase.reviewed_at ? ` · Reviewed ${new Date(verificationCase.reviewed_at).toLocaleString("en-IN")}` : ""}</p>}
        {status === "verified" ? <Alert tone="success">Your account is identity verified. Address verification remains subject to any applicable operational/legal requirement.</Alert> : canSubmit ? <>
          <div className="verification-step"><span>1</span><div><strong>Choose an identity document</strong><p>Passport is preferred. PAN or Driving Licence are accepted fallback types for manual review.</p></div></div>
          <label className="ss-label" htmlFor="document-type">Document type</label>
          <select id="document-type" className="ss-input" value={documentType} onChange={(event) => setDocumentType(event.target.value as typeof documentType)}><option value="passport">Passport (preferred)</option><option value="pan">PAN</option><option value="driving_licence">Driving Licence</option></select>
          <label className="ss-label" htmlFor="identity-document">Identity document (JPG, PNG or PDF, max 10 MB)</label>
          <input id="identity-document" className="ss-input" type="file" accept=".jpg,.jpeg,.png,.pdf,image/jpeg,image/png,application/pdf" onChange={(event) => setDocumentFile(event.target.files?.[0] ?? null)}/>
          <Input label="Document reference (optional, last 4 characters only)" name="document-last4" maxLength={8} value={documentLast4} onChange={(event) => setDocumentLast4(event.target.value)} hint="Do not enter the full PAN/passport/licence number."/>
          <div className="verification-step"><span>2</span><div><strong>Address evidence, only when requested</strong><p>PAN is not address proof. The accepted address documents and address-proof policy are still awaiting product/legal approval.</p></div></div>
          <label className="ss-label" htmlFor="address-document">Optional address evidence (private; do not submit unless requested)</label>
          <input id="address-document" className="ss-input" type="file" accept=".jpg,.jpeg,.png,.pdf,image/jpeg,image/png,application/pdf" onChange={(event) => setAddressFile(event.target.files?.[0] ?? null)}/>
          <label className="check-row"><input type="checkbox" checked={showSelfie} onChange={(event) => { setShowSelfie(event.target.checked); setSelfieFile(null); }}/><span>Add a private verification selfie (only if requested by the reviewer).</span></label>
          {showSelfie && <LiveCameraCapture onCapture={setSelfieFile}/>}
          <Button block size="lg" disabled={busy || !documentFile} onClick={() => { setBusy(true); void submit(); }}><FileCheck2 size={17}/>{busy ? "Submitting securely…" : "Submit for manual review"}</Button>
        </> : <Alert tone="info">Your submission is in the manual review workflow. Check back for a reviewer decision or request for additional information.</Alert>}
      </section>
      <aside className="verification-aside"><LockKeyhole size={22}/><h3>Your identity stays private.</h3><p>Document and selfie objects are kept in private buckets. Browser users have upload-only access to their own folders and no direct read access. Staff previews require an authorised reviewer session and a short-lived signed URL.</p><Alert tone="warning">Manual approval does not happen automatically. No user can approve their own case. Address-proof requirements remain unresolved.</Alert></aside>
    </div>
  </MemberLayout>;
}

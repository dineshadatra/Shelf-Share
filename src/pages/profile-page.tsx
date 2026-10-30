import { useEffect, useState } from "react";
import { UserRound, ShieldCheck, MapPin, Smartphone, CheckCircle2 } from "lucide-react";
import { Link } from "react-router-dom";
import { MemberLayout } from "@/layouts/member-layout";
import { PageHeading } from "./page-helpers";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/alert";
import { Input } from "@/components/ui/input";
import { useAuth } from "@/contexts/auth-context";
import { supabase, normaliseIndianPhone, userFacingAuthError } from "@/lib/supabase";

export default function ProfilePage() {
  const { user, verification, refreshVerification } = useAuth();
  const [profile, setProfile] = useState<{ display_name: string; date_of_birth: string | null; account_status: string } | null>(null);
  const [phone, setPhone] = useState("");
  const [newPhone, setNewPhone] = useState("");
  const [otp, setOtp] = useState("");
  const [changeStep, setChangeStep] = useState<"phone" | "otp">("phone");
  const [normalisedPhone, setNormalisedPhone] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  useEffect(() => {
    if (!supabase || !user) return;
    supabase.from("profiles").select("display_name,date_of_birth,account_status").eq("id", user.id).maybeSingle()
      .then(({ data }) => { if (data) setProfile(data); });
    setPhone(user.phone ?? "");
  }, [user?.id, user?.phone]);

  const sendPhoneChangeOtp = async () => {
    setError(""); setNotice("");
    if (!supabase) return;
    try {
      const formatted = normaliseIndianPhone(newPhone);
      setBusy(true);
      const { error: updateError } = await supabase.auth.updateUser({ phone: formatted });
      if (updateError) throw updateError;
      setNormalisedPhone(formatted);
      setChangeStep("otp");
      setNotice(`A confirmation code was sent to ${formatted}.`);
    } catch (reason) { setError(userFacingAuthError(reason)); }
    finally { setBusy(false); }
  };

  const confirmPhoneChange = async () => {
    setError(""); setNotice("");
    if (!supabase) return;
    if (!/^\\d{6}$/.test(otp)) { setError("Enter the six-digit confirmation code."); return; }
    setBusy(true);
    try {
      const { error: verifyError } = await supabase.auth.verifyOtp({
        phone: normalisedPhone, token: otp, type: "phone_change"
      });
      if (verifyError) throw verifyError;
      const { data: { user: updatedUser } } = await supabase.auth.getUser();
      setPhone(updatedUser?.phone ?? normalisedPhone);
      setNewPhone(""); setOtp(""); setChangeStep("phone");
      setNotice("Your mobile number was changed successfully.");
      await refreshVerification();
    } catch (reason) { setError(userFacingAuthError(reason)); }
    finally { setBusy(false); }
  };

  const status = verification?.status ?? "not submitted";
  return <MemberLayout title="My profile">
    <PageHeading eyebrow="YOUR SHELFSHARE ID" title="A little about you." description="Manage your account details and verification status."/>
    {error && <Alert tone="warning">{error}</Alert>}{notice && <Alert tone="success">{notice}</Alert>}
    <div className="profile-layout">
      <Card><CardContent>
        <div className="profile-person"><span className="avatar profile-avatar"><UserRound size={26}/></span><div><h2 className="serif">{profile?.display_name ?? "Your profile"}</h2><p>Member account</p></div><Badge tone={status === "verified" ? "green" : "amber"}>{status.replaceAll("_"," ")}</Badge></div>
        <div className="profile-details">
          <div><span>Mobile number</span><strong>{phone || "Not connected"} <CheckCircle2 size={14}/></strong></div>
          <div><span>Date of birth</span><strong>{profile?.date_of_birth ?? "—"}</strong></div>
          <div><span>Account status</span><strong>{profile?.account_status ?? "—"}</strong></div>
          <div><span>Phone verified</span><strong>{verification?.phone_verified_at ? "Verified" : "Pending"}</strong></div>
        </div>
        <section className="phone-change-section">
          <h3><Smartphone size={17}/> Change mobile number</h3>
          {changeStep === "phone" ? <>
            <Input label="New Indian mobile number" name="new-phone" type="tel" placeholder="+91 98765 43210" value={newPhone} onChange={(event) => setNewPhone(event.target.value)} hint="A confirmation OTP will be sent to the new number. Your current number remains active until confirmation."/>
            <Button variant="outline" disabled={busy || !newPhone.trim()} onClick={() => void sendPhoneChangeOtp()}>{busy ? "Sending…" : "Verify new number"}</Button>
          </> : <>
            <Input label={`Confirmation code sent to ${normalisedPhone}`} name="phone-change-otp" inputMode="numeric" autoComplete="one-time-code" maxLength={6} value={otp} onChange={(event) => setOtp(event.target.value.replace(/\\D/g,"").slice(0,6))}/>
            <div className="admin-case-actions"><Button disabled={busy || otp.length !== 6} onClick={() => void confirmPhoneChange()}>{busy ? "Verifying…" : "Confirm mobile change"}</Button><Button variant="ghost" onClick={() => { setChangeStep("phone"); setOtp(""); }}>Cancel</Button></div>
          </>}
        </section>
      </CardContent></Card>
      <aside className="profile-side"><div className="surface profile-verification"><ShieldCheck size={22}/><h3>Build trust, one step at a time.</h3><p>Complete manual identity review before listing or renting books.</p><Button asChild variant="secondary"><Link to="/verification">View verification</Link></Button></div><Alert tone="info">Your identity documents and verification selfies are private and are not displayed on public profiles.</Alert></aside>
    </div>
  </MemberLayout>;
}

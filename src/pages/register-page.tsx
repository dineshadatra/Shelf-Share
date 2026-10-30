import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Camera, ShieldCheck, Smartphone } from "lucide-react";
import { AuthLayout } from "@/layouts/auth-layout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Alert } from "@/components/ui/alert";
import { AuthCaptcha, captchaRequired } from "@/components/auth/auth-captcha";
import { LiveCameraCapture } from "@/components/auth/live-camera-capture";
import { useAuth } from "@/contexts/auth-context";
import { supabase, normaliseIndianPhone, userFacingAuthError } from "@/lib/supabase";

type RegistrationPolicy = { terms_version: string; privacy_version: string; terms_url: string; privacy_url: string };

export default function RegisterPage() {
  const { user } = useAuth();
  const [policy, setPolicy] = useState<RegistrationPolicy | null>(null);
  const [policyLoading, setPolicyLoading] = useState(true);
  const [phone, setPhone] = useState("");
  const [normalisedPhone, setNormalisedPhone] = useState("");
  const [name, setName] = useState("");
  const [dob, setDob] = useState("");
  const [accepted, setAccepted] = useState(false);
  const [code, setCode] = useState("");
  const [step, setStep] = useState<"details" | "otp" | "camera">("details");
  const [seconds, setSeconds] = useState(0);
  const [photo, setPhoto] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  const [captchaReset, setCaptchaReset] = useState(0);
  const navigate = useNavigate();
  const ageCutoff = new Date();
  ageCutoff.setFullYear(ageCutoff.getFullYear() - 18);
  const maxAdultDob = [ageCutoff.getFullYear(), String(ageCutoff.getMonth() + 1).padStart(2, "0"), String(ageCutoff.getDate()).padStart(2, "0")].join("-");

  useEffect(() => {
    if (!user || !supabase) return;
    setPhone(user.phone ?? "");
    setNormalisedPhone(user.phone ?? "");
    supabase.from("profiles").select("id").eq("id", user.id).maybeSingle()
      .then(({ data }) => { if (data?.id) navigate("/reader", { replace: true }); });
  }, [user?.id, user?.phone, navigate]);

  useEffect(() => {
    if (!supabase) { setPolicyLoading(false); return; }
    let active = true;
    supabase.rpc("get_active_registration_policy").then(({ data, error: policyError }) => {
      if (!active) return;
      if (!policyError && data?.[0]) setPolicy(data[0] as RegistrationPolicy);
      setPolicyLoading(false);
    });
    return () => { active = false; };
  }, []);

  useEffect(() => {
    if (seconds <= 0) return;
    const timer = window.setInterval(() => setSeconds((value) => Math.max(0, value - 1)), 1000);
    return () => window.clearInterval(timer);
  }, [seconds]);

  const requestOtp = async () => {
    setError("");
    if (!supabase) { setError("Supabase is not configured. Add the VITE_SUPABASE environment variables."); return; }
    if (captchaRequired && !captchaToken) { setError("Complete the security check before requesting an OTP."); return; }
    if (!policy) { setError("Registration is paused until approved Terms and Privacy versions are configured."); return; }
    if (!accepted) { setError("Please accept the current Terms and Privacy Notice before continuing."); return; }
    if (!name.trim() || !dob) { setError("Name and date of birth are required."); return; }
    if (user) { setStep("camera"); return; }
    try {
      const formatted = normaliseIndianPhone(phone);
      setBusy(true);
      const { error: otpError } = await supabase.auth.signInWithOtp({
        phone: formatted, options: { shouldCreateUser: true, channel: "sms", ...(captchaToken ? { captchaToken } : {}) }
      });
      if (otpError) throw otpError;
      setNormalisedPhone(formatted); setStep("otp"); setSeconds(60);
    } catch (reason) { setError(userFacingAuthError(reason)); }
    finally { setBusy(false); setCaptchaToken(null); setCaptchaReset((value) => value + 1); }
  };

  const verifyOtp = async () => {
    setError("");
    if (!supabase) return;
    if (!/^\\d{6}$/.test(code)) { setError("Enter the six-digit code sent to your mobile."); return; }
    setBusy(true);
    try {
      const { data, error: verifyError } = await supabase.auth.verifyOtp({ phone: normalisedPhone, token: code, type: "sms" });
      if (verifyError) throw verifyError;
      if (!data.user) throw new Error("The mobile number could not be verified.");
      setStep("camera");
    } catch (reason) { setError(userFacingAuthError(reason)); }
    finally { setBusy(false); }
  };

  const completeRegistration = async () => {
    setError("");
    if (!supabase || !policy || !photo) { setError("Complete the live camera capture before continuing."); return; }
    setBusy(true);
    try {
      const { data: { user }, error: userError } = await supabase.auth.getUser();
      if (userError || !user) throw new Error("Your verified session has expired. Sign in again.");
      const objectKey = `${user.id}/profile/${crypto.randomUUID()}.jpg`;
      const { error: uploadError } = await supabase.storage.from("profile-private").upload(objectKey, photo, {
        contentType: "image/jpeg", upsert: false, cacheControl: "0"
      });
      if (uploadError) throw uploadError;
      const { error: registrationError } = await supabase.rpc("complete_registration", {
        p_display_name: name.trim(), p_date_of_birth: dob, p_profile_photo_object_key: objectKey,
        p_terms_version: policy.terms_version, p_privacy_version: policy.privacy_version,
        p_user_agent: navigator.userAgent
      });
      if (registrationError) throw registrationError;
      navigate("/reader", { replace: true });
    } catch (reason) { setError(userFacingAuthError(reason)); }
    finally { setBusy(false); }
  };

  return <AuthLayout title="Make room for stories." description="Create one account to read, share and discover books nearby.">
    <form className="auth-form" onSubmit={(event) => { event.preventDefault(); void (step === "details" ? requestOtp() : step === "otp" ? verifyOtp() : completeRegistration()); }}>
      {error && <Alert tone="warning">{error}</Alert>}
      {step === "details" && <>
        <Input label="Your name" name="name" autoComplete="name" placeholder="Name as you’d like it shown" required maxLength={80} value={name} onChange={(event) => setName(event.target.value)}/>
        <Input label="Date of birth" name="dob" type="date" required max={maxAdultDob} value={dob} onChange={(event) => setDob(event.target.value)} hint="You must be at least 18 years old to register."/>
        <Input label="Indian mobile number" name="phone" type="tel" inputMode="tel" autoComplete="tel" placeholder="+91 98765 43210" required readOnly={Boolean(user)} value={phone} onChange={(event) => setPhone(event.target.value)} hint={user ? "This number is already verified for your current session." : "Mobile OTP only. No email OTP is used."}/>
        <div className="legal-consent">
          {policyLoading ? <p>Checking current legal terms…</p> : policy ? <>
            <label className="check-row"><input type="checkbox" checked={accepted} onChange={(event) => setAccepted(event.target.checked)}/><span>I have read and agree to the <a href={policy.terms_url} target="_blank" rel="noreferrer">Terms of Service and Rental Agreement</a> and <a href={policy.privacy_url} target="_blank" rel="noreferrer">Privacy Notice</a>.</span></label>
            <small>Terms {policy.terms_version} · Privacy {policy.privacy_version}</small>
          </> : <Alert tone="warning">Registration is disabled until ShelfShare publishes and activates approved Terms and Privacy documents.</Alert>}
        </div>
        <AuthCaptcha resetKey={captchaReset} onToken={setCaptchaToken}/>
        <Button type="submit" size="lg" block disabled={busy || policyLoading || !policy || !accepted || (!user && captchaRequired && !captchaToken)}><Smartphone size={17}/>{busy ? "Sending OTP…" : user ? "Continue to live photo" : "Create account with OTP"}</Button>
      </>}
      {step === "otp" && <>
        <Alert tone="info">Enter the six-digit code sent to <strong>{normalisedPhone}</strong>. It expires after five minutes.</Alert>
        <Input label="6-digit OTP" name="otp" inputMode="numeric" autoComplete="one-time-code" placeholder="000000" maxLength={6} required value={code} onChange={(event) => setCode(event.target.value.replace(/\\D/g, "").slice(0, 6))}/>
        <Button type="submit" size="lg" block disabled={busy || code.length !== 6}>{busy ? "Verifying…" : "Verify mobile number"}</Button>
        <AuthCaptcha resetKey={captchaReset} onToken={setCaptchaToken}/>
        <Button type="button" variant="ghost" block disabled={busy || seconds > 0 || (captchaRequired && !captchaToken)} onClick={() => void requestOtp()}>{seconds > 0 ? `Resend OTP in ${seconds}s` : "Resend OTP"}</Button>
      </>}
      {step === "camera" && <>
        <div className="camera-requirement"><span className="camera-icon"><Camera size={19}/></span><div><strong>First-time live profile photo</strong><p>Use your device camera now. Gallery uploads are not accepted for registration.</p></div></div>
        <LiveCameraCapture onCapture={setPhoto}/>
        {photo && <Alert tone="success">Live camera photo captured. It will be uploaded to private storage.</Alert>}
        <Button type="submit" size="lg" block disabled={busy || !photo}><ShieldCheck size={17}/>{busy ? "Creating your account…" : "Complete registration"}</Button>
      </>}
    </form>
    <div className="auth-switch">Already have an account? <Link to="/login">Sign in</Link></div>
    <div className="auth-security-note"><ShieldCheck size={16}/> Identity verification is a separate manual approval step.</div>
  </AuthLayout>;
}

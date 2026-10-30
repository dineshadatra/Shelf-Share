import { useEffect, useState } from "react";
import { Link, useLocation, useNavigate, useSearchParams } from "react-router-dom";
import { ArrowLeft, LockKeyhole, Smartphone } from "lucide-react";
import { AuthLayout } from "@/layouts/auth-layout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Alert } from "@/components/ui/alert";
import { supabase, normaliseIndianPhone, userFacingAuthError } from "@/lib/supabase";

export default function LoginPage() {
  const [phone, setPhone] = useState("");
  const [normalisedPhone, setNormalisedPhone] = useState("");
  const [code, setCode] = useState("");
  const [step, setStep] = useState<"phone" | "otp">("phone");
  const [seconds, setSeconds] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const navigate = useNavigate();
  const location = useLocation();
  const [search] = useSearchParams();
  const fromState = (location.state as { from?: string } | null)?.from;
  const requestedPath = search.get("next") ?? fromState ?? "/reader";
  const nextPath = requestedPath.startsWith("/") && !requestedPath.startsWith("//") ? requestedPath : "/reader";

  useEffect(() => {
    if (seconds <= 0) return;
    const timer = window.setInterval(() => setSeconds((value) => Math.max(0, value - 1)), 1000);
    return () => window.clearInterval(timer);
  }, [seconds > 0]);

  const requestOtp = async () => {
    setError("");
    if (!supabase) { setError("Supabase is not configured. Add the VITE_SUPABASE environment variables."); return; }
    try {
      const formatted = normaliseIndianPhone(phone);
      setBusy(true);
      const { error: otpError } = await supabase.auth.signInWithOtp({
        phone: formatted, options: { shouldCreateUser: false, channel: "sms" }
      });
      if (otpError) throw otpError;
      setNormalisedPhone(formatted); setStep("otp"); setSeconds(60);
    } catch (reason) { setError(userFacingAuthError(reason)); }
    finally { setBusy(false); }
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
      navigate(nextPath, { replace: true });
    } catch (reason) { setError(userFacingAuthError(reason)); }
    finally { setBusy(false); }
  };

  return <AuthLayout title="Welcome back." description="Sign in securely with your Indian mobile number.">
    <form className="auth-form" onSubmit={(event) => { event.preventDefault(); void (step === "phone" ? requestOtp() : verifyOtp()); }}>
      {error && <Alert tone="warning">{error}</Alert>}
      {step === "phone" ? <>
        <Input label="Indian mobile number" name="phone" type="tel" inputMode="tel" autoComplete="tel" placeholder="+91 98765 43210" required value={phone} onChange={(event) => setPhone(event.target.value)} hint="We send an SMS OTP only. Email OTP and password sign-in are not used."/>
        <Button type="submit" block size="lg" disabled={busy}><Smartphone size={17}/>{busy ? "Sending…" : "Send mobile OTP"}</Button>
      </> : <>
        <Alert tone="info">Enter the six-digit code sent to <strong>{normalisedPhone}</strong>. It expires after five minutes.</Alert>
        <Input label="6-digit OTP" name="otp" inputMode="numeric" autoComplete="one-time-code" placeholder="000000" maxLength={6} required value={code} onChange={(event) => setCode(event.target.value.replace(/\\D/g, "").slice(0, 6))}/>
        <Button type="submit" block size="lg" disabled={busy || code.length !== 6}><LockKeyhole size={17}/>{busy ? "Verifying…" : "Verify & sign in"}</Button>
        <Button type="button" variant="ghost" block disabled={busy || seconds > 0} onClick={() => void requestOtp()}>{seconds > 0 ? `Resend OTP in ${seconds}s` : "Resend OTP"}</Button>
        <Button type="button" variant="link" block onClick={() => { setStep("phone"); setCode(""); setError(""); }}><ArrowLeft size={15}/> Change mobile number</Button>
      </>}
    </form>
    <div className="auth-switch">New to ShelfShare? <Link to="/register">Create an account</Link></div>
    <div className="auth-security-note"><LockKeyhole size={16}/> OTP attempts and SMS sends are rate-limited by Supabase Auth.</div>
  </AuthLayout>;
}

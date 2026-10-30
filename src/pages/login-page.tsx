import { useEffect, useState } from "react";
import { Link, useLocation, useNavigate, useSearchParams } from "react-router-dom";
import { ArrowLeft, LockKeyhole, Smartphone } from "lucide-react";
import { AuthLayout } from "@/layouts/auth-layout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Alert } from "@/components/ui/alert";
import { AuthCaptcha, captchaRequired } from "@/components/auth/auth-captcha";
import { supabase, normaliseIndianPhone, userFacingAuthError } from "@/lib/supabase";

export default function LoginPage() {
  const [phone, setPhone] = useState("");
  const [normalisedPhone, setNormalisedPhone] = useState("");
  const [code, setCode] = useState("");
  const [step, setStep] = useState<"phone" | "otp">("phone");
  const [seconds, setSeconds] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  const [captchaReset, setCaptchaReset] = useState(0);
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
  }, [seconds]);

  const requestOtp = async () => {
    setError("");
    if (!supabase) { setError("Supabase is not configured. Add the VITE_SUPABASE environment variables."); return; }
    if (captchaRequired && !captchaToken) { setError("Complete the security check before requesting an OTP."); return; }
    try {
      const formatted = normaliseIndianPhone(phone);
      setBusy(true);
      const { error: otpError } = await supabase.auth.signInWithOtp({
        phone: formatted, options: { shouldCreateUser: false, channel: "sms", ...(captchaToken ? { captchaToken } : {}) }
      });
      if (otpError) throw otpError;
      setNormalisedPhone(formatted); setStep("otp"); setSeconds(60);
    } catch (reason) { setError(userFacingAuthError(reason)); }
    finally { setBusy(false); setCaptchaToken(null); setCaptchaReset((value) => value + 1); }
  };

  const verifyOtp = async () => {
    setError("");
    if (!supabase) return;
    if (captchaRequired && !captchaToken) { setError("Complete the security check before verifying the OTP."); return; }
    if (!/^\\d{6}$/.test(code)) { setError("Enter the six-digit code sent to your mobile."); return; }
    setBusy(true);
    try {
      const { data, error: verifyError } = await supabase.auth.verifyOtp({ phone: normalisedPhone, token: code, type: "sms", options: captchaToken ? { captchaToken } : undefined });
      if (verifyError) throw verifyError;
      if (!data.user) throw new Error("The mobile number could not be verified.");
      navigate(nextPath, { replace: true });
    } catch (reason) { setError(userFacingAuthError(reason)); }
    finally { setBusy(false); setCaptchaToken(null); setCaptchaReset((value) => value + 1); }
  };

  return <AuthLayout title="Welcome back." description="Sign in securely with your Indian mobile number.">
    <form className="auth-form" onSubmit={(event) => { event.preventDefault(); void (step === "phone" ? requestOtp() : verifyOtp()); }}>
      {error && <Alert tone="warning">{error}</Alert>}
      {step === "phone" ? <>
        <Input label="Indian mobile number" name="phone" type="tel" inputMode="tel" autoComplete="tel" placeholder="+91 98765 43210" required value={phone} onChange={(event) => setPhone(event.target.value)} hint="We send an SMS OTP only. Email OTP and password sign-in are not used."/>
        <AuthCaptcha resetKey={captchaReset} onToken={setCaptchaToken}/>
        <Button type="submit" block size="lg" disabled={busy || (captchaRequired && !captchaToken)}><Smartphone size={17}/>{busy ? "Sending…" : "Send mobile OTP"}</Button>
      </> : <>
        <Alert tone="info">Enter the six-digit code sent to <strong>{normalisedPhone}</strong>. It expires after five minutes.</Alert>
        <Input label="6-digit OTP" name="otp" inputMode="numeric" autoComplete="one-time-code" placeholder="000000" maxLength={6} required value={code} onChange={(event) => setCode(event.target.value.replace(/\\D/g, "").slice(0, 6))}/>
        <Button type="submit" block size="lg" disabled={busy || code.length !== 6 || (captchaRequired && !captchaToken)}><LockKeyhole size={17}/>{busy ? "Verifying…" : "Verify & sign in"}</Button>
        <AuthCaptcha resetKey={captchaReset} onToken={setCaptchaToken}/>
        <Button type="button" variant="ghost" block disabled={busy || seconds > 0 || (captchaRequired && !captchaToken)} onClick={() => void requestOtp()}>{seconds > 0 ? `Resend OTP in ${seconds}s` : "Resend OTP"}</Button>
        <Button type="button" variant="link" block onClick={() => { setStep("phone"); setCode(""); setError(""); }}><ArrowLeft size={15}/> Change mobile number</Button>
      </>}
    </form>
    <div className="auth-switch">New to ShelfShare? <Link to="/register">Create an account</Link></div>
    <div className="auth-security-note"><LockKeyhole size={16}/> OTP attempts and SMS sends are rate-limited by Supabase Auth.</div>
  </AuthLayout>;
}

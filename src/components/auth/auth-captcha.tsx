import { Turnstile } from "@marsidev/react-turnstile";
import { Alert } from "@/components/ui/alert";

const siteKey = import.meta.env.VITE_TURNSTILE_SITE_KEY as string | undefined;
export const captchaRequired = import.meta.env.VITE_CAPTCHA_REQUIRED === "true";

export function AuthCaptcha({ resetKey, onToken }: {
  resetKey: number;
  onToken: (token: string | null) => void;
}) {
  if (!siteKey) {
    return captchaRequired
      ? <Alert tone="error" title="Security check unavailable">ShelfShare requires CAPTCHA for authentication, but the Turnstile site key is missing.</Alert>
      : <p className="ss-field-hint">CAPTCHA is disabled in this local environment. Enable it before production.</p>;
  }

  return <div className="auth-captcha">
    <Turnstile
      key={resetKey}
      siteKey={siteKey}
      onSuccess={(token) => onToken(token)}
      onExpire={() => onToken(null)}
      onError={() => onToken(null)}
    />
  </div>;
}

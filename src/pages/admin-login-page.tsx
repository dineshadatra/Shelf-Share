import { Link } from "react-router-dom";
import { LockKeyhole, Smartphone } from "lucide-react";
import { AuthLayout } from "@/layouts/auth-layout";
import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/alert";

export default function AdminLoginPage() {
  return <AuthLayout title="Admin access." description="ShelfShare operations staff sign in with their verified mobile number.">
    <div className="auth-form">
      <Alert tone="info"><LockKeyhole size={16}/> Admin access is granted only to accounts with an active server-side reviewer/admin role. A normal member account cannot open the verification queue.</Alert>
      <Button asChild block size="lg"><Link to="/login?next=%2Fadmin%2Fverifications"><Smartphone size={17}/> Continue with mobile OTP</Link></Button>
    </div>
    <div className="auth-switch"><Link to="/">Return to the public site</Link></div>
  </AuthLayout>;
}

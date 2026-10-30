import type { ReactNode } from "react";
import { Link } from "react-router-dom";
import { ArrowLeft } from "lucide-react";
import { BrandMark } from "@/components/brand/brand-mark";

export function AuthLayout({ children, title, description }: { children: ReactNode; title: string; description: string }) {
  return <main className="auth-layout">
    <div className="auth-aside">
      <BrandMark light/>
      <div className="auth-aside-copy"><span className="eyebrow">A little more local. A lot more stories.</span><h1 className="serif">Good books<br/>find good people.</h1><p>Discover the books sitting on shelves just around your corner.</p></div>
      <p className="auth-aside-foot">Read more. Own less. Share better.</p>
    </div>
    <section className="auth-main">
      <Link to="/" className="auth-back"><ArrowLeft size={15}/> Back to ShelfShare</Link>
      <div className="auth-panel"><span className="eyebrow">WELCOME TO SHELFSHARE</span><h2 className="serif">{title}</h2><p className="auth-description">{description}</p>{children}
        <p className="auth-legal">Sign-in codes are sent by SMS to your mobile number. Email OTP is not used.</p>
      </div>
    </section>
  </main>;
}

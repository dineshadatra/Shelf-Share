import { useCallback, useEffect, useMemo, useState } from "react";
import { CheckCircle2, Clock3, CreditCard, FileCheck2, Handshake, RefreshCw, ShieldAlert, UploadCloud } from "lucide-react";
import { QRCodeSVG } from "qrcode.react";
import { MemberLayout } from "@/layouts/member-layout";
import { PageHeading } from "./page-helpers";
import { EmptyState } from "@/components/ui/empty-state";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Alert } from "@/components/ui/alert";
import { supabase } from "@/lib/supabase";
import { useAuth } from "@/contexts/auth-context";
import { QRCodeScanner } from "@/components/marketplace/qr-code-scanner";

type Handover = {
  id:string; type:"collection"|"return"; expires_at:string; status:string; created_at:string;
  completed_at:string|null; initiator_id:string; qr_consumed_at:string|null;
  owner_confirmed:boolean; reader_confirmed:boolean;
  owner_condition_confirmed:boolean; reader_condition_confirmed:boolean;
  owner_photo_count:number; reader_photo_count:number;
};
type Booking = {
  id:string; booking_number:string; status:string; reader_id:string; owner_id:string; is_reader:boolean;
  requested_start_at:string; requested_end_at:string; requested_duration_days:number;
  rent_subtotal_paise:number; platform_fee_paise:number; tax_paise:number; deposit_required_paise:number;
  total_due_paise:number; created_at:string; accepted_at:string|null; completed_at:string|null;
  cancellation_reason_code:string|null; title:string|null; authors:string[]|null; copy_id:string;
  condition:string|null; locality_id:string|null; handover_location:string|null;
  handover_location_id:string|null; payment_status:string|null; payment_amount_paise:number|null;
  checkout_url:string|null; owner_agreement_accepted:boolean; reader_agreement_accepted:boolean;
  rental_start_at:string|null; rental_due_at:string|null; active_handover:Handover|null;
};
type Provider = {provider:string;adapter_registered:boolean;approved:boolean;deposits_approved:boolean};
type FinancialTransaction = {transaction_type:string;reference_id:string;status:string;amount_paise:number;currency:string;description:string;created_at:string};
type DepositPosition = {deposit_id:string;booking_id:string;status:string;amount_paise:number;locked_paise:number;available_for_release_paise:number;currency:string;provider_reference:string|null};
type Agreement = {title:string;version:string;content_uri:string};
type Secret = {sessionId:string;token:string;otp:string;expiresAt:string};

const INR=new Intl.NumberFormat("en-IN",{style:"currency",currency:"INR",maximumFractionDigits:2});
const dateTime=(value:string|null|undefined)=>value?new Intl.DateTimeFormat("en-IN",{dateStyle:"medium",timeStyle:"short",timeZone:"Asia/Kolkata"}).format(new Date(value)):"—";
const ACTIVE=["confirmed","collection_pending","active","return_pending","disputed"];
const PAST=["completed","cancelled","expired"];

export default function RentalHistoryPage(){
  const {user}=useAuth();
  const [bookings,setBookings]=useState<Booking[]>([]);
  const [providers,setProviders]=useState<Provider[]>([]);
  const [transactions,setTransactions]=useState<FinancialTransaction[]>([]);
  const [depositPositions,setDepositPositions]=useState<DepositPosition[]>([]);
  const [agreement,setAgreement]=useState<Agreement|null>(null);
  const [secrets,setSecrets]=useState<Record<string,Secret>>({});
  const [otpValues,setOtpValues]=useState<Record<string,string>>({});
  const [incidentText,setIncidentText]=useState<Record<string,string>>({});
  const [disputeReason,setDisputeReason]=useState<Record<string,string>>({});
  const [disputeDescription,setDisputeDescription]=useState<Record<string,string>>({});
  const [scannerSession,setScannerSession]=useState<string|null>(null);
  const [loading,setLoading]=useState(true);
  const [busyId,setBusyId]=useState<string|null>(null);
  const [error,setError]=useState("");
  const [notice,setNotice]=useState("");
  const [currentTime,setCurrentTime]=useState(0);

  useEffect(()=>{
    const refreshClock=()=>setCurrentTime(Date.now());
    refreshClock();
    const interval=window.setInterval(refreshClock,1000);
    return ()=>window.clearInterval(interval);
  },[]);

  const load=useCallback(async()=>{
    if(!supabase){setLoading(false);return;}
    setError("");
    const [{data:bookingsData,error:bookingError},{data:providerData},{data:agreementData},{data:financialData}] = await Promise.all([
      supabase.rpc("get_my_booking_workspace"),
      supabase.functions.invoke("marketplace-api",{body:{action:"payment_capabilities"}}),
      supabase.from("legal_documents").select("title,version,content_uri")
        .eq("document_type","rental_agreement").eq("is_published",true)
        .lte("effective_from",new Date().toISOString()).order("effective_from",{ascending:false}).limit(1),
      supabase.functions.invoke("marketplace-api",{body:{action:"my_financial_history"}}),
    ]);
    if(bookingError){setError(bookingError.message);setBookings([]);}
    else setBookings((Array.isArray(bookingsData)?bookingsData:[]) as Booking[]);
    setProviders((providerData?.providers??[]) as Provider[]);
    setTransactions((financialData?.transactions??[]) as FinancialTransaction[]);
    setDepositPositions((financialData?.deposits??[]) as DepositPosition[]);
    setAgreement(((agreementData??[])[0]??null) as Agreement|null);
    setLoading(false);
  },[]);

  useEffect(()=>{void load();},[load]);

  const provider=useMemo(()=>providers.find(x=>x.approved&&x.adapter_registered),[providers]);

  const invoke=async(action:string,body:Record<string,unknown>)=>{
    if(!supabase)throw new Error("ShelfShare backend is not configured.");
    const {data,error:invokeError}=await supabase.functions.invoke("marketplace-api",{body:{action,...body}});
    if(invokeError)throw new Error(invokeError.message);
    return data;
  };

  const run=async(id:string,work:()=>Promise<void>)=>{
    setBusyId(id);setError("");setNotice("");
    try{await work();await load();}
    catch(e){setError(e instanceof Error?e.message:"The request could not be completed.");}
    finally{setBusyId(null);}
  };

  const acceptBooking=(booking:Booking)=>run(booking.id,async()=>{
    await invoke("owner_accept",{booking_id:booking.id});
    setNotice("You accepted the rental request. The reader must accept the current rental agreement before payment can begin.");
  });
  const declineBooking=(booking:Booking)=>run(booking.id,async()=>{
    const reason=window.prompt("Reason for declining this request (at least 5 characters):");
    if(!reason||reason.trim().length<5)throw new Error("A reason is required to decline a booking request.");
    await invoke("owner_decline",{booking_id:booking.id,reason});
    setNotice("Booking request declined. No payment was taken.");
  });
  const acceptAgreement=(booking:Booking)=>run(booking.id,async()=>{
    if(!agreement)throw new Error("There is no current published rental agreement to accept.");
    const {error:rpcError}=await supabase!.rpc("accept_booking_agreement",{p_booking_id:booking.id});
    if(rpcError)throw new Error(rpcError.message);
    setNotice("Rental agreement acceptance was recorded for version "+agreement.version+".");
  });
  const beginPayment=(booking:Booking)=>run(booking.id,async()=>{
    if(!provider)throw new Error("Checkout is disabled until a provider adapter and written marketplace approval are configured.");
    const result=await invoke("begin_payment",{booking_id:booking.id,provider:provider.provider});
    if(result?.checkout_url&&typeof result.checkout_url==="string"){
      setNotice("Opening the provider checkout. Booking confirmation will come from a verified provider webhook, not the browser return page.");
      window.location.assign(result.checkout_url);
      return;
    }
    setNotice("Payment initiation is being reconciled. This is not a payment-success confirmation.");
  });
  const startHandover=(booking:Booking,type:"collection"|"return")=>run(booking.id,async()=>{
    const result=await invoke("start_handover",{booking_id:booking.id,handover_type:type});
    setSecrets(s=>({...s,[booking.id]:{sessionId:result.session_id,token:result.qr_token,otp:result.otp,expiresAt:result.expires_at}}));
    setNotice(type==="collection"?"One-time collection QR created. The other participant must scan it, both parties must acknowledge condition and both must upload photographs.":"One-time return QR created. The other participant must scan it, both parties must acknowledge return condition and both must upload photographs.");
  });
  const openDispute=(booking:Booking)=>run(booking.id,async()=>{
    const reason=disputeReason[booking.id]?.trim();
    const description=disputeDescription[booking.id]?.trim();
    if(!reason||reason.length<3||!description||description.length<20)throw new Error("Provide a dispute reason and at least 20 characters describing the issue.");
    await invoke("open_dispute",{booking_id:booking.id,reason_code:reason,description});
    setNotice("Dispute opened. Settlement and deposit release are blocked until review. Any provider deposit hold is separately confirmed.");
  });
  const requestReturn=(booking:Booking)=>run(booking.id,async()=>{
    await invoke("request_return",{booking_id:booking.id});
    setNotice("Return request recorded. Start a return handover at the agreed public meeting point.");
  });
  const requestDepositRelease=(booking:Booking)=>run(booking.id,async()=>{
    const position=depositPositions.find(x=>x.booking_id===booking.id);
    if(!position||position.available_for_release_paise<=0||!position.provider_reference)
      throw new Error("No provider-confirmed deposit amount is currently eligible for release.");
    await invoke("request_deposit_release",{
      deposit_id:position.deposit_id,
      idempotency_key:"shelfshare-deposit-release-"+crypto.randomUUID(),
    });
    setNotice("Deposit release requested. The deposit remains pending until the provider confirms release.");
  });
  const refreshStatus=()=>run("refresh",async()=>{setNotice("Booking and payment status refreshed from the server.");});
  const confirmOtp=(booking:Booking,session: Handover)=>run(booking.id,async()=>{
    const otp=otpValues[session.id]?.trim();
    if(!otp||!/^\d{6}$/.test(otp))throw new Error("Enter the six-digit handover fallback OTP.");
    const result=await invoke("confirm_handover",{session_id:session.id,otp,condition_acknowledged:true});
    setNotice(result?.completed?"Handover completed by server verification.":"OTP verified. The other party’s confirmation or condition photographs are still required.");
    setOtpValues(v=>({...v,[session.id]:""}));
  });
  const confirmInitiator=(booking:Booking,session:Handover)=>run(booking.id,async()=>{
    const result=await invoke("confirm_handover_initiator",{session_id:session.id,condition_acknowledged:true});
    setNotice(result?.completed?"Handover completed and rental status updated by the server.":"Your confirmation is recorded. Both parties’ photographs and confirmations are still required.");
  });
  const uploadConditionPhoto=async(booking:Booking,session:Handover,file:File)=>{
    await run(booking.id,async()=>{
      if(!supabase||!user)throw new Error("Sign in to upload condition evidence.");
      if(!["image/jpeg","image/png","image/webp"].includes(file.type)||file.size>10*1024*1024)throw new Error("Choose a JPEG, PNG or WebP image up to 10 MB.");
      const extension=file.type==="image/png"?"png":file.type==="image/webp"?"webp":"jpg";
      const objectKey=user.id+"/"+booking.id+"/"+session.id+"/"+crypto.randomUUID()+"."+extension;
      const {error:uploadError}=await supabase.storage.from("rental-evidence-private").upload(objectKey,file,{contentType:file.type,upsert:false});
      if(uploadError)throw new Error(uploadError.message);
      const digest=await crypto.subtle.digest("SHA-256",await file.arrayBuffer());
      const sha=[...new Uint8Array(digest)].map(x=>x.toString(16).padStart(2,"0")).join("");
      await invoke("register_handover_photo",{session_id:session.id,object_key:objectKey,sha256:sha,caption:session.type==="collection"?"Initial rental condition":"Return condition"});
      setNotice("Private condition photograph uploaded and registered. It is not publicly visible.");
    });
  };
  const scanned=useCallback(async(booking:Booking,session:Handover,token:string)=>{
    setScannerSession(null);
    await run(booking.id,async()=>{
      const result=await invoke("confirm_handover",{session_id:session.id,qr_token:token,condition_acknowledged:true});
      setNotice(result?.completed?"Handover completed by server verification.":"QR verified. Waiting for both parties’ evidence and confirmation.");
    });
  },[]);

  const renderHandover=(booking:Booking)=>{
    const session=booking.active_handover;
    const secret=secrets[booking.id];
    const sessionCurrent=Boolean(session&&session.status!=="completed"&&Date.parse(session.expires_at)>currentTime);
    const isInitiator=Boolean(session&&user?.id===session.initiator_id);
    const myPhotos=session?(booking.is_reader?session.reader_photo_count:session.owner_photo_count):0;
    const otherPhotos=session?(booking.is_reader?session.owner_photo_count:session.reader_photo_count):0;
    const myConfirmed=session?(booking.is_reader?session.reader_confirmed:session.owner_confirmed):false;

    if(session&&session.status==="completed"){
      return <Alert tone="success"><CheckCircle2 size={16}/> {session.type==="collection"?"Collection handover completed. Rental is active.":"Return handover completed. Rental is closed."} Both parties’ photographs and confirmations are recorded.</Alert>;
    }

    return <section className="surface" style={{padding:"1rem",display:"grid",gap:".8rem"}}>
      <div><strong><Handshake size={16} style={{verticalAlign:"middle"}}/> {sessionCurrent?(session!.type==="collection"?"Collection handover":"Return handover"):"Physical handover"}</strong>
        <p className="muted">{booking.handover_location??"Approved public location"} · No residential address is shared.</p></div>
      {sessionCurrent&&<>
        <div className="booking-progress-grid">
          <span>Owner confirmation: <b>{session!.owner_confirmed?"Done":"Pending"}</b></span>
          <span>Reader confirmation: <b>{session!.reader_confirmed?"Done":"Pending"}</b></span>
          <span>Owner photos: <b>{session!.owner_photo_count}</b></span>
          <span>Reader photos: <b>{session!.reader_photo_count}</b></span>
        </div>
        <p className="muted">QR expires {dateTime(session!.expires_at)}. Each participant must confirm independently and upload at least one condition photo.</p>
        {isInitiator&&secret?.sessionId===session!.id&&Date.parse(secret.expiresAt)>currentTime&&<div style={{display:"grid",justifyItems:"center",gap:".5rem"}}>
          <QRCodeSVG value={secret.token} size={220} level="H" includeMargin/>
          <strong>One-time handover QR</strong>
          <p className="muted">Show this only to the other booking participant.</p>
          <p>OTP fallback: <strong style={{letterSpacing:".2em"}}>{secret.otp}</strong></p>
        </div>}
        {isInitiator&&(!secret||secret.sessionId!==session!.id)&&!session!.qr_consumed_at&&<>
          <Alert tone="info">This device no longer has the original QR secret. The unused token can be invalidated and replaced; the replacement expires shortly.</Alert>
          <Button variant="outline" onClick={()=>void startHandover(booking,session!.type)} disabled={busyId===booking.id}>Replace unused QR and OTP</Button>
        </>}
        {isInitiator&&(!secret||secret.sessionId!==session!.id)&&session!.qr_consumed_at&&
          <Alert tone="info">The other participant has already consumed the QR. Do not rotate it; upload your condition photograph and confirm your side below.</Alert>}
        {!isInitiator&&!myConfirmed&&myPhotos>0&&<div style={{display:"grid",gap:".5rem"}}>
          <Button onClick={()=>setScannerSession(session!.id)}>Scan participant QR with camera</Button>
          {scannerSession===session!.id&&<QRCodeScanner onScan={token=>void scanned(booking,session!,token)} onClose={()=>setScannerSession(null)}/>}
          <label className="ss-field"><span className="ss-label">Or enter one-time OTP</span><input className="ss-input" inputMode="numeric" maxLength={6} value={otpValues[session!.id]??""} onChange={e=>setOtpValues(v=>({...v,[session!.id]:e.target.value.replace(/\D/g,"").slice(0,6)}))}/></label>
          <Button variant="outline" onClick={()=>void confirmOtp(booking,session!)} disabled={busyId===booking.id}>Verify OTP fallback</Button>
        </div>}
        {isInitiator&&session!.qr_consumed_at&&myPhotos>0&&!myConfirmed&&<Button onClick={()=>void confirmInitiator(booking,session!)} disabled={busyId===booking.id}>Confirm my side and condition</Button>}
        <div style={{display:"grid",gap:".4rem"}}>
          <strong>Upload {session!.type==="collection"?"initial condition":"return condition"} photo</strong>
          <input type="file" accept="image/jpeg,image/png,image/webp" disabled={busyId===booking.id}
            onChange={e=>{const file=e.target.files?.[0];if(file)void uploadConditionPhoto(booking,session!,file);e.currentTarget.value="";}}/>
          <p className="muted">Private evidence only · one or more clear photos · up to 10 MB per image.</p>
        </div>
      </>}
      {!sessionCurrent&&(booking.status==="confirmed"||booking.status==="collection_pending"||booking.status==="return_pending")&&<Button onClick={()=>void startHandover(booking,booking.status==="confirmed"?"collection":"return")} disabled={busyId===booking.id}>
        {session&&session.status!=="completed"?"Create a fresh one-time QR":"Start "+(booking.status==="confirmed"?"collection":"return")+" handover"}
      </Button>}
      {session&&sessionCurrent&&!isInitiator&&myConfirmed&&<Alert tone="success">Your side is confirmed. Waiting for the other participant and the required condition photographs.</Alert>}
      {session&&sessionCurrent&&isInitiator&&myConfirmed&&<Alert tone="success">Your side is confirmed. Waiting for the other participant and the required condition photographs.</Alert>}
      {sessionCurrent&&myPhotos===0&&<p className="muted"><UploadCloud size={14} style={{verticalAlign:"middle"}}/> Upload your condition photo before completing your confirmation.</p>}
      {sessionCurrent&&otherPhotos===0&&<p className="muted">Waiting for the other participant to upload a condition photo.</p>}
    </section>;
  };

  const renderBooking=(booking:Booking)=>(
    <article key={booking.id} className="surface" style={{padding:"1.1rem",display:"grid",gap:".8rem"}}>
      <div style={{display:"flex",justifyContent:"space-between",gap:"1rem",alignItems:"flex-start",flexWrap:"wrap"}}>
        <div><span className="eyebrow">{booking.is_reader?"READER BOOKING":"OWNER REQUEST"}</span>
          <h3 style={{margin:".2rem 0"}}>{booking.title??"Book rental"} <span className="muted" style={{fontSize:".85em"}}>· {booking.condition??"Condition not supplied"}</span></h3>
          <p className="muted">{booking.authors?.join(", ")??"Author unavailable"} · {booking.booking_number}</p></div>
        <span className="status-pill">{booking.status.replaceAll("_"," ")}</span>
      </div>
      <div className="booking-progress-grid">
        <span>Start: <b>{dateTime(booking.requested_start_at)}</b></span>
        <span>End: <b>{dateTime(booking.requested_end_at)}</b></span>
        <span>Duration: <b>{booking.requested_duration_days} days</b></span>
        <span>Handover: <b>{booking.handover_location??"—"}</b></span>
      </div>
      <div className="booking-price-breakdown">
        <span>Rental fee <b>{INR.format(booking.rent_subtotal_paise/100)}</b></span>
        <span>Owner-side commission (10%, withheld from rent) <b>{INR.format(booking.platform_fee_paise/100)}</b></span>
        <span>Tax <b>{INR.format(booking.tax_paise/100)}</b></span>
        <span>Security deposit (separate) <b>{booking.deposit_required_paise>0?INR.format(booking.deposit_required_paise/100):"Not configured"}</b></span>
        <strong>Rental checkout total <b>{INR.format(booking.total_due_paise/100)}</b></strong>
      </div>
      <p className="muted" style={{fontSize:".85rem"}}>The 10% commission is deducted from Owner rent proceeds; it is not added as an extra Reader checkout charge. The checkout total includes rental fee and approved tax only. Any security deposit is a separate provider-held amount and remains disabled until approval.</p>
      {booking.payment_status&&<Alert tone={booking.payment_status==="captured"?"success":booking.payment_status==="failed"?"warning":"info"}>
        <CreditCard size={15}/> Provider payment status: <b>{booking.payment_status.replaceAll("_"," ")}</b>. Browser redirects do not confirm payment.
      </Alert>}
      {booking.status==="requested"&&!booking.is_reader&&<div style={{display:"flex",gap:".5rem",flexWrap:"wrap"}}>
        <Button onClick={()=>void acceptBooking(booking)} disabled={busyId===booking.id}>Accept request</Button>
        <Button variant="outline" onClick={()=>void declineBooking(booking)} disabled={busyId===booking.id}>Decline</Button>
      </div>}
      {booking.status==="requested"&&booking.is_reader&&<p className="muted">Waiting for the owner to accept or decline. No payment has been initiated.</p>}
      {booking.status==="owner_accepted"&&booking.is_reader&&<>
        <Alert tone="info"><FileCheck2 size={16}/> The owner accepted your request. Both participants must accept the current rental agreement before checkout.</Alert>
        {agreement&&<p><a href={agreement.content_uri} target="_blank" rel="noreferrer">{agreement.title} · version {agreement.version}</a></p>}
        {!booking.reader_agreement_accepted&&<Button onClick={()=>void acceptAgreement(booking)} disabled={busyId===booking.id||!agreement}>Review and accept rental agreement</Button>}
        {booking.reader_agreement_accepted&&!provider&&<Alert tone="warning">Online checkout is not enabled: ShelfShare has no deployed provider adapter with written approval for this marketplace model. No payment can be initiated.</Alert>}
        {booking.reader_agreement_accepted&&provider&&<Button onClick={()=>void beginPayment(booking)} disabled={busyId===booking.id}>Continue to secure payment</Button>}
      </>}
      {booking.status==="owner_accepted"&&!booking.is_reader&&<Alert tone="info">You accepted this request and the rental agreement. Waiting for the reader’s agreement acceptance and provider-confirmed payment.</Alert>}
      {booking.status==="payment_pending"&&<><Alert tone="info"><Clock3 size={15}/> Payment is pending provider confirmation. Refresh this page after checkout; a successful browser return is not proof of payment.</Alert>
        {booking.is_reader&&booking.checkout_url&&<Button onClick={()=>window.location.assign(booking.checkout_url!)} disabled={busyId===booking.id}>Continue secure provider checkout</Button>}
      </>}
      {booking.status==="confirmed"&&<Alert tone="success">Payment was confirmed by the provider. Agree the collection time and meet only at the approved public handover point.</Alert>}
      {booking.status==="active"&&<div><Alert tone="success">Rental active since {dateTime(booking.rental_start_at)}. Due {dateTime(booking.rental_due_at)}.</Alert>
        {booking.is_reader&&<Button variant="outline" onClick={()=>void requestReturn(booking)} disabled={busyId===booking.id}>Request return</Button>}</div>}
      {booking.status==="return_pending"&&<Alert tone="info">Return has been requested. Complete the QR/OTP flow and upload return-condition photographs from both participants.</Alert>}
      {booking.status==="disputed"&&<Alert tone="warning"><ShieldAlert size={15}/> This booking is under dispute/reconciliation. Financial release and settlement remain blocked while the issue is open.</Alert>}
      {["confirmed","collection_pending","active","return_pending","completed"].includes(booking.status)&&<div className="surface" style={{padding:"1rem",display:"grid",gap:".5rem"}}>
        <strong>Open a rental dispute</strong>
        <label className="ss-field"><span className="ss-label">Reason code</span>
          <select className="ss-input" value={disputeReason[booking.id]??""} onChange={e=>setDisputeReason(v=>({...v,[booking.id]:e.target.value}))}>
            <option value="">Select a reason</option><option value="condition_mismatch">Book condition mismatch</option>
            <option value="handover_safety">Handover or safety issue</option><option value="non_return">Book not returned</option>
            <option value="payment_issue">Payment or refund issue</option><option value="other">Other</option>
          </select>
        </label>
        <label className="ss-field"><span className="ss-label">Explain what happened</span>
          <textarea className="ss-input" rows={3} minLength={20} value={disputeDescription[booking.id]??""}
            onChange={e=>setDisputeDescription(v=>({...v,[booking.id]:e.target.value}))}
            placeholder="Describe the issue, dates, evidence and what outcome you are requesting."/>
        </label>
        <Button variant="outline" onClick={()=>void openDispute(booking)} disabled={busyId===booking.id}>Open dispute</Button>
        <p className="muted">Opening a dispute does not deduct or confiscate any deposit. Any provider-side hold requires a separate signed provider confirmation.</p>
      </div>}
      {booking.status==="completed"&&<Alert tone="success">Return closed on {dateTime(booking.completed_at)}. Any deposit release remains subject to the approved provider custody, inspection/claim window and dispute checks.</Alert>}
      {booking.is_reader&&booking.status==="completed"&&(depositPositions.find(x=>x.booking_id===booking.id)?.available_for_release_paise??0)>0&&
        <Button variant="outline" onClick={()=>void requestDepositRelease(booking)} disabled={busyId===booking.id}>
          Request provider deposit release
        </Button>}
      {ACTIVE.includes(booking.status)&&renderHandover(booking)}
      {booking.status==="confirmed"&&<div style={{display:"grid",gap:".5rem"}}>
        <label className="ss-field"><span className="ss-label">Report a no-show or handover issue</span><textarea className="ss-input" rows={2} value={incidentText[booking.id]??""} onChange={e=>setIncidentText(v=>({...v,[booking.id]:e.target.value}))} placeholder="Describe what happened and where you waited."/></label>
        {booking.is_reader?<Button variant="outline" onClick={()=>void run(booking.id,async()=>{await invoke("report_incident",{booking_id:booking.id,incident_type:"owner_no_show",description:incidentText[booking.id]});setNotice("Owner no-show incident recorded. Financial penalties are not automatically applied.");})} disabled={busyId===booking.id||!(incidentText[booking.id]?.trim().length>=10)}>Report owner no-show</Button>
        :<Button variant="outline" onClick={()=>void run(booking.id,async()=>{await invoke("report_incident",{booking_id:booking.id,incident_type:"reader_no_show",description:incidentText[booking.id]});setNotice("Reader no-show incident recorded. Financial penalties are not automatically applied.");})} disabled={busyId===booking.id||!(incidentText[booking.id]?.trim().length>=10)}>Report reader no-show</Button>}
      </div>}
    </article>
  );

  const upcoming=bookings.filter(x=>["requested","owner_accepted","payment_pending","confirmed","collection_pending"].includes(x.status));
  const active=bookings.filter(x=>["active","return_pending","disputed"].includes(x.status));
  const past=bookings.filter(x=>PAST.includes(x.status));
  return <MemberLayout title="Rental history">
    <PageHeading eyebrow="YOUR READING JOURNEY" title="Every book leaves a little mark." description="Track rental requests, provider-confirmed payments, handovers, active rentals and returns."/>
    {error&&<Alert tone="error">{error}</Alert>}{notice&&<Alert tone="success">{notice}</Alert>}
    <div style={{display:"flex",justifyContent:"flex-end"}}><Button variant="outline" size="sm" onClick={()=>void refreshStatus()}><RefreshCw size={14}/> Refresh server status</Button></div>
    {loading?<p>Loading your bookings…</p>:bookings.length===0?<EmptyState icon={<Clock3 size={28}/>} title="Nothing on your reading table yet" description="Your rental requests and completed bookings will appear here."/>:
    <Tabs defaultValue="upcoming">
      <TabsList><TabsTrigger value="upcoming">Requests & upcoming ({upcoming.length})</TabsTrigger><TabsTrigger value="active">Active & return ({active.length})</TabsTrigger><TabsTrigger value="past">Past ({past.length})</TabsTrigger></TabsList>
      <TabsContent value="upcoming"><div style={{display:"grid",gap:"1rem"}}>{upcoming.length?upcoming.map(renderBooking):<EmptyState title="No upcoming bookings" description="New rental requests will appear here."/ >}</div></TabsContent>
      <TabsContent value="active"><div style={{display:"grid",gap:"1rem"}}>{active.length?active.map(renderBooking):<EmptyState title="No active rentals" description="After provider-confirmed payment and collection, your active rentals appear here."/ >}</div></TabsContent>
      <TabsContent value="past"><div style={{display:"grid",gap:"1rem"}}>{past.length?past.map(renderBooking):<EmptyState title="No past rentals" description="Completed or cancelled bookings appear here."/ >}</div></TabsContent>
    </Tabs>}
    {!loading&&<section className="surface" style={{padding:"1.1rem",display:"grid",gap:"1rem",marginTop:"1.25rem"}}>
      <div><span className="eyebrow">FINANCIAL ACTIVITY</span><h2 style={{margin:".2rem 0"}}>Payments, refunds and settlements</h2>
        <p className="muted">Statuses and amounts are read from ShelfShare’s server records. A pending or failed transaction is not a completed payment or payout.</p></div>
      {transactions.length===0?<EmptyState title="No financial transactions yet" description="Provider-confirmed payments, refunds and owner settlements will appear here."/>:
        <div style={{display:"grid",gap:".55rem"}}>{transactions.map(item=><div key={item.transaction_type+item.reference_id} style={{display:"flex",justifyContent:"space-between",gap:"1rem",flexWrap:"wrap",borderBottom:"1px solid var(--border)",paddingBottom:".6rem"}}>
          <div><strong>{item.description}</strong><div className="muted" style={{fontSize:".85rem"}}>{item.transaction_type.replaceAll("_"," ")} · {dateTime(item.created_at)}</div></div>
          <div style={{textAlign:"right"}}><strong>{INR.format(item.amount_paise/100)}</strong><div className="muted" style={{fontSize:".85rem"}}>{item.status.replaceAll("_"," ")}</div></div>
        </div>)}</div>}
      <div><h3 style={{marginBottom:".35rem"}}>Booking-scoped security deposits</h3>
        <p className="muted">These are not a pooled wallet. Locked or releasable values are shown only when backed by a provider reference and provider-confirmed deposit events.</p></div>
      {depositPositions.length===0?<p className="muted">No provider-backed deposits are recorded.</p>:
        <div style={{display:"grid",gap:".7rem"}}>{depositPositions.map(item=><div key={item.deposit_id} style={{border:"1px solid var(--border)",borderRadius:".65rem",padding:".8rem"}}>
          <div style={{display:"flex",justifyContent:"space-between",gap:"1rem",flexWrap:"wrap"}}><strong>Booking deposit · {item.status.replaceAll("_"," ")}</strong><span>{INR.format(item.amount_paise/100)}</span></div>
          <div className="booking-progress-grid" style={{marginTop:".5rem"}}>
            <span>Provider-locked <b>{INR.format(item.locked_paise/100)}</b></span>
            <span>Eligible for release <b>{INR.format(item.available_for_release_paise/100)}</b></span>
          </div>
        </div>)}</div>}
    </section>}
  </MemberLayout>;
}

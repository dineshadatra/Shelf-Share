import { useCallback, useEffect, useState } from "react";
import { Eye, RefreshCw, ShieldCheck } from "lucide-react";
import { AdminLayout } from "@/layouts/admin-layout";
import { PageHeading } from "./page-helpers";
import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { supabase } from "@/lib/supabase";

type AdminListing={
  id:string;owner_id:string;condition_summary:string;description:string|null;listing_status:string;created_at:string;
  owner:{display_name:string;account_status:string};title:{title:string;authors:string[];isbn13:string|null;edition:string|null;publisher:string|null;moderation_status:string}|null;
  locality:string;verification:{status:string;age_eligible:boolean|null}|null;
  details:{existing_damage:string;original_price_paise:number|null;original_price_evidence_note:string|null;requested_deposit_paise:number;ownership_declaration_type:string}|null;
  pricing:Record<string,number|null>|null;
  images:Array<{id:string;alt_text:string|null;moderation_status:string;is_cover:boolean;url?:string|null}>;
  history:Array<{id:number;actor_user_id:string|null;action:string;from_status:string|null;to_status:string;reason:string|null;created_at:string}>;
};
const INR=new Intl.NumberFormat("en-IN",{style:"currency",currency:"INR",maximumFractionDigits:2});

export default function AdminListingQueuePage(){
  const [listings,setListings]=useState<AdminListing[]>([]);
  const [loading,setLoading]=useState(true);
  const [busy,setBusy]=useState("");
  const [error,setError]=useState("");
  const load=useCallback(async()=>{
    if(!supabase){setLoading(false);return;}
    setLoading(true);setError("");
    const {data,error:invokeError}=await supabase.functions.invoke("catalogue-api",{body:{action:"admin_queue"}});
    if(invokeError)setError(invokeError.message);
    else setListings((data?.listings??[]) as AdminListing[]);
    setLoading(false);
  },[]);
  useEffect(()=>{void load();},[load]);
  const preview=async(item:AdminListing,imageId:string)=>{
    if(!supabase)return;
    const purpose=window.prompt("Why are you viewing this submitted listing photograph? This will be audited.","Manual listing moderation");
    if(!purpose||purpose.trim().length<5)return;
    const w=window.open("about:blank","_blank");
    if(!w){setError("Allow pop-ups for ShelfShare to open a private photo preview.");return;}
    w.opener=null;
    const {data,error:invokeError}=await supabase.functions.invoke("catalogue-api",{body:{action:"preview_image",copy_id:item.id,image_id:imageId,purpose}});
    if(invokeError||!data?.signed_url){w.close();setError(invokeError?.message??"Preview could not be created.");return;}
    w.location.href=data.signed_url;
  };
  const previewEvidence=async(item:AdminListing)=>{
    if(!supabase)return;
    const purpose=window.prompt("Why are you reviewing this original-price evidence? This will be audited.","Review original-price evidence");
    if(!purpose||purpose.trim().length<5)return;
    const w=window.open("about:blank","_blank");
    if(!w){setError("Allow pop-ups for ShelfShare to open a secure evidence preview.");return;}
    w.opener=null;
    const {data,error:invokeError}=await supabase.functions.invoke("catalogue-api",{body:{action:"preview_price_evidence",copy_id:item.id,purpose}});
    if(invokeError||!data?.signed_url){w.close();setError(invokeError?.message??"Evidence preview could not be created.");return;}
    w.location.href=data.signed_url;
  };
  const decide=async(item:AdminListing,decision:"approve"|"reject"|"suspend"|"remove")=>{
    if(!supabase)return;
    const labels={approve:"Optional approval note",reject:"Reason shown to the owner",suspend:"Reason for suspending this listing",remove:"Reason for removing this listing"};
    const reason=window.prompt(labels[decision],"");
    if(reason===null||(decision!=="approve"&&reason.trim().length<5))return;
    const notes=window.prompt("Internal moderation notes (optional)","")??"";
    setBusy(item.id);setError("");
    const {error:invokeError}=await supabase.functions.invoke("catalogue-api",{body:{
      action:"moderate_listing",copy_id:item.id,decision,reason:reason||"Listing approved after manual review",internal_notes:notes,
    }});
    if(invokeError)setError(invokeError.message);
    await load();setBusy("");
  };
  const tone=(status:string)=>status==="approved"?"green":status==="pending_review"?"amber":status==="rejected"||status==="removed"?"rose":"neutral";
  return <AdminLayout>
    <PageHeading eyebrow="MARKETPLACE TRUST" title="Book listing moderation" description="Review catalogue metadata and real copy photographs before a listing becomes discoverable." action={<Button variant="outline" onClick={()=>void load()}><RefreshCw size={15}/> Refresh</Button>}/>
    {error&&<Alert tone="error">{error}</Alert>}
    <Alert tone="info"><ShieldCheck size={16}/> Reviewers cannot approve their own listing. Each photo preview is logged and delivered through a 60-second signed URL.</Alert>
    {loading?<div className="surface admin-case-empty">Loading listing queue…</div>:listings.length===0?<div className="surface admin-case-empty"><ShieldCheck size={25}/><strong>No listings to review</strong><p>New owner submissions will appear here.</p></div>:
      <div className="admin-case-list">{listings.map(item=><article className="surface admin-case listing-review-card" key={item.id}>
        <div className="admin-case-head"><div><span className="eyebrow">COPY {item.id.slice(0,8).toUpperCase()}</span><h2>{item.title?.title??"Catalogue entry pending"}</h2><p>{item.title?.authors?.join(", ")??"Author unavailable"} · Owner: {item.owner.display_name}</p></div><Badge tone={tone(item.listing_status)}>{item.listing_status.replaceAll("_"," ")}</Badge></div>
        <div className="admin-case-meta"><span>Submitted: {new Date(item.created_at).toLocaleString("en-IN")}</span><span>{item.locality}</span><span>Account: {item.owner.account_status}</span><span>Identity: {item.verification?.status??"unknown"} · 18+: {String(item.verification?.age_eligible??false)}</span></div>
        {item.title&&<dl className="listing-review-metadata"><div><dt>ISBN-13</dt><dd>{item.title.isbn13??"Not supplied"}</dd></div><div><dt>Edition</dt><dd>{item.title.edition??"Not supplied"}</dd></div><div><dt>Publisher</dt><dd>{item.title.publisher??"Not supplied"}</dd></div><div><dt>Catalogue moderation</dt><dd>{item.title.moderation_status}</dd></div><div><dt>Copy condition</dt><dd>{item.condition_summary.replaceAll("_"," ")}</dd></div><div><dt>Ownership declaration</dt><dd>{item.details?.ownership_declaration_type??"Missing"}</dd></div></dl>}
        {item.details?.existing_damage&&<Alert tone="warning">Disclosed damage: {item.details.existing_damage}</Alert>}
        {item.details?.original_price_evidence_note&&<p className="admin-case-reason">Original-price note: {item.details.original_price_evidence_note}</p>}{item.details?.has_original_price_evidence&&<Button size="sm" variant="outline" onClick={()=>void previewEvidence(item)}><Eye size={14}/> Audited purchase evidence preview</Button>}
        <div className="listing-review-photos">{item.images.map(image=><div className="listing-review-photo" key={image.id}><span>{image.is_cover?"Cover photo":"Copy photo"} · {image.moderation_status}</span><Button size="sm" variant="outline" disabled={busy===item.id} onClick={()=>void preview(item,image.id)}><Eye size={14}/> Audited preview</Button></div>)}</div>
        {item.pricing&&<div className="admin-case-meta">{([["3 days",item.pricing.rental_3d_paise],["7 days",item.pricing.rental_7d_paise],["15 days",item.pricing.rental_15d_paise],["30 days",item.pricing.rental_30d_paise]] as Array<[string,number|null]>).filter(x=>x[1]!=null).map(([label,value])=><span key={label}>{label}: {INR.format((value??0)/100)}</span>)}</div>}
        <details className="admin-audit-history"><summary>Moderation history ({item.history.length})</summary><ol>{item.history.map(event=><li key={event.id}><strong>{event.action.replaceAll("_"," ")}</strong><span>{new Date(event.created_at).toLocaleString("en-IN")} · {event.actor_user_id??"System"}</span>{event.reason&&<small>{event.reason}</small>}</li>)}</ol></details>
        <div className="admin-case-actions">
          {item.listing_status==="pending_review"&&<><Button size="sm" disabled={busy===item.id} onClick={()=>void decide(item,"approve")}>Approve</Button><Button size="sm" variant="danger" disabled={busy===item.id} onClick={()=>void decide(item,"reject")}>Reject</Button></>}
          {item.listing_status==="approved"&&<Button size="sm" variant="danger" disabled={busy===item.id} onClick={()=>void decide(item,"suspend")}>Suspend</Button>}
          {["approved","paused","pending_review"].includes(item.listing_status)&&<Button size="sm" variant="outline" disabled={busy===item.id} onClick={()=>void decide(item,"remove")}>Remove listing</Button>}
          {item.listing_status==="paused"&&<Button size="sm" disabled={busy===item.id} onClick={()=>void decide(item,"approve")}>Re-review and approve</Button>}
        </div>
      </article>)}</div>}
  </AdminLayout>;
}

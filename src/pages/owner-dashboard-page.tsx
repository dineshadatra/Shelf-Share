import { useCallback, useEffect, useMemo, useState } from "react";
import { ArrowRight, CalendarDays, CheckCircle2, Clock3, Edit3, PauseCircle, Plus, RefreshCw } from "lucide-react";
import { Link } from "react-router-dom";
import { MemberLayout } from "@/layouts/member-layout";
import { PageHeading } from "./page-helpers";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { supabase } from "@/lib/supabase";
import { useAuth } from "@/contexts/auth-context";

type Listing = {
  id:string; listing_status:string; is_available_for_rent:boolean; condition:string;
  title:string; authors:string[]; city:string; locality:string;
  images:Array<{url?:string;is_cover?:boolean;moderation_status?:string}>;
  pricing:{rental_3d_paise:number|null;rental_7d_paise:number|null;rental_15d_paise:number|null;rental_30d_paise:number|null}|null;
};
type Block={block_id:string;starts_at:string;ends_at:string;reason:string};
const INR=new Intl.NumberFormat("en-IN",{style:"currency",currency:"INR",maximumFractionDigits:2});

export default function OwnerDashboardPage(){
  const {verification}=useAuth();
  const [listings,setListings]=useState<Listing[]>([]);
  const [loading,setLoading]=useState(true);
  const [busy,setBusy]=useState("");
  const [error,setError]=useState("");
  const [selected,setSelected]=useState("");
  const [from,setFrom]=useState("");
  const [until,setUntil]=useState("");
  const [blockReason,setBlockReason]=useState("owner_unavailable");
  const [blocks,setBlocks]=useState<Block[]>([]);
  const [blockLoading,setBlockLoading]=useState(false);
  const verified=verification?.status==="verified"&&verification.age_eligible===true;

  const load=useCallback(async()=>{
    if(!supabase){setLoading(false);return;}
    setLoading(true);setError("");
    const {data,error:invokeError}=await supabase.functions.invoke("catalogue-api",{body:{action:"owner_listings"}});
    if(invokeError)setError(invokeError.message);
    else {
      const rows=(data?.listings??[]) as Listing[];
      setListings(rows);
      if(!selected&&rows[0])setSelected(rows[0].id);
    }
    setLoading(false);
  },[selected]);
  useEffect(()=>{void load();},[load]);

  const selectedListing=useMemo(()=>listings.find(x=>x.id===selected),[listings,selected]);
  const refreshBlocks=useCallback(async()=>{
    if(!supabase||!selected){setBlocks([]);return;}
    setBlockLoading(true);
    const {data,error:rpcError}=await supabase.rpc("get_my_book_availability_blocks",{p_book_copy_id:selected});
    if(rpcError)setError(rpcError.message);else setBlocks((data??[]) as Block[]);
    setBlockLoading(false);
  },[selected]);
  useEffect(()=>{void refreshBlocks();},[refreshBlocks]);

  const addBlock=async()=>{
    if(!supabase||!selected)return;
    if(!from||!until||until<=from){setError("Choose a valid future date range.");return;}
    setBusy(selected);setError("");
    const {error:rpcError}=await supabase.rpc("create_owner_availability_block",{
      p_book_copy_id:selected,p_start_at:from+"T00:00:00+05:30",p_end_at:until+"T23:59:59+05:30",p_reason:blockReason,
    });
    if(rpcError)setError(rpcError.message);else{setFrom("");setUntil("");await refreshBlocks();}
    setBusy("");
  };
  const removeBlock=async(blockId:string)=>{
    if(!supabase)return;
    setBusy(blockId);setError("");
    const {error:rpcError}=await supabase.rpc("delete_owner_availability_block",{p_block_id:blockId});
    if(rpcError)setError(rpcError.message);else await refreshBlocks();
    setBusy("");
  };
  const pause=async(item:Listing)=>{
    if(!supabase)return;
    if(!window.confirm("Pause this listing? It will disappear from discovery. To list it again, edit and resubmit it for moderation."))return;
    setBusy(item.id);setError("");
    const {error:rpcError}=await supabase.rpc("pause_my_book_listing",{p_book_copy_id:item.id});
    if(rpcError)setError(rpcError.message);else await load();
    setBusy("");
  };
  const statusTone=(status:string)=>status==="approved"?"green":status==="rejected"||status==="removed"?"rose":status==="pending_review"?"amber":"neutral";
  const count=(status:string)=>listings.filter(x=>x.listing_status===status).length;

  return <MemberLayout mode="owner" title="Owner overview">
    <PageHeading eyebrow="YOUR BOOKS, OUT IN THE WORLD" title="Your little lending library." description="Save drafts, follow review status, pause listings and manage dates unavailable for lending." action={<Button asChild><Link to="/owner/list-book">List a book <ArrowRight size={16}/></Link></Button>}/>
    {!verified&&<Alert tone="warning" title="Identity approval required">You can browse, but only active verified members can create and submit owner listings.</Alert>}
    {error&&<Alert tone="error">{error}</Alert>}
    <div className="stats-grid">
      <Card><CardContent><span className="stat-icon"><CheckCircle2 size={18}/></span><span className="stat-label">Approved</span><strong className="stat-value">{count("approved")}</strong><small>Visible when available</small></CardContent></Card>
      <Card><CardContent><span className="stat-icon"><Clock3 size={18}/></span><span className="stat-label">In review</span><strong className="stat-value">{count("pending_review")}</strong><small>Awaiting moderation</small></CardContent></Card>
      <Card><CardContent><span className="stat-icon"><Edit3 size={18}/></span><span className="stat-label">Drafts</span><strong className="stat-value">{count("draft")+count("rejected")}</strong><small>Private to you</small></CardContent></Card>
    </div>
    <section className="owner-listing-section">
      <div className="section-heading"><div><h2 className="serif">Your physical copies</h2><p>Each copy has a separate status and availability calendar.</p></div><Button variant="outline" size="sm" onClick={()=>void load()}><RefreshCw size={14}/> Refresh</Button></div>
      {loading?<div className="surface admin-case-empty">Loading your listings…</div>:listings.length===0?<Card><CardContent><div className="admin-case-empty"><Edit3 size={24}/><strong>Your shelf is empty</strong><p>Create a draft listing for your first physical copy.</p><Button asChild><Link to="/owner/list-book">Add a book</Link></Button></div></CardContent></Card>:
        <div className="owner-listings-grid">{listings.map(item=><article className="surface owner-listing-card" key={item.id}>
          <div className="owner-listing-image">{item.images?.find(x=>x.is_cover)?.url&&<img src={item.images.find(x=>x.is_cover)?.url} alt={item.title+" physical copy"}/>}</div>
          <div className="owner-listing-info"><div className="owner-listing-title"><div><h3>{item.title}</h3><p>{item.authors?.join(", ")}</p></div><Badge tone={statusTone(item.listing_status)}>{item.listing_status.replaceAll("_"," ")}</Badge></div>
            <p className="owner-listing-meta">{item.city} · {item.locality} · {item.condition.replaceAll("_"," ")}</p>
            <div className="owner-listing-prices">{item.pricing?.rental_3d_paise!=null&&<span>3 days {INR.format(item.pricing.rental_3d_paise/100)}</span>}{item.pricing?.rental_7d_paise!=null&&<span>7 days {INR.format(item.pricing.rental_7d_paise/100)}</span>}</div>
            <div className="owner-listing-actions">
              {["draft","rejected","paused"].includes(item.listing_status)&&<Button size="sm" variant="outline" asChild><Link to={"/owner/list-book?id="+item.id}><Edit3 size={14}/> Edit & resubmit</Link></Button>}
              {item.listing_status==="approved"&&<Button size="sm" variant="outline" disabled={busy===item.id} onClick={()=>void pause(item)}><PauseCircle size={14}/> Pause listing</Button>}
              <Button size="sm" variant="ghost" onClick={()=>setSelected(item.id)}><CalendarDays size={14}/> Availability</Button>
            </div>
          </div>
        </article>)}</div>}
    </section>
    {selectedListing&&<section className="availability-manager surface">
      <div className="availability-manager-heading"><div><span className="eyebrow">OWNER CALENDAR</span><h2>{selectedListing.title}</h2><p>Block dates when this copy is unavailable for personal use or maintenance. Conflicting active bookings cannot be blocked.</p></div><Badge tone={selectedListing.listing_status==="approved"?"green":"neutral"}>{selectedListing.listing_status.replaceAll("_"," ")}</Badge></div>
      {["approved","draft","pending_review"].includes(selectedListing.listing_status)?<>
        <div className="availability-create-form"><Input label="Unavailable from" type="date" name="block-from" value={from} onChange={e=>setFrom(e.target.value)}/><Input label="Unavailable until" type="date" name="block-until" value={until} onChange={e=>setUntil(e.target.value)}/>
          <label className="ss-field"><span className="ss-label">Reason</span><select className="ss-input" value={blockReason} onChange={e=>setBlockReason(e.target.value)}><option value="owner_unavailable">Personal use / unavailable</option><option value="maintenance">Maintenance</option></select></label>
          <Button disabled={busy===selected} onClick={()=>void addBlock()}><Plus size={14}/> Add block</Button>
        </div>
      </>:<Alert tone="info">Availability blocks can be managed when this listing is approved or under review.</Alert>}
      <div className="availability-block-list"><h3>Upcoming blocks</h3>{blockLoading?<p>Loading calendar…</p>:blocks.length===0?<p>No upcoming owner blocks.</p>:blocks.map(block=><div key={block.block_id}><span><strong>{new Date(block.starts_at).toLocaleDateString("en-IN")} – {new Date(block.ends_at).toLocaleDateString("en-IN")}</strong><small>{block.reason.replaceAll("_"," ")}</small></span><Button size="sm" variant="ghost" disabled={busy===block.block_id} onClick={()=>void removeBlock(block.block_id)}>Remove</Button></div>)}</div>
    </section>}
    <div className="owner-workspace-note"><CalendarDays size={16}/><span>Public availability is calculated against owner blocks and confirmed reservations on the server. A browser calendar is not the final booking lock.</span></div>
  </MemberLayout>;
}

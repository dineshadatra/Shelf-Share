import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { ArrowLeft, CalendarDays, CheckCircle2, Heart, MapPin, ShieldCheck } from "lucide-react";
import { PublicLayout } from "@/layouts/public-layout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Alert } from "@/components/ui/alert";
import { EmptyState } from "@/components/ui/empty-state";
import { supabase } from "@/lib/supabase";
import { useAuth } from "@/contexts/auth-context";

type Detail = {
  copy:{id:string;city_id:string;locality_id:string;condition:string;description:string;existing_damage:string};
  title:{id:string;isbn13:string|null;title:string;subtitle:string|null;edition:string|null;authors:string[];publisher:string|null;language_code:string|null;publication_year:number|null;description:string|null;cover_image_url:string|null};
  locality:{id:string;name:string;map_latitude:number|null;map_longitude:number|null}|null;
  pricing:{rental_3d_paise:number|null;rental_7d_paise:number|null;rental_15d_paise:number|null;rental_30d_paise:number|null;custom_daily_paise:number|null;min_custom_days:number|null;max_custom_days:number|null}|null;
  owner:{display_name:string;verified:boolean};
  images:Array<{url:string;alt_text:string|null;is_cover:boolean}>;
};
const INR=new Intl.NumberFormat("en-IN",{style:"currency",currency:"INR",maximumFractionDigits:2});
const indiaDate=(value:string,end=false)=>value?value+(end?"T23:59:59+05:30":"T00:00:00+05:30"):"";

export default function BookDetailsPage(){
  const {id}=useParams();
  const {user}=useAuth();
  const [detail,setDetail]=useState<Detail|null>(null);
  const [loading,setLoading]=useState(true);
  const [error,setError]=useState("");
  const [from,setFrom]=useState("");
  const [until,setUntil]=useState("");
  const [duration,setDuration]=useState(7);
  const [availability,setAvailability]=useState<"unknown"|"available"|"unavailable">("unknown");
  const [busy,setBusy]=useState(false);
  const [notice,setNotice]=useState("");
  const [wishlisted,setWishlisted]=useState(false);
  useEffect(()=>{
    if(!supabase||!id){setLoading(false);return;}
    supabase.functions.invoke("catalogue-api",{body:{action:"listing_detail",copy_id:id}})
      .then(({data,error:invokeError})=>{if(invokeError)setError(invokeError.message);else setDetail(data as Detail);})
      .finally(()=>setLoading(false));
  },[id]);
  const price=useMemo(()=>{
    const p=detail?.pricing;
    if(!p)return null;
    if(duration===3)return p.rental_3d_paise;
    if(duration===7)return p.rental_7d_paise;
    if(duration===15)return p.rental_15d_paise;
    if(duration===30)return p.rental_30d_paise;
    if(p.custom_daily_paise!=null)return p.custom_daily_paise*duration;
    return null;
  },[detail,duration]);
  const checkAvailability=async()=>{
    if(!supabase||!detail)return;
    if(!from||!until||until<from){setError("Choose a valid start and end date.");return;}
    setBusy(true);setError("");setAvailability("unknown");
    const {data,error:invokeError}=await supabase.functions.invoke("catalogue-api",{body:{
      action:"check_availability",copy_id:detail.copy.id,available_from:indiaDate(from),available_until:indiaDate(until,true),
    }});
    if(invokeError)setError(invokeError.message);
    else setAvailability(data?.available?"available":"unavailable");
    setBusy(false);
  };
  const joinWaitlist=async()=>{
    if(!supabase||!detail)return;
    if(!user){setNotice("Sign in and complete verification before joining a waitlist.");return;}
    setBusy(true);setError("");setNotice("");
    const {error:rpcError}=await supabase.rpc("join_book_waitlist",{
      p_book_title_id:detail.title.id,p_city_id:detail.copy.city_id,p_locality_id:detail.copy.locality_id,
      p_start_at:from?indiaDate(from):null,p_end_at:until?indiaDate(until,true):null,p_duration_days:duration,
    });
    if(rpcError)setError(rpcError.message);else setNotice("You have joined the waitlist for this edition and city.");
    setBusy(false);
  };
  const addWishlist=async()=>{
    if(!supabase||!detail)return;
    if(!user){setNotice("Sign in to save this book to your wishlist.");return;}
    setBusy(true);
    const {data,error:rpcError}=await supabase.rpc("toggle_book_wishlist",{p_book_title_id:detail.title.id});
    if(rpcError)setError(rpcError.message);else setWishlisted(data===true);
    setBusy(false);
  };

  if(loading)return <PublicLayout><main className="page-container public-page"><p>Loading book details…</p></main></PublicLayout>;
  if(error&&!detail)return <PublicLayout><main className="page-container public-page"><Link to="/discover" className="back-link"><ArrowLeft size={16}/> Back to discover</Link><EmptyState title="This copy is unavailable" description={error}/></main></PublicLayout>;
  if(!detail)return <PublicLayout><main className="page-container public-page"><Link to="/discover" className="back-link"><ArrowLeft size={16}/> Back to discover</Link><EmptyState title="This book is no longer available" description="It may have been paused, rented, or removed."/></main></PublicLayout>;
  return <PublicLayout><main className="page-container details-page">
    <Link to="/discover" className="back-link"><ArrowLeft size={16}/> Back to discover</Link>
    {error&&<Alert tone="error">{error}</Alert>}{notice&&<Alert tone="success">{notice}</Alert>}
    <div className="book-detail-grid">
      <div className="book-detail-cover live-detail-gallery">
        {detail.images.map((image,index)=><img key={image.url} src={image.url} alt={image.alt_text??detail.title.title+" physical copy photo "+(index+1)}/>)}
        {detail.images.length===0&&detail.title.cover_image_url&&<img src={detail.title.cover_image_url} alt={detail.title.title+" cover"}/>}
      </div>
      <div className="book-detail-copy">
        <div className="live-detail-badges"><Badge tone="green">{detail.copy.condition.replaceAll("_"," ")}</Badge><Badge tone="blue"><ShieldCheck size={12}/> Verified owner</Badge></div>
        <h1 className="serif">{detail.title.title}</h1>
        <p className="detail-author">by {detail.title.authors.join(", ")}</p>
        <p className="detail-blurb">{detail.title.description??detail.copy.description}</p>
        <dl className="detail-book-meta">
          {detail.title.edition&&<div><dt>Edition</dt><dd>{detail.title.edition}</dd></div>}
          {detail.title.publisher&&<div><dt>Publisher</dt><dd>{detail.title.publisher}</dd></div>}
          {detail.title.publication_year&&<div><dt>Published</dt><dd>{detail.title.publication_year}</dd></div>}
          {detail.title.language_code&&<div><dt>Language</dt><dd>{detail.title.language_code}</dd></div>}
          {detail.title.isbn13&&<div><dt>ISBN-13</dt><dd>{detail.title.isbn13}</dd></div>}
        </dl>
        <div className="detail-owner surface"><span className="avatar initials">{detail.owner.display_name.slice(0,1)}</span><div><strong>{detail.owner.display_name}</strong><p>Identity-verified ShelfShare owner</p></div><Badge tone="green">Verified</Badge></div>
        <div className="detail-location"><MapPin size={17}/><div><strong>{detail.locality?.name??"Locality unavailable"}</strong><p>Public locality only · exact owner address is not shown</p></div>
          {detail.locality?.map_latitude!=null&&detail.locality.map_longitude!=null&&<a href={"https://www.openstreetmap.org/?mlat="+detail.locality.map_latitude+"&mlon="+detail.locality.map_longitude+"#map=15/"+detail.locality.map_latitude+"/"+detail.locality.map_longitude} target="_blank" rel="noreferrer">Map</a>}
        </div>
        {detail.copy.existing_damage&&<Alert tone="warning">Existing wear disclosed by owner: {detail.copy.existing_damage}</Alert>}
        <div className="detail-price-panel">
          <label className="ss-field"><span className="ss-label">Rental duration</span><select className="ss-input" value={duration} onChange={e=>setDuration(Number(e.target.value))}><option value={3}>3 days</option><option value={7}>7 days</option><option value={15}>15 days</option><option value={30}>30 days</option></select></label>
          <strong>{price!=null?INR.format(price/100):"Price not configured"}</strong>
          <span>Selected rental duration · deposit not enabled</span>
        </div>
        <section className="detail-availability">
          <h3><CalendarDays size={17}/> Check dates</h3>
          <div className="form-two-col"><Input label="From" type="date" name="availability-from" value={from} onChange={e=>{setFrom(e.target.value);setAvailability("unknown");}}/><Input label="Until" type="date" name="availability-until" value={until} onChange={e=>{setUntil(e.target.value);setAvailability("unknown");}}/></div>
          <Button variant="outline" block disabled={busy||!from||!until} onClick={()=>void checkAvailability()}>{busy?"Checking…":"Check availability"}</Button>
          {availability==="available"&&<Alert tone="success"><CheckCircle2 size={15}/> No conflicting reservation or owner block was found for those dates. A booking has not been created.</Alert>}
          {availability==="unavailable"&&<Alert tone="warning">This copy is unavailable for the selected dates. Join the waitlist to be notified when another copy is available.</Alert>}
        </section>
        <div className="detail-actions"><Button block onClick={()=>void joinWaitlist()} disabled={busy}>Join waitlist</Button><Button variant="outline" onClick={()=>void addWishlist()} disabled={busy}><Heart size={16} fill={wishlisted?"currentColor":"none"}/>{wishlisted?"Saved":"Wishlist"}</Button></div>
        <p className="detail-safety"><ShieldCheck size={16}/> Coordinate handover only at approved public meeting points.</p>
        <Alert tone="info">Date checks are advisory and do not reserve a copy. Booking confirmation and payments are separate trusted workflows.</Alert>
      </div>
    </div>
  </main></PublicLayout>;
}

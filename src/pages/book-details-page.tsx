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
type HandoverLocation = { id:string; name:string; public_address:string };
const INR=new Intl.NumberFormat("en-IN",{style:"currency",currency:"INR",maximumFractionDigits:2});
const indiaDate=(value:string,end=false)=>value?value+(end?"T23:59:59+05:30":"T00:00:00+05:30"):"";
const addDays=(date:string,days:number)=>{
  const [y,m,d]=date.split("-").map(Number);
  const next=new Date(Date.UTC(y,m-1,d+days));
  return next.toISOString().slice(0,10);
};
const calendarStart=(date:string)=>date+"T00:00:00+05:30";

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
  const [locations,setLocations]=useState<HandoverLocation[]>([]);
  const [locationId,setLocationId]=useState("");

  useEffect(()=>{
    let active=true;
    const client=supabase;
    if(!client||!id){setLoading(false);return;}
    client.functions.invoke("catalogue-api",{body:{action:"listing_detail",copy_id:id}})
      .then(async({data,error:invokeError})=>{
        if(!active)return;
        if(invokeError){setError(invokeError.message);return;}
        setDetail(data as Detail);
        const city=(data as Detail)?.copy?.city_id;
        if(city){
          const {data:points,error:pointError}=await client.from("handover_locations")
            .select("id,name,public_address").eq("city_id",city).eq("status","active").order("name");
          if(active){
            if(pointError)setError("Unable to load approved public handover points.");
            else {
              const next=(points??[]) as HandoverLocation[];
              setLocations(next);
              if(next.length)setLocationId(next[0].id);
            }
          }
        }
      })
      .finally(()=>{if(active)setLoading(false);});
    return ()=>{active=false;};
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

  const requestBooking=async()=>{
    if(!supabase||!detail)return;
    if(!user){setNotice("Sign in and complete identity verification before requesting a rental.");return;}
    if(!from||!until||until<from){setError("Choose valid rental dates.");return;}
    if(!locationId){setError("Choose an approved public handover point.");return;}
    const days=Math.round((Date.parse(until+"T00:00:00Z")-Date.parse(from+"T00:00:00Z"))/86400000)+1;
    if(days!==duration){setError("The selected dates must match the chosen rental duration.");return;}
    setBusy(true);setError("");setNotice("");
    const {data:policy,error:policyError}=await supabase.functions.invoke("marketplace-api",{body:{action:"booking_configuration"}});
    if(policyError||!policy?.rental_duration_mode){
      setError(policyError?.message??"Booking is not enabled yet. Approved timing policies are still required.");
      setBusy(false);return;
    }
    const startAt=calendarStart(from);
    const endAt=calendarStart(addDays(until,1));
    const {error:bookingError}=await supabase.functions.invoke("marketplace-api",{body:{
      action:"request_booking",copy_id:detail.copy.id,handover_location_id:locationId,
      start_at:startAt,end_at:endAt,duration_days:duration,
      idempotency_key:"ss-booking-"+crypto.randomUUID(),
    }});
    if(bookingError)setError(bookingError.message);
    else {
      setNotice("Your request has been sent to the owner. No payment has been started. You can follow the owner’s decision in Rental history.");
      setAvailability("unknown");
    }
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
          <span>Rental fee · 10% commission is withheld from Owner proceeds, not charged as an extra Reader fee</span>
        </div>
        <section className="detail-availability">
          <h3><CalendarDays size={17}/> Request this copy</h3>
          <div className="form-two-col"><Input label="From" type="date" name="availability-from" min={new Date().toISOString().slice(0,10)} value={from} onChange={e=>{setFrom(e.target.value);setUntil(e.target.value?addDays(e.target.value,duration-1):"");setAvailability("unknown");}}/><Input label="Until (inclusive)" type="date" name="availability-until" min={from||new Date().toISOString().slice(0,10)} value={until} onChange={e=>{setUntil(e.target.value);setAvailability("unknown");}}/></div>
          <label className="ss-field"><span className="ss-label">Approved public handover point</span><select className="ss-input" value={locationId} onChange={e=>setLocationId(e.target.value)}><option value="">Choose a public meeting point</option>{locations.map(point=><option key={point.id} value={point.id}>{point.name} — {point.public_address}</option>)}</select></label>
          {locations.length===0&&<Alert tone="warning">No approved public handover point is available for this listing’s city yet.</Alert>}
          <Button variant="outline" block disabled={busy||!from||!until} onClick={()=>void checkAvailability()}>{busy?"Checking…":"Check availability"}</Button>
          {availability==="available"&&<Alert tone="success"><CheckCircle2 size={15}/> No conflicting reservation or owner block was found. This check does not reserve the copy.</Alert>}
          {availability==="unavailable"&&<Alert tone="warning">This copy is unavailable for the selected dates. Join the waitlist to be notified when another copy is available.</Alert>}
        </section>
        <div className="detail-actions">
          <Button block disabled={busy||!price||locations.length===0||!from||!until||!locationId} onClick={()=>void requestBooking()}>{busy?"Submitting…":"Request to rent"}</Button>
          <Button variant="outline" onClick={()=>void addWishlist()} disabled={busy}><Heart size={16} fill={wishlisted?"currentColor":"none"}/>{wishlisted?"Saved":"Wishlist"}</Button>
          <Button variant="outline" onClick={()=>void joinWaitlist()} disabled={busy}>Join waitlist</Button>
        </div>
        <p className="detail-safety"><ShieldCheck size={16}/> Handover is limited to approved public meeting points. Residential addresses are never shown.</p>
        <Alert tone="info">The owner must accept your request first. Payment is only offered after both parties accept the current rental agreement and the server validates pricing, tax, policy and availability.</Alert>
      </div>
    </div>
  </main></PublicLayout>;
}

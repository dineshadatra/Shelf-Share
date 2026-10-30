import { useCallback, useEffect, useState } from "react";
import { CalendarClock, Heart, Trash2 } from "lucide-react";
import { Link } from "react-router-dom";
import { MemberLayout } from "@/layouts/member-layout";
import { PageHeading } from "./page-helpers";
import { EmptyState } from "@/components/ui/empty-state";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Alert } from "@/components/ui/alert";
import { supabase } from "@/lib/supabase";

type SavedTitle={id:string;title:string;authors:string[];cover_image_url:string|null};
type Waitlist={id:string;book_title_id:string;title:string;authors:string[];city:string;locality:string|null;status:string;created_at:string;requested_start_at:string|null;requested_end_at:string|null};

export default function WishlistPage(){
  const [titles,setTitles]=useState<SavedTitle[]>([]);
  const [waitlist,setWaitlist]=useState<Waitlist[]>([]);
  const [tab,setTab]=useState<"saved"|"waitlist">("saved");
  const [loading,setLoading]=useState(true);
  const [error,setError]=useState("");
  const [busy,setBusy]=useState("");
  const load=useCallback(async()=>{
    if(!supabase){setLoading(false);return;}
    setLoading(true);setError("");
    const {data:wishlist,error:wishlistError}=await supabase.from("wishlists").select("id").eq("name","My wishlist").maybeSingle();
    if(wishlistError)setError(wishlistError.message);
    let savedTitles:SavedTitle[]=[];
    if(wishlist?.id){
      const {data:items,error:itemError}=await supabase.from("wishlist_items").select("book_title_id").eq("wishlist_id",wishlist.id);
      if(itemError)setError(itemError.message);
      const ids=(items??[]).map(x=>x.book_title_id);
      if(ids.length){
        const {data:rows,error:titleError}=await supabase.from("book_titles").select("id,title,authors,cover_image_url").in("id",ids).eq("moderation_status","approved");
        if(titleError)setError(titleError.message);savedTitles=(rows??[]) as SavedTitle[];
      }
    }
    setTitles(savedTitles);
    const {data:waitData,error:waitError}=await supabase.functions.invoke("catalogue-api",{body:{action:"my_waitlist"}});
    if(waitError)setError(waitError.message);else setWaitlist((waitData?.entries??[]) as Waitlist[]);
    setLoading(false);
  },[]);
  useEffect(()=>{void load();},[load]);
  const removeSaved=async(titleId:string)=>{
    if(!supabase)return;
    setBusy(titleId);
    const {error:rpcError}=await supabase.rpc("toggle_book_wishlist",{p_book_title_id:titleId});
    if(rpcError)setError(rpcError.message);else setTitles(old=>old.filter(x=>x.id!==titleId));
    setBusy("");
  };
  const removeWaitlist=async(id:string)=>{
    if(!supabase)return;
    setBusy(id);
    const {error:rpcError}=await supabase.rpc("leave_book_waitlist",{p_entry_id:id});
    if(rpcError)setError(rpcError.message);else setWaitlist(old=>old.filter(x=>x.id!==id));
    setBusy("");
  };
  return <MemberLayout title="Wishlist">
    <PageHeading eyebrow="YOUR NEXT READS" title="Keep a little list." description="Your saved editions and the rental waitlists you have joined."/>
    {error&&<Alert tone="error">{error}</Alert>}
    <div className="ss-tabs-list" role="tablist"><button type="button" className={"ss-tabs-trigger "+(tab==="saved"?"active":"")} onClick={()=>setTab("saved")} role="tab" aria-selected={tab==="saved"}><Heart size={14}/> Saved books</button><button type="button" className={"ss-tabs-trigger "+(tab==="waitlist"?"active":"")} onClick={()=>setTab("waitlist")} role="tab" aria-selected={tab==="waitlist"}><CalendarClock size={14}/> Waitlists</button></div>
    {loading?<div className="surface admin-case-empty">Loading your list…</div>:tab==="saved"?titles.length===0?<EmptyState icon={<Heart size={28}/>} title="Your wishlist is waiting for its first book" description="Browse the neighbourhood shelves and save a title to revisit it later." action={<Button asChild><Link to="/discover">Explore books</Link></Button>}/>:<div className="wishlist-live-grid">{titles.map(item=><article className="surface wishlist-live-card" key={item.id}><div className="wishlist-live-cover">{item.cover_image_url&&<img src={item.cover_image_url} alt={item.title+" cover"}/>}</div><div className="wishlist-live-copy"><h3>{item.title}</h3><p>{item.authors?.join(", ")}</p><Link to={"/discover?query="+encodeURIComponent(item.title)}>Find available copies</Link><Button size="sm" variant="ghost" disabled={busy===item.id} onClick={()=>void removeSaved(item.id)}><Trash2 size={14}/> Remove</Button></div></article>)}</div>:waitlist.length===0?<EmptyState icon={<CalendarClock size={28}/>} title="No active waitlists" description="When a title is unavailable in your city, join its waitlist from the book detail page." action={<Button asChild><Link to="/discover">Browse books</Link></Button>}/>:<div className="waitlist-cards">{waitlist.map(item=><article className="surface waitlist-card" key={item.id}><div><Badge tone={item.status==="notified"?"green":"neutral"}>{item.status}</Badge><h3>{item.title}</h3><p>{item.authors?.join(", ")}</p><small>{item.locality?item.locality+", ":""}{item.city}</small>{item.requested_start_at&&item.requested_end_at&&<small>Requested: {new Date(item.requested_start_at).toLocaleDateString("en-IN")} – {new Date(item.requested_end_at).toLocaleDateString("en-IN")}</small>}</div><Button size="sm" variant="outline" disabled={busy===item.id} onClick={()=>void removeWaitlist(item.id)}><Trash2 size={14}/> Leave waitlist</Button></article>)}</div>}
  </MemberLayout>;
}

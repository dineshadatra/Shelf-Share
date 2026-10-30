import { useCallback, useEffect, useState } from "react";
import { Layers3, RefreshCw, ShieldCheck } from "lucide-react";
import { AdminLayout } from "@/layouts/admin-layout";
import { PageHeading } from "./page-helpers";
import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { supabase } from "@/lib/supabase";

type Bundle={
  id:string;owner_id:string;name:string;description:string|null;status:string;created_at:string;city:string;
  owner:{display_name:string;account_status:string};
  items:Array<{copy_id:string;status:string;available:boolean;title:{title:string;authors:string[]}|null}>;
  history:Array<{id:number;action:string;from_status:string|null;to_status:string;reason:string|null;created_at:string}>;
};
export default function AdminBundleQueuePage(){
  const [bundles,setBundles]=useState<Bundle[]>([]);
  const [loading,setLoading]=useState(true);
  const [busy,setBusy]=useState("");
  const [error,setError]=useState("");
  const load=useCallback(async()=>{
    if(!supabase){setLoading(false);return;}
    setLoading(true);setError("");
    const {data,error:invokeError}=await supabase.functions.invoke("catalogue-api",{body:{action:"admin_bundle_queue"}});
    if(invokeError)setError(invokeError.message);else setBundles((data?.bundles??[]) as Bundle[]);
    setLoading(false);
  },[]);
  useEffect(()=>{void load();},[load]);
  const decide=async(bundle:Bundle,decision:"approve"|"reject"|"suspend"|"remove")=>{
    if(!supabase)return;
    const reason=window.prompt("Reason for "+decision+" this bundle","");
    if(reason===null||reason.trim().length<5)return;
    setBusy(bundle.id);setError("");
    const {error:invokeError}=await supabase.functions.invoke("catalogue-api",{body:{
      action:"moderate_bundle",bundle_id:bundle.id,decision,reason,
    }});
    if(invokeError)setError(invokeError.message);
    await load();setBusy("");
  };
  const tone=(status:string)=>status==="approved"?"green":status==="pending_review"?"amber":status==="rejected"||status==="removed"?"rose":"neutral";
  return <AdminLayout>
    <PageHeading eyebrow="MARKETPLACE TRUST" title="Book bundle moderation" description="Review owner-curated sets. Each bundle must contain two to five approved, available copies from one owner and one city." action={<Button variant="outline" onClick={()=>void load()}><RefreshCw size={15}/> Refresh</Button>}/>
    {error&&<Alert tone="error">{error}</Alert>}
    <Alert tone="info"><ShieldCheck size={16}/> Bundle owners cannot approve their own bundles. Decisions require a reason and are recorded in immutable moderation history.</Alert>
    {loading?<div className="surface admin-case-empty">Loading bundles…</div>:bundles.length===0?<div className="surface admin-case-empty"><Layers3 size={25}/><strong>No bundles to review</strong><p>Owner submissions will appear here.</p></div>:
      <div className="admin-case-list">{bundles.map(bundle=><article className="surface admin-case" key={bundle.id}>
        <div className="admin-case-head"><div><span className="eyebrow">BUNDLE {bundle.id.slice(0,8).toUpperCase()}</span><h2>{bundle.name}</h2><p>{bundle.city} · Owner: {bundle.owner.display_name}</p></div><Badge tone={tone(bundle.status)}>{bundle.status.replaceAll("_"," ")}</Badge></div>
        {bundle.description&&<p className="admin-case-reason">{bundle.description}</p>}
        <div className="bundle-review-items">{bundle.items.map(item=><div key={item.copy_id}><strong>{item.title?.title??"Catalogue entry missing"}</strong><small>{item.title?.authors?.join(", ")}</small><Badge tone={item.status==="approved"&&item.available?"green":"amber"}>{item.status.replaceAll("_"," ")}{item.available?" · available":""}</Badge></div>)}</div>
        <div className="admin-case-meta"><span>Owner account: {bundle.owner.account_status}</span><span>Created: {new Date(bundle.created_at).toLocaleString("en-IN")}</span></div>
        <details className="admin-audit-history"><summary>Bundle decision history ({bundle.history.length})</summary><ol>{bundle.history.map(item=><li key={item.id}><strong>{item.action}</strong><span>{new Date(item.created_at).toLocaleString("en-IN")}</span>{item.reason&&<small>{item.reason}</small>}</li>)}</ol></details>
        <div className="admin-case-actions">
          {bundle.status==="pending_review"&&<><Button size="sm" disabled={busy===bundle.id} onClick={()=>void decide(bundle,"approve")}>Approve</Button><Button size="sm" variant="danger" disabled={busy===bundle.id} onClick={()=>void decide(bundle,"reject")}>Reject</Button></>}
          {bundle.status==="approved"&&<Button size="sm" variant="danger" disabled={busy===bundle.id} onClick={()=>void decide(bundle,"suspend")}>Suspend</Button>}
          {["approved","paused","pending_review"].includes(bundle.status)&&<Button size="sm" variant="outline" disabled={busy===bundle.id} onClick={()=>void decide(bundle,"remove")}>Remove</Button>}
        </div>
      </article>)}</div>}
  </AdminLayout>;
}

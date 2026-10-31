import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const state={supabase:null,modules:[],permissions:new Set(),currentModule:"dashboard",page:0,pageSize:25,total:0,rows:[],pendingReason:null};
const el=id=>document.getElementById(id);
const esc=value=>String(value??"").replace(/[&<>"']/gu,ch=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[ch]));
const fmt=value=>{
 if(value===null||value===undefined||value==="")return "—";
 if(typeof value==="object")return JSON.stringify(value);
 if(typeof value==="boolean")return value?"Yes":"No";
 if(typeof value==="string" && /^\d{4}-\d\d-\d\dT/u.test(value))return new Date(value).toLocaleString();
 return String(value);
};
async function invoke(action,payload={}){
 const {data,error}=await state.supabase.functions.invoke("admin-portal",{body:Object.assign({action},payload)});
 if(error)throw error;
 if(data?.error)throw new Error(data.error);
 return data;
}
function authMessage(message,isError=false){el("authMessage").textContent=message;el("authMessage").style.color=isError?"#a43d34":"#527078";}
async function sendOtp(){
 try{
  const url=el("projectUrl").value.trim().replace(/\/+$/u,"");
  const key=el("anonKey").value.trim();
  const phone=el("phone").value.trim();
  if(!/^https:\/\/[a-z0-9.-]+\.supabase\.co$/iu.test(url)||!key||!/^\+[1-9]\d{7,14}$/u.test(phone))throw new Error("Enter a valid project URL, public anon key and international-format staff phone.");
  state.supabase=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:true}});
  const {error}=await state.supabase.auth.signInWithOtp({phone,options:{shouldCreateUser:false}});
  if(error)throw error;
  el("otpWrap").hidden=false;el("verifyOtp").hidden=false;el("sendOtp").disabled=true;
  authMessage("A one-time code was sent to the staff phone number.");
 }catch(error){authMessage(error.message||"Unable to send code.",true);}
}
async function verifyOtp(){
 try{
  const {error}=await state.supabase.auth.verifyOtp({phone:el("phone").value.trim(),token:el("otp").value.trim(),type:"sms"});
  if(error)throw error;
  await bootstrap();
 }catch(error){authMessage(error.message||"Sign-in failed.",true);}
}
async function bootstrap(){
 const data=await invoke("bootstrap");
 state.modules=data.modules||[];state.permissions=new Set(data.permissions||[]);
 if(!state.modules.length)throw new Error("Your account has no admin portal permissions. Contact a super-admin.");
 el("auth").hidden=true;el("app").hidden=false;
 el("staffIdentity").textContent="Staff · "+String(data.user.id).slice(0,8)+"…";
 el("roleBadges").innerHTML=(data.roles||[]).map(role=>"<span>"+esc(role.replaceAll("_"," "))+"</span>").join("");
 renderNavigation();await selectModule("dashboard");
}
function renderNavigation(){
 el("navigation").innerHTML=state.modules.map(module=>'<button type="button" data-module="'+esc(module.key)+'" class="'+(module.key===state.currentModule?"active":"")+'">'+esc(module.label)+"</button>").join("");
 el("navigation").querySelectorAll("button").forEach(button=>button.addEventListener("click",()=>selectModule(button.dataset.module)));
}
async function selectModule(key){
 const module=state.modules.find(item=>item.key===key);if(!module)return;
 state.currentModule=key;state.page=0;el("pageTitle").textContent=module.label;renderNavigation();
 if(key==="dashboard")await renderDashboard();else await loadModule();
}
async function renderDashboard(){
 el("content").innerHTML='<div class="notice"><strong>Operational snapshot</strong>Counts are permission-filtered and are not financial statements. Payment counts do not indicate collected or settled money.</div><div id="dashboardCards" class="cards"><div class="card">Loading dashboard…</div></div><div class="section-heading"><div><h2>Your access</h2><p>Access depends on the role permissions currently assigned to your account.</p></div></div><div class="card"><div class="permission-list">'+[...state.permissions].sort().map(item=>"<span>"+esc(item)+"</span>").join("")+"</div></div>';
 try{
  const data=await invoke("dashboard");
  const labels={users:"User accounts",physicalCopies:"Physical copies",booksAwaitingModeration:"Books awaiting moderation",verificationsAwaitingReview:"Verifications awaiting review",activeBookings:"Active bookings",openDisputes:"Open disputes",openGrievances:"Open grievances",openRiskAlerts:"Open risk alerts",paymentRecords:"Payment records"};
  el("dashboardCards").innerHTML=Object.entries(data.cards||{}).filter(([,value])=>typeof value==="number").map(([key,value])=>'<div class="card"><div class="metric-label">'+esc(labels[key]||key)+'</div><div class="metric-value">'+Number(value).toLocaleString()+"</div></div>").join("")||'<div class="card">No summary permissions available.</div>';
 }catch(error){el("dashboardCards").innerHTML='<div class="card">'+esc(error.message)+"</div>";}
}
function toolbarMarkup(module){
 const hasStatus=["users","verification","catalogue","copies","categories","cities","localities","handover-locations","valuation","bookings","payments","deposits","payouts","refunds","disputes","damage-claims","late-fees","community","reviews","referrals","risk-alerts","support","grievances","privacy-requests","legal-documents","audit-logs","reconciliation","approvals"].includes(module.key);
 const hasCity=["copies","localities","handover-locations","bookings","analytics"].includes(module.key);
 const hasDates=["users","verification","catalogue","copies","handover-locations","pricing","valuation","bookings","payments","deposits","commission","payouts","refunds","disputes","damage-claims","late-fees","community","reviews","referrals","risk-alerts","support","grievances","privacy-requests","legal-documents","audit-logs","reconciliation","analytics","approvals"].includes(module.key);
 return '<div class="toolbar"><div class="field"><label>Search</label><input id="search" placeholder="Search this module"></div>'+
 (hasStatus?'<div class="field"><label>Status (exact)</label><input id="statusFilter" placeholder="Any status"></div>':"")+
 (hasCity?'<div class="field"><label>City ID</label><input id="cityFilter" placeholder="Optional city UUID"></div>':"")+
 (hasDates?'<div class="field"><label>From date</label><input id="fromFilter" type="date"></div><div class="field"><label>To date</label><input id="toFilter" type="date"></div>':"")+
 '<button id="applyFilters" class="primary">Apply</button>'+
 (module.exportable?'<button id="exportCsv" class="secondary">Export CSV</button>':"")+"</div>";
}
async function ensureAal2(){
 const {data,error}=await state.supabase.auth.mfa.getAuthenticatorAssuranceLevel();
 if(error)throw error;
 if(data.currentLevel==="aal2")return;
 const {data:factors,error:factorError}=await state.supabase.auth.mfa.listFactors();
 if(factorError)throw factorError;
 const factor=(factors.totp||[]).find(item=>item.status==="verified");
 if(!factor)throw new Error("This action requires a verified authenticator (MFA). Enrol TOTP for your staff account first.");
 const code=prompt("Enter the current code from your authenticator app:");
 if(!code)throw new Error("MFA verification was cancelled.");
 const {data:challenge,error:challengeError}=await state.supabase.auth.mfa.challenge({factorId:factor.id});
 if(challengeError)throw challengeError;
 const {error:verifyError}=await state.supabase.auth.mfa.verify({factorId:factor.id,challengeId:challenge.id,code:code.trim()});
 if(verifyError)throw verifyError;
}
function pageFilters(){
 const dateValue=id=>el(id)?.value?new Date(el(id).value+(id==="toFilter"?"T23:59:59":"T00:00:00")).toISOString():undefined;
 return {module:state.currentModule,limit:state.pageSize,offset:state.page*state.pageSize,search:el("search")?.value||undefined,status:el("statusFilter")?.value||undefined,cityId:el("cityFilter")?.value||undefined,from:dateValue("fromFilter"),to:dateValue("toFilter")};
}
async function loadModule(){
 const module=state.modules.find(item=>item.key===state.currentModule);
 const restricted=["verification","payments","deposits","payouts","refunds","disputes","damage-claims","privacy-requests","risk-alerts","audit-logs","approvals"].includes(module.key);
 el("content").innerHTML=(restricted?'<div class="notice"><strong>Restricted data view</strong>Only the columns allowed for your role are returned. Identity documents, raw provider payloads and private evidence are not included in ordinary lists. Sensitive actions require MFA and audit logging.</div>':"")+
 '<div class="card"><div class="section-heading"><div><h2>'+esc(module.label)+'</h2><p>Server-side permission checks, filtering and pagination.</p></div></div>'+toolbarMarkup(module)+'</div>'+
 '<div id="records" class="table-wrap" style="margin-top:13px"><div class="empty">Loading records…</div></div><div id="pager" class="pagination"></div>';
 el("applyFilters").addEventListener("click",()=>{state.page=0;fetchRecords();});
 el("search").addEventListener("keydown",event=>{if(event.key==="Enter"){state.page=0;fetchRecords();}});
 if(el("exportCsv"))el("exportCsv").addEventListener("click",exportCsv);
 await fetchRecords();
}
function cellValue(value){
 const text=fmt(value);
 if(typeof value==="string"&&/^(pending|approved|rejected|active|paused|hidden|removed|published|open|closed|failed|success|denied|requested|under_review|completed|triaged)$/u.test(value))return '<span class="pill">'+esc(text.replaceAll("_"," "))+"</span>";
 return esc(text.length>180?text.slice(0,177)+"…":text);
}
function actionCell(module,row){
 const id=row.id||row.user_id;
 if(module.key==="verification")return '<div class="table-actions"><button class="secondary" data-action="docs" data-user="'+esc(row.user_id)+'">View documents</button><button class="primary" data-action="verify" data-user="'+esc(row.user_id)+'">Review</button></div>';
 if(["catalogue","copies","community","reviews"].includes(module.key))return '<div class="table-actions"><button class="secondary" data-action="moderate" data-id="'+esc(id)+'" data-module="'+esc(module.key)+'">Moderate</button></div>';
 if(module.key==="users")return '<div class="table-actions"><button class="secondary" data-action="suspend" data-id="'+esc(row.id)+'">Request restriction</button></div>';
 if(module.key==="approvals"&&row.status==="pending")return '<div class="table-actions"><button class="primary" data-action="approval" data-id="'+esc(row.id)+'">Review</button></div>';
 const actionMap={refunds:"refund.execute",payouts:"payout.execute",deposits:"deposit.release",disputes:"dispute.finalize",pricing:"pricing.publish",valuation:"valuation.publish", "legal-documents":"legal.publish","risk-alerts":"risk.resolve"};
 if(actionMap[module.key])return '<div class="table-actions"><button class="secondary" data-action="request" data-id="'+esc(id)+'" data-key="'+esc(actionMap[module.key])+'">Request approval</button></div>';
 return "—";
}
async function fetchRecords(){
 const module=state.modules.find(item=>item.key===state.currentModule);
 el("records").innerHTML='<div class="empty">Loading…</div>';
 try{
  const data=await invoke("list",pageFilters());state.rows=data.rows||[];state.total=data.total||0;
  const columns=Object.keys(state.rows[0]||{});
  const hasActions=["verification","catalogue","copies","community","reviews","users","approvals","refunds","payouts","deposits","disputes","pricing","valuation","legal-documents","risk-alerts"].includes(module.key);
  if(!columns.length)el("records").innerHTML='<div class="empty">No records found.</div>';
  else{
   el("records").innerHTML="<table><thead><tr>"+columns.map(col=>"<th>"+esc(col.replaceAll("_"," "))+"</th>").join("")+(hasActions?"<th>Actions</th>":"")+"</tr></thead><tbody>"+
    state.rows.map(row=>"<tr>"+columns.map(col=>'<td title="'+esc(fmt(row[col]))+'">'+cellValue(row[col])+"</td>").join("")+(hasActions?"<td>"+actionCell(module,row)+"</td>":"")+"</tr>").join("")+"</tbody></table>";
   bindRowActions();
  }
  el("pager").innerHTML="<span>"+state.total.toLocaleString()+" records · Page "+(state.page+1)+"</span><div class=\"table-actions\"><button id=\"previous\" class=\"secondary\" "+(state.page===0?"disabled":"")+">Previous</button><button id=\"next\" class=\"secondary\" "+(((state.page+1)*state.pageSize)>=state.total?"disabled":"")+">Next</button></div>";
  el("previous").addEventListener("click",()=>{state.page=Math.max(0,state.page-1);fetchRecords();});
  el("next").addEventListener("click",()=>{state.page++;fetchRecords();});
 }catch(error){el("records").innerHTML='<div class="empty">'+esc(error.message)+"</div>";}
}
function askReason(title,description,callback){
 el("reasonTitle").textContent=title;el("reasonDescription").textContent=description;el("reasonText").value="";state.pendingReason=callback;el("reasonDialog").showModal();
}
el("reasonForm").addEventListener("submit",async event=>{
 if(event.submitter?.value!=="confirm"){state.pendingReason=null;return;}
 event.preventDefault();const reason=el("reasonText").value.trim();
 if(reason.length<20){el("reasonDescription").textContent="Please enter a reason with at least 20 characters.";return;}
 const action=state.pendingReason;state.pendingReason=null;el("reasonDialog").close();
 try{await action(reason);await fetchRecords();}catch(error){alert(error.message||"Action failed.");}
});
function bindRowActions(){
 document.querySelectorAll("[data-action]").forEach(button=>button.addEventListener("click",()=>{
  const kind=button.dataset.action;
  if(kind==="docs")askReason("Open identity documents","Only verification reviewers with MFA AAL2 can open a 60-second private link.",async reason=>{
   await ensureAal2();const data=await invoke("identity-documents",{userId:button.dataset.user,reason});
   const docs=(data.documents||[]).map(doc=>doc.type+" ("+(doc.last4||"—")+"): "+doc.signedUrl).join("\n");
   alert(docs||"No identity documents available. Signed links expire after 60 seconds.");
  });
  if(kind==="verify")askReason("Finalise verification","This is an identity decision. Confirm that evidence is sufficient and record an accurate reason.",async reason=>{
   await ensureAal2();const status=prompt("Enter verified, rejected or needs_resubmission:");if(!status)return;
   const reasonCode=prompt("Reason code:");if(!reasonCode)return;
   await invoke("finalize-verification",{userId:button.dataset.user,statusValue:status,reasonCode,reason});
  });
  if(kind==="moderate")askReason("Moderate content","Allowed status values depend on the selected module. A reviewer cannot moderate their own copy, post or review.",async reason=>{
   await ensureAal2();const choices={catalogue:["approved","rejected","pending_review"],copies:["approved","rejected","paused","removed"],community:["published","hidden","removed","draft"],reviews:["published","hidden","removed","pending_moderation"]};
   const status=prompt("Allowed values: "+choices[button.dataset.module].join(", "));if(!status)return;
   await invoke("moderate",{module:button.dataset.module,targetId:button.dataset.id,statusValue:status,reason});
  });
  if(kind==="suspend")askReason("Request account restriction","A separate super-admin approval is required. This does not suspend the account immediately.",async reason=>{
   await ensureAal2();const target=button.dataset.id;
   await invoke("request-approval",{actionKey:"user.suspend",targetId:target,requestPayload:{status:"suspended",reasonCode:"admin_review"},reason,idempotencyKey:"admin-approval:"+crypto.randomUUID()});
  });
  if(kind==="request")askReason("Request high-risk approval","The action will enter the maker-checker queue. Approval is not a provider refund, payout, deposit transfer or publication.",async reason=>{
   await ensureAal2();
   const payloadText=prompt("Optional JSON payload for the checker (for example amountPaise and reasonCode):","{}");
   if(payloadText===null)return;
   let requestPayload;try{requestPayload=JSON.parse(payloadText);}catch{throw new Error("The approval payload must be valid JSON.");}
   if(!requestPayload||typeof requestPayload!=="object"||Array.isArray(requestPayload))throw new Error("The approval payload must be a JSON object.");
   await invoke("request-approval",{actionKey:button.dataset.key,targetId:button.dataset.id,requestPayload,reason,idempotencyKey:"admin-approval:"+crypto.randomUUID()});
  });
  if(kind==="approval")askReason("Review approval request","The requester cannot approve their own request. MFA AAL2 is mandatory. Approval does not execute the downstream provider transaction.",async reason=>{
   await ensureAal2();const decision=prompt("Enter approved or rejected:");if(!decision)return;
   await invoke("decide-approval",{requestId:button.dataset.id,decision,reason});
  });
 }));
}
async function exportCsv(){
 try{
  const data=await invoke("export",Object.assign({},pageFilters(),{limit:1000,offset:0}));
  const blob=new Blob([data.csv||""],{type:"text/csv;charset=utf-8"});
  const url=URL.createObjectURL(blob),a=document.createElement("a");
  a.href=url;a.download=data.filename||("shelfshare-"+state.currentModule+".csv");a.click();URL.revokeObjectURL(url);
 }catch(error){alert(error.message||"Export failed.");}
}
el("sendOtp").addEventListener("click",sendOtp);
el("verifyOtp").addEventListener("click",verifyOtp);
el("logout").addEventListener("click",async()=>{await state.supabase.auth.signOut();location.reload();});

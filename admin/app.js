import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const state={supabase:null,projectUrl:null,anonKey:null,modules:[],permissions:new Set(),currentModule:"dashboard",page:0,pageSize:25,total:0,rows:[],pendingReason:null};
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
  state.projectUrl=url;state.anonKey=key;
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
function availableModules(){
 const modules=[...state.modules];
 if(state.permissions.has("support.manage")||state.permissions.has("grievances.manage"))modules.push({key:"support-tickets",label:"Support tickets"});
 if(state.permissions.has("finance.analytics.read"))modules.push({key:"finance-report",label:"Financial analytics"});
 return modules;
}
function renderNavigation(){
 el("navigation").innerHTML=availableModules().map(module=>'<button type="button" data-module="'+esc(module.key)+'" class="'+(module.key===state.currentModule?"active":"")+'">'+esc(module.label)+"</button>").join("");
 el("navigation").querySelectorAll("button").forEach(button=>button.addEventListener("click",()=>selectModule(button.dataset.module)));
}
async function selectModule(key){
 const module=availableModules().find(item=>item.key===key);if(!module)return;
 state.currentModule=key;state.page=0;el("pageTitle").textContent=module.label;renderNavigation();
 if(key==="dashboard")await renderDashboard();
 else if(key==="support-tickets")await renderSupportTickets();
 else if(key==="finance-report")await renderFinanceReport();
 else await loadModule();
}
async function renderDashboard(){
 el("content").innerHTML='<div class="notice"><strong>Operational snapshot</strong>Counts are permission-filtered and are not financial statements. Payment counts do not indicate collected or settled money.</div><div id="dashboardCards" class="cards"><div class="card">Loading dashboard…</div></div><div class="section-heading"><div><h2>Your access</h2><p>Access depends on the role permissions currently assigned to your account.</p></div></div><div class="card"><div class="permission-list">'+[...state.permissions].sort().map(item=>"<span>"+esc(item)+"</span>").join("")+"</div></div>";
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


async function invokeOperations(action,payload={}){
 const {data,error}=await state.supabase.functions.invoke("customer-operations",{body:Object.assign({action},payload)});
 if(error)throw error;
 if(data?.error)throw new Error(data.error);
 return data;
}
async function callOperationsDownload(endpoint,payload,filename){
 const {data,error}=await state.supabase.auth.getSession();
 if(error||!data.session)throw new Error("Your session has expired. Sign in again.");
 const response=await fetch(state.projectUrl+"/functions/v1/"+endpoint,{
  method:"POST",
  headers:{Authorization:"Bearer "+data.session.access_token,apikey:state.anonKey,"Content-Type":"application/json"},
  body:JSON.stringify(payload)
 });
 if(!response.ok){
  const result=await response.json().catch(()=>({}));
  throw new Error(result.error||"Download failed.");
 }
 const blob=await response.blob(),url=URL.createObjectURL(blob),a=document.createElement("a");
 a.href=url;a.download=filename;a.click();URL.revokeObjectURL(url);
}
async function requestFinanceReport(format){
 const {data,error}=await state.supabase.auth.getSession();
 if(error||!data.session)throw new Error("Your session has expired. Sign in again.");
 const response=await fetch(state.projectUrl+"/functions/v1/financial-report",{
  method:"POST",
  headers:{Authorization:"Bearer "+data.session.access_token,apikey:state.anonKey,"Content-Type":"application/json"},
  body:JSON.stringify({from:el("financeFrom").value,to:el("financeTo").value,format})
 });
 if(!response.ok){
  const result=await response.json().catch(()=>({}));
  throw new Error(result.error||"Financial report request failed.");
 }
 if(format==="csv"){
  const blob=await response.blob(),url=URL.createObjectURL(blob),a=document.createElement("a");
  a.href=url;a.download="shelfshare-financial-"+el("financeFrom").value+"-"+el("financeTo").value+".csv";a.click();URL.revokeObjectURL(url);
  return null;
 }
 return response.json();
}
function localDateInput(date){
 return date.getFullYear()+"-"+String(date.getMonth()+1).padStart(2,"0")+"-"+String(date.getDate()).padStart(2,"0");
}
function inrFromPaise(value){
 const amount=Number(value??0)/100;
 return new Intl.NumberFormat("en-IN",{style:"currency",currency:"INR",maximumFractionDigits:2}).format(amount);
}
async function renderFinanceReport(){
 const now=new Date(),start=new Date(now.getFullYear(),now.getMonth(),1);
 el("content").innerHTML='<div class="notice"><strong>Finance-only reporting</strong>Amounts are in INR and sourced from recorded payment, commission, refund and operating-cost records. This report is operational analytics, not a statutory tax return or accounting statement. MFA AAL2 is required.</div>'+
 '<div class="card"><div class="toolbar"><div class="field"><label>From date (IST)</label><input id="financeFrom" type="date" value="'+localDateInput(start)+'"></div><div class="field"><label>To date (IST)</label><input id="financeTo" type="date" value="'+localDateInput(now)+'"></div><button id="loadFinance" class="primary">Load analytics</button><button id="downloadFinance" class="secondary">Download CSV</button></div><p id="financeMessage" class="muted"></p></div>'+
 '<div id="financeSummary" class="cards" style="margin-top:14px"></div>'+
 '<div class="section-heading"><div><h2>Daily performance</h2><p>Captured rental value by India business date.</p></div></div><div id="financeDaily" class="table-wrap"></div>'+
 '<div class="section-heading"><div><h2>Locality performance</h2><p>Paid rentals grouped by physical copy locality.</p></div></div><div id="financeLocality" class="table-wrap"></div>';
 el("loadFinance").addEventListener("click",loadFinanceAnalytics);
 el("downloadFinance").addEventListener("click",async()=>{try{await ensureAal2();if(!el("financeFrom").value||!el("financeTo").value)throw new Error("Choose a date range.");await requestFinanceReport("csv");}catch(error){el("financeMessage").textContent=error.message||"Download failed."; }});
 await loadFinanceAnalytics();
}
async function loadFinanceAnalytics(){
 const message=el("financeMessage");message.textContent="Loading finance metrics…";
 try{
  await ensureAal2();
  if(!el("financeFrom").value||!el("financeTo").value||el("financeTo").value<el("financeFrom").value)throw new Error("Choose a valid date range.");
  const data=await requestFinanceReport("json"),s=data.summary||{};
  const metrics=[
   ["Gross rental transaction value",inrFromPaise(s.gross_rental_transaction_value_paise)],
   ["Platform commission",inrFromPaise(s.commission_paise)],
   ["Gateway charges",inrFromPaise(s.gateway_charges_paise)],
   ["Refunds completed",inrFromPaise(s.refunds_completed_paise)],
   ["Booked tax",inrFromPaise(s.booked_tax_paise)],
   ["SMS costs",inrFromPaise(s.sms_cost_paise)],
   ["Verification costs",inrFromPaise(s.verification_cost_paise)],
   ["Referral rewards",inrFromPaise(s.referral_reward_expenditure_paise)],
   ["Referral operating costs",inrFromPaise(s.referral_operating_cost_paise)],
   ["Support costs",inrFromPaise(s.support_cost_paise)],
   ["Net contribution*",inrFromPaise(s.net_contribution_before_other_overheads_paise)],
   ["Average rental value",inrFromPaise(s.average_rental_value_paise)],
   ["Repeat rental rate",String(s.repeat_rental_rate_percent??0)+"%"],
   ["Booking conversion",String(s.booking_conversion_percent??0)+"%"],
   ["Paid bookings",Number(s.paid_bookings??0).toLocaleString("en-IN")],
   ["Active books now",Number(s.active_books_now??0).toLocaleString("en-IN")]
  ];
  el("financeSummary").innerHTML=metrics.map(([label,value])=>'<div class="card"><div class="metric-label">'+esc(label)+'</div><div class="metric-value finance-value">'+esc(value)+'</div></div>').join("");
  const daily=data.daily_performance||[];
  el("financeDaily").innerHTML=daily.length?'<table><thead><tr><th>IST date</th><th>Paid bookings</th><th>Gross rental value</th></tr></thead><tbody>'+daily.map(row=>'<tr><td>'+esc(row.date)+'</td><td>'+Number(row.paid_bookings??0).toLocaleString("en-IN")+'</td><td>'+esc(inrFromPaise(row.gross_rental_value_paise))+'</td></tr>').join("")+'</tbody></table>':'<div class="empty">No captured rentals in this period.</div>';
  const localities=data.locality_performance||[];
  el("financeLocality").innerHTML=localities.length?'<table><thead><tr><th>City</th><th>Locality</th><th>Paid bookings</th><th>Gross rental value</th></tr></thead><tbody>'+localities.map(row=>'<tr><td>'+esc(row.city)+'</td><td>'+esc(row.locality)+'</td><td>'+Number(row.paid_bookings??0).toLocaleString("en-IN")+'</td><td>'+esc(inrFromPaise(row.gross_rental_value_paise))+'</td></tr>').join("")+'</tbody></table>':'<div class="empty">No locality data available for this period.</div>';
  message.textContent="Period: "+data.period.from+" to "+data.period.to+" ("+data.period.timezone+"). *Before other overheads; see metric definitions in the operations guide.";
 }catch(error){message.textContent=error.message||"Unable to load analytics.";el("financeSummary").innerHTML="";el("financeDaily").innerHTML="";el("financeLocality").innerHTML="";}
}
async function renderSupportTickets(){
 el("content").innerHTML='<div class="notice"><strong>Support operations</strong>Ticket reads are permission-filtered. Internal notes are visible only to authorised support staff. Status/priority/assignment changes require MFA AAL2 and an audit reason.</div>'+
 '<div class="card"><div class="toolbar"><div class="field"><label>Status</label><select id="supportStatus"><option value="open">Open and active</option><option value="all">All</option><option value="in_progress">In progress</option><option value="waiting_user">Waiting for user</option><option value="resolved">Resolved</option><option value="closed">Closed</option></select></div><div class="field"><label>Category</label><select id="supportCategory"><option value="">All categories</option></select></div><div class="field"><label>Priority</label><select id="supportPriority"><option value="">All priorities</option><option>urgent</option><option>high</option><option>normal</option><option>low</option></select></div><div class="field"><label>Assignee UUID</label><input id="supportAssignee" placeholder="Optional staff user ID"></div><button id="loadSupport" class="primary">Apply filters</button><button id="exportSupport" class="secondary">Export CSV</button></div></div>'+
 '<div id="supportRecords" class="table-wrap" style="margin-top:13px"><div class="empty">Loading support queue…</div></div>'+
 '<div id="ticketDetail" style="margin-top:15px"></div>';
 try{
  const categories=await invokeOperations("support-categories");
  el("supportCategory").innerHTML='<option value="">All categories</option>'+(categories.categories||[]).map(item=>'<option value="'+esc(item.category_key)+'">'+esc(item.label)+'</option>').join("");
 }catch(error){el("supportRecords").innerHTML='<div class="empty">'+esc(error.message)+'</div>';return;}
 el("loadSupport").addEventListener("click",loadSupportQueue);
 el("exportSupport").addEventListener("click",async()=>{try{await ensureAal2();await callOperationsDownload("customer-operations",{action:"support-export",limit:1000},"shelfshare-support-tickets.csv");}catch(error){alert(error.message||"Export failed.");}});
 await loadSupportQueue();
}
async function loadSupportQueue(){
 const target=el("supportRecords");
 target.innerHTML='<div class="empty">Loading tickets…</div>';
 try{
  const data=await invokeOperations("support-queue",{
   status:el("supportStatus").value,category:el("supportCategory").value||undefined,
   priority:el("supportPriority").value||undefined,assignedTo:el("supportAssignee").value.trim()||undefined,limit:200
  });
  const rows=data.tickets||[];
  target.innerHTML=rows.length?'<table><thead><tr><th>Ticket</th><th>Category</th><th>Priority</th><th>Status</th><th>Assignee</th><th>First response due</th><th>Resolution due</th><th>SLA breach</th><th>Actions</th></tr></thead><tbody>'+
   rows.map(row=>'<tr><td><strong>'+esc(row.ticket_number)+'</strong><br>'+esc(row.subject)+'</td><td>'+esc(row.category)+'</td><td>'+esc(row.priority)+'</td><td>'+esc(row.status)+'</td><td>'+esc(row.assigned_to||"Unassigned")+'</td><td>'+esc(fmt(row.first_response_due_at))+'</td><td>'+esc(fmt(row.resolution_due_at))+'</td><td>'+esc(fmt(row.sla_breached_at))+'</td><td><div class="table-actions"><button class="secondary" data-ticket-view="'+esc(row.id)+'">Open</button><button class="primary" data-ticket-manage="'+esc(row.id)+'" data-ticket-status="'+esc(row.status)+'" data-ticket-priority="'+esc(row.priority)+'" data-ticket-assignee="'+esc(row.assigned_to||"")+'">Manage</button></div></td></tr>').join("")+
   '</tbody></table>':'<div class="empty">No support tickets match these filters.</div>';
  target.querySelectorAll("[data-ticket-view]").forEach(button=>button.addEventListener("click",()=>openSupportTicket(button.dataset.ticketView)));
  target.querySelectorAll("[data-ticket-manage]").forEach(button=>button.addEventListener("click",()=>manageSupportTicket(button.dataset.ticketManage,button.dataset.ticketStatus,button.dataset.ticketPriority,button.dataset.ticketAssignee)));
 }catch(error){target.innerHTML='<div class="empty">'+esc(error.message||"Unable to load queue.")+'</div>';}
}
async function openSupportTicket(ticketId){
 const panel=el("ticketDetail");panel.innerHTML='<div class="card">Loading ticket conversation…</div>';
 try{
  const data=await invokeOperations("ticket-detail",{ticketId});
  const ticket=data.ticket||{},messages=data.messages||[],history=data.history||[];
  panel.innerHTML='<div class="card"><div class="section-heading"><div><h2>'+esc(ticket.ticket_number)+" · "+esc(ticket.subject)+'</h2><p>'+esc(ticket.category)+" · "+esc(ticket.priority)+" · "+esc(ticket.status)+'</p></div></div>'+
   '<p>'+esc(ticket.description)+'</p><h3>Response history</h3><div class="support-thread">'+messages.map(item=>'<article class="support-message"><div><strong>'+esc(item.author_type.replaceAll("_"," "))+'</strong><small>'+esc(fmt(item.created_at))+(item.is_internal?" · internal note":"")+'</small></div><p>'+esc(item.body)+'</p></article>').join("")+'</div>'+
   '<h3>Ticket activity</h3><div class="support-history">'+history.map(item=>'<p><strong>'+esc(item.event_type.replaceAll("_"," "))+'</strong> · '+esc(fmt(item.created_at))+' · '+esc(item.reason||"")+'</p>').join("")+'</div>'+
   (ticket.status==="closed"?"":'<label class="support-reply-label">Add reply or internal note<textarea id="supportReply" rows="4" maxlength="5000"></textarea></label><label class="support-check"><input id="supportInternal" type="checkbox"> Internal note (staff only)</label><button id="sendSupportReply" class="primary">Send response</button>')+
   '</div>';
  if(el("sendSupportReply"))el("sendSupportReply").addEventListener("click",async()=>{
   const message=el("supportReply").value.trim(),internal=el("supportInternal").checked;
   if(!message)throw new Error("Enter a response before sending.");
   try{await invokeOperations("reply-ticket",{ticketId,message,internal});await openSupportTicket(ticketId);await loadSupportQueue();}catch(error){alert(error.message||"Response failed.");}
  });
 }catch(error){panel.innerHTML='<div class="card">'+esc(error.message||"Unable to open ticket.")+'</div>';}
}
function manageSupportTicket(ticketId,currentStatus,currentPriority,currentAssignee){
 askReason("Manage support ticket","Choose the next status and priority, assign a support staff user, and record an audit reason.",async reason=>{
  await ensureAal2();
  const status=prompt("Status: open, in_progress, waiting_user, resolved, closed",currentStatus);
  if(!status)return;
  const priority=prompt("Priority: low, normal, high, urgent",currentPriority);
  if(!priority)return;
  const assignedTo=prompt("Assignee user UUID (leave blank to unassign)",currentAssignee||"");
  if(assignedTo===null)return;
  await invokeOperations("manage-ticket",{ticketId,status,priority,assignedTo:assignedTo.trim()||null,reason});
  await loadSupportQueue();
  await openSupportTicket(ticketId);
 });
}

el("sendOtp").addEventListener("click",sendOtp);
el("verifyOtp").addEventListener("click",verifyOtp);
el("logout").addEventListener("click",async()=>{await state.supabase.auth.signOut();location.reload();});

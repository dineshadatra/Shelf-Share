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
 if(["legal.read","legal.draft.write","privacy.read","privacy.manage","privacy.incidents.read","privacy.retention.read","privacy.accesslog.read"].some(permission=>state.permissions.has(permission)))
  modules.push({key:"privacy-legal",label:"Privacy & Legal"});
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
 else if(key==="privacy-legal")await renderPrivacyLegal();
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
 '<div class="section-heading"><div><h2>Locality performance</h2><p>Paid rentals grouped by physical copy locality.</p></div></div><div id="financeLocality" class="table-wrap"></div>'+
 (state.permissions.has("finance.costs.write")?'<div class="section-heading"><div><h2>Record verified operating cost</h2><p>Enter a provider invoice, receipt or approved expense record. Amounts are INR.</p></div></div><div class="card"><div class="toolbar"><div class="field"><label>Cost category</label><select id="costCategory"><option value="gateway_charge">Gateway charge</option><option value="sms">SMS</option><option value="verification">Verification</option><option value="referral">Referral operations</option><option value="support">Support</option></select></div><div class="field"><label>Amount (₹)</label><input id="costAmount" type="number" min="0.01" step="0.01" placeholder="0.00"></div><div class="field"><label>Expense date (IST)</label><input id="costDate" type="date" value="'+localDateInput(now)+'"></div><div class="field"><label>Vendor</label><input id="costVendor" maxlength="120"></div><div class="field"><label>Source type</label><input id="costSourceType" maxlength="60" placeholder="provider_invoice"></div><div class="field"><label>Source reference</label><input id="costSourceReference" maxlength="160" placeholder="Invoice or receipt ID"></div></div><label>Reason / evidence description<textarea id="costReason" rows="3" maxlength="1000" placeholder="Describe the source document and expense period."></textarea></label><button id="saveFinanceCost" class="primary">Record cost</button><p id="financeCostMessage" class="muted"></p></div>':"");
 el("loadFinance").addEventListener("click",loadFinanceAnalytics);
 el("downloadFinance").addEventListener("click",async()=>{try{await ensureAal2();if(!el("financeFrom").value||!el("financeTo").value)throw new Error("Choose a date range.");await requestFinanceReport("csv");}catch(error){el("financeMessage").textContent=error.message||"Download failed."; }});
 if(el("saveFinanceCost"))el("saveFinanceCost").addEventListener("click",recordFinanceCost);
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

async function recordFinanceCost(){
 const message=el("financeCostMessage");
 try{
  await ensureAal2();
  const amount=Number(el("costAmount").value),reason=el("costReason").value.trim();
  const sourceType=el("costSourceType").value.trim(),sourceReference=el("costSourceReference").value.trim();
  if(!Number.isFinite(amount)||amount<=0||!Number.isSafeInteger(Math.round(amount*100)))throw new Error("Enter a valid positive INR amount.");
  if(reason.length<20||sourceType.length<2||sourceReference.length<1)throw new Error("Provide a source type, source reference and reason of at least 20 characters.");
  if(!el("costDate").value)throw new Error("Choose the expense date.");
  const occurredAt=new Date(el("costDate").value+"T12:00:00+05:30").toISOString();
  const {data,error}=await state.supabase.rpc("record_financial_cost",{
   p_cost_category:el("costCategory").value,
   p_amount_paise:Math.round(amount*100),
   p_occurred_at:occurredAt,
   p_vendor:el("costVendor").value.trim()||null,
   p_source_type:sourceType,
   p_source_reference:sourceReference,
   p_reason:reason,
   p_idempotency_key:"finance-cost-"+crypto.randomUUID(),
   p_city_id:null,
   p_locality_id:null
  });
  if(error)throw error;
  message.textContent="Verified cost entry recorded ("+String(data)+").";
  el("costAmount").value="";el("costReason").value="";
  await loadFinanceAnalytics();
 }catch(error){message.textContent=error.message||"Unable to record cost entry.";}
}



async function invokePrivacy(action,payload={}){
 const {data,error}=await state.supabase.functions.invoke("legal-privacy-operations",{body:Object.assign({action},payload)});
 if(error)throw error;
 if(data?.error)throw new Error(data.error);
 return data;
}
async function downloadPrivacyDocument(documentId){
 const {data,error}=await state.supabase.auth.getSession();
 if(error||!data.session)throw new Error("Your session has expired.");
 const response=await fetch(state.projectUrl+"/functions/v1/legal-privacy-operations",{
  method:"POST",
  headers:{Authorization:"Bearer "+data.session.access_token,apikey:state.anonKey,"Content-Type":"application/json"},
  body:JSON.stringify({action:"download-legal-document",documentId})
 });
 if(!response.ok){const body=await response.json().catch(()=>({}));throw new Error(body.error||"Document download failed.");}
 const blob=await response.blob(),url=URL.createObjectURL(blob),a=document.createElement("a");
 a.href=url;a.download="shelfshare-legal-"+documentId+".md";a.click();URL.revokeObjectURL(url);
}
function downloadMarkdown(name,content){
 const blob=new Blob([content],{type:"text/markdown;charset=utf-8"}),url=URL.createObjectURL(blob),a=document.createElement("a");
 a.href=url;a.download=name;a.click();URL.revokeObjectURL(url);
}
async function renderPrivacyLegal(){
 const canLegal=state.permissions.has("legal.read");
 const canEditLegal=state.permissions.has("legal.draft.write");
 const canPrivacy=state.permissions.has("privacy.read");
 const canPrivacyManage=state.permissions.has("privacy.manage");
 const canIncidents=state.permissions.has("privacy.incidents.read");
 const canRetention=state.permissions.has("privacy.retention.read");
 const canAccessLog=state.permissions.has("privacy.accesslog.read");
 el("content").innerHTML='<div class="notice"><strong>Privacy & legal operations</strong>All legal content is draft-only until reviewed by Indian counsel and published through maker-checker approval. Privacy requests, breach incidents, retention rules and sensitive-data access are restricted and audited. Do not put passwords, OTPs, full Aadhaar/PAN numbers or payment credentials in case notes.</div>'+
 (canLegal?'<div class="section-heading"><div><h2>Legal document register</h2><p>Versioned Markdown documents · SHA-256 · publication requires independent approval</p></div><button id="refreshLegal" class="secondary">Refresh</button></div><div id="legalDocumentTable" class="table-wrap"><div class="empty">Loading legal documents…</div></div><div id="legalEditor" class="card" style="margin-top:12px"><div class="empty">Select a draft to review or edit.</div></div>':"")+
 (canPrivacy?'<div class="section-heading"><div><h2>Privacy requests</h2><p>Access, correction, deletion, consent withdrawal, portability and grievance requests</p></div><button id="exportPrivacy" class="secondary">Export request metadata</button></div><div id="privacyRequestTable" class="table-wrap"><div class="empty">Loading privacy requests…</div></div>':"")+
 (canIncidents?'<div class="section-heading"><div><h2>Security and privacy incidents</h2><p>Incident record, containment, impact assessment and notification evidence</p></div><button id="newPrivacyIncident" class="primary">Record incident</button></div><div id="privacyIncidentTable" class="table-wrap"></div>':"")+
 (canRetention?'<div class="section-heading"><div><h2>Data retention rules</h2><p>Retention periods remain inactive until separately approved. No blanket automatic deletion.</p></div><button id="newRetentionRule" class="secondary">Create draft rule</button></div><div id="retentionPolicyTable" class="table-wrap"></div>':"")+
 (canAccessLog?'<div class="section-heading"><div><h2>Sensitive-data access log</h2><p>Read-only audit trail; every view of this log is also logged.</p></div><button id="refreshAccessLog" class="secondary">Refresh</button></div><div id="sensitiveAccessTable" class="table-wrap"></div>':"");
 if(canLegal){
  el("refreshLegal").addEventListener("click",loadLegalDocuments);
  await loadLegalDocuments();
 }
 if(canPrivacy){
  el("exportPrivacy").addEventListener("click",async()=>{try{await ensureAal2();await downloadOperationsCsv("privacy-export","shelfshare-privacy-requests.csv");}catch(error){alert(error.message||"Export failed.");}});
  await loadPrivacyQueue();
 }
 if(canIncidents){
  el("newPrivacyIncident").addEventListener("click",createPrivacyIncident);
  await loadPrivacyIncidents();
 }
 if(canRetention){
  el("newRetentionRule").addEventListener("click",createRetentionRule);
  await loadRetentionPolicies();
 }
 if(canAccessLog){
  el("refreshAccessLog").addEventListener("click",loadSensitiveAccessLog);
  await loadSensitiveAccessLog();
 }
}
async function downloadOperationsCsv(action,filename){
 const {data,error}=await state.supabase.auth.getSession();
 if(error||!data.session)throw new Error("Your session has expired.");
 const response=await fetch(state.projectUrl+"/functions/v1/legal-privacy-operations",{
  method:"POST",
  headers:{Authorization:"Bearer "+data.session.access_token,apikey:state.anonKey,"Content-Type":"application/json"},
  body:JSON.stringify({action})
 });
 if(!response.ok){const result=await response.json().catch(()=>({}));throw new Error(result.error||"Export failed.");}
 const blob=await response.blob(),url=URL.createObjectURL(blob),a=document.createElement("a");
 a.href=url;a.download=filename;a.click();URL.revokeObjectURL(url);
}
async function loadLegalDocuments(){
 const target=el("legalDocumentTable");if(!target)return;
 target.innerHTML='<div class="empty">Loading legal document register…</div>';
 try{
  const data=await invokePrivacy("legal-list"),rows=data.documents||[];
  target.innerHTML=rows.length?'<table><thead><tr><th>Document</th><th>Version</th><th>Review state</th><th>Published</th><th>SHA-256</th><th>Effective from</th><th>Actions</th></tr></thead><tbody>'+
   rows.map(row=>'<tr><td><strong>'+esc(row.title)+'</strong><br><small>'+esc(row.document_type)+'</small></td><td>'+esc(row.version)+'</td><td>'+esc(row.review_status)+'</td><td>'+esc(row.is_published?"Yes":"No")+'</td><td><code>'+esc(String(row.sha256||"").slice(0,16))+'…</code></td><td>'+esc(fmt(row.effective_from))+'</td><td><div class="table-actions">'+(row.is_published?'<button class="secondary" data-legal-download="'+esc(row.id)+'">Download</button>':(state.permissions.has("legal.draft.write")?'<button class="secondary" data-legal-edit="'+esc(row.id)+'">Edit draft</button>':""))+(row.is_published&&state.permissions.has("legal.draft.write")?'<button class="secondary" data-legal-next="'+esc(row.id)+'">Create next version</button>':"")+(row.review_status==="draft"&&state.permissions.has("legal.draft.write")?'<button class="secondary" data-legal-review="'+esc(row.id)+'">Submit review</button>':"")+(row.review_status==="in_review"&&state.permissions.has("legal.publish.request")?'<button class="secondary" data-legal-counsel="'+esc(row.id)+'">Record counsel review</button><button class="primary" data-legal-request="'+esc(row.id)+'">Request publication</button>':"")+(row.review_status==="in_review"&&state.permissions.has("legal.publish.approve")?'<button class="secondary" data-legal-publish="'+esc(row.id)+'">Publish approved</button>':"")+'</div></td></tr>').join("")+'</tbody></table>':'<div class="empty">No legal documents found.</div>';
  target.querySelectorAll("[data-legal-edit]").forEach(button=>button.addEventListener("click",()=>openLegalDraft(button.dataset.legalEdit)));
  target.querySelectorAll("[data-legal-next]").forEach(button=>button.addEventListener("click",()=>createLegalVersion(button.dataset.legalNext)));
  target.querySelectorAll("[data-legal-download]").forEach(button=>button.addEventListener("click",async()=>{try{await downloadPrivacyDocument(button.dataset.legalDownload);}catch(error){alert(error.message||"Download failed.");}}));
  target.querySelectorAll("[data-legal-review]").forEach(button=>button.addEventListener("click",()=>submitLegalReview(button.dataset.legalReview)));
  target.querySelectorAll("[data-legal-request]").forEach(button=>button.addEventListener("click",()=>requestLegalPublication(button.dataset.legalRequest)));
  target.querySelectorAll("[data-legal-counsel]").forEach(button=>button.addEventListener("click",()=>recordLegalCounselReview(button.dataset.legalCounsel)));
  target.querySelectorAll("[data-legal-publish]").forEach(button=>button.addEventListener("click",()=>publishLegalDocument(button.dataset.legalPublish)));
 }catch(error){target.innerHTML='<div class="empty">'+esc(error.message||"Unable to load legal documents.")+'</div>';}
}
async function openLegalDraft(documentId){
 const panel=el("legalEditor");panel.innerHTML='<div class="empty">Loading draft…</div>';
 try{
  await ensureAal2();
  const data=await invokePrivacy("legal-draft-detail",{documentId}),doc=data.document;
  panel.innerHTML='<div class="section-heading"><div><h2>Edit legal draft</h2><p>Saving creates a new content hash. Published versions cannot be edited.</p></div></div>'+
   '<div class="toolbar"><div class="field"><label>Document type</label><input id="legalType" value="'+esc(doc.document_type)+'" readonly></div><div class="field"><label>Version</label><input id="legalVersion" value="'+esc(doc.version)+'"></div><div class="field"><label>Title</label><input id="legalTitle" maxlength="160" value="'+esc(doc.title)+'"></div></div>'+
   '<div class="toolbar"><div class="field"><label>Version-controlled source path</label><input id="legalUri" value="'+esc(doc.content_uri)+'"></div><label class="support-check"><input id="legalRequireAcceptance" type="checkbox" '+(doc.requires_acceptance?"checked":"")+'> User acceptance required</label><label class="support-check"><input id="legalReacceptance" type="checkbox" '+(doc.reacceptance_required?"checked":"")+'> Reaccept after material change</label></div>'+
   '<label class="support-reply-label">Markdown content<textarea id="legalMarkdown" rows="18" maxlength="150000"></textarea></label>'+
   '<label class="support-reply-label">Internal review notes<textarea id="legalReviewNotes" rows="3" maxlength="4000"></textarea></label>'+
   '<div class="table-actions"><button id="downloadLegalDraft" class="secondary">Download draft</button><button id="saveLegalDraft" class="primary">Save draft and recompute hash</button></div><p id="legalSaveMessage" class="muted"></p>';
  el("legalMarkdown").value=doc.content_markdown||"";
  el("legalReviewNotes").value=doc.review_notes||"";
  const revisions=data.revisions||[];
  panel.innerHTML+='<div class="section-heading"><div><h3>Immutable revision history</h3><p>Each save adds a new SHA-256 snapshot.</p></div></div>'+
   (revisions.length?'<div class="table-wrap"><table><thead><tr><th>Revision</th><th>SHA-256</th><th>Changed by</th><th>Changed at</th><th>Note</th></tr></thead><tbody>'+
    revisions.map(item=>'<tr><td>'+Number(item.revision_number)+'</td><td><code>'+esc(item.sha256.slice(0,16))+'…</code></td><td><code>'+esc(item.changed_by)+'</code></td><td>'+esc(fmt(item.created_at))+'</td><td>'+esc(item.change_note||"")+'</td></tr>').join("")+
    '</tbody></table></div>':'<div class="empty">No saved revisions.</div>');
  el("downloadLegalDraft").addEventListener("click",()=>downloadMarkdown("shelfshare-"+doc.document_type+"-v"+doc.version+".md",el("legalMarkdown").value));
  el("saveLegalDraft").addEventListener("click",async()=>{
   const message=el("legalSaveMessage");
   try{
    await ensureAal2();
    const result=await invokePrivacy("legal-save-draft",{
     documentId:doc.id,documentType:doc.document_type,version:el("legalVersion").value.trim(),
     title:el("legalTitle").value.trim(),contentUri:el("legalUri").value.trim(),
     contentMarkdown:el("legalMarkdown").value,
     requiresAcceptance:el("legalRequireAcceptance").checked,
     reacceptanceRequired:el("legalReacceptance").checked,
     reviewNotes:el("legalReviewNotes").value
    });
    message.textContent="Saved. New SHA-256 is stored in the registry for document "+result.documentId+".";
    await loadLegalDocuments();
   }catch(error){message.textContent=error.message||"Unable to save legal draft.";}
  });
 }catch(error){panel.innerHTML='<div class="empty">'+esc(error.message||"Unable to open legal draft.")+'</div>';}
}
async function submitLegalReview(documentId){
 askReason("Submit legal document for review","The content becomes read-only after publication. Confirm counsel review notes and complete all placeholders before requesting publication.",async reason=>{
  await ensureAal2();
  await invokePrivacy("legal-submit-review",{documentId,reviewNotes:reason});
  await loadLegalDocuments();
 });
}


async function createLegalVersion(sourceDocumentId){
 askReason("Create next legal document version","This copies the published source into a new unpublished draft. Choose a new version number and Markdown source path, then download and commit the file to Git after editing.",async reason=>{
  await ensureAal2();
  const newVersion=prompt("New version (e.g. 1.1 or 2.0):");
  if(!newVersion)return;
  const newContentUri=prompt("New Markdown path (docs/legal-drafts/...md):");
  if(!newContentUri)return;
  const result=await invokePrivacy("legal-create-version",{sourceDocumentId,newVersion,newContentUri,reason});
  await loadLegalDocuments();
  await openLegalDraft(result.documentId);
 });
}

async function recordLegalCounselReview(documentId){
 askReason("Record Indian counsel review","Enter the external Indian lawyer's name, review date and a reference to the written review. This records an internal attestation; it does not verify the lawyer or make the draft legally compliant.",async reason=>{
  await ensureAal2();
  const counselName=prompt("Indian counsel full name:");
  if(!counselName)return;
  const reviewReference=prompt("Written opinion / engagement reference (do not enter confidential advice text):");
  if(!reviewReference)return;
  const reviewedAt=prompt("Date/time counsel completed review (ISO 8601):",new Date().toISOString());
  if(!reviewedAt)return;
  await invokePrivacy("legal-record-counsel-review",{documentId,counselName,reviewReference,reviewedAt,reason});
  await loadLegalDocuments();
 });
}

async function requestLegalPublication(documentId){
 askReason("Request legal publication","This creates a maker-checker approval. The requesting user cannot approve their own request.",async reason=>{
  await ensureAal2();
  const data=await invokePrivacy("legal-request-publish",{documentId,reason,idempotencyKey:"legal-publish-"+crypto.randomUUID()});
  alert("Publication approval request created: "+data.approvalRequestId+". A different authorised reviewer must approve it in the Approvals module.");
  await loadLegalDocuments();
 });
}
async function publishLegalDocument(documentId){
 askReason("Publish approved legal document","Enter the approval request ID and effective date. Only a separately approved legal.publish request can publish this version.",async reason=>{
  await ensureAal2();
  const approvalRequestId=prompt("Approved publication request UUID:");
  if(!approvalRequestId)return;
  const effectiveFrom=prompt("Effective from (ISO 8601 with timezone):",new Date().toISOString());
  if(!effectiveFrom)return;
  await invokePrivacy("legal-publish",{documentId,approvalRequestId,effectiveFrom});
  await loadLegalDocuments();
 });
}
async function loadPrivacyQueue(){
 const target=el("privacyRequestTable");if(!target)return;
 target.innerHTML='<div class="empty">Loading privacy requests…</div>';
 try{
  const data=await invokePrivacy("privacy-queue",{limit:200}),rows=data.requests||[];
  target.innerHTML=rows.length?'<table><thead><tr><th>Reference</th><th>Type</th><th>Status</th><th>Requester UUID</th><th>Assigned</th><th>Received</th><th>Legal hold</th><th>Actions</th></tr></thead><tbody>'+
   rows.map(row=>'<tr><td><strong>'+esc(row.request_reference)+'</strong></td><td>'+esc(row.request_type)+'</td><td>'+esc(row.status)+'</td><td><code>'+esc(row.requester_id)+'</code></td><td>'+esc(row.assigned_to||"Unassigned")+'</td><td>'+esc(fmt(row.received_at))+'</td><td>'+esc(row.legal_hold?"Yes":"No")+'</td><td><div class="table-actions"><button class="secondary" data-privacy-view="'+esc(row.id)+'">Review</button>'+(!row.identity_verified_at&&state.permissions.has("privacy.manage")?'<button class="secondary" data-privacy-verify="'+esc(row.id)+'">Verify identity</button>':"")+(row.request_type==="correction"&&row.identity_verified_at?'<button class="primary" data-privacy-correct="'+esc(row.id)+'" data-privacy-user="'+esc(row.requester_id)+'">Apply correction</button>':"")+(row.request_type==="erasure"&&state.permissions.has("privacy.erase.request")?'<button class="secondary" data-privacy-erase="'+esc(row.id)+'">Request erasure approval</button>':"")+'<button class="secondary" data-privacy-hold="'+esc(row.requester_id)+'">Place legal hold</button></div></td></tr>').join("")+'</tbody></table>':'<div class="empty">No privacy requests found.</div>';
  target.querySelectorAll("[data-privacy-view]").forEach(button=>button.addEventListener("click",()=>reviewPrivacyRequest(button.dataset.privacyView)));
  target.querySelectorAll("[data-privacy-verify]").forEach(button=>button.addEventListener("click",()=>verifyPrivacyRequest(button.dataset.privacyVerify)));
  target.querySelectorAll("[data-privacy-correct]").forEach(button=>button.addEventListener("click",()=>applyPrivacyCorrection(button.dataset.privacyCorrect,button.dataset.privacyUser)));
  target.querySelectorAll("[data-privacy-erase]").forEach(button=>button.addEventListener("click",()=>requestPrivacyErasure(button.dataset.privacyErase)));
  target.querySelectorAll("[data-privacy-hold]").forEach(button=>button.addEventListener("click",()=>createPrivacyHold(button.dataset.privacyHold)));
 }catch(error){target.innerHTML='<div class="empty">'+esc(error.message||"Unable to load privacy requests.")+'</div>';}
}
async function reviewPrivacyRequest(requestId){
 try{
  await ensureAal2();
  const data=await invokePrivacy("privacy-detail",{requestId});
  const item=data.request,events=data.events||[];
  const nextStatus=prompt("New status: received, identity_check, in_progress, awaiting_user, fulfilled, partially_fulfilled, rejected, closed",item.status);
  if(!nextStatus)return;
  const assignedTo=prompt("Assigned staff UUID (blank to unassign)",item.assigned_to||"");
  if(assignedTo===null)return;
  const resolutionSummary=prompt("Resolution / update summary (leave blank to retain)",item.resolution_summary||"");
  const reason=prompt("Internal audit reason (minimum 20 characters):");
  if(!reason)return;
  await invokePrivacy("privacy-update",{requestId,status:nextStatus,assignedTo:assignedTo.trim()||null,resolutionSummary:resolutionSummary||null,reason});
  await loadPrivacyQueue();
  alert("Request "+item.request_reference+" updated. "+events.length+" prior events were reviewed.");
 }catch(error){alert(error.message||"Unable to update privacy request.");}
}

async function verifyPrivacyRequest(requestId){
 askReason("Verify privacy requester identity","Use a proportionate verification step and record the verification method in the audit reason. Do not request a password or OTP.",async reason=>{
  await ensureAal2();
  await invokePrivacy("privacy-verify-request",{requestId,reason});
  await loadPrivacyQueue();
 });
}
async function applyPrivacyCorrection(requestId,userId){
 askReason("Apply verified profile correction","Only display name, bio, preferred city and locale can be changed in this workflow. Email/phone changes use the account recovery/verification flow.",async reason=>{
  await ensureAal2();
  const displayName=prompt("Correct display name (blank to leave unchanged):");
  const bio=prompt("Correct bio (blank to leave unchanged; use [CLEAR] to clear):");
  const preferredCityId=prompt("Preferred city UUID (blank unchanged; [CLEAR] to clear):");
  const locale=prompt("Locale (blank unchanged):");
  const payload={requestId,reason};
  if(displayName)payload.displayName=displayName;
  if(bio!==null&&bio.trim())payload.bio=bio.trim()==="[CLEAR]"?null:bio;
  if(preferredCityId!==null&&preferredCityId.trim())payload.preferredCityId=preferredCityId.trim()==="[CLEAR]"?null:preferredCityId;
  if(locale)payload.locale=locale;
  await invokePrivacy("privacy-correct-profile",payload);
  await loadPrivacyQueue();
  alert("The allowed profile fields were corrected for "+userId+".");
 });
}

async function requestPrivacyErasure(requestId){
 askReason("Request controlled data erasure","This queues only identity document deletion and basic profile anonymisation after a separate approver checks active rentals and legal holds.",async reason=>{
  await ensureAal2();
  const result=await invokePrivacy("privacy-erase-request",{requestId,reason});
  alert("Erasure approval request created: "+result.approvalRequestId+". A separate super-admin must approve it, then queue the worker.");
 });
}
async function createPrivacyHold(userId){
 askReason("Place privacy legal hold","Use only for a documented legal, contractual, safety or dispute preservation reason.",async reason=>{
  await ensureAal2();
  const dataClass=prompt("Data class (e.g. identity_documents, booking_contracts, payment_ledger):","identity_documents");
  if(!dataClass)return;
  await invokePrivacy("privacy-hold-create",{userId,dataClass,reason});
  await loadPrivacyQueue();
 });
}
async function loadPrivacyIncidents(){
 const target=el("privacyIncidentTable");if(!target)return;
 target.innerHTML='<div class="empty">Loading incident register…</div>';
 try{
  const data=await invokePrivacy("incident-list"),rows=data.incidents||[];
  target.innerHTML=rows.length?'<table><thead><tr><th>Reference</th><th>Detected</th><th>Severity</th><th>Status</th><th>Affected subjects (estimate)</th><th>Data categories</th></tr></thead><tbody>'+
   rows.map(row=>'<tr><td>'+esc(row.incident_reference)+'</td><td>'+esc(fmt(row.detected_at))+'</td><td>'+esc(row.severity)+'</td><td>'+esc(row.status)+'</td><td>'+esc(row.estimated_affected_subjects??"Unknown")+'</td><td>'+esc((row.data_categories||[]).join(", "))+'</td></tr>').join("")+'</tbody></table>':'<div class="empty">No incident records.</div>';
 }catch(error){target.innerHTML='<div class="empty">'+esc(error.message||"Unable to load incidents.")+'</div>';}
}
async function createPrivacyIncident(){
 askReason("Record a privacy/security incident","Record known facts only. Do not speculate about impact. Incident reference format: INC- followed by an uppercase unique identifier.",async containment=>{
  await ensureAal2();
  const incidentReference="INC-"+crypto.randomUUID().replaceAll("-","").slice(0,12).toUpperCase();
  const detectedAt=prompt("Detection timestamp (ISO 8601):",new Date().toISOString());
  if(!detectedAt)return;
  const severity=prompt("Severity: low, medium, high, critical","medium");
  if(!severity)return;
  const factualSummary=prompt("Factual summary (minimum 20 characters):");
  if(!factualSummary)return;
  const categories=(prompt("Affected data categories, comma separated:","account_profile,identity_documents")||"").split(",").map(value=>value.trim()).filter(Boolean);
  const systems=(prompt("Systems affected, comma separated:","supabase_storage")||"").split(",").map(value=>value.trim()).filter(Boolean);
  const affected=prompt("Estimated affected people (blank if unknown):","");
  const estimatedSubjects=affected?.trim()?Number(affected):null;
  await invokePrivacy("incident-create",{incidentReference,detectedAt,severity,dataCategories:categories,systemsAffected:systems,estimatedSubjects,factualSummary,containment});
  await loadPrivacyIncidents();
 });
}
async function loadRetentionPolicies(){
 const target=el("retentionPolicyTable");if(!target)return;
 target.innerHTML='<div class="empty">Loading retention rules…</div>';
 try{
  const data=await invokePrivacy("retention-list"),rows=data.policies||[];
  target.innerHTML=rows.length?'<table><thead><tr><th>Data class</th><th>Rule/version</th><th>Days</th><th>Status</th><th>Created by</th><th>Approved by</th><th>Actions</th></tr></thead><tbody>'+
   rows.map(row=>'<tr><td>'+esc(row.data_class)+'</td><td>'+esc(row.rule_key)+" / "+esc(row.version)+'</td><td>'+esc(row.retention_days??"Not set")+'</td><td>'+esc(row.status)+'</td><td>'+esc(row.created_by)+'</td><td>'+esc(row.approved_by||"—")+'</td><td>'+(row.status==="draft"&&state.permissions.has("privacy.retention.approve")?'<button class="secondary" data-retention-approve="'+esc(row.id)+'">Approve</button>':"")+'</td></tr>').join("")+'</tbody></table>':'<div class="empty">No retention rules configured. No retention period is assumed by default.</div>';
  target.querySelectorAll("[data-retention-approve]").forEach(button=>button.addEventListener("click",()=>approveRetentionRule(button.dataset.retentionApprove)));
 }catch(error){target.innerHTML='<div class="empty">'+esc(error.message||"Unable to load retention rules.")+'</div>';}
}
async function createRetentionRule(){
 askReason("Create a draft retention rule","A retention period must be justified by actual business purpose and Indian legal advice. Creating a rule does not activate deletion.",async rationale=>{
  await ensureAal2();
  const ruleKey=prompt("Rule key (e.g. identity-document-retention):");
  if(!ruleKey)return;
  const version=prompt("Version:","1.0");
  if(!version)return;
  const dataClass=prompt("Data class: identity_documents, verification_metadata, account_profile, booking_contracts, payment_ledger, tax_records, handover_evidence, support_cases, grievance_records, community_content, security_logs, consent_records, legal_acceptance_records, breach_incident_records, marketing_analytics","identity_documents");
  if(!dataClass)return;
  const days=Number(prompt("Proposed retention days (must be legally approved before activation):","365"));
  if(!Number.isInteger(days)||days<1)throw new Error("Enter a positive whole number of days.");
  const legalBasisNote=prompt("Legal basis / preservation rationale (minimum 10 characters):");
  if(!legalBasisNote)return;
  await invokePrivacy("retention-save",{ruleKey,version,dataClass,retentionDays:days,rationale,legalBasisNote});
  await loadRetentionPolicies();
 });
}
async function approveRetentionRule(policyId){
 askReason("Approve retention schedule","Confirm that the retention period has been reviewed by Indian counsel, the business owner and the relevant records owner.",async reason=>{
  await ensureAal2();
  const effectiveFrom=prompt("Effective from (ISO 8601):",new Date().toISOString());
  if(!effectiveFrom)return;
  await invokePrivacy("retention-approve",{policyId,effectiveFrom,reason});
  await loadRetentionPolicies();
 });
}
async function loadSensitiveAccessLog(){
 const target=el("sensitiveAccessTable");if(!target)return;
 target.innerHTML='<div class="empty">Loading sensitive-data access events…</div>';
 try{
  const data=await invokePrivacy("privacy-access-log",{limit:250}),rows=data.events||[];
  target.innerHTML=rows.length?'<table><thead><tr><th>Time</th><th>Actor</th><th>Subject</th><th>Data class</th><th>Resource</th><th>Purpose</th><th>Outcome</th><th>Request ID</th></tr></thead><tbody>'+
   rows.map(row=>'<tr><td>'+esc(fmt(row.accessed_at))+'</td><td><code>'+esc(row.actor_id)+'</code></td><td><code>'+esc(row.subject_user_id||"—")+'</code></td><td>'+esc(row.data_class)+'</td><td>'+esc(row.resource_table)+"/"+esc(row.resource_id)+'</td><td>'+esc(row.purpose)+'</td><td>'+esc(row.outcome)+'</td><td><code>'+esc(row.request_id)+'</code></td></tr>').join("")+'</tbody></table>':'<div class="empty">No sensitive access events recorded yet.</div>';
 }catch(error){target.innerHTML='<div class="empty">'+esc(error.message||"Unable to load access history.")+'</div>';}
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

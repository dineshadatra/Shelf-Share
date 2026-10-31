import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { ADMIN_MODULES, findAdminModule, sanitizeAdminSearch, validateAdminPage, toCsv } from "../_shared/admin.ts";

type Body = {
  action?: string; module?: string; search?: string; status?: string; cityId?: string;
  from?: string; to?: string; limit?: number; offset?: number; userId?: string;
  documentId?: string; reason?: string; decision?: string; reasonCode?: string;
  targetId?: string; targetTable?: string; requestPayload?: Record<string, unknown>;
  actionKey?: string; idempotencyKey?: string; requestId?: string; statusValue?: string;
  role?: string; reference?: Record<string, unknown>; referenceId?: string;
};
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const SEARCH_DATE = /^\d{4}-\d{2}-\d{2}T/u;
const APPROVAL_ACTIONS = new Set([
  "refund.execute","payout.execute","deposit.release","dispute.finalize",
  "pricing.publish","valuation.publish","legal.publish","risk.resolve","user.suspend"
]);
const REFERENCE_POLICIES: Record<string, { table: string; permission: string; fields: string[]; columns: string }> = {
  categories: { table:"categories", permission:"geography.manage", fields:["slug","name","description","parent_id","is_active"], columns:"id,slug,name,description,parent_id,is_active,created_at" },
  cities: { table:"cities", permission:"geography.manage", fields:["code","name","state_name","country_code","timezone","status","is_active"], columns:"id,code,name,state_name,country_code,timezone,status,is_active,created_at,updated_at" },
  localities: { table:"localities", permission:"geography.manage", fields:["city_id","name","normalized_name","postal_codes","is_active"], columns:"id,city_id,name,normalized_name,postal_codes,is_active,created_at" },
  "handover-locations": { table:"handover_locations", permission:"geography.manage", fields:["locality_id","city_id","name","description","public_address","latitude","longitude","opening_hours","safety_notes","status"], columns:"id,locality_id,city_id,name,description,public_address,status,opening_hours,created_at,updated_at" }
};

function json(data: unknown, status = 200, origin = "") {
  const headers = new Headers({
    "Content-Type":"application/json; charset=utf-8",
    "Cache-Control":"no-store",
    "X-Content-Type-Options":"nosniff",
    "Referrer-Policy":"no-referrer"
  });
  if (origin) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set("Vary", "Origin");
    headers.set("Access-Control-Allow-Headers", "authorization, apikey, content-type, x-client-info");
    headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  }
  return new Response(JSON.stringify(data), {status,headers});
}
function errorStatus(message: string) {
  if (/authentication|invalid jwt|session required/iu.test(message)) return 401;
  if (/permission|mfa|aal2|forbidden/iu.test(message)) return 403;
  if (/not found/iu.test(message)) return 404;
  if (/already|pending|expired|conflict/iu.test(message)) return 409;
  return 400;
}
function textValue(value: unknown, field: string, min = 2, max = 2000): string {
  if (typeof value !== "string") throw new Error("invalid_" + field);
  const result = value.trim();
  if (result.length < min || result.length > max) throw new Error("invalid_" + field);
  return result;
}
function uuidValue(value: unknown, field: string): string {
  if (typeof value !== "string" || !UUID.test(value)) throw new Error("invalid_" + field);
  return value;
}
function isoDate(value: unknown, field: string): string {
  if (typeof value !== "string" || !SEARCH_DATE.test(value) || Number.isNaN(Date.parse(value))) throw new Error("invalid_" + field);
  return new Date(value).toISOString();
}
function tokenClaims(token: string): Record<string, unknown> {
  const part = token.split(".")[1];
  if (!part) throw new Error("invalid_session_token");
  const normalized = part.replace(/-/gu,"+").replace(/_/gu,"/");
  return JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4,"=")));
}
function redact(value: Record<string, unknown>): Record<string, unknown> {
  const visit = (input: unknown): unknown => {
    if (Array.isArray(input)) return input.map(visit);
    if (!input || typeof input !== "object") return input;
    const output: Record<string, unknown> = {};
    for (const [key, child] of Object.entries(input as Record<string, unknown>)) {
      if (/token|secret|object_key|document|phone|email|address|payload|url|identity|pan|aadhaar/iu.test(key)) continue;
      output[key] = visit(child);
    }
    return output;
  };
  return visit(value) as Record<string, unknown>;
}
function escapeSearch(value: string) {
  return value.replace(/[%_\\,()]/gu, character => "\\" + character);
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("Origin") ?? "";
  const configuredOrigins = (Deno.env.get("ADMIN_PORTAL_ORIGINS") ?? "https://admin.shelfshare.in")
    .split(",").map(value => value.trim()).filter(Boolean);
  const allowedOrigin = origin && configuredOrigins.includes(origin) ? origin : "";
  if (request.method === "OPTIONS") {
    if (!allowedOrigin) return json({error:"origin_not_allowed"},403);
    return new Response(null,{status:204,headers:{
      "Access-Control-Allow-Origin":allowedOrigin,"Vary":"Origin",
      "Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info",
      "Access-Control-Allow-Methods":"POST, OPTIONS","Access-Control-Max-Age":"600"
    }});
  }
  if (request.method !== "POST") return json({error:"method_not_allowed"},405,allowedOrigin);

  const requestId = crypto.randomUUID();
  let actorId: string | null = null;
  let admin: ReturnType<typeof createClient> | null = null;
  let actorClient: ReturnType<typeof createClient> | null = null;

  try {
    if (!allowedOrigin) throw new Error("origin_not_allowed");
    const authorization = request.headers.get("Authorization") ?? "";
    const accessToken = authorization.replace(/^Bearer\s+/iu,"");
    if (!accessToken) throw new Error("authentication_required");

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceKey) throw new Error("server_configuration_missing");

    actorClient = createClient(supabaseUrl,anonKey,{
      auth:{persistSession:false,autoRefreshToken:false},
      global:{headers:{Authorization:authorization}}
    });
    const {data:userResult,error:userError} = await actorClient.auth.getUser();
    if (userError || !userResult.user) throw new Error("authentication_required");
    actorId = userResult.user.id;
    admin = createClient(supabaseUrl,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});

    const body = await request.json() as Body;
    const action = textValue(body.action,"action",2,60);

    const activity = async (
      activityAction: string, moduleKey: string, permissionKey: string | null,
      outcome: "success"|"denied"|"failed", reason: string | null = null,
      targetTable: string | null = null, targetId: string | null = null,
      metadata: Record<string,unknown> = {}
    ) => {
      const {error} = await admin!.from("admin_activity_events").insert({
        actor_id:actorId,action:activityAction,module_key:moduleKey,permission_key:permissionKey,
        outcome,reason:reason ? reason.slice(0,500) : null,target_table:targetTable,
        target_id:targetId,request_id:requestId,metadata:redact(metadata)
      });
      if (error) throw new Error("admin_activity_write_failed");
    };
    const hasPermission = async (permission: string): Promise<boolean> => {
      const {data,error} = await actorClient!.rpc("admin_has_permission",{p_permission_key:permission});
      if (error) throw error;
      return data === true;
    };
    const requirePermission = async (permission: string, moduleKey: string) => {
      if (!await hasPermission(permission)) {
        await activity(action,moduleKey,permission,"denied","permission_denied");
        throw new Error("permission_denied");
      }
    };
    const requireAal2 = () => {
      const claims = tokenClaims(accessToken);
      if (claims.aal !== "aal2") throw new Error("step_up_mfa_aal2_required");
    };
    const finish = async (activityAction: string,moduleKey:string,permission:string,targetTable:string,targetId:string,result:unknown) => {
      await activity(activityAction,moduleKey,permission,"success",null,targetTable,targetId);
      return json({ok:true,result,requestId},200,allowedOrigin);
    };

    if (action === "bootstrap") {
      await requirePermission("dashboard.read","dashboard");
      const [{data:permissions,error:permissionError},{data:roles,error:roleError}] = await Promise.all([
        actorClient.rpc("admin_my_permissions"),
        admin.from("user_roles").select("role,granted_at").eq("user_id",actorId).is("revoked_at",null)
      ]);
      if (permissionError || roleError) throw new Error("admin_bootstrap_failed");
      const keys = new Set<string>((permissions ?? []) as string[]);
      await activity("portal_opened","dashboard","dashboard.read","success");
      return json({
        user:{id:actorId},
        roles:(roles ?? []).map(row=>row.role),
        permissions:[...keys],
        modules:ADMIN_MODULES.filter(module=>keys.has(module.permission)).map(({key,label,permission,exportable})=>({key,label,permission,exportable}))
      },200,allowedOrigin);
    }

    if (action === "dashboard") {
      await requirePermission("dashboard.read","dashboard");
      const count = async (permission:string,table:string,apply?:(query:any)=>any):Promise<number|null> => {
        if (!await hasPermission(permission)) return null;
        let query = admin!.from(table).select("*",{count:"exact",head:true});
        if (apply) query=apply(query);
        const {count:total,error}=await query;
        if(error) throw error;
        return total ?? 0;
      };
      const [users,copies,pendingBooks,pendingVerification,activeBookings,openDisputes,openGrievances,openRisk] = await Promise.all([
        count("users.read","profiles"),
        count("inventory.read","book_copies"),
        count("catalogue.read","book_titles",q=>q.eq("moderation_status","pending_review")),
        count("verification.queue.read","user_verifications",q=>q.in("status",["pending","under_review","needs_resubmission"])),
        count("bookings.read","bookings",q=>q.in("status",["confirmed","collection_pending","active","return_pending"])),
        count("disputes.read","disputes",q=>q.neq("status","closed")),
        count("grievances.read","grievance_tickets",q=>q.in("status",["open","in_progress","waiting_user"])),
        count("risk.read","risk_alerts",q=>q.eq("status","open"))
      ]);
      const financeCount = await count("payments.read","payments");
      const cards = {users,physicalCopies:copies,booksAwaitingModeration:pendingBooks,
        verificationsAwaitingReview:pendingVerification,activeBookings,openDisputes,
        openGrievances,openRiskAlerts:openRisk,paymentRecords:financeCount};
      await activity("dashboard_viewed","dashboard","dashboard.read","success");
      return json({cards,requestId},200,allowedOrigin);
    }

    if (action === "list" || action === "export") {
      const moduleKey = textValue(body.module,"module",2,60);
      const module = findAdminModule(moduleKey);
      if (!module || !module.table) return json({error:"unknown_admin_module"},404,allowedOrigin);
      await requirePermission(module.permission,module.key);
      const exporting = action === "export";
      if (exporting && !module.exportable) return json({error:"export_not_allowed_for_module"},403,allowedOrigin);
      const page = validateAdminPage({limit:body.limit,offset:body.offset,export:exporting});
      const search = sanitizeAdminSearch(body.search);
      if (body.status && !module.statusField) throw new Error("status_filter_not_supported");
      if (body.cityId && !module.cityField) throw new Error("city_filter_not_supported");
      if ((body.from || body.to) && !module.dateField) throw new Error("date_filter_not_supported");

      const fields = module.columns.split(",");
      let query = admin.from(module.table).select(module.columns,{count:"exact"});
      if(module.key==="approvals"){
        const actionPermissions:Record<string,string[]> = {
          "refund.execute":["refunds.execute.request","refunds.execute.approve"],
          "payout.execute":["payouts.execute.request","payouts.execute.approve"],
          "deposit.release":["deposits.release.request","deposits.release.approve"],
          "dispute.finalize":["disputes.finalize.request","disputes.finalize.approve"],
          "pricing.publish":["pricing.publish.request","pricing.publish.approve"],
          "valuation.publish":["valuation.publish.request","valuation.publish.approve"],
          "legal.publish":["legal.publish.request","legal.publish.approve"],
          "risk.resolve":["risk.resolve.request","risk.resolve.approve"],
          "user.suspend":["users.suspend.request","users.suspend.approve"]
        };
        const visibleActions:string[]=[];
        for(const [key,permissions] of Object.entries(actionPermissions)){
          for(const permission of permissions){
            if(await hasPermission(permission)){visibleActions.push(key);break;}
          }
        }
        if(!visibleActions.length) return json({rows:[],total:0,limit:page.limit,offset:page.offset,requestId},200,allowedOrigin);
        query=query.in("action_key",visibleActions);
      }
      if(search && module.searchFields.length){
        const term=escapeSearch(search);
        query=query.or(module.searchFields.map(field=>field+".ilike.%"+term+"%").join(","));
      }
      if(body.status && module.statusField) query=query.eq(module.statusField,body.status);
      if(body.cityId && module.cityField) query=query.eq(module.cityField,uuidValue(body.cityId,"city_id"));
      if(body.from && module.dateField) query=query.gte(module.dateField,isoDate(body.from,"from"));
      if(body.to && module.dateField) query=query.lte(module.dateField,isoDate(body.to,"to"));
      query=query.order(module.orderBy,{ascending:false}).range(page.offset,page.offset+page.limit-1);
      const {data, count:total, error}=await query;
      if(error) throw error;
      if(exporting){
        const csv=toCsv((data??[]) as Record<string,unknown>[],fields);
        await activity("data_exported",module.key,module.permission,"success",null,module.table,null,{row_count:data?.length??0,format:"csv"});
        return json({csv,filename:"shelfshare-"+module.key+".csv",rows:data?.length??0},200,allowedOrigin);
      }
      await activity("module_list_viewed",module.key,module.permission,"success",null,module.table,null,{returned:data?.length??0,offset:page.offset});
      return json({rows:data??[],total:total??0,limit:page.limit,offset:page.offset,requestId},200,allowedOrigin);
    }

    if (action === "identity-documents") {
      await requirePermission("identity.documents.read","verification");
      requireAal2();
      const targetUser=uuidValue(body.userId,"user_id");
      const reason=textValue(body.reason,"reason",20,1000);
      const {data:role,error:roleError}=await admin.from("user_roles").select("role")
        .eq("user_id",actorId).eq("role","verification_reviewer").is("revoked_at",null).maybeSingle();
      if(roleError || !role) throw new Error("verification_reviewer_role_required");
      const {data:verification,error:verificationError}=await admin.from("user_verifications")
        .select("user_id,status").eq("user_id",targetUser).maybeSingle();
      if(verificationError || !verification) return json({error:"verification_not_found"},404,allowedOrigin);
      const {data:documents,error:documentError}=await admin.from("identity_documents")
        .select("id,storage_bucket,object_key,document_type,document_last4,status,submitted_at")
        .eq("user_id",targetUser).order("submitted_at",{ascending:false}).limit(10);
      if(documentError) throw documentError;
      const signed=[];
      for(const doc of documents??[]){
        const {data,error}=await admin.storage.from("identity-private").createSignedUrl(doc.object_key,60);
        if(!error && data?.signedUrl) signed.push({id:doc.id,type:doc.document_type,last4:doc.document_last4,status:doc.status,submittedAt:doc.submitted_at,signedUrl:data.signedUrl,expiresInSeconds:60});
      }
      await activity("identity_documents_opened","verification","identity.documents.read","success",reason,"identity_documents",targetUser,{count:signed.length,stepUp:"aal2"});
      return json({documents:signed,requestId,expiresInSeconds:60,warning:"Private identity material. Do not download or retain outside the approved verification process."},200,allowedOrigin);
    }

    if (action === "review-identity-document") {
      await requirePermission("verification.decide","verification"); requireAal2();
      const documentId=uuidValue(body.documentId,"document_id");
      const decision=textValue(body.decision,"decision",5,30);
      const reasonCode=textValue(body.reasonCode,"reason_code",3,100);
      const reason=textValue(body.reason,"reason",20,1000);
      const {error}=await actorClient.rpc("admin_review_identity_document",{p_document_id:documentId,p_decision:decision,p_reason_code:reasonCode,p_reason:reason});
      if(error) throw error;
      return await finish("identity_document_reviewed","verification","verification.decide","identity_documents",documentId,{decision});
    }

    if (action === "finalize-verification") {
      await requirePermission("verification.decide","verification"); requireAal2();
      const targetUser=uuidValue(body.userId,"user_id");
      const status=textValue(body.statusValue,"status",5,30);
      const reasonCode=textValue(body.reasonCode,"reason_code",3,100);
      const reason=textValue(body.reason,"reason",20,1000);
      const {error}=await actorClient.rpc("admin_finalize_verification",{p_user_id:targetUser,p_status:status,p_reason_code:reasonCode,p_reason:reason});
      if(error) throw error;
      return await finish("verification_finalized","verification","verification.decide","user_verifications",targetUser,{status});
    }

    if (action === "request-approval") {
      requireAal2();
      const actionKey=textValue(body.actionKey,"action_key",3,60);
      if(!APPROVAL_ACTIONS.has(actionKey)) throw new Error("unsupported_high_risk_action");
      const targetId=textValue(body.targetId,"target_id",1,100);
      const reason=textValue(body.reason,"reason",30,2000);
      if(!body.requestPayload || typeof body.requestPayload!=="object" || Array.isArray(body.requestPayload)) throw new Error("invalid_request_payload");
      const idempotencyKey=textValue(body.idempotencyKey,"idempotency_key",20,120);
      const {data,error}=await actorClient.rpc("admin_request_approval",{
        p_action_key:actionKey,p_target_id:targetId,p_request_payload:redact(body.requestPayload),
        p_reason:reason,p_idempotency_key:idempotencyKey
      });
      if(error) throw error;
      return await finish("high_risk_action_requested","approvals","approvals.read","admin_approval_requests",String(data),{actionKey,targetId});
    }

    if (action === "decide-approval") {
      await requirePermission("approvals.read","approvals"); requireAal2();
      const request=uuidValue(body.requestId,"request_id");
      const decision=textValue(body.decision,"decision",5,20);
      const reason=textValue(body.reason,"reason",30,2000);
      const {error}=await actorClient.rpc("admin_decide_approval",{p_request_id:request,p_decision:decision,p_reason:reason});
      if(error) throw error;
      return await finish("high_risk_approval_decided","approvals","approvals.read","admin_approval_requests",request,{decision});
    }

    if (action === "moderate") {
      const moduleKey=textValue(body.module,"module",2,40);
      const targetId=uuidValue(body.targetId,"target_id");
      const reason=textValue(body.reason,"reason",20,1000);
      const status=textValue(body.statusValue,"status",3,30);
      const policy:Record<string,{table:string;field:string;permission:string;allowed:string[]}> = {
        catalogue:{table:"book_titles",field:"moderation_status",permission:"catalogue.moderate",allowed:["approved","rejected","pending_review"]},
        copies:{table:"book_copies",field:"listing_status",permission:"inventory.moderate",allowed:["approved","rejected","paused","removed"]},
        community:{table:"community_posts",field:"status",permission:"community.moderate",allowed:["published","hidden","removed","draft"]},
        reviews:{table:"reviews",field:"status",permission:"reviews.moderate",allowed:["published","hidden","removed","pending_moderation"]}
      };
      const config=policy[moduleKey];
      if(!config || !config.allowed.includes(status)) return json({error:"unsupported_moderation_action"},400,allowedOrigin);
      await requirePermission(config.permission,moduleKey);
      const {error}=await actorClient.rpc("admin_moderate_content",{
        p_module_key:moduleKey,p_target_id:targetId,p_status:status,p_reason:reason
      });
      if(error) throw error;
      return await finish("content_moderated",moduleKey,config.permission,config.table,targetId,{status});
    }

    if (action === "save-reference") {
      const moduleKey=textValue(body.module,"module",2,60);
      const policy=REFERENCE_POLICIES[moduleKey];
      if(!policy) return json({error:"reference_module_not_supported"},400,allowedOrigin);
      await requirePermission(policy.permission,moduleKey); requireAal2();
      const reason=textValue(body.reason,"reason",20,1000);
      if(!body.reference || typeof body.reference!=="object" || Array.isArray(body.reference)) throw new Error("reference_payload_required");
      const values:Record<string,unknown>={};
      for(const field of policy.fields) if(body.reference[field]!==undefined) values[field]=body.reference[field];
      if(Object.keys(values).length===0) throw new Error("reference_fields_required");
      if(moduleKey==="localities" && typeof values.name==="string" && values.normalized_name===undefined) values.normalized_name=values.name.trim().toLowerCase().replace(/\s+/gu," ");
      let data:any, error:any;
      const referenceId=body.referenceId ? uuidValue(body.referenceId,"reference_id") : null;
      if(referenceId){
        const result=await admin.from(policy.table).update(values).eq("id",referenceId).select(policy.columns).single();
        data=result.data; error=result.error;
      }else{
        const result=await admin.from(policy.table).insert(values).select(policy.columns).single();
        data=result.data; error=result.error;
      }
      if(error || !data) throw new Error("reference_save_failed");
      const {error:auditError}=await admin.from("admin_audit_logs").insert({
        actor_id:actorId,action:referenceId?"admin_reference_updated":"admin_reference_created",
        target_table:policy.table,target_id:data.id,reason:reason.slice(0,1000),
        after_data:redact(values)
      });
      if(auditError) throw new Error("admin_audit_write_failed");
      return await finish("reference_saved",moduleKey,policy.permission,policy.table,data.id,{id:data.id});
    }

    if (action === "assign-staff-role" || action === "revoke-staff-role") {
      await requirePermission("access.roles.manage","access"); requireAal2();
      const targetUser=uuidValue(body.userId,"user_id");
      const role=textValue(body.role,"role",3,40);
      const reason=textValue(body.reason,"reason",30,2000);
      const rpc=action==="assign-staff-role"?"admin_assign_staff_role":"admin_revoke_staff_role";
      const {data,error}=await actorClient.rpc(rpc,{p_user_id:targetUser,p_role:role,p_reason:reason});
      if(error) throw error;
      return await finish(action,"access","access.roles.manage","user_roles",targetUser,data??{ok:true});
    }

    await activity(action,"system",null,"denied","unsupported_admin_action");
    return json({error:"unsupported_admin_action",requestId},400,allowedOrigin);
  } catch (error) {
    const message=error instanceof Error?error.message:"unexpected_error";
    if(actorId && admin){
      try {
        await admin.from("admin_activity_events").insert({
          actor_id:actorId,action:"admin_request_failed",module_key:"system",permission_key:null,
          outcome:"failed",reason:message.slice(0,500),request_id:requestId,metadata:{}
        });
      } catch { /* retain original error */ }
    }
    return json({error:message,requestId},errorStatus(message),allowedOrigin);
  }
});

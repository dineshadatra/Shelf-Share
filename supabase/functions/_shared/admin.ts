export type AdminModule = {
  key: string; label: string; permission: string; table: string; columns: string;
  searchFields: string[]; statusField?: string; cityField?: string; dateField?: string;
  orderBy: string; exportable: boolean;
};
export const ADMIN_MODULES: AdminModule[] = [
  {key:"dashboard",label:"Dashboard",permission:"dashboard.read",table:"",columns:"",searchFields:[],orderBy:"created_at",exportable:false},
  {key:"users",label:"User management",permission:"users.read",table:"profiles",columns:"id,display_name,account_status,preferred_city_id,created_at,updated_at",searchFields:["display_name"],statusField:"account_status",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"verification",label:"Manual verification",permission:"verification.queue.read",table:"user_verifications",columns:"user_id,status,age_eligible,phone_verified_at,identity_verified_at,address_verified_at,reviewed_by,reviewed_at,rejection_reason_code,created_at,updated_at",searchFields:["rejection_reason_code"],statusField:"status",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"catalogue",label:"Book catalogue",permission:"catalogue.read",table:"book_titles",columns:"id,isbn13,title,subtitle,authors,publisher,language_code,publication_year,moderation_status,created_at,updated_at",searchFields:["title","publisher","isbn13"],statusField:"moderation_status",dateField:"created_at",orderBy:"created_at",exportable:true},
  {key:"copies",label:"Physical copy moderation",permission:"inventory.read",table:"book_copies",columns:"id,book_title_id,owner_id,city_id,locality_id,condition_summary,listing_status,is_available_for_rent,created_at,updated_at",searchFields:["owner_reference"],statusField:"listing_status",cityField:"city_id",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"categories",label:"Categories",permission:"geography.read",table:"categories",columns:"id,slug,name,description,parent_id,is_active,created_at",searchFields:["name","slug"],statusField:"is_active",orderBy:"name",exportable:true},
  {key:"cities",label:"Cities",permission:"geography.read",table:"cities",columns:"id,code,name,state_name,country_code,timezone,status,is_active,created_at,updated_at",searchFields:["name","code","state_name"],statusField:"status",orderBy:"name",exportable:true},
  {key:"localities",label:"Localities",permission:"geography.read",table:"localities",columns:"id,city_id,name,normalized_name,postal_codes,is_active,created_at",searchFields:["name","normalized_name"],statusField:"is_active",cityField:"city_id",orderBy:"name",exportable:true},
  {key:"handover-locations",label:"Handover locations",permission:"geography.read",table:"handover_locations",columns:"id,locality_id,city_id,name,public_address,status,opening_hours,created_at,updated_at",searchFields:["name","public_address"],statusField:"status",cityField:"city_id",orderBy:"created_at",exportable:true},
  {key:"pricing",label:"Pricing rules",permission:"pricing.read",table:"pricing_configuration",columns:"id,config_key,scope_type,scope_id,value,version,effective_from,effective_until,approved_by,created_at",searchFields:["config_key","version"],dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"valuation",label:"Valuation rules",permission:"valuation.read",table:"book_valuation_rules",columns:"id,rule_key,version,description,formula,effective_from,effective_until,status,created_by,approved_by,approved_at,created_at",searchFields:["rule_key","description"],statusField:"status",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"bookings",label:"Booking management",permission:"bookings.read",table:"bookings",columns:"id,booking_number,reader_id,owner_id,city_id,status,requested_start_at,requested_end_at,rental_start_at,rental_due_at,completed_at,total_due_paise,deposit_required_paise,created_at,updated_at",searchFields:["booking_number"],statusField:"status",cityField:"city_id",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"payments",label:"Payment management",permission:"payments.read",table:"payments",columns:"id,booking_id,payer_id,provider,amount_paise,currency,status,captured_at,failure_code,created_at,updated_at",searchFields:["provider","failure_code"],statusField:"status",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"deposits",label:"Deposit management",permission:"deposits.read",table:"deposits",columns:"id,booking_id,payer_id,amount_paise,currency,status,feature_enabled_at_creation,created_at,updated_at",searchFields:["status"],statusField:"status",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"commission",label:"Commission",permission:"commission.read",table:"commission_ledger",columns:"id,booking_id,payment_id,commission_rate_bps,rent_basis_paise,commission_paise,currency,policy_version,created_at",searchFields:["policy_version"],dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"payouts",label:"Owner payouts",permission:"payouts.read",table:"payouts",columns:"id,owner_earning_id,owner_id,amount_paise,currency,status,initiated_at,settled_at,failure_code,created_at",searchFields:["failure_code"],statusField:"status",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"refunds",label:"Refunds",permission:"refunds.read",table:"refunds",columns:"id,booking_id,payment_id,requested_by,provider,amount_paise,currency,status,reason_code,created_at,completed_at",searchFields:["provider","reason_code"],statusField:"status",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"disputes",label:"Disputes",permission:"disputes.read",table:"disputes",columns:"id,booking_id,opened_by,against_user_id,status,reason_code,assigned_to,opened_at,decided_at,closed_at",searchFields:["reason_code"],statusField:"status",dateField:"opened_at",orderBy:"opened_at",exportable:false},
  {key:"damage-claims",label:"Damage claims",permission:"claims.read",table:"rental_damage_claims",columns:"id,booking_id,claimant_id,respondent_id,claim_category,requested_compensation_paise,approved_compensation_paise,status,decision_by,decided_at,created_at",searchFields:["claim_category"],statusField:"status",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"late-fees",label:"Late fees",permission:"late_fees.read",table:"late_fees",columns:"id,booking_id,assessed_to,amount_paise,currency,policy_version,reason_code,status,assessed_at,approved_by",searchFields:["reason_code","policy_version"],statusField:"status",dateField:"assessed_at",orderBy:"assessed_at",exportable:false},
  {key:"community",label:"Community moderation",permission:"community.moderate",table:"community_posts",columns:"id,author_id,title,body,status,published_at,created_at,updated_at",searchFields:["title","body"],statusField:"status",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"reviews",label:"Reviews",permission:"reviews.moderate",table:"reviews",columns:"id,rental_item_id,reviewer_id,reviewee_id,rating,review_text,status,created_at,published_at",searchFields:["review_text"],statusField:"status",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"referrals",label:"Referral campaigns",permission:"referrals.read",table:"admin_referral_campaigns",columns:"id,name,description,reward_type,reward_value_paise,qualifying_minimum_paise,starts_at,ends_at,max_redemptions,status,created_by,approved_by,approved_at,created_at",searchFields:["name","description"],statusField:"status",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"risk-alerts",label:"Risk alerts",permission:"risk.read",table:"risk_alerts",columns:"id,subject_user_id,booking_id,alert_type,severity,status,signal_summary,assigned_to,created_at,resolved_at",searchFields:["alert_type","signal_summary"],statusField:"status",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"support",label:"Customer support",permission:"support.read",table:"rental_safety_reports",columns:"id,reporter_id,reported_user_id,booking_id,target_type,report_type,severity,status,assigned_to,resolution_code,resolved_at,created_at",searchFields:["report_type","resolution_code"],statusField:"status",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"grievances",label:"Grievances",permission:"grievances.read",table:"grievance_tickets",columns:"id,ticket_number,requester_id,category,subject,status,assigned_to,priority,created_at,updated_at,resolved_at",searchFields:["ticket_number","category","subject"],statusField:"status",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"privacy-requests",label:"Privacy requests",permission:"privacy.read",table:"privacy_requests",columns:"id,requester_id,request_type,status,received_at,due_at,completed_at",searchFields:["request_type"],statusField:"status",dateField:"received_at",orderBy:"received_at",exportable:false},
  {key:"legal-documents",label:"Legal documents",permission:"legal.read",table:"legal_documents",columns:"id,document_type,version,title,sha256,effective_from,effective_until,is_published,created_at",searchFields:["document_type","version","title"],statusField:"is_published",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"audit-logs",label:"Audit logs",permission:"audit.read",table:"admin_activity_events",columns:"id,actor_id,action,module_key,permission_key,target_table,target_id,outcome,reason,request_id,created_at",searchFields:["action","module_key","target_table","target_id"],statusField:"outcome",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"reconciliation",label:"Financial reconciliation",permission:"reconciliation.read",table:"payment_reconciliation_runs",columns:"id,provider,report_reference,period_start,period_end,status,matched_count,unmatched_count,created_at,completed_at",searchFields:["provider","report_reference"],statusField:"status",dateField:"created_at",orderBy:"created_at",exportable:false},
  {key:"analytics",label:"Business analytics",permission:"analytics.read",table:"daily_business_metrics",columns:"metric_date,scope_key,city_id,metric_key,metric_value,dimensions,calculated_at",searchFields:["metric_key","scope_key"],cityField:"city_id",dateField:"metric_date",orderBy:"metric_date",exportable:true},
  {key:"system-settings",label:"System settings",permission:"settings.read",table:"booking_workflow_configuration",columns:"id,is_active,buffer_before,buffer_after,payment_hold_seconds,handover_ttl_seconds,rental_duration_mode,configuration_version,tax_policy_version,cancellation_policy_version,approved_by,approved_at,updated_at",searchFields:["configuration_version"],orderBy:"updated_at",exportable:false},
  {key:"approvals",label:"High-risk approvals",permission:"approvals.read",table:"admin_approval_requests",columns:"id,action_key,target_table,target_id,request_payload,reason,requested_by,approved_by,status,decision_reason,expires_at,decided_at,created_at",searchFields:["action_key","target_table","target_id"],statusField:"status",dateField:"created_at",orderBy:"created_at",exportable:false}
];
export function findAdminModule(key: string): AdminModule | undefined {
  return ADMIN_MODULES.find(module => module.key === key);
}
export function validateAdminPage(input: {limit?:unknown;offset?:unknown;export?:boolean}) {
  const maxLimit = input.export ? 1000 : 100;
  const limit = Number(input.limit ?? (input.export ? 1000 : 25));
  const offset = Number(input.offset ?? 0);
  if (!Number.isInteger(limit) || limit < 1 || limit > maxLimit) throw new Error("invalid_admin_limit");
  if (!Number.isInteger(offset) || offset < 0 || offset > 100000) throw new Error("invalid_admin_offset");
  return {limit,offset};
}
export function sanitizeAdminSearch(value: unknown): string | null {
  if (typeof value !== "string" || value.trim() === "") return null;
  const normalized=value.trim();
  if (normalized.length>80 || /[^\p{L}\p{N}\s@.+_-]/u.test(normalized)) throw new Error("invalid_admin_search");
  return normalized;
}
export function requiresMakerChecker(actionKey: string): boolean {
  return ["refund.execute","payout.execute","deposit.release","dispute.finalize","pricing.publish","valuation.publish","legal.publish","risk.resolve","user.suspend"].includes(actionKey);
}
export function toCsv(rows: Record<string,unknown>[], fields:string[]):string {
  const quote=(value:unknown)=>{
    let text=value===null||value===undefined?"":typeof value==="object"?JSON.stringify(value):String(value);
    if (/^[\s]*[=+\-@]/u.test(text)) text="'"+text;
    return '"'+text.replace(/"/gu,'""')+'"';
  };
  return [fields.map(quote).join(","),...rows.map(row=>fields.map(field=>quote(row[field])).join(","))].join("\r\n");
}

import test from "node:test";
import assert from "node:assert/strict";
import {ADMIN_MODULES,findAdminModule,validateAdminPage,sanitizeAdminSearch,requiresMakerChecker,toCsv} from "../../functions/_shared/admin.ts";
test("the portal has all 32 requested modules plus a separate approvals queue",()=>{
  assert.equal(ADMIN_MODULES.length,33);
  for(const key of ["dashboard","users","verification","catalogue","copies","categories","cities","localities","handover-locations","pricing","valuation","bookings","payments","deposits","commission","payouts","refunds","disputes","damage-claims","late-fees","community","reviews","referrals","risk-alerts","support","grievances","privacy-requests","legal-documents","audit-logs","reconciliation","analytics","system-settings","approvals"]) assert.ok(findAdminModule(key),"missing "+key);
});
test("identity object keys are never returned by ordinary verification queue",()=>{
  const module=findAdminModule("verification");
  assert.ok(module);
  assert.equal(module.columns.includes("object_key"),false);
  assert.equal(module.columns.includes("storage_bucket"),false);
  assert.equal(module.exportable,false);
});
test("pagination is bounded",()=>{
  assert.deepEqual(validateAdminPage({limit:25,offset:50}),{limit:25,offset:50});
  assert.throws(()=>validateAdminPage({limit:101}),/invalid_admin_limit/u);
  assert.throws(()=>validateAdminPage({offset:-1}),/invalid_admin_offset/u);
  assert.deepEqual(validateAdminPage({export:true}),{limit:1000,offset:0});
});
test("search rejects PostgREST operators and wildcard syntax",()=>{
  assert.equal(sanitizeAdminSearch("Bengaluru 2026"),"Bengaluru 2026");
  assert.throws(()=>sanitizeAdminSearch("x),status.eq.active"),/invalid_admin_search/u);
  assert.throws(()=>sanitizeAdminSearch("user%"),/invalid_admin_search/u);
});
test("financial and policy actions are maker-checker gated",()=>{
  for(const action of ["refund.execute","payout.execute","deposit.release","pricing.publish","valuation.publish","legal.publish","risk.resolve","user.suspend"]) assert.equal(requiresMakerChecker(action),true);
  assert.equal(requiresMakerChecker("moderate.post"),false);
});
test("CSV output neutralizes formulas and quotes delimiters",()=>{
  assert.equal(toCsv([{title:"=HYPERLINK(1)",body:'hello, "world"'}],["title","body"]),'"title","body"\r\n"\'=HYPERLINK(1)","hello, ""world"""');
});

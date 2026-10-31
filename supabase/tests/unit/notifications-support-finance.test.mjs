import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  NOTIFICATION_EVENT_KEYS,
  renderApprovedSmsTemplate,
  buildCsv
} from "../../functions/_shared/notifications.ts";

test("all requested notification event families have registered template keys", () => {
  for (const key of [
    "auth.otp","verification.submitted","verification.approved","verification.rejected",
    "listing.approved","listing.rejected","booking.requested","booking.accepted","booking.rejected",
    "payment.succeeded","payment.failed","collection.reminder","handover.confirmed",
    "rental.due_reminder","rental.overdue","extension.requested","return.confirmed",
    "dispute.opened","dispute.updated","refund.updated","payout.updated",
    "referral.rewarded","community.activity","grievance.updated"
  ]) assert.ok(NOTIFICATION_EVENT_KEYS.includes(key), "missing " + key);
  assert.equal(NOTIFICATION_EVENT_KEYS.length,24);
});

test("SMS rendering requires every variable to be pre-approved in the DLT policy", () => {
  const rendered = renderApprovedSmsTemplate(
    "ShelfShare: booking {{booking_number}} is {{status}}.",
    { booking_number: "SS-2601-000012", status: "accepted" },
    [
      { key: "booking_number", type: "reference" },
      { key: "status", type: "status" }
    ]
  );
  assert.equal(rendered, "ShelfShare: booking SS-2601-000012 is accepted.");
  assert.throws(() => renderApprovedSmsTemplate(
    "ShelfShare: booking {{booking_number}}.",
    {}, [{ key: "booking_number", type: "reference" }]
  ), /sms_template_variable_missing/u);
  assert.throws(() => renderApprovedSmsTemplate(
    "ShelfShare: {{unexpected}}.",
    { unexpected: "x" }, []
  ), /sms_template_variable_not_preapproved/u);
  assert.throws(() => renderApprovedSmsTemplate(
    "ShelfShare: code {{ref}}.",
    { ref: "<1234>" }, [{ key: "ref", type: "reference" }]
  ), /sms_template_variable_unsafe/u);
});

test("SMS templates with too many variables or duplicated variable names fail closed", () => {
  const policy = [
    { key: "a", type: "reference"  },
    { key: "b", type: "reference" },
    { key: "c", type: "reference" },
    { key: "d", type: "reference" }
  ];
  assert.throws(() => renderApprovedSmsTemplate("{{a}} {{b}} {{c}} {{d}}", {
    a:"a",b:"b",c:"c",d:"d"
  }, policy), /sms_template_variable_count_invalid/u);
  assert.throws(() => renderApprovedSmsTemplate("{{a}} {{a}}", {a:"a"}, policy),
    /sms_template_variable_count_invalid/u);
});

test("CSV export quotes cells and neutralizes spreadsheet formulas", () => {
  assert.equal(
    buildCsv([{ metric: "=HYPERLINK(1)", note: 'hello, "world"' }], ["metric","note"]),
    "\"metric\",\"note\"\r\n\"'=HYPERLINK(1)\",\"hello, \"\"world\"\"\""
  );
});

test("migration contains restricted delivery, consent, support SLA and finance gates", async () => {
  const migration = await readFile(
    new URL("../../migrations/202610310008_notifications_support_financial_analytics.sql", import.meta.url),
    "utf8"
  );
  assert.match(migration, /sms_service_enabled boolean not null default false/u);
  assert.match(migration, /sms_marketing_enabled boolean not null default false/u);
  assert.match(migration, /notification_delivery_jobs/u);
  assert.match(migration, /run_support_sla_sweep/u);
  assert.match(migration, /finance\.analytics\.read/u);
  assert.match(migration, /get_admin_financial_analytics/u);
  assert.match(migration, /Step-up MFA AAL2/u);
  const hardening = await readFile(new URL("../../migrations/202610310009_operations_hardening.sql", import.meta.url), "utf8");
  const controls = await readFile(new URL("../../migrations/202610310010_operations_controls.sql", import.meta.url), "utf8");
  const contentAndCoverage = await readFile(new URL("../../migrations/202610310011_notification_content_and_event_coverage.sql", import.meta.url), "utf8");
  const backfill = await readFile(new URL("../../migrations/202610310012_notification_backfill_and_resubmission.sql", import.meta.url), "utf8");
  assert.match(hardening, /notification_delivery_job_sendable/u);
  assert.match(controls, /reverse_financial_cost_entry/u);
  assert.match(contentAndCoverage, /collection_pending/u);
  assert.match(backfill, /verification-submitted-reviewer/u);
});

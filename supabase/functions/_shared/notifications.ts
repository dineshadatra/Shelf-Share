export const NOTIFICATION_EVENT_KEYS = [
  "auth.otp",
  "verification.submitted",
  "verification.approved",
  "verification.rejected",
  "listing.approved",
  "listing.rejected",
  "booking.requested",
  "booking.accepted",
  "booking.rejected",
  "payment.succeeded",
  "payment.failed",
  "collection.reminder",
  "handover.confirmed",
  "rental.due_reminder",
  "rental.overdue",
  "extension.requested",
  "return.confirmed",
  "dispute.opened",
  "dispute.updated",
  "refund.updated",
  "payout.updated",
  "referral.rewarded",
  "community.activity",
  "grievance.updated"
] as const;

export type DltVariablePolicy = { key: string; type: "name"|"reference"|"date"|"amount"|"status" };
const TOKEN = /\{\{([a-z][a-z0-9_]*)\}\}/gu;

function safeValue(value: unknown, type: DltVariablePolicy["type"]): string {
  if (typeof value !== "string" && typeof value !== "number") {
    throw new Error("sms_template_variable_missing");
  }
  const result = String(value).trim();
  if (!result || result.length > 48 || /[\r\n<>%$]/u.test(result)) {
    throw new Error("sms_template_variable_unsafe");
  }
  const patterns: Record<DltVariablePolicy["type"], RegExp> = {
    name: /^[\p{L}\p{N} .'-]{1,48}$/u,
    reference: /^[A-Za-z0-9_-]{1,40}$/u,
    date: /^[0-9T:Z+./ -]{1,40}$/u,
    amount: /^[0-9,.₹ ]{1,32}$/u,
    status: /^[\p{L}\p{N} _-]{1,32}$/u
  };
  if (!patterns[type].test(result)) throw new Error("sms_template_variable_type_invalid");
  return result;
}

/**
 * Render only a DLT-registered template. Variable names must be pre-tagged
 * in the template's saved DLT policy; callers cannot supply message text.
 */
export function renderApprovedSmsTemplate(
  template: string,
  payload: Record<string, unknown>,
  policy: DltVariablePolicy[]
): string {
  if (typeof template !== "string" || template.length < 1 || template.length > 1600) {
    throw new Error("sms_template_invalid");
  }
  const tokens = [...template.matchAll(TOKEN)];
  const names = tokens.map(match => match[1]);
  if (names.length > 3 || new Set(names).size !== names.length) {
    throw new Error("sms_template_variable_count_invalid");
  }
  const approved = new Map(policy.map(item => [item.key, item.type]));
  if (approved.size !== policy.length || names.some(name => !approved.has(name) ||
      /(^|_)(otp|code|token|pin|password|secret)(_|$)/iu.test(name))) {
    throw new Error("sms_template_variable_not_preapproved");
  }
  const rendered = template.replace(TOKEN, (_token, name: string) => {
    const type = approved.get(name);
    if (!type) throw new Error("sms_template_variable_not_preapproved");
    return safeValue(payload[name], type);
  });
  if (/\{\{|\}\}/u.test(rendered) || rendered.length > 1600) {
    throw new Error("sms_template_render_failed");
  }
  return rendered;
}

function csvCell(value: unknown): string {
  let text = value === null || value === undefined
    ? ""
    : typeof value === "object" ? JSON.stringify(value) : String(value);
  if (/^[\s]*[=+\-@]/u.test(text)) text = "'" + text;
  return '"' + text.replace(/"/gu, '""') + '"';
}

export function buildCsv(rows: Record<string, unknown>[], fields: string[]): string {
  return [
    fields.map(csvCell).join(","),
    ...rows.map(row => fields.map(field => csvCell(row[field])).join(","))
  ].join("\r\n");
}

import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const sql = await readFile(new URL("../../supabase/migrations/202610300008_verification_listing_gates.sql", import.meta.url), "utf8");

test("listing writes require verified and active owners", () => {
  assert.match(sql, /v.status = 'verified'/);
  assert.match(sql, /p.account_status = 'active'/);
});

test("verification loss and account restriction pause existing listings", () => {
  assert.match(sql, /pause_owner_listings_after_verification_loss/);
  assert.match(sql, /pause_owner_listings_after_account_restriction/);
  assert.match(sql, /listing_status = 'paused'/);
  assert.match(sql, /is_available_for_rent = false/);
});

import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL(path, import.meta.url), "utf8");
const [config, migration, securityMigration, edge, login, register] = await Promise.all([
  read("../../supabase/config.toml"),
  read("../../supabase/migrations/202610300007_authentication_verification.sql"),
  read("../../supabase/migrations/202610300006_security_rls_functions.sql"),
  read("../../supabase/functions/verification-admin/index.ts"),
  read("../../src/pages/login-page.tsx"),
  read("../../src/pages/register-page.tsx")
]);

test("phone authentication is SMS-only and email OTP is not invoked", () => {
  assert.match(login, /signInWithOtp\(\{\s*phone:/);
  assert.match(login, /channel:\s*"sms"/);
  assert.match(login, /verifyOtp\(\{[^}]*type:\s*"sms"/s);
  assert.match(register, /signInWithOtp\(\{\s*phone:/);
  assert.match(register, /channel:\s*"sms"/);
  assert.doesNotMatch(login + register, /signInWithOtp\(\{\s*email:/);
  assert.doesNotMatch(login + register, /verifyOtp\(\{[^}]*type:\s*"email"/s);
});

test("OTP expiry, resend interval and server rate limits are configured", () => {
  assert.match(config, /otp_expiry\s*=\s*300/);
  assert.match(config, /max_frequency\s*=\s*"60s"/);
  assert.match(config, /timebox = "30d"/);
  assert.match(config, /inactivity_timeout = "24h"/);
  assert.match(config, /sms_sent\s*=\s*15/);
  assert.match(config, /sign_in_sign_ups\s*=\s*20/);
  assert.match(config, /token_verifications\s*=\s*10/);
  assert.ok(config.includes("[auth.email]\nenable_signup = false"));
});

test("registration enforces phone verification, age, camera object and accepted legal version server-side", () => {
  const fn = migration.slice(migration.indexOf("create or replace function public.complete_registration"), migration.indexOf("create or replace function public.submit_identity_verification"));
  assert.match(fn, /phone_confirmed_at/);
  assert.match(fn, /p_date_of_birth/);
  assert.match(fn, /interval '18 years'/);
  assert.match(fn, /profile-private/);
  assert.match(fn, /registration_policy_versions/);
  assert.match(fn, /registration_acceptances/);
});

test("identity submission binds evidence to the authenticated user and private bucket", () => {
  const fn = migration.slice(migration.indexOf("create or replace function public.submit_identity_verification"), migration.indexOf("create or replace function public.review_verification_case"));
  assert.match(fn, /auth\.uid\(\)/);
  assert.match(fn, /identity-private/);
  assert.match(fn, /verification-selfie-private/);
  assert.match(fn, /p_case_id/);
  assert.match(fn, /p_document_type not in \('passport','pan','driving_licence'\)/);
  assert.match(fn, /user_verifications/);
  assert.match(fn, /address_evidence/);
});

test("verification status and identity evidence are not browser-writable", () => {
  assert.match(securityMigration, /revoke insert, update, delete, truncate on[\s\S]*public\.user_roles, public\.user_verifications, public\.identity_documents/);
  assert.match(migration, /revoke all on public\.registration_policy_versions,[\s\S]*public\.verification_document_access_audit from anon, authenticated/);
  assert.match(migration, /revoke select, insert, update, delete on public\.identity_documents,[\s\S]*public\.verification_document_access_audit from anon, authenticated/);
});

test("private identity, selfie and profile buckets have no browser read policy", () => {
  assert.match(migration, /'profile-private','profile-private',false/);
  assert.match(migration, /'verification-selfie-private','verification-selfie-private',false/);
  assert.match(securityMigration, /'identity-private','identity-private',false/);
  const profilePolicyArea = migration.slice(migration.indexOf("create policy profile_private_upload_own"), migration.indexOf("-- There are intentionally no SELECT"));
  assert.match(profilePolicyArea, /for insert to authenticated/);
  assert.doesNotMatch(profilePolicyArea, /for select/i);
  assert.doesNotMatch(securityMigration, /create policy .*identity-private.*for select/i);
});

test("admin verification endpoints authenticate staff roles and prevent self review", () => {
  assert.match(edge, /verification_reviewer/);
  assert.match(edge, /auth\.admin\.updateUserById/);
  assert.match(edge, /ban_duration: "876000h"/);
  assert.match(edge, /verification_document_access_audit/);
  assert.match(migration, /v_case\.user_id = v_actor then raise exception 'Reviewers cannot review or approve their own account'/);
  assert.match(migration, /private\.has_role\('verification_reviewer'\)/);
  assert.match(migration, /revoke all on function public\.review_verification_case/);
});

test("private document previews are time-limited and access is audited before the URL is returned", () => {
  assert.match(edge, /createSignedUrl\(file\.object_key, 60\)/);
  const audit = edge.indexOf('from("verification_document_access_audit").insert');
  const response = edge.indexOf('return reply(200, { signed_url: signed.signedUrl');
  assert.ok(audit > -1 && response > audit, "audit entry must be written before the signed URL is returned");
});

test("review transitions require a reason and suspensions invalidate verified status", () => {
  assert.match(migration, /length\(btrim\(p_reason\)\) < 5/);
  assert.match(migration, /status='needs_resubmission'/);
  assert.match(migration, /status='rejected', identity_verified_at=null,[\s\S]*rejection_reason_code='account_suspended'/);
  assert.match(migration, /account_status='suspended'/);
});

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";

const url = Deno.env.get("SUPABASE_URL")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const allowedOrigin = Deno.env.get("APP_ORIGIN") ?? "http://localhost:5173";
const headers = {
  "Access-Control-Allow-Origin": allowedOrigin,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function boundedText(value: unknown, max = 120): string | null {
  if (typeof value !== "string") return null;
  const clean = value.trim();
  return clean ? clean.slice(0, max) : null;
}

function intIn(value: unknown, fallback: number, min: number, max: number): number {
  const n = Number(value);
  return Number.isInteger(n) ? Math.min(max, Math.max(min, n)) : fallback;
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "Request could not be completed";
}

async function signImages(service: SupabaseClient, rows: Record<string, unknown>[], ttl = 300) {
  return await Promise.all(rows.map(async (row) => {
    const keys = Array.isArray(row.images) ? row.images as Record<string, unknown>[] : [];
    const images = await Promise.all(keys.slice(0, 5).map(async (item) => {
      const key = typeof item.object_key === "string" ? item.object_key : "";
      if (!key) return null;
      const { data } = await service.storage.from("book-listing-public").createSignedUrl(key, ttl);
      return data?.signedUrl ? {
        url: data.signedUrl,
        alt_text: item.alt_text ?? null,
        is_cover: item.is_cover === true,
      } : null;
    }));
    const { images: _ignored, ...safe } = row;
    return { ...safe, images: images.filter(Boolean) };
  }));
}

async function getAuthenticatedUser(req: Request) {
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return { user: null, userClient: null, error: "Authentication required" };
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error } = await userClient.auth.getUser();
  if (error || !user) return { user: null, userClient: null, error: "Invalid session" };
  return { user, userClient, error: null };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return reply(405, { error: "Method not allowed" });
  const origin = req.headers.get("origin");
  if (origin && origin !== allowedOrigin) return reply(403, { error: "Origin not allowed" });

  let payload: Record<string, unknown>;
  try { payload = await req.json(); } catch { return reply(400, { error: "Invalid JSON body" }); }
  const action = payload.action;
  const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  if (action === "discover") {
    const filters = payload.filters && typeof payload.filters === "object"
      ? payload.filters as Record<string, unknown> : {};
    const page = intIn(payload.page, 1, 1, 100000);
    const pageSize = intIn(payload.page_size, 12, 1, 24);
    const { data, error } = await service.rpc("search_book_listings", {
      p_filters: filters,
      p_limit: pageSize,
      p_offset: (page - 1) * pageSize,
    });
    if (error) return reply(400, { error: error.message });
    const result = (data ?? {}) as Record<string, unknown>;
    const rows = Array.isArray(result.results) ? result.results as Record<string, unknown>[] : [];
    return reply(200, { ...result, results: await signImages(service, rows, 300) });
  }

  if (action === "check_availability") {
    const copyId = boundedText(payload.copy_id, 64);
    const from = boundedText(payload.available_from, 80);
    const until = boundedText(payload.available_until, 80);
    if (!copyId || !from || !until || !Number.isFinite(Date.parse(from)) || !Number.isFinite(Date.parse(until)) || Date.parse(until) <= Date.parse(from)) {
      return reply(400, { error: "Choose a valid availability date range" });
    }
    const { data: copy } = await service.from("book_copies").select("id,listing_status,is_available_for_rent")
      .eq("id", copyId).maybeSingle();
    if (!copy || copy.listing_status !== "approved" || !copy.is_available_for_rent) {
      return reply(200, { available: false, reason: "This copy is not currently listed as available" });
    }
    const interval = "[" + from + "," + until + ")";
    const [blocks, reservations] = await Promise.all([
      service.from("book_availability_blocks").select("id").eq("book_copy_id", copyId).filter("blocked_period", "ov", interval).limit(1),
      service.from("copy_reservations").select("id,status,expires_at").eq("book_copy_id", copyId).in("status", ["hold", "confirmed", "in_use"]).filter("reserved_period", "ov", interval).limit(10),
    ]);
    if (blocks.error || reservations.error) return reply(500, { error: "Unable to check availability" });
    const activeReservation = (reservations.data ?? []).some((r) => r.status !== "hold" || !r.expires_at || Date.parse(r.expires_at) > Date.now());
    return reply(200, { available: (blocks.data ?? []).length === 0 && !activeReservation });
  }

  if (action === "bundles") {
    const city = boundedText(payload.city, 80);
    const { data, error } = await service.rpc("get_public_book_bundles", { p_city: city });
    if (error) return reply(400, { error: error.message });
    return reply(200, { bundles: data ?? [] });
  }

  const auth = await getAuthenticatedUser(req);
  if (!auth.user || !auth.userClient) return reply(401, { error: auth.error ?? "Authentication required" });
  const user = auth.user;
  const userClient = auth.userClient;

  if (action === "owner_listings") {
    const { data, error } = await userClient.rpc("get_my_book_listings");
    if (error) return reply(400, { error: error.message });
    const rows = Array.isArray(data) ? data as Record<string, unknown>[] : [];
    const signed = await Promise.all(rows.map(async (row) => {
      const images = Array.isArray(row.images) ? row.images as Record<string, unknown>[] : [];
      const signedImages = await Promise.all(images.slice(0, 5).map(async (item) => {
        const key = typeof item.object_key === "string" ? item.object_key : "";
        if (!key) return null;
        const { data: signedData } = await service.storage.from("book-listing-public").createSignedUrl(key, 300);
        return signedData?.signedUrl ? { ...item, url: signedData.signedUrl } : null;
      }));
      return { ...row, images: signedImages.filter(Boolean) };
    }));
    return reply(200, { listings: signed });
  }

  if (action === "my_waitlist") {
    const { data, error } = await userClient.rpc("get_my_book_waitlist");
    if (error) return reply(400, { error: error.message });
    return reply(200, { entries: data ?? [] });
  }

  if (action === "listing_detail") {
    const copyId = boundedText(payload.copy_id, 64);
    if (!copyId) return reply(400, { error: "Listing identifier is required" });
    const { data: copy, error: copyError } = await service.from("book_copies")
      .select("id,owner_id,book_title_id,city_id,locality_id,condition_summary,description,listing_status,is_available_for_rent")
      .eq("id", copyId).eq("listing_status", "approved").eq("is_available_for_rent", true).maybeSingle();
    if (copyError || !copy) return reply(404, { error: "This book is not currently available" });
    const [titleResult, localityResult, priceResult, detailResult, imagesResult, profileResult, verificationResult] = await Promise.all([
      service.from("book_titles").select("id,isbn13,title,subtitle,edition,authors,publisher,language_code,publication_year,description,cover_image_url").eq("id", copy.book_title_id).eq("moderation_status", "approved").maybeSingle(),
      service.from("localities").select("id,name,map_latitude,map_longitude").eq("id", copy.locality_id).maybeSingle(),
      service.from("book_pricing").select("rental_3d_paise,rental_7d_paise,rental_15d_paise,rental_30d_paise,custom_daily_paise,min_custom_days,max_custom_days,currency").eq("book_copy_id", copy.id).is("effective_until", null).maybeSingle(),
      service.from("book_copy_listing_details").select("existing_damage,original_price_paise,requested_deposit_paise,deposit_feature_enabled").eq("book_copy_id", copy.id).maybeSingle(),
      service.from("book_images").select("id,object_key,alt_text,is_cover,display_order").eq("book_copy_id", copy.id).eq("moderation_status", "approved").order("display_order"),
      service.from("profiles").select("display_name,account_status").eq("id", copy.owner_id).maybeSingle(),
      service.from("user_verifications").select("status").eq("user_id", copy.owner_id).maybeSingle(),
    ]);
    if (titleResult.error || !titleResult.data) return reply(404, { error: "Book edition is not available" });
    if (profileResult.data?.account_status !== "active" || verificationResult.data?.status !== "verified") return reply(404, { error: "This book is not currently available" });
    const keys = (imagesResult.data ?? []).map((i) => ({ object_key: i.object_key, alt_text: i.alt_text, is_cover: i.is_cover }));
    const [signed] = await signImages(service, [{ images: keys }]);
    return reply(200, {
      copy: { id: copy.id, owner_id: copy.owner_id, book_title_id: copy.book_title_id, city_id: copy.city_id, locality_id: copy.locality_id, condition: copy.condition_summary, description: copy.description, existing_damage: detailResult.data?.existing_damage ?? "" },
      title: titleResult.data,
      locality: localityResult.data,
      pricing: priceResult.data,
      owner: { display_name: profileResult.data?.display_name ?? "Verified owner", verified: true },
      images: signed.images ?? [],
    });
  }

  const { data: roles, error: roleError } = await service.from("user_roles")
    .select("role").eq("user_id", user.id).is("revoked_at", null);
  if (roleError) return reply(500, { error: "Unable to validate staff permissions" });
  const roleNames = (roles ?? []).map((row) => row.role as string);
  const isModerator = roleNames.some((role) => ["moderator", "admin", "super_admin"].includes(role));
  const isAdmin = roleNames.some((role) => ["admin", "super_admin"].includes(role));

  if (action === "admin_queue" || action === "preview_image" || action === "moderate_listing" || action === "moderate_bundle") {
    if (!isModerator) return reply(403, { error: "Marketplace moderator permission required" });
  }

  if (action === "admin_queue") {
    const { data: copies, error } = await service.from("book_copies")
      .select("id,owner_id,book_title_id,city_id,locality_id,condition_summary,description,listing_status,created_at")
      .in("listing_status", ["pending_review", "approved", "paused"])
      .order("created_at", { ascending: true }).limit(100);
    if (error) return reply(500, { error: "Unable to load listing moderation queue" });
    const ownerIds = [...new Set((copies ?? []).map((x) => x.owner_id))];
    const titleIds = [...new Set((copies ?? []).map((x) => x.book_title_id))];
    const [profiles, titles] = await Promise.all([
      ownerIds.length ? service.from("profiles").select("id,display_name,account_status").in("id", ownerIds) : Promise.resolve({ data: [] }),
      titleIds.length ? service.from("book_titles").select("id,title,authors,isbn13,edition,publisher,moderation_status").in("id", titleIds) : Promise.resolve({ data: [] }),
    ]);
    const profileMap = new Map((profiles.data ?? []).map((p) => [p.id, p]));
    const titleMap = new Map((titles.data ?? []).map((t) => [t.id, t]));
    const queue = await Promise.all((copies ?? []).map(async (copy) => {
      const [images, details, pricing, locality, verification, history] = await Promise.all([
        service.from("book_images").select("id,object_key,alt_text,moderation_status,is_cover,display_order").eq("book_copy_id", copy.id).order("display_order"),
        service.from("book_copy_listing_details").select("existing_damage,original_price_paise,original_price_evidence_note,requested_deposit_paise,ownership_declaration_type").eq("book_copy_id", copy.id).maybeSingle(),
        service.from("book_pricing").select("rental_3d_paise,rental_7d_paise,rental_15d_paise,rental_30d_paise,custom_daily_paise").eq("book_copy_id", copy.id).is("effective_until", null).maybeSingle(),
        service.from("localities").select("name").eq("id", copy.locality_id).maybeSingle(),
        service.from("user_verifications").select("status,age_eligible").eq("user_id", copy.owner_id).maybeSingle(),
        service.from("book_listing_moderation_events").select("id,actor_user_id,action,from_status,to_status,reason,created_at").eq("book_copy_id", copy.id).order("created_at", { ascending: false }).limit(50),
      ]);
      const imageRows = (images.data ?? []).map((image) => ({
        id: image.id, alt_text: image.alt_text, moderation_status: image.moderation_status, is_cover: image.is_cover,
      }));
      return {
        ...copy,
        owner: profileMap.get(copy.owner_id) ?? { display_name: "Member", account_status: "unknown" },
        title: titleMap.get(copy.book_title_id) ?? null,
        locality: locality.data?.name ?? "Unknown locality",
        verification: verification.data ?? null,
        details: details.data ?? null,
        pricing: pricing.data ?? null,
        images: imageRows,
        history: history.data ?? [],
      };
    }));
    return reply(200, { listings: queue, is_admin: isAdmin });
  }

  if (action === "preview_image") {
    const copyId = boundedText(payload.copy_id, 64);
    const imageId = boundedText(payload.image_id, 64);
    const purpose = boundedText(payload.purpose, 500);
    if (!copyId || !imageId || !purpose || purpose.length < 5) return reply(400, { error: "Listing, photo and review purpose are required" });
    const { data: image } = await service.from("book_images").select("id,book_copy_id,object_key")
      .eq("id", imageId).eq("book_copy_id", copyId).maybeSingle();
    if (!image) return reply(404, { error: "Listing photograph not found" });
    const { data: copy } = await service.from("book_copies").select("owner_id").eq("id", copyId).maybeSingle();
    if (!copy || copy.owner_id === user.id) return reply(403, { error: "You cannot review your own listing" });
    const { error: auditError } = await service.from("book_listing_image_access_audit").insert({
      book_copy_id: copyId, book_image_id: imageId, actor_user_id: user.id, purpose,
    });
    if (auditError) return reply(500, { error: "Preview audit could not be recorded; access blocked" });
    const { data: signed, error: signedError } = await service.storage.from("book-listing-public").createSignedUrl(image.object_key, 60);
    if (signedError || !signed?.signedUrl) return reply(500, { error: "Unable to create secure photo preview" });
    return reply(200, { signed_url: signed.signedUrl, expires_in_seconds: 60 });
  }

  if (action === "moderate_listing") {
    const copyId = boundedText(payload.copy_id, 64);
    const decision = boundedText(payload.decision, 20);
    const reason = boundedText(payload.reason, 1000);
    const notes = boundedText(payload.internal_notes, 4000);
    if (!copyId || !decision || !reason || reason.length < 5) return reply(400, { error: "A decision reason of at least five characters is required" });
    const { error } = await userClient.rpc("review_book_listing", {
      p_book_copy_id: copyId, p_action: decision, p_reason: reason, p_internal_notes: notes,
    });
    if (error) return reply(400, { error: error.message });
    return reply(200, { success: true });
  }

  if (action === "moderate_bundle") {
    const bundleId = boundedText(payload.bundle_id, 64);
    const decision = boundedText(payload.decision, 20);
    const reason = boundedText(payload.reason, 1000);
    if (!bundleId || !decision || !reason || reason.length < 5) return reply(400, { error: "A moderation reason is required" });
    const { error } = await userClient.rpc("review_book_bundle", {
      p_bundle_id: bundleId, p_action: decision, p_reason: reason,
    });
    if (error) return reply(400, { error: error.message });
    return reply(200, { success: true });
  }

  return reply(400, { error: "Unsupported catalogue action" });
});

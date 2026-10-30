import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";

const url = Deno.env.get("SUPABASE_URL")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const allowedOrigin = Deno.env.get("APP_ORIGIN") ?? "http://localhost:5173";
let lastIsbnProviderRequestAt = 0;
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

  if (action === "isbn_lookup") {
    const isbn13 = boundedText(payload.isbn13, 13) ?? "";
    if (!/^\d{13}$/.test(isbn13)) return reply(400, { error: "A normalized ISBN-13 is required" });
    const checksum = [...isbn13.slice(0, 12)].reduce((sum, digit, index) => sum + Number(digit) * (index % 2 === 0 ? 1 : 3), 0);
    if (String((10 - (checksum % 10)) % 10) !== isbn13[12]) return reply(400, { error: "ISBN-13 checksum is invalid" });
    const { data: cached } = await service.from("book_metadata_cache").select("metadata,expires_at")
      .eq("isbn13", isbn13).maybeSingle();
    if (cached && Date.parse(cached.expires_at) > Date.now()) return reply(200, cached.metadata as Record<string, unknown>);
    if (Date.now() - lastIsbnProviderRequestAt < 1000) {
      return reply(429, { error: "Please wait a moment before requesting another ISBN lookup. You can still enter the details manually." });
    }
    lastIsbnProviderRequestAt = Date.now();
    const providerUrl = new URL("https://openlibrary.org/api/books");
    providerUrl.searchParams.set("bibkeys", "ISBN:" + isbn13);
    providerUrl.searchParams.set("jscmd", "data");
    providerUrl.searchParams.set("format", "json");
    let response: Response;
    try {
      response = await fetch(providerUrl, {
        headers: { Accept: "application/json", "User-Agent": "ShelfShare/0.1 (+https://github.com/dineshadatra/Shelf-Share)" },
        signal: AbortSignal.timeout(8000),
      });
    } catch {
      return reply(502, { error: "The book metadata provider could not be reached. Enter the book details manually." });
    }
    if (response.status === 404) return reply(404, { error: "No catalogue record was found for this ISBN. Enter the book details manually." });
    if (response.status === 429) return reply(429, { error: "The metadata provider is busy. Please wait or enter the details manually." });
    if (!response.ok) return reply(502, { error: "Book metadata could not be retrieved. Enter the details manually." });
    const body = await response.json() as Record<string, {
      title?: string; authors?: Array<{ name?: string }>; publishers?: Array<{ name?: string }>;
      publish_date?: string; edition_name?: string; languages?: Array<{ key?: string }>;
      cover?: { large?: string; medium?: string; small?: string }; notes?: string | { value?: string };
    }>;
    const book = body["ISBN:" + isbn13];
    if (!book) return reply(404, { error: "No catalogue record was found for this ISBN. Enter the book details manually." });
    const year = book.publish_date?.match(/\b(1[4-9]\d{2}|20\d{2}|21\d{2}|2200)\b/)?.[1] ?? "";
    const languageKey = book.languages?.[0]?.key ?? "";
    const notes = typeof book.notes === "string" ? book.notes : book.notes?.value ?? "";
    const metadata = {
      isbn13, title: book.title ?? "",
      authors: (book.authors ?? []).map((x) => x.name ?? "").filter(Boolean),
      publisher: book.publishers?.[0]?.name ?? "", edition: book.edition_name ?? "",
      publicationYear: year, languageCode: languageKey.split("/").filter(Boolean).pop() ?? "",
      description: notes.slice(0, 4000),
      coverImageUrl: book.cover?.large ?? book.cover?.medium ?? book.cover?.small ?? "",
      metadataSource: "openlibrary", metadataSourceId: isbn13,
    };
    await service.from("book_metadata_cache").upsert({
      isbn13, provider: "openlibrary", metadata, fetched_at: new Date().toISOString(),
      expires_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
    }, { onConflict: "isbn13" });
    return reply(200, metadata);
  }

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
    const safeRows = rows.map((row) => {
      const { requested_deposit_paise: _depositNotPublic, original_price_paise: _purchasePriceNotPublic, ...safe } = row;
      return safe;
    });
    return reply(200, { ...result, results: await signImages(service, safeRows, 300) });
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
    const [entriesResult, notificationsResult] = await Promise.all([
      userClient.rpc("get_my_book_waitlist"),
      userClient.rpc("get_my_book_waitlist_notifications"),
    ]);
    if (entriesResult.error || notificationsResult.error) return reply(400, { error: entriesResult.error?.message ?? notificationsResult.error?.message ?? "Unable to load waitlist" });
    return reply(200, { entries: entriesResult.data ?? [], notifications: notificationsResult.data ?? [] });
  }

  if (action === "owner_bundles") {
    const { data, error } = await userClient.rpc("get_my_book_bundles");
    if (error) return reply(400, { error: error.message });
    return reply(200, { bundles: data ?? [] });
  }

  const { data: roles, error: roleError } = await service.from("user_roles")
    .select("role").eq("user_id", user.id).is("revoked_at", null);
  if (roleError) return reply(500, { error: "Unable to validate staff permissions" });
  const roleNames = (roles ?? []).map((row) => row.role as string);
  const isModerator = roleNames.some((role) => ["moderator", "admin", "super_admin"].includes(role));
  const isAdmin = roleNames.some((role) => ["admin", "super_admin"].includes(role));
  if (action === "moderator_me") return isModerator ? reply(200, { authorized: true }) : reply(403, { error: "Marketplace moderator permission required" });

  if (action === "admin_queue" || action === "admin_bundle_queue" || action === "preview_image" || action === "preview_price_evidence" || action === "moderate_listing" || action === "moderate_bundle") {
    if (!isModerator) return reply(403, { error: "Marketplace moderator permission required" });
  }

  if (action === "admin_bundle_queue") {
    const { data: rows, error } = await service.from("book_bundles")
      .select("id,owner_id,city_id,name,description,status,created_at")
      .in("status", ["pending_review", "approved", "paused"])
      .order("created_at", { ascending: true }).limit(100);
    if (error) return reply(500, { error: "Unable to load bundle moderation queue" });
    const owners = [...new Set((rows ?? []).map((row) => row.owner_id))];
    const cities = [...new Set((rows ?? []).map((row) => row.city_id))];
    const [profiles, cityRows] = await Promise.all([
      owners.length ? service.from("profiles").select("id,display_name,account_status").in("id", owners) : Promise.resolve({ data: [] }),
      cities.length ? service.from("cities").select("id,name").in("id", cities) : Promise.resolve({ data: [] }),
    ]);
    const profileMap = new Map((profiles.data ?? []).map((row) => [row.id, row]));
    const cityMap = new Map((cityRows.data ?? []).map((row) => [row.id, row.name]));
    const bundles = await Promise.all((rows ?? []).map(async (bundle) => {
      const [items, history] = await Promise.all([
        service.from("book_bundle_items").select("book_copy_id,display_order").eq("bundle_id", bundle.id).order("display_order"),
        service.from("book_bundle_moderation_events").select("id,actor_user_id,action,from_status,to_status,reason,created_at").eq("bundle_id", bundle.id).order("created_at", { ascending: false }).limit(50),
      ]);
      const copyIds = (items.data ?? []).map((item) => item.book_copy_id);
      const copies = copyIds.length ? await service.from("book_copies").select("id,listing_status,is_available_for_rent,book_title_id").in("id", copyIds) : { data: [] };
      const titleIds = [...new Set((copies.data ?? []).map((copy) => copy.book_title_id))];
      const titles = titleIds.length ? await service.from("book_titles").select("id,title,authors").in("id", titleIds) : { data: [] };
      const titleMap = new Map((titles.data ?? []).map((title) => [title.id, title]));
      const copyMap = new Map((copies.data ?? []).map((copy) => [copy.id, copy]));
      return {
        ...bundle,
        owner: profileMap.get(bundle.owner_id) ?? { display_name: "Member", account_status: "unknown" },
        city: cityMap.get(bundle.city_id) ?? "Unknown city",
        items: copyIds.map((copyId) => {
          const copy = copyMap.get(copyId);
          return { copy_id: copyId, status: copy?.listing_status ?? "unknown", available: copy?.is_available_for_rent === true, title: copy ? titleMap.get(copy.book_title_id) ?? null : null };
        }),
        history: history.data ?? [],
      };
    }));
    return reply(200, { bundles });
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
        service.from("book_copy_listing_details").select("existing_damage,original_price_paise,original_price_evidence_note,original_price_evidence_key,requested_deposit_paise,ownership_declaration_type").eq("book_copy_id", copy.id).maybeSingle(),
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
        details: details.data ? { existing_damage: details.data.existing_damage, original_price_paise: details.data.original_price_paise, original_price_evidence_note: details.data.original_price_evidence_note, requested_deposit_paise: details.data.requested_deposit_paise, ownership_declaration_type: details.data.ownership_declaration_type, has_original_price_evidence: Boolean(details.data.original_price_evidence_key) } : null,
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

  if (action === "preview_price_evidence") {
    const copyId = boundedText(payload.copy_id, 64);
    const purpose = boundedText(payload.purpose, 500);
    if (!copyId || !purpose || purpose.length < 5) return reply(400, { error: "Listing and review purpose are required" });
    const { data: copy } = await service.from("book_copies").select("owner_id").eq("id", copyId).maybeSingle();
    const { data: details } = await service.from("book_copy_listing_details").select("original_price_evidence_key").eq("book_copy_id", copyId).maybeSingle();
    const objectKey = details?.original_price_evidence_key;
    if (!copy || !objectKey) return reply(404, { error: "Original-price evidence not found" });
    if (copy.owner_id === user.id) return reply(403, { error: "You cannot review your own listing evidence" });
    const { error: auditError } = await service.from("book_listing_evidence_access_audit").insert({ book_copy_id: copyId, actor_user_id: user.id, purpose });
    if (auditError) return reply(500, { error: "Evidence access audit could not be recorded; preview blocked" });
    const { data: signed, error: signedError } = await service.storage.from("listing-evidence-private").createSignedUrl(objectKey, 60);
    if (signedError || !signed?.signedUrl) return reply(500, { error: "Unable to create secure evidence preview" });
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

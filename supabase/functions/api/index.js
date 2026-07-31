import { createClient } from "npm:@supabase/supabase-js@^2.95.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

const TABLES = new Set([
  "profiles", "branches", "room_types", "rooms", "room_images", "bookings",
]);
const RPCS = new Set([
  "search_available_rooms", "create_booking", "cancel_own_booking",
  "admin_update_booking_status", "admin_update_payment_status",
  "admin_set_profile_role", "admin_set_profile_status",
]);
const PUBLIC_RPCS = new Set(["search_available_rooms"]);
const FUNCTIONS = new Set(["recommend-rooms"]);
const IDENTIFIER = /^[a-z_][a-z0-9_]*(?:\.[a-z_][a-z0-9_]*)?$/;
const SELECT_EXPRESSION = /^[a-zA-Z0-9_.*(),!:\s]+$/;

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function fail(message, status = 400, code = "bad_request") {
  return json({ data: null, error: { message, code } }, status);
}

function env(name) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing server environment variable: ${name}`);
  return value;
}

function bearer(req) {
  const match = req.headers.get("Authorization")?.match(/^Bearer\s+(\S+)$/i);
  return match?.[1] || null;
}

function publicClient() {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function userClient(token) {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: token ? { Authorization: `Bearer ${token}` } : {} },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function requireUser(req) {
  const token = bearer(req);
  if (!token) return { error: fail("Authentication required.", 401, "unauthorized") };
  const client = userClient(token);
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) {
    return { error: fail("Invalid or expired JWT.", 401, "invalid_jwt") };
  }
  return { token, user: data.user, client };
}

function validIdentifier(value) {
  return typeof value === "string" && IDENTIFIER.test(value);
}

async function authRoute(path, body, req) {
  const client = publicClient();

  if (path === "/auth/register") {
    if (typeof body.email !== "string" || typeof body.password !== "string") {
      return fail("Email and password are required.");
    }
    const metadata = body.options?.data || {};
    // Authority fields are never accepted from a registration request.
    const safeMetadata = {
      full_name: typeof metadata.full_name === "string" ? metadata.full_name.trim() : "",
      phone: typeof metadata.phone === "string" ? metadata.phone.trim() : "",
    };
    const result = await client.auth.signUp({
      email: body.email.trim(),
      password: body.password,
      options: { data: safeMetadata },
    });
    return json(result, result.error ? 400 : 200);
  }

  if (path === "/auth/login") {
    if (typeof body.email !== "string" || typeof body.password !== "string") {
      return fail("Email and password are required.");
    }
    const result = await client.auth.signInWithPassword({
      email: body.email.trim(),
      password: body.password,
    });
    return json(result, result.error ? 401 : 200);
  }

  if (path === "/auth/refresh") {
    if (typeof body.refresh_token !== "string" || body.refresh_token.length < 20) {
      return fail("A valid refresh token is required.");
    }
    const result = await client.auth.refreshSession({
      refresh_token: body.refresh_token,
    });
    return json(result, result.error ? 401 : 200);
  }

  const auth = await requireUser(req);
  if (auth.error) return auth.error;
  if (path === "/auth/session") return json({ data: { user: auth.user }, error: null });
  if (path === "/auth/logout") {
    const result = await auth.client.auth.signOut();
    return json(result, result.error ? 400 : 200);
  }
  return fail("Unknown auth endpoint.", 404, "not_found");
}

async function queryRoute(body, req) {
  if (!TABLES.has(body.table)) return fail("Table is not exposed by this API.", 403);
  if (!["select", "insert", "update", "delete"].includes(body.operation)) {
    return fail("Unsupported query operation.");
  }
  if (typeof body.columns !== "string" || !SELECT_EXPRESSION.test(body.columns)) {
    return fail("Invalid select expression.");
  }
  if (!Array.isArray(body.filters) || !Array.isArray(body.orders)) {
    return fail("Invalid query shape.");
  }
  if (body.filters.some((f) =>
    !["eq", "neq", "gte", "in"].includes(f.operator) || !validIdentifier(f.column) ||
    (f.operator === "in" && !Array.isArray(f.value)))) {
    return fail("Invalid filter.");
  }
  if (body.orders.some((o) => !validIdentifier(o.column) ||
      typeof o.ascending !== "boolean")) {
    return fail("Invalid ordering.");
  }
  if (body.limit !== undefined &&
      (!Number.isSafeInteger(body.limit) || body.limit < 1 || body.limit > 1000)) {
    return fail("Invalid limit.");
  }

  const token = bearer(req);
  const client = userClient(token);
  let query;
  if (body.operation === "select") {
    query = client.from(body.table).select(body.columns, body.selectOptions || {});
  } else {
    const auth = await requireUser(req);
    if (auth.error) return auth.error;
    query = body.operation === "insert"
      ? auth.client.from(body.table).insert(body.values)
      : body.operation === "update"
        ? auth.client.from(body.table).update(body.values)
        : auth.client.from(body.table).delete();
    if (body.returning) query = query.select(body.columns);
  }
  for (const filter of body.filters) query = query[filter.operator](filter.column, filter.value);
  for (const order of body.orders) query = query.order(order.column, { ascending: order.ascending });
  if (body.limit) query = query.limit(body.limit);
  if (body.resultMode === "single") query = query.single();
  if (body.resultMode === "maybeSingle") query = query.maybeSingle();

  const result = await query;
  return json(result, result.error ? 400 : 200);
}

async function rpcRoute(body, req) {
  if (!RPCS.has(body.name)) return fail("RPC is not exposed by this API.", 403);
  let client = userClient(bearer(req));
  if (!PUBLIC_RPCS.has(body.name)) {
    const auth = await requireUser(req);
    if (auth.error) return auth.error;
    client = auth.client;
  }
  const result = await client.rpc(body.name, body.args || {});
  return json(result, result.error ? 400 : 200);
}

async function functionRoute(body, req) {
  if (!FUNCTIONS.has(body.name)) return fail("Function is not exposed by this API.", 403);
  const token = bearer(req);
  const response = await fetch(`${env("SUPABASE_URL")}/functions/v1/${body.name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "apikey": env("SUPABASE_ANON_KEY"),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body.body || {}),
  });
  const payload = await response.json();
  return json(response.ok
    ? { data: payload, error: null }
    : { data: null, error: payload.error || { message: "Function request failed." } },
  response.status);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("Method not allowed.", 405);

  try {
    const path = new URL(req.url).pathname.replace(/^\/api/, "") || "/";
    const body = await req.json();
    if (path.startsWith("/auth/")) return await authRoute(path, body, req);
    if (path === "/query") return await queryRoute(body, req);
    if (path === "/rpc") return await rpcRoute(body, req);
    if (path === "/function") return await functionRoute(body, req);
    return fail("Endpoint not found.", 404, "not_found");
  } catch (error) {
    console.error(error);
    return fail("Internal server error.", 500, "internal_error");
  }
});

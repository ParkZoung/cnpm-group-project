import { fail, json } from "../../_shared/response.js";
import { env } from "../config/environment.js";
import { bearer } from "../middleware/authentication.js";

const FUNCTIONS = new Set(["recommend-rooms"]);

export async function handleFunction(body, req) {
  if (!FUNCTIONS.has(body.name)) return fail("Function is not exposed by this API.", 403);
  const token = bearer(req);
  const response = await fetch(`${env("SUPABASE_URL")}/functions/v1/${body.name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: env("SUPABASE_ANON_KEY"),
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

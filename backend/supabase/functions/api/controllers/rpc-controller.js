import { fail, json } from "../../_shared/response.js";
import { bearer, requireUser } from "../middleware/authentication.js";
import { userClient } from "../repositories/supabase-repository.js";

const RPCS = new Set([
  "search_available_rooms", "create_booking", "cancel_own_booking",
  "admin_update_booking_status", "admin_update_payment_status",
  "admin_set_profile_role", "admin_set_profile_status",
]);
const PUBLIC_RPCS = new Set(["search_available_rooms"]);

export async function handleRpc(body, req) {
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

import { fail, json } from "../../_shared/response.js";
import { bearer, requireUser } from "../middleware/authentication.js";
import { userClient } from "../repositories/supabase-repository.js";

const RPCS = new Set([
  "search_available_rooms", "create_booking", "cancel_own_booking",
  "admin_update_booking_status", "admin_update_payment_status",
  "admin_set_profile_role", "admin_set_profile_status",
  "customer_start_online_checkin", "customer_claim_online_payment",
  "staff_confirm_booking", "staff_review_online_payment",
  "staff_lookup_checkin_token", "staff_consume_checkin_token",
  "staff_collect_balance", "staff_check_in", "staff_check_out",
  "staff_record_refund", "staff_select_working_branch", "admin_assign_profile_access",
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

import { fail, json } from "../../_shared/response.js";
import { bearer, requireUser } from "../middleware/authentication.js";
import { userClient } from "../repositories/supabase-repository.js";
import { validateQuery } from "../validators/query-validator.js";

const TABLES = new Set([
  "profiles", "branches", "room_types", "room_classes", "rooms", "room_images", "bookings",
  "amenities", "room_amenities", "online_checkins", "payment_transactions",
]);

export async function handleQuery(body, req) {
  if (!TABLES.has(body.table)) return fail("Table is not exposed by this API.", 403);
  const validationError = validateQuery(body);
  if (validationError) return fail(validationError);

  let client = userClient(bearer(req));
  let query;
  if (body.operation === "select") {
    query = client.from(body.table).select(body.columns, body.selectOptions || {});
  } else {
    const auth = await requireUser(req);
    if (auth.error) return auth.error;
    client = auth.client;
    query = body.operation === "insert"
      ? client.from(body.table).insert(body.values)
      : body.operation === "update"
        ? client.from(body.table).update(body.values)
        : client.from(body.table).delete();
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

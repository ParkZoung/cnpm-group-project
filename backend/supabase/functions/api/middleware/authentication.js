import { fail } from "../../_shared/response.js";
import { userClient } from "../repositories/supabase-repository.js";

export function bearer(req) {
  const match = req.headers.get("Authorization")?.match(/^Bearer\s+(\S+)$/i);
  return match?.[1] || null;
}

export async function requireUser(req) {
  const token = bearer(req);
  if (!token) return { error: fail("Authentication required.", 401, "unauthorized") };
  const client = userClient(token);
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) {
    return { error: fail("Invalid or expired JWT.", 401, "invalid_jwt") };
  }
  return { token, user: data.user, client };
}

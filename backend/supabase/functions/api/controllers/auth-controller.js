import { fail, json } from "../../_shared/response.js";
import { env } from "../config/environment.js";
import { requireUser } from "../middleware/authentication.js";
import { publicClient } from "../repositories/supabase-repository.js";

function validRedirectUrl(value) {
  if (typeof value !== "string") return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" || url.hostname === "localhost" || url.hostname === "127.0.0.1"
      ? url.toString()
      : null;
  } catch (_) {
    return null;
  }
}

export async function handleAuth(path, body, req) {
  const client = publicClient();

  if (path === "/auth/register") {
    if (typeof body.email !== "string" || typeof body.password !== "string") {
      return fail("Email and password are required.");
    }
    const metadata = body.options?.data || {};
    const result = await client.auth.signUp({
      email: body.email.trim(),
      password: body.password,
      options: {
        data: {
          full_name: typeof metadata.full_name === "string" ? metadata.full_name.trim() : "",
          phone: typeof metadata.phone === "string" ? metadata.phone.trim() : "",
        },
        emailRedirectTo: validRedirectUrl(body.options?.emailRedirectTo) || undefined,
      },
    });
    return json(result, result.error ? 400 : 200);
  }

  if (path === "/auth/oauth") {
    if (body.provider !== "google") return fail("Unsupported OAuth provider.");
    const redirectTo = validRedirectUrl(body.options?.redirectTo);
    if (!redirectTo) return fail("A valid OAuth redirect URL is required.");
    const result = await client.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo, skipBrowserRedirect: true },
    });
    return json(result, result.error ? 400 : 200);
  }

  if (path === "/auth/login") {
    if (typeof body.email !== "string" || typeof body.password !== "string") {
      return fail("Email and password are required.");
    }
    const result = await client.auth.signInWithPassword({
      email: body.email.trim(), password: body.password,
    });
    return json(result, result.error ? 401 : 200);
  }

  if (path === "/auth/recovery/request") {
    if (typeof body.email !== "string" || !body.email.includes("@")) {
      return fail("A valid email is required.");
    }
    const result = await client.auth.resetPasswordForEmail(body.email.trim(), {
      redirectTo: validRedirectUrl(body.redirectTo) || undefined,
    });
    return json(result, result.error ? 400 : 200);
  }

  if (path === "/auth/recovery/verify") {
    const email = typeof body.email === "string" ? body.email.trim() : "";
    const token = typeof body.token === "string" ? body.token.trim() : "";
    if (!email.includes("@") || !/^\d{6}$/.test(token)) {
      return fail("A valid email and 6-digit OTP are required.");
    }
    const result = await client.auth.verifyOtp({ email, token, type: "recovery" });
    return json(result, result.error ? 400 : 200);
  }

  if (path === "/auth/refresh") {
    if (typeof body.refresh_token !== "string" || body.refresh_token.length < 20) {
      return fail("A valid refresh token is required.");
    }
    const result = await client.auth.refreshSession({ refresh_token: body.refresh_token });
    return json(result, result.error ? 401 : 200);
  }

  const auth = await requireUser(req);
  if (auth.error) return auth.error;

  if (path === "/auth/recovery/update") {
    if (typeof body.password !== "string" || body.password.length < 8) {
      return fail("Password must contain at least 8 characters.");
    }
    const response = await fetch(`${env("SUPABASE_URL")}/auth/v1/user`, {
      method: "PUT",
      headers: {
        apikey: env("SUPABASE_ANON_KEY"),
        Authorization: `Bearer ${auth.token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ password: body.password }),
    });
    const payload = await response.json();
    if (!response.ok) {
      return json({ data: null, error: {
        message: payload?.msg || payload?.message || "Unable to update password.",
        code: payload?.code || "password_update_failed",
      } }, response.status);
    }
    return json({ data: { user: payload }, error: null });
  }
  if (path === "/auth/session") return json({ data: { user: auth.user }, error: null });
  if (path === "/auth/logout") {
    const result = await auth.client.auth.signOut();
    return json(result, result.error ? 400 : 200);
  }
  return fail("Unknown auth endpoint.", 404, "not_found");
}

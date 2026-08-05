import { corsHeaders, fail } from "../_shared/response.js";
import { handleAuth } from "./controllers/auth-controller.js";
import { handleFunction } from "./controllers/function-controller.js";
import { handleQuery } from "./controllers/query-controller.js";
import { handleRpc } from "./controllers/rpc-controller.js";
import { handleRoomImage } from "./controllers/room-image-controller.js";
import { handleVietQr } from "./controllers/vietqr-controller.js";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("Method not allowed.", 405);

  try {
    const path = new URL(req.url).pathname.replace(/^\/api/, "") || "/";
    const body = await req.json();
    if (path.startsWith("/auth/")) return await handleAuth(path, body, req);
    if (path === "/query") return await handleQuery(body, req);
    if (path === "/rpc") return await handleRpc(body, req);
    if (path === "/room-image") return await handleRoomImage(body, req);
    if (path === "/vietqr") return await handleVietQr(body, req);
    if (path === "/function") return await handleFunction(body, req);
    return fail("Endpoint not found.", 404, "not_found");
  } catch (error) {
    console.error(error);
    return fail("Internal server error.", 500, "internal_error");
  }
});

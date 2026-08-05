import { fail, json } from "../../_shared/response.js";
import { requireUser } from "../middleware/authentication.js";

const BUCKET = "room-images";
const MIME_EXTENSIONS = new Map([
  ["image/jpeg", "jpg"], ["image/png", "png"], ["image/webp", "webp"],
]);

export async function handleRoomImage(body, req) {
  const auth = await requireUser(req);
  if (auth.error) return auth.error;

  const { data: profile } = await auth.client
    .from("profiles").select("role").eq("id", auth.user.id).maybeSingle();
  if (profile?.role !== "admin") return fail("Admin access required.", 403);

  const roomId = Number(body.roomId);
  if (!Number.isSafeInteger(roomId) || roomId <= 0) return fail("Invalid room id.");

  const { data: room } = await auth.client.from("rooms").select("id").eq("id", roomId).maybeSingle();
  if (!room) return fail("Room not found.", 404);

  const { data: currentImages } = await auth.client
    .from("room_images").select("id,image_url").eq("room_id", roomId).eq("is_primary", true);

  if (body.action === "delete") {
    const { error } = await auth.client.from("room_images").delete().eq("room_id", roomId);
    if (error) return json({ data: null, error }, 400);
    await removeStoredImages(auth.client, currentImages || []);
    return json({ data: { deleted: true }, error: null });
  }

  const mimeType = String(body.mimeType || "").toLowerCase();
  const extension = MIME_EXTENSIONS.get(mimeType);
  const base64 = String(body.base64 || "");
  if (!extension || !base64) return fail("Only JPG, PNG and WebP images are supported.");

  let bytes;
  try {
    bytes = Uint8Array.from(atob(base64), character => character.charCodeAt(0));
  } catch (_) {
    return fail("Invalid image data.");
  }
  if (bytes.byteLength > 5 * 1024 * 1024) return fail("Image must not exceed 5 MB.");

  const path = `${roomId}/${crypto.randomUUID()}.${extension}`;
  const upload = await auth.client.storage.from(BUCKET).upload(path, bytes, {
    contentType: mimeType, upsert: false,
  });
  if (upload.error) return json({ data: null, error: upload.error }, 400);

  const publicUrl = auth.client.storage.from(BUCKET).getPublicUrl(path).data.publicUrl;
  await auth.client.from("room_images").update({ is_primary: false }).eq("room_id", roomId);
  const inserted = await auth.client.from("room_images").insert({
    room_id: roomId,
    image_url: publicUrl,
    alt_text: String(body.altText || "Ảnh phòng GoStay").slice(0, 250),
    is_primary: true,
    sort_order: 0,
  }).select("id,image_url").single();
  if (inserted.error) {
    await auth.client.storage.from(BUCKET).remove([path]);
    return json({ data: null, error: inserted.error }, 400);
  }
  await removeStoredImages(auth.client, currentImages || []);
  return json({ data: inserted.data, error: null });
}

async function removeStoredImages(client, images) {
  const marker = `/storage/v1/object/public/${BUCKET}/`;
  const paths = images.map(image => {
    const index = String(image.image_url || "").indexOf(marker);
    return index >= 0 ? decodeURIComponent(String(image.image_url).slice(index + marker.length)) : null;
  }).filter(Boolean);
  if (paths.length) await client.storage.from(BUCKET).remove(paths);
}

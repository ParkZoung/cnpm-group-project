import { fail, json } from "../../_shared/response.js";
import { requireUser } from "../middleware/authentication.js";

const BUCKET = "room-images";
const MAX_FILE_BYTES = 5 * 1024 * 1024;
const MIME_EXTENSIONS = new Map([
  ["image/jpeg", "jpg"], ["image/png", "png"], ["image/webp", "webp"],
]);

async function requireAdmin(req) {
  const auth = await requireUser(req);
  if (auth.error) return auth;
  const { data: profile, error } = await auth.client.from("profiles")
    .select("role, status").eq("id", auth.user.id).maybeSingle();
  if (error || !profile || profile.role !== "admin" || profile.status !== "active") {
    return { error: fail("Active administrator access is required.", 403, "forbidden") };
  }
  return auth;
}

function decodeBase64(value) {
  try {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
    return bytes;
  } catch (_) { return null; }
}

function matchesImageSignature(bytes, mimeType) {
  if (mimeType === "image/jpeg") return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  if (mimeType === "image/png") {
    return bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47;
  }
  if (mimeType === "image/webp") {
    return String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" &&
      String.fromCharCode(...bytes.slice(8, 12)) === "WEBP";
  }
  return false;
}

function objectPathFromPublicUrl(url) {
  try {
    const pathname = new URL(url).pathname;
    const marker = `/storage/v1/object/public/${BUCKET}/`;
    const index = pathname.indexOf(marker);
    return index === -1 ? null : decodeURIComponent(pathname.slice(index + marker.length));
  } catch (_) { return null; }
}

export async function handleRoomImage(body, req) {
  const auth = await requireAdmin(req);
  if (auth.error) return auth.error;
  if (!body || typeof body !== "object") return fail("Invalid room image request.");
  if (body.action === "upload") return uploadRoomImage(body, auth.client);
  if (body.action === "delete") return deleteRoomImage(body, auth.client);
  return fail("Unsupported room image action.");
}

async function uploadRoomImage(body, client) {
  const roomId = Number(body.roomId);
  const extension = MIME_EXTENSIONS.get(body.mimeType);
  if (!Number.isSafeInteger(roomId) || roomId < 1) return fail("Invalid room id.");
  if (!extension) return fail("Only JPG, PNG, and WebP images are supported.");
  if (typeof body.base64 !== "string" || !body.base64) return fail("Image data is required.");
  if (body.base64.length > Math.ceil(MAX_FILE_BYTES / 3) * 4 + 4) {
    return fail("Each image must not exceed 5 MB.");
  }
  const bytes = decodeBase64(body.base64);
  if (!bytes?.length) return fail("Invalid image data.");
  if (bytes.length > MAX_FILE_BYTES) return fail("Each image must not exceed 5 MB.");
  if (!matchesImageSignature(bytes, body.mimeType)) return fail("The file content does not match its image type.");

  const { data: room, error: roomError } = await client.from("rooms")
    .select("id, name").eq("id", roomId).maybeSingle();
  if (roomError || !room) return fail("Room was not found.", 404, "not_found");
  const { data: existing, error: readError } = await client.from("room_images")
    .select("id, sort_order").eq("room_id", roomId)
    .order("sort_order", { ascending: false }).limit(1);
  if (readError) return fail("Could not read the room image list.", 400);

  const objectPath = `${roomId}/${crypto.randomUUID()}.${extension}`;
  const { error: uploadError } = await client.storage.from(BUCKET)
    .upload(objectPath, bytes, { contentType: body.mimeType, upsert: false });
  if (uploadError) return fail(`Image upload failed: ${uploadError.message}`, 400);
  const { data: urlData } = client.storage.from(BUCKET).getPublicUrl(objectPath);
  const firstImage = !existing?.length;
  const { data: image, error: insertError } = await client.from("room_images").insert({
    room_id: roomId,
    image_url: urlData.publicUrl,
    alt_text: String(body.altText || room.name || "Room image").trim().slice(0, 255),
    is_primary: firstImage,
    sort_order: firstImage ? 0 : Number(existing[0].sort_order || 0) + 1,
  }).select("id, room_id, image_url, alt_text, is_primary, sort_order").single();
  if (insertError) {
    await client.storage.from(BUCKET).remove([objectPath]);
    return fail(`Could not save image information: ${insertError.message}`, 400);
  }
  return json({ data: image, error: null }, 201);
}

async function deleteRoomImage(body, client) {
  const imageId = Number(body.imageId);
  if (!Number.isSafeInteger(imageId) || imageId < 1) return fail("Invalid image id.");
  const { data: image, error } = await client.from("room_images")
    .select("id, room_id, image_url, is_primary").eq("id", imageId).maybeSingle();
  if (error || !image) return fail("Room image was not found.", 404, "not_found");
  const path = objectPathFromPublicUrl(image.image_url);
  if (path) {
    const { error: storageError } = await client.storage.from(BUCKET).remove([path]);
    if (storageError) return fail(`Could not delete the stored image: ${storageError.message}`, 400);
  }
  const { error: deleteError } = await client.from("room_images").delete().eq("id", imageId);
  if (deleteError) return fail(`Could not delete image information: ${deleteError.message}`, 400);
  if (image.is_primary) {
    const { data: replacements } = await client.from("room_images").select("id")
      .eq("room_id", image.room_id).order("sort_order", { ascending: true }).limit(1);
    if (replacements?.[0]) {
      await client.from("room_images").update({ is_primary: true }).eq("id", replacements[0].id);
    }
  }
  return json({ data: { id: imageId }, error: null });
}

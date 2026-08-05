/* Storage bucket for room photos uploaded by active administrators. */
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('room-images', 'room-images', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE
SET public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS room_images_storage_admin_insert ON storage.objects;
CREATE POLICY room_images_storage_admin_insert ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'room-images' AND public.is_admin());

DROP POLICY IF EXISTS room_images_storage_admin_delete ON storage.objects;
CREATE POLICY room_images_storage_admin_delete ON storage.objects
FOR DELETE TO authenticated
USING (bucket_id = 'room-images' AND public.is_admin());

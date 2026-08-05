DROP POLICY IF EXISTS room_images_storage_admin_delete ON storage.objects;
DROP POLICY IF EXISTS room_images_storage_admin_insert ON storage.objects;

/* Stop if objects still exist; uploaded files must not be silently destroyed. */
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id = 'room-images') THEN
    RAISE EXCEPTION 'Room image storage rollback stopped: the bucket still contains objects.';
  END IF;
END
$$;

DELETE FROM storage.buckets WHERE id = 'room-images';

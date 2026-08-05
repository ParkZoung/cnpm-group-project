BEGIN;

CREATE OR REPLACE FUNCTION public.staff_confirm_booking(p_booking_id uuid)
RETURNS TABLE(booking_id uuid, booking_status character varying)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.can_manage_booking(p_booking_id) THEN
    RAISE EXCEPTION 'Staff authorization required.' USING ERRCODE = '42501';
  END IF;

  UPDATE public.bookings AS booking
  SET booking_status = 'confirmed'
  WHERE booking.id = p_booking_id
    AND booking.booking_status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Booking cannot be confirmed.' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY SELECT p_booking_id, 'confirmed'::character varying;
END;
$$;

ALTER FUNCTION public.staff_confirm_booking(uuid) OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.staff_confirm_booking(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.staff_confirm_booking(uuid) TO authenticated;

COMMIT;

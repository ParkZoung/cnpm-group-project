BEGIN;

-- Preserve pooled room inventory while making create_booking idempotent for an
-- identical active stay submitted concurrently by the same customer.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.bookings
    WHERE booking_status IN ('pending', 'confirmed', 'checked_in')
    GROUP BY user_id, room_id, check_in_date, check_out_date
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Cannot install duplicate-booking guard: active duplicates require review.';
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS bookings_customer_active_stay_unique
  ON public.bookings (user_id, room_id, check_in_date, check_out_date)
  WHERE booking_status IN ('pending', 'confirmed', 'checked_in');

COMMIT;

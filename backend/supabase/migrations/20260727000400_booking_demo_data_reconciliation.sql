BEGIN;

/*
 * Booking demo-data reconciliation
 *
 * The project owner explicitly confirmed that all three existing rows in
 * public.bookings are disposable demo data. Ownership must not be inferred or
 * assigned to any Auth user. This migration therefore removes those rows only
 * after the reviewed preflight state is reproduced exactly.
 *
 * ACCESS EXCLUSIVE prevents a concurrent insert, update, or delete from
 * changing the reviewed counts between the precondition and the DELETE.
 */
LOCK TABLE public.bookings IN ACCESS EXCLUSIVE MODE;

DO $precondition$
DECLARE
  booking_count bigint;
  ownerless_booking_count bigint;
  overlapping_pair_count bigint;
  affected_room_count bigint;
BEGIN
  SELECT count(*)
  INTO booking_count
  FROM public.bookings;

  SELECT count(*)
  INTO ownerless_booking_count
  FROM public.bookings AS booking
  WHERE booking.user_id IS NULL;

  SELECT
    count(*),
    count(DISTINCT overlap.room_id)
  INTO
    overlapping_pair_count,
    affected_room_count
  FROM (
    SELECT left_booking.room_id
    FROM public.bookings AS left_booking
    JOIN public.bookings AS right_booking
      ON left_booking.id < right_booking.id
     AND left_booking.room_id = right_booking.room_id
     AND left_booking.booking_status IN (
       'pending',
       'confirmed',
       'checked_in'
     )
     AND right_booking.booking_status IN (
       'pending',
       'confirmed',
       'checked_in'
     )
     AND left_booking.check_in_date IS NOT NULL
     AND left_booking.check_out_date IS NOT NULL
     AND right_booking.check_in_date IS NOT NULL
     AND right_booking.check_out_date IS NOT NULL
     AND left_booking.check_out_date > left_booking.check_in_date
     AND right_booking.check_out_date > right_booking.check_in_date
     AND daterange(
       left_booking.check_in_date,
       left_booking.check_out_date,
       '[)'
     ) && daterange(
       right_booking.check_in_date,
       right_booking.check_out_date,
       '[)'
     )
  ) AS overlap;

  IF booking_count <> 3 THEN
    RAISE EXCEPTION
      'Booking demo-data reconciliation stopped: expected exactly 3 bookings, found %.',
      booking_count;
  END IF;

  IF ownerless_booking_count <> 3 THEN
    RAISE EXCEPTION
      'Booking demo-data reconciliation stopped: expected all 3 bookings to have NULL user_id, found % ownerless rows.',
      ownerless_booking_count;
  END IF;

  IF overlapping_pair_count <> 1 THEN
    RAISE EXCEPTION
      'Booking demo-data reconciliation stopped: expected exactly 1 holding-status overlapping pair, found %.',
      overlapping_pair_count;
  END IF;

  IF affected_room_count <> 1 THEN
    RAISE EXCEPTION
      'Booking demo-data reconciliation stopped: expected exactly 1 room affected by overlap, found %.',
      affected_room_count;
  END IF;
END;
$precondition$;

/*
 * DELETE is intentional. It runs normal row deletion semantics, preserves
 * trigger/FK enforcement, and does not use TRUNCATE's broader table-level
 * behavior. Only the three owner-confirmed demo rows may reach this statement.
 */
DELETE FROM public.bookings;

DO $postcondition$
DECLARE
  booking_count bigint;
  ownerless_booking_count bigint;
  overlapping_pair_count bigint;
BEGIN
  SELECT count(*)
  INTO booking_count
  FROM public.bookings;

  SELECT count(*)
  INTO ownerless_booking_count
  FROM public.bookings AS booking
  WHERE booking.user_id IS NULL;

  SELECT count(*)
  INTO overlapping_pair_count
  FROM public.bookings AS left_booking
  JOIN public.bookings AS right_booking
    ON left_booking.id < right_booking.id
   AND left_booking.room_id = right_booking.room_id
   AND left_booking.booking_status IN (
     'pending',
     'confirmed',
     'checked_in'
   )
   AND right_booking.booking_status IN (
     'pending',
     'confirmed',
     'checked_in'
   )
   AND left_booking.check_in_date IS NOT NULL
   AND left_booking.check_out_date IS NOT NULL
   AND right_booking.check_in_date IS NOT NULL
   AND right_booking.check_out_date IS NOT NULL
   AND left_booking.check_out_date > left_booking.check_in_date
   AND right_booking.check_out_date > right_booking.check_in_date
   AND daterange(
     left_booking.check_in_date,
     left_booking.check_out_date,
     '[)'
   ) && daterange(
     right_booking.check_in_date,
     right_booking.check_out_date,
     '[)'
   );

  IF booking_count <> 0 THEN
    RAISE EXCEPTION
      'Booking demo-data reconciliation failed: public.bookings still contains % rows.',
      booking_count;
  END IF;

  IF ownerless_booking_count <> 0 THEN
    RAISE EXCEPTION
      'Booking demo-data reconciliation failed: % ownerless bookings remain.',
      ownerless_booking_count;
  END IF;

  IF overlapping_pair_count <> 0 THEN
    RAISE EXCEPTION
      'Booking demo-data reconciliation failed: % overlapping booking pairs remain.',
      overlapping_pair_count;
  END IF;
END;
$postcondition$;

COMMIT;

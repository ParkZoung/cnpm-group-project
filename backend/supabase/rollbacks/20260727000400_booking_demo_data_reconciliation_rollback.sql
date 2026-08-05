BEGIN;

/*
 * This rollback intentionally does not recreate deleted booking rows.
 *
 * The reconciliation migration deleted owner-confirmed demo data without
 * retaining personal or booking payloads in the repository. Reconstructing
 * rows here would require invented ownership, identifiers, prices, statuses,
 * or guest data and would be unsafe.
 *
 * To restore the deleted demo rows, use the separately exported backup through
 * a reviewed restoration procedure. This file changes no data, RLS policy,
 * privilege, constraint, extension, function, trigger, or table structure.
 */
DO $rollback_verification$
DECLARE
  current_booking_count bigint;
BEGIN
  SELECT count(*)
  INTO current_booking_count
  FROM public.bookings;

  RAISE EXCEPTION
    'Automatic rollback is unavailable: deleted demo bookings cannot be reconstructed safely. public.bookings currently contains % rows. Restore only from the separately exported backup using a reviewed procedure.',
    current_booking_count;
END;
$rollback_verification$;

COMMIT;

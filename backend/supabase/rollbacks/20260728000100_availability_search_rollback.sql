BEGIN;

/*
 * GoStay Availability Search rollback.
 * Removes only the availability RPC and preserves all booking protections.
 */
DO $close_rpc_access$
DECLARE
  function_oid oid :=
    pg_catalog.to_regprocedure(
      'public.search_available_rooms(date,date,integer,bigint,bigint,bigint,bigint)'
    );
BEGIN
  IF function_oid IS NOT NULL THEN
    EXECUTE
      'REVOKE EXECUTE ON FUNCTION public.search_available_rooms'
      || '(date, date, integer, bigint, bigint, bigint, bigint) '
      || 'FROM PUBLIC, anon, authenticated';

    IF (
      pg_catalog.has_function_privilege('anon', function_oid, 'EXECUTE')
      OR pg_catalog.has_function_privilege(
        'authenticated', function_oid, 'EXECUTE'
      )
      OR EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS procedure_value
        CROSS JOIN LATERAL pg_catalog.aclexplode(
          coalesce(
            procedure_value.proacl,
            pg_catalog.acldefault('f', procedure_value.proowner)
          )
        ) AS acl
        WHERE procedure_value.oid = function_oid
          AND acl.grantee = 0
          AND acl.privilege_type = 'EXECUTE'
      )
    ) THEN
      RAISE EXCEPTION
        'Availability Search rollback failed: RPC execution remains open.';
    END IF;
  END IF;
END;
$close_rpc_access$;

DROP FUNCTION IF EXISTS public.search_available_rooms(
  date, date, integer, bigint, bigint, bigint, bigint
);

DO $postconditions$
BEGIN
  IF pg_catalog.to_regprocedure(
    'public.search_available_rooms(date,date,integer,bigint,bigint,bigint,bigint)'
  ) IS NOT NULL THEN
    RAISE EXCEPTION
      'Availability Search rollback failed: RPC still exists.';
  END IF;

  IF pg_catalog.to_regprocedure(
    'public.create_booking(bigint,date,date,integer,text,text,text,text)'
  ) IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_constraint AS constraint_value
       WHERE constraint_value.conrelid = 'public.bookings'::regclass
         AND constraint_value.conname = 'bookings_no_holding_overlap'
         AND constraint_value.contype = 'x'
         AND constraint_value.convalidated
     )
     OR (
       SELECT count(*)
       FROM pg_catalog.pg_policy AS policy
       WHERE policy.polrelid = 'public.bookings'::regclass
         AND policy.polname IN ('bookings_select_own', 'bookings_select_admin')
         AND policy.polcmd = 'r'
     ) <> 2
  THEN
    RAISE EXCEPTION
      'Availability Search rollback failed: booking foundation drift detected.';
  END IF;
END;
$postconditions$;

COMMIT;

BEGIN;

/*
 * Fail-closed rollback for Booking Security Foundation.
 *
 * Access is closed before policies and RPCs are removed. Data-integrity
 * invariants, ownership, indexes, btree_gist, and RLS remain in place.
 */
REVOKE ALL PRIVILEGES ON TABLE public.bookings FROM PUBLIC;
REVOKE ALL PRIVILEGES ON TABLE public.bookings FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.bookings FROM authenticated;
REVOKE ALL PRIVILEGES (
  id, booking_code, user_id, room_id, guest_name, guest_email, guest_phone,
  check_in_date, check_out_date, number_of_nights, number_of_guests,
  special_request, price_per_night, subtotal, tax_rate, tax_amount,
  discount_amount, total_amount, booking_status, payment_method,
  payment_status, created_at, updated_at, cancelled_at, promotion_id
) ON TABLE public.bookings FROM PUBLIC;
REVOKE ALL PRIVILEGES (
  id, booking_code, user_id, room_id, guest_name, guest_email, guest_phone,
  check_in_date, check_out_date, number_of_nights, number_of_guests,
  special_request, price_per_night, subtotal, tax_rate, tax_amount,
  discount_amount, total_amount, booking_status, payment_method,
  payment_status, created_at, updated_at, cancelled_at, promotion_id
) ON TABLE public.bookings FROM anon;
REVOKE ALL PRIVILEGES (
  id, booking_code, user_id, room_id, guest_name, guest_email, guest_phone,
  check_in_date, check_out_date, number_of_nights, number_of_guests,
  special_request, price_per_night, subtotal, tax_rate, tax_amount,
  discount_amount, total_amount, booking_status, payment_method,
  payment_status, created_at, updated_at, cancelled_at, promotion_id
) ON TABLE public.bookings FROM authenticated;

DO $revoke_rpc_access$
DECLARE
  rpc record;
BEGIN
  FOR rpc IN
    SELECT
      namespace.nspname,
      procedure_value.proname,
      pg_catalog.pg_get_function_identity_arguments(procedure_value.oid)
        AS identity_arguments
    FROM pg_catalog.pg_proc AS procedure_value
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = procedure_value.pronamespace
    WHERE namespace.nspname = 'public'
      AND procedure_value.prokind = 'f'
      AND procedure_value.proname IN (
        'create_booking',
        'cancel_own_booking',
        'admin_update_booking_status',
        'admin_update_payment_status'
      )
  LOOP
    EXECUTE pg_catalog.format(
      'REVOKE EXECUTE ON FUNCTION %I.%I(%s) FROM PUBLIC, anon, authenticated',
      rpc.nspname,
      rpc.proname,
      rpc.identity_arguments
    );
  END LOOP;
END;
$revoke_rpc_access$;

/*
 * Commit the access barrier before removing owned objects. If later drift
 * verification rejects the rollback because an unknown overload remains, that
 * overload stays non-executable by the frontend roles.
 */
DO $verify_rpc_access_closed$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_value
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = procedure_value.pronamespace
    WHERE namespace.nspname = 'public'
      AND procedure_value.prokind = 'f'
      AND procedure_value.proname IN (
        'create_booking',
        'cancel_own_booking',
        'admin_update_booking_status',
        'admin_update_payment_status'
      )
      AND (
        pg_catalog.has_function_privilege(
          'anon', procedure_value.oid, 'EXECUTE'
        )
        OR pg_catalog.has_function_privilege(
          'authenticated', procedure_value.oid, 'EXECUTE'
        )
        OR EXISTS (
          SELECT 1
          FROM pg_catalog.aclexplode(
            coalesce(
              procedure_value.proacl,
              pg_catalog.acldefault('f', procedure_value.proowner)
            )
          ) AS acl
          WHERE acl.grantee = 0
            AND acl.privilege_type = 'EXECUTE'
        )
      )
  ) THEN
    RAISE EXCEPTION
      'Booking Foundation rollback failed: booking RPC access could not be closed.';
  END IF;
END;
$verify_rpc_access_closed$;

COMMIT;
BEGIN;

DROP POLICY IF EXISTS bookings_select_own ON public.bookings;
DROP POLICY IF EXISTS bookings_select_admin ON public.bookings;

DROP FUNCTION IF EXISTS public.create_booking(
  bigint, date, date, integer, text, text, text, text
);
DROP FUNCTION IF EXISTS public.cancel_own_booking(uuid);
DROP FUNCTION IF EXISTS public.admin_update_booking_status(
  uuid, character varying
);
DROP FUNCTION IF EXISTS public.admin_update_payment_status(
  uuid, character varying
);

ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings NO FORCE ROW LEVEL SECURITY;

DO $rollback_verification$
DECLARE
  booking_oid oid := 'public.bookings'::regclass::oid;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_value
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = procedure_value.pronamespace
    WHERE namespace.nspname = 'public'
      AND procedure_value.prokind = 'f'
      AND procedure_value.proname IN (
        'create_booking',
        'cancel_own_booking',
        'admin_update_booking_status',
        'admin_update_payment_status'
      )
  ) THEN
    RAISE EXCEPTION
      'Booking Foundation rollback failed: a booking RPC overload remains.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS class
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      coalesce(class.relacl, pg_catalog.acldefault('r', class.relowner))
    ) AS acl
    WHERE class.oid = booking_oid
      AND (
        acl.grantee = 0
        OR pg_catalog.pg_get_userbyid(acl.grantee)::text
          IN ('anon', 'authenticated')
      )
  ) OR pg_catalog.has_table_privilege('anon', booking_oid, 'SELECT')
     OR pg_catalog.has_table_privilege('anon', booking_oid, 'INSERT')
     OR pg_catalog.has_table_privilege('anon', booking_oid, 'UPDATE')
     OR pg_catalog.has_table_privilege('anon', booking_oid, 'DELETE')
     OR pg_catalog.has_table_privilege('anon', booking_oid, 'TRUNCATE')
     OR pg_catalog.has_table_privilege('anon', booking_oid, 'REFERENCES')
     OR pg_catalog.has_table_privilege('anon', booking_oid, 'TRIGGER')
     OR pg_catalog.has_table_privilege(
       'authenticated', booking_oid, 'SELECT'
     )
     OR pg_catalog.has_table_privilege(
       'authenticated', booking_oid, 'INSERT'
     )
     OR pg_catalog.has_table_privilege(
       'authenticated', booking_oid, 'UPDATE'
     )
     OR pg_catalog.has_table_privilege(
       'authenticated', booking_oid, 'DELETE'
     )
     OR pg_catalog.has_table_privilege(
       'authenticated', booking_oid, 'TRUNCATE'
     )
     OR pg_catalog.has_table_privilege(
       'authenticated', booking_oid, 'REFERENCES'
     )
     OR pg_catalog.has_table_privilege(
       'authenticated', booking_oid, 'TRIGGER'
     )
     OR pg_catalog.has_any_column_privilege(
       'anon', booking_oid, 'INSERT,UPDATE,REFERENCES'
     )
     OR pg_catalog.has_any_column_privilege(
       'authenticated', booking_oid, 'INSERT,UPDATE,REFERENCES'
     )
     OR EXISTS (
       SELECT 1
       FROM pg_catalog.pg_attribute AS attribute
       CROSS JOIN LATERAL pg_catalog.aclexplode(attribute.attacl) AS acl
       WHERE attribute.attrelid = booking_oid
         AND attribute.attnum > 0
         AND NOT attribute.attisdropped
         AND (
           acl.grantee = 0
           OR pg_catalog.pg_get_userbyid(acl.grantee)::text
             IN ('anon', 'authenticated')
         )
     )
  THEN
    RAISE EXCEPTION
      'Booking Foundation rollback failed: frontend table access remains.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS class
    WHERE class.oid = booking_oid
      AND class.relrowsecurity
      AND NOT class.relforcerowsecurity
  ) THEN
    RAISE EXCEPTION
      'Booking Foundation rollback failed: fail-closed RLS state was not preserved.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute
    WHERE attribute.attrelid = booking_oid
      AND attribute.attname = 'user_id'
      AND attribute.attnotnull
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS con
    WHERE con.conrelid = booking_oid
      AND con.conname = 'bookings_user_id_fkey'
      AND con.contype = 'f'
      AND con.convalidated
      AND con.confupdtype = 'c'
      AND con.confdeltype = 'r'
  ) OR (
    SELECT count(*)
    FROM pg_catalog.pg_constraint AS con
    WHERE con.conrelid = booking_oid
      AND con.convalidated
      AND con.conname IN (
        'bookings_valid_date_range',
        'bookings_number_of_nights_matches_dates',
        'chk_booking_subtotal',
        'chk_booking_total',
        'bookings_stage1_tax_rate',
        'bookings_tax_amount_consistent',
        'bookings_discount_upper_bound',
        'bookings_cancellation_consistent',
        'bookings_no_holding_overlap'
      )
  ) <> 9 THEN
    RAISE EXCEPTION
      'Booking Foundation rollback failed: a preserved security invariant is missing.';
  END IF;

  IF pg_catalog.to_regclass('public.bookings_user_created_at_idx') IS NULL
     OR pg_catalog.to_regclass(
       'public.bookings_payment_status_created_at_idx'
     ) IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_extension
       WHERE extname = 'btree_gist'
     )
  THEN
    RAISE EXCEPTION
      'Booking Foundation rollback failed: a preserved index or extension is missing.';
  END IF;

  IF pg_catalog.to_regprocedure('public.is_admin()') IS NULL
     OR pg_catalog.to_regprocedure('public.handle_new_auth_user()') IS NULL
  THEN
    RAISE WARNING
      'Foundation drift detected after booking rollback. Separate Auth/Profile remediation is required; booking access remains closed.';
  END IF;
END;
$rollback_verification$;

COMMIT;

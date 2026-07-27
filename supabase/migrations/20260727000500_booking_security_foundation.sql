BEGIN;

/*
 * GoStay Booking Security Foundation
 *
 * The live booking preflight passed and reconciliation left public.bookings
 * empty. This migration fails closed if any reviewed assumption has drifted.
 */
LOCK TABLE public.bookings IN ACCESS EXCLUSIVE MODE;

DO $preconditions$
DECLARE
  booking_oid oid;
  profiles_oid oid;
  rooms_oid oid;
  room_types_oid oid;
  branches_oid oid;
  current_fk_count integer;
  reviewed_constraint_count integer;
  target_constraint_count integer;
  target_index_count integer;
  target_policy_count integer;
  target_function_count integer;
  catalog_policy_count integer;
  admin_body text;
  room_date_index_first_column text;
BEGIN
  SELECT class.oid
  INTO booking_oid
  FROM pg_catalog.pg_class AS class
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = class.relnamespace
  WHERE namespace.nspname = 'public'
    AND class.relname = 'bookings'
    AND class.relkind IN ('r', 'p');

  profiles_oid := pg_catalog.to_regclass('public.profiles');
  rooms_oid := pg_catalog.to_regclass('public.rooms');
  room_types_oid := pg_catalog.to_regclass('public.room_types');
  branches_oid := pg_catalog.to_regclass('public.branches');

  IF booking_oid IS NULL
     OR profiles_oid IS NULL
     OR rooms_oid IS NULL
     OR room_types_oid IS NULL
     OR branches_oid IS NULL
  THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: a required Foundation relation is missing.';
  END IF;

  IF (SELECT count(*) FROM public.bookings) <> 0 THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: public.bookings must remain empty after reconciliation.';
  END IF;

  IF (
    SELECT count(*)
    FROM information_schema.columns AS column_value
    JOIN (
      VALUES
        ('id', 'uuid', 'NO'),
        ('booking_code', 'varchar', 'NO'),
        ('user_id', 'uuid', 'YES'),
        ('room_id', 'int8', 'NO'),
        ('check_in_date', 'date', 'NO'),
        ('check_out_date', 'date', 'NO'),
        ('number_of_nights', 'int4', 'NO'),
        ('number_of_guests', 'int4', 'NO'),
        ('price_per_night', 'int8', 'NO'),
        ('subtotal', 'int8', 'NO'),
        ('tax_rate', 'numeric', 'NO'),
        ('tax_amount', 'int8', 'NO'),
        ('discount_amount', 'int8', 'NO'),
        ('total_amount', 'int8', 'NO'),
        ('booking_status', 'varchar', 'NO'),
        ('payment_method', 'varchar', 'NO'),
        ('payment_status', 'varchar', 'NO'),
        ('cancelled_at', 'timestamptz', 'YES'),
        ('promotion_id', 'int8', 'YES'),
        ('created_at', 'timestamptz', 'NO'),
        ('updated_at', 'timestamptz', 'NO')
    ) AS expected(column_name, udt_name, nullable)
      ON expected.column_name = column_value.column_name
     AND expected.udt_name = column_value.udt_name
     AND expected.nullable = column_value.is_nullable
    WHERE column_value.table_schema = 'public'
      AND column_value.table_name = 'bookings'
  ) <> 21 THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: reviewed bookings columns or nullability changed.';
  END IF;

  /*
   * Reviewed pre-migration ownership FK:
   * ON UPDATE CASCADE / ON DELETE SET NULL.
   */
  SELECT count(*)
  INTO current_fk_count
  FROM pg_catalog.pg_constraint AS con
  JOIN pg_catalog.pg_attribute AS source_attribute
    ON source_attribute.attrelid = con.conrelid
   AND source_attribute.attname = 'user_id'
   AND con.conkey = ARRAY[source_attribute.attnum]::smallint[]
  JOIN pg_catalog.pg_attribute AS target_attribute
    ON target_attribute.attrelid = con.confrelid
   AND target_attribute.attname = 'id'
   AND con.confkey = ARRAY[target_attribute.attnum]::smallint[]
  WHERE con.conrelid = booking_oid
    AND con.conname = 'bookings_user_id_fkey'
    AND con.contype = 'f'
    AND con.confrelid = profiles_oid
    AND con.convalidated
    AND con.confupdtype = 'c'
    AND con.confdeltype = 'n';

  IF current_fk_count <> 1 THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: bookings_user_id_fkey is not the reviewed ON UPDATE CASCADE / ON DELETE SET NULL FK.';
  END IF;

  SELECT count(*)
  INTO reviewed_constraint_count
  FROM pg_catalog.pg_constraint AS con
  WHERE con.conrelid = booking_oid
    AND con.convalidated
    AND con.conname IN (
      'bookings_valid_date_range',
      'bookings_number_of_nights_matches_dates',
      'chk_booking_subtotal',
      'chk_booking_total'
    );

  IF reviewed_constraint_count <> 4 THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: a reviewed validated booking constraint is missing.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS con
    WHERE con.conrelid = booking_oid
      AND con.contype = 'c'
      AND con.convalidated
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%booking_status%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%pending%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%confirmed%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%checked_in%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%completed%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%cancelled%'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS con
    WHERE con.conrelid = booking_oid
      AND con.contype = 'c'
      AND con.convalidated
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%payment_status%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%unpaid%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%pending%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%paid%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%failed%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%refunded%'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS con
    WHERE con.conrelid = booking_oid
      AND con.contype = 'c'
      AND con.convalidated
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%payment_method%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%pay_at_hotel%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%online%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%bank_transfer%'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS con
    WHERE con.conrelid = booking_oid
      AND con.contype = 'c'
      AND con.convalidated
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%number_of_guests%'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS con
    WHERE con.conrelid = booking_oid
      AND con.contype = 'c'
      AND con.convalidated
      AND (
        pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%price_per_night%'
        OR pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%subtotal%'
        OR pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%tax_amount%'
        OR pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%discount_amount%'
        OR pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%total_amount%'
      )
  ) THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: reviewed status, payment, guest, or monetary checks changed.';
  END IF;

  SELECT count(*)
  INTO target_constraint_count
  FROM pg_catalog.pg_constraint AS con
  WHERE con.conrelid = booking_oid
    AND con.conname IN (
      'bookings_stage1_tax_rate',
      'bookings_tax_amount_consistent',
      'bookings_discount_upper_bound',
      'bookings_cancellation_consistent',
      'bookings_no_holding_overlap'
    );

  IF target_constraint_count <> 0 THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: a migration-owned constraint name already exists.';
  END IF;

  SELECT count(*)
  INTO target_index_count
  FROM pg_catalog.pg_class AS index_class
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = index_class.relnamespace
  WHERE namespace.nspname = 'public'
    AND index_class.relname IN (
      'bookings_user_created_at_idx',
      'bookings_payment_status_created_at_idx'
    );

  IF target_index_count <> 0 THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: a migration-owned index name already exists.';
  END IF;

  SELECT attribute.attname::text
  INTO room_date_index_first_column
  FROM pg_catalog.pg_index AS index_value
  JOIN pg_catalog.pg_class AS index_class
    ON index_class.oid = index_value.indexrelid
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = index_class.relnamespace
  JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = index_value.indrelid
   AND attribute.attnum = index_value.indkey[0]
  WHERE namespace.nspname = 'public'
    AND index_class.relname = 'idx_bookings_room_dates'
    AND index_value.indrelid = booking_oid
    AND index_value.indisvalid
    AND index_value.indisready;

  IF room_date_index_first_column IS DISTINCT FROM 'room_id' THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: idx_bookings_room_dates is missing, invalid, or no longer starts with room_id.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute
    WHERE attribute.attrelid = rooms_oid
      AND attribute.attname = 'capacity'
      AND attribute.attnum > 0
      AND NOT attribute.attisdropped
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute
    WHERE attribute.attrelid = room_types_oid
      AND attribute.attname = 'capacity'
      AND attribute.atttypid IN (
        'smallint'::regtype,
        'integer'::regtype,
        'bigint'::regtype
      )
      AND attribute.attnotnull
      AND attribute.attnum > 0
      AND NOT attribute.attisdropped
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS con
    JOIN pg_catalog.pg_attribute AS source_attribute
      ON source_attribute.attrelid = con.conrelid
     AND source_attribute.attname = 'room_type_id'
     AND con.conkey = ARRAY[source_attribute.attnum]::smallint[]
    JOIN pg_catalog.pg_attribute AS target_attribute
      ON target_attribute.attrelid = con.confrelid
     AND target_attribute.attname = 'id'
     AND con.confkey = ARRAY[target_attribute.attnum]::smallint[]
    WHERE con.conrelid = rooms_oid
      AND con.confrelid = room_types_oid
      AND con.contype = 'f'
      AND con.convalidated
  ) THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: the reviewed authoritative room_types.capacity source changed or became ambiguous.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_value
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = procedure_value.pronamespace
    JOIN pg_catalog.pg_language AS language
      ON language.oid = procedure_value.prolang
    WHERE namespace.nspname = 'public'
      AND procedure_value.proname = 'is_admin'
      AND procedure_value.pronargs = 0
      AND procedure_value.prorettype = 'boolean'::regtype
      AND procedure_value.prosecdef
      AND procedure_value.provolatile = 's'
      AND language.lanname = 'sql'
      AND pg_catalog.pg_get_userbyid(procedure_value.proowner) = 'postgres'
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.unnest(procedure_value.proconfig) AS config(setting)
        WHERE pg_catalog.split_part(config.setting, '=', 1) = 'search_path'
          AND pg_catalog.replace(
            pg_catalog.split_part(config.setting, '=', 2),
            '"',
            ''
          ) = ''
      )
  ) THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: public.is_admin() security attributes drifted.';
  END IF;

  SELECT pg_catalog.btrim(
    pg_catalog.regexp_replace(
      pg_catalog.lower(procedure_value.prosrc),
      '[[:space:]]+',
      '',
      'g'
    ),
    pg_catalog.chr(59)
  )
  INTO admin_body
  FROM pg_catalog.pg_proc AS procedure_value
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = procedure_value.pronamespace
  WHERE namespace.nspname = 'public'
    AND procedure_value.proname = 'is_admin'
    AND procedure_value.pronargs = 0;

  IF admin_body IS DISTINCT FROM
    $approved$selectcoalesce(exists(select1frompublic.profilesaspwherep.id=auth.uid()andp.role='admin'andp.status='active'),false)$approved$
  THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: public.is_admin() body differs from Auth/Profile Foundation.';
  END IF;

  IF pg_catalog.to_regprocedure('public.handle_new_auth_user()') IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_trigger AS trigger_value
       WHERE trigger_value.tgrelid = 'auth.users'::regclass
         AND trigger_value.tgname = 'on_auth_user_created'
         AND NOT trigger_value.tgisinternal
         AND trigger_value.tgenabled <> 'D'
         AND trigger_value.tgfoid =
           'public.handle_new_auth_user()'::regprocedure::oid
     )
  THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: Auth/Profile Foundation objects drifted.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_value
    JOIN pg_catalog.pg_proc AS procedure_value
      ON procedure_value.oid = trigger_value.tgfoid
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = procedure_value.pronamespace
    WHERE trigger_value.tgrelid = booking_oid
      AND trigger_value.tgname = 'trg_bookings_updated_at'
      AND NOT trigger_value.tgisinternal
      AND trigger_value.tgenabled <> 'D'
      AND namespace.nspname = 'public'
      AND procedure_value.proname = 'set_updated_at'
  ) THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: trg_bookings_updated_at drifted.';
  END IF;

  SELECT count(*)
  INTO target_policy_count
  FROM pg_catalog.pg_policy AS policy
  WHERE policy.polrelid = booking_oid;

  IF target_policy_count <> 0 THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: public.bookings already has an unreviewed policy.';
  END IF;

  SELECT count(*)
  INTO target_function_count
  FROM pg_catalog.pg_proc AS procedure_value
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = procedure_value.pronamespace
  WHERE namespace.nspname = 'public'
    AND procedure_value.proname IN (
      'create_booking',
      'cancel_own_booking',
      'admin_update_booking_status',
      'admin_update_payment_status'
    );

  IF target_function_count <> 0 THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: a migration-owned RPC name already exists.';
  END IF;

  SELECT count(*)
  INTO catalog_policy_count
  FROM pg_catalog.pg_policy AS policy
  JOIN pg_catalog.pg_class AS class
    ON class.oid = policy.polrelid
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = class.relnamespace
  WHERE namespace.nspname = 'public'
    AND (
      (class.relname = 'branches'
       AND policy.polname IN ('branches_public_select', 'branches_admin_all'))
      OR (class.relname = 'room_types'
       AND policy.polname IN ('room_types_public_select', 'room_types_admin_all'))
      OR (class.relname = 'rooms'
       AND policy.polname IN ('rooms_public_select', 'rooms_admin_all'))
      OR (class.relname = 'amenities'
       AND policy.polname IN ('amenities_public_select', 'amenities_admin_all'))
      OR (class.relname = 'room_images'
       AND policy.polname IN ('room_images_public_select', 'room_images_admin_all'))
      OR (class.relname = 'room_amenities'
       AND policy.polname IN ('room_amenities_public_select', 'room_amenities_admin_all'))
      OR (class.relname = 'promotions'
       AND policy.polname IN ('promotions_public_select', 'promotions_admin_all'))
    );

  IF catalog_policy_count <> 14 OR (
    SELECT count(*)
    FROM pg_catalog.pg_policy AS policy
    JOIN pg_catalog.pg_class AS class
      ON class.oid = policy.polrelid
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = class.relnamespace
    WHERE namespace.nspname = 'public'
      AND class.relname IN (
        'branches',
        'room_types',
        'rooms',
        'amenities',
        'room_images',
        'room_amenities',
        'promotions'
      )
  ) <> 14 THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: the 14 approved Catalog policies are not intact.';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_class AS class
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = class.relnamespace
    WHERE namespace.nspname = 'public'
      AND class.relname IN (
        'branches',
        'room_types',
        'rooms',
        'amenities',
        'room_images',
        'room_amenities',
        'promotions'
      )
      AND class.relkind IN ('r', 'p')
      AND class.relrowsecurity
      AND NOT class.relforcerowsecurity
  ) <> 7 THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: Catalog RLS state drifted.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_extension AS extension_value
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = extension_value.extnamespace
    WHERE extension_value.extname = 'btree_gist'
      AND namespace.nspname <> 'extensions'
  ) THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: btree_gist is installed outside the reviewed extensions schema.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_extension
    WHERE extname = 'btree_gist'
  ) AND (
    NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_available_extensions
      WHERE name = 'btree_gist'
    )
    OR pg_catalog.to_regnamespace('extensions') IS NULL
  ) THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: btree_gist cannot be installed safely in schema extensions.';
  END IF;

  IF pg_catalog.to_regprocedure('pg_catalog.gen_random_uuid()') IS NULL
     OR pg_catalog.to_regprocedure(
       'pg_catalog.daterange(date,date,text)'
     ) IS NULL
  THEN
    RAISE EXCEPTION
      'Booking Foundation stopped: required PostgreSQL UUID or daterange capability is unavailable.';
  END IF;
END;
$preconditions$;

/*
 * Close the direct table API before creating trusted RPCs. All statements are
 * transactional, so any later failure also rolls these revocations back.
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

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;

DO $opclass_verification$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_opclass AS operator_class
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = operator_class.opcnamespace
    JOIN pg_catalog.pg_am AS access_method
      ON access_method.oid = operator_class.opcmethod
    JOIN pg_catalog.pg_amop AS operator_member
      ON operator_member.amopfamily = operator_class.opcfamily
     AND operator_member.amoplefttype = 'bigint'::regtype
     AND operator_member.amoprighttype = 'bigint'::regtype
     AND operator_member.amopstrategy = 3
    JOIN pg_catalog.pg_operator AS operator_value
      ON operator_value.oid = operator_member.amopopr
     AND operator_value.oprname = '='
    WHERE namespace.nspname = 'extensions'
      AND operator_class.opcname = 'gist_int8_ops'
      AND operator_class.opcintype = 'bigint'::regtype
      AND access_method.amname = 'gist'
  ) THEN
    RAISE EXCEPTION
      'Booking Foundation failed: extensions.gist_int8_ops does not provide reviewed bigint GiST equality.';
  END IF;
END;
$opclass_verification$;

ALTER TABLE public.bookings
  DROP CONSTRAINT bookings_user_id_fkey;

ALTER TABLE public.bookings
  ALTER COLUMN user_id SET NOT NULL;

ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_user_id_fkey
  FOREIGN KEY (user_id)
  REFERENCES public.profiles(id)
  ON UPDATE CASCADE
  ON DELETE RESTRICT;

ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_stage1_tax_rate
  CHECK (tax_rate = 10::numeric),
  ADD CONSTRAINT bookings_tax_amount_consistent
  CHECK (
    tax_amount =
      pg_catalog.round(subtotal::numeric * tax_rate / 100::numeric)::bigint
  ),
  ADD CONSTRAINT bookings_discount_upper_bound
  CHECK (discount_amount <= subtotal + tax_amount),
  ADD CONSTRAINT bookings_cancellation_consistent
  CHECK (
    (booking_status = 'cancelled'::character varying)
      = (cancelled_at IS NOT NULL)
  );

CREATE INDEX bookings_user_created_at_idx
  ON public.bookings (user_id, created_at DESC);

CREATE INDEX bookings_payment_status_created_at_idx
  ON public.bookings (payment_status, created_at DESC);

ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_no_holding_overlap
  EXCLUDE USING gist (
    room_id extensions.gist_int8_ops WITH =,
    (
      pg_catalog.daterange(check_in_date, check_out_date, '[)'::text)
    ) pg_catalog.range_ops WITH &&
  )
  WHERE (
    booking_status IN (
      'pending'::character varying,
      'confirmed'::character varying,
      'checked_in'::character varying
    )
  );

CREATE FUNCTION public.create_booking(
  p_room_id bigint,
  p_check_in_date date,
  p_check_out_date date,
  p_number_of_guests integer,
  p_guest_name text,
  p_guest_email text,
  p_guest_phone text,
  p_special_request text DEFAULT NULL
)
RETURNS TABLE (
  booking_id uuid,
  booking_code character varying,
  booking_status character varying,
  payment_status character varying,
  total_amount bigint,
  created_at timestamp with time zone
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_caller_id uuid := auth.uid();
  v_profile_status character varying;
  v_room_status character varying;
  v_branch_status character varying;
  v_room_price bigint;
  v_room_capacity integer;
  v_number_of_nights integer;
  v_subtotal bigint;
  v_tax_amount bigint;
  v_total_amount bigint;
  v_booking_id uuid := pg_catalog.gen_random_uuid();
  v_booking_code character varying;
  v_created_at timestamp with time zone := pg_catalog.statement_timestamp();
  v_guest_name character varying;
  v_guest_email character varying;
  v_guest_phone character varying;
  v_special_request text;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'Authentication is required to create a booking.';
  END IF;

  SELECT profile.status
  INTO v_profile_status
  FROM public.profiles AS profile
  WHERE profile.id = v_caller_id
  FOR SHARE;

  IF v_profile_status IS DISTINCT FROM 'active'::character varying THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'The authenticated profile is not allowed to create bookings.';
  END IF;

  IF p_check_in_date IS NULL
     OR p_check_out_date IS NULL
     OR p_check_out_date <= p_check_in_date
     OR p_check_in_date < CURRENT_DATE
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'The booking date range is invalid.';
  END IF;

  IF p_number_of_guests IS NULL OR p_number_of_guests <= 0 THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'The guest count is invalid.';
  END IF;

  v_guest_name := nullif(pg_catalog.btrim(p_guest_name), '');
  v_guest_email := nullif(pg_catalog.btrim(p_guest_email), '');
  v_guest_phone := nullif(pg_catalog.btrim(p_guest_phone), '');
  v_special_request := nullif(pg_catalog.btrim(p_special_request), '');

  IF v_guest_name IS NULL
     OR v_guest_email IS NULL
     OR pg_catalog.strpos(v_guest_email, '@') <= 1
     OR v_guest_phone IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'Required guest contact information is invalid.';
  END IF;

  SELECT
    room.status,
    branch.status,
    room.price_per_night,
    room_type.capacity
  INTO
    v_room_status,
    v_branch_status,
    v_room_price,
    v_room_capacity
  FROM public.rooms AS room
  JOIN public.branches AS branch
    ON branch.id = room.branch_id
  JOIN public.room_types AS room_type
    ON room_type.id = room.room_type_id
  WHERE room.id = p_room_id
  FOR SHARE OF room, branch, room_type;

  IF NOT FOUND
     OR v_room_status IS DISTINCT FROM 'available'::character varying
     OR v_branch_status IS DISTINCT FROM 'active'::character varying
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'The selected room is not available for booking.';
  END IF;

  IF p_number_of_guests > v_room_capacity THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'The guest count exceeds the selected room capacity.';
  END IF;

  v_number_of_nights := p_check_out_date - p_check_in_date;
  v_subtotal := v_room_price * v_number_of_nights;
  v_tax_amount :=
    pg_catalog.round(v_subtotal::numeric * 10::numeric / 100::numeric)::bigint;
  v_total_amount := v_subtotal + v_tax_amount;
  v_booking_code :=
    'GS'
    || pg_catalog.to_char(v_created_at, 'YYYYMMDD')
    || '-'
    || pg_catalog.upper(
      pg_catalog.substr(
        pg_catalog.replace(v_booking_id::text, '-', ''),
        1,
        12
      )
    );

  INSERT INTO public.bookings (
    id,
    booking_code,
    user_id,
    room_id,
    guest_name,
    guest_email,
    guest_phone,
    check_in_date,
    check_out_date,
    number_of_nights,
    number_of_guests,
    special_request,
    price_per_night,
    subtotal,
    tax_rate,
    tax_amount,
    discount_amount,
    total_amount,
    booking_status,
    payment_method,
    payment_status,
    created_at,
    updated_at,
    cancelled_at,
    promotion_id
  )
  VALUES (
    v_booking_id,
    v_booking_code,
    v_caller_id,
    p_room_id,
    v_guest_name,
    v_guest_email,
    v_guest_phone,
    p_check_in_date,
    p_check_out_date,
    v_number_of_nights,
    p_number_of_guests,
    v_special_request,
    v_room_price,
    v_subtotal,
    10,
    v_tax_amount,
    0,
    v_total_amount,
    'pending',
    'pay_at_hotel',
    'unpaid',
    v_created_at,
    v_created_at,
    NULL,
    NULL
  );

  RETURN QUERY
  SELECT
    v_booking_id,
    v_booking_code,
    'pending'::character varying,
    'unpaid'::character varying,
    v_total_amount,
    v_created_at;
EXCEPTION
  WHEN exclusion_violation THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'The selected room is no longer available for those dates.';
  WHEN unique_violation THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'The booking could not be created safely. Please retry.';
  WHEN check_violation
    OR foreign_key_violation
    OR not_null_violation
    OR numeric_value_out_of_range
    OR string_data_right_truncation
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'The booking input could not be accepted safely.';
END;
$function$;

CREATE FUNCTION public.cancel_own_booking(
  p_booking_id uuid
)
RETURNS TABLE (
  booking_id uuid,
  booking_status character varying,
  cancelled_at timestamp with time zone
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_caller_id uuid := auth.uid();
  v_booking_id uuid;
  v_booking_status character varying;
  v_cancelled_at timestamp with time zone;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'Authentication is required to cancel a booking.';
  END IF;

  UPDATE public.bookings AS booking
  SET
    booking_status = 'cancelled',
    cancelled_at = pg_catalog.statement_timestamp()
  WHERE booking.id = p_booking_id
    AND booking.user_id = v_caller_id
    AND booking.booking_status IN ('pending', 'confirmed')
  RETURNING
    booking.id,
    booking.booking_status,
    booking.cancelled_at
  INTO
    v_booking_id,
    v_booking_status,
    v_cancelled_at;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'The booking cannot be cancelled.';
  END IF;

  RETURN QUERY
  SELECT v_booking_id, v_booking_status, v_cancelled_at;
END;
$function$;

CREATE FUNCTION public.admin_update_booking_status(
  p_booking_id uuid,
  p_new_status character varying
)
RETURNS TABLE (
  booking_id uuid,
  old_status character varying,
  new_status character varying,
  updated_at timestamp with time zone
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
/*
 * Stage 1 enforces transition ordering only. Date-gated check-in/completion is
 * intentionally deferred to the dedicated booking-lifecycle business task.
 */
DECLARE
  v_old_status character varying;
  v_updated_at timestamp with time zone;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'Administrator authorization is required.';
  END IF;

  IF p_new_status IS NULL
     OR p_new_status NOT IN (
       'pending',
       'confirmed',
       'checked_in',
       'completed',
       'cancelled'
     )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'The requested booking status is invalid.';
  END IF;

  SELECT booking.booking_status
  INTO v_old_status
  FROM public.bookings AS booking
  WHERE booking.id = p_booking_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'The booking was not found.';
  END IF;

  IF NOT (
    (v_old_status = 'pending' AND p_new_status IN ('confirmed', 'cancelled'))
    OR (v_old_status = 'confirmed' AND p_new_status IN ('checked_in', 'cancelled'))
    OR (v_old_status = 'checked_in' AND p_new_status = 'completed')
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'The requested booking status transition is not allowed.';
  END IF;

  UPDATE public.bookings AS booking
  SET
    booking_status = p_new_status,
    cancelled_at = CASE
      WHEN p_new_status = 'cancelled'
        THEN pg_catalog.statement_timestamp()
      ELSE NULL
    END
  WHERE booking.id = p_booking_id
  RETURNING booking.updated_at
  INTO v_updated_at;

  RETURN QUERY
  SELECT p_booking_id, v_old_status, p_new_status, v_updated_at;
END;
$function$;

CREATE FUNCTION public.admin_update_payment_status(
  p_booking_id uuid,
  p_new_payment_status character varying
)
RETURNS TABLE (
  booking_id uuid,
  old_payment_status character varying,
  new_payment_status character varying,
  updated_at timestamp with time zone
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_old_payment_status character varying;
  v_booking_status character varying;
  v_updated_at timestamp with time zone;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'Administrator authorization is required.';
  END IF;

  IF p_new_payment_status IS NULL
     OR p_new_payment_status NOT IN (
       'unpaid',
       'pending',
       'paid',
       'failed',
       'refunded'
     )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'The requested payment status is invalid.';
  END IF;

  SELECT booking.payment_status, booking.booking_status
  INTO v_old_payment_status, v_booking_status
  FROM public.bookings AS booking
  WHERE booking.id = p_booking_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'The booking was not found.';
  END IF;

  IF NOT (
    (v_booking_status <> 'cancelled'
      AND v_old_payment_status = 'unpaid'
      AND p_new_payment_status IN ('pending', 'paid'))
    OR (v_booking_status <> 'cancelled'
      AND v_old_payment_status = 'pending'
      AND p_new_payment_status IN ('paid', 'failed'))
    OR (v_booking_status <> 'cancelled'
      AND v_old_payment_status = 'failed'
      AND p_new_payment_status IN ('pending', 'paid'))
    OR (v_booking_status = 'cancelled'
      AND v_old_payment_status = 'paid'
      AND p_new_payment_status = 'refunded')
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'The requested payment status transition is not allowed.';
  END IF;

  UPDATE public.bookings AS booking
  SET payment_status = p_new_payment_status
  WHERE booking.id = p_booking_id
  RETURNING booking.updated_at
  INTO v_updated_at;

  RETURN QUERY
  SELECT
    p_booking_id,
    v_old_payment_status,
    p_new_payment_status,
    v_updated_at;
END;
$function$;

ALTER FUNCTION public.create_booking(
  bigint, date, date, integer, text, text, text, text
) OWNER TO postgres;
ALTER FUNCTION public.cancel_own_booking(uuid) OWNER TO postgres;
ALTER FUNCTION public.admin_update_booking_status(
  uuid, character varying
) OWNER TO postgres;
ALTER FUNCTION public.admin_update_payment_status(
  uuid, character varying
) OWNER TO postgres;

REVOKE EXECUTE ON FUNCTION public.create_booking(
  bigint, date, date, integer, text, text, text, text
) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cancel_own_booking(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_update_booking_status(
  uuid, character varying
) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_update_payment_status(
  uuid, character varying
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.create_booking(
  bigint, date, date, integer, text, text, text, text
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_own_booking(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_booking_status(
  uuid, character varying
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_payment_status(
  uuid, character varying
) TO authenticated;

ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings NO FORCE ROW LEVEL SECURITY;

CREATE POLICY bookings_select_own
ON public.bookings
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY bookings_select_admin
ON public.bookings
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (public.is_admin());

GRANT SELECT ON TABLE public.bookings TO authenticated;

DO $postconditions$
DECLARE
  booking_oid oid := 'public.bookings'::regclass::oid;
  profiles_oid oid := 'public.profiles'::regclass::oid;
  expected_rpc_oids oid[];
  actual_rpc_oids oid[];
  function_oid oid;
  catalog_policy_count integer;
BEGIN
  IF (SELECT count(*) FROM public.bookings) <> 0 THEN
    RAISE EXCEPTION
      'Booking Foundation verification failed: bookings changed during migration.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute
    WHERE attribute.attrelid = booking_oid
      AND attribute.attname = 'user_id'
      AND attribute.atttypid = 'uuid'::regtype
      AND attribute.attnotnull
  ) THEN
    RAISE EXCEPTION
      'Booking Foundation verification failed: user_id is not required.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS con
    JOIN pg_catalog.pg_attribute AS source_attribute
      ON source_attribute.attrelid = con.conrelid
     AND source_attribute.attname = 'user_id'
     AND con.conkey = ARRAY[source_attribute.attnum]::smallint[]
    JOIN pg_catalog.pg_attribute AS target_attribute
      ON target_attribute.attrelid = con.confrelid
     AND target_attribute.attname = 'id'
     AND con.confkey = ARRAY[target_attribute.attnum]::smallint[]
    WHERE con.conrelid = booking_oid
      AND con.conname = 'bookings_user_id_fkey'
      AND con.contype = 'f'
      AND con.confrelid = profiles_oid
      AND con.convalidated
      AND con.confupdtype = 'c'
      AND con.confdeltype = 'r'
  ) THEN
    RAISE EXCEPTION
      'Booking Foundation verification failed: ownership FK actions are incorrect.';
  END IF;

  IF (
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
      'Booking Foundation verification failed: reviewed or new constraints are missing.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS con
    WHERE con.conrelid = booking_oid
      AND con.conname = 'bookings_no_holding_overlap'
      AND con.contype = 'x'
      AND con.convalidated
      AND pg_catalog.pg_get_constraintdef(con.oid, true)
        ILIKE '%daterange(check_in_date, check_out_date, ''[)''%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%room_id WITH =%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%pending%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%confirmed%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%checked_in%'
  ) THEN
    RAISE EXCEPTION
      'Booking Foundation verification failed: overlap exclusion definition differs.';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_index AS index_value
    JOIN pg_catalog.pg_class AS index_class
      ON index_class.oid = index_value.indexrelid
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = index_class.relnamespace
    WHERE namespace.nspname = 'public'
      AND index_value.indrelid = booking_oid
      AND index_value.indisvalid
      AND index_value.indisready
      AND index_class.relname IN (
        'idx_bookings_room_dates',
        'bookings_user_created_at_idx',
        'bookings_payment_status_created_at_idx'
      )
  ) <> 3 THEN
    RAISE EXCEPTION
      'Booking Foundation verification failed: required indexes are missing or invalid.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_extension AS extension_value
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = extension_value.extnamespace
    WHERE extension_value.extname = 'btree_gist'
      AND namespace.nspname = 'extensions'
  ) THEN
    RAISE EXCEPTION
      'Booking Foundation verification failed: btree_gist is not installed in schema extensions.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS class
    WHERE class.oid = booking_oid
      AND class.relrowsecurity
      AND NOT class.relforcerowsecurity
  ) THEN
    RAISE EXCEPTION
      'Booking Foundation verification failed: RLS state is incorrect.';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_policy AS policy
    WHERE policy.polrelid = booking_oid
      AND policy.polname IN (
        'bookings_select_own',
        'bookings_select_admin'
      )
      AND policy.polcmd = 'r'
      AND policy.polpermissive
      AND (
        SELECT array_agg(role_name ORDER BY role_name)::text[]
        FROM (
          SELECT CASE role_oid
            WHEN 0 THEN 'PUBLIC'::text
            ELSE pg_catalog.pg_get_userbyid(role_oid)::text
          END AS role_name
          FROM pg_catalog.unnest(policy.polroles) AS role_value(role_oid)
        ) AS normalized
      ) = ARRAY['authenticated']::text[]
      AND policy.polwithcheck IS NULL
      AND (
        (
          policy.polname = 'bookings_select_own'
          AND pg_catalog.regexp_replace(
            pg_catalog.lower(
              pg_catalog.pg_get_expr(policy.polqual, policy.polrelid, true)
            ),
            '[[:space:]]+',
            '',
            'g'
          ) IN ('user_id=auth.uid()', '(user_id=auth.uid())')
        )
        OR (
          policy.polname = 'bookings_select_admin'
          AND EXISTS (
            SELECT 1
            FROM pg_catalog.pg_depend AS dependency
            WHERE dependency.classid = 'pg_catalog.pg_policy'::regclass
              AND dependency.objid = policy.oid
              AND dependency.refclassid = 'pg_catalog.pg_proc'::regclass
              AND dependency.refobjid =
                'public.is_admin()'::regprocedure::oid
          )
          AND pg_catalog.regexp_replace(
            pg_catalog.lower(
              pg_catalog.pg_get_expr(policy.polqual, policy.polrelid, true)
            ),
            '[[:space:]]+',
            '',
            'g'
          ) IN (
            'is_admin()',
            '(is_admin())',
            'public.is_admin()',
            '(public.is_admin())'
          )
        )
      )
  ) <> 2 OR (
    SELECT count(*)
    FROM pg_catalog.pg_policy AS policy
    WHERE policy.polrelid = booking_oid
  ) <> 2 THEN
    RAISE EXCEPTION
      'Booking Foundation verification failed: booking policy allowlist differs.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS class
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      coalesce(class.relacl, pg_catalog.acldefault('r', class.relowner))
    ) AS acl
    WHERE class.oid = booking_oid
      AND acl.grantee = 0
  ) OR pg_catalog.has_table_privilege('anon', booking_oid, 'SELECT')
     OR pg_catalog.has_table_privilege('anon', booking_oid, 'INSERT')
     OR pg_catalog.has_table_privilege('anon', booking_oid, 'UPDATE')
     OR pg_catalog.has_table_privilege('anon', booking_oid, 'DELETE')
     OR NOT pg_catalog.has_table_privilege(
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
         AND acl.grantee = 0
     )
  THEN
    RAISE EXCEPTION
      'Booking Foundation verification failed: booking table ACL is too broad.';
  END IF;

  expected_rpc_oids := ARRAY[
    'public.create_booking(bigint,date,date,integer,text,text,text,text)'::regprocedure::oid,
    'public.cancel_own_booking(uuid)'::regprocedure::oid,
    'public.admin_update_booking_status(uuid,character varying)'::regprocedure::oid,
    'public.admin_update_payment_status(uuid,character varying)'::regprocedure::oid
  ];

  SELECT array_agg(procedure_value.oid ORDER BY procedure_value.oid)
  INTO actual_rpc_oids
  FROM pg_catalog.pg_proc AS procedure_value
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = procedure_value.pronamespace
  WHERE namespace.nspname = 'public'
    AND procedure_value.proname IN (
      'create_booking',
      'cancel_own_booking',
      'admin_update_booking_status',
      'admin_update_payment_status'
    );

  SELECT array_agg(oid_value ORDER BY oid_value)
  INTO expected_rpc_oids
  FROM pg_catalog.unnest(expected_rpc_oids) AS oid_value;

  IF actual_rpc_oids IS DISTINCT FROM expected_rpc_oids THEN
    RAISE EXCEPTION
      'Booking Foundation verification failed: RPC overload allowlist differs.';
  END IF;

  FOREACH function_oid IN ARRAY expected_rpc_oids
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc AS procedure_value
      WHERE procedure_value.oid = function_oid
        AND procedure_value.prosecdef
        AND procedure_value.provolatile = 'v'
        AND pg_catalog.pg_get_userbyid(procedure_value.proowner) = 'postgres'
        AND EXISTS (
          SELECT 1
          FROM pg_catalog.unnest(procedure_value.proconfig) AS config(setting)
          WHERE pg_catalog.split_part(config.setting, '=', 1) = 'search_path'
            AND pg_catalog.replace(
              pg_catalog.split_part(config.setting, '=', 2),
              '"',
              ''
            ) = ''
        )
    ) OR EXISTS (
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
    ) OR pg_catalog.has_function_privilege('anon', function_oid, 'EXECUTE')
       OR NOT pg_catalog.has_function_privilege(
         'authenticated', function_oid, 'EXECUTE'
       )
    THEN
      RAISE EXCEPTION
        'Booking Foundation verification failed: RPC security attributes or ACL differ.';
    END IF;
  END LOOP;

  IF pg_catalog.to_regprocedure('public.is_admin()') IS NULL
     OR pg_catalog.to_regprocedure('public.handle_new_auth_user()') IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_trigger AS trigger_value
       WHERE trigger_value.tgrelid = 'auth.users'::regclass
         AND trigger_value.tgname = 'on_auth_user_created'
         AND NOT trigger_value.tgisinternal
         AND trigger_value.tgfoid =
           'public.handle_new_auth_user()'::regprocedure::oid
     )
     OR NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_trigger AS trigger_value
       JOIN pg_catalog.pg_proc AS procedure_value
         ON procedure_value.oid = trigger_value.tgfoid
       JOIN pg_catalog.pg_namespace AS namespace
         ON namespace.oid = procedure_value.pronamespace
       WHERE trigger_value.tgrelid = booking_oid
         AND trigger_value.tgname = 'trg_bookings_updated_at'
         AND NOT trigger_value.tgisinternal
         AND trigger_value.tgenabled <> 'D'
         AND namespace.nspname = 'public'
         AND procedure_value.proname = 'set_updated_at'
     )
  THEN
    RAISE EXCEPTION
      'Booking Foundation verification failed: Foundation or updated_at trigger drifted.';
  END IF;

  SELECT count(*)
  INTO catalog_policy_count
  FROM pg_catalog.pg_policy AS policy
  JOIN pg_catalog.pg_class AS class
    ON class.oid = policy.polrelid
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = class.relnamespace
  WHERE namespace.nspname = 'public'
    AND class.relname IN (
      'branches',
      'room_types',
      'rooms',
      'amenities',
      'room_images',
      'room_amenities',
      'promotions'
    );

  IF catalog_policy_count <> 14 THEN
    RAISE EXCEPTION
      'Booking Foundation verification failed: Catalog policy count changed.';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_class AS class
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = class.relnamespace
    WHERE namespace.nspname = 'public'
      AND class.relname IN (
        'branches',
        'room_types',
        'rooms',
        'amenities',
        'room_images',
        'room_amenities',
        'promotions'
      )
      AND class.relkind IN ('r', 'p')
      AND class.relrowsecurity
      AND NOT class.relforcerowsecurity
  ) <> 7 THEN
    RAISE EXCEPTION
      'Booking Foundation verification failed: Catalog RLS state changed.';
  END IF;
END;
$postconditions$;

COMMIT;

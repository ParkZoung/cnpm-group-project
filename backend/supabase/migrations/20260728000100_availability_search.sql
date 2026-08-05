BEGIN;

/*
 * GoStay Availability Search
 *
 * This migration adds one read-only catalog RPC. It intentionally does not
 * change bookings RLS, table privileges, create_booking, or the existing
 * overlap exclusion constraint.
 */
DO $preconditions$
DECLARE
  holding_constraint_definition text;
  holding_statuses text[];
  booking_statuses text[];
  own_policy_valid boolean;
  admin_policy_valid boolean;
  create_booking_valid boolean;
  table_privileges_valid boolean;
BEGIN
  IF pg_catalog.to_regclass('public.rooms') IS NULL
     OR pg_catalog.to_regclass('public.branches') IS NULL
     OR pg_catalog.to_regclass('public.room_types') IS NULL
     OR pg_catalog.to_regclass('public.room_images') IS NULL
     OR pg_catalog.to_regclass('public.bookings') IS NULL
  THEN
    RAISE EXCEPTION
      'Availability Search stopped: required catalog or booking tables are missing.';
  END IF;

  IF pg_catalog.to_regprocedure(
    'public.search_available_rooms(date,date,integer,bigint,bigint,bigint,bigint)'
  ) IS NOT NULL THEN
    RAISE EXCEPTION
      'Availability Search stopped: the target RPC signature already exists.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_value
    WHERE procedure_value.pronamespace = 'public'::regnamespace
      AND procedure_value.proname = 'search_available_rooms'
  ) THEN
    RAISE EXCEPTION
      'Availability Search stopped: a conflicting RPC overload exists.';
  END IF;

  IF pg_catalog.to_regprocedure(
    'public.create_booking(bigint,date,date,integer,text,text,text,text)'
  ) IS NULL THEN
    RAISE EXCEPTION
      'Availability Search stopped: create_booking is missing.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute
    WHERE attribute.attrelid = 'public.bookings'::regclass
      AND attribute.attname = 'user_id'
      AND attribute.atttypid = 'uuid'::regtype
      AND attribute.attnotnull
      AND NOT attribute.attisdropped
  ) THEN
    RAISE EXCEPTION
      'Availability Search stopped: bookings.user_id is not required.';
  END IF;

  SELECT
    count(*) FILTER (
      WHERE policy.polname = 'bookings_select_own'
        AND policy.polcmd = 'r'
        AND policy.polpermissive
        AND (
          SELECT array_agg(
            CASE role_oid
              WHEN 0 THEN 'PUBLIC'::text
              ELSE pg_catalog.pg_get_userbyid(role_oid)::text
            END
            ORDER BY role_oid
          )
          FROM pg_catalog.unnest(policy.polroles) AS role(role_oid)
        ) = ARRAY['authenticated']::text[]
        AND policy.polwithcheck IS NULL
        AND pg_catalog.regexp_replace(
          pg_catalog.regexp_replace(
            pg_catalog.regexp_replace(
              pg_catalog.regexp_replace(
                pg_catalog.lower(
                  pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
                ),
                '[[:space:]]+',
                '',
                'g'
              ),
              '::((pg_catalog[.])?uuid|(pg_catalog[.])?text)',
              '',
              'g'
            ),
            '(public[.])?bookings[.]',
            '',
            'g'
          ),
          '[()]',
          '',
          'g'
        ) = 'user_id=auth.uid'
    ) = 1,
    count(*) FILTER (
      WHERE policy.polname = 'bookings_select_admin'
        AND policy.polcmd = 'r'
        AND policy.polpermissive
        AND (
          SELECT array_agg(
            CASE role_oid
              WHEN 0 THEN 'PUBLIC'::text
              ELSE pg_catalog.pg_get_userbyid(role_oid)::text
            END
            ORDER BY role_oid
          )
          FROM pg_catalog.unnest(policy.polroles) AS role(role_oid)
        ) = ARRAY['authenticated']::text[]
        AND policy.polwithcheck IS NULL
        AND pg_catalog.regexp_replace(
          pg_catalog.regexp_replace(
            pg_catalog.lower(
              pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
            ),
            '[[:space:]]+',
            '',
            'g'
          ),
          '[()]',
          '',
          'g'
        ) IN ('is_admin', 'public.is_admin')
    ) = 1
  INTO own_policy_valid, admin_policy_valid
  FROM pg_catalog.pg_policy AS policy
  WHERE policy.polrelid = 'public.bookings'::regclass;

  IF NOT own_policy_valid OR NOT admin_policy_valid THEN
    RAISE EXCEPTION
      'Availability Search stopped: booking SELECT policy definitions drifted.';
  END IF;

  SELECT
    NOT EXISTS (
      SELECT 1
      FROM pg_catalog.aclexplode(
        coalesce(
          class.relacl,
          pg_catalog.acldefault('r', class.relowner)
        )
      ) AS acl
      WHERE acl.grantee = 0
    )
    AND NOT EXISTS (
      SELECT 1
      FROM (
        VALUES
          ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'),
          ('TRUNCATE'), ('REFERENCES'), ('TRIGGER'), ('MAINTAIN')
      ) AS privilege(name)
      WHERE pg_catalog.has_table_privilege(
        'anon', class.oid, privilege.name
      )
    )
    AND pg_catalog.has_table_privilege(
      'authenticated', class.oid, 'SELECT'
    )
    AND NOT EXISTS (
      SELECT 1
      FROM (
        VALUES
          ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'),
          ('REFERENCES'), ('TRIGGER'), ('MAINTAIN')
      ) AS privilege(name)
      WHERE pg_catalog.has_table_privilege(
        'authenticated', class.oid, privilege.name
      )
    )
    AND NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS attribute
      CROSS JOIN LATERAL pg_catalog.aclexplode(attribute.attacl) AS acl
      WHERE attribute.attrelid = class.oid
        AND attribute.attnum > 0
        AND NOT attribute.attisdropped
        AND (
          acl.grantee = 0
          OR acl.grantee = 'anon'::regrole
          OR acl.grantee = 'authenticated'::regrole
        )
    )
  INTO table_privileges_valid
  FROM pg_catalog.pg_class AS class
  WHERE class.oid = 'public.bookings'::regclass;

  IF NOT table_privileges_valid THEN
    RAISE EXCEPTION
      'Availability Search stopped: booking table privileges drifted.';
  END IF;

  SELECT
    count(*) = 1
    AND bool_and(
      pg_catalog.oidvectortypes(procedure_value.proargtypes) =
        'bigint, date, date, integer, text, text, text, text'
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
      AND NOT EXISTS (
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
      AND NOT pg_catalog.has_function_privilege(
        'anon', procedure_value.oid, 'EXECUTE'
      )
      AND pg_catalog.has_function_privilege(
        'authenticated', procedure_value.oid, 'EXECUTE'
      )
    )
  INTO create_booking_valid
  FROM pg_catalog.pg_proc AS procedure_value
  WHERE procedure_value.pronamespace = 'public'::regnamespace
    AND procedure_value.proname = 'create_booking';

  IF NOT create_booking_valid THEN
    RAISE EXCEPTION
      'Availability Search stopped: create_booking security contract drifted.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS class
    WHERE class.oid = 'public.bookings'::regclass
      AND class.relrowsecurity
      AND NOT class.relforcerowsecurity
  ) OR (
    SELECT count(*)
    FROM pg_catalog.pg_policy AS policy
    WHERE policy.polrelid = 'public.bookings'::regclass
  ) <> 2 OR (
    SELECT count(*)
    FROM pg_catalog.pg_policy AS policy
    WHERE policy.polrelid = 'public.bookings'::regclass
      AND policy.polname IN ('bookings_select_own', 'bookings_select_admin')
      AND policy.polcmd = 'r'
  ) <> 2 THEN
    RAISE EXCEPTION
      'Availability Search stopped: booking RLS foundation has drifted.';
  END IF;

  SELECT pg_catalog.pg_get_constraintdef(constraint_value.oid, true)
  INTO holding_constraint_definition
  FROM pg_catalog.pg_constraint AS constraint_value
  WHERE constraint_value.conrelid = 'public.bookings'::regclass
    AND constraint_value.conname = 'bookings_no_holding_overlap'
    AND constraint_value.contype = 'x'
    AND constraint_value.convalidated;

  SELECT array_agg(DISTINCT status_match.value[1] ORDER BY status_match.value[1])
  INTO holding_statuses
  FROM pg_catalog.regexp_matches(
    holding_constraint_definition,
    $pattern$'([^']+)'$pattern$,
    'g'
  ) AS status_match(value)
  WHERE status_match.value[1] <> '[)';

  IF holding_constraint_definition IS NULL
     OR pg_catalog.regexp_replace(
       pg_catalog.lower(holding_constraint_definition),
       '[[:space:]]+',
       '',
       'g'
     ) NOT LIKE '%daterange(check_in_date,check_out_date,''[)''%'
     OR holding_constraint_definition NOT LIKE '%booking_status%'
     OR holding_statuses IS DISTINCT FROM
       ARRAY['checked_in', 'confirmed', 'pending']::text[]
  THEN
    RAISE EXCEPTION
      'Availability Search stopped: holding-overlap constraint has drifted.';
  END IF;

  SELECT array_agg(DISTINCT status_match.value[1] ORDER BY status_match.value[1])
  INTO booking_statuses
  FROM pg_catalog.pg_constraint AS constraint_value
  JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = constraint_value.conrelid
   AND attribute.attname = 'booking_status'
   AND constraint_value.conkey = ARRAY[attribute.attnum]::smallint[]
  CROSS JOIN LATERAL pg_catalog.regexp_matches(
    pg_catalog.pg_get_constraintdef(constraint_value.oid, true),
    $pattern$'([^']+)'$pattern$,
    'g'
  ) AS status_match(value)
  WHERE constraint_value.conrelid = 'public.bookings'::regclass
    AND constraint_value.contype = 'c'
    AND constraint_value.convalidated;

  IF booking_statuses IS DISTINCT FROM ARRAY[
    'cancelled', 'checked_in', 'completed', 'confirmed', 'pending'
  ]::text[] THEN
    RAISE EXCEPTION
      'Availability Search stopped: booking status allowlist drifted.';
  END IF;
END;
$preconditions$;

CREATE FUNCTION public.search_available_rooms(
  p_check_in_date date,
  p_check_out_date date,
  p_guests integer,
  p_branch_id bigint DEFAULT NULL,
  p_room_type_id bigint DEFAULT NULL,
  p_min_price bigint DEFAULT NULL,
  p_max_price bigint DEFAULT NULL
)
RETURNS TABLE (
  room_id bigint,
  branch_id bigint,
  branch_name character varying,
  branch_city character varying,
  room_type_id bigint,
  room_type_name character varying,
  room_type_capacity integer,
  room_type_bed_type character varying,
  room_type_area_m2 numeric,
  room_number character varying,
  room_name character varying,
  room_description text,
  price_per_night bigint,
  image_url text,
  image_alt_text character varying
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF p_check_in_date IS NULL
     OR p_check_out_date IS NULL
     OR p_check_out_date <= p_check_in_date
     OR p_check_in_date < CURRENT_DATE
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'The availability date range is invalid.';
  END IF;

  IF p_guests IS NULL OR p_guests < 1 THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'The guest count is invalid.';
  END IF;

  IF p_min_price < 0
     OR p_max_price < 0
     OR (
       p_min_price IS NOT NULL
       AND p_max_price IS NOT NULL
       AND p_min_price > p_max_price
     )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'The price range is invalid.';
  END IF;

  RETURN QUERY
  SELECT
    room.id,
    branch.id,
    branch.name,
    branch.city,
    room_type.id,
    room_type.name,
    room_type.capacity,
    room_type.bed_type,
    room_type.area_m2,
    room.room_number,
    room.name,
    room.description,
    room.price_per_night,
    first_image.image_url,
    first_image.alt_text
  FROM public.rooms AS room
  JOIN public.branches AS branch
    ON branch.id = room.branch_id
  JOIN public.room_types AS room_type
    ON room_type.id = room.room_type_id
  LEFT JOIN LATERAL (
    SELECT
      image.image_url,
      image.alt_text
    FROM public.room_images AS image
    WHERE image.room_id = room.id
    ORDER BY image.is_primary DESC, image.sort_order ASC, image.id ASC
    LIMIT 1
  ) AS first_image ON true
  WHERE room.status = 'available'::character varying
    AND branch.status = 'active'::character varying
    AND room_type.capacity >= p_guests
    AND (p_branch_id IS NULL OR room.branch_id = p_branch_id)
    AND (p_room_type_id IS NULL OR room.room_type_id = p_room_type_id)
    AND (p_min_price IS NULL OR room.price_per_night >= p_min_price)
    AND (p_max_price IS NULL OR room.price_per_night <= p_max_price)
    AND NOT EXISTS (
      SELECT 1
      FROM public.bookings AS booking
      WHERE booking.room_id = room.id
        AND booking.booking_status IN (
          'pending'::character varying,
          'confirmed'::character varying,
          'checked_in'::character varying
        )
        AND booking.check_in_date < p_check_out_date
        AND booking.check_out_date > p_check_in_date
    )
  ORDER BY
    room.price_per_night ASC,
    branch.id ASC,
    room.room_number ASC,
    room.id ASC;
END;
$function$;

ALTER FUNCTION public.search_available_rooms(
  date, date, integer, bigint, bigint, bigint, bigint
) OWNER TO postgres;

REVOKE EXECUTE ON FUNCTION public.search_available_rooms(
  date, date, integer, bigint, bigint, bigint, bigint
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.search_available_rooms(
  date, date, integer, bigint, bigint, bigint, bigint
) TO anon, authenticated;

DO $postconditions$
DECLARE
  function_oid oid :=
    'public.search_available_rooms(date,date,integer,bigint,bigint,bigint,bigint)'::regprocedure;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_value
    WHERE procedure_value.oid = function_oid
      AND procedure_value.prosecdef
      AND procedure_value.provolatile = 's'
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
      AND NOT EXISTS (
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
      AND pg_catalog.has_function_privilege('anon', function_oid, 'EXECUTE')
      AND pg_catalog.has_function_privilege('authenticated', function_oid, 'EXECUTE')
  ) THEN
    RAISE EXCEPTION
      'Availability Search verification failed: RPC security is incorrect.';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_policy AS policy
    WHERE policy.polrelid = 'public.bookings'::regclass
      AND policy.polcmd = 'r'
  ) <> 2 OR (
    SELECT count(*)
    FROM pg_catalog.pg_policy AS policy
    WHERE policy.polrelid = 'public.bookings'::regclass
      AND policy.polname IN ('bookings_select_own', 'bookings_select_admin')
      AND policy.polcmd = 'r'
  ) <> 2 THEN
    RAISE EXCEPTION
      'Availability Search verification failed: booking RLS policies changed.';
  END IF;
END;
$postconditions$;

COMMIT;

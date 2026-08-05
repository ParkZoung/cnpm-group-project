/* GoStay Availability Search - read-only, fail-closed postcheck. */
WITH
booking_relation AS (
  SELECT oid, relrowsecurity, relforcerowsecurity, relacl, relowner
  FROM pg_catalog.pg_class
  WHERE oid = pg_catalog.to_regclass('public.bookings')
    AND relkind IN ('r', 'p')
),
policy_catalog AS (
  SELECT
    policy.polname::text AS name,
    policy.polcmd,
    policy.polpermissive,
    (
      SELECT array_agg(
        CASE role_oid WHEN 0 THEN 'PUBLIC'
          ELSE pg_catalog.pg_get_userbyid(role_oid) END
        ORDER BY role_oid
      )::text[]
      FROM pg_catalog.unnest(policy.polroles) AS role(role_oid)
    ) AS roles,
    policy.polwithcheck,
    pg_catalog.regexp_replace(
      pg_catalog.regexp_replace(
        pg_catalog.regexp_replace(
          pg_catalog.regexp_replace(
            pg_catalog.lower(pg_catalog.pg_get_expr(
              policy.polqual, policy.polrelid
            )), '[[:space:]]+', '', 'g'
          ),
          '::((pg_catalog[.])?uuid|(pg_catalog[.])?text)', '', 'g'
        ),
        '(public[.])?bookings[.]', '', 'g'
      ),
      '[()]', '', 'g'
    ) AS canonical_using
  FROM booking_relation AS relation
  JOIN pg_catalog.pg_policy AS policy ON policy.polrelid = relation.oid
),
policy_state AS (
  SELECT count(*) = 2
    AND count(*) FILTER (
      WHERE name = 'bookings_select_own' AND polcmd = 'r'
        AND polpermissive AND roles = ARRAY['authenticated']::text[]
        AND polwithcheck IS NULL AND canonical_using = 'user_id=auth.uid'
    ) = 1
    AND count(*) FILTER (
      WHERE name = 'bookings_select_admin' AND polcmd = 'r'
        AND polpermissive AND roles = ARRAY['authenticated']::text[]
        AND polwithcheck IS NULL
        AND canonical_using IN ('is_admin', 'public.is_admin')
    ) = 1 AS booking_policies_exact
  FROM policy_catalog
),
privilege_names(name) AS (
  VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'),
    ('TRUNCATE'), ('REFERENCES'), ('TRIGGER'), ('MAINTAIN')
),
foundation_state AS (
  SELECT
    coalesce((SELECT relrowsecurity AND NOT relforcerowsecurity
      FROM booking_relation), false) AS booking_rls_ok,
    NOT EXISTS (
      SELECT 1 FROM booking_relation AS relation
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        coalesce(relation.relacl,
          pg_catalog.acldefault('r', relation.relowner))
      ) AS acl WHERE acl.grantee = 0
    ) AS public_none,
    NOT EXISTS (
      SELECT 1 FROM booking_relation AS relation
      CROSS JOIN privilege_names AS privilege
      WHERE pg_catalog.has_table_privilege(
        'anon', relation.oid, privilege.name
      )
    ) AS anon_none,
    EXISTS (
      SELECT 1 FROM booking_relation AS relation
      WHERE pg_catalog.has_table_privilege(
        'authenticated', relation.oid, 'SELECT'
      )
    ) AND NOT EXISTS (
      SELECT 1 FROM booking_relation AS relation
      CROSS JOIN privilege_names AS privilege
      WHERE privilege.name <> 'SELECT'
        AND pg_catalog.has_table_privilege(
          'authenticated', relation.oid, privilege.name
        )
    ) AS authenticated_select_only,
    NOT EXISTS (
      SELECT 1 FROM booking_relation AS relation
      JOIN pg_catalog.pg_attribute AS attribute
        ON attribute.attrelid = relation.oid
       AND attribute.attnum > 0 AND NOT attribute.attisdropped
      CROSS JOIN LATERAL pg_catalog.aclexplode(attribute.attacl) AS acl
      WHERE acl.grantee IN (
        0, 'anon'::regrole::oid, 'authenticated'::regrole::oid
      )
    ) AS no_frontend_column_grants
),
create_booking_state AS (
  SELECT count(*) = 1 AND coalesce(bool_and(
    pg_catalog.oidvectortypes(proargtypes) =
      'bigint, date, date, integer, text, text, text, text'
    AND prosecdef AND provolatile = 'v'
    AND pg_catalog.pg_get_userbyid(proowner) = 'postgres'
    AND EXISTS (
      SELECT 1 FROM pg_catalog.unnest(proconfig) AS config(setting)
      WHERE pg_catalog.split_part(config.setting, '=', 1) = 'search_path'
        AND pg_catalog.replace(
          pg_catalog.split_part(config.setting, '=', 2), '"', ''
        ) = ''
    )
    AND NOT EXISTS (
      SELECT 1 FROM pg_catalog.aclexplode(
        coalesce(proacl, pg_catalog.acldefault('f', proowner))
      ) AS acl
      WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
    )
    AND NOT pg_catalog.has_function_privilege('anon', oid, 'EXECUTE')
    AND pg_catalog.has_function_privilege(
      'authenticated', oid, 'EXECUTE'
    )
  ), false) AS create_booking_security_exact
  FROM pg_catalog.pg_proc
  WHERE pronamespace = 'public'::regnamespace AND proname = 'create_booking'
),
constraint_state AS (
  SELECT
    (
      SELECT count(*) = 1 AND coalesce(bool_and(
        pg_catalog.regexp_replace(
          pg_catalog.lower(definition), '[[:space:]]+', '', 'g'
        ) LIKE '%daterange(check_in_date,check_out_date,''[)''%'
        AND (
          SELECT array_agg(DISTINCT match.value[1] ORDER BY match.value[1])
          FROM pg_catalog.regexp_matches(
            definition, $pattern$'([^']+)'$pattern$, 'g'
          ) AS match(value)
          WHERE match.value[1] <> '[)'
        ) = ARRAY['checked_in', 'confirmed', 'pending']::text[]
      ), false)
      FROM (
        SELECT pg_catalog.pg_get_constraintdef(constraint_value.oid, true)
          AS definition
        FROM booking_relation AS relation
        JOIN pg_catalog.pg_constraint AS constraint_value
          ON constraint_value.conrelid = relation.oid
         AND constraint_value.conname = 'bookings_no_holding_overlap'
         AND constraint_value.contype = 'x'
         AND constraint_value.convalidated
      ) AS holding
    ) AS holding_constraint_exact,
    (
      SELECT array_agg(DISTINCT match.value[1] ORDER BY match.value[1])
      FROM booking_relation AS relation
      JOIN pg_catalog.pg_constraint AS constraint_value
        ON constraint_value.conrelid = relation.oid
       AND constraint_value.contype = 'c'
       AND constraint_value.convalidated
      JOIN pg_catalog.pg_attribute AS attribute
        ON attribute.attrelid = relation.oid
       AND attribute.attname = 'booking_status'
       AND constraint_value.conkey = ARRAY[attribute.attnum]::smallint[]
      CROSS JOIN LATERAL pg_catalog.regexp_matches(
        pg_catalog.pg_get_constraintdef(constraint_value.oid, true),
        $pattern$'([^']+)'$pattern$, 'g'
      ) AS match(value)
    ) = ARRAY[
      'cancelled', 'checked_in', 'completed', 'confirmed', 'pending'
    ]::text[] AS booking_status_allowlist_exact
),
rpc_catalog AS (
  SELECT
    procedure_value.*,
    pg_catalog.pg_get_function_identity_arguments(procedure_value.oid)
      AS identity_arguments,
    pg_catalog.pg_get_function_result(procedure_value.oid) AS result_type,
    pg_catalog.lower(pg_catalog.regexp_replace(
      procedure_value.prosrc, '[[:space:]]+', '', 'g'
    )) AS normalized_body
  FROM pg_catalog.pg_proc AS procedure_value
  WHERE procedure_value.pronamespace = 'public'::regnamespace
    AND procedure_value.proname = 'search_available_rooms'
),
rpc_state AS (
  SELECT count(*) = 1 AS rpc_exists_once,
    coalesce(bool_and(
      identity_arguments =
        'p_check_in_date date, p_check_out_date date, p_guests integer, p_branch_id bigint, p_room_type_id bigint, p_min_price bigint, p_max_price bigint'
      AND result_type =
        'TABLE(room_id bigint, branch_id bigint, branch_name character varying, branch_city character varying, room_type_id bigint, room_type_name character varying, room_type_capacity integer, room_type_bed_type character varying, room_type_area_m2 numeric, room_number character varying, room_name character varying, room_description text, price_per_night bigint, image_url text, image_alt_text character varying)'
      AND prosecdef AND provolatile = 's'
      AND pg_catalog.pg_get_userbyid(proowner) = 'postgres'
      AND EXISTS (
        SELECT 1 FROM pg_catalog.unnest(proconfig) AS config(setting)
        WHERE pg_catalog.split_part(config.setting, '=', 1) = 'search_path'
          AND pg_catalog.replace(
            pg_catalog.split_part(config.setting, '=', 2), '"', ''
          ) = ''
      )
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.aclexplode(
          coalesce(proacl, pg_catalog.acldefault('f', proowner))
        ) AS acl
        WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
      )
      AND pg_catalog.has_function_privilege('anon', oid, 'EXECUTE')
      AND pg_catalog.has_function_privilege(
        'authenticated', oid, 'EXECUTE'
      )
    ), false) AS rpc_definition_exact,
    coalesce(bool_and(
      normalized_body LIKE
        '%booking.booking_statusin(''pending''::charactervarying,''confirmed''::charactervarying,''checked_in''::charactervarying)%'
      AND normalized_body LIKE '%booking.check_in_date<p_check_out_date%'
      AND normalized_body LIKE '%booking.check_out_date>p_check_in_date%'
      AND normalized_body NOT LIKE '%booking_status<>%'
      AND normalized_body NOT LIKE '%booking.guest_%'
      AND normalized_body NOT LIKE '%booking.user_id%'
      AND normalized_body NOT LIKE '%execute%'
    ), false) AS rpc_body_safe
  FROM rpc_catalog
),
checks AS (
  SELECT * FROM policy_state CROSS JOIN foundation_state
  CROSS JOIN create_booking_state CROSS JOIN constraint_state
  CROSS JOIN rpc_state
)
SELECT jsonb_build_object(
  'decision', CASE WHEN
    booking_policies_exact AND booking_rls_ok AND public_none AND anon_none
    AND authenticated_select_only AND no_frontend_column_grants
    AND create_booking_security_exact AND holding_constraint_exact
    AND booking_status_allowlist_exact AND rpc_exists_once
    AND rpc_definition_exact AND rpc_body_safe
    THEN 'POSTCHECK_PASSED' ELSE 'POSTCHECK_BLOCKED' END,
  'booking_policies_exact', booking_policies_exact,
  'booking_rls_ok', booking_rls_ok,
  'public_none', public_none,
  'anon_none', anon_none,
  'authenticated_select_only', authenticated_select_only,
  'no_frontend_column_grants', no_frontend_column_grants,
  'create_booking_security_exact', create_booking_security_exact,
  'holding_constraint_exact', holding_constraint_exact,
  'booking_status_allowlist_exact', booking_status_allowlist_exact,
  'rpc_exists_once', rpc_exists_once,
  'rpc_definition_exact', rpc_definition_exact,
  'rpc_body_safe', rpc_body_safe
) AS availability_search_postcheck
FROM checks;

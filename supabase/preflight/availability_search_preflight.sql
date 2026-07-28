/*
 * GoStay Availability Search - read-only, fail-closed preflight.
 * Catalog inspection only; returns no booking or customer rows.
 */
WITH
booking_relation AS (
  SELECT class.oid, class.relrowsecurity, class.relforcerowsecurity,
    class.relacl, class.relowner
  FROM pg_catalog.pg_class AS class
  WHERE class.oid = pg_catalog.to_regclass('public.bookings')
    AND class.relkind IN ('r', 'p')
),
required_relations(relation_name) AS (
  VALUES ('rooms'), ('branches'), ('room_types'), ('room_images'), ('bookings')
),
relation_state AS (
  SELECT
    count(class.oid) = 5 AS required_relations_exist,
    coalesce((SELECT relrowsecurity AND NOT relforcerowsecurity
      FROM booking_relation), false) AS booking_rls_ok
  FROM required_relations AS required
  LEFT JOIN pg_catalog.pg_class AS class
    ON class.relname = required.relation_name
   AND class.relnamespace = 'public'::regnamespace
   AND class.relkind IN ('r', 'p')
),
owner_column_state AS (
  SELECT count(*) = 1 AS booking_owner_required
  FROM booking_relation AS relation
  JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = relation.oid
   AND attribute.attname = 'user_id'
   AND attribute.atttypid = 'uuid'::regtype
   AND attribute.attnotnull
   AND NOT attribute.attisdropped
),
policy_catalog AS (
  SELECT
    policy.oid,
    policy.polname::text AS policy_name,
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
            )),
            '[[:space:]]+', '', 'g'
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
  SELECT
    count(*) = 2
    AND count(*) FILTER (
      WHERE policy_name = 'bookings_select_own'
        AND polcmd = 'r'
        AND polpermissive
        AND roles = ARRAY['authenticated']::text[]
        AND polwithcheck IS NULL
        AND canonical_using = 'user_id=auth.uid'
    ) = 1
    AND count(*) FILTER (
      WHERE policy_name = 'bookings_select_admin'
        AND polcmd = 'r'
        AND polpermissive
        AND roles = ARRAY['authenticated']::text[]
        AND polwithcheck IS NULL
        AND canonical_using IN ('is_admin', 'public.is_admin')
    ) = 1 AS booking_policies_exact
  FROM policy_catalog
),
privilege_names(name) AS (
  VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'),
    ('TRUNCATE'), ('REFERENCES'), ('TRIGGER'), ('MAINTAIN')
),
privilege_state AS (
  SELECT
    NOT EXISTS (
      SELECT 1
      FROM booking_relation AS relation
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        coalesce(relation.relacl,
          pg_catalog.acldefault('r', relation.relowner))
      ) AS acl
      WHERE acl.grantee = 0
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
    )
    AND NOT EXISTS (
      SELECT 1 FROM booking_relation AS relation
      CROSS JOIN privilege_names AS privilege
      WHERE privilege.name <> 'SELECT'
        AND pg_catalog.has_table_privilege(
          'authenticated', relation.oid, privilege.name
        )
    ) AS authenticated_select_only,
    NOT EXISTS (
      SELECT 1
      FROM booking_relation AS relation
      JOIN pg_catalog.pg_attribute AS attribute
        ON attribute.attrelid = relation.oid
       AND attribute.attnum > 0
       AND NOT attribute.attisdropped
      CROSS JOIN LATERAL pg_catalog.aclexplode(attribute.attacl) AS acl
      WHERE acl.grantee IN (
        0, 'anon'::regrole::oid, 'authenticated'::regrole::oid
      )
    ) AS no_frontend_column_grants
),
create_booking_catalog AS (
  SELECT procedure_value.*
  FROM pg_catalog.pg_proc AS procedure_value
  WHERE procedure_value.pronamespace = 'public'::regnamespace
    AND procedure_value.proname = 'create_booking'
),
create_booking_state AS (
  SELECT count(*) = 1 AND coalesce(bool_and(
    pg_catalog.oidvectortypes(proargtypes) =
      'bigint, date, date, integer, text, text, text, text'
    AND prosecdef
    AND provolatile = 'v'
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
  FROM create_booking_catalog
),
holding_constraint AS (
  SELECT
    constraint_value.oid,
    pg_catalog.pg_get_constraintdef(constraint_value.oid, true) AS definition
  FROM booking_relation AS relation
  JOIN pg_catalog.pg_constraint AS constraint_value
    ON constraint_value.conrelid = relation.oid
   AND constraint_value.conname = 'bookings_no_holding_overlap'
   AND constraint_value.contype = 'x'
   AND constraint_value.convalidated
),
holding_state AS (
  SELECT count(*) = 1
    AND coalesce(bool_and(
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
    ), false) AS holding_constraint_exact
  FROM holding_constraint
),
booking_status_state AS (
  SELECT (
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
target_state AS (
  SELECT count(*) = 0 AS target_name_free
  FROM pg_catalog.pg_proc
  WHERE pronamespace = 'public'::regnamespace
    AND proname = 'search_available_rooms'
),
checks AS (
  SELECT * FROM relation_state
  CROSS JOIN owner_column_state
  CROSS JOIN policy_state
  CROSS JOIN privilege_state
  CROSS JOIN create_booking_state
  CROSS JOIN holding_state
  CROSS JOIN booking_status_state
  CROSS JOIN target_state
)
SELECT jsonb_build_object(
  'decision', CASE WHEN
    required_relations_exist AND booking_rls_ok AND booking_owner_required
    AND booking_policies_exact AND public_none AND anon_none
    AND authenticated_select_only AND no_frontend_column_grants
    AND create_booking_security_exact AND holding_constraint_exact
    AND booking_status_allowlist_exact AND target_name_free
    THEN 'PREFLIGHT_PASSED' ELSE 'PREFLIGHT_BLOCKED' END,
  'required_relations_exist', required_relations_exist,
  'booking_rls_ok', booking_rls_ok,
  'booking_owner_required', booking_owner_required,
  'booking_policies_exact', booking_policies_exact,
  'public_none', public_none,
  'anon_none', anon_none,
  'authenticated_select_only', authenticated_select_only,
  'no_frontend_column_grants', no_frontend_column_grants,
  'create_booking_security_exact', create_booking_security_exact,
  'holding_constraint_exact', holding_constraint_exact,
  'booking_status_allowlist_exact', booking_status_allowlist_exact,
  'target_name_free', target_name_free
) AS availability_search_preflight
FROM checks;

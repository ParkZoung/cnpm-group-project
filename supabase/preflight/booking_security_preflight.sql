/*
 * GoStay Booking Security Foundation — read-only preflight
 *
 * Safety:
 * - This file is one WITH ... SELECT statement.
 * - It performs catalog inspection and aggregate SELECTs only.
 * - It returns no booking rows or personal data.
 * - query_to_xml() is used only to run guarded aggregate SELECT statements,
 *   allowing the preflight to return PREFLIGHT_FAILED when a required relation
 *   or column is missing instead of failing at parse time.
 */
WITH
expected_columns(column_name, expected_type) AS (
  VALUES
    ('id', 'uuid'),
    ('booking_code', 'character varying'),
    ('user_id', 'uuid'),
    ('room_id', 'bigint'),
    ('promotion_id', 'bigint'),
    ('check_in_date', 'date'),
    ('check_out_date', 'date'),
    ('number_of_nights', 'integer'),
    ('number_of_guests', 'integer'),
    ('price_per_night', 'bigint'),
    ('subtotal', 'bigint'),
    ('tax_rate', 'numeric'),
    ('tax_amount', 'bigint'),
    ('discount_amount', 'bigint'),
    ('total_amount', 'bigint'),
    ('booking_status', 'character varying'),
    ('payment_method', 'character varying'),
    ('payment_status', 'character varying'),
    ('cancelled_at', 'timestamp with time zone'),
    ('created_at', 'timestamp with time zone'),
    ('updated_at', 'timestamp with time zone')
),
target_relation AS (
  SELECT
    class.oid AS relation_oid,
    namespace.nspname::text AS schema_name,
    class.relname::text AS table_name,
    class.relkind::text AS relation_kind,
    class.relrowsecurity AS rls_enabled,
    class.relforcerowsecurity AS force_rls,
    class.relowner AS owner_oid,
    pg_catalog.pg_get_userbyid(class.relowner)::text AS owner_name,
    class.relacl
  FROM pg_catalog.pg_class AS class
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = class.relnamespace
  WHERE namespace.nspname = 'public'
    AND class.relname = 'bookings'
),
relation_state AS (
  SELECT
    count(*) = 1
      AND count(*) FILTER (WHERE relation_kind IN ('r', 'p')) = 1
      AS bookings_table_exists,
    count(*) = 1 AS bookings_relation_name_unique,
    max(relation_oid) FILTER (WHERE relation_kind IN ('r', 'p'))
      AS booking_relation_oid,
    coalesce(bool_or(rls_enabled) FILTER (WHERE relation_kind IN ('r', 'p')), false)
      AS rls_enabled,
    coalesce(bool_or(force_rls) FILTER (WHERE relation_kind IN ('r', 'p')), false)
      AS force_rls,
    max(owner_name) FILTER (WHERE relation_kind IN ('r', 'p')) AS owner_name,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'schema', schema_name,
          'name', table_name,
          'relation_kind', relation_kind
        )
        ORDER BY schema_name, table_name
      ),
      '[]'::jsonb
    ) AS matching_relations
  FROM target_relation
),
column_catalog AS (
  SELECT
    attribute.attnum AS ordinal_position,
    attribute.attname::text AS column_name,
    pg_catalog.format_type(attribute.atttypid, attribute.atttypmod)::text
      AS data_type,
    attribute.atttypid AS type_oid,
    NOT attribute.attnotnull AS nullable,
    pg_catalog.pg_get_expr(default_value.adbin, default_value.adrelid, true)
      AS column_default,
    attribute.attidentity::text AS identity_mode,
    attribute.attgenerated::text AS generated_mode
  FROM relation_state AS relation
  JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = relation.booking_relation_oid
  LEFT JOIN pg_catalog.pg_attrdef AS default_value
    ON default_value.adrelid = attribute.attrelid
   AND default_value.adnum = attribute.attnum
  WHERE attribute.attnum > 0
    AND NOT attribute.attisdropped
),
column_state AS (
  SELECT
    count(*) FILTER (WHERE actual.column_name IS NULL) = 0
      AS all_expected_columns_exist,
    count(*) FILTER (
      WHERE actual.column_name IS NOT NULL
        AND actual.type_oid <> expected.expected_type::regtype
    ) = 0 AS expected_column_types_match,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'column', expected.column_name,
          'expected_type', expected.expected_type,
          'actual_type', actual.data_type,
          'exists', actual.column_name IS NOT NULL,
          'type_matches',
            actual.type_oid = expected.expected_type::regtype
        )
        ORDER BY expected.column_name
      ),
      '[]'::jsonb
    ) AS expected_column_checks
  FROM expected_columns AS expected
  LEFT JOIN column_catalog AS actual
    ON actual.column_name = expected.column_name
),
column_report AS (
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'name', column_name,
        'type', data_type,
        'nullable', nullable,
        'default', column_default,
        'identity_mode', nullif(identity_mode, ''),
        'generated_mode', nullif(generated_mode, '')
      )
      ORDER BY ordinal_position
    ),
    '[]'::jsonb
  ) AS columns
  FROM column_catalog
),
constraint_catalog AS (
  SELECT
    constraint_value.oid AS constraint_oid,
    constraint_value.conname::text AS constraint_name,
    constraint_value.contype::text AS constraint_type_code,
    CASE constraint_value.contype
      WHEN 'p' THEN 'PRIMARY KEY'
      WHEN 'u' THEN 'UNIQUE'
      WHEN 'c' THEN 'CHECK'
      WHEN 'f' THEN 'FOREIGN KEY'
      WHEN 'x' THEN 'EXCLUSION'
      ELSE constraint_value.contype::text
    END AS constraint_type,
    constraint_value.convalidated AS validated,
    pg_catalog.pg_get_constraintdef(constraint_value.oid, true)
      AS constraint_definition,
    constraint_value.confrelid AS referenced_relation_oid
  FROM relation_state AS relation
  JOIN pg_catalog.pg_constraint AS constraint_value
    ON constraint_value.conrelid = relation.booking_relation_oid
),
constraint_report AS (
  SELECT
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'name', constraint_name,
          'type', constraint_type,
          'type_code', constraint_type_code,
          'validated', validated,
          'definition', constraint_definition
        )
        ORDER BY constraint_type, constraint_name
      ),
      '[]'::jsonb
    ) AS constraints,
    count(*) FILTER (WHERE constraint_type_code = 'p') = 1
      AS primary_key_exists,
    count(*) FILTER (WHERE constraint_type_code = 'u') > 0
      AS unique_constraint_exists,
    count(*) FILTER (WHERE constraint_type_code = 'x') > 0
      AS exclusion_constraint_exists,
    coalesce(bool_or(
      constraint_type_code = 'c'
      AND regexp_replace(lower(constraint_definition), '\s+', '', 'g')
          ~ 'check_out_date>check_in_date'
    ), false) AS valid_date_constraint_detected,
    coalesce(bool_or(
      constraint_type_code = 'c'
      AND regexp_replace(lower(constraint_definition), '\s+', '', 'g')
          ~ 'number_of_nights.*check_out_date.*check_in_date'
    ), false) AS nights_consistency_constraint_detected,
    coalesce(bool_or(
      constraint_type_code = 'c'
      AND lower(constraint_definition) LIKE '%booking_status%'
    ), false) AS booking_status_constraint_detected,
    coalesce(bool_or(
      constraint_type_code = 'c'
      AND lower(constraint_definition) LIKE '%payment_status%'
    ), false) AS payment_status_constraint_detected,
    coalesce(bool_or(
      constraint_type_code = 'c'
      AND lower(constraint_definition) LIKE '%cancelled_at%'
    ), false) AS cancellation_consistency_constraint_detected,
    coalesce(bool_or(
      constraint_type_code = 'c'
      AND (
        lower(constraint_definition) LIKE '%price_per_night%'
        OR lower(constraint_definition) LIKE '%subtotal%'
        OR lower(constraint_definition) LIKE '%tax_amount%'
        OR lower(constraint_definition) LIKE '%discount_amount%'
        OR lower(constraint_definition) LIKE '%total_amount%'
      )
    ), false) AS monetary_check_constraints_detected
  FROM constraint_catalog
),
not_null_state AS (
  SELECT coalesce(
    bool_or(column_name = 'user_id' AND NOT nullable),
    false
  ) AS user_id_not_null
  FROM column_catalog
),
foreign_key_report AS (
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'name', constraint_name,
        'validated', validated,
        'definition', constraint_definition,
        'referenced_relation',
          coalesce(
            constraint_value.referenced_relation_oid::regclass::text,
            null
          )
      )
      ORDER BY constraint_name
    ) FILTER (WHERE constraint_type_code = 'f'),
    '[]'::jsonb
  ) AS foreign_keys
  FROM constraint_catalog AS constraint_value
),
index_catalog AS (
  SELECT
    index_class.oid AS index_oid,
    index_class.relname::text AS index_name,
    index_value.indisprimary AS is_primary,
    index_value.indisunique AS is_unique,
    index_value.indisvalid AS is_valid,
    index_value.indisready AS is_ready,
    pg_catalog.pg_get_indexdef(index_value.indexrelid, 0, true)
      AS index_definition,
    coalesce(
      array_agg(attribute.attname::text ORDER BY key_position.ordinality)
        FILTER (WHERE attribute.attname IS NOT NULL),
      ARRAY[]::text[]
    ) AS key_columns
  FROM relation_state AS relation
  JOIN pg_catalog.pg_index AS index_value
    ON index_value.indrelid = relation.booking_relation_oid
  JOIN pg_catalog.pg_class AS index_class
    ON index_class.oid = index_value.indexrelid
  LEFT JOIN LATERAL pg_catalog.unnest(index_value.indkey)
    WITH ORDINALITY AS key_position(attribute_number, ordinality)
    ON key_position.ordinality <= index_value.indnkeyatts
  LEFT JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = relation.booking_relation_oid
   AND attribute.attnum = key_position.attribute_number
  GROUP BY
    index_class.oid,
    index_class.relname,
    index_value.indisprimary,
    index_value.indisunique,
    index_value.indisvalid,
    index_value.indisready,
    index_value.indexrelid
),
index_state AS (
  SELECT
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'name', index_name,
          'primary', is_primary,
          'unique', is_unique,
          'valid', is_valid,
          'ready', is_ready,
          'key_columns', to_jsonb(key_columns),
          'definition', index_definition
        )
        ORDER BY index_name
      ),
      '[]'::jsonb
    ) AS indexes,
    coalesce(bool_or(key_columns @> ARRAY['user_id']::text[]), false)
      AS user_id_index_exists,
    coalesce(bool_or(key_columns @> ARRAY['room_id']::text[]), false)
      AS room_id_index_exists,
    coalesce(bool_or(key_columns @> ARRAY['booking_status']::text[]), false)
      AS booking_status_index_exists,
    coalesce(bool_or(key_columns @> ARRAY['payment_status']::text[]), false)
      AS payment_status_index_exists,
    coalesce(bool_or(
      key_columns @> ARRAY['room_id', 'check_in_date', 'check_out_date']::text[]
      OR (
        index_definition ILIKE '%room_id%'
        AND index_definition ILIKE '%daterange%'
      )
    ), false) AS availability_index_exists,
    coalesce(bool_or(
      key_columns[1:2] = ARRAY['user_id', 'created_at']::text[]
      OR key_columns[1:2] = ARRAY['user_id', 'check_in_date']::text[]
    ), false) AS customer_history_index_exists
  FROM index_catalog
),
policy_catalog AS (
  SELECT
    policy.oid AS policy_oid,
    policy.polname::text AS policy_name,
    policy.polcmd::text AS command_code,
    CASE policy.polcmd
      WHEN 'r' THEN 'SELECT'
      WHEN 'a' THEN 'INSERT'
      WHEN 'w' THEN 'UPDATE'
      WHEN 'd' THEN 'DELETE'
      WHEN '*' THEN 'ALL'
      ELSE policy.polcmd::text
    END AS command,
    policy.polpermissive AS permissive,
    (
      SELECT coalesce(
        array_agg(normalized.role_name ORDER BY normalized.role_name),
        ARRAY[]::text[]
      )
      FROM (
        SELECT CASE role_value.role_oid
          WHEN 0 THEN 'PUBLIC'::text
          ELSE pg_catalog.pg_get_userbyid(role_value.role_oid)::text
        END AS role_name
        FROM pg_catalog.unnest(policy.polroles) AS role_value(role_oid)
      ) AS normalized
    )::text[] AS roles,
    pg_catalog.pg_get_expr(policy.polqual, policy.polrelid, true)
      AS using_expression,
    pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid, true)
      AS with_check_expression
  FROM relation_state AS relation
  JOIN pg_catalog.pg_policy AS policy
    ON policy.polrelid = relation.booking_relation_oid
),
policy_report AS (
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'name', policy_name,
        'command', command,
        'command_code', command_code,
        'roles', to_jsonb(roles),
        'mode', CASE WHEN permissive THEN 'PERMISSIVE' ELSE 'RESTRICTIVE' END,
        'using', using_expression,
        'with_check', with_check_expression
      )
      ORDER BY policy_name
    ),
    '[]'::jsonb
  ) AS policies
  FROM policy_catalog
),
frontend_roles(role_name) AS (
  VALUES ('PUBLIC'::text), ('anon'::text), ('authenticated'::text),
         ('service_role'::text)
),
role_catalog AS (
  SELECT
    requested.role_name,
    role_value.oid AS role_oid,
    role_value.rolname IS NOT NULL AS role_exists
  FROM frontend_roles AS requested
  LEFT JOIN pg_catalog.pg_roles AS role_value
    ON role_value.rolname::text = requested.role_name
),
direct_table_acl AS (
  SELECT
    CASE acl.grantee
      WHEN 0 THEN 'PUBLIC'::text
      ELSE pg_catalog.pg_get_userbyid(acl.grantee)::text
    END AS grantee,
    acl.privilege_type::text AS privilege_type,
    acl.is_grantable
  FROM target_relation AS relation
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    coalesce(
      relation.relacl,
      pg_catalog.acldefault('r', relation.owner_oid)
    )
  ) AS acl
  WHERE acl.grantee = 0
     OR pg_catalog.pg_get_userbyid(acl.grantee)::text
        IN ('anon', 'authenticated', 'service_role')
),
table_privilege_report AS (
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'role', role_value.role_name,
        'role_exists', role_value.role_exists,
        'direct', coalesce(direct_value.direct_privileges, '{}'::jsonb),
        'effective', jsonb_build_object(
          'SELECT', CASE WHEN role_value.role_name = 'PUBLIC'
            THEN EXISTS (
              SELECT 1 FROM direct_table_acl AS acl
              WHERE acl.grantee = 'PUBLIC' AND acl.privilege_type = 'SELECT'
            )
            ELSE coalesce(pg_catalog.has_table_privilege(
              role_value.role_oid, relation.booking_relation_oid, 'SELECT'
            ), false)
          END,
          'INSERT', CASE WHEN role_value.role_name = 'PUBLIC'
            THEN EXISTS (
              SELECT 1 FROM direct_table_acl AS acl
              WHERE acl.grantee = 'PUBLIC' AND acl.privilege_type = 'INSERT'
            )
            ELSE coalesce(pg_catalog.has_table_privilege(
              role_value.role_oid, relation.booking_relation_oid, 'INSERT'
            ), false)
          END,
          'UPDATE', CASE WHEN role_value.role_name = 'PUBLIC'
            THEN EXISTS (
              SELECT 1 FROM direct_table_acl AS acl
              WHERE acl.grantee = 'PUBLIC' AND acl.privilege_type = 'UPDATE'
            )
            ELSE coalesce(pg_catalog.has_table_privilege(
              role_value.role_oid, relation.booking_relation_oid, 'UPDATE'
            ), false)
          END,
          'DELETE', CASE WHEN role_value.role_name = 'PUBLIC'
            THEN EXISTS (
              SELECT 1 FROM direct_table_acl AS acl
              WHERE acl.grantee = 'PUBLIC' AND acl.privilege_type = 'DELETE'
            )
            ELSE coalesce(pg_catalog.has_table_privilege(
              role_value.role_oid, relation.booking_relation_oid, 'DELETE'
            ), false)
          END,
          'TRUNCATE', CASE WHEN role_value.role_name = 'PUBLIC'
            THEN EXISTS (
              SELECT 1 FROM direct_table_acl AS acl
              WHERE acl.grantee = 'PUBLIC' AND acl.privilege_type = 'TRUNCATE'
            )
            ELSE coalesce(pg_catalog.has_table_privilege(
              role_value.role_oid, relation.booking_relation_oid, 'TRUNCATE'
            ), false)
          END,
          'REFERENCES', CASE WHEN role_value.role_name = 'PUBLIC'
            THEN EXISTS (
              SELECT 1 FROM direct_table_acl AS acl
              WHERE acl.grantee = 'PUBLIC' AND acl.privilege_type = 'REFERENCES'
            )
            ELSE coalesce(pg_catalog.has_table_privilege(
              role_value.role_oid, relation.booking_relation_oid, 'REFERENCES'
            ), false)
          END,
          'TRIGGER', CASE WHEN role_value.role_name = 'PUBLIC'
            THEN EXISTS (
              SELECT 1 FROM direct_table_acl AS acl
              WHERE acl.grantee = 'PUBLIC' AND acl.privilege_type = 'TRIGGER'
            )
            ELSE coalesce(pg_catalog.has_table_privilege(
              role_value.role_oid, relation.booking_relation_oid, 'TRIGGER'
            ), false)
          END
        )
      )
      ORDER BY role_value.role_name
    ),
    '[]'::jsonb
  ) AS table_privileges,
  count(*) FILTER (
    WHERE role_value.role_name IN ('anon', 'authenticated')
      AND NOT role_value.role_exists
  ) = 0 AS required_roles_visible
  FROM role_catalog AS role_value
  CROSS JOIN relation_state AS relation
  LEFT JOIN LATERAL (
    SELECT jsonb_object_agg(
      acl.privilege_type,
      jsonb_build_object('granted', true, 'grantable', acl.is_grantable)
      ORDER BY acl.privilege_type
    ) AS direct_privileges
    FROM direct_table_acl AS acl
    WHERE acl.grantee = role_value.role_name
  ) AS direct_value ON true
),
booking_sequences AS (
  SELECT DISTINCT
    sequence_namespace.nspname::text AS sequence_schema,
    sequence_class.relname::text AS sequence_name,
    sequence_class.oid AS sequence_oid,
    attribute.attname::text AS owning_column,
    sequence_class.relowner AS owner_oid,
    sequence_class.relacl
  FROM relation_state AS relation
  JOIN pg_catalog.pg_depend AS dependency
    ON dependency.refobjid = relation.booking_relation_oid
   AND dependency.deptype IN ('a', 'i')
  JOIN pg_catalog.pg_class AS sequence_class
    ON sequence_class.oid = dependency.objid
   AND sequence_class.relkind = 'S'
  JOIN pg_catalog.pg_namespace AS sequence_namespace
    ON sequence_namespace.oid = sequence_class.relnamespace
  LEFT JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = relation.booking_relation_oid
   AND attribute.attnum = dependency.refobjsubid
),
direct_sequence_acl AS (
  SELECT
    sequence_value.sequence_oid,
    CASE acl.grantee
      WHEN 0 THEN 'PUBLIC'::text
      ELSE pg_catalog.pg_get_userbyid(acl.grantee)::text
    END AS grantee,
    acl.privilege_type::text AS privilege_type,
    acl.is_grantable
  FROM booking_sequences AS sequence_value
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    coalesce(
      sequence_value.relacl,
      pg_catalog.acldefault('S', sequence_value.owner_oid)
    )
  ) AS acl
  WHERE acl.grantee = 0
     OR pg_catalog.pg_get_userbyid(acl.grantee)::text
        IN ('anon', 'authenticated', 'service_role')
),
sequence_privilege_report AS (
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'schema', sequence_value.sequence_schema,
        'name', sequence_value.sequence_name,
        'owning_column', sequence_value.owning_column,
        'privileges', (
          SELECT coalesce(
            jsonb_agg(
              jsonb_build_object(
                'role', role_value.role_name,
                'role_exists', role_value.role_exists,
                'direct', coalesce(direct_value.direct_privileges, '{}'::jsonb),
                'effective', jsonb_build_object(
                  'USAGE', CASE WHEN role_value.role_name = 'PUBLIC'
                    THEN EXISTS (
                      SELECT 1 FROM direct_sequence_acl AS acl
                      WHERE acl.sequence_oid = sequence_value.sequence_oid
                        AND acl.grantee = 'PUBLIC'
                        AND acl.privilege_type = 'USAGE'
                    )
                    ELSE coalesce(pg_catalog.has_sequence_privilege(
                      role_value.role_oid,
                      sequence_value.sequence_oid,
                      'USAGE'
                    ), false)
                  END,
                  'SELECT', CASE WHEN role_value.role_name = 'PUBLIC'
                    THEN EXISTS (
                      SELECT 1 FROM direct_sequence_acl AS acl
                      WHERE acl.sequence_oid = sequence_value.sequence_oid
                        AND acl.grantee = 'PUBLIC'
                        AND acl.privilege_type = 'SELECT'
                    )
                    ELSE coalesce(pg_catalog.has_sequence_privilege(
                      role_value.role_oid,
                      sequence_value.sequence_oid,
                      'SELECT'
                    ), false)
                  END,
                  'UPDATE', CASE WHEN role_value.role_name = 'PUBLIC'
                    THEN EXISTS (
                      SELECT 1 FROM direct_sequence_acl AS acl
                      WHERE acl.sequence_oid = sequence_value.sequence_oid
                        AND acl.grantee = 'PUBLIC'
                        AND acl.privilege_type = 'UPDATE'
                    )
                    ELSE coalesce(pg_catalog.has_sequence_privilege(
                      role_value.role_oid,
                      sequence_value.sequence_oid,
                      'UPDATE'
                    ), false)
                  END
                )
              )
              ORDER BY role_value.role_name
            ),
            '[]'::jsonb
          )
          FROM role_catalog AS role_value
          LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(
              acl.privilege_type,
              jsonb_build_object(
                'granted', true,
                'grantable', acl.is_grantable
              )
              ORDER BY acl.privilege_type
            ) AS direct_privileges
            FROM direct_sequence_acl AS acl
            WHERE acl.sequence_oid = sequence_value.sequence_oid
              AND acl.grantee = role_value.role_name
          ) AS direct_value ON true
        )
      )
      ORDER BY sequence_value.sequence_schema, sequence_value.sequence_name
    ),
    '[]'::jsonb
  ) AS sequences
  FROM booking_sequences AS sequence_value
),
relevant_function_oids AS (
  SELECT DISTINCT procedure_value.oid
  FROM pg_catalog.pg_proc AS procedure_value
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = procedure_value.pronamespace
  WHERE namespace.nspname = 'public'
    AND (
      procedure_value.proname ILIKE '%booking%'
      OR procedure_value.proname IN (
        'create_booking',
        'cancel_own_booking',
        'admin_update_booking_status',
        'admin_update_payment_status',
        'generate_booking_code',
        'check_room_availability'
      )
      OR procedure_value.oid IN (
        SELECT trigger_value.tgfoid
        FROM relation_state AS relation
        JOIN pg_catalog.pg_trigger AS trigger_value
          ON trigger_value.tgrelid = relation.booking_relation_oid
        WHERE NOT trigger_value.tgisinternal
      )
    )
),
function_catalog AS (
  SELECT
    procedure_value.oid AS function_oid,
    namespace.nspname::text AS function_schema,
    procedure_value.proname::text AS function_name,
    pg_catalog.pg_get_function_identity_arguments(procedure_value.oid)
      AS identity_arguments,
    pg_catalog.pg_get_function_result(procedure_value.oid) AS return_type,
    pg_catalog.pg_get_userbyid(procedure_value.proowner)::text AS owner,
    procedure_value.prosecdef AS security_definer,
    CASE procedure_value.provolatile
      WHEN 'i' THEN 'IMMUTABLE'
      WHEN 's' THEN 'STABLE'
      WHEN 'v' THEN 'VOLATILE'
      ELSE procedure_value.provolatile::text
    END AS volatility,
    language.lanname::text AS language,
    procedure_value.proconfig AS configuration,
    procedure_value.proowner AS owner_oid,
    procedure_value.proacl
  FROM relevant_function_oids AS relevant
  JOIN pg_catalog.pg_proc AS procedure_value
    ON procedure_value.oid = relevant.oid
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = procedure_value.pronamespace
  JOIN pg_catalog.pg_language AS language
    ON language.oid = procedure_value.prolang
),
direct_function_acl AS (
  SELECT
    function_value.function_oid,
    CASE acl.grantee
      WHEN 0 THEN 'PUBLIC'::text
      ELSE pg_catalog.pg_get_userbyid(acl.grantee)::text
    END AS grantee,
    acl.privilege_type::text AS privilege_type,
    acl.is_grantable
  FROM function_catalog AS function_value
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    coalesce(
      function_value.proacl,
      pg_catalog.acldefault('f', function_value.owner_oid)
    )
  ) AS acl
  WHERE acl.grantee = 0
     OR pg_catalog.pg_get_userbyid(acl.grantee)::text
        IN ('anon', 'authenticated', 'service_role')
),
function_report AS (
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'schema', function_value.function_schema,
        'name', function_value.function_name,
        'arguments', function_value.identity_arguments,
        'return_type', function_value.return_type,
        'owner', function_value.owner,
        'security', CASE WHEN function_value.security_definer
          THEN 'DEFINER' ELSE 'INVOKER' END,
        'volatility', function_value.volatility,
        'language', function_value.language,
        'configuration', to_jsonb(function_value.configuration),
        'execute_privileges', (
          SELECT coalesce(
            jsonb_agg(
              jsonb_build_object(
                'role', role_value.role_name,
                'role_exists', role_value.role_exists,
                'direct', coalesce((
                  SELECT jsonb_object_agg(
                    acl.privilege_type,
                    jsonb_build_object(
                      'granted', true,
                      'grantable', acl.is_grantable
                    )
                  )
                  FROM direct_function_acl AS acl
                  WHERE acl.function_oid = function_value.function_oid
                    AND acl.grantee = role_value.role_name
                ), '{}'::jsonb),
                'effective_execute',
                  CASE WHEN role_value.role_name = 'PUBLIC'
                    THEN EXISTS (
                      SELECT 1
                      FROM direct_function_acl AS acl
                      WHERE acl.function_oid = function_value.function_oid
                        AND acl.grantee = 'PUBLIC'
                        AND acl.privilege_type = 'EXECUTE'
                    )
                    ELSE coalesce(pg_catalog.has_function_privilege(
                      role_value.role_oid,
                      function_value.function_oid,
                      'EXECUTE'
                    ), false)
                  END
              )
              ORDER BY role_value.role_name
            ),
            '[]'::jsonb
          )
          FROM role_catalog AS role_value
        )
      )
      ORDER BY
        function_value.function_schema,
        function_value.function_name,
        function_value.identity_arguments
    ),
    '[]'::jsonb
  ) AS functions,
  count(*) FILTER (
    WHERE function_name IN (
      'create_booking',
      'cancel_own_booking',
      'admin_update_booking_status',
      'admin_update_payment_status',
      'generate_booking_code',
      'check_room_availability'
    )
  ) AS target_name_conflict_count
  FROM function_catalog AS function_value
),
trigger_catalog AS (
  SELECT
    trigger_value.tgname::text AS trigger_name,
    CASE trigger_value.tgenabled
      WHEN 'O' THEN 'ENABLED'
      WHEN 'D' THEN 'DISABLED'
      WHEN 'R' THEN 'REPLICA'
      WHEN 'A' THEN 'ALWAYS'
      ELSE trigger_value.tgenabled::text
    END AS enabled_state,
    pg_catalog.pg_get_triggerdef(trigger_value.oid, true)
      AS trigger_definition,
    function_namespace.nspname::text AS function_schema,
    function_value.proname::text AS function_name,
    pg_catalog.pg_get_function_identity_arguments(function_value.oid)
      AS function_arguments
  FROM relation_state AS relation
  JOIN pg_catalog.pg_trigger AS trigger_value
    ON trigger_value.tgrelid = relation.booking_relation_oid
   AND NOT trigger_value.tgisinternal
  JOIN pg_catalog.pg_proc AS function_value
    ON function_value.oid = trigger_value.tgfoid
  JOIN pg_catalog.pg_namespace AS function_namespace
    ON function_namespace.oid = function_value.pronamespace
),
trigger_report AS (
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'name', trigger_name,
        'enabled', enabled_state,
        'definition', trigger_definition,
        'function_schema', function_schema,
        'function_name', function_name,
        'function_arguments', function_arguments
      )
      ORDER BY trigger_name
    ),
    '[]'::jsonb
  ) AS triggers
  FROM trigger_catalog
),
foundation_relations AS (
  SELECT
    expected.relation_name,
    class.oid AS relation_oid,
    class.relkind::text AS relation_kind
  FROM (
    VALUES
      ('profiles'::text),
      ('rooms'::text),
      ('room_types'::text),
      ('branches'::text)
  ) AS expected(relation_name)
  LEFT JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.nspname = 'public'
  LEFT JOIN pg_catalog.pg_class AS class
    ON class.relnamespace = namespace.oid
   AND class.relname::text = expected.relation_name
   AND class.relkind IN ('r', 'p')
),
profiles_auth_fk_state AS (
  SELECT coalesce(bool_or(
    constraint_value.contype = 'f'
    AND constraint_value.convalidated
    AND constraint_value.confrelid = pg_catalog.to_regclass('auth.users')
    AND (
      SELECT array_agg(attribute.attname::text ORDER BY key_value.ordinality)
      FROM pg_catalog.unnest(constraint_value.conkey)
        WITH ORDINALITY AS key_value(attnum, ordinality)
      JOIN pg_catalog.pg_attribute AS attribute
        ON attribute.attrelid = constraint_value.conrelid
       AND attribute.attnum = key_value.attnum
    ) = ARRAY['id']::text[]
  ), false) AS profiles_auth_fk_valid
  FROM foundation_relations AS profiles
  LEFT JOIN pg_catalog.pg_constraint AS constraint_value
    ON constraint_value.conrelid = profiles.relation_oid
  WHERE profiles.relation_name = 'profiles'
),
is_admin_catalog AS (
  SELECT
    procedure_value.oid AS function_oid,
    pg_catalog.pg_get_function_identity_arguments(procedure_value.oid)
      AS identity_arguments,
    procedure_value.prorettype,
    procedure_value.prosecdef,
    procedure_value.provolatile::text AS volatility_code,
    language.lanname::text AS language,
    pg_catalog.pg_get_userbyid(procedure_value.proowner)::text AS owner,
    procedure_value.proconfig,
    EXISTS (
      SELECT 1
      FROM pg_catalog.aclexplode(
        coalesce(
          procedure_value.proacl,
          pg_catalog.acldefault('f', procedure_value.proowner)
        )
      ) AS acl
      WHERE acl.grantee = 0
        AND acl.privilege_type = 'EXECUTE'
    ) AS public_execute,
    coalesce(pg_catalog.has_function_privilege(
      (
        SELECT role_value.oid
        FROM pg_catalog.pg_roles AS role_value
        WHERE role_value.rolname = 'anon'
      ),
      procedure_value.oid,
      'EXECUTE'
    ), false) AS anon_execute,
    coalesce(pg_catalog.has_function_privilege(
      (
        SELECT role_value.oid
        FROM pg_catalog.pg_roles AS role_value
        WHERE role_value.rolname = 'authenticated'
      ),
      procedure_value.oid,
      'EXECUTE'
    ), false) AS authenticated_execute,
    regexp_replace(
      regexp_replace(
        lower(pg_catalog.pg_get_functiondef(procedure_value.oid)),
        '--[^\n\r]*',
        '',
        'g'
      ),
      '\s+',
      '',
      'g'
    ) AS normalized_definition,
    regexp_replace(
      regexp_replace(
        lower(procedure_value.prosrc),
        '--[^\n\r]*',
        '',
        'g'
      ),
      '\s+',
      '',
      'g'
    ) AS normalized_body,
    pg_catalog.md5(
      regexp_replace(
        regexp_replace(
          lower(pg_catalog.pg_get_functiondef(procedure_value.oid)),
          '--[^\n\r]*',
          '',
          'g'
        ),
        '\s+',
        '',
        'g'
      )
    ) AS normalized_definition_hash
  FROM pg_catalog.pg_proc AS procedure_value
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = procedure_value.pronamespace
  JOIN pg_catalog.pg_language AS language
    ON language.oid = procedure_value.prolang
  WHERE namespace.nspname = 'public'
    AND procedure_value.proname = 'is_admin'
    AND procedure_value.pronargs = 0
),
is_admin_state AS (
  SELECT
    count(*) = 1 AS exactly_one,
    coalesce(bool_and(prorettype = 'boolean'::regtype), false)
      AS returns_boolean,
    coalesce(bool_and(prosecdef), false) AS security_definer,
    coalesce(bool_and(volatility_code = 's'), false) AS stable,
    coalesce(bool_and(language = 'sql'), false) AS language_sql,
    CASE WHEN count(*) = 1 THEN max(owner) ELSE null END AS owner,
    coalesce(bool_and(
      proconfig IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.unnest(proconfig) AS setting(value)
        WHERE regexp_replace(lower(setting.value), '\s+', '', 'g')
          IN ('search_path=', 'search_path=""')
      )
    ), false) AS search_path_safe,
    coalesce(bool_and(NOT public_execute), false) AS no_public_execute,
    coalesce(bool_and(NOT anon_execute), false) AS no_anon_execute,
    coalesce(bool_and(authenticated_execute), false)
      AS authenticated_execute,
    coalesce(bool_and(
      normalized_body LIKE '%exists%'
      AND normalized_body LIKE '%select%'
      AND normalized_body LIKE '%auth.uid()%'
      AND normalized_body LIKE '%public.profiles%'
      AND normalized_body ~ $pattern$(\.id|id)[^=]{0,40}=auth\.uid\(\)$pattern$
      AND normalized_body ~ $pattern$(\.role|role)[^=]{0,40}='admin'$pattern$
      AND normalized_body ~ $pattern$(\.status|status)[^=]{0,40}='active'$pattern$
      AND normalized_body !~ '\mor\M'
      AND normalized_body !~ 'union|intersect|except'
      AND normalized_body !~ (
        'email|raw_user_meta_data|raw_app_meta_data|jwt|'
        || 'localstorage|current_setting|execute|format\('
      )
    ), false) AS approved_body,
    coalesce(bool_and(normalized_body LIKE '%auth.uid()%'), false)
      AS uses_auth_uid,
    coalesce(bool_and(normalized_body LIKE '%public.profiles%'), false)
      AS reads_profiles,
    coalesce(bool_and(normalized_body LIKE $pattern$%role='admin'%$pattern$), false)
      AS requires_admin_role,
    coalesce(bool_and(normalized_body LIKE $pattern$%status='active'%$pattern$), false)
      AS requires_active_status,
    coalesce(bool_and(normalized_body !~ (
      'email|raw_user_meta_data|raw_app_meta_data|jwt|'
      || 'localstorage|current_setting'
    )), false) AS avoids_unapproved_identity_sources,
    CASE WHEN count(*) = 1 THEN max(identity_arguments) ELSE null END
      AS identity_arguments,
    CASE WHEN count(*) = 1 THEN max(normalized_definition_hash) ELSE null END
      AS normalized_definition_hash,
    array_remove(ARRAY[
      CASE WHEN count(*) <> 1 THEN 'FUNCTION_COUNT_OR_SIGNATURE' END,
      CASE WHEN NOT coalesce(bool_and(prorettype = 'boolean'::regtype), false)
        THEN 'RETURN_TYPE_NOT_BOOLEAN' END,
      CASE WHEN NOT coalesce(bool_and(prosecdef), false)
        THEN 'SECURITY_DEFINER_MISSING' END,
      CASE WHEN NOT coalesce(bool_and(volatility_code = 's'), false)
        THEN 'VOLATILITY_NOT_STABLE' END,
      CASE WHEN NOT coalesce(bool_and(language = 'sql'), false)
        THEN 'LANGUAGE_NOT_SQL' END,
      CASE WHEN count(*) <> 1 OR max(owner) IS DISTINCT FROM 'postgres'
        THEN 'OWNER_NOT_POSTGRES' END,
      CASE WHEN NOT coalesce(bool_and(
        proconfig IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM pg_catalog.unnest(proconfig) AS setting(value)
          WHERE regexp_replace(lower(setting.value), '\s+', '', 'g')
            IN ('search_path=', 'search_path=""')
        )
      ), false) THEN 'SEARCH_PATH_NOT_FIXED_EMPTY' END,
      CASE WHEN coalesce(bool_or(public_execute), false)
        THEN 'PUBLIC_EXECUTE_PRESENT' END,
      CASE WHEN coalesce(bool_or(anon_execute), false)
        THEN 'ANON_EXECUTE_PRESENT' END,
      CASE WHEN NOT coalesce(bool_and(authenticated_execute), false)
        THEN 'AUTHENTICATED_EXECUTE_MISSING' END,
      CASE WHEN NOT coalesce(bool_and(normalized_body LIKE '%exists%'), false)
        THEN 'EXISTS_PREDICATE_MISSING' END,
      CASE WHEN NOT coalesce(bool_and(normalized_body LIKE '%auth.uid()%'), false)
        THEN 'AUTH_UID_MISSING' END,
      CASE WHEN NOT coalesce(bool_and(normalized_body LIKE '%public.profiles%'), false)
        THEN 'SCHEMA_QUALIFIED_PROFILES_REFERENCE_MISSING' END,
      CASE WHEN NOT coalesce(bool_and(
        normalized_body ~ $pattern$(\.id|id)[^=]{0,40}=auth\.uid\(\)$pattern$
      ), false) THEN 'CALLER_PROFILE_ID_PREDICATE_MISSING' END,
      CASE WHEN NOT coalesce(bool_and(
        normalized_body ~ $pattern$(\.role|role)[^=]{0,40}='admin'$pattern$
      ), false) THEN 'ADMIN_ROLE_PREDICATE_MISSING' END,
      CASE WHEN NOT coalesce(bool_and(
        normalized_body ~ $pattern$(\.status|status)[^=]{0,40}='active'$pattern$
      ), false) THEN 'ACTIVE_STATUS_PREDICATE_MISSING' END,
      CASE WHEN coalesce(bool_or(normalized_body ~ '\mor\M'), false)
        THEN 'OR_BYPASS_PRESENT' END,
      CASE WHEN coalesce(bool_or(
        normalized_body ~ 'union|intersect|except'
      ), false) THEN 'SET_OPERATION_PRESENT' END,
      CASE WHEN coalesce(bool_or(normalized_body ~ (
        'email|raw_user_meta_data|raw_app_meta_data|jwt|'
        || 'localstorage|current_setting|execute|format\('
      )), false) THEN 'UNAPPROVED_IDENTITY_OR_DYNAMIC_SQL_SOURCE' END
    ], null)::text[] AS failed_approval_rules
  FROM is_admin_catalog
),
foundation_state AS (
  SELECT
    count(*) FILTER (
      WHERE relation_oid IS NOT NULL AND relation_kind IN ('r', 'p')
    ) = 4 AS required_tables_exist,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'name', relation_name,
          'exists', relation_oid IS NOT NULL,
          'relation_kind', relation_kind
        )
        ORDER BY relation_name
      ),
      '[]'::jsonb
    ) AS tables
  FROM foundation_relations
),
capacity_schema_state AS (
  SELECT
    rooms.relation_oid IS NOT NULL AS rooms_exists,
    room_types.relation_oid IS NOT NULL AS room_types_exists,
    EXISTS (
      SELECT 1
      FROM foundation_relations AS profiles
      JOIN pg_catalog.pg_attribute AS attribute
        ON attribute.attrelid = profiles.relation_oid
      WHERE profiles.relation_name = 'profiles'
        AND attribute.attname = 'id'
        AND attribute.atttypid = 'uuid'::regtype
        AND attribute.attnum > 0
        AND NOT attribute.attisdropped
    ) AS profiles_id_valid,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS attribute
      WHERE attribute.attrelid = rooms.relation_oid
        AND attribute.attname = 'id'
        AND attribute.atttypid = 'bigint'::regtype
        AND attribute.attnum > 0
        AND NOT attribute.attisdropped
    ) AS rooms_id_valid,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS attribute
      WHERE attribute.attrelid = rooms.relation_oid
        AND attribute.attname = 'capacity'
        AND attribute.atttypid IN (
          'smallint'::regtype,
          'integer'::regtype,
          'bigint'::regtype
        )
        AND attribute.attnum > 0
        AND NOT attribute.attisdropped
    ) AS rooms_capacity_valid,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS attribute
      WHERE attribute.attrelid = rooms.relation_oid
        AND attribute.attname = 'room_type_id'
        AND attribute.atttypid = 'bigint'::regtype
        AND attribute.attnum > 0
        AND NOT attribute.attisdropped
    ) AS rooms_room_type_id_valid,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS attribute
      WHERE attribute.attrelid = room_types.relation_oid
        AND attribute.attname = 'id'
        AND attribute.atttypid = 'bigint'::regtype
        AND attribute.attnum > 0
        AND NOT attribute.attisdropped
    ) AS room_types_id_valid,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS attribute
      WHERE attribute.attrelid = room_types.relation_oid
        AND attribute.attname = 'capacity'
        AND attribute.atttypid IN ('smallint'::regtype, 'integer'::regtype, 'bigint'::regtype)
        AND attribute.attnum > 0
        AND NOT attribute.attisdropped
    ) AS room_types_capacity_valid,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_value
      WHERE constraint_value.conrelid = rooms.relation_oid
        AND constraint_value.confrelid = room_types.relation_oid
        AND constraint_value.contype = 'f'
        AND constraint_value.convalidated
        AND (
          SELECT array_agg(attribute.attname::text ORDER BY key_value.ordinality)
          FROM pg_catalog.unnest(constraint_value.conkey)
            WITH ORDINALITY AS key_value(attnum, ordinality)
          JOIN pg_catalog.pg_attribute AS attribute
            ON attribute.attrelid = constraint_value.conrelid
           AND attribute.attnum = key_value.attnum
        ) = ARRAY['room_type_id']::text[]
    ) AS rooms_room_types_fk_valid
  FROM foundation_relations AS rooms
  CROSS JOIN foundation_relations AS room_types
  WHERE rooms.relation_name = 'rooms'
    AND room_types.relation_name = 'room_types'
),
capacity_source_state AS (
  SELECT
    (
      schema_value.rooms_exists
      AND schema_value.rooms_id_valid
      AND schema_value.rooms_capacity_valid
    ) AS rooms_capacity_source_valid,
    (
      schema_value.rooms_exists
      AND schema_value.room_types_exists
      AND schema_value.rooms_id_valid
      AND schema_value.rooms_room_type_id_valid
      AND schema_value.room_types_id_valid
      AND schema_value.room_types_capacity_valid
      AND schema_value.rooms_room_types_fk_valid
    ) AS room_types_capacity_source_valid,
    (
      (schema_value.rooms_exists
       AND schema_value.rooms_id_valid
       AND schema_value.rooms_capacity_valid)::integer
      +
      (schema_value.rooms_exists
       AND schema_value.room_types_exists
       AND schema_value.rooms_id_valid
       AND schema_value.rooms_room_type_id_valid
       AND schema_value.room_types_id_valid
       AND schema_value.room_types_capacity_valid
       AND schema_value.rooms_room_types_fk_valid)::integer
    ) AS valid_source_count,
    CASE
      WHEN schema_value.rooms_exists
       AND schema_value.rooms_id_valid
       AND schema_value.rooms_capacity_valid
       AND NOT (
         schema_value.room_types_exists
         AND schema_value.rooms_room_type_id_valid
         AND schema_value.room_types_id_valid
         AND schema_value.room_types_capacity_valid
         AND schema_value.rooms_room_types_fk_valid
       )
        THEN 'public.rooms.capacity'
      WHEN NOT schema_value.rooms_capacity_valid
       AND schema_value.rooms_exists
       AND schema_value.room_types_exists
       AND schema_value.rooms_id_valid
       AND schema_value.rooms_room_type_id_valid
       AND schema_value.room_types_id_valid
       AND schema_value.room_types_capacity_valid
       AND schema_value.rooms_room_types_fk_valid
        THEN 'public.room_types.capacity'
      ELSE null
    END AS selected_authoritative_source,
    CASE
      WHEN schema_value.rooms_capacity_valid
       AND NOT (
         schema_value.room_types_capacity_valid
         AND schema_value.rooms_room_types_fk_valid
       )
        THEN 'bookings.room_id -> rooms.id'
      WHEN NOT schema_value.rooms_capacity_valid
       AND schema_value.room_types_capacity_valid
       AND schema_value.rooms_room_types_fk_valid
        THEN 'bookings.room_id -> rooms.id; rooms.room_type_id -> room_types.id'
      ELSE null
    END AS selected_relationship,
    CASE
      WHEN schema_value.rooms_capacity_valid
       AND NOT (
         schema_value.room_types_capacity_valid
         AND schema_value.rooms_room_types_fk_valid
       )
        THEN 'Exactly one valid capacity source exists directly on rooms.'
      WHEN NOT schema_value.rooms_capacity_valid
       AND schema_value.room_types_capacity_valid
       AND schema_value.rooms_room_types_fk_valid
        THEN 'Exactly one valid capacity source exists on room_types through a validated foreign key.'
      WHEN schema_value.rooms_capacity_valid
       AND schema_value.room_types_capacity_valid
       AND schema_value.rooms_room_types_fk_valid
        THEN 'Both rooms.capacity and room_types.capacity are valid candidates; human selection is required.'
      ELSE 'No compatible authoritative capacity source and relationship could be confirmed.'
    END AS selection_reason,
    jsonb_build_array(
      jsonb_build_object(
        'source', 'public.rooms.capacity',
        'valid',
          schema_value.rooms_exists
          AND schema_value.rooms_id_valid
          AND schema_value.rooms_capacity_valid,
        'relationship', 'bookings.room_id -> rooms.id'
      ),
      jsonb_build_object(
        'source', 'public.room_types.capacity',
        'valid',
          schema_value.rooms_exists
          AND schema_value.room_types_exists
          AND schema_value.rooms_id_valid
          AND schema_value.rooms_room_type_id_valid
          AND schema_value.room_types_id_valid
          AND schema_value.room_types_capacity_valid
          AND schema_value.rooms_room_types_fk_valid,
        'relationship',
          'bookings.room_id -> rooms.id; rooms.room_type_id -> room_types.id'
      )
    ) AS candidate_sources
  FROM capacity_schema_state AS schema_value
),
inspection_column_state AS (
  SELECT
    count(*) FILTER (
      WHERE expected.column_name IN (
        'id', 'booking_code', 'user_id', 'room_id',
        'check_in_date', 'check_out_date',
        'number_of_nights', 'number_of_guests',
        'price_per_night', 'subtotal', 'tax_rate', 'tax_amount',
        'discount_amount', 'total_amount',
        'booking_status', 'payment_status', 'cancelled_at'
      )
        AND actual.column_name IS NOT NULL
        AND actual.type_oid = expected.expected_type::regtype
    ) = 17 AS booking_data_columns_compatible,
    count(*) FILTER (
      WHERE expected.column_name IN (
        'id', 'room_id', 'check_in_date', 'check_out_date',
        'booking_status'
      )
        AND actual.column_name IS NOT NULL
        AND actual.type_oid = expected.expected_type::regtype
    ) = 5 AS overlap_columns_compatible,
    count(*) FILTER (
      WHERE expected.column_name IN ('user_id', 'room_id')
        AND actual.column_name IS NOT NULL
        AND actual.type_oid = expected.expected_type::regtype
    ) = 2 AS relationship_columns_compatible,
    count(*) FILTER (
      WHERE expected.column_name IN ('room_id', 'number_of_guests')
        AND actual.column_name IS NOT NULL
        AND actual.type_oid = expected.expected_type::regtype
    ) = 2 AS capacity_columns_compatible
  FROM expected_columns AS expected
  LEFT JOIN column_catalog AS actual
    ON actual.column_name = expected.column_name
),
schema_guard AS (
  SELECT
    relation.bookings_table_exists
    AND inspection.booking_data_columns_compatible
    AS booking_data_query_safe,
    relation.bookings_table_exists
    AND inspection.overlap_columns_compatible
    AS overlap_query_safe,
    relation.bookings_table_exists
    AND inspection.relationship_columns_compatible
    AND capacity.profiles_id_valid
    AND capacity.rooms_id_valid
    AS relationship_query_safe,
    relation.bookings_table_exists
    AND inspection.capacity_columns_compatible
    AND source.valid_source_count = 1
    AS capacity_query_safe
  FROM relation_state AS relation
  CROSS JOIN inspection_column_state AS inspection
  CROSS JOIN capacity_schema_state AS capacity
  CROSS JOIN capacity_source_state AS source
),
/*
 * The guarded dynamic statement returns aggregate counts only. CASE prevents
 * evaluation when the live schema cannot safely support the expressions.
 */
booking_data_xml AS (
  SELECT CASE WHEN guard.booking_data_query_safe THEN
    pg_catalog.query_to_xml(
      $query$
        SELECT jsonb_build_object(
          'booking_count', count(*),
          'null_user_id_count',
            count(*) FILTER (WHERE booking.user_id IS NULL),
          'invalid_date_count',
            count(*) FILTER (
              WHERE booking.check_in_date IS NULL
                 OR booking.check_out_date IS NULL
                 OR booking.check_out_date <= booking.check_in_date
            ),
          'inconsistent_nights_count',
            count(*) FILTER (
              WHERE booking.number_of_nights IS NULL
                 OR booking.number_of_nights
                <> booking.check_out_date - booking.check_in_date
            ),
          'non_positive_guest_count',
            count(*) FILTER (
              WHERE booking.number_of_guests IS NULL
                 OR booking.number_of_guests <= 0
            ),
          'negative_monetary_value_count',
            count(*) FILTER (
              WHERE booking.price_per_night IS NULL
                 OR booking.subtotal IS NULL
                 OR booking.tax_rate IS NULL
                 OR booking.tax_amount IS NULL
                 OR booking.discount_amount IS NULL
                 OR booking.total_amount IS NULL
                 OR booking.price_per_night < 0
                 OR booking.subtotal < 0
                 OR booking.tax_rate < 0
                 OR booking.tax_amount < 0
                 OR booking.discount_amount < 0
                 OR booking.total_amount < 0
            ),
          'subtotal_inconsistency_count',
            count(*) FILTER (
              WHERE booking.subtotal
                <> booking.price_per_night * booking.number_of_nights
            ),
          'tax_inconsistency_count',
            count(*) FILTER (
              WHERE booking.tax_amount
                <> round(
                  booking.subtotal::numeric * booking.tax_rate / 100
                )::bigint
            ),
          'total_inconsistency_count',
            count(*) FILTER (
              WHERE booking.total_amount
                <> booking.subtotal
                   + booking.tax_amount
                   - booking.discount_amount
            ),
          'discount_exceeds_charges_count',
            count(*) FILTER (
              WHERE booking.discount_amount
                > booking.subtotal + booking.tax_amount
            ),
          'cancelled_without_timestamp_count',
            count(*) FILTER (
              WHERE booking.booking_status = 'cancelled'
                AND booking.cancelled_at IS NULL
            ),
          'non_cancelled_with_timestamp_count',
            count(*) FILTER (
              WHERE booking.booking_status <> 'cancelled'
                AND booking.cancelled_at IS NOT NULL
            ),
          'invalid_booking_status_count',
            count(*) FILTER (
              WHERE booking.booking_status IS NULL
                 OR booking.booking_status NOT IN (
                'pending', 'confirmed', 'checked_in',
                'completed', 'cancelled'
              )
            ),
          'invalid_payment_status_count',
            count(*) FILTER (
              WHERE booking.payment_status IS NULL
                 OR booking.payment_status NOT IN (
                'unpaid', 'pending', 'paid', 'failed', 'refunded'
              )
            ),
          'duplicate_booking_code_group_count', (
            SELECT count(*)
            FROM (
              SELECT duplicate.booking_code
              FROM public.bookings AS duplicate
              GROUP BY duplicate.booking_code
              HAVING count(*) > 1
            ) AS duplicate_codes
          )
        ) AS payload
        FROM public.bookings AS booking
      $query$,
      false,
      true,
      ''
    )
  ELSE null::xml END AS result_xml
  FROM schema_guard AS guard
),
booking_data_state AS (
  SELECT
    parsed.payload::jsonb AS metrics,
    parsed.payload IS NOT NULL AS inspected
  FROM booking_data_xml AS data_xml
  LEFT JOIN LATERAL XMLTABLE(
    '//*[local-name()="row"]'
    PASSING data_xml.result_xml
    COLUMNS payload text PATH '*[local-name()="payload"]'
  ) AS parsed ON true
),
overlap_data_xml AS (
  SELECT CASE WHEN guard.overlap_query_safe THEN
    pg_catalog.query_to_xml(
      $query$
        SELECT jsonb_build_object(
          'overlapping_pair_count', count(*),
          'overlap_affected_room_count',
            count(DISTINCT overlap.room_id)
        ) AS payload
        FROM (
          SELECT left_booking.room_id
          FROM public.bookings AS left_booking
          JOIN public.bookings AS right_booking
            ON left_booking.id < right_booking.id
           AND left_booking.room_id = right_booking.room_id
           AND left_booking.booking_status IN (
             'pending', 'confirmed', 'checked_in'
           )
           AND right_booking.booking_status IN (
             'pending', 'confirmed', 'checked_in'
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
               )
               && daterange(
                    right_booking.check_in_date,
                    right_booking.check_out_date,
                    '[)'
                  )
        ) AS overlap
      $query$,
      false,
      true,
      ''
    )
  ELSE null::xml END AS result_xml
  FROM schema_guard AS guard
),
overlap_data_state AS (
  SELECT
    parsed.payload::jsonb AS metrics,
    parsed.payload IS NOT NULL AS inspected
  FROM overlap_data_xml AS data_xml
  LEFT JOIN LATERAL XMLTABLE(
    '//*[local-name()="row"]'
    PASSING data_xml.result_xml
    COLUMNS payload text PATH '*[local-name()="payload"]'
  ) AS parsed ON true
),
relationship_data_xml AS (
  SELECT CASE WHEN guard.relationship_query_safe THEN
    pg_catalog.query_to_xml(
      $query$
        SELECT jsonb_build_object(
          'orphan_user_id_count',
            count(*) FILTER (
              WHERE booking.user_id IS NOT NULL
                AND profile.id IS NULL
            ),
          'orphan_room_id_count',
            count(*) FILTER (WHERE room.id IS NULL)
        ) AS payload
        FROM public.bookings AS booking
        LEFT JOIN public.profiles AS profile
          ON profile.id = booking.user_id
        LEFT JOIN public.rooms AS room
          ON room.id = booking.room_id
      $query$,
      false,
      true,
      ''
    )
  ELSE null::xml END AS result_xml
  FROM schema_guard AS guard
),
relationship_data_state AS (
  SELECT
    parsed.payload::jsonb AS metrics,
    parsed.payload IS NOT NULL AS inspected
  FROM relationship_data_xml AS data_xml
  LEFT JOIN LATERAL XMLTABLE(
    '//*[local-name()="row"]'
    PASSING data_xml.result_xml
    COLUMNS payload text PATH '*[local-name()="payload"]'
  ) AS parsed ON true
),
capacity_data_xml AS (
  SELECT CASE
    WHEN guard.capacity_query_safe
     AND source.selected_authoritative_source = 'public.rooms.capacity'
    THEN pg_catalog.query_to_xml(
      $query$
        SELECT jsonb_build_object(
          'over_capacity_booking_count',
            count(*) FILTER (
              WHERE booking.number_of_guests > room.capacity
            )
        ) AS payload
        FROM public.bookings AS booking
        JOIN public.rooms AS room
          ON room.id = booking.room_id
      $query$,
      false,
      true,
      ''
    )
    WHEN guard.capacity_query_safe
     AND source.selected_authoritative_source = 'public.room_types.capacity'
    THEN pg_catalog.query_to_xml(
      $query$
        SELECT jsonb_build_object(
          'over_capacity_booking_count',
            count(*) FILTER (
              WHERE booking.number_of_guests > room_type.capacity
            )
        ) AS payload
        FROM public.bookings AS booking
        JOIN public.rooms AS room
          ON room.id = booking.room_id
        JOIN public.room_types AS room_type
          ON room_type.id = room.room_type_id
      $query$,
      false,
      true,
      ''
    )
    ELSE null::xml
  END AS result_xml
  FROM schema_guard AS guard
  CROSS JOIN capacity_source_state AS source
),
capacity_data_state AS (
  SELECT
    parsed.payload::jsonb AS metrics,
    parsed.payload IS NOT NULL AS inspected
  FROM capacity_data_xml AS data_xml
  LEFT JOIN LATERAL XMLTABLE(
    '//*[local-name()="row"]'
    PASSING data_xml.result_xml
    COLUMNS payload text PATH '*[local-name()="payload"]'
  ) AS parsed ON true
),
extension_state AS (
  SELECT
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_extension AS extension_value
      WHERE extension_value.extname = 'btree_gist'
    ) AS btree_gist_installed,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_available_extensions AS available
      WHERE available.name = 'btree_gist'
    ) AS btree_gist_available
),
room_id_type AS (
  SELECT type_oid
  FROM column_catalog
  WHERE column_name = 'room_id'
),
gist_capability AS (
  SELECT
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_opclass AS operator_class
      JOIN pg_catalog.pg_am AS access_method
        ON access_method.oid = operator_class.opcmethod
      JOIN pg_catalog.pg_amop AS operator_member
        ON operator_member.amopfamily = operator_class.opcfamily
       AND operator_member.amoplefttype = operator_class.opcintype
       AND operator_member.amoprighttype = operator_class.opcintype
       AND operator_member.amopstrategy = 3
      JOIN pg_catalog.pg_operator AS operator_value
        ON operator_value.oid = operator_member.amopopr
       AND operator_value.oprname = '='
      WHERE access_method.amname = 'gist'
        AND operator_class.opcintype = room_type.type_oid
    ) AS room_id_gist_equality_opclass_installed,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_opclass AS operator_class
      JOIN pg_catalog.pg_am AS access_method
        ON access_method.oid = operator_class.opcmethod
      WHERE access_method.amname = 'gist'
        AND operator_class.opcintype = 'daterange'::regtype
    ) AS daterange_gist_opclass_exists,
    pg_catalog.to_regoperator('&&(anyrange,anyrange)') IS NOT NULL
      AS range_overlap_operator_exists,
    EXISTS (
      SELECT 1
      FROM column_catalog
      WHERE column_name IN ('check_in_date', 'check_out_date')
        AND type_oid = 'date'::regtype
      GROUP BY type_oid
      HAVING count(*) = 2
    ) AS date_columns_compatible,
    coalesce(
      room_type.type_oid IN (
        'smallint'::regtype,
        'integer'::regtype,
        'bigint'::regtype
      ),
      false
    ) AS room_id_type_supported_by_btree_gist
  FROM room_id_type AS room_type
  UNION ALL
  SELECT
    false,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_opclass AS operator_class
      JOIN pg_catalog.pg_am AS access_method
        ON access_method.oid = operator_class.opcmethod
      WHERE access_method.amname = 'gist'
        AND operator_class.opcintype = 'daterange'::regtype
    ),
    pg_catalog.to_regoperator('&&(anyrange,anyrange)') IS NOT NULL,
    false,
    false
  WHERE NOT EXISTS (SELECT 1 FROM room_id_type)
),
capability_state AS (
  SELECT
    extension_value.btree_gist_installed,
    extension_value.btree_gist_available,
    gist.room_id_gist_equality_opclass_installed,
    gist.daterange_gist_opclass_exists,
    gist.range_overlap_operator_exists,
    gist.date_columns_compatible,
    gist.room_id_type_supported_by_btree_gist,
    (
      extension_value.btree_gist_available
      AND gist.range_overlap_operator_exists
      AND gist.date_columns_compatible
      AND gist.room_id_type_supported_by_btree_gist
    ) AS exclusion_constraint_possible_after_install,
    (
      NOT extension_value.btree_gist_installed
      AND extension_value.btree_gist_available
    ) AS requires_btree_gist_install,
    (
      pg_catalog.to_regprocedure(
        'pg_catalog.pg_advisory_xact_lock(bigint)'
      ) IS NOT NULL
      AND gist.room_id_type_supported_by_btree_gist
    ) AS safe_alternative_available,
    (
      (
        extension_value.btree_gist_available
        AND gist.range_overlap_operator_exists
        AND gist.date_columns_compatible
        AND gist.room_id_type_supported_by_btree_gist
      )
    ) AS future_exclusion_constraint_supported,
    (
      (
        extension_value.btree_gist_available
        AND gist.range_overlap_operator_exists
        AND gist.date_columns_compatible
        AND gist.room_id_type_supported_by_btree_gist
      )
      OR (
        pg_catalog.to_regprocedure(
          'pg_catalog.pg_advisory_xact_lock(bigint)'
        ) IS NOT NULL
        AND gist.room_id_type_supported_by_btree_gist
      )
    ) AS safe_concurrency_path_available
  FROM extension_state AS extension_value
  CROSS JOIN gist_capability AS gist
),
evaluation AS (
  SELECT
    relation.*,
    columns.all_expected_columns_exist,
    columns.expected_column_types_match,
    columns.expected_column_checks,
    column_report.columns,
    constraints.*,
    not_null.user_id_not_null,
    foreign_keys.foreign_keys,
    indexes.*,
    policies.policies,
    table_privileges.table_privileges,
    table_privileges.required_roles_visible,
    sequence_privileges.sequences,
    functions.functions,
    functions.target_name_conflict_count,
    triggers.triggers,
    foundation.required_tables_exist AS foundation_tables_exist,
    foundation.tables AS foundation_tables,
    profiles_fk.profiles_auth_fk_valid,
    admin.exactly_one AS is_admin_exists_once,
    admin.returns_boolean AS is_admin_returns_boolean,
    admin.security_definer AS is_admin_security_definer,
    admin.stable AS is_admin_stable,
    admin.language_sql AS is_admin_language_sql,
    admin.owner AS is_admin_owner,
    admin.search_path_safe AS is_admin_search_path_safe,
    admin.no_public_execute AS is_admin_no_public_execute,
    admin.no_anon_execute AS is_admin_no_anon_execute,
    admin.authenticated_execute AS is_admin_authenticated_execute,
    admin.approved_body AS is_admin_approved_body,
    admin.uses_auth_uid AS is_admin_uses_auth_uid,
    admin.reads_profiles AS is_admin_reads_profiles,
    admin.requires_admin_role AS is_admin_requires_admin_role,
    admin.requires_active_status AS is_admin_requires_active_status,
    admin.avoids_unapproved_identity_sources
      AS is_admin_avoids_unapproved_identity_sources,
    admin.identity_arguments AS is_admin_identity_arguments,
    admin.normalized_definition_hash AS is_admin_normalized_definition_hash,
    admin.failed_approval_rules AS is_admin_failed_approval_rules,
    capacity_schema.*,
    capacity_source.*,
    booking_data.inspected AS booking_data_inspected,
    relationship_data.inspected AS relationship_data_inspected,
    (
      coalesce(booking_data.metrics, '{}'::jsonb)
      || coalesce(relationship_data.metrics, '{}'::jsonb)
    ) AS booking_metrics,
    overlap_data.inspected AS overlap_data_inspected,
    coalesce(overlap_data.metrics, '{}'::jsonb) AS overlap_metrics,
    capacity_data.inspected AS capacity_data_inspected,
    coalesce(capacity_data.metrics, '{}'::jsonb) AS capacity_metrics,
    guard.booking_data_query_safe,
    guard.overlap_query_safe,
    guard.relationship_query_safe,
    guard.capacity_query_safe,
    capability.*
  FROM relation_state AS relation
  CROSS JOIN column_state AS columns
  CROSS JOIN column_report
  CROSS JOIN constraint_report AS constraints
  CROSS JOIN not_null_state AS not_null
  CROSS JOIN foreign_key_report AS foreign_keys
  CROSS JOIN index_state AS indexes
  CROSS JOIN policy_report AS policies
  CROSS JOIN table_privilege_report AS table_privileges
  CROSS JOIN sequence_privilege_report AS sequence_privileges
  CROSS JOIN function_report AS functions
  CROSS JOIN trigger_report AS triggers
  CROSS JOIN foundation_state AS foundation
  CROSS JOIN profiles_auth_fk_state AS profiles_fk
  CROSS JOIN is_admin_state AS admin
  CROSS JOIN capacity_schema_state AS capacity_schema
  CROSS JOIN capacity_source_state AS capacity_source
  CROSS JOIN booking_data_state AS booking_data
  CROSS JOIN relationship_data_state AS relationship_data
  CROSS JOIN overlap_data_state AS overlap_data
  CROSS JOIN capacity_data_state AS capacity_data
  CROSS JOIN capability_state AS capability
  CROSS JOIN schema_guard AS guard
),
decision_inputs AS (
  SELECT
    evaluation.*,
    NOT (
      bookings_table_exists
      AND bookings_relation_name_unique
      AND all_expected_columns_exist
      AND expected_column_types_match
      AND foundation_tables_exist
      AND profiles_auth_fk_valid
      AND is_admin_exists_once
      AND is_admin_returns_boolean
      AND is_admin_security_definer
      AND is_admin_stable
      AND is_admin_language_sql
      AND is_admin_owner = 'postgres'
      AND is_admin_search_path_safe
      AND is_admin_no_public_execute
      AND is_admin_no_anon_execute
      AND is_admin_authenticated_execute
      AND is_admin_approved_body
      AND is_admin_uses_auth_uid
      AND is_admin_reads_profiles
      AND is_admin_requires_admin_role
      AND is_admin_requires_active_status
      AND is_admin_avoids_unapproved_identity_sources
      AND required_roles_visible
      AND profiles_id_valid
      AND rooms_id_valid
      AND valid_source_count = 1
      AND booking_data_inspected
      AND relationship_data_inspected
      AND overlap_data_inspected
      AND capacity_data_inspected
      AND safe_concurrency_path_available
    ) AS structural_failure,
    (
      coalesce((booking_metrics ->> 'null_user_id_count')::bigint, 0) > 0
      OR coalesce((booking_metrics ->> 'orphan_user_id_count')::bigint, 0) > 0
      OR coalesce((booking_metrics ->> 'orphan_room_id_count')::bigint, 0) > 0
      OR coalesce((booking_metrics ->> 'invalid_date_count')::bigint, 0) > 0
      OR coalesce((booking_metrics ->> 'inconsistent_nights_count')::bigint, 0) > 0
      OR coalesce((booking_metrics ->> 'non_positive_guest_count')::bigint, 0) > 0
      OR coalesce((booking_metrics ->> 'negative_monetary_value_count')::bigint, 0) > 0
      OR coalesce((booking_metrics ->> 'subtotal_inconsistency_count')::bigint, 0) > 0
      OR coalesce((booking_metrics ->> 'tax_inconsistency_count')::bigint, 0) > 0
      OR coalesce((booking_metrics ->> 'total_inconsistency_count')::bigint, 0) > 0
      OR coalesce((booking_metrics ->> 'discount_exceeds_charges_count')::bigint, 0) > 0
      OR coalesce((booking_metrics ->> 'cancelled_without_timestamp_count')::bigint, 0) > 0
      OR coalesce((booking_metrics ->> 'non_cancelled_with_timestamp_count')::bigint, 0) > 0
      OR coalesce((booking_metrics ->> 'invalid_booking_status_count')::bigint, 0) > 0
      OR coalesce((booking_metrics ->> 'invalid_payment_status_count')::bigint, 0) > 0
      OR coalesce((booking_metrics ->> 'duplicate_booking_code_group_count')::bigint, 0) > 0
      OR coalesce((overlap_metrics ->> 'overlapping_pair_count')::bigint, 0) > 0
      OR coalesce((capacity_metrics ->> 'over_capacity_booking_count')::bigint, 0) > 0
    ) AS reconciliation_required
  FROM evaluation
),
result AS (
  SELECT
    decision.*,
    CASE
      WHEN reconciliation_required AND NOT structural_failure
        THEN 'RECONCILIATION_REQUIRED'
      WHEN structural_failure THEN 'PREFLIGHT_FAILED'
      ELSE 'PREFLIGHT_PASSED'
    END AS status,
    array_remove(ARRAY[
      CASE WHEN NOT bookings_table_exists
        THEN 'BOOKINGS_TABLE_MISSING_OR_WRONG_RELATION_KIND' END,
      CASE WHEN NOT bookings_relation_name_unique
        THEN 'BOOKINGS_RELATION_NAME_AMBIGUOUS' END,
      CASE WHEN bookings_table_exists AND NOT all_expected_columns_exist
        THEN 'BOOKINGS_REQUIRED_COLUMNS_MISSING' END,
      CASE WHEN bookings_table_exists AND NOT expected_column_types_match
        THEN 'BOOKINGS_COLUMN_TYPES_UNEXPECTED' END,
      CASE WHEN NOT foundation_tables_exist
        THEN 'REQUIRED_FOUNDATION_TABLE_MISSING' END,
      CASE WHEN NOT profiles_auth_fk_valid
        THEN 'PROFILES_AUTH_USERS_FOREIGN_KEY_INVALID' END,
      CASE WHEN NOT (
        is_admin_exists_once
        AND is_admin_returns_boolean
        AND is_admin_security_definer
        AND is_admin_stable
        AND is_admin_language_sql
        AND is_admin_owner = 'postgres'
        AND is_admin_search_path_safe
        AND is_admin_no_public_execute
        AND is_admin_no_anon_execute
        AND is_admin_authenticated_execute
        AND is_admin_approved_body
        AND is_admin_uses_auth_uid
        AND is_admin_reads_profiles
        AND is_admin_requires_admin_role
        AND is_admin_requires_active_status
        AND is_admin_avoids_unapproved_identity_sources
      ) THEN 'IS_ADMIN_FOUNDATION_INVALID' END,
      CASE WHEN NOT required_roles_visible
        THEN 'REQUIRED_FRONTEND_ROLE_NOT_VISIBLE' END,
      CASE WHEN valid_source_count = 0
        THEN 'AUTHORITATIVE_ROOM_CAPACITY_CANNOT_BE_CONFIRMED' END,
      CASE WHEN valid_source_count > 1
        THEN 'AUTHORITATIVE_ROOM_CAPACITY_SOURCE_AMBIGUOUS' END,
      CASE WHEN NOT booking_data_inspected
        THEN 'BOOKING_DATA_COULD_NOT_BE_SAFELY_INSPECTED' END,
      CASE WHEN NOT relationship_data_inspected
        THEN 'BOOKING_RELATIONSHIPS_COULD_NOT_BE_SAFELY_INSPECTED' END,
      CASE WHEN NOT overlap_data_inspected
        THEN 'BOOKING_OVERLAPS_COULD_NOT_BE_SAFELY_INSPECTED' END,
      CASE WHEN NOT capacity_data_inspected
        THEN 'BOOKING_CAPACITY_COULD_NOT_BE_SAFELY_INSPECTED' END,
      CASE WHEN NOT safe_concurrency_path_available
        THEN 'SAFE_CONCURRENCY_CONTROL_UNAVAILABLE' END,
      CASE WHEN coalesce((booking_metrics ->> 'null_user_id_count')::bigint, 0) > 0
        THEN 'NULL_BOOKING_OWNERS_REQUIRE_RECONCILIATION' END,
      CASE WHEN coalesce((booking_metrics ->> 'orphan_user_id_count')::bigint, 0) > 0
        THEN 'ORPHAN_BOOKING_OWNERS_REQUIRE_RECONCILIATION' END,
      CASE WHEN coalesce((booking_metrics ->> 'orphan_room_id_count')::bigint, 0) > 0
        THEN 'ORPHAN_BOOKING_ROOMS_REQUIRE_RECONCILIATION' END,
      CASE WHEN coalesce((booking_metrics ->> 'invalid_date_count')::bigint, 0) > 0
        THEN 'INVALID_BOOKING_DATES_REQUIRE_RECONCILIATION' END,
      CASE WHEN coalesce((booking_metrics ->> 'inconsistent_nights_count')::bigint, 0) > 0
        THEN 'INCONSISTENT_BOOKING_NIGHTS_REQUIRE_RECONCILIATION' END,
      CASE WHEN coalesce((booking_metrics ->> 'non_positive_guest_count')::bigint, 0) > 0
        THEN 'INVALID_GUEST_COUNTS_REQUIRE_RECONCILIATION' END,
      CASE WHEN (
        coalesce((booking_metrics ->> 'negative_monetary_value_count')::bigint, 0) > 0
        OR coalesce((booking_metrics ->> 'subtotal_inconsistency_count')::bigint, 0) > 0
        OR coalesce((booking_metrics ->> 'tax_inconsistency_count')::bigint, 0) > 0
        OR coalesce((booking_metrics ->> 'total_inconsistency_count')::bigint, 0) > 0
        OR coalesce((booking_metrics ->> 'discount_exceeds_charges_count')::bigint, 0) > 0
      ) THEN 'INVALID_BOOKING_PRICING_REQUIRES_RECONCILIATION' END,
      CASE WHEN (
        coalesce((booking_metrics ->> 'cancelled_without_timestamp_count')::bigint, 0) > 0
        OR coalesce((booking_metrics ->> 'non_cancelled_with_timestamp_count')::bigint, 0) > 0
      ) THEN 'INCONSISTENT_CANCELLATION_STATE_REQUIRES_RECONCILIATION' END,
      CASE WHEN coalesce((booking_metrics ->> 'invalid_booking_status_count')::bigint, 0) > 0
        THEN 'INVALID_BOOKING_STATUS_REQUIRES_RECONCILIATION' END,
      CASE WHEN coalesce((booking_metrics ->> 'invalid_payment_status_count')::bigint, 0) > 0
        THEN 'INVALID_PAYMENT_STATUS_REQUIRES_RECONCILIATION' END,
      CASE WHEN coalesce((booking_metrics ->> 'duplicate_booking_code_group_count')::bigint, 0) > 0
        THEN 'DUPLICATE_BOOKING_CODES_REQUIRE_RECONCILIATION' END,
      CASE WHEN coalesce((overlap_metrics ->> 'overlapping_pair_count')::bigint, 0) > 0
        THEN 'ACTIVE_BOOKING_OVERLAPS_REQUIRE_RECONCILIATION' END,
      CASE WHEN coalesce((capacity_metrics ->> 'over_capacity_booking_count')::bigint, 0) > 0
        THEN 'OVER_CAPACITY_BOOKINGS_REQUIRE_RECONCILIATION' END
    ], null)::text[] AS blocking_reasons,
    array_remove(ARRAY[
      CASE WHEN target_name_conflict_count > 0
        THEN 'BOOKING_SECURITY_OBJECT_NAMES_ALREADY_EXIST_REVIEW_BEFORE_MIGRATION' END,
      CASE WHEN NOT rls_enabled
        THEN 'BOOKINGS_RLS_IS_CURRENTLY_DISABLED' END,
      CASE WHEN force_rls
        THEN 'BOOKINGS_FORCE_RLS_IS_CURRENTLY_ENABLED' END,
      CASE WHEN NOT user_id_not_null
        THEN 'BOOKINGS_USER_ID_IS_CURRENTLY_NULLABLE' END,
      CASE WHEN NOT valid_date_constraint_detected
        THEN 'DATE_ORDER_CONSTRAINT_NOT_DETECTED' END,
      CASE WHEN NOT nights_consistency_constraint_detected
        THEN 'NIGHTS_CONSISTENCY_CONSTRAINT_NOT_DETECTED' END,
      CASE WHEN NOT cancellation_consistency_constraint_detected
        THEN 'CANCELLATION_CONSISTENCY_CONSTRAINT_NOT_DETECTED' END,
      CASE WHEN NOT exclusion_constraint_exists
        THEN 'OVERLAP_EXCLUSION_CONSTRAINT_NOT_DETECTED' END,
      CASE WHEN NOT user_id_index_exists
        THEN 'USER_ID_INDEX_NOT_DETECTED' END,
      CASE WHEN NOT availability_index_exists
        THEN 'AVAILABILITY_INDEX_NOT_DETECTED' END,
      CASE WHEN NOT customer_history_index_exists
        THEN 'CUSTOMER_HISTORY_INDEX_NOT_DETECTED' END,
      CASE WHEN btree_gist_available AND NOT btree_gist_installed
        THEN 'BTREE_GIST_AVAILABLE_BUT_NOT_INSTALLED' END
    ], null)::text[] AS warnings
  FROM decision_inputs AS decision
)
SELECT jsonb_build_object(
  'check', 'booking_security_preflight',
  'status', status,
  'summary', jsonb_build_object(
    'booking_count', booking_metrics -> 'booking_count',
    'schema_understood',
      bookings_table_exists
      AND all_expected_columns_exist
      AND expected_column_types_match,
    'data_inspected', booking_data_inspected,
    'capacity_inspected', capacity_data_inspected,
    'safe_migration_path_identified', NOT structural_failure
  ),
  'schema', jsonb_build_object(
    'table_exists', bookings_table_exists,
    'matching_relations', matching_relations,
    'owner', owner_name,
    'columns', columns,
    'expected_column_checks', expected_column_checks,
    'all_expected_columns_exist', all_expected_columns_exist,
    'expected_column_types_match', expected_column_types_match
  ),
  'constraints', jsonb_build_object(
    'all', constraints,
    'foreign_keys', foreign_keys,
    'primary_key_exists', primary_key_exists,
    'unique_constraint_exists', unique_constraint_exists,
    'user_id_not_null', user_id_not_null,
    'valid_date_constraint_detected', valid_date_constraint_detected,
    'nights_consistency_constraint_detected',
      nights_consistency_constraint_detected,
    'monetary_check_constraints_detected',
      monetary_check_constraints_detected,
    'booking_status_constraint_detected',
      booking_status_constraint_detected,
    'payment_status_constraint_detected',
      payment_status_constraint_detected,
    'cancellation_consistency_constraint_detected',
      cancellation_consistency_constraint_detected,
    'exclusion_constraint_exists', exclusion_constraint_exists
  ),
  'indexes', jsonb_build_object(
    'all', indexes,
    'user_id', user_id_index_exists,
    'room_id', room_id_index_exists,
    'booking_status', booking_status_index_exists,
    'payment_status', payment_status_index_exists,
    'availability', availability_index_exists,
    'customer_history', customer_history_index_exists
  ),
  'data_quality', booking_metrics - ARRAY[
    'overlapping_pair_count',
    'overlap_affected_room_count'
  ],
  'overlaps', jsonb_build_object(
    'holding_statuses', jsonb_build_array(
      'pending', 'confirmed', 'checked_in'
    ),
    'range_semantics', '[check_in_date, check_out_date)',
    'overlapping_pair_count',
      overlap_metrics -> 'overlapping_pair_count',
    'affected_room_count',
      overlap_metrics -> 'overlap_affected_room_count',
    'inspected', overlap_data_inspected
  ),
  'capacity', jsonb_build_object(
    'candidate_sources', candidate_sources,
    'valid_source_count', valid_source_count,
    'authoritative_source', selected_authoritative_source,
    'relationship_used', selected_relationship,
    'selection_reason', selection_reason,
    'schema_valid',
      capacity_query_safe
      AND selected_authoritative_source IS NOT NULL,
    'inspected', capacity_data_inspected,
    'over_capacity_booking_count',
      capacity_metrics -> 'over_capacity_booking_count'
  ),
  'rls', jsonb_build_object(
    'enabled', rls_enabled,
    'force_enabled', force_rls,
    'policies', policies
  ),
  'privileges', jsonb_build_object(
    'table', table_privileges,
    'sequences', sequences,
    'required_roles_visible', required_roles_visible
  ),
  'functions', jsonb_build_object(
    'booking_related', functions,
    'future_object_name_conflict_count', target_name_conflict_count
  ),
  'triggers', jsonb_build_object(
    'booking_triggers', triggers
  ),
  'postgres_capabilities', jsonb_build_object(
    'btree_gist_installed', btree_gist_installed,
    'btree_gist_available', btree_gist_available,
    'room_id_gist_equality_opclass_installed',
      room_id_gist_equality_opclass_installed,
    'daterange_gist_opclass_exists', daterange_gist_opclass_exists,
    'range_overlap_operator_exists', range_overlap_operator_exists,
    'date_columns_compatible', date_columns_compatible,
    'room_id_type_supported_by_btree_gist',
      room_id_type_supported_by_btree_gist,
    'requires_btree_gist_install', requires_btree_gist_install,
    'exclusion_constraint_possible_after_install',
      exclusion_constraint_possible_after_install,
    'safe_alternative_available', safe_alternative_available,
    'future_exclusion_constraint_supported',
      future_exclusion_constraint_supported,
    'safe_concurrency_path_available',
      safe_concurrency_path_available
  ),
  'foundation_integrity', jsonb_build_object(
    'tables', foundation_tables,
    'required_tables_exist', foundation_tables_exist,
    'profiles_auth_users_foreign_key_valid', profiles_auth_fk_valid,
    'is_admin', jsonb_build_object(
      'exists_exactly_once', is_admin_exists_once,
      'identity_arguments', is_admin_identity_arguments,
      'returns_boolean', is_admin_returns_boolean,
      'security_definer', is_admin_security_definer,
      'stable', is_admin_stable,
      'language_sql', is_admin_language_sql,
      'owner', is_admin_owner,
      'search_path_safe', is_admin_search_path_safe,
      'public_execute', NOT is_admin_no_public_execute,
      'anon_execute', NOT is_admin_no_anon_execute,
      'authenticated_execute', is_admin_authenticated_execute,
      'approved_body', is_admin_approved_body,
      'behavior_consistent_with_auth_profile_foundation',
        is_admin_approved_body
        AND is_admin_uses_auth_uid
        AND is_admin_reads_profiles
        AND is_admin_requires_admin_role
        AND is_admin_requires_active_status
        AND is_admin_avoids_unapproved_identity_sources,
      'normalized_definition_hash',
        is_admin_normalized_definition_hash,
      'failed_approval_rules',
        to_jsonb(is_admin_failed_approval_rules),
      'uses_auth_uid', is_admin_uses_auth_uid,
      'reads_public_profiles', is_admin_reads_profiles,
      'requires_admin_role', is_admin_requires_admin_role,
      'requires_active_status', is_admin_requires_active_status,
      'avoids_unapproved_identity_sources',
        is_admin_avoids_unapproved_identity_sources
    )
  ),
  'blocking_reasons', to_jsonb(blocking_reasons),
  'warnings', to_jsonb(warnings),
  'recommended_next_action', CASE status
    WHEN 'PREFLIGHT_PASSED'
      THEN 'Review the reported schema, privileges and object warnings, then prepare the Booking Security Foundation migration.'
    WHEN 'RECONCILIATION_REQUIRED'
      THEN 'Reconcile the counted booking data issues with a separately reviewed, data-specific plan before creating the foundation migration.'
    ELSE
      'Resolve structural blocking reasons and rerun this read-only preflight before designing the migration.'
  END
)
FROM result;

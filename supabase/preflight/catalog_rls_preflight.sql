-- GoStay - Catalog RLS and Privilege Hardening preflight
-- Read-only: this single query inspects PostgreSQL catalogs and returns one JSON object.
-- It does not read catalog business rows or user data.

WITH
target_tables(table_schema, table_name) AS (
  VALUES
    ('public', 'branches'),
    ('public', 'room_types'),
    ('public', 'rooms'),
    ('public', 'amenities'),
    ('public', 'room_images'),
    ('public', 'room_amenities'),
    ('public', 'promotions')
),
target_relations AS (
  SELECT
    target.table_schema,
    target.table_name,
    pg_catalog.to_regclass(
      pg_catalog.format('%I.%I', target.table_schema, target.table_name)
    ) AS relation_oid,
    class.relkind
  FROM target_tables AS target
  LEFT JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.nspname = target.table_schema
  LEFT JOIN pg_catalog.pg_class AS class
    ON class.relnamespace = namespace.oid
   AND class.relname = target.table_name
),
table_existence AS (
  SELECT
    count(*) FILTER (WHERE relation_oid IS NOT NULL) = 7 AS all_tables_exist,
    count(*) FILTER (
      WHERE relation_oid IS NOT NULL
        AND relkind IN ('r', 'p')
    ) = 7 AS all_target_relations_are_tables,
    jsonb_object_agg(
      table_name,
      jsonb_build_object(
        'exists', relation_oid IS NOT NULL,
        'relkind', relkind,
        'is_ordinary_or_partitioned_table',
          relation_oid IS NOT NULL AND relkind IN ('r', 'p')
      )
      ORDER BY table_name
    ) AS tables
  FROM target_relations
),
required_columns(
  table_name,
  column_name,
  expected_udt_name,
  expected_nullable
) AS (
  VALUES
    ('branches', 'id', 'int8', 'NO'),
    ('branches', 'status', 'varchar', 'NO'),
    ('room_types', 'id', 'int8', 'NO'),
    ('rooms', 'id', 'int8', 'NO'),
    ('rooms', 'branch_id', 'int8', 'NO'),
    ('rooms', 'status', 'varchar', 'NO'),
    ('amenities', 'id', 'int8', 'NO'),
    ('amenities', 'status', 'varchar', 'NO'),
    ('room_images', 'id', 'int8', 'NO'),
    ('room_images', 'room_id', 'int8', 'NO'),
    ('room_amenities', 'room_id', 'int8', 'NO'),
    ('room_amenities', 'amenity_id', 'int8', 'NO'),
    ('promotions', 'id', 'int8', 'NO'),
    ('promotions', 'status', 'varchar', 'NO'),
    ('promotions', 'start_at', 'timestamptz', 'NO'),
    ('promotions', 'end_at', 'timestamptz', 'NO'),
    ('promotions', 'usage_limit', 'int4', 'YES'),
    ('promotions', 'used_count', 'int4', 'NO')
),
column_catalog AS (
  SELECT
    columns.table_name,
    columns.ordinal_position,
    columns.column_name,
    columns.data_type,
    columns.udt_schema,
    columns.udt_name,
    columns.is_nullable,
    columns.column_default,
    columns.is_identity,
    columns.identity_generation
  FROM information_schema.columns AS columns
  JOIN target_tables AS target
    ON target.table_schema = columns.table_schema
   AND target.table_name = columns.table_name
),
column_summary AS (
  SELECT
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'table', table_name,
          'ordinal_position', ordinal_position,
          'column', column_name,
          'data_type', data_type,
          'udt_schema', udt_schema,
          'udt_name', udt_name,
          'nullable', is_nullable,
          'default', column_default,
          'is_identity', is_identity,
          'identity_generation', identity_generation
        )
        ORDER BY table_name, ordinal_position
      ),
      '[]'::jsonb
    ) AS columns
  FROM column_catalog
),
required_column_state AS (
  SELECT
    count(*) = (SELECT count(*) FROM required_columns)
    AND coalesce(bool_and(
      actual.column_name IS NOT NULL
      AND actual.udt_schema = 'pg_catalog'
      AND actual.udt_name = required.expected_udt_name
      AND actual.is_nullable = required.expected_nullable
    ), false) AS required_columns_match
  FROM required_columns AS required
  LEFT JOIN column_catalog AS actual
    ON actual.table_name = required.table_name
   AND actual.column_name = required.column_name
),
constraint_catalog AS (
  SELECT
    relation.table_name,
    con.oid AS constraint_oid,
    con.conname AS constraint_name,
    con.contype AS constraint_type_code,
    con.convalidated AS validated,
    pg_catalog.pg_get_constraintdef(con.oid, true)
      AS constraint_definition
  FROM target_relations AS relation
  JOIN pg_catalog.pg_constraint AS con
    ON con.conrelid = relation.relation_oid
),
constraint_summary AS (
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'table', table_name,
        'constraint_name', constraint_name,
        'constraint_type', CASE constraint_type_code
          WHEN 'p' THEN 'PRIMARY KEY'
          WHEN 'f' THEN 'FOREIGN KEY'
          WHEN 'c' THEN 'CHECK'
          WHEN 'u' THEN 'UNIQUE'
          WHEN 'x' THEN 'EXCLUSION'
          ELSE constraint_type_code::text
        END,
        'validated', validated,
        'definition', constraint_definition
      )
      ORDER BY table_name, constraint_name
    ),
    '[]'::jsonb
  ) AS constraints
  FROM constraint_catalog
),
expected_status_values(table_name, expected_values) AS (
  VALUES
    ('branches', ARRAY['active', 'inactive']::text[]),
    ('rooms', ARRAY['available', 'inactive', 'maintenance']::text[]),
    ('amenities', ARRAY['active', 'inactive']::text[]),
    ('promotions', ARRAY['active', 'expired', 'inactive']::text[])
),
status_check_constraints AS (
  SELECT
    catalog.table_name,
    catalog.constraint_name,
    catalog.validated,
    catalog.constraint_definition,
    coalesce(
      (
        SELECT array_agg(
          DISTINCT match.value[1]
          ORDER BY match.value[1]
        )
        FROM pg_catalog.regexp_matches(
          catalog.constraint_definition,
          $pattern$'([^']+)'$pattern$,
          'g'
        ) AS match(value)
      ),
      ARRAY[]::text[]
    ) AS allowed_values
  FROM constraint_catalog AS catalog
  WHERE catalog.constraint_type_code = 'c'
    AND catalog.constraint_definition ~* 'status'
),
status_state AS (
  SELECT
    count(*) = 4
    AND coalesce(bool_and(
      status_column.column_name IS NOT NULL
      AND status_column.udt_name = 'varchar'
      AND status_column.is_nullable = 'NO'
      AND checks.constraint_name IS NOT NULL
      AND checks.validated
      AND checks.allowed_values = expected.expected_values
    ), false) AS status_constraints_match,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'table', expected.table_name,
          'status_column_exists', status_column.column_name IS NOT NULL,
          'data_type', status_column.data_type,
          'nullable', status_column.is_nullable,
          'default', status_column.column_default,
          'constraint_name', checks.constraint_name,
          'constraint_validated', checks.validated,
          'allowed_values', coalesce(
            to_jsonb(checks.allowed_values),
            '[]'::jsonb
          ),
          'expected_values', to_jsonb(expected.expected_values)
        )
        ORDER BY expected.table_name
      ),
      '[]'::jsonb
    ) AS status_columns
  FROM expected_status_values AS expected
  LEFT JOIN column_catalog AS status_column
    ON status_column.table_name = expected.table_name
   AND status_column.column_name = 'status'
  LEFT JOIN status_check_constraints AS checks
    ON checks.table_name = expected.table_name
),
expected_foreign_keys(
  source_table,
  source_column,
  target_table,
  target_column
) AS (
  VALUES
    ('rooms', 'branch_id', 'branches', 'id'),
    ('room_images', 'room_id', 'rooms', 'id'),
    ('room_amenities', 'room_id', 'rooms', 'id'),
    ('room_amenities', 'amenity_id', 'amenities', 'id')
),
foreign_key_state AS (
  SELECT
    count(*) = 4
    AND coalesce(bool_and(
      matched.constraint_name IS NOT NULL
      AND matched.validated
    ), false) AS required_foreign_keys_match,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'source_table', expected.source_table,
          'source_column', expected.source_column,
          'target_table', expected.target_table,
          'target_column', expected.target_column,
          'exists', matched.constraint_name IS NOT NULL,
          'constraint_name', matched.constraint_name,
          'validated', matched.validated
        )
        ORDER BY expected.source_table, expected.source_column
      ),
      '[]'::jsonb
    ) AS foreign_keys
  FROM expected_foreign_keys AS expected
  LEFT JOIN LATERAL (
    SELECT
      con.conname AS constraint_name,
      con.convalidated AS validated
    FROM pg_catalog.pg_constraint AS con
    JOIN pg_catalog.pg_class AS source_relation
      ON source_relation.oid = con.conrelid
    JOIN pg_catalog.pg_namespace AS source_namespace
      ON source_namespace.oid = source_relation.relnamespace
    JOIN pg_catalog.pg_class AS target_relation
      ON target_relation.oid = con.confrelid
    JOIN pg_catalog.pg_namespace AS target_namespace
      ON target_namespace.oid = target_relation.relnamespace
    JOIN pg_catalog.pg_attribute AS source_attribute
      ON source_attribute.attrelid = source_relation.oid
     AND source_attribute.attnum = con.conkey[1]
    JOIN pg_catalog.pg_attribute AS target_attribute
      ON target_attribute.attrelid = target_relation.oid
     AND target_attribute.attnum = con.confkey[1]
    WHERE con.contype = 'f'
      AND pg_catalog.array_length(con.conkey, 1) = 1
      AND pg_catalog.array_length(con.confkey, 1) = 1
      AND source_namespace.nspname = 'public'
      AND source_relation.relname = expected.source_table
      AND source_attribute.attname = expected.source_column
      AND target_namespace.nspname = 'public'
      AND target_relation.relname = expected.target_table
      AND target_attribute.attname = expected.target_column
    ORDER BY con.conname
    LIMIT 1
  ) AS matched ON true
),
rls_state AS (
  SELECT
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'table', relation.table_name,
          'rls_enabled', coalesce(class.relrowsecurity, false),
          'force_rls', coalesce(class.relforcerowsecurity, false)
        )
        ORDER BY relation.table_name
      ),
      '[]'::jsonb
    ) AS rls
  FROM target_relations AS relation
  LEFT JOIN pg_catalog.pg_class AS class
    ON class.oid = relation.relation_oid
),
policy_catalog AS (
  SELECT
    relation.table_name,
    policy.polname AS policy_name,
    CASE policy.polcmd
      WHEN 'r' THEN 'SELECT'
      WHEN 'a' THEN 'INSERT'
      WHEN 'w' THEN 'UPDATE'
      WHEN 'd' THEN 'DELETE'
      WHEN '*' THEN 'ALL'
      ELSE policy.polcmd::text
    END AS command,
    (
      SELECT array_agg(role_name ORDER BY role_name)::text[]
      FROM (
        SELECT CASE role_oid
          WHEN 0 THEN 'PUBLIC'::text
          ELSE pg_catalog.pg_get_userbyid(role_oid)::text
        END AS role_name
        FROM pg_catalog.unnest(policy.polroles) AS roles(role_oid)
      ) AS normalized_roles
    ) AS roles,
    CASE WHEN policy.polpermissive THEN 'PERMISSIVE' ELSE 'RESTRICTIVE' END
      AS policy_mode,
    pg_catalog.pg_get_expr(policy.polqual, policy.polrelid) AS using_expression,
    pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
      AS with_check_expression,
    coalesce(
      pg_catalog.regexp_replace(
        pg_catalog.lower(
          pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
        ),
        '[[:space:]]+',
        '',
        'g'
      ),
      '<null>'
    ) AS normalized_using_expression,
    coalesce(
      pg_catalog.regexp_replace(
        pg_catalog.lower(
          pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
        ),
        '[[:space:]]+',
        '',
        'g'
      ),
      '<null>'
    ) AS normalized_with_check_expression
  FROM target_relations AS relation
  JOIN pg_catalog.pg_policy AS policy
    ON policy.polrelid = relation.relation_oid
),
policy_summary AS (
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'table', table_name,
        'policy_name', policy_name,
        'command', command,
        'roles', to_jsonb(roles),
        'mode', policy_mode,
        'using', using_expression,
        'with_check', with_check_expression
      )
      ORDER BY table_name, policy_name
    ),
    '[]'::jsonb
  ) AS policies
  FROM policy_catalog
),
expected_existing_policies(
  table_name,
  policy_name,
  command,
  expected_roles,
  policy_mode,
  normalized_using_expression,
  normalized_with_check_expression
) AS (
  -- Missing reviewed legacy policies are reported but are intentionally
  -- non-blocking. The future migration must safely support both states:
  -- reuse/replace a valid present policy, or create the new policy when absent.
  -- An expected name with any modified definition is blocking.
  VALUES
    (
      'branches',
      'Public read active branches',
      'SELECT',
      ARRAY['anon', 'authenticated']::text[],
      'PERMISSIVE',
      $definition$((status)::text='active'::text)$definition$,
      '<null>'
    ),
    (
      'room_types',
      'Public read room types',
      'SELECT',
      ARRAY['anon', 'authenticated']::text[],
      'PERMISSIVE',
      'true',
      '<null>'
    ),
    (
      'rooms',
      'Public read available rooms',
      'SELECT',
      ARRAY['anon', 'authenticated']::text[],
      'PERMISSIVE',
      $definition$((status)::text='available'::text)$definition$,
      '<null>'
    )
),
expected_policy_assessment AS (
  SELECT
    expected.table_name,
    expected.policy_name,
    actual.policy_name IS NOT NULL AS present,
    actual.policy_name IS NOT NULL
      AND actual.command = expected.command
      AND actual.roles = expected.expected_roles
      AND actual.policy_mode = expected.policy_mode
      AND actual.normalized_using_expression =
        expected.normalized_using_expression
      AND actual.normalized_with_check_expression =
        expected.normalized_with_check_expression AS valid,
    actual.command AS actual_command,
    actual.roles AS actual_roles,
    actual.policy_mode AS actual_mode,
    actual.normalized_using_expression AS actual_normalized_using,
    actual.normalized_with_check_expression AS actual_normalized_with_check
  FROM expected_existing_policies AS expected
  LEFT JOIN policy_catalog AS actual
    ON actual.table_name = expected.table_name
   AND actual.policy_name = expected.policy_name
),
expected_policy_state AS (
  SELECT
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'table', table_name,
          'policy_name', policy_name
        )
        ORDER BY table_name, policy_name
      ) FILTER (WHERE present AND valid),
      '[]'::jsonb
    ) AS expected_policies_present_and_valid,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'table', table_name,
          'policy_name', policy_name
        )
        ORDER BY table_name, policy_name
      ) FILTER (WHERE NOT present),
      '[]'::jsonb
    ) AS expected_policies_missing,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'table', table_name,
          'policy_name', policy_name,
          'actual_command', actual_command,
          'actual_roles', to_jsonb(actual_roles),
          'actual_mode', actual_mode,
          'actual_normalized_using', actual_normalized_using,
          'actual_normalized_with_check', actual_normalized_with_check
        )
        ORDER BY table_name, policy_name
      ) FILTER (WHERE present AND NOT valid),
      '[]'::jsonb
    ) AS expected_named_policies_with_invalid_definitions,
    count(*) FILTER (WHERE present AND valid)
      AS expected_policy_valid_count,
    count(*) FILTER (WHERE NOT present)
      AS expected_policy_missing_count,
    count(*) FILTER (WHERE present AND NOT valid)
      AS expected_policy_invalid_count
  FROM expected_policy_assessment
),
outside_allowlist_policy_state AS (
  SELECT
    count(*) AS outside_allowlist_policy_count,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'table', policy.table_name,
          'policy_name', policy.policy_name,
          'command', policy.command
        )
        ORDER BY policy.table_name, policy.policy_name
      ),
      '[]'::jsonb
    ) AS policies_outside_allowlist
  FROM policy_catalog AS policy
  LEFT JOIN expected_existing_policies AS expected
    ON expected.table_name = policy.table_name
   AND expected.policy_name = policy.policy_name
  WHERE expected.policy_name IS NULL
),
table_grant_catalog AS (
  SELECT
    relation.table_name,
    CASE acl.grantee
      WHEN 0 THEN 'PUBLIC'
      ELSE grantee_role.rolname
    END AS grantee,
    acl.privilege_type,
    acl.is_grantable
  FROM target_relations AS relation
  JOIN pg_catalog.pg_class AS class
    ON class.oid = relation.relation_oid
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    coalesce(class.relacl, pg_catalog.acldefault('r', class.relowner))
  ) AS acl
  LEFT JOIN pg_catalog.pg_roles AS grantee_role
    ON grantee_role.oid = acl.grantee
  WHERE acl.grantee = 0
     OR grantee_role.rolname IN ('anon', 'authenticated')
),
table_grant_summary AS (
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'table', table_name,
        'grantee', grantee,
        'privilege', privilege_type,
        'grantable', is_grantable
      )
      ORDER BY table_name, grantee, privilege_type
    ),
    '[]'::jsonb
  ) AS table_grants
  FROM table_grant_catalog
),
frontend_grantees(grantee) AS (
  VALUES ('PUBLIC'), ('anon'), ('authenticated')
),
table_privilege_types(privilege_type) AS (
  VALUES
    ('SELECT'),
    ('INSERT'),
    ('UPDATE'),
    ('DELETE'),
    ('TRUNCATE'),
    ('REFERENCES'),
    ('TRIGGER')
),
effective_table_privilege_summary AS (
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'table', relation.table_name,
        'grantee', grantee.grantee,
        'privilege', privilege.privilege_type,
        'effective', CASE
          WHEN grantee.grantee = 'PUBLIC' THEN EXISTS (
            SELECT 1
            FROM pg_catalog.pg_class AS class
            CROSS JOIN LATERAL pg_catalog.aclexplode(
              coalesce(
                class.relacl,
                pg_catalog.acldefault('r', class.relowner)
              )
            ) AS acl
            WHERE class.oid = relation.relation_oid
              AND acl.grantee = 0
              AND acl.privilege_type = privilege.privilege_type
          )
          ELSE pg_catalog.has_table_privilege(
            grantee.grantee,
            relation.relation_oid,
            privilege.privilege_type
          )
        END
      )
      ORDER BY
        relation.table_name,
        grantee.grantee,
        privilege.privilege_type
    ),
    '[]'::jsonb
  ) AS effective_table_privileges
  FROM target_relations AS relation
  CROSS JOIN frontend_grantees AS grantee
  CROSS JOIN table_privilege_types AS privilege
  WHERE relation.relation_oid IS NOT NULL
    AND relation.relkind IN ('r', 'p')
),
identity_sequence_catalog AS (
  SELECT DISTINCT
    sequence_namespace.nspname AS sequence_schema,
    sequence_class.relname AS sequence_name,
    relation.table_name AS owned_by_table,
    attribute.attname AS owned_by_column,
    attribute.attidentity AS identity_code,
    sequence_class.oid AS sequence_oid,
    sequence_class.relowner,
    sequence_class.relacl
  FROM target_relations AS relation
  JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = relation.relation_oid
   AND attribute.attnum > 0
   AND NOT attribute.attisdropped
   AND attribute.attidentity IN ('a', 'd')
  JOIN pg_catalog.pg_depend AS dependency
    ON dependency.refobjid = relation.relation_oid
   AND dependency.refobjsubid = attribute.attnum
   AND dependency.deptype = 'i'
  JOIN pg_catalog.pg_class AS sequence_class
    ON sequence_class.oid = dependency.objid
   AND sequence_class.relkind = 'S'
  JOIN pg_catalog.pg_namespace AS sequence_namespace
    ON sequence_namespace.oid = sequence_class.relnamespace
),
identity_sequence_summary AS (
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'sequence_schema', sequence_schema,
        'sequence_name', sequence_name,
        'owned_by_table', owned_by_table,
        'owned_by_column', owned_by_column,
        'identity_generation', CASE identity_code
          WHEN 'a' THEN 'ALWAYS'
          WHEN 'd' THEN 'BY DEFAULT'
          ELSE identity_code::text
        END
      )
      ORDER BY sequence_schema, sequence_name
    ),
    '[]'::jsonb
  ) AS identity_sequences
  FROM identity_sequence_catalog
),
sequence_privilege_summary AS (
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'sequence_schema', sequence.sequence_schema,
        'sequence_name', sequence.sequence_name,
        'public_usage', EXISTS (
          SELECT 1
          FROM pg_catalog.aclexplode(
            coalesce(
              sequence.relacl,
              pg_catalog.acldefault('S', sequence.relowner)
            )
          ) AS acl
          WHERE acl.grantee = 0
            AND acl.privilege_type = 'USAGE'
        ),
        'public_select', EXISTS (
          SELECT 1
          FROM pg_catalog.aclexplode(
            coalesce(
              sequence.relacl,
              pg_catalog.acldefault('S', sequence.relowner)
            )
          ) AS acl
          WHERE acl.grantee = 0
            AND acl.privilege_type = 'SELECT'
        ),
        'public_update', EXISTS (
          SELECT 1
          FROM pg_catalog.aclexplode(
            coalesce(
              sequence.relacl,
              pg_catalog.acldefault('S', sequence.relowner)
            )
          ) AS acl
          WHERE acl.grantee = 0
            AND acl.privilege_type = 'UPDATE'
        ),
        'anon_usage', pg_catalog.has_sequence_privilege(
          'anon', sequence.sequence_oid, 'USAGE'
        ),
        'anon_select', pg_catalog.has_sequence_privilege(
          'anon', sequence.sequence_oid, 'SELECT'
        ),
        'anon_update', pg_catalog.has_sequence_privilege(
          'anon', sequence.sequence_oid, 'UPDATE'
        ),
        'authenticated_usage', pg_catalog.has_sequence_privilege(
          'authenticated', sequence.sequence_oid, 'USAGE'
        ),
        'authenticated_select', pg_catalog.has_sequence_privilege(
          'authenticated', sequence.sequence_oid, 'SELECT'
        ),
        'authenticated_update', pg_catalog.has_sequence_privilege(
          'authenticated', sequence.sequence_oid, 'UPDATE'
        )
      )
      ORDER BY sequence.sequence_schema, sequence.sequence_name
    ),
    '[]'::jsonb
  ) AS sequence_privileges
  FROM identity_sequence_catalog AS sequence
),
is_admin_catalog AS (
  SELECT
    p.oid,
    p.proowner,
    p.prosecdef,
    p.proconfig,
    p.proacl,
    p.pronargs,
    p.prorettype,
    p.provolatile,
    language.lanname AS language_name,
    p.prosrc,
    pg_catalog.btrim(
      pg_catalog.regexp_replace(
        pg_catalog.lower(p.prosrc),
        '[[:space:]]+',
        '',
        'g'
      ),
      pg_catalog.chr(59)
    ) AS normalized_body
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = p.pronamespace
  JOIN pg_catalog.pg_language AS language
    ON language.oid = p.prolang
  WHERE namespace.nspname = 'public'
    AND p.proname = 'is_admin'
    AND p.pronargs = 0
),
is_admin_state AS (
  SELECT
    count(*) = 1 AS is_admin_exactly_one_zero_argument_function,
    count(*) = 1 AS is_admin_exists,
    coalesce(bool_and(prorettype = 'boolean'::regtype), false)
      AS is_admin_returns_boolean,
    coalesce(bool_and(language_name = 'sql'), false)
      AS is_admin_language_sql,
    coalesce(bool_and(provolatile = 's'), false)
      AS is_admin_stable,
    coalesce(bool_and(prosecdef), false) AS is_admin_security_definer,
    CASE WHEN count(*) = 1
      THEN pg_catalog.min(pg_catalog.pg_get_userbyid(proowner))
      ELSE NULL
    END AS is_admin_owner,
    count(*) = 1
    AND coalesce(bool_and(
      EXISTS (
        SELECT 1
        FROM pg_catalog.unnest(proconfig) AS config(setting)
        WHERE pg_catalog.split_part(config.setting, '=', 1) = 'search_path'
          AND pg_catalog.replace(
            pg_catalog.split_part(config.setting, '=', 2),
            '"',
            ''
          ) = ''
      )
    ), false) AS is_admin_search_path_safe,
    coalesce(bool_or(
      EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(
          coalesce(proacl, pg_catalog.acldefault('f', proowner))
        ) AS acl
        WHERE acl.grantee = 0
          AND acl.privilege_type = 'EXECUTE'
      )
    ), false) AS is_admin_public_execute,
    coalesce(bool_or(
      pg_catalog.has_function_privilege('anon', oid, 'EXECUTE')
    ), false) AS is_admin_anon_execute,
    coalesce(bool_or(
      pg_catalog.has_function_privilege('authenticated', oid, 'EXECUTE')
    ), false) AS is_admin_authenticated_execute,
    count(*) = 1
    AND coalesce(bool_and(
      normalized_body =
        $approved$selectcoalesce(exists(select1frompublic.profilesaspwherep.id=auth.uid()andp.role='admin'andp.status='active'),false)$approved$
    ), false) AS is_admin_definition_matches_approved,
    count(*) = 1
    AND coalesce(bool_and(normalized_body LIKE '%auth.uid()%'), false)
      AS is_admin_uses_auth_uid,
    count(*) = 1
    AND coalesce(bool_and(normalized_body LIKE '%frompublic.profiles%'), false)
      AS is_admin_reads_schema_qualified_profiles,
    count(*) = 1
    AND coalesce(bool_and(normalized_body LIKE $check$%role='admin'%$check$), false)
      AS is_admin_requires_admin_role,
    count(*) = 1
    AND coalesce(bool_and(normalized_body LIKE $check$%status='active'%$check$), false)
      AS is_admin_requires_active_status,
    count(*) = 1
    AND coalesce(bool_and(
      normalized_body !~*
        'email|raw_user_meta_data|raw_app_meta_data|jwt|localstorage|current_setting'
    ), false) AS is_admin_has_no_unapproved_identity_source
  FROM is_admin_catalog
),
checks AS (
  SELECT
    existence.all_tables_exist,
    existence.all_target_relations_are_tables,
    required.required_columns_match,
    status.status_constraints_match,
    foreign_keys.required_foreign_keys_match,
    expected_policies.expected_policy_valid_count,
    expected_policies.expected_policy_missing_count,
    expected_policies.expected_policy_invalid_count,
    outside_policies.outside_allowlist_policy_count,
    admin.is_admin_exists,
    admin.is_admin_exactly_one_zero_argument_function,
    admin.is_admin_returns_boolean,
    admin.is_admin_language_sql,
    admin.is_admin_stable,
    admin.is_admin_security_definer,
    admin.is_admin_owner,
    admin.is_admin_search_path_safe,
    admin.is_admin_public_execute,
    admin.is_admin_anon_execute,
    admin.is_admin_authenticated_execute,
    admin.is_admin_definition_matches_approved,
    admin.is_admin_uses_auth_uid,
    admin.is_admin_reads_schema_qualified_profiles,
    admin.is_admin_requires_admin_role,
    admin.is_admin_requires_active_status,
    admin.is_admin_has_no_unapproved_identity_source,
    existence.tables AS table_existence,
    columns.columns,
    constraints.constraints,
    status.status_columns,
    foreign_keys.foreign_keys,
    rls.rls,
    policies.policies,
    expected_policies.expected_policies_present_and_valid,
    expected_policies.expected_policies_missing,
    expected_policies.expected_named_policies_with_invalid_definitions,
    outside_policies.policies_outside_allowlist,
    grants.table_grants,
    effective_grants.effective_table_privileges,
    sequences.identity_sequences,
    sequence_privileges.sequence_privileges
  FROM table_existence AS existence
  CROSS JOIN required_column_state AS required
  CROSS JOIN column_summary AS columns
  CROSS JOIN constraint_summary AS constraints
  CROSS JOIN status_state AS status
  CROSS JOIN foreign_key_state AS foreign_keys
  CROSS JOIN rls_state AS rls
  CROSS JOIN policy_summary AS policies
  CROSS JOIN expected_policy_state AS expected_policies
  CROSS JOIN outside_allowlist_policy_state AS outside_policies
  CROSS JOIN table_grant_summary AS grants
  CROSS JOIN effective_table_privilege_summary AS effective_grants
  CROSS JOIN identity_sequence_summary AS sequences
  CROSS JOIN sequence_privilege_summary AS sequence_privileges
  CROSS JOIN is_admin_state AS admin
),
decision_state AS (
  SELECT
    checks.*,
    (
      all_tables_exist
      AND all_target_relations_are_tables
      AND required_columns_match
      AND status_constraints_match
      AND required_foreign_keys_match
      AND expected_policy_invalid_count = 0
      AND outside_allowlist_policy_count = 0
      AND is_admin_exists
      AND is_admin_exactly_one_zero_argument_function
      AND is_admin_returns_boolean
      AND is_admin_language_sql
      AND is_admin_stable
      AND is_admin_security_definer
      AND is_admin_owner = 'postgres'
      AND is_admin_search_path_safe
      AND NOT is_admin_public_execute
      AND NOT is_admin_anon_execute
      AND is_admin_authenticated_execute
      AND is_admin_definition_matches_approved
      AND is_admin_uses_auth_uid
      AND is_admin_reads_schema_qualified_profiles
      AND is_admin_requires_admin_role
      AND is_admin_requires_active_status
      AND is_admin_has_no_unapproved_identity_source
    ) AS preflight_passed,
    array_remove(ARRAY[
      CASE WHEN NOT all_tables_exist
        THEN 'TARGET_TABLE_MISSING' END,
      CASE WHEN NOT all_target_relations_are_tables
        THEN 'TARGET_RELATION_IS_NOT_ORDINARY_OR_PARTITIONED_TABLE' END,
      CASE WHEN NOT required_columns_match
        THEN 'REQUIRED_COLUMN_SCHEMA_MISMATCH' END,
      CASE WHEN NOT status_constraints_match
        THEN 'STATUS_COLUMN_OR_ALLOWLIST_MISMATCH' END,
      CASE WHEN NOT required_foreign_keys_match
        THEN 'REQUIRED_FOREIGN_KEY_MISSING_OR_INVALID' END,
      CASE WHEN expected_policy_invalid_count <> 0
        THEN 'EXPECTED_POLICY_DEFINITION_MODIFIED' END,
      CASE WHEN outside_allowlist_policy_count <> 0
        THEN 'POLICY_OUTSIDE_ALLOWLIST' END,
      CASE WHEN NOT is_admin_exists
        THEN 'IS_ADMIN_MISSING_OR_DUPLICATED' END,
      CASE WHEN NOT is_admin_exactly_one_zero_argument_function
        THEN 'IS_ADMIN_ZERO_ARGUMENT_SIGNATURE_INVALID' END,
      CASE WHEN is_admin_exists AND NOT is_admin_returns_boolean
        THEN 'IS_ADMIN_RETURN_TYPE_INVALID' END,
      CASE WHEN is_admin_exists AND NOT is_admin_language_sql
        THEN 'IS_ADMIN_LANGUAGE_INVALID' END,
      CASE WHEN is_admin_exists AND NOT is_admin_stable
        THEN 'IS_ADMIN_VOLATILITY_INVALID' END,
      CASE WHEN is_admin_exists AND NOT is_admin_security_definer
        THEN 'IS_ADMIN_NOT_SECURITY_DEFINER' END,
      CASE WHEN is_admin_exists
             AND is_admin_owner IS DISTINCT FROM 'postgres'
        THEN 'IS_ADMIN_OWNER_INVALID' END,
      CASE WHEN is_admin_exists AND NOT is_admin_search_path_safe
        THEN 'IS_ADMIN_SEARCH_PATH_UNSAFE' END,
      CASE WHEN is_admin_public_execute
        THEN 'IS_ADMIN_PUBLIC_EXECUTE_PRESENT' END,
      CASE WHEN is_admin_anon_execute
        THEN 'IS_ADMIN_ANON_EXECUTE_PRESENT' END,
      CASE WHEN NOT is_admin_authenticated_execute
        THEN 'IS_ADMIN_AUTHENTICATED_EXECUTE_MISSING' END,
      CASE WHEN is_admin_exists AND NOT is_admin_definition_matches_approved
        THEN 'IS_ADMIN_DEFINITION_MISMATCH' END,
      CASE WHEN is_admin_exists AND NOT is_admin_uses_auth_uid
        THEN 'IS_ADMIN_DOES_NOT_USE_AUTH_UID' END,
      CASE WHEN is_admin_exists
             AND NOT is_admin_reads_schema_qualified_profiles
        THEN 'IS_ADMIN_PROFILES_REFERENCE_UNSAFE' END,
      CASE WHEN is_admin_exists AND NOT is_admin_requires_admin_role
        THEN 'IS_ADMIN_ROLE_CHECK_MISSING' END,
      CASE WHEN is_admin_exists AND NOT is_admin_requires_active_status
        THEN 'IS_ADMIN_STATUS_CHECK_MISSING' END,
      CASE WHEN is_admin_exists
             AND NOT is_admin_has_no_unapproved_identity_source
        THEN 'IS_ADMIN_UNAPPROVED_IDENTITY_SOURCE' END
    ], NULL) AS blocking_reasons
  FROM checks
)
SELECT jsonb_build_object(
  'all_tables_exist', all_tables_exist,
  'all_target_relations_are_tables', all_target_relations_are_tables,
  'table_existence', table_existence,
  'required_columns_match', required_columns_match,
  'columns', columns,
  'constraints', constraints,
  'status_constraints_match', status_constraints_match,
  'status_columns', status_columns,
  'required_foreign_keys_match', required_foreign_keys_match,
  'foreign_keys', foreign_keys,
  'rls', rls,
  'policies', policies,
  'legacy_policy_missing_is_blocking', false,
  'legacy_policy_missing_decision',
    'NON_BLOCKING_IF_FUTURE_MIGRATION_SUPPORTS_PRESENT_AND_ABSENT_STATES',
  'expected_policy_valid_count', expected_policy_valid_count,
  'expected_policies_present_and_valid',
    expected_policies_present_and_valid,
  'expected_policy_missing_count', expected_policy_missing_count,
  'expected_policies_missing', expected_policies_missing,
  'expected_policy_invalid_count', expected_policy_invalid_count,
  'expected_named_policies_with_invalid_definitions',
    expected_named_policies_with_invalid_definitions,
  'outside_allowlist_policy_count', outside_allowlist_policy_count,
  'policies_outside_allowlist', policies_outside_allowlist,
  'table_grants', table_grants,
  'effective_table_privileges', effective_table_privileges,
  'identity_sequences', identity_sequences,
  'sequence_privileges', sequence_privileges,
  'is_admin_exists', is_admin_exists,
  'is_admin_exactly_one_zero_argument_function',
    is_admin_exactly_one_zero_argument_function,
  'is_admin_returns_boolean', is_admin_returns_boolean,
  'is_admin_language_sql', is_admin_language_sql,
  'is_admin_stable', is_admin_stable,
  'is_admin_security_definer', is_admin_security_definer,
  'is_admin_owner', is_admin_owner,
  'is_admin_search_path_safe', is_admin_search_path_safe,
  'is_admin_public_execute', is_admin_public_execute,
  'is_admin_anon_execute', is_admin_anon_execute,
  'is_admin_authenticated_execute', is_admin_authenticated_execute,
  'is_admin_definition_matches_approved',
    is_admin_definition_matches_approved,
  'is_admin_uses_auth_uid', is_admin_uses_auth_uid,
  'is_admin_reads_schema_qualified_profiles',
    is_admin_reads_schema_qualified_profiles,
  'is_admin_requires_admin_role', is_admin_requires_admin_role,
  'is_admin_requires_active_status', is_admin_requires_active_status,
  'is_admin_has_no_unapproved_identity_source',
    is_admin_has_no_unapproved_identity_source,
  'decision', CASE
    WHEN preflight_passed THEN 'PREFLIGHT_PASSED'
    ELSE 'PREFLIGHT_BLOCKED'
  END,
  'blocking_reasons', to_jsonb(blocking_reasons)
) AS catalog_rls_preflight
FROM decision_state;

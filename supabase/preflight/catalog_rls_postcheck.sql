-- GoStay - Catalog RLS and Privilege Hardening postcheck
-- One read-only query; returns one JSON object and reads no business/user rows.

WITH
target_tables(table_name) AS (
  VALUES
    ('branches'),
    ('room_types'),
    ('rooms'),
    ('amenities'),
    ('room_images'),
    ('room_amenities'),
    ('promotions')
),
target_relations AS (
  SELECT
    target.table_name,
    class.oid AS relation_oid,
    class.relkind,
    class.relrowsecurity,
    class.relforcerowsecurity,
    class.relowner,
    class.relacl
  FROM target_tables AS target
  LEFT JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.nspname = 'public'
  LEFT JOIN pg_catalog.pg_class AS class
    ON class.relnamespace = namespace.oid
   AND class.relname = target.table_name
),
table_state AS (
  SELECT
    count(*) FILTER (
      WHERE relation_oid IS NOT NULL
        AND relkind IN ('r', 'p')
    ) = 7 AS all_tables_valid,
    coalesce(bool_and(
      relation_oid IS NOT NULL
      AND relkind IN ('r', 'p')
      AND relrowsecurity
    ), false) AS all_rls_enabled,
    coalesce(bool_and(
      relation_oid IS NOT NULL
      AND NOT relforcerowsecurity
    ), false) AS all_force_rls_disabled,
    jsonb_agg(
      jsonb_build_object(
        'table', table_name,
        'exists', relation_oid IS NOT NULL,
        'relkind', relkind,
        'rls_enabled', coalesce(relrowsecurity, false),
        'force_rls', coalesce(relforcerowsecurity, false)
      )
      ORDER BY table_name
    ) AS tables
  FROM target_relations
),
expected_policies(
  table_name,
  policy_name,
  command_code,
  expected_roles,
  canonical_using,
  canonical_with_check
) AS (
  VALUES
    (
      'branches',
      'branches_public_select',
      'r',
      ARRAY['anon', 'authenticated']::text[],
      $expr$((status)='active')$expr$,
      '<null>'
    ),
    (
      'branches',
      'branches_admin_all',
      '*',
      ARRAY['authenticated']::text[],
      'is_admin()',
      'is_admin()'
    ),
    (
      'room_types',
      'room_types_public_select',
      'r',
      ARRAY['anon', 'authenticated']::text[],
      'true',
      '<null>'
    ),
    (
      'room_types',
      'room_types_admin_all',
      '*',
      ARRAY['authenticated']::text[],
      'is_admin()',
      'is_admin()'
    ),
    (
      'rooms',
      'rooms_public_select',
      'r',
      ARRAY['anon', 'authenticated']::text[],
      $expr$(((status)='available')and(exists(select1frombranchesbranchwhere((branch.id=rooms.branch_id)and((branch.status)='active')))))$expr$,
      '<null>'
    ),
    (
      'rooms',
      'rooms_admin_all',
      '*',
      ARRAY['authenticated']::text[],
      'is_admin()',
      'is_admin()'
    ),
    (
      'amenities',
      'amenities_public_select',
      'r',
      ARRAY['anon', 'authenticated']::text[],
      $expr$((status)='active')$expr$,
      '<null>'
    ),
    (
      'amenities',
      'amenities_admin_all',
      '*',
      ARRAY['authenticated']::text[],
      'is_admin()',
      'is_admin()'
    ),
    (
      'room_images',
      'room_images_public_select',
      'r',
      ARRAY['anon', 'authenticated']::text[],
      $expr$(exists(select1fromroomsroomwhere((room.id=room_images.room_id)and((room.status)='available')and(exists(select1frombranchesbranchwhere((branch.id=room.branch_id)and((branch.status)='active'))))))$expr$,
      '<null>'
    ),
    (
      'room_images',
      'room_images_admin_all',
      '*',
      ARRAY['authenticated']::text[],
      'is_admin()',
      'is_admin()'
    ),
    (
      'room_amenities',
      'room_amenities_public_select',
      'r',
      ARRAY['anon', 'authenticated']::text[],
      $expr$((exists(select1fromroomsroomwhere((room.id=room_amenities.room_id)and((room.status)='available')and(exists(select1frombranchesbranchwhere((branch.id=room.branch_id)and((branch.status)='active'))))))and(exists(select1fromamenitiesamenitywhere((amenity.id=room_amenities.amenity_id)and((amenity.status)='active')))))$expr$,
      '<null>'
    ),
    (
      'room_amenities',
      'room_amenities_admin_all',
      '*',
      ARRAY['authenticated']::text[],
      'is_admin()',
      'is_admin()'
    ),
    (
      'promotions',
      'promotions_public_select',
      'r',
      ARRAY['anon', 'authenticated']::text[],
      $expr$(((status)='active')and(start_at<=now())and(end_at>now())and((usage_limitisnull)or(used_count<usage_limit)))$expr$,
      '<null>'
    ),
    (
      'promotions',
      'promotions_admin_all',
      '*',
      ARRAY['authenticated']::text[],
      'is_admin()',
      'is_admin()'
    )
),
policy_catalog AS (
  SELECT
    class.relname::text AS table_name,
    policy.polname::text AS policy_name,
    policy.polcmd::text AS command_code,
    policy.polpermissive,
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
    coalesce(
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
          'public[.]',
          '',
          'g'
        ),
        '::(text|charactervarying)',
        '',
        'g'
      ),
      '<null>'
    ) AS canonical_using,
    coalesce(
      pg_catalog.regexp_replace(
        pg_catalog.regexp_replace(
          pg_catalog.regexp_replace(
            pg_catalog.lower(
              pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
            ),
            '[[:space:]]+',
            '',
            'g'
          ),
          'public[.]',
          '',
          'g'
        ),
        '::(text|charactervarying)',
        '',
        'g'
      ),
      '<null>'
    ) AS canonical_with_check
  FROM pg_catalog.pg_policy AS policy
  JOIN pg_catalog.pg_class AS class
    ON class.oid = policy.polrelid
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = class.relnamespace
  WHERE namespace.nspname = 'public'
    AND class.relname IN (
      SELECT table_name FROM target_tables
    )
),
policy_state AS (
  SELECT
    (SELECT count(*) FROM policy_catalog) = 14 AS policy_count_ok,
    count(*) FILTER (
      WHERE actual.policy_name IS NOT NULL
        AND actual.command_code = expected.command_code
        AND actual.roles = expected.expected_roles
        AND actual.polpermissive
        AND actual.canonical_using = expected.canonical_using
        AND actual.canonical_with_check = expected.canonical_with_check
    ) = 14 AS all_policy_definitions_ok,
    (
      SELECT count(*)
      FROM policy_catalog AS actual_policy
      LEFT JOIN expected_policies AS expected_policy
        ON expected_policy.table_name = actual_policy.table_name
       AND expected_policy.policy_name = actual_policy.policy_name
      WHERE expected_policy.policy_name IS NULL
    ) AS unexpected_policy_count,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'table', expected.table_name,
          'policy_name', expected.policy_name,
          'valid',
            actual.policy_name IS NOT NULL
            AND actual.command_code = expected.command_code
            AND actual.roles = expected.expected_roles
            AND actual.polpermissive
            AND actual.canonical_using = expected.canonical_using
            AND actual.canonical_with_check = expected.canonical_with_check
        )
        ORDER BY expected.table_name, expected.policy_name
      ),
      '[]'::jsonb
    ) AS policies
  FROM expected_policies AS expected
  LEFT JOIN policy_catalog AS actual
    ON actual.table_name = expected.table_name
   AND actual.policy_name = expected.policy_name
),
privilege_types(privilege_type) AS (
  VALUES
    ('SELECT'),
    ('INSERT'),
    ('UPDATE'),
    ('DELETE'),
    ('TRUNCATE'),
    ('REFERENCES'),
    ('TRIGGER'),
    ('MAINTAIN')
),
table_privilege_state AS (
  SELECT
    coalesce(bool_and(
      CASE privilege.privilege_type
        WHEN 'SELECT' THEN
          pg_catalog.has_table_privilege(
            'anon', relation.relation_oid, privilege.privilege_type
          )
          AND pg_catalog.has_table_privilege(
            'authenticated', relation.relation_oid, privilege.privilege_type
          )
        WHEN 'INSERT' THEN
          NOT pg_catalog.has_table_privilege(
            'anon', relation.relation_oid, privilege.privilege_type
          )
          AND pg_catalog.has_table_privilege(
            'authenticated', relation.relation_oid, privilege.privilege_type
          )
        WHEN 'UPDATE' THEN
          NOT pg_catalog.has_table_privilege(
            'anon', relation.relation_oid, privilege.privilege_type
          )
          AND pg_catalog.has_table_privilege(
            'authenticated', relation.relation_oid, privilege.privilege_type
          )
        WHEN 'DELETE' THEN
          NOT pg_catalog.has_table_privilege(
            'anon', relation.relation_oid, privilege.privilege_type
          )
          AND pg_catalog.has_table_privilege(
            'authenticated', relation.relation_oid, privilege.privilege_type
          )
        ELSE
          NOT pg_catalog.has_table_privilege(
            'anon', relation.relation_oid, privilege.privilege_type
          )
          AND NOT pg_catalog.has_table_privilege(
            'authenticated', relation.relation_oid, privilege.privilege_type
          )
      END
    ), false) AS frontend_table_privileges_ok,
    coalesce(bool_and(
      NOT EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(
          coalesce(
            relation.relacl,
            pg_catalog.acldefault('r', relation.relowner)
          )
        ) AS acl
        WHERE acl.grantee = 0
          AND acl.privilege_type = privilege.privilege_type
      )
    ), false) AS public_has_no_table_privilege,
    jsonb_agg(
      jsonb_build_object(
        'table', relation.table_name,
        'privilege', privilege.privilege_type,
        'public', EXISTS (
          SELECT 1
          FROM pg_catalog.aclexplode(
            coalesce(
              relation.relacl,
              pg_catalog.acldefault('r', relation.relowner)
            )
          ) AS acl
          WHERE acl.grantee = 0
            AND acl.privilege_type = privilege.privilege_type
        ),
        'anon', pg_catalog.has_table_privilege(
          'anon', relation.relation_oid, privilege.privilege_type
        ),
        'authenticated', pg_catalog.has_table_privilege(
          'authenticated',
          relation.relation_oid,
          privilege.privilege_type
        )
      )
      ORDER BY relation.table_name, privilege.privilege_type
    ) AS table_privileges
  FROM target_relations AS relation
  CROSS JOIN privilege_types AS privilege
  WHERE relation.relation_oid IS NOT NULL
),
identity_sequences AS (
  SELECT
    table_class.relname::text AS owning_table,
    attribute.attname::text AS owning_column,
    CASE attribute.attidentity
      WHEN 'a' THEN 'ALWAYS'
      WHEN 'd' THEN 'BY DEFAULT'
      ELSE attribute.attidentity::text
    END AS generation_mode,
    sequence_namespace.nspname::text AS sequence_schema,
    sequence_class.relname::text AS sequence_name,
    sequence_class.oid AS sequence_oid,
    sequence_class.relowner,
    sequence_class.relacl
  FROM pg_catalog.pg_class AS table_class
  JOIN pg_catalog.pg_namespace AS table_namespace
    ON table_namespace.oid = table_class.relnamespace
  JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = table_class.oid
   AND attribute.attnum > 0
   AND NOT attribute.attisdropped
   AND attribute.attidentity IN ('a', 'd')
  JOIN pg_catalog.pg_depend AS dependency
    ON dependency.refobjid = table_class.oid
   AND dependency.refobjsubid = attribute.attnum
   AND dependency.deptype = 'i'
  JOIN pg_catalog.pg_class AS sequence_class
    ON sequence_class.oid = dependency.objid
   AND sequence_class.relkind = 'S'
  JOIN pg_catalog.pg_namespace AS sequence_namespace
    ON sequence_namespace.oid = sequence_class.relnamespace
  WHERE table_namespace.nspname = 'public'
    AND table_class.relname IN (
      SELECT table_name FROM target_tables
    )
),
expected_identity_mappings(
  owning_table,
  owning_column,
  generation_mode
) AS (
  VALUES
    ('amenities', 'id', 'ALWAYS'),
    ('branches', 'id', 'BY DEFAULT'),
    ('promotions', 'id', 'BY DEFAULT'),
    ('room_images', 'id', 'ALWAYS'),
    ('room_types', 'id', 'BY DEFAULT'),
    ('rooms', 'id', 'BY DEFAULT')
),
identity_mapping_state AS (
  SELECT
    (SELECT count(*) FROM identity_sequences) = 6
    AND count(*) FILTER (
      WHERE actual.sequence_oid IS NOT NULL
    ) = 6 AS identity_mappings_ok,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'owning_table', expected.owning_table,
          'owning_column', expected.owning_column,
          'expected_generation_mode', expected.generation_mode,
          'actual_generation_mode', actual.generation_mode,
          'sequence_schema', actual.sequence_schema,
          'sequence_name', actual.sequence_name,
          'valid',
            actual.sequence_oid IS NOT NULL
            AND actual.generation_mode = expected.generation_mode
        )
        ORDER BY expected.owning_table, expected.owning_column
      ),
      '[]'::jsonb
    ) AS identity_mappings
  FROM expected_identity_mappings AS expected
  LEFT JOIN identity_sequences AS actual
    ON actual.owning_table = expected.owning_table
   AND actual.owning_column = expected.owning_column
   AND actual.generation_mode = expected.generation_mode
),
sequence_state AS (
  SELECT
    count(*) = 6 AS identity_sequence_count_ok,
    coalesce(bool_and(
      NOT EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(
          coalesce(
            sequence.relacl,
            pg_catalog.acldefault('S', sequence.relowner)
          )
        ) AS acl
        WHERE acl.grantee = 0
      )
      AND NOT pg_catalog.has_sequence_privilege(
        'anon', sequence.sequence_oid, 'USAGE'
      )
      AND NOT pg_catalog.has_sequence_privilege(
        'anon', sequence.sequence_oid, 'SELECT'
      )
      AND NOT pg_catalog.has_sequence_privilege(
        'anon', sequence.sequence_oid, 'UPDATE'
      )
      AND pg_catalog.has_sequence_privilege(
        'authenticated', sequence.sequence_oid, 'USAGE'
      )
      AND NOT pg_catalog.has_sequence_privilege(
        'authenticated', sequence.sequence_oid, 'SELECT'
      )
      AND NOT pg_catalog.has_sequence_privilege(
        'authenticated', sequence.sequence_oid, 'UPDATE'
      )
    ), false) AS sequence_privileges_ok,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'owning_table', sequence.owning_table,
          'owning_column', sequence.owning_column,
          'generation_mode', sequence.generation_mode,
          'sequence_schema', sequence.sequence_schema,
          'sequence_name', sequence.sequence_name,
          'public_has_privilege', EXISTS (
            SELECT 1
            FROM pg_catalog.aclexplode(
              coalesce(
                sequence.relacl,
                pg_catalog.acldefault('S', sequence.relowner)
              )
            ) AS acl
            WHERE acl.grantee = 0
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
        ORDER BY
          sequence.owning_table,
          sequence.owning_column,
          sequence.sequence_schema,
          sequence.sequence_name
      ),
      '[]'::jsonb
    ) AS sequences
  FROM identity_sequences AS sequence
),
is_admin_catalog AS (
  SELECT
    p.oid,
    p.proowner,
    p.prosecdef,
    p.proconfig,
    p.proacl,
    p.prorettype,
    p.provolatile,
    language.lanname::text AS language_name,
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
foundation_state AS (
  SELECT
    count(*) = 1
    AND coalesce(bool_and(
      prorettype = 'boolean'::regtype
      AND language_name = 'sql'
      AND provolatile = 's'
      AND prosecdef
      AND pg_catalog.pg_get_userbyid(proowner) = 'postgres'
      AND normalized_body =
        $approved$selectcoalesce(exists(select1frompublic.profilesaspwherep.id=auth.uid()andp.role='admin'andp.status='active'),false)$approved$
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.unnest(proconfig) AS config(setting)
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
          coalesce(proacl, pg_catalog.acldefault('f', proowner))
        ) AS acl
        WHERE acl.grantee = 0
          AND acl.privilege_type = 'EXECUTE'
      )
      AND NOT pg_catalog.has_function_privilege('anon', oid, 'EXECUTE')
      AND pg_catalog.has_function_privilege(
        'authenticated', oid, 'EXECUTE'
      )
    ), false) AS is_admin_foundation_ok
  FROM is_admin_catalog
),
checks AS (
  SELECT *
  FROM table_state
  CROSS JOIN policy_state
  CROSS JOIN table_privilege_state
  CROSS JOIN identity_mapping_state
  CROSS JOIN sequence_state
  CROSS JOIN foundation_state
),
decision_state AS (
  SELECT
    checks.*,
    (
      all_tables_valid
      AND all_rls_enabled
      AND all_force_rls_disabled
      AND policy_count_ok
      AND all_policy_definitions_ok
      AND unexpected_policy_count = 0
      AND frontend_table_privileges_ok
      AND public_has_no_table_privilege
      AND identity_mappings_ok
      AND identity_sequence_count_ok
      AND sequence_privileges_ok
      AND is_admin_foundation_ok
    ) AS postcheck_passed,
    array_remove(ARRAY[
      CASE WHEN NOT all_tables_valid THEN 'TARGET_TABLE_INVALID' END,
      CASE WHEN NOT all_rls_enabled THEN 'TARGET_RLS_DISABLED' END,
      CASE WHEN NOT all_force_rls_disabled THEN 'TARGET_FORCE_RLS_ENABLED' END,
      CASE WHEN NOT policy_count_ok THEN 'POLICY_COUNT_INVALID' END,
      CASE WHEN NOT all_policy_definitions_ok THEN 'POLICY_DEFINITION_INVALID' END,
      CASE WHEN unexpected_policy_count <> 0 THEN 'UNEXPECTED_POLICY_EXISTS' END,
      CASE WHEN NOT frontend_table_privileges_ok THEN 'FRONTEND_TABLE_PRIVILEGES_INVALID' END,
      CASE WHEN NOT public_has_no_table_privilege THEN 'PUBLIC_TABLE_PRIVILEGE_PRESENT' END,
      CASE WHEN NOT identity_mappings_ok THEN 'IDENTITY_MAPPING_INVALID' END,
      CASE WHEN NOT identity_sequence_count_ok THEN 'IDENTITY_SEQUENCE_COUNT_INVALID' END,
      CASE WHEN NOT sequence_privileges_ok THEN 'IDENTITY_SEQUENCE_PRIVILEGES_INVALID' END,
      CASE WHEN NOT is_admin_foundation_ok THEN 'IS_ADMIN_FOUNDATION_INVALID' END
    ], NULL) AS blocking_reasons
  FROM checks
)
SELECT jsonb_build_object(
  'all_tables_valid', all_tables_valid,
  'all_rls_enabled', all_rls_enabled,
  'all_force_rls_disabled', all_force_rls_disabled,
  'tables', tables,
  'policy_count_ok', policy_count_ok,
  'all_policy_definitions_ok', all_policy_definitions_ok,
  'unexpected_policy_count', unexpected_policy_count,
  'policies', policies,
  'frontend_table_privileges_ok', frontend_table_privileges_ok,
  'public_has_no_table_privilege', public_has_no_table_privilege,
  'table_privileges', table_privileges,
  'identity_mappings_ok', identity_mappings_ok,
  'identity_mappings', identity_mappings,
  'identity_sequence_count_ok', identity_sequence_count_ok,
  'sequence_privileges_ok', sequence_privileges_ok,
  'sequences', sequences,
  'is_admin_foundation_ok', is_admin_foundation_ok,
  'decision', CASE
    WHEN postcheck_passed THEN 'POSTCHECK_PASSED'
    ELSE 'POSTCHECK_BLOCKED'
  END,
  'blocking_reasons', to_jsonb(blocking_reasons)
) AS catalog_rls_postcheck
FROM decision_state;

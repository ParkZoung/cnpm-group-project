/*
 * GoStay Booking Security Foundation — read-only postcheck
 *
 * Safety:
 * - This file is one WITH ... SELECT statement.
 * - It reads PostgreSQL catalogs and aggregate counts only.
 * - It returns no booking, profile, Auth-user, or guest-identifying rows.
 * - Guarded query_to_xml() calls prevent missing schema objects from causing
 *   parse-time failures in the aggregate data-quality inspection.
 */
WITH
roles AS (
  SELECT expected.role_name, role_value.oid AS role_oid
  FROM (
    VALUES
      ('PUBLIC'::text),
      ('anon'::text),
      ('authenticated'::text),
      ('service_role'::text)
  ) AS expected(role_name)
  LEFT JOIN pg_catalog.pg_roles AS role_value
    ON role_value.rolname::text = expected.role_name
),
booking_relation AS (
  SELECT
    class.oid AS relation_oid,
    class.relkind::text AS relation_kind,
    class.relrowsecurity AS rls_enabled,
    class.relforcerowsecurity AS force_rls,
    pg_catalog.pg_get_userbyid(class.relowner)::text AS owner
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
      AS table_exists,
    max(relation_oid) FILTER (WHERE relation_kind IN ('r', 'p'))
      AS relation_oid,
    coalesce(bool_or(rls_enabled), false) AS rls_enabled,
    coalesce(bool_or(force_rls), false) AS force_rls,
    max(owner) AS owner,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'relation_kind', relation_kind,
          'rls_enabled', rls_enabled,
          'force_rls', force_rls,
          'owner', owner
        )
      ),
      '[]'::jsonb
    ) AS relations
  FROM booking_relation
),
column_catalog AS (
  SELECT
    attribute.attname::text AS column_name,
    attribute.atttypid AS type_oid,
    attribute.attnotnull AS not_null
  FROM relation_state AS relation
  JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = relation.relation_oid
  WHERE attribute.attnum > 0
    AND NOT attribute.attisdropped
),
column_state AS (
  SELECT
    coalesce(bool_or(
      column_name = 'user_id'
      AND type_oid = 'uuid'::regtype
      AND not_null
    ), false) AS user_id_not_null,
    count(*) FILTER (
      WHERE (column_name, type_oid) IN (
        ('user_id', 'uuid'::regtype),
        ('room_id', 'bigint'::regtype),
        ('check_in_date', 'date'::regtype),
        ('check_out_date', 'date'::regtype),
        ('number_of_nights', 'integer'::regtype),
        ('number_of_guests', 'integer'::regtype),
        ('price_per_night', 'bigint'::regtype),
        ('subtotal', 'bigint'::regtype),
        ('tax_rate', 'numeric'::regtype),
        ('tax_amount', 'bigint'::regtype),
        ('discount_amount', 'bigint'::regtype),
        ('total_amount', 'bigint'::regtype),
        ('booking_status', 'character varying'::regtype),
        ('payment_method', 'character varying'::regtype),
        ('payment_status', 'character varying'::regtype),
        ('cancelled_at', 'timestamp with time zone'::regtype)
      )
    ) = 16 AS data_columns_safe
  FROM column_catalog
),
constraint_catalog AS (
  SELECT
    con.oid AS constraint_oid,
    con.conname::text AS constraint_name,
    con.contype::text AS constraint_type,
    con.convalidated AS validated,
    con.confrelid,
    con.confupdtype::text AS update_action,
    con.confdeltype::text AS delete_action,
    (
      SELECT array_agg(attribute.attname::text ORDER BY attribute.attname::text)
      FROM pg_catalog.unnest(con.conkey) AS key_value(attnum)
      JOIN pg_catalog.pg_attribute AS attribute
        ON attribute.attrelid = con.conrelid
       AND attribute.attnum = key_value.attnum
    ) AS referenced_columns,
    (
      SELECT array_agg(DISTINCT operator_value.oprname::text
        ORDER BY operator_value.oprname::text)
      FROM pg_catalog.regexp_matches(
        con.conbin::text,
        ':opno ([0-9]+)',
        'g'
      ) AS operator_match(value)
      JOIN pg_catalog.pg_operator AS operator_value
        ON operator_value.oid = operator_match.value[1]::oid
    ) AS referenced_operators,
    pg_catalog.pg_get_constraintdef(con.oid, true)::text
      AS constraint_definition,
    pg_catalog.regexp_replace(
      pg_catalog.lower(pg_catalog.pg_get_constraintdef(con.oid, true)),
      '[[:space:]]+',
      '',
      'g'
    ) AS normalized_definition
  FROM relation_state AS relation
  JOIN pg_catalog.pg_constraint AS con
    ON con.conrelid = relation.relation_oid
),
ownership_fk_state AS (
  SELECT
    count(con.oid) = 1
    AND coalesce(bool_and(
      con.contype = 'f'
      AND con.convalidated
      AND con.confrelid = pg_catalog.to_regclass('public.profiles')
      AND con.confupdtype = 'c'
      AND con.confdeltype = 'r'
      AND (
        SELECT array_agg(attribute.attname::text ORDER BY key_value.ordinality)
        FROM pg_catalog.unnest(con.conkey)
          WITH ORDINALITY AS key_value(attnum, ordinality)
        JOIN pg_catalog.pg_attribute AS attribute
          ON attribute.attrelid = con.conrelid
         AND attribute.attnum = key_value.attnum
      ) = ARRAY['user_id']::text[]
      AND (
        SELECT array_agg(attribute.attname::text ORDER BY key_value.ordinality)
        FROM pg_catalog.unnest(con.confkey)
          WITH ORDINALITY AS key_value(attnum, ordinality)
        JOIN pg_catalog.pg_attribute AS attribute
          ON attribute.attrelid = con.confrelid
         AND attribute.attnum = key_value.attnum
      ) = ARRAY['id']::text[]
    ), false) AS ownership_fk_valid,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'name', con.conname::text,
          'validated', con.convalidated,
          'definition', pg_catalog.pg_get_constraintdef(con.oid, true),
          'on_update_code', con.confupdtype::text,
          'on_delete_code', con.confdeltype::text
        )
      ) FILTER (WHERE con.oid IS NOT NULL),
      '[]'::jsonb
    ) AS ownership_foreign_keys
  FROM relation_state AS relation
  LEFT JOIN pg_catalog.pg_constraint AS con
    ON con.conrelid = relation.relation_oid
   AND con.conname = 'bookings_user_id_fkey'
  GROUP BY relation.relation_oid
),
named_constraint_state AS (
  SELECT
    count(*) FILTER (
      WHERE constraint_name IN (
        'bookings_valid_date_range',
        'bookings_number_of_nights_matches_dates',
        'chk_booking_subtotal',
        'chk_booking_total'
      )
      AND constraint_type = 'c'
      AND validated
    ) = 4 AS reviewed_named_constraints_valid,
    count(*) FILTER (
      WHERE constraint_name IN (
        'bookings_stage1_tax_rate',
        'bookings_tax_amount_consistent',
        'bookings_discount_upper_bound',
        'bookings_cancellation_consistent'
      )
      AND constraint_type = 'c'
      AND validated
    ) = 4 AS new_check_constraints_present,
    coalesce(bool_or(
      constraint_name = 'bookings_stage1_tax_rate'
      AND constraint_type = 'c'
      AND validated
      AND referenced_columns = ARRAY['tax_rate']::text[]
      AND referenced_operators @> ARRAY['=']::text[]
      AND normalized_definition ~
        E'^check\\(+tax_rate=\\(*10(::numeric)?\\)*\\)+$'
    ), false) AS tax_rate_constraint_valid,
    coalesce(bool_or(
      constraint_name = 'bookings_tax_amount_consistent'
      AND constraint_type = 'c'
      AND validated
      AND referenced_columns =
        ARRAY['subtotal', 'tax_amount', 'tax_rate']::text[]
      AND referenced_operators @> ARRAY['*', '/', '=']::text[]
      AND normalized_definition ~
        E'^check\\(+tax_amount=\\(*round\\(.*subtotal.*tax_rate.*100.*\\)::bigint\\)*\\)+$'
    ), false) AS tax_amount_constraint_valid,
    coalesce(bool_or(
      constraint_name = 'bookings_discount_upper_bound'
      AND constraint_type = 'c'
      AND validated
      AND referenced_columns =
        ARRAY['discount_amount', 'subtotal', 'tax_amount']::text[]
      AND referenced_operators @> ARRAY['+', '<=']::text[]
      AND normalized_definition ~
        E'^check\\(+discount_amount<=\\(*subtotal\\+tax_amount\\)*\\)+$'
    ), false) AS discount_constraint_valid,
    coalesce(bool_or(
      constraint_name = 'bookings_cancellation_consistent'
      AND constraint_type = 'c'
      AND validated
      AND referenced_columns =
        ARRAY['booking_status', 'cancelled_at']::text[]
      AND referenced_operators @> ARRAY['=']::text[]
      AND pg_catalog.regexp_replace(
        pg_catalog.regexp_replace(
          normalized_definition,
          '::((pg_catalog\.)?charactervarying|(pg_catalog\.)?text)',
          '',
          'g'
        ),
        '[()]',
        '',
        'g'
      ) = 'checkbooking_status=''cancelled''=cancelled_atisnotnull'
    ), false) AS cancellation_constraint_valid,
    coalesce(bool_or(
      constraint_type = 'c'
      AND validated
      AND normalized_definition LIKE '%booking_status%'
      AND normalized_definition LIKE '%pending%'
      AND normalized_definition LIKE '%confirmed%'
      AND normalized_definition LIKE '%checked_in%'
      AND normalized_definition LIKE '%completed%'
      AND normalized_definition LIKE '%cancelled%'
    ), false) AS booking_status_allowlist_valid,
    coalesce(bool_or(
      constraint_type = 'c'
      AND validated
      AND normalized_definition LIKE '%payment_status%'
      AND normalized_definition LIKE '%unpaid%'
      AND normalized_definition LIKE '%pending%'
      AND normalized_definition LIKE '%paid%'
      AND normalized_definition LIKE '%failed%'
      AND normalized_definition LIKE '%refunded%'
    ), false) AS payment_status_allowlist_valid,
    coalesce(bool_or(
      constraint_type = 'c'
      AND validated
      AND normalized_definition LIKE '%payment_method%'
      AND normalized_definition LIKE '%pay_at_hotel%'
      AND normalized_definition LIKE '%online%'
      AND normalized_definition LIKE '%bank_transfer%'
    ), false) AS payment_method_allowlist_valid,
    coalesce(bool_or(
      constraint_type = 'c'
      AND validated
      AND normalized_definition LIKE '%number_of_guests%'
    ), false) AS guest_check_valid,
    coalesce(bool_or(
      constraint_type = 'c'
      AND validated
      AND (
        normalized_definition LIKE '%price_per_night%'
        OR normalized_definition LIKE '%subtotal%'
        OR normalized_definition LIKE '%tax_amount%'
        OR normalized_definition LIKE '%discount_amount%'
        OR normalized_definition LIKE '%total_amount%'
      )
    ), false) AS monetary_checks_valid,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'name', constraint_name,
          'type', constraint_type,
          'validated', validated,
          'referenced_columns', referenced_columns,
          'referenced_operators', referenced_operators,
          'definition', constraint_definition
        )
        ORDER BY constraint_name
      ),
      '[]'::jsonb
    ) AS constraints
  FROM constraint_catalog
),
exclusion_state AS (
  SELECT
    count(*) = 1 AS exactly_one,
    coalesce(bool_and(
      constraint_type = 'x'
      AND validated
      AND normalized_definition LIKE 'excludeusinggist%'
      AND normalized_definition LIKE '%room_idwith=%'
      AND normalized_definition LIKE
        '%daterange(check_in_date,check_out_date,''[)''::text)%with&&%'
      AND normalized_definition LIKE '%where%'
      AND normalized_definition LIKE '%booking_status%'
      AND normalized_definition LIKE '%pending%'
      AND normalized_definition LIKE '%confirmed%'
      AND normalized_definition LIKE '%checked_in%'
      AND normalized_definition NOT LIKE '%completed%'
      AND normalized_definition NOT LIKE '%cancelled%'
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint AS exclusion_con
        JOIN pg_catalog.pg_index AS exclusion_index
          ON exclusion_index.indexrelid = exclusion_con.conindid
        JOIN LATERAL pg_catalog.unnest(exclusion_index.indclass::oid[])
          AS index_opclass(opclass_oid) ON true
        JOIN pg_catalog.pg_opclass AS operator_class
          ON operator_class.oid = index_opclass.opclass_oid
        JOIN pg_catalog.pg_namespace AS namespace
          ON namespace.oid = operator_class.opcnamespace
        WHERE exclusion_con.oid = constraint_oid
          AND namespace.nspname = 'extensions'
          AND operator_class.opcname = 'gist_int8_ops'
          AND operator_class.opcintype = 'bigint'::regtype
      )
    ), false) AS definition_valid,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'name', constraint_name,
          'type', constraint_type,
          'validated', validated,
          'definition', constraint_definition,
          'cancelled_holds_room',
            normalized_definition LIKE '%cancelled%',
          'completed_holds_room',
            normalized_definition LIKE '%completed%'
        )
      ) FILTER (WHERE constraint_oid IS NOT NULL),
      '[]'::jsonb
    ) AS exclusion_constraints
  FROM constraint_catalog
  WHERE constraint_name = 'bookings_no_holding_overlap'
),
extension_state AS (
  SELECT
    count(*) FILTER (
      WHERE extension_value.extname = 'btree_gist'
        AND namespace.nspname = 'extensions'
    ) = 1 AS btree_gist_in_extensions,
    max(extension_value.extversion)
      FILTER (WHERE extension_value.extname = 'btree_gist') AS version,
    max(namespace.nspname::text)
      FILTER (WHERE extension_value.extname = 'btree_gist') AS schema_name
  FROM pg_catalog.pg_extension AS extension_value
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = extension_value.extnamespace
),
opclass_state AS (
  SELECT
    count(*) FILTER (
      WHERE namespace.nspname = 'extensions'
        AND operator_class.opcname = 'gist_int8_ops'
        AND operator_class.opcintype = 'bigint'::regtype
        AND access_method.amname = 'gist'
        AND operator_member.amopstrategy = 3
        AND operator_value.oprname = '='
    ) > 0 AS bigint_gist_equality_available,
    coalesce(
      jsonb_agg(DISTINCT jsonb_build_object(
        'schema', namespace.nspname,
        'name', operator_class.opcname,
        'input_type', pg_catalog.format_type(
          operator_class.opcintype, NULL
        ),
        'access_method', access_method.amname,
        'equality_operator', operator_value.oprname
      )) FILTER (
        WHERE namespace.nspname = 'extensions'
          AND operator_class.opcname = 'gist_int8_ops'
      ),
      '[]'::jsonb
    ) AS bigint_gist_opclasses
  FROM pg_catalog.pg_opclass AS operator_class
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = operator_class.opcnamespace
  JOIN pg_catalog.pg_am AS access_method
    ON access_method.oid = operator_class.opcmethod
  LEFT JOIN pg_catalog.pg_amop AS operator_member
    ON operator_member.amopfamily = operator_class.opcfamily
   AND operator_member.amoplefttype = operator_class.opcintype
   AND operator_member.amoprighttype = operator_class.opcintype
  LEFT JOIN pg_catalog.pg_operator AS operator_value
    ON operator_value.oid = operator_member.amopopr
),
index_catalog AS (
  SELECT
    index_class.relname::text AS index_name,
    index_value.indisvalid AS valid,
    index_value.indisready AS ready,
    pg_catalog.pg_get_indexdef(index_value.indexrelid)::text AS definition,
    pg_catalog.regexp_replace(
      pg_catalog.lower(pg_catalog.pg_get_indexdef(index_value.indexrelid)),
      '[[:space:]]+',
      '',
      'g'
    ) AS normalized_definition
  FROM relation_state AS relation
  JOIN pg_catalog.pg_index AS index_value
    ON index_value.indrelid = relation.relation_oid
  JOIN pg_catalog.pg_class AS index_class
    ON index_class.oid = index_value.indexrelid
),
index_state AS (
  SELECT
    coalesce(bool_or(
      index_name = 'bookings_user_created_at_idx'
      AND valid AND ready
      AND normalized_definition LIKE
        '%usingbtree(user_id,created_atdesc)%'
    ), false) AS user_created_index_valid,
    coalesce(bool_or(
      index_name = 'bookings_payment_status_created_at_idx'
      AND valid AND ready
      AND normalized_definition LIKE
        '%usingbtree(payment_status,created_atdesc)%'
    ), false) AS payment_created_index_valid,
    count(*) FILTER (
      WHERE index_name IN (
        'idx_bookings_room_dates',
        'idx_bookings_status',
        'idx_bookings_user_id'
      )
      AND valid
      AND ready
    ) = 3 AS reviewed_indexes_preserved,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'name', index_name,
          'valid', valid,
          'ready', ready,
          'definition', definition
        )
        ORDER BY index_name
      ),
      '[]'::jsonb
    ) AS indexes
  FROM index_catalog
),
policy_catalog AS (
  SELECT
    policy.oid AS policy_oid,
    policy.polrelid AS relation_oid,
    policy.polname::text AS policy_name,
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
      SELECT array_agg(role_name ORDER BY role_name)::text[]
      FROM (
        SELECT CASE role_oid
          WHEN 0 THEN 'PUBLIC'::text
          ELSE pg_catalog.pg_get_userbyid(role_oid)::text
        END AS role_name
        FROM pg_catalog.unnest(policy.polroles) AS role_value(role_oid)
      ) AS normalized_roles
    ) AS roles,
    pg_catalog.pg_get_expr(policy.polqual, policy.polrelid, true)::text
      AS using_expression,
    pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid, true)::text
      AS check_expression,
    pg_catalog.regexp_replace(
      pg_catalog.lower(
        pg_catalog.pg_get_expr(policy.polqual, policy.polrelid, true)
      ),
      '[[:space:]]+',
      '',
      'g'
    ) AS normalized_using,
    EXISTS (
      SELECT 1
      FROM pg_catalog.regexp_matches(
        policy.polqual::text,
        ':opno ([0-9]+)',
        'g'
      ) AS operator_match(value)
      JOIN pg_catalog.pg_operator AS operator_value
        ON operator_value.oid = operator_match.value[1]::oid
      WHERE operator_value.oprname = '='
    ) AS uses_equality
  FROM relation_state AS relation
  JOIN pg_catalog.pg_policy AS policy
    ON policy.polrelid = relation.relation_oid
),
policy_state AS (
  SELECT
    count(*) = 2 AS exact_policy_count,
    count(*) FILTER (
      WHERE policy_name = 'bookings_select_own'
        AND command = 'SELECT'
        AND permissive
        AND roles = ARRAY['authenticated']::text[]
        AND check_expression IS NULL
        AND EXISTS (
          SELECT 1
          FROM pg_catalog.pg_depend AS dependency
          WHERE dependency.classid = 'pg_catalog.pg_policy'::regclass
            AND dependency.objid = policy_oid
            AND dependency.refclassid = 'pg_catalog.pg_proc'::regclass
            AND dependency.refobjid =
              'auth.uid()'::regprocedure::oid
        )
        AND EXISTS (
          SELECT 1
          FROM pg_catalog.pg_depend AS dependency
          JOIN pg_catalog.pg_attribute AS attribute
            ON attribute.attrelid = dependency.refobjid
           AND attribute.attnum = dependency.refobjsubid
          WHERE dependency.classid = 'pg_catalog.pg_policy'::regclass
            AND dependency.objid = policy_oid
            AND dependency.refclassid = 'pg_catalog.pg_class'::regclass
            AND dependency.refobjid = relation_oid
            AND attribute.attname = 'user_id'
        )
        AND uses_equality
        AND pg_catalog.regexp_replace(
          pg_catalog.regexp_replace(
            pg_catalog.regexp_replace(
              normalized_using,
              '::((pg_catalog\.)?uuid|(pg_catalog\.)?text)',
              '',
              'g'
            ),
            '(public\.)?bookings\.',
            '',
            'g'
          ),
          '[()]',
          '',
          'g'
        ) = 'user_id=auth.uid'
    ) = 1 AS own_policy_valid,
    count(*) FILTER (
      WHERE policy_name = 'bookings_select_admin'
        AND command = 'SELECT'
        AND permissive
        AND roles = ARRAY['authenticated']::text[]
        AND check_expression IS NULL
        AND EXISTS (
          SELECT 1
          FROM pg_catalog.pg_depend AS dependency
          WHERE dependency.classid = 'pg_catalog.pg_policy'::regclass
            AND dependency.objid = policy_oid
            AND dependency.refclassid = 'pg_catalog.pg_proc'::regclass
            AND dependency.refobjid =
              'public.is_admin()'::regprocedure::oid
        )
        AND normalized_using IN (
          'is_admin()',
          '(is_admin())',
          'public.is_admin()',
          '(public.is_admin())'
        )
    ) = 1 AS admin_policy_valid,
    count(*) FILTER (
      WHERE policy_name NOT IN (
        'bookings_select_own',
        'bookings_select_admin'
      )
    ) AS unexpected_policy_count,
    count(*) FILTER (
      WHERE command IN ('INSERT', 'UPDATE', 'DELETE', 'ALL')
    ) AS write_policy_count,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'name', policy_name,
          'command', command,
          'permissive', permissive,
          'roles', to_jsonb(roles),
          'using', using_expression,
          'with_check', check_expression
        )
        ORDER BY policy_name
      ),
      '[]'::jsonb
    ) AS policies
  FROM policy_catalog
),
table_privileges AS (
  SELECT
    role_value.role_name,
    role_value.role_oid IS NOT NULL OR role_value.role_name = 'PUBLIC'
      AS role_exists,
    privilege.privilege_name,
    CASE
      WHEN role_value.role_name = 'PUBLIC' THEN EXISTS (
        SELECT 1
        FROM booking_relation AS relation
        CROSS JOIN LATERAL pg_catalog.aclexplode(
          coalesce(
            (
              SELECT class.relacl
              FROM pg_catalog.pg_class AS class
              WHERE class.oid = relation.relation_oid
            ),
            pg_catalog.acldefault(
              'r',
              (
                SELECT class.relowner
                FROM pg_catalog.pg_class AS class
                WHERE class.oid = relation.relation_oid
              )
            )
          )
        ) AS acl
        WHERE acl.grantee = 0
          AND acl.privilege_type::text = privilege.privilege_name
      )
      WHEN privilege.privilege_name = 'MAINTAIN' THEN EXISTS (
        SELECT 1
        FROM booking_relation AS relation
        CROSS JOIN LATERAL pg_catalog.aclexplode(
          coalesce(
            (
              SELECT class.relacl
              FROM pg_catalog.pg_class AS class
              WHERE class.oid = relation.relation_oid
            ),
            pg_catalog.acldefault(
              'r',
              (
                SELECT class.relowner
                FROM pg_catalog.pg_class AS class
                WHERE class.oid = relation.relation_oid
              )
            )
          )
        ) AS acl
        WHERE acl.privilege_type::text = 'MAINTAIN'
          AND (
            acl.grantee = 0
            OR acl.grantee = role_value.role_oid
            OR (
              role_value.role_oid IS NOT NULL
              AND acl.grantee <> 0
              AND pg_catalog.pg_has_role(
                role_value.role_oid,
                acl.grantee,
                'USAGE'
              )
            )
          )
      )
      WHEN role_value.role_oid IS NULL THEN false
      ELSE coalesce(pg_catalog.has_table_privilege(
        role_value.role_oid,
        relation.relation_oid,
        privilege.privilege_name
      ), false)
    END AS effective
  FROM roles AS role_value
  CROSS JOIN (
    VALUES
      ('SELECT'::text), ('INSERT'::text), ('UPDATE'::text),
      ('DELETE'::text), ('TRUNCATE'::text), ('REFERENCES'::text),
      ('TRIGGER'::text), ('MAINTAIN'::text)
  ) AS privilege(privilege_name)
  CROSS JOIN relation_state AS relation
),
column_privileges AS (
  SELECT
    role_value.role_name,
    attribute.attname::text AS column_name,
    acl.privilege_type::text AS privilege_name,
    acl.is_grantable
  FROM relation_state AS relation
  JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = relation.relation_oid
   AND attribute.attnum > 0
   AND NOT attribute.attisdropped
  CROSS JOIN LATERAL pg_catalog.aclexplode(attribute.attacl) AS acl
  JOIN roles AS role_value
    ON (
      (role_value.role_name = 'PUBLIC' AND acl.grantee = 0)
      OR role_value.role_oid = acl.grantee
    )
),
privilege_state AS (
  SELECT
    NOT EXISTS (
      SELECT 1 FROM table_privileges
      WHERE role_name = 'PUBLIC' AND effective
    ) AS public_none,
    NOT EXISTS (
      SELECT 1 FROM table_privileges
      WHERE role_name = 'anon' AND effective
    ) AS anon_none,
    (
      EXISTS (
        SELECT 1 FROM table_privileges
        WHERE role_name = 'authenticated'
          AND privilege_name = 'SELECT'
          AND effective
      )
      AND NOT EXISTS (
        SELECT 1 FROM table_privileges
        WHERE role_name = 'authenticated'
          AND privilege_name <> 'SELECT'
          AND effective
      )
    ) AS authenticated_select_only,
    NOT EXISTS (
      SELECT 1
      FROM column_privileges
      WHERE role_name IN ('PUBLIC', 'anon', 'authenticated')
    ) AS no_frontend_column_grants,
    coalesce(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'role', role_name,
            'role_exists', role_exists,
            'privilege', privilege_name,
            'effective', effective
          )
          ORDER BY role_name, privilege_name
        )
        FROM table_privileges
      ),
      '[]'::jsonb
    ) AS table_privilege_report,
    coalesce(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'role', role_name,
            'column', column_name,
            'privilege', privilege_name,
            'grantable', is_grantable
          )
          ORDER BY role_name, column_name, privilege_name
        )
        FROM column_privileges
      ),
      '[]'::jsonb
    ) AS column_privilege_report
),
expected_rpcs(
  function_name,
  identity_arguments,
  return_type,
  returns_set,
  all_argument_types,
  argument_modes,
  argument_names,
  function_result,
  approved_body_hash
) AS (
  VALUES
    (
      'create_booking'::text,
      'bigint, date, date, integer, text, text, text, text'::text,
      'record'::regtype::oid,
      true,
      ARRAY[
        'bigint'::regtype::oid, 'date'::regtype::oid,
        'date'::regtype::oid, 'integer'::regtype::oid,
        'text'::regtype::oid, 'text'::regtype::oid,
        'text'::regtype::oid, 'text'::regtype::oid,
        'uuid'::regtype::oid, 'character varying'::regtype::oid,
        'character varying'::regtype::oid,
        'character varying'::regtype::oid, 'bigint'::regtype::oid,
        'timestamp with time zone'::regtype::oid
      ]::oid[],
      ARRAY[
        'i', 'i', 'i', 'i', 'i', 'i', 'i', 'i',
        't', 't', 't', 't', 't', 't'
      ]::text[],
      ARRAY[
        'p_room_id', 'p_check_in_date', 'p_check_out_date',
        'p_number_of_guests', 'p_guest_name', 'p_guest_email',
        'p_guest_phone', 'p_special_request', 'booking_id',
        'booking_code', 'booking_status', 'payment_status',
        'total_amount', 'created_at'
      ]::text[],
      'TABLE(booking_id uuid, booking_code character varying, booking_status character varying, payment_status character varying, total_amount bigint, created_at timestamp with time zone)'::text,
      '174386950d2b4e0d1f16f4c896a6cbf3'::text
    ),
    (
      'cancel_own_booking',
      'uuid',
      'record'::regtype::oid,
      true,
      ARRAY[
        'uuid'::regtype::oid, 'uuid'::regtype::oid,
        'character varying'::regtype::oid,
        'timestamp with time zone'::regtype::oid
      ]::oid[],
      ARRAY['i', 't', 't', 't']::text[],
      ARRAY[
        'p_booking_id', 'booking_id', 'booking_status', 'cancelled_at'
      ]::text[],
      'TABLE(booking_id uuid, booking_status character varying, cancelled_at timestamp with time zone)'::text,
      '09e3a70d3ba2fb1caa3204b924d13f46'
    ),
    (
      'admin_update_booking_status',
      'uuid, character varying',
      'record'::regtype::oid,
      true,
      ARRAY[
        'uuid'::regtype::oid, 'character varying'::regtype::oid,
        'uuid'::regtype::oid, 'character varying'::regtype::oid,
        'character varying'::regtype::oid,
        'timestamp with time zone'::regtype::oid
      ]::oid[],
      ARRAY['i', 'i', 't', 't', 't', 't']::text[],
      ARRAY[
        'p_booking_id', 'p_new_status', 'booking_id', 'old_status',
        'new_status', 'updated_at'
      ]::text[],
      'TABLE(booking_id uuid, old_status character varying, new_status character varying, updated_at timestamp with time zone)'::text,
      '90fc7c0223d47cf4259cb3b731acba81'
    ),
    (
      'admin_update_payment_status',
      'uuid, character varying',
      'record'::regtype::oid,
      true,
      ARRAY[
        'uuid'::regtype::oid, 'character varying'::regtype::oid,
        'uuid'::regtype::oid, 'character varying'::regtype::oid,
        'character varying'::regtype::oid,
        'timestamp with time zone'::regtype::oid
      ]::oid[],
      ARRAY['i', 'i', 't', 't', 't', 't']::text[],
      ARRAY[
        'p_booking_id', 'p_new_payment_status', 'booking_id',
        'old_payment_status', 'new_payment_status', 'updated_at'
      ]::text[],
      'TABLE(booking_id uuid, old_payment_status character varying, new_payment_status character varying, updated_at timestamp with time zone)'::text,
      '4c26786061dfe6485105fd327196bcbb'
    )
),
rpc_catalog AS (
  SELECT
    procedure_value.oid AS function_oid,
    procedure_value.proname::text AS function_name,
    pg_catalog.oidvectortypes(procedure_value.proargtypes)::text
      AS identity_arguments,
    procedure_value.prorettype,
    procedure_value.proretset,
    procedure_value.proallargtypes,
    ARRAY(
      SELECT mode_value::text
      FROM pg_catalog.unnest(procedure_value.proargmodes)
        AS mode_value
    ) AS argument_modes,
    procedure_value.proargnames,
    pg_catalog.pg_get_function_result(procedure_value.oid)::text
      AS function_result,
    pg_catalog.pg_get_userbyid(procedure_value.proowner)::text AS owner,
    procedure_value.prosecdef AS security_definer,
    procedure_value.prokind::text AS function_kind,
    language.lanname::text AS language,
    procedure_value.provolatile::text AS volatility_code,
    procedure_value.proconfig,
    procedure_value.proacl,
    pg_catalog.regexp_replace(
      pg_catalog.regexp_replace(
        pg_catalog.regexp_replace(
          pg_catalog.lower(procedure_value.prosrc),
          '/\*([^*]|\*+[^*/])*\*+/',
          '',
          'g'
        ),
        '--[^\n\r]*',
        '',
        'g'
      ),
      '[[:space:]]+',
      '',
      'g'
    ) AS normalized_body
  FROM pg_catalog.pg_proc AS procedure_value
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = procedure_value.pronamespace
  JOIN pg_catalog.pg_language AS language
    ON language.oid = procedure_value.prolang
  WHERE namespace.nspname = 'public'
    AND procedure_value.proname IN (
      'create_booking',
      'cancel_own_booking',
      'admin_update_booking_status',
      'admin_update_payment_status'
    )
),
rpc_evaluation AS (
  SELECT
    expected.function_name,
    expected.identity_arguments AS expected_arguments,
    expected.return_type AS expected_return_type,
    expected.returns_set AS expected_returns_set,
    expected.all_argument_types AS expected_all_argument_types,
    expected.argument_modes AS expected_argument_modes,
    expected.argument_names AS expected_argument_names,
    expected.function_result AS expected_function_result,
    expected.approved_body_hash,
    actual.function_oid,
    actual.identity_arguments AS actual_arguments,
    actual.prorettype AS actual_return_type,
    actual.proretset AS actual_returns_set,
    actual.proallargtypes AS actual_all_argument_types,
    actual.argument_modes AS actual_argument_modes,
    actual.proargnames AS actual_argument_names,
    actual.function_result AS actual_function_result,
    actual.owner,
    actual.security_definer,
    actual.language,
    actual.volatility_code,
    actual.normalized_body,
    count(actual.function_oid) OVER (
      PARTITION BY expected.function_name
    ) AS matching_name_count,
    (
      actual.function_oid IS NOT NULL
      AND actual.identity_arguments = expected.identity_arguments
      AND actual.prorettype = expected.return_type
      AND actual.proretset = expected.returns_set
      AND actual.proallargtypes = expected.all_argument_types
      AND actual.argument_modes = expected.argument_modes
      AND actual.proargnames = expected.argument_names
      AND actual.function_result = expected.function_result
    ) AS contract_valid,
    (
      actual.function_oid IS NOT NULL
      AND actual.identity_arguments = expected.identity_arguments
      AND actual.prorettype = expected.return_type
      AND actual.proretset = expected.returns_set
      AND actual.proallargtypes = expected.all_argument_types
      AND actual.argument_modes = expected.argument_modes
      AND actual.proargnames = expected.argument_names
      AND actual.function_result = expected.function_result
      AND actual.owner = 'postgres'
      AND actual.security_definer
      AND actual.function_kind = 'f'
      AND actual.language = 'plpgsql'
      AND actual.volatility_code = 'v'
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.unnest(actual.proconfig) AS setting(value)
        WHERE pg_catalog.regexp_replace(
          pg_catalog.lower(setting.value),
          '[[:space:]]+',
          '',
          'g'
        ) IN ('search_path=', 'search_path=""')
      )
      AND actual.normalized_body NOT LIKE '%execute%'
      AND actual.normalized_body NOT LIKE '%format(%'
      AND actual.normalized_body NOT LIKE '%current_setting%'
      AND NOT EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(
          coalesce(
            actual.proacl,
            pg_catalog.acldefault(
              'f',
              (
                SELECT procedure_value.proowner
                FROM pg_catalog.pg_proc AS procedure_value
                WHERE procedure_value.oid = actual.function_oid
              )
            )
          )
        ) AS acl
        WHERE acl.grantee = 0
          AND acl.privilege_type = 'EXECUTE'
      )
      AND NOT coalesce(pg_catalog.has_function_privilege(
        (SELECT role_oid FROM roles WHERE role_name = 'anon'),
        actual.function_oid,
        'EXECUTE'
      ), false)
      AND coalesce(pg_catalog.has_function_privilege(
        (SELECT role_oid FROM roles WHERE role_name = 'authenticated'),
        actual.function_oid,
        'EXECUTE'
      ), false)
    ) AS security_valid
  FROM expected_rpcs AS expected
  LEFT JOIN rpc_catalog AS actual
    ON actual.function_name = expected.function_name
),
rpc_behavior AS (
  SELECT
    function_name,
    expected_arguments,
    actual_arguments,
    function_oid,
    matching_name_count,
    contract_valid,
    security_valid,
    pg_catalog.md5(normalized_body) = approved_body_hash
      AS body_hash_matches,
    (
      CASE function_name
      WHEN 'create_booking' THEN
        normalized_body LIKE '%auth.uid()%'
        AND normalized_body LIKE '%frompublic.profiles%'
        AND normalized_body LIKE '%profile.status%'
        AND normalized_body LIKE '%active%'
        AND normalized_body LIKE '%frompublic.rooms%'
        AND normalized_body LIKE '%joinpublic.room_types%'
        AND normalized_body LIKE '%room.price_per_night%'
        AND normalized_body LIKE '%room_type.capacity%'
        AND normalized_body LIKE
          '%p_check_in_date<current_date%'
        AND normalized_body LIKE '%v_subtotal::numeric*10::numeric/100::numeric%'
        AND normalized_body LIKE '%10,%'
        AND normalized_body LIKE '%0,%'
        AND normalized_body LIKE '%''pending''%'
        AND normalized_body LIKE '%''pay_at_hotel''%'
        AND normalized_body LIKE '%''unpaid''%'
        AND normalized_body LIKE '%null,%'
        AND normalized_body LIKE '%whenexclusion_violationthen%'
        AND normalized_body LIKE
          '%selectedroomisnolongeravailableforthosedates%'
        AND normalized_body NOT LIKE '%p_user_id%'
        AND normalized_body NOT LIKE '%p_total%'
        AND normalized_body NOT LIKE '%p_status%'
        AND normalized_body NOT LIKE '%p_payment_method%'
      WHEN 'cancel_own_booking' THEN
        normalized_body LIKE '%auth.uid()%'
        AND normalized_body LIKE '%updatepublic.bookings%'
        AND normalized_body LIKE '%booking.user_id=v_caller_id%'
        AND normalized_body LIKE
          '%booking.booking_statusin(''pending'',''confirmed'')%'
        AND normalized_body LIKE '%booking_status=''cancelled''%'
        AND normalized_body LIKE
          '%cancelled_at=pg_catalog.statement_timestamp()%'
        AND normalized_body NOT LIKE '%deletefrompublic.bookings%'
      WHEN 'admin_update_booking_status' THEN
        normalized_body LIKE '%public.is_admin()%'
        AND normalized_body LIKE
          '%v_old_status=''pending''andp_new_statusin(''confirmed'',''cancelled'')%'
        AND normalized_body LIKE
          '%v_old_status=''confirmed''andp_new_statusin(''checked_in'',''cancelled'')%'
        AND normalized_body LIKE
          '%v_old_status=''checked_in''andp_new_status=''completed''%'
        AND normalized_body NOT LIKE '%auth.uid()=%'
        AND normalized_body NOT LIKE '%p_caller%'
        AND normalized_body NOT LIKE '%p_role%'
      WHEN 'admin_update_payment_status' THEN
        normalized_body LIKE '%public.is_admin()%'
        AND normalized_body LIKE
          '%selectbooking.payment_status,booking.booking_status%'
        AND normalized_body LIKE
          '%forupdate%'
        AND normalized_body LIKE
          '%v_booking_status<>''cancelled''andv_old_payment_status=''unpaid''andp_new_payment_statusin(''pending'',''paid'')%'
        AND normalized_body LIKE
          '%v_booking_status<>''cancelled''andv_old_payment_status=''pending''andp_new_payment_statusin(''paid'',''failed'')%'
        AND normalized_body LIKE
          '%v_booking_status<>''cancelled''andv_old_payment_status=''failed''andp_new_payment_statusin(''pending'',''paid'')%'
        AND normalized_body LIKE
          '%v_booking_status=''cancelled''andv_old_payment_status=''paid''andp_new_payment_status=''refunded''%'
        AND normalized_body NOT LIKE '%auth.uid()=%'
        AND normalized_body NOT LIKE '%p_caller%'
        AND normalized_body NOT LIKE '%p_role%'
      ELSE false
      END
    ) AS behavior_valid,
    jsonb_build_object(
      'name', function_name,
      'expected_arguments', expected_arguments,
      'actual_arguments', actual_arguments,
      'expected_return_type', expected_return_type::regtype::text,
      'actual_return_type',
        CASE WHEN actual_return_type IS NULL THEN NULL
          ELSE actual_return_type::regtype::text END,
      'expected_returns_set', expected_returns_set,
      'actual_returns_set', actual_returns_set,
      'expected_all_argument_types', expected_all_argument_types,
      'actual_all_argument_types', actual_all_argument_types,
      'expected_argument_modes', expected_argument_modes,
      'actual_argument_modes', actual_argument_modes,
      'expected_argument_names', expected_argument_names,
      'actual_argument_names', actual_argument_names,
      'expected_function_result', expected_function_result,
      'actual_function_result', actual_function_result,
      'matching_overload_count', matching_name_count,
      'contract_valid', contract_valid,
      'owner', owner,
      'security_definer', security_definer,
      'language', language,
      'search_path_safe', security_valid,
      'approved_body_hash', approved_body_hash,
      'body_hash_matches',
        pg_catalog.md5(normalized_body) = approved_body_hash,
      'normalized_body_hash',
        CASE WHEN normalized_body IS NULL
          THEN NULL ELSE pg_catalog.md5(normalized_body) END
    ) AS report
  FROM rpc_evaluation
),
rpc_state AS (
  SELECT
    count(*) = 4
      AND count(*) FILTER (
        WHERE function_oid IS NOT NULL
          AND actual_arguments = expected_arguments
          AND matching_name_count = 1
      ) = 4 AS exact_overloads,
    coalesce(bool_and(security_valid), false) AS security_valid,
    coalesce(bool_and(contract_valid), false) AS contract_valid,
    coalesce(bool_and(behavior_valid), false) AS behavior_valid,
    count(*) FILTER (WHERE NOT coalesce(body_hash_matches, false))
      AS body_hash_mismatch_count,
    coalesce(
      jsonb_agg(
        report || jsonb_build_object(
          'security_valid', security_valid,
          'behavior_valid', behavior_valid
        )
        ORDER BY function_name
      ),
      '[]'::jsonb
    ) AS functions
  FROM rpc_behavior
),
foundation_functions AS (
  SELECT
    procedure_value.oid AS function_oid,
    procedure_value.proname::text AS function_name,
    procedure_value.pronargs,
    procedure_value.prorettype,
    procedure_value.prosecdef,
    procedure_value.provolatile::text AS volatility_code,
    procedure_value.proconfig,
    pg_catalog.pg_get_userbyid(procedure_value.proowner)::text AS owner,
    language.lanname::text AS language,
    pg_catalog.btrim(
      pg_catalog.regexp_replace(
        pg_catalog.lower(procedure_value.prosrc),
        '[[:space:]]+',
        '',
        'g'
      ),
      pg_catalog.chr(59)
    ) AS normalized_body
  FROM pg_catalog.pg_proc AS procedure_value
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = procedure_value.pronamespace
  JOIN pg_catalog.pg_language AS language
    ON language.oid = procedure_value.prolang
  WHERE namespace.nspname = 'public'
    AND procedure_value.proname IN (
      'is_admin',
      'handle_new_auth_user'
    )
),
auth_profile_state AS (
  SELECT
    (
      SELECT count(*) = 1
        AND coalesce(bool_and(
          pronargs = 0
          AND prorettype = 'boolean'::regtype
          AND prosecdef
          AND volatility_code = 's'
          AND owner = 'postgres'
          AND language = 'sql'
          AND normalized_body =
            $approved$selectcoalesce(exists(select1frompublic.profilesaspwherep.id=auth.uid()andp.role='admin'andp.status='active'),false)$approved$
          AND EXISTS (
            SELECT 1
            FROM pg_catalog.unnest(proconfig) AS setting(value)
            WHERE pg_catalog.regexp_replace(
              pg_catalog.lower(setting.value),
              '[[:space:]]+',
              '',
              'g'
            ) IN ('search_path=', 'search_path=""')
          )
        ), false)
      FROM foundation_functions
      WHERE function_name = 'is_admin'
    ) AS is_admin_valid,
    (
      SELECT count(*) = 1
        AND coalesce(bool_and(
          pronargs = 0
          AND prosecdef
          AND owner = 'postgres'
          AND language = 'plpgsql'
          AND EXISTS (
            SELECT 1
            FROM pg_catalog.unnest(proconfig) AS setting(value)
            WHERE pg_catalog.regexp_replace(
              pg_catalog.lower(setting.value),
              '[[:space:]]+',
              '',
              'g'
            ) IN ('search_path=', 'search_path=""')
          )
          AND normalized_body LIKE '%insertintopublic.profiles%'
          AND normalized_body LIKE '%new.id%'
          AND normalized_body LIKE '%''customer''%'
          AND normalized_body LIKE '%''active''%'
          AND normalized_body NOT LIKE
            '%raw_user_meta_data->>''role''%'
          AND normalized_body NOT LIKE
            '%raw_user_meta_data->>''status''%'
        ), false)
      FROM foundation_functions
      WHERE function_name = 'handle_new_auth_user'
    ) AS handle_new_auth_user_valid,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_value
      WHERE trigger_value.tgrelid = pg_catalog.to_regclass('auth.users')
        AND trigger_value.tgname = 'on_auth_user_created'
        AND NOT trigger_value.tgisinternal
        AND trigger_value.tgenabled <> 'D'
        AND trigger_value.tgfoid =
          pg_catalog.to_regprocedure(
            'public.handle_new_auth_user()'
          )::oid
    ) AS auth_trigger_valid,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS con
      JOIN pg_catalog.pg_attribute AS source_attribute
        ON source_attribute.attrelid = con.conrelid
       AND source_attribute.attname = 'id'
       AND con.conkey = ARRAY[source_attribute.attnum]::smallint[]
      WHERE con.conrelid = pg_catalog.to_regclass('public.profiles')
        AND con.contype = 'f'
        AND con.confrelid = pg_catalog.to_regclass('auth.users')
        AND con.convalidated
    ) AS profiles_auth_fk_valid
),
expected_catalog_policies(table_name, policy_name) AS (
  VALUES
    ('branches'::text, 'branches_public_select'::text),
    ('branches', 'branches_admin_all'),
    ('room_types', 'room_types_public_select'),
    ('room_types', 'room_types_admin_all'),
    ('rooms', 'rooms_public_select'),
    ('rooms', 'rooms_admin_all'),
    ('amenities', 'amenities_public_select'),
    ('amenities', 'amenities_admin_all'),
    ('room_images', 'room_images_public_select'),
    ('room_images', 'room_images_admin_all'),
    ('room_amenities', 'room_amenities_public_select'),
    ('room_amenities', 'room_amenities_admin_all'),
    ('promotions', 'promotions_public_select'),
    ('promotions', 'promotions_admin_all')
),
catalog_foundation_state AS (
  SELECT
    (
      SELECT count(*) = 7
      FROM pg_catalog.pg_class AS class
      JOIN pg_catalog.pg_namespace AS namespace
        ON namespace.oid = class.relnamespace
      WHERE namespace.nspname = 'public'
        AND class.relname IN (
          'branches', 'room_types', 'rooms', 'amenities',
          'room_images', 'room_amenities', 'promotions'
        )
        AND class.relkind IN ('r', 'p')
        AND class.relrowsecurity
        AND NOT class.relforcerowsecurity
    ) AS seven_catalog_tables_hardened,
    (
      SELECT count(*) = 14
        AND count(*) FILTER (WHERE policy.oid IS NOT NULL) = 14
        AND (
          SELECT count(*)
          FROM pg_catalog.pg_policy AS actual_policy
          JOIN pg_catalog.pg_class AS actual_class
            ON actual_class.oid = actual_policy.polrelid
          JOIN pg_catalog.pg_namespace AS actual_namespace
            ON actual_namespace.oid = actual_class.relnamespace
          WHERE actual_namespace.nspname = 'public'
            AND actual_class.relname IN (
              'branches', 'room_types', 'rooms', 'amenities',
              'room_images', 'room_amenities', 'promotions'
            )
        ) = 14
      FROM expected_catalog_policies AS expected
      LEFT JOIN pg_catalog.pg_namespace AS namespace
        ON namespace.nspname = 'public'
      LEFT JOIN pg_catalog.pg_class AS class
        ON class.relnamespace = namespace.oid
       AND class.relname::text = expected.table_name
       AND class.relkind IN ('r', 'p')
      LEFT JOIN pg_catalog.pg_policy AS policy
        ON policy.polrelid = class.oid
       AND policy.polname::text = expected.policy_name
    ) AS catalog_policy_allowlist_intact
),
booking_trigger_state AS (
  SELECT
    count(*) FILTER (
      WHERE trigger_value.tgname = 'trg_bookings_updated_at'
        AND trigger_value.tgenabled <> 'D'
        AND function_namespace.nspname = 'public'
        AND function_value.proname = 'set_updated_at'
    ) = 1 AS updated_at_trigger_valid,
    count(*) FILTER (
      WHERE trigger_value.tgname <> 'trg_bookings_updated_at'
        AND (
          pg_catalog.lower(trigger_value.tgname::text) LIKE '%history%'
          OR pg_catalog.lower(function_value.proname::text) LIKE '%history%'
        )
    ) = 0 AS no_booking_history_trigger,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'name', trigger_value.tgname::text,
          'enabled', trigger_value.tgenabled::text,
          'function',
            function_namespace.nspname::text || '.'
            || function_value.proname::text
        )
        ORDER BY trigger_value.tgname::text
      ),
      '[]'::jsonb
    ) AS triggers
  FROM relation_state AS relation
  JOIN pg_catalog.pg_trigger AS trigger_value
    ON trigger_value.tgrelid = relation.relation_oid
   AND NOT trigger_value.tgisinternal
  JOIN pg_catalog.pg_proc AS function_value
    ON function_value.oid = trigger_value.tgfoid
  JOIN pg_catalog.pg_namespace AS function_namespace
    ON function_namespace.oid = function_value.pronamespace
),
data_guard AS (
  SELECT
    relation.table_exists
      AND columns.data_columns_safe
      AND pg_catalog.to_regclass('public.profiles') IS NOT NULL
      AND pg_catalog.to_regclass('public.rooms') IS NOT NULL
      AND pg_catalog.to_regclass('public.room_types') IS NOT NULL
      AS inspectable
  FROM relation_state AS relation
  CROSS JOIN column_state AS columns
),
data_xml AS (
  SELECT CASE WHEN guard.inspectable THEN
    pg_catalog.query_to_xml(
      $data$
        SELECT jsonb_build_object(
          'booking_count', count(*),
          'null_owner_count',
            count(*) FILTER (WHERE booking.user_id IS NULL),
          'orphan_owner_count',
            count(*) FILTER (
              WHERE booking.user_id IS NOT NULL AND profile.id IS NULL
            ),
          'invalid_date_count',
            count(*) FILTER (
              WHERE booking.check_in_date IS NULL
                 OR booking.check_out_date IS NULL
                 OR booking.check_out_date <= booking.check_in_date
            ),
          'invalid_nights_count',
            count(*) FILTER (
              WHERE booking.number_of_nights IS NULL
                 OR booking.number_of_nights
                  <> booking.check_out_date - booking.check_in_date
            ),
          'invalid_guest_count',
            count(*) FILTER (
              WHERE booking.number_of_guests IS NULL
                 OR booking.number_of_guests <= 0
            ),
          'over_capacity_count',
            count(*) FILTER (
              WHERE room.id IS NULL
                 OR room_type.id IS NULL
                 OR booking.number_of_guests > room_type.capacity
            ),
          'subtotal_inconsistency_count',
            count(*) FILTER (
              WHERE booking.subtotal
                <> booking.price_per_night * booking.number_of_nights
            ),
          'tax_rate_inconsistency_count',
            count(*) FILTER (WHERE booking.tax_rate <> 10::numeric),
          'tax_amount_inconsistency_count',
            count(*) FILTER (
              WHERE booking.tax_amount
                <> round(
                  booking.subtotal::numeric
                  * booking.tax_rate
                  / 100::numeric
                )::bigint
            ),
          'discount_upper_bound_violation_count',
            count(*) FILTER (
              WHERE booking.discount_amount
                > booking.subtotal + booking.tax_amount
            ),
          'total_inconsistency_count',
            count(*) FILTER (
              WHERE booking.total_amount
                <> booking.subtotal
                  + booking.tax_amount
                  - booking.discount_amount
            ),
          'cancellation_inconsistency_count',
            count(*) FILTER (
              WHERE (booking.booking_status = 'cancelled')
                <> (booking.cancelled_at IS NOT NULL)
            )
        ) AS payload
        FROM public.bookings AS booking
        LEFT JOIN public.profiles AS profile
          ON profile.id = booking.user_id
        LEFT JOIN public.rooms AS room
          ON room.id = booking.room_id
        LEFT JOIN public.room_types AS room_type
          ON room_type.id = room.room_type_id
      $data$,
      false,
      true,
      ''
    )
  ELSE NULL::xml END AS result_xml
  FROM data_guard AS guard
),
data_state AS (
  SELECT
    parsed.payload::jsonb AS data_metrics,
    parsed.payload IS NOT NULL AS data_inspected
  FROM data_xml
  LEFT JOIN LATERAL XMLTABLE(
    '//*[local-name()="row"]'
    PASSING data_xml.result_xml
    COLUMNS payload text PATH '*[local-name()="payload"]'
  ) AS parsed ON true
),
overlap_xml AS (
  SELECT CASE WHEN guard.inspectable THEN
    pg_catalog.query_to_xml(
      $overlap$
        SELECT jsonb_build_object(
          'overlapping_pair_count', count(*),
          'affected_room_count', count(DISTINCT overlap.room_id)
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
           AND pg_catalog.daterange(
             left_booking.check_in_date,
             left_booking.check_out_date,
             '[)'
           ) && pg_catalog.daterange(
             right_booking.check_in_date,
             right_booking.check_out_date,
             '[)'
           )
        ) AS overlap
      $overlap$,
      false,
      true,
      ''
    )
  ELSE NULL::xml END AS result_xml
  FROM data_guard AS guard
),
overlap_state AS (
  SELECT
    parsed.payload::jsonb AS overlap_metrics,
    parsed.payload IS NOT NULL AS overlap_inspected
  FROM overlap_xml
  LEFT JOIN LATERAL XMLTABLE(
    '//*[local-name()="row"]'
    PASSING overlap_xml.result_xml
    COLUMNS payload text PATH '*[local-name()="payload"]'
  ) AS parsed ON true
),
all_checks AS (
  SELECT *
  FROM relation_state
  CROSS JOIN column_state
  CROSS JOIN ownership_fk_state
  CROSS JOIN named_constraint_state
  CROSS JOIN exclusion_state
  CROSS JOIN extension_state
  CROSS JOIN opclass_state
  CROSS JOIN index_state
  CROSS JOIN policy_state
  CROSS JOIN privilege_state
  CROSS JOIN rpc_state
  CROSS JOIN auth_profile_state
  CROSS JOIN catalog_foundation_state
  CROSS JOIN booking_trigger_state
  CROSS JOIN data_state
  CROSS JOIN overlap_state
),
decision AS (
  SELECT
    checks.*,
    array_remove(ARRAY[
      CASE WHEN NOT table_exists THEN 'BOOKINGS_TABLE_INVALID' END,
      CASE WHEN NOT user_id_not_null THEN 'BOOKINGS_USER_ID_NULLABLE' END,
      CASE WHEN NOT ownership_fk_valid THEN 'BOOKING_OWNERSHIP_FK_INVALID' END,
      CASE WHEN NOT reviewed_named_constraints_valid
        THEN 'REVIEWED_CONSTRAINT_MISSING_OR_INVALID' END,
      CASE WHEN NOT new_check_constraints_present
        OR NOT tax_rate_constraint_valid
        OR NOT tax_amount_constraint_valid
        OR NOT discount_constraint_valid
        OR NOT cancellation_constraint_valid
        THEN 'FOUNDATION_CHECK_CONSTRAINT_INVALID' END,
      CASE WHEN NOT booking_status_allowlist_valid
        OR NOT payment_status_allowlist_valid
        OR NOT payment_method_allowlist_valid
        OR NOT guest_check_valid
        OR NOT monetary_checks_valid
        THEN 'REVIEWED_SEMANTIC_CONSTRAINT_INVALID' END,
      CASE WHEN NOT exactly_one OR NOT definition_valid
        THEN 'OVERLAP_EXCLUSION_CONSTRAINT_INVALID' END,
      CASE WHEN NOT btree_gist_in_extensions
        THEN 'BTREE_GIST_SCHEMA_INVALID' END,
      CASE WHEN NOT bigint_gist_equality_available
        THEN 'BIGINT_GIST_EQUALITY_OPCLASS_INVALID' END,
      CASE WHEN NOT user_created_index_valid
        OR NOT payment_created_index_valid
        OR NOT reviewed_indexes_preserved
        THEN 'BOOKING_INDEX_INVALID' END,
      CASE WHEN NOT rls_enabled OR force_rls
        THEN 'BOOKING_RLS_STATE_INVALID' END,
      CASE WHEN NOT exact_policy_count
        OR NOT own_policy_valid
        OR NOT admin_policy_valid
        OR unexpected_policy_count <> 0
        OR write_policy_count <> 0
        THEN 'BOOKING_POLICY_ALLOWLIST_INVALID' END,
      CASE WHEN NOT public_none OR NOT anon_none
        OR NOT authenticated_select_only
        OR NOT no_frontend_column_grants
        THEN 'BOOKING_PRIVILEGES_INVALID' END,
      CASE WHEN NOT exact_overloads THEN 'BOOKING_RPC_OVERLOAD_INVALID' END,
      CASE WHEN NOT contract_valid
        THEN 'BOOKING_RPC_RETURN_CONTRACT_INVALID' END,
      CASE WHEN NOT security_valid
        THEN 'BOOKING_RPC_SECURITY_INVALID' END,
      CASE WHEN NOT behavior_valid
        THEN 'BOOKING_RPC_BEHAVIOR_INVALID' END,
      CASE WHEN NOT data_inspected
        OR NOT overlap_inspected
        THEN 'BOOKING_DATA_NOT_INSPECTED' END,
      CASE WHEN coalesce((data_metrics->>'null_owner_count')::bigint, -1) <> 0
        OR coalesce((data_metrics->>'orphan_owner_count')::bigint, -1) <> 0
        THEN 'BOOKING_OWNERSHIP_DATA_INVALID' END,
      CASE WHEN coalesce((data_metrics->>'invalid_date_count')::bigint, -1) <> 0
        OR coalesce((data_metrics->>'invalid_nights_count')::bigint, -1) <> 0
        OR coalesce((data_metrics->>'invalid_guest_count')::bigint, -1) <> 0
        OR coalesce((data_metrics->>'over_capacity_count')::bigint, -1) <> 0
        OR coalesce((data_metrics->>'subtotal_inconsistency_count')::bigint, -1) <> 0
        OR coalesce((data_metrics->>'tax_rate_inconsistency_count')::bigint, -1) <> 0
        OR coalesce((data_metrics->>'tax_amount_inconsistency_count')::bigint, -1) <> 0
        OR coalesce((data_metrics->>'discount_upper_bound_violation_count')::bigint, -1) <> 0
        OR coalesce((data_metrics->>'total_inconsistency_count')::bigint, -1) <> 0
        OR coalesce((data_metrics->>'cancellation_inconsistency_count')::bigint, -1) <> 0
        OR coalesce((overlap_metrics->>'overlapping_pair_count')::bigint, -1) <> 0
        THEN 'BOOKING_DATA_QUALITY_INVALID' END,
      CASE WHEN NOT is_admin_valid
        OR NOT handle_new_auth_user_valid
        OR NOT auth_trigger_valid
        OR NOT profiles_auth_fk_valid
        THEN 'AUTH_PROFILE_FOUNDATION_DRIFT' END,
      CASE WHEN NOT seven_catalog_tables_hardened
        OR NOT catalog_policy_allowlist_intact
        THEN 'CATALOG_FOUNDATION_DRIFT' END,
      CASE WHEN NOT updated_at_trigger_valid
        THEN 'BOOKINGS_UPDATED_AT_TRIGGER_INVALID' END,
      CASE WHEN NOT no_booking_history_trigger
        THEN 'UNEXPECTED_BOOKING_HISTORY_TRIGGER' END
    ], NULL)::text[] AS failures,
    array_remove(ARRAY[
      CASE WHEN (
        SELECT role_oid IS NULL FROM roles WHERE role_name = 'service_role'
      ) THEN 'SERVICE_ROLE_DOES_NOT_EXIST_PRIVILEGES_NOT_APPLICABLE' END,
      CASE WHEN body_hash_mismatch_count > 0
        THEN 'BOOKING_RPC_BODY_FINGERPRINT_CHANGED' END,
      NULL::text
    ], NULL)::text[] AS warnings
  FROM all_checks AS checks
),
final_state AS (
  SELECT
    decision.*,
    cardinality(failures) = 0 AS passed
  FROM decision
)
SELECT jsonb_build_object(
  'check', 'booking_security_postcheck',
  'status', CASE
    WHEN passed THEN 'POSTCHECK_PASSED'
    ELSE 'POSTCHECK_FAILED'
  END,
  'schema', jsonb_build_object(
    'table_exists', table_exists,
    'relations', relations,
    'owner', owner,
    'user_id_not_null', user_id_not_null,
    'ownership_fk_valid', ownership_fk_valid,
    'ownership_foreign_keys', ownership_foreign_keys,
    'null_owner_count', data_metrics->'null_owner_count',
    'orphan_owner_count', data_metrics->'orphan_owner_count'
  ),
  'constraints', jsonb_build_object(
    'reviewed_named_constraints_valid', reviewed_named_constraints_valid,
    'new_check_constraints_present', new_check_constraints_present,
    'tax_rate_constraint_valid', tax_rate_constraint_valid,
    'tax_amount_constraint_valid', tax_amount_constraint_valid,
    'discount_constraint_valid', discount_constraint_valid,
    'cancellation_constraint_valid', cancellation_constraint_valid,
    'booking_status_allowlist_valid', booking_status_allowlist_valid,
    'payment_status_allowlist_valid', payment_status_allowlist_valid,
    'payment_method_allowlist_valid', payment_method_allowlist_valid,
    'guest_check_valid', guest_check_valid,
    'monetary_checks_valid', monetary_checks_valid,
    'exclusion_exactly_one', exactly_one,
    'exclusion_definition_valid', definition_valid,
    'definitions', constraints,
    'exclusion', exclusion_constraints
  ),
  'extension', jsonb_build_object(
    'btree_gist_in_extensions', btree_gist_in_extensions,
    'schema', schema_name,
    'version', version,
    'bigint_gist_equality_available', bigint_gist_equality_available,
    'bigint_gist_opclasses', bigint_gist_opclasses
  ),
  'indexes', jsonb_build_object(
    'bookings_user_created_at_idx_valid', user_created_index_valid,
    'bookings_payment_status_created_at_idx_valid',
      payment_created_index_valid,
    'reviewed_indexes_preserved', reviewed_indexes_preserved,
    'definitions', indexes
  ),
  'rls', jsonb_build_object(
    'enabled', rls_enabled,
    'force_rls', force_rls,
    'exact_policy_count', exact_policy_count,
    'bookings_select_own_valid', own_policy_valid,
    'bookings_select_admin_valid', admin_policy_valid,
    'unexpected_policy_count', unexpected_policy_count,
    'write_policy_count', write_policy_count,
    'policies', policies
  ),
  'privileges', jsonb_build_object(
    'public_none', public_none,
    'anon_none', anon_none,
    'authenticated_select_only', authenticated_select_only,
    'no_frontend_column_grants', no_frontend_column_grants,
    'table_effective', table_privilege_report,
    'column_direct', column_privilege_report
  ),
  'functions', jsonb_build_object(
    'exact_overloads', exact_overloads,
    'return_contract_valid', contract_valid,
    'security_valid', security_valid,
    'behavior_valid', behavior_valid,
    'body_hash_mismatch_count', body_hash_mismatch_count,
    'rpcs', functions
  ),
  'data_quality',
    coalesce(data_metrics, '{}'::jsonb)
    || coalesce(overlap_metrics, '{}'::jsonb)
    || jsonb_build_object(
      'inspected', data_inspected AND overlap_inspected
    ),
  'foundation_integrity', jsonb_build_object(
    'is_admin_valid', is_admin_valid,
    'handle_new_auth_user_valid', handle_new_auth_user_valid,
    'on_auth_user_created_valid', auth_trigger_valid,
    'profiles_auth_fk_valid', profiles_auth_fk_valid,
    'catalog_tables_hardened', seven_catalog_tables_hardened,
    'catalog_policy_allowlist_intact', catalog_policy_allowlist_intact,
    'trg_bookings_updated_at_valid', updated_at_trigger_valid,
    'no_booking_history_trigger', no_booking_history_trigger,
    'booking_triggers', triggers
  ),
  'failures', to_jsonb(failures),
  'warnings', to_jsonb(warnings),
  'recommended_next_action', CASE
    WHEN passed
      THEN 'Proceed to isolated runtime tests with dedicated test accounts.'
    ELSE
      'Review every failure and remediate drift before runtime testing.'
  END
) AS booking_security_postcheck
FROM final_state;

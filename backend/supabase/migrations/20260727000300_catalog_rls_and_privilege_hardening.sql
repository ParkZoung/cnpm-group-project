BEGIN;

-- GoStay Catalog RLS and Privilege Hardening.
-- This migration changes only RLS policies and privileges for the seven catalog
-- tables and their catalog-discovered identity sequences.

DO $preconditions$
DECLARE
  target_table_count integer;
  required_column_count integer;
  valid_status_constraint_count integer;
  valid_foreign_key_count integer;
  actual_identity_mapping_count integer;
  valid_identity_mapping_count integer;
  reviewed_policy_count integer;
  valid_reviewed_policy_count integer;
  admin_oid oid;
  admin_body text;
BEGIN
  SELECT count(*)
  INTO target_table_count
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
    AND class.relkind IN ('r', 'p');

  IF target_table_count <> 7 THEN
    RAISE EXCEPTION
      'Catalog hardening stopped: expected 7 ordinary or partitioned tables, found %.',
      target_table_count;
  END IF;

  WITH required(table_name, column_name, udt_name, nullable) AS (
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
  )
  SELECT count(*)
  INTO required_column_count
  FROM required
  JOIN information_schema.columns AS actual
    ON actual.table_schema = 'public'
   AND actual.table_name = required.table_name
   AND actual.column_name = required.column_name
   AND actual.udt_schema = 'pg_catalog'
   AND actual.udt_name = required.udt_name
   AND actual.is_nullable = required.nullable;

  IF required_column_count <> 18 THEN
    RAISE EXCEPTION
      'Catalog hardening stopped: a required column assumption changed.';
  END IF;

  WITH expected(table_name, expected_values) AS (
    VALUES
      ('branches', ARRAY['active', 'inactive']::text[]),
      ('rooms', ARRAY['available', 'inactive', 'maintenance']::text[]),
      ('amenities', ARRAY['active', 'inactive']::text[]),
      ('promotions', ARRAY['active', 'expired', 'inactive']::text[])
  ),
  actual AS (
    SELECT
      class.relname::text AS table_name,
      con.convalidated,
      (
        SELECT array_agg(
          DISTINCT match.value[1]
          ORDER BY match.value[1]
        )
        FROM pg_catalog.regexp_matches(
          pg_catalog.pg_get_constraintdef(con.oid, true),
          $pattern$'([^']+)'$pattern$,
          'g'
        ) AS match(value)
      ) AS allowed_values
    FROM pg_catalog.pg_constraint AS con
    JOIN pg_catalog.pg_class AS class
      ON class.oid = con.conrelid
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = class.relnamespace
    WHERE namespace.nspname = 'public'
      AND con.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ~* 'status'
  )
  SELECT count(*)
  INTO valid_status_constraint_count
  FROM expected
  JOIN actual
    ON actual.table_name = expected.table_name
   AND actual.convalidated
   AND actual.allowed_values = expected.expected_values;

  IF valid_status_constraint_count <> 4 THEN
    RAISE EXCEPTION
      'Catalog hardening stopped: a status allowlist assumption changed.';
  END IF;

  WITH expected(
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
  )
  SELECT count(*)
  INTO valid_foreign_key_count
  FROM expected
  JOIN pg_catalog.pg_class AS source_relation
    ON source_relation.relname = expected.source_table
  JOIN pg_catalog.pg_namespace AS source_namespace
    ON source_namespace.oid = source_relation.relnamespace
   AND source_namespace.nspname = 'public'
  JOIN pg_catalog.pg_attribute AS source_attribute
    ON source_attribute.attrelid = source_relation.oid
   AND source_attribute.attname = expected.source_column
  JOIN pg_catalog.pg_constraint AS con
    ON con.conrelid = source_relation.oid
   AND con.contype = 'f'
   AND con.convalidated
   AND pg_catalog.array_length(con.conkey, 1) = 1
   AND con.conkey[1] = source_attribute.attnum
  JOIN pg_catalog.pg_class AS target_relation
    ON target_relation.oid = con.confrelid
   AND target_relation.relname = expected.target_table
  JOIN pg_catalog.pg_namespace AS target_namespace
    ON target_namespace.oid = target_relation.relnamespace
   AND target_namespace.nspname = 'public'
  JOIN pg_catalog.pg_attribute AS target_attribute
    ON target_attribute.attrelid = target_relation.oid
   AND target_attribute.attname = expected.target_column
   AND pg_catalog.array_length(con.confkey, 1) = 1
   AND con.confkey[1] = target_attribute.attnum;

  IF valid_foreign_key_count <> 4 THEN
    RAISE EXCEPTION
      'Catalog hardening stopped: a required foreign key assumption changed.';
  END IF;

  SELECT p.oid
  INTO admin_oid
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = p.pronamespace
  JOIN pg_catalog.pg_language AS language
    ON language.oid = p.prolang
  WHERE namespace.nspname = 'public'
    AND p.proname = 'is_admin'
    AND p.pronargs = 0
    AND p.prorettype = 'boolean'::regtype
    AND language.lanname = 'sql'
    AND p.provolatile = 's'
    AND p.prosecdef
    AND pg_catalog.pg_get_userbyid(p.proowner) = 'postgres';

  IF admin_oid IS NULL OR (
    SELECT count(*)
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = p.pronamespace
    WHERE namespace.nspname = 'public'
      AND p.proname = 'is_admin'
      AND p.pronargs = 0
  ) <> 1
  THEN
    RAISE EXCEPTION
      'Catalog hardening stopped: public.is_admin() signature or security attributes differ.';
  END IF;

  SELECT pg_catalog.btrim(
    pg_catalog.regexp_replace(
      pg_catalog.lower(p.prosrc),
      '[[:space:]]+',
      '',
      'g'
    ),
    pg_catalog.chr(59)
  )
  INTO admin_body
  FROM pg_catalog.pg_proc AS p
  WHERE p.oid = admin_oid;

  IF admin_body IS DISTINCT FROM
    $approved$selectcoalesce(exists(select1frompublic.profilesaspwherep.id=auth.uid()andp.role='admin'andp.status='active'),false)$approved$
  THEN
    RAISE EXCEPTION
      'Catalog hardening stopped: public.is_admin() body differs from Foundation.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS p
    CROSS JOIN LATERAL pg_catalog.unnest(p.proconfig) AS config(setting)
    WHERE p.oid = admin_oid
      AND pg_catalog.split_part(config.setting, '=', 1) = 'search_path'
      AND pg_catalog.replace(
        pg_catalog.split_part(config.setting, '=', 2),
        '"',
        ''
      ) = ''
  )
  OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS p
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
    ) AS acl
    WHERE p.oid = admin_oid
      AND acl.grantee = 0
      AND acl.privilege_type = 'EXECUTE'
  )
  OR pg_catalog.has_function_privilege('anon', admin_oid, 'EXECUTE')
  OR NOT pg_catalog.has_function_privilege(
    'authenticated',
    admin_oid,
    'EXECUTE'
  )
  THEN
    RAISE EXCEPTION
      'Catalog hardening stopped: public.is_admin() search_path or ACL differs.';
  END IF;

  WITH target_relations AS (
    SELECT class.oid, class.relname
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
  )
  SELECT count(*)
  INTO reviewed_policy_count
  FROM pg_catalog.pg_policy AS policy
  JOIN target_relations AS relation
    ON relation.oid = policy.polrelid;

  WITH expected(
    table_name,
    policy_name,
    normalized_using
  ) AS (
    VALUES
      (
        'branches',
        'Public read active branches',
        $definition$((status)::text='active'::text)$definition$
      ),
      (
        'room_types',
        'Public read room types',
        'true'
      ),
      (
        'rooms',
        'Public read available rooms',
        $definition$((status)::text='available'::text)$definition$
      )
  ),
  actual AS (
    SELECT
      class.relname AS table_name,
      policy.polname AS policy_name,
      policy.polcmd,
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
          pg_catalog.lower(
            pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
          ),
          '[[:space:]]+',
          '',
          'g'
        ),
        '<null>'
      ) AS normalized_using,
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
      ) AS normalized_with_check
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
  )
  SELECT count(*)
  INTO valid_reviewed_policy_count
  FROM expected
  JOIN actual
    ON actual.table_name = expected.table_name
   AND actual.policy_name = expected.policy_name
   AND actual.polcmd = 'r'
   AND actual.polpermissive
   AND actual.roles = ARRAY['anon', 'authenticated']::text[]
   AND actual.normalized_using = expected.normalized_using
   AND actual.normalized_with_check = '<null>';

  IF reviewed_policy_count <> 3 OR valid_reviewed_policy_count <> 3 THEN
    RAISE EXCEPTION
      'Catalog hardening stopped: reviewed policies changed or an outside policy exists.';
  END IF;

  WITH expected(table_name, column_name, identity_code) AS (
    VALUES
      ('amenities', 'id', 'a'),
      ('branches', 'id', 'd'),
      ('promotions', 'id', 'd'),
      ('room_images', 'id', 'a'),
      ('room_types', 'id', 'd'),
      ('rooms', 'id', 'd')
  ),
  actual AS (
    SELECT
      table_class.relname::text AS table_name,
      attribute.attname::text AS column_name,
      attribute.attidentity::text AS identity_code,
      sequence_class.oid AS sequence_oid
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
    WHERE table_namespace.nspname = 'public'
      AND table_class.relname IN (
        'branches',
        'room_types',
        'rooms',
        'amenities',
        'room_images',
        'room_amenities',
        'promotions'
      )
  )
  SELECT
    (SELECT count(*) FROM actual),
    (
      SELECT count(*)
      FROM expected
      JOIN actual
        ON actual.table_name = expected.table_name
       AND actual.column_name = expected.column_name
       AND actual.identity_code = expected.identity_code
    )
  INTO actual_identity_mapping_count, valid_identity_mapping_count;

  IF actual_identity_mapping_count <> 6
     OR valid_identity_mapping_count <> 6
  THEN
    RAISE EXCEPTION
      'Catalog hardening stopped: identity table/column/generation mappings differ.';
  END IF;
END;
$preconditions$;

DROP POLICY "Public read active branches" ON public.branches;
DROP POLICY "Public read room types" ON public.room_types;
DROP POLICY "Public read available rooms" ON public.rooms;

ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branches NO FORCE ROW LEVEL SECURITY;
ALTER TABLE public.room_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_types NO FORCE ROW LEVEL SECURITY;
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rooms NO FORCE ROW LEVEL SECURITY;
ALTER TABLE public.amenities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.amenities NO FORCE ROW LEVEL SECURITY;
ALTER TABLE public.room_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_images NO FORCE ROW LEVEL SECURITY;
ALTER TABLE public.room_amenities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_amenities NO FORCE ROW LEVEL SECURITY;
ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promotions NO FORCE ROW LEVEL SECURITY;

CREATE POLICY branches_public_select
ON public.branches
AS PERMISSIVE
FOR SELECT
TO anon, authenticated
USING (status = 'active');

CREATE POLICY branches_admin_all
ON public.branches
AS PERMISSIVE
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

CREATE POLICY room_types_public_select
ON public.room_types
AS PERMISSIVE
FOR SELECT
TO anon, authenticated
USING (true);

CREATE POLICY room_types_admin_all
ON public.room_types
AS PERMISSIVE
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

CREATE POLICY rooms_public_select
ON public.rooms
AS PERMISSIVE
FOR SELECT
TO anon, authenticated
USING (
  status = 'available'
  AND EXISTS (
    SELECT 1
    FROM public.branches AS branch
    WHERE branch.id = rooms.branch_id
      AND branch.status = 'active'
  )
);

CREATE POLICY rooms_admin_all
ON public.rooms
AS PERMISSIVE
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

CREATE POLICY amenities_public_select
ON public.amenities
AS PERMISSIVE
FOR SELECT
TO anon, authenticated
USING (status = 'active');

CREATE POLICY amenities_admin_all
ON public.amenities
AS PERMISSIVE
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

CREATE POLICY room_images_public_select
ON public.room_images
AS PERMISSIVE
FOR SELECT
TO anon, authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.rooms AS room
    WHERE room.id = room_images.room_id
      AND room.status = 'available'
      AND EXISTS (
        SELECT 1
        FROM public.branches AS branch
        WHERE branch.id = room.branch_id
          AND branch.status = 'active'
      )
  )
);

CREATE POLICY room_images_admin_all
ON public.room_images
AS PERMISSIVE
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

CREATE POLICY room_amenities_public_select
ON public.room_amenities
AS PERMISSIVE
FOR SELECT
TO anon, authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.rooms AS room
    WHERE room.id = room_amenities.room_id
      AND room.status = 'available'
      AND EXISTS (
        SELECT 1
        FROM public.branches AS branch
        WHERE branch.id = room.branch_id
          AND branch.status = 'active'
      )
  )
  AND EXISTS (
    SELECT 1
    FROM public.amenities AS amenity
    WHERE amenity.id = room_amenities.amenity_id
      AND amenity.status = 'active'
  )
);

CREATE POLICY room_amenities_admin_all
ON public.room_amenities
AS PERMISSIVE
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

CREATE POLICY promotions_public_select
ON public.promotions
AS PERMISSIVE
FOR SELECT
TO anon, authenticated
USING (
  status = 'active'
  AND start_at <= pg_catalog.now()
  AND end_at > pg_catalog.now()
  AND (usage_limit IS NULL OR used_count < usage_limit)
);

CREATE POLICY promotions_admin_all
ON public.promotions
AS PERMISSIVE
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

REVOKE ALL PRIVILEGES ON TABLE
  public.branches,
  public.room_types,
  public.rooms,
  public.amenities,
  public.room_images,
  public.room_amenities,
  public.promotions
FROM PUBLIC, anon, authenticated;

GRANT SELECT ON TABLE
  public.branches,
  public.room_types,
  public.rooms,
  public.amenities,
  public.room_images,
  public.room_amenities,
  public.promotions
TO anon, authenticated;

GRANT INSERT, UPDATE, DELETE ON TABLE
  public.branches,
  public.room_types,
  public.rooms,
  public.amenities,
  public.room_images,
  public.room_amenities,
  public.promotions
TO authenticated;

DO $sequence_privileges$
DECLARE
  sequence_record record;
BEGIN
  FOR sequence_record IN
    SELECT DISTINCT
      sequence_namespace.nspname AS sequence_schema,
      sequence_class.relname AS sequence_name
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
        'branches',
        'room_types',
        'rooms',
        'amenities',
        'room_images',
        'room_amenities',
        'promotions'
      )
  LOOP
    EXECUTE pg_catalog.format(
      'REVOKE ALL PRIVILEGES ON SEQUENCE %I.%I FROM PUBLIC, anon, authenticated',
      sequence_record.sequence_schema,
      sequence_record.sequence_name
    );
    EXECUTE pg_catalog.format(
      'GRANT USAGE ON SEQUENCE %I.%I TO authenticated',
      sequence_record.sequence_schema,
      sequence_record.sequence_name
    );
  END LOOP;
END;
$sequence_privileges$;

-- Compact postconditions; the separate postcheck performs full policy expression
-- reporting and validation.
DO $postconditions$
DECLARE
  policy_count integer;
  bad_table_count integer;
  bad_sequence_count integer;
BEGIN
  SELECT count(*)
  INTO policy_count
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

  IF policy_count <> 14 THEN
    RAISE EXCEPTION
      'Catalog hardening verification failed: expected 14 policies, found %.',
      policy_count;
  END IF;

  SELECT count(*)
  INTO bad_table_count
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
    AND (
      NOT class.relrowsecurity
      OR class.relforcerowsecurity
      OR EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(
          coalesce(class.relacl, pg_catalog.acldefault('r', class.relowner))
        ) AS acl
        WHERE acl.grantee = 0
      )
      OR NOT pg_catalog.has_table_privilege('anon', class.oid, 'SELECT')
      OR NOT pg_catalog.has_table_privilege(
        'authenticated',
        class.oid,
        'SELECT'
      )
      OR NOT pg_catalog.has_table_privilege(
        'authenticated',
        class.oid,
        'INSERT'
      )
      OR NOT pg_catalog.has_table_privilege(
        'authenticated',
        class.oid,
        'UPDATE'
      )
      OR NOT pg_catalog.has_table_privilege(
        'authenticated',
        class.oid,
        'DELETE'
      )
      OR pg_catalog.has_table_privilege('anon', class.oid, 'INSERT')
      OR pg_catalog.has_table_privilege('anon', class.oid, 'UPDATE')
      OR pg_catalog.has_table_privilege('anon', class.oid, 'DELETE')
      OR pg_catalog.has_table_privilege('anon', class.oid, 'TRUNCATE')
      OR pg_catalog.has_table_privilege('anon', class.oid, 'REFERENCES')
      OR pg_catalog.has_table_privilege('anon', class.oid, 'TRIGGER')
      OR pg_catalog.has_table_privilege('anon', class.oid, 'MAINTAIN')
      OR pg_catalog.has_table_privilege(
        'authenticated',
        class.oid,
        'TRUNCATE'
      )
      OR pg_catalog.has_table_privilege(
        'authenticated',
        class.oid,
        'REFERENCES'
      )
      OR pg_catalog.has_table_privilege(
        'authenticated',
        class.oid,
        'TRIGGER'
      )
      OR pg_catalog.has_table_privilege(
        'authenticated',
        class.oid,
        'MAINTAIN'
      )
    );

  IF bad_table_count <> 0 THEN
    RAISE EXCEPTION
      'Catalog hardening verification failed: unsafe table RLS or privilege state.';
  END IF;

  SELECT count(*)
  INTO bad_sequence_count
  FROM (
    SELECT DISTINCT sequence_class.oid
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
    WHERE table_namespace.nspname = 'public'
      AND table_class.relname IN (
        'branches',
        'room_types',
        'rooms',
        'amenities',
        'room_images',
        'room_amenities',
        'promotions'
      )
  ) AS sequence
  JOIN pg_catalog.pg_class AS sequence_class
    ON sequence_class.oid = sequence.oid
  WHERE EXISTS (
       SELECT 1
       FROM pg_catalog.aclexplode(
         coalesce(
           sequence_class.relacl,
           pg_catalog.acldefault('S', sequence_class.relowner)
         )
       ) AS acl
       WHERE acl.grantee = 0
     )
     OR pg_catalog.has_sequence_privilege('anon', sequence.oid, 'USAGE')
     OR pg_catalog.has_sequence_privilege('anon', sequence.oid, 'SELECT')
     OR pg_catalog.has_sequence_privilege('anon', sequence.oid, 'UPDATE')
     OR NOT pg_catalog.has_sequence_privilege(
       'authenticated',
       sequence.oid,
       'USAGE'
     )
     OR pg_catalog.has_sequence_privilege(
       'authenticated',
       sequence.oid,
       'SELECT'
     )
     OR pg_catalog.has_sequence_privilege(
       'authenticated',
       sequence.oid,
       'UPDATE'
     );

  IF bad_sequence_count <> 0 THEN
    RAISE EXCEPTION
      'Catalog hardening verification failed: unsafe identity-sequence ACL.';
  END IF;
END;
$postconditions$;

COMMIT;

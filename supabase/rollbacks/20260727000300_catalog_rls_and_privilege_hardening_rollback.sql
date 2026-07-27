BEGIN;

-- Fail-closed rollback: preserve data and Foundation objects, keep RLS enabled,
-- restore no legacy policy, and leave frontend catalog access closed.

REVOKE ALL PRIVILEGES ON TABLE
  public.branches,
  public.room_types,
  public.rooms,
  public.amenities,
  public.room_images,
  public.room_amenities,
  public.promotions
FROM PUBLIC, anon, authenticated;

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
  END LOOP;
END;
$sequence_privileges$;

DROP POLICY IF EXISTS branches_public_select ON public.branches;
DROP POLICY IF EXISTS branches_admin_all ON public.branches;
DROP POLICY IF EXISTS room_types_public_select ON public.room_types;
DROP POLICY IF EXISTS room_types_admin_all ON public.room_types;
DROP POLICY IF EXISTS rooms_public_select ON public.rooms;
DROP POLICY IF EXISTS rooms_admin_all ON public.rooms;
DROP POLICY IF EXISTS amenities_public_select ON public.amenities;
DROP POLICY IF EXISTS amenities_admin_all ON public.amenities;
DROP POLICY IF EXISTS room_images_public_select ON public.room_images;
DROP POLICY IF EXISTS room_images_admin_all ON public.room_images;
DROP POLICY IF EXISTS room_amenities_public_select ON public.room_amenities;
DROP POLICY IF EXISTS room_amenities_admin_all ON public.room_amenities;
DROP POLICY IF EXISTS promotions_public_select ON public.promotions;
DROP POLICY IF EXISTS promotions_admin_all ON public.promotions;

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

DO $verification$
DECLARE
  unsafe_table_count integer;
  unsafe_sequence_count integer;
BEGIN
  SELECT count(*)
  INTO unsafe_table_count
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
      OR pg_catalog.has_table_privilege('anon', class.oid, 'SELECT')
      OR pg_catalog.has_table_privilege('anon', class.oid, 'INSERT')
      OR pg_catalog.has_table_privilege('anon', class.oid, 'UPDATE')
      OR pg_catalog.has_table_privilege('anon', class.oid, 'DELETE')
      OR pg_catalog.has_table_privilege(
        'authenticated',
        class.oid,
        'SELECT'
      )
      OR pg_catalog.has_table_privilege(
        'authenticated',
        class.oid,
        'INSERT'
      )
      OR pg_catalog.has_table_privilege(
        'authenticated',
        class.oid,
        'UPDATE'
      )
      OR pg_catalog.has_table_privilege(
        'authenticated',
        class.oid,
        'DELETE'
      )
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

  IF unsafe_table_count <> 0 THEN
    RAISE EXCEPTION
      'Fail-closed rollback failed: a target table is not closed.';
  END IF;

  SELECT count(*)
  INTO unsafe_sequence_count
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
    OR pg_catalog.has_sequence_privilege(
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

  IF unsafe_sequence_count <> 0 THEN
    RAISE EXCEPTION
      'Fail-closed rollback failed: a target identity sequence is not closed.';
  END IF;

  IF pg_catalog.to_regprocedure('public.is_admin()') IS NULL
     OR pg_catalog.to_regprocedure('public.handle_new_auth_user()') IS NULL
  THEN
    RAISE WARNING
      'Foundation drift detected: public.is_admin() or public.handle_new_auth_user() is missing. Separate Foundation remediation is required; catalog privilege revocations will still commit.';
  END IF;
END;
$verification$;

COMMIT;

-- GoStay - Auth/Profile Foundation readiness summary
-- Run this single read-only query in Supabase SQL Editor.
-- The result is one JSON object and contains no user-level data.

WITH
expected_schema AS (
  SELECT
    count(*) = 6
    AND count(*) FILTER (
      WHERE column_name = 'id'
        AND udt_schema = 'pg_catalog'
        AND udt_name = 'uuid'
        AND is_nullable = 'NO'
    ) = 1
    AND count(*) FILTER (
      WHERE column_name = 'full_name'
        AND udt_schema = 'pg_catalog'
        AND udt_name = 'varchar'
        AND is_nullable = 'YES'
    ) = 1
    AND count(*) FILTER (
      WHERE column_name = 'phone'
        AND udt_schema = 'pg_catalog'
        AND udt_name = 'varchar'
        AND is_nullable = 'YES'
    ) = 1
    AND count(*) FILTER (
      WHERE column_name = 'role'
        AND udt_schema = 'pg_catalog'
        AND udt_name = 'varchar'
        AND is_nullable = 'NO'
    ) = 1
    AND count(*) FILTER (
      WHERE column_name = 'status'
        AND udt_schema = 'pg_catalog'
        AND udt_name = 'varchar'
        AND is_nullable = 'NO'
    ) = 1
    AND count(*) FILTER (
      WHERE column_name = 'created_at'
        AND udt_schema = 'pg_catalog'
        AND udt_name = 'timestamptz'
        AND is_nullable = 'NO'
    ) = 1 AS schema_matches_expected
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'profiles'
    AND column_name IN ('id', 'full_name', 'phone', 'role', 'status', 'created_at')
),
constraint_state AS (
  SELECT
    coalesce(bool_or(
      c.contype = 'p'
      AND c.convalidated
      AND c.conkey = ARRAY[pa.attnum]::smallint[]
    ), false) AS profiles_primary_key_exists,
    coalesce(bool_or(
      c.contype = 'f'
      AND c.confrelid = 'auth.users'::regclass
      AND c.conkey = ARRAY[pa.attnum]::smallint[]
      AND c.confkey = ARRAY[ua.attnum]::smallint[]
    ), false) AS profiles_auth_foreign_key_exists,
    coalesce(bool_or(
      c.contype = 'f'
      AND c.confrelid = 'auth.users'::regclass
      AND c.conkey = ARRAY[pa.attnum]::smallint[]
      AND c.confkey = ARRAY[ua.attnum]::smallint[]
      AND c.convalidated
    ), false) AS profiles_auth_foreign_key_validated,
    coalesce(bool_or(
      c.contype = 'c'
      AND c.convalidated
      AND lower(pg_catalog.pg_get_constraintdef(c.oid, true)) LIKE '%role%'
      AND lower(pg_catalog.pg_get_constraintdef(c.oid, true)) LIKE '%customer%'
      AND lower(pg_catalog.pg_get_constraintdef(c.oid, true)) LIKE '%admin%'
    ), false) AS role_check_constraint_exists,
    coalesce(bool_or(
      c.contype = 'c'
      AND c.convalidated
      AND lower(pg_catalog.pg_get_constraintdef(c.oid, true)) LIKE '%status%'
      AND lower(pg_catalog.pg_get_constraintdef(c.oid, true)) LIKE '%active%'
      AND lower(pg_catalog.pg_get_constraintdef(c.oid, true)) LIKE '%inactive%'
      AND lower(pg_catalog.pg_get_constraintdef(c.oid, true)) LIKE '%blocked%'
    ), false) AS status_check_constraint_exists
  FROM pg_catalog.pg_attribute AS pa
  CROSS JOIN pg_catalog.pg_attribute AS ua
  LEFT JOIN pg_catalog.pg_constraint AS c
    ON c.conrelid = 'public.profiles'::regclass
  WHERE pa.attrelid = 'public.profiles'::regclass
    AND pa.attname = 'id'
    AND NOT pa.attisdropped
    AND ua.attrelid = 'auth.users'::regclass
    AND ua.attname = 'id'
    AND NOT ua.attisdropped
),
relationship_counts AS (
  SELECT
    (SELECT count(*) FROM auth.users) AS auth_user_count,
    (SELECT count(*) FROM public.profiles) AS profile_count,
    (
      SELECT count(*)
      FROM auth.users AS u
      LEFT JOIN public.profiles AS p
        ON p.id = u.id
      WHERE p.id IS NULL
    ) AS auth_users_without_profile_count,
    (
      SELECT count(*)
      FROM public.profiles AS p
      LEFT JOIN auth.users AS u
        ON u.id = p.id
      WHERE u.id IS NULL
    ) AS orphan_profiles_count
),
profile_counts AS (
  SELECT
    count(*) FILTER (WHERE role = 'customer') AS customer_count,
    count(*) FILTER (WHERE role = 'admin') AS admin_count,
    count(*) FILTER (
      WHERE role IS NULL OR role NOT IN ('customer', 'admin')
    ) AS invalid_or_null_role_count,
    count(*) FILTER (WHERE status = 'active') AS active_count,
    count(*) FILTER (WHERE status = 'inactive') AS inactive_count,
    count(*) FILTER (WHERE status = 'blocked') AS blocked_count,
    count(*) FILTER (
      WHERE status IS NULL OR status NOT IN ('active', 'inactive', 'blocked')
    ) AS invalid_or_null_status_count
  FROM public.profiles
),
metadata_counts AS (
  SELECT count(*) FILTER (
    WHERE raw_user_meta_data ? 'role'
       OR raw_user_meta_data ? 'status'
  ) AS users_with_role_or_status_metadata_count
  FROM auth.users
),
object_state AS (
  SELECT
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc AS p
      JOIN pg_catalog.pg_namespace AS n
        ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname = 'handle_new_auth_user'
    ) AS handle_new_auth_user_exists,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc AS p
      JOIN pg_catalog.pg_namespace AS n
        ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname = 'is_admin'
    ) AS is_admin_exists,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS t
      WHERE t.tgrelid = 'auth.users'::regclass
        AND NOT t.tgisinternal
        AND t.tgname = 'on_auth_user_created'
    ) AS on_auth_user_created_exists,
    (
      SELECT count(*)
      FROM pg_catalog.pg_trigger AS t
      WHERE t.tgrelid = 'auth.users'::regclass
        AND NOT t.tgisinternal
        AND t.tgname <> 'on_auth_user_created'
    ) AS other_auth_users_trigger_count
),
profiles_security AS (
  SELECT
    c.relrowsecurity AS profiles_rls_enabled,
    c.relforcerowsecurity AS profiles_force_rls,
    pg_catalog.pg_get_userbyid(c.relowner) AS profiles_owner,
    (
      SELECT count(*)
      FROM pg_catalog.aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) AS a
      LEFT JOIN pg_catalog.pg_roles AS grantee_role
        ON grantee_role.oid = a.grantee
      WHERE a.grantee = 0
         OR grantee_role.rolname IN ('anon', 'authenticated')
    ) AS unexpected_profiles_grant_count
  FROM pg_catalog.pg_class AS c
  JOIN pg_catalog.pg_namespace AS n
    ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = 'profiles'
    AND c.relkind IN ('r', 'p')
),
checks AS (
  SELECT
    es.schema_matches_expected,
    cs.profiles_primary_key_exists,
    cs.profiles_auth_foreign_key_exists,
    cs.profiles_auth_foreign_key_validated,
    cs.role_check_constraint_exists,
    cs.status_check_constraint_exists,
    rc.auth_user_count,
    rc.profile_count,
    rc.auth_users_without_profile_count,
    rc.orphan_profiles_count,
    (
      rc.auth_users_without_profile_count = 0
      AND rc.orphan_profiles_count = 0
      AND rc.auth_user_count = rc.profile_count
    ) AS one_to_one_relationship_ok,
    pc.customer_count,
    pc.admin_count,
    pc.invalid_or_null_role_count,
    pc.active_count,
    pc.inactive_count,
    pc.blocked_count,
    pc.invalid_or_null_status_count,
    mc.users_with_role_or_status_metadata_count,
    os.handle_new_auth_user_exists,
    os.is_admin_exists,
    os.on_auth_user_created_exists,
    os.other_auth_users_trigger_count,
    ps.profiles_rls_enabled,
    ps.profiles_force_rls,
    ps.profiles_owner,
    ps.unexpected_profiles_grant_count
  FROM expected_schema AS es
  CROSS JOIN constraint_state AS cs
  CROSS JOIN relationship_counts AS rc
  CROSS JOIN profile_counts AS pc
  CROSS JOIN metadata_counts AS mc
  CROSS JOIN object_state AS os
  CROSS JOIN profiles_security AS ps
),
decision_state AS (
  SELECT
    checks.*,
    (
      schema_matches_expected
      AND profiles_primary_key_exists
      AND profiles_auth_foreign_key_exists
      AND profiles_auth_foreign_key_validated
      AND role_check_constraint_exists
      AND status_check_constraint_exists
      AND auth_users_without_profile_count = 0
      AND orphan_profiles_count = 0
      AND invalid_or_null_role_count = 0
      AND invalid_or_null_status_count = 0
      AND NOT handle_new_auth_user_exists
      AND NOT is_admin_exists
      AND NOT on_auth_user_created_exists
    ) AS foundation_ready,
    array_remove(ARRAY[
      CASE WHEN NOT schema_matches_expected
        THEN 'SCHEMA_MISMATCH' END,
      CASE WHEN NOT profiles_primary_key_exists
        THEN 'PROFILES_PRIMARY_KEY_MISSING_OR_INVALID' END,
      CASE WHEN NOT profiles_auth_foreign_key_exists
        THEN 'PROFILES_AUTH_FOREIGN_KEY_MISSING' END,
      CASE WHEN profiles_auth_foreign_key_exists
             AND NOT profiles_auth_foreign_key_validated
        THEN 'PROFILES_AUTH_FOREIGN_KEY_NOT_VALIDATED' END,
      CASE WHEN NOT role_check_constraint_exists
        THEN 'ROLE_CHECK_CONSTRAINT_MISSING_OR_INVALID' END,
      CASE WHEN NOT status_check_constraint_exists
        THEN 'STATUS_CHECK_CONSTRAINT_MISSING_OR_INVALID' END,
      CASE WHEN auth_users_without_profile_count <> 0
        THEN 'AUTH_USERS_WITHOUT_PROFILE' END,
      CASE WHEN orphan_profiles_count <> 0
        THEN 'ORPHAN_PROFILES' END,
      CASE WHEN invalid_or_null_role_count <> 0
        THEN 'INVALID_OR_NULL_PROFILE_ROLE' END,
      CASE WHEN invalid_or_null_status_count <> 0
        THEN 'INVALID_OR_NULL_PROFILE_STATUS' END,
      CASE WHEN handle_new_auth_user_exists
        THEN 'HANDLE_NEW_AUTH_USER_OBJECT_CONFLICT' END,
      CASE WHEN is_admin_exists
        THEN 'IS_ADMIN_OBJECT_CONFLICT' END,
      CASE WHEN on_auth_user_created_exists
        THEN 'ON_AUTH_USER_CREATED_OBJECT_CONFLICT' END
    ], NULL) AS blocking_reasons
  FROM checks
)
SELECT jsonb_build_object(
  'schema_matches_expected', schema_matches_expected,
  'profiles_primary_key_exists', profiles_primary_key_exists,
  'profiles_auth_foreign_key_exists', profiles_auth_foreign_key_exists,
  'profiles_auth_foreign_key_validated', profiles_auth_foreign_key_validated,
  'role_check_constraint_exists', role_check_constraint_exists,
  'status_check_constraint_exists', status_check_constraint_exists,
  'auth_user_count', auth_user_count,
  'profile_count', profile_count,
  'auth_users_without_profile_count', auth_users_without_profile_count,
  'orphan_profiles_count', orphan_profiles_count,
  'one_to_one_relationship_ok', one_to_one_relationship_ok,
  'customer_count', customer_count,
  'admin_count', admin_count,
  'invalid_or_null_role_count', invalid_or_null_role_count,
  'active_count', active_count,
  'inactive_count', inactive_count,
  'blocked_count', blocked_count,
  'invalid_or_null_status_count', invalid_or_null_status_count,
  'users_with_role_or_status_metadata_count', users_with_role_or_status_metadata_count,
  'handle_new_auth_user_exists', handle_new_auth_user_exists,
  'is_admin_exists', is_admin_exists,
  'on_auth_user_created_exists', on_auth_user_created_exists,
  'other_auth_users_trigger_count', other_auth_users_trigger_count,
  'profiles_rls_enabled', profiles_rls_enabled,
  'profiles_force_rls', profiles_force_rls,
  'profiles_owner', profiles_owner,
  'unexpected_profiles_grant_count', unexpected_profiles_grant_count,
  'decision', CASE
    WHEN foundation_ready THEN 'READY_FOR_FOUNDATION'
    ELSE 'RECONCILIATION_REQUIRED'
  END,
  'blocking_reasons', to_jsonb(blocking_reasons)
) AS auth_profile_foundation_summary
FROM decision_state;

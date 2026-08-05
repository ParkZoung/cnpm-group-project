-- GoStay - Auth/Profile Foundation Preflight Audit
-- Purpose: inspect the current database state before implementing Auth/Profile Foundation.
-- Usage: run one section at a time in Supabase SQL Editor.
-- This file is read-only: every executable statement is a SELECT query.
-- Do not store exported rows or real user data in the repository.


-- ============================================================================
-- A. AUTH USERS WITHOUT A PROFILE
-- Normal: missing_profile_count = 0 and the detail query returns no rows.
-- Abnormal: any Auth user has no matching public.profiles row.
-- Action: review each user; prepare a separately reviewed reconciliation plan.
-- Metadata role/status below is audit evidence only and is never authoritative.
-- ============================================================================

SELECT count(*) AS missing_profile_count
FROM auth.users AS u
LEFT JOIN public.profiles AS p
  ON p.id = u.id
WHERE p.id IS NULL;

SELECT
  u.id,
  u.email,
  u.created_at,
  nullif(btrim(u.raw_user_meta_data ->> 'full_name'), '') AS metadata_full_name,
  nullif(btrim(u.raw_user_meta_data ->> 'phone'), '') AS metadata_phone,
  u.raw_user_meta_data ->> 'role' AS metadata_role_audit_only,
  u.raw_user_meta_data ->> 'status' AS metadata_status_audit_only
FROM auth.users AS u
LEFT JOIN public.profiles AS p
  ON p.id = u.id
WHERE p.id IS NULL
ORDER BY u.created_at, u.id;


-- ============================================================================
-- B. PROFILES WITHOUT AN AUTH USER
-- Normal: orphan_profile_count = 0 and the detail query returns no rows.
-- Abnormal: a profile ID has no matching auth.users row.
-- Action: verify the foreign key and investigate how each orphan was created.
-- ============================================================================

SELECT count(*) AS orphan_profile_count
FROM public.profiles AS p
LEFT JOIN auth.users AS u
  ON u.id = p.id
WHERE u.id IS NULL;

SELECT
  p.id,
  p.full_name,
  p.phone,
  p.role,
  p.status,
  p.created_at
FROM public.profiles AS p
LEFT JOIN auth.users AS u
  ON u.id = p.id
WHERE u.id IS NULL
ORDER BY p.created_at, p.id;


-- ============================================================================
-- C. ONE-TO-ONE RELATIONSHIP
-- Normal: auth/profile totals match and every Auth user has profile_count = 1.
-- Abnormal: totals differ or the violation query returns any row.
-- Action: classify missing, orphaned, or duplicated relationships before changes.
-- ============================================================================

SELECT
  (SELECT count(*) FROM auth.users) AS total_auth_users,
  (SELECT count(*) FROM public.profiles) AS total_profiles,
  (
    SELECT count(*)
    FROM auth.users AS u
    JOIN public.profiles AS p
      ON p.id = u.id
  ) AS matched_auth_profiles;

SELECT
  u.id AS auth_user_id,
  u.email,
  u.created_at,
  count(p.id) AS profile_count
FROM auth.users AS u
LEFT JOIN public.profiles AS p
  ON p.id = u.id
GROUP BY u.id, u.email, u.created_at
HAVING count(p.id) <> 1
ORDER BY u.created_at, u.id;


-- ============================================================================
-- D. CURRENT ROLES
-- Normal: only customer/admin appear; no NULL or unexpected value; admins are known.
-- Abnormal: NULL, an out-of-allowlist role, or an unrecognized admin account.
-- Action: verify every admin by Auth user ID; never infer authority from metadata.
-- ============================================================================

SELECT
  p.role,
  count(*) AS profile_count
FROM public.profiles AS p
GROUP BY p.role
ORDER BY p.role NULLS FIRST;

SELECT count(*) AS null_role_count
FROM public.profiles AS p
WHERE p.role IS NULL;

SELECT
  p.id,
  p.role,
  p.status,
  p.created_at
FROM public.profiles AS p
WHERE p.role IS NULL
   OR p.role NOT IN ('customer', 'admin')
ORDER BY p.created_at, p.id;

SELECT
  p.id,
  u.email,
  p.full_name,
  p.status,
  p.created_at AS profile_created_at,
  u.created_at AS auth_created_at
FROM public.profiles AS p
LEFT JOIN auth.users AS u
  ON u.id = p.id
WHERE p.role = 'admin'
ORDER BY p.created_at, p.id;


-- ============================================================================
-- E. CURRENT STATUSES
-- Normal: only active/inactive/blocked appear; no NULL or unexpected value.
-- Abnormal: NULL or a value outside the approved status allowlist.
-- Action: classify each invalid row and agree on a correction before constraints.
-- ============================================================================

SELECT
  p.status,
  count(*) AS profile_count
FROM public.profiles AS p
GROUP BY p.status
ORDER BY p.status NULLS FIRST;

SELECT count(*) AS null_status_count
FROM public.profiles AS p
WHERE p.status IS NULL;

SELECT
  p.id,
  p.role,
  p.status,
  p.created_at
FROM public.profiles AS p
WHERE p.status IS NULL
   OR p.status NOT IN ('active', 'inactive', 'blocked')
ORDER BY p.created_at, p.id;


-- ============================================================================
-- F. AUTH METADATA
-- Normal: optional full_name/phone may exist; role/status metadata is absent.
-- Abnormal: role/status metadata exists, especially values suggesting admin access.
-- Action: record affected IDs for review; metadata role/status must remain non-authoritative.
-- ============================================================================

SELECT
  count(*) FILTER (
    WHERE nullif(btrim(u.raw_user_meta_data ->> 'full_name'), '') IS NOT NULL
  ) AS users_with_metadata_full_name,
  count(*) FILTER (
    WHERE nullif(btrim(u.raw_user_meta_data ->> 'phone'), '') IS NOT NULL
  ) AS users_with_metadata_phone,
  count(*) FILTER (
    WHERE u.raw_user_meta_data ? 'role'
  ) AS users_with_metadata_role,
  count(*) FILTER (
    WHERE u.raw_user_meta_data ? 'status'
  ) AS users_with_metadata_status,
  count(*) AS total_auth_users
FROM auth.users AS u;

SELECT
  u.id,
  u.email,
  u.created_at,
  u.raw_user_meta_data ->> 'role' AS metadata_role_audit_only,
  u.raw_user_meta_data ->> 'status' AS metadata_status_audit_only
FROM auth.users AS u
WHERE u.raw_user_meta_data ? 'role'
   OR u.raw_user_meta_data ? 'status'
ORDER BY u.created_at, u.id;


-- ============================================================================
-- G. CURRENT CONSTRAINTS ON PUBLIC.PROFILES
-- Normal: validated primary key on id, validated foreign key to auth.users(id),
-- and validated checks for the approved role and status values.
-- Abnormal: a required constraint is absent, unvalidated, or targets other columns.
-- Action: compare definitions with the intended schema before any schema change.
-- ============================================================================

SELECT
  c.conname AS constraint_name,
  CASE c.contype
    WHEN 'p' THEN 'PRIMARY KEY'
    WHEN 'f' THEN 'FOREIGN KEY'
    WHEN 'c' THEN 'CHECK'
    WHEN 'u' THEN 'UNIQUE'
    ELSE c.contype::text
  END AS constraint_type,
  c.convalidated AS is_validated,
  pg_catalog.pg_get_constraintdef(c.oid, true) AS constraint_definition
FROM pg_catalog.pg_constraint AS c
WHERE c.conrelid = 'public.profiles'::regclass
ORDER BY
  CASE c.contype WHEN 'p' THEN 1 WHEN 'f' THEN 2 WHEN 'c' THEN 3 ELSE 4 END,
  c.conname;


-- ============================================================================
-- H. OBJECT CONFLICTS
-- Normal: target functions/trigger do not yet exist; unrelated Auth triggers are understood.
-- Abnormal: a target name already exists or an unknown trigger acts on auth.users.
-- Action: review owner and exact definition; do not overwrite an unexplained object.
-- ============================================================================

SELECT
  n.nspname AS function_schema,
  p.proname AS function_name,
  pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
  pg_catalog.pg_get_function_result(p.oid) AS result_type,
  p.prosecdef AS is_security_definer,
  p.proconfig AS function_settings,
  pg_catalog.pg_get_userbyid(p.proowner) AS function_owner,
  pg_catalog.pg_get_functiondef(p.oid) AS function_definition
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n
  ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('handle_new_auth_user', 'is_admin')
ORDER BY p.proname, pg_catalog.pg_get_function_identity_arguments(p.oid);

SELECT
  t.tgname AS trigger_name,
  t.tgenabled AS trigger_enabled_code,
  pn.nspname AS function_schema,
  p.proname AS function_name,
  pg_catalog.pg_get_triggerdef(t.oid, true) AS trigger_definition
FROM pg_catalog.pg_trigger AS t
JOIN pg_catalog.pg_class AS c
  ON c.oid = t.tgrelid
JOIN pg_catalog.pg_namespace AS n
  ON n.oid = c.relnamespace
JOIN pg_catalog.pg_proc AS p
  ON p.oid = t.tgfoid
JOIN pg_catalog.pg_namespace AS pn
  ON pn.oid = p.pronamespace
WHERE n.nspname = 'auth'
  AND c.relname = 'users'
  AND NOT t.tgisinternal
ORDER BY
  CASE WHEN t.tgname = 'on_auth_user_created' THEN 0 ELSE 1 END,
  t.tgname;


-- ============================================================================
-- I. OWNERS AND PRIVILEGES
-- Normal: profiles and definer functions have trusted owners; grants are minimal;
-- profiles RLS state matches the documented current state before the later RLS task.
-- Abnormal: broad write grants, PUBLIC function execution, unexpected owners, or drift.
-- Action: review grants/owners before deployment and plan least-privilege corrections.
-- ============================================================================

SELECT
  n.nspname AS table_schema,
  c.relname AS table_name,
  pg_catalog.pg_get_userbyid(c.relowner) AS table_owner,
  c.relrowsecurity AS rls_enabled,
  c.relforcerowsecurity AS force_row_level_security
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n
  ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'profiles'
  AND c.relkind IN ('r', 'p');

SELECT
  g.grantor,
  g.grantee,
  g.privilege_type,
  g.is_grantable
FROM information_schema.role_table_grants AS g
WHERE g.table_schema = 'public'
  AND g.table_name = 'profiles'
ORDER BY g.grantee, g.privilege_type;

SELECT
  n.nspname AS function_schema,
  p.proname AS function_name,
  pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
  pg_catalog.pg_get_userbyid(p.proowner) AS function_owner,
  p.prosecdef AS is_security_definer,
  p.proconfig AS function_settings
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n
  ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'handle_new_auth_user',
    'is_admin',
    'rls_auto_enable',
    'set_updated_at'
  )
ORDER BY p.proname, pg_catalog.pg_get_function_identity_arguments(p.oid);

SELECT
  r.routine_schema AS function_schema,
  r.routine_name AS function_name,
  r.specific_name,
  r.grantor,
  r.grantee,
  r.privilege_type,
  r.is_grantable
FROM information_schema.routine_privileges AS r
WHERE r.routine_schema = 'public'
  AND r.routine_name IN (
    'handle_new_auth_user',
    'is_admin',
    'rls_auto_enable',
    'set_updated_at'
  )
ORDER BY r.routine_name, r.specific_name, r.grantee, r.privilege_type;


-- ============================================================================
-- J. ACTUAL PUBLIC.PROFILES COLUMN SHAPE
-- Normal: id is non-null uuid; role/status/created_at are non-null; optional
-- full_name/phone match the expected character types; defaults match documentation.
-- Abnormal: missing columns, unexpected types, nullable security fields, or schema drift.
-- Action: reconcile the documented schema with the actual shape before implementation.
-- ============================================================================

SELECT
  c.ordinal_position,
  c.column_name,
  c.data_type,
  c.udt_schema,
  c.udt_name,
  c.character_maximum_length,
  c.is_nullable,
  c.column_default
FROM information_schema.columns AS c
WHERE c.table_schema = 'public'
  AND c.table_name = 'profiles'
  AND c.column_name IN (
    'id',
    'full_name',
    'phone',
    'role',
    'status',
    'created_at'
  )
ORDER BY c.ordinal_position;

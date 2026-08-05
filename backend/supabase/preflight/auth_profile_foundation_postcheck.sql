-- GoStay - Auth/Profile Foundation post-deployment check
-- Run this single read-only query after applying the Foundation migration.
-- The result contains aggregate and database-object information only.
-- profiles RLS flags are informational: RLS remains the next security task.

WITH
target_functions AS (
  SELECT
    p.oid,
    n.nspname AS function_schema,
    p.proname AS function_name,
    p.proowner,
    p.prosecdef,
    p.proconfig,
    p.proacl
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n
    ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('handle_new_auth_user', 'is_admin')
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = ''
),
handle_function AS (
  SELECT
    count(*) = 1 AS function_exists,
    coalesce(bool_and(prosecdef), false) AS security_definer,
    CASE
      WHEN count(*) = 1 THEN pg_catalog.min(pg_catalog.pg_get_userbyid(proowner))
      ELSE NULL
    END AS function_owner,
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
    ), false) AS search_path_safe,
    coalesce(bool_or(
      EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(
          coalesce(proacl, pg_catalog.acldefault('f', proowner))
        ) AS acl
        WHERE acl.grantee = 0
          AND acl.privilege_type = 'EXECUTE'
      )
    ), false) AS public_execute,
    coalesce(bool_or(
      pg_catalog.has_function_privilege('anon', oid, 'EXECUTE')
    ), false) AS anon_execute,
    coalesce(bool_or(
      pg_catalog.has_function_privilege('authenticated', oid, 'EXECUTE')
    ), false) AS authenticated_execute
  FROM target_functions
  WHERE function_name = 'handle_new_auth_user'
),
admin_function AS (
  SELECT
    count(*) = 1 AS function_exists,
    coalesce(bool_and(prosecdef), false) AS security_definer,
    CASE
      WHEN count(*) = 1 THEN pg_catalog.min(pg_catalog.pg_get_userbyid(proowner))
      ELSE NULL
    END AS function_owner,
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
    ), false) AS search_path_safe,
    coalesce(bool_or(
      EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(
          coalesce(proacl, pg_catalog.acldefault('f', proowner))
        ) AS acl
        WHERE acl.grantee = 0
          AND acl.privilege_type = 'EXECUTE'
      )
    ), false) AS public_execute,
    coalesce(bool_or(
      pg_catalog.has_function_privilege('anon', oid, 'EXECUTE')
    ), false) AS anon_execute,
    coalesce(bool_or(
      pg_catalog.has_function_privilege('authenticated', oid, 'EXECUTE')
    ), false) AS authenticated_execute
  FROM target_functions
  WHERE function_name = 'is_admin'
),
foundation_trigger AS (
  SELECT
    count(*) = 1 AS trigger_exists,
    count(*) = 1
    AND coalesce(bool_and(t.tgenabled <> 'D'), false) AS trigger_enabled,
    CASE
      WHEN count(*) = 1
      THEN pg_catalog.min(table_ns.nspname || '.' || table_class.relname)
      ELSE NULL
    END AS trigger_table,
    CASE
      WHEN count(*) = 1
      THEN pg_catalog.min(
        function_ns.nspname || '.'
        || function_proc.proname || '('
        || pg_catalog.pg_get_function_identity_arguments(function_proc.oid)
        || ')'
      )
      ELSE NULL
    END AS trigger_function
  FROM pg_catalog.pg_trigger AS t
  JOIN pg_catalog.pg_class AS table_class
    ON table_class.oid = t.tgrelid
  JOIN pg_catalog.pg_namespace AS table_ns
    ON table_ns.oid = table_class.relnamespace
  JOIN pg_catalog.pg_proc AS function_proc
    ON function_proc.oid = t.tgfoid
  JOIN pg_catalog.pg_namespace AS function_ns
    ON function_ns.oid = function_proc.pronamespace
  WHERE table_ns.nspname = 'auth'
    AND table_class.relname = 'users'
    AND t.tgname = 'on_auth_user_created'
    AND NOT t.tgisinternal
),
relationship_state AS (
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
profiles_security AS (
  SELECT
    coalesce(bool_and(c.relrowsecurity), false) AS profiles_rls_enabled,
    coalesce(bool_and(c.relforcerowsecurity), false) AS profiles_force_rls
  FROM pg_catalog.pg_class AS c
  JOIN pg_catalog.pg_namespace AS n
    ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = 'profiles'
    AND c.relkind IN ('r', 'p')
),
checks AS (
  SELECT
    hf.function_exists AS handle_new_auth_user_exists,
    hf.security_definer AS handle_new_auth_user_security_definer,
    hf.function_owner AS handle_new_auth_user_owner,
    hf.search_path_safe AS handle_new_auth_user_search_path_safe,
    hf.public_execute AS handle_new_auth_user_public_execute,
    hf.anon_execute AS handle_new_auth_user_anon_execute,
    hf.authenticated_execute AS handle_new_auth_user_authenticated_execute,
    af.function_exists AS is_admin_exists,
    af.security_definer AS is_admin_security_definer,
    af.function_owner AS is_admin_owner,
    af.search_path_safe AS is_admin_search_path_safe,
    af.public_execute AS is_admin_public_execute,
    af.anon_execute AS is_admin_anon_execute,
    af.authenticated_execute AS is_admin_authenticated_execute,
    ft.trigger_exists AS on_auth_user_created_exists,
    ft.trigger_enabled,
    ft.trigger_table,
    ft.trigger_function,
    rs.auth_user_count,
    rs.profile_count,
    rs.auth_users_without_profile_count,
    rs.orphan_profiles_count,
    (
      rs.auth_users_without_profile_count = 0
      AND rs.orphan_profiles_count = 0
      AND rs.auth_user_count = rs.profile_count
    ) AS one_to_one_relationship_ok,
    ps.profiles_rls_enabled,
    ps.profiles_force_rls
  FROM handle_function AS hf
  CROSS JOIN admin_function AS af
  CROSS JOIN foundation_trigger AS ft
  CROSS JOIN relationship_state AS rs
  CROSS JOIN profiles_security AS ps
),
decision_state AS (
  SELECT
    checks.*,
    (
      handle_new_auth_user_exists
      AND handle_new_auth_user_security_definer
      AND handle_new_auth_user_owner = 'postgres'
      AND handle_new_auth_user_search_path_safe
      AND NOT handle_new_auth_user_public_execute
      AND NOT handle_new_auth_user_anon_execute
      AND NOT handle_new_auth_user_authenticated_execute
      AND is_admin_exists
      AND is_admin_security_definer
      AND is_admin_owner = 'postgres'
      AND is_admin_search_path_safe
      AND NOT is_admin_public_execute
      AND NOT is_admin_anon_execute
      AND is_admin_authenticated_execute
      AND on_auth_user_created_exists
      AND trigger_enabled
      AND trigger_table = 'auth.users'
      AND trigger_function = 'public.handle_new_auth_user()'
      AND one_to_one_relationship_ok
    ) AS postcheck_passed,
    array_remove(ARRAY[
      CASE WHEN NOT handle_new_auth_user_exists
        THEN 'HANDLE_NEW_AUTH_USER_MISSING_OR_DUPLICATED' END,
      CASE WHEN handle_new_auth_user_exists
             AND NOT handle_new_auth_user_security_definer
        THEN 'HANDLE_NEW_AUTH_USER_NOT_SECURITY_DEFINER' END,
      CASE WHEN handle_new_auth_user_exists
             AND handle_new_auth_user_owner IS DISTINCT FROM 'postgres'
        THEN 'HANDLE_NEW_AUTH_USER_OWNER_INVALID' END,
      CASE WHEN handle_new_auth_user_exists
             AND NOT handle_new_auth_user_search_path_safe
        THEN 'HANDLE_NEW_AUTH_USER_SEARCH_PATH_UNSAFE' END,
      CASE WHEN handle_new_auth_user_public_execute
        THEN 'HANDLE_NEW_AUTH_USER_PUBLIC_EXECUTE_PRESENT' END,
      CASE WHEN handle_new_auth_user_anon_execute
        THEN 'HANDLE_NEW_AUTH_USER_ANON_EXECUTE_PRESENT' END,
      CASE WHEN handle_new_auth_user_authenticated_execute
        THEN 'HANDLE_NEW_AUTH_USER_AUTHENTICATED_EXECUTE_PRESENT' END,
      CASE WHEN NOT is_admin_exists
        THEN 'IS_ADMIN_MISSING_OR_DUPLICATED' END,
      CASE WHEN is_admin_exists
             AND NOT is_admin_security_definer
        THEN 'IS_ADMIN_NOT_SECURITY_DEFINER' END,
      CASE WHEN is_admin_exists
             AND is_admin_owner IS DISTINCT FROM 'postgres'
        THEN 'IS_ADMIN_OWNER_INVALID' END,
      CASE WHEN is_admin_exists
             AND NOT is_admin_search_path_safe
        THEN 'IS_ADMIN_SEARCH_PATH_UNSAFE' END,
      CASE WHEN is_admin_public_execute
        THEN 'IS_ADMIN_PUBLIC_EXECUTE_PRESENT' END,
      CASE WHEN is_admin_anon_execute
        THEN 'IS_ADMIN_ANON_EXECUTE_PRESENT' END,
      CASE WHEN NOT is_admin_authenticated_execute
        THEN 'IS_ADMIN_AUTHENTICATED_EXECUTE_MISSING' END,
      CASE WHEN NOT on_auth_user_created_exists
        THEN 'ON_AUTH_USER_CREATED_MISSING_OR_DUPLICATED' END,
      CASE WHEN on_auth_user_created_exists
             AND NOT trigger_enabled
        THEN 'ON_AUTH_USER_CREATED_DISABLED' END,
      CASE WHEN on_auth_user_created_exists
             AND trigger_table IS DISTINCT FROM 'auth.users'
        THEN 'ON_AUTH_USER_CREATED_TABLE_INVALID' END,
      CASE WHEN on_auth_user_created_exists
             AND trigger_function IS DISTINCT FROM 'public.handle_new_auth_user()'
        THEN 'ON_AUTH_USER_CREATED_FUNCTION_INVALID' END,
      CASE WHEN auth_users_without_profile_count <> 0
        THEN 'AUTH_USERS_WITHOUT_PROFILE' END,
      CASE WHEN orphan_profiles_count <> 0
        THEN 'ORPHAN_PROFILES' END,
      CASE WHEN NOT one_to_one_relationship_ok
        THEN 'AUTH_PROFILE_ONE_TO_ONE_RELATIONSHIP_INVALID' END
    ], NULL) AS blocking_reasons
  FROM checks
)
SELECT jsonb_build_object(
  'handle_new_auth_user_exists', handle_new_auth_user_exists,
  'handle_new_auth_user_security_definer', handle_new_auth_user_security_definer,
  'handle_new_auth_user_owner', handle_new_auth_user_owner,
  'handle_new_auth_user_search_path_safe', handle_new_auth_user_search_path_safe,
  'handle_new_auth_user_public_execute', handle_new_auth_user_public_execute,
  'handle_new_auth_user_anon_execute', handle_new_auth_user_anon_execute,
  'handle_new_auth_user_authenticated_execute', handle_new_auth_user_authenticated_execute,
  'is_admin_exists', is_admin_exists,
  'is_admin_security_definer', is_admin_security_definer,
  'is_admin_owner', is_admin_owner,
  'is_admin_search_path_safe', is_admin_search_path_safe,
  'is_admin_public_execute', is_admin_public_execute,
  'is_admin_anon_execute', is_admin_anon_execute,
  'is_admin_authenticated_execute', is_admin_authenticated_execute,
  'on_auth_user_created_exists', on_auth_user_created_exists,
  'trigger_enabled', trigger_enabled,
  'trigger_table', trigger_table,
  'trigger_function', trigger_function,
  'auth_user_count', auth_user_count,
  'profile_count', profile_count,
  'auth_users_without_profile_count', auth_users_without_profile_count,
  'orphan_profiles_count', orphan_profiles_count,
  'one_to_one_relationship_ok', one_to_one_relationship_ok,
  'profiles_rls_enabled', profiles_rls_enabled,
  'profiles_force_rls', profiles_force_rls,
  'decision', CASE
    WHEN postcheck_passed THEN 'POSTCHECK_PASSED'
    ELSE 'POSTCHECK_FAILED'
  END,
  'blocking_reasons', to_jsonb(blocking_reasons)
) AS auth_profile_foundation_postcheck
FROM decision_state;

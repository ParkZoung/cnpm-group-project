-- GoStay - Profiles RLS and Privilege Hardening postcheck
-- This is one read-only query returning one JSON object with no personal data.

WITH
role_ids AS (
  SELECT
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'authenticated')
      AS authenticated_oid,
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'anon')
      AS anon_oid
),
table_state AS (
  SELECT
    c.relrowsecurity AS profiles_rls_enabled,
    c.relforcerowsecurity AS profiles_force_rls
  FROM pg_catalog.pg_class AS c
  WHERE c.oid = 'public.profiles'::regclass
),
policy_state AS (
  SELECT
    count(*) FILTER (
      WHERE policy.polname = 'profiles_select_own'
        AND policy.polcmd = 'r'
        AND policy.polroles = ARRAY[roles.authenticated_oid]
        AND pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
            ~ 'id = auth[.]uid[(][)]'
    ) = 1 AS profiles_select_own_ok,
    count(*) FILTER (
      WHERE policy.polname = 'profiles_select_admin'
        AND policy.polcmd = 'r'
        AND policy.polroles = ARRAY[roles.authenticated_oid]
        AND pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
            ~ 'is_admin[(][)]'
    ) = 1 AS profiles_select_admin_ok,
    count(*) FILTER (
      WHERE policy.polname = 'profiles_update_own'
        AND policy.polcmd = 'w'
        AND policy.polroles = ARRAY[roles.authenticated_oid]
        AND pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
            ~ 'id = auth[.]uid[(][)]'
        AND pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
            ~ 'id = auth[.]uid[(][)]'
    ) = 1 AS profiles_update_own_ok,
    count(*) FILTER (
      WHERE policy.polroles = ARRAY[0::oid]
         OR roles.anon_oid = ANY(policy.polroles)
    ) AS anon_applicable_policy_count
  FROM role_ids AS roles
  LEFT JOIN pg_catalog.pg_policy AS policy
    ON policy.polrelid = 'public.profiles'::regclass
),
grant_state AS (
  SELECT
    pg_catalog.has_table_privilege(
      'authenticated', 'public.profiles', 'SELECT'
    ) AS authenticated_select,
    pg_catalog.has_table_privilege(
      'authenticated', 'public.profiles', 'UPDATE'
    ) AS authenticated_table_update,
    pg_catalog.has_column_privilege(
      'authenticated', 'public.profiles', 'full_name', 'UPDATE'
    ) AS authenticated_update_full_name,
    pg_catalog.has_column_privilege(
      'authenticated', 'public.profiles', 'phone', 'UPDATE'
    ) AS authenticated_update_phone,
    pg_catalog.has_column_privilege(
      'authenticated', 'public.profiles', 'id', 'UPDATE'
    ) AS authenticated_update_id,
    pg_catalog.has_column_privilege(
      'authenticated', 'public.profiles', 'role', 'UPDATE'
    ) AS authenticated_update_role,
    pg_catalog.has_column_privilege(
      'authenticated', 'public.profiles', 'status', 'UPDATE'
    ) AS authenticated_update_status,
    pg_catalog.has_column_privilege(
      'authenticated', 'public.profiles', 'created_at', 'UPDATE'
    ) AS authenticated_update_created_at,
    pg_catalog.has_table_privilege(
      'authenticated', 'public.profiles', 'INSERT'
    ) AS authenticated_insert,
    pg_catalog.has_table_privilege(
      'authenticated', 'public.profiles', 'DELETE'
    ) AS authenticated_delete,
    pg_catalog.has_table_privilege(
      'anon', 'public.profiles', 'SELECT'
    ) AS anon_select,
    pg_catalog.has_table_privilege(
      'anon', 'public.profiles', 'INSERT'
    ) AS anon_insert,
    pg_catalog.has_table_privilege(
      'anon', 'public.profiles', 'UPDATE'
    ) AS anon_update,
    pg_catalog.has_table_privilege(
      'anon', 'public.profiles', 'DELETE'
    ) AS anon_delete
),
rpc_catalog AS (
  SELECT
    p.oid,
    p.proname,
    p.proowner,
    p.prosecdef,
    p.proconfig,
    p.proacl,
    pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n
    ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('admin_set_profile_role', 'admin_set_profile_status')
),
rpc_state AS (
  SELECT
    count(*) FILTER (
      WHERE proname = 'admin_set_profile_role'
        AND identity_arguments =
          'target_user_id uuid, new_role character varying'
    ) = 1 AS admin_set_profile_role_exists,
    coalesce(bool_and(prosecdef) FILTER (
      WHERE proname = 'admin_set_profile_role'
    ), false) AS admin_set_profile_role_security_definer,
    coalesce(bool_and(
      pg_catalog.pg_get_userbyid(proowner) = 'postgres'
    ) FILTER (
      WHERE proname = 'admin_set_profile_role'
    ), false) AS admin_set_profile_role_owner_ok,
    coalesce(bool_and(
      EXISTS (
        SELECT 1
        FROM pg_catalog.unnest(proconfig) AS config(setting)
        WHERE pg_catalog.split_part(config.setting, '=', 1) = 'search_path'
          AND pg_catalog.replace(
            pg_catalog.split_part(config.setting, '=', 2), '"', ''
          ) = ''
      )
    ) FILTER (
      WHERE proname = 'admin_set_profile_role'
    ), false) AS admin_set_profile_role_search_path_safe,
    coalesce(bool_and(
      NOT EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(
          coalesce(proacl, pg_catalog.acldefault('f', proowner))
        ) AS acl
        WHERE acl.grantee = 0
          AND acl.privilege_type = 'EXECUTE'
      )
      AND NOT pg_catalog.has_function_privilege('anon', oid, 'EXECUTE')
      AND pg_catalog.has_function_privilege('authenticated', oid, 'EXECUTE')
    ) FILTER (
      WHERE proname = 'admin_set_profile_role'
    ), false) AS admin_set_profile_role_acl_ok,
    count(*) FILTER (
      WHERE proname = 'admin_set_profile_status'
        AND identity_arguments =
          'target_user_id uuid, new_status character varying'
    ) = 1 AS admin_set_profile_status_exists,
    coalesce(bool_and(prosecdef) FILTER (
      WHERE proname = 'admin_set_profile_status'
    ), false) AS admin_set_profile_status_security_definer,
    coalesce(bool_and(
      pg_catalog.pg_get_userbyid(proowner) = 'postgres'
    ) FILTER (
      WHERE proname = 'admin_set_profile_status'
    ), false) AS admin_set_profile_status_owner_ok,
    coalesce(bool_and(
      EXISTS (
        SELECT 1
        FROM pg_catalog.unnest(proconfig) AS config(setting)
        WHERE pg_catalog.split_part(config.setting, '=', 1) = 'search_path'
          AND pg_catalog.replace(
            pg_catalog.split_part(config.setting, '=', 2), '"', ''
          ) = ''
      )
    ) FILTER (
      WHERE proname = 'admin_set_profile_status'
    ), false) AS admin_set_profile_status_search_path_safe,
    coalesce(bool_and(
      NOT EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(
          coalesce(proacl, pg_catalog.acldefault('f', proowner))
        ) AS acl
        WHERE acl.grantee = 0
          AND acl.privilege_type = 'EXECUTE'
      )
      AND NOT pg_catalog.has_function_privilege('anon', oid, 'EXECUTE')
      AND pg_catalog.has_function_privilege('authenticated', oid, 'EXECUTE')
    ) FILTER (
      WHERE proname = 'admin_set_profile_status'
    ), false) AS admin_set_profile_status_acl_ok
  FROM rpc_catalog
),
foundation_state AS (
  SELECT
    pg_catalog.to_regprocedure('public.handle_new_auth_user()') IS NOT NULL
      AS handle_new_auth_user_exists,
    pg_catalog.to_regprocedure('public.is_admin()') IS NOT NULL
      AS is_admin_exists,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger
      WHERE trigger.tgrelid = 'auth.users'::regclass
        AND trigger.tgname = 'on_auth_user_created'
        AND NOT trigger.tgisinternal
        AND trigger.tgenabled <> 'D'
        AND trigger.tgfoid = 'public.handle_new_auth_user()'::regprocedure
    ) AS on_auth_user_created_ok
),
checks AS (
  SELECT *
  FROM table_state
  CROSS JOIN policy_state
  CROSS JOIN grant_state
  CROSS JOIN rpc_state
  CROSS JOIN foundation_state
),
decision_state AS (
  SELECT
    checks.*,
    (
      profiles_rls_enabled
      AND NOT profiles_force_rls
      AND profiles_select_own_ok
      AND profiles_select_admin_ok
      AND profiles_update_own_ok
      AND anon_applicable_policy_count = 0
      AND authenticated_select
      AND NOT authenticated_table_update
      AND authenticated_update_full_name
      AND authenticated_update_phone
      AND NOT authenticated_update_id
      AND NOT authenticated_update_role
      AND NOT authenticated_update_status
      AND NOT authenticated_update_created_at
      AND NOT authenticated_insert
      AND NOT authenticated_delete
      AND NOT anon_select
      AND NOT anon_insert
      AND NOT anon_update
      AND NOT anon_delete
      AND admin_set_profile_role_exists
      AND admin_set_profile_role_security_definer
      AND admin_set_profile_role_owner_ok
      AND admin_set_profile_role_search_path_safe
      AND admin_set_profile_role_acl_ok
      AND admin_set_profile_status_exists
      AND admin_set_profile_status_security_definer
      AND admin_set_profile_status_owner_ok
      AND admin_set_profile_status_search_path_safe
      AND admin_set_profile_status_acl_ok
      AND handle_new_auth_user_exists
      AND is_admin_exists
      AND on_auth_user_created_ok
    ) AS postcheck_passed,
    array_remove(ARRAY[
      CASE WHEN NOT profiles_rls_enabled THEN 'PROFILES_RLS_DISABLED' END,
      CASE WHEN profiles_force_rls THEN 'PROFILES_FORCE_RLS_ENABLED' END,
      CASE WHEN NOT profiles_select_own_ok THEN 'PROFILES_SELECT_OWN_INVALID' END,
      CASE WHEN NOT profiles_select_admin_ok THEN 'PROFILES_SELECT_ADMIN_INVALID' END,
      CASE WHEN NOT profiles_update_own_ok THEN 'PROFILES_UPDATE_OWN_INVALID' END,
      CASE WHEN anon_applicable_policy_count <> 0 THEN 'ANON_APPLICABLE_POLICY_EXISTS' END,
      CASE WHEN NOT authenticated_select THEN 'AUTHENTICATED_SELECT_MISSING' END,
      CASE WHEN authenticated_table_update THEN 'AUTHENTICATED_TABLE_UPDATE_PRESENT' END,
      CASE WHEN NOT authenticated_update_full_name THEN 'FULL_NAME_UPDATE_MISSING' END,
      CASE WHEN NOT authenticated_update_phone THEN 'PHONE_UPDATE_MISSING' END,
      CASE WHEN authenticated_update_id THEN 'ID_UPDATE_PRESENT' END,
      CASE WHEN authenticated_update_role THEN 'ROLE_UPDATE_PRESENT' END,
      CASE WHEN authenticated_update_status THEN 'STATUS_UPDATE_PRESENT' END,
      CASE WHEN authenticated_update_created_at THEN 'CREATED_AT_UPDATE_PRESENT' END,
      CASE WHEN authenticated_insert THEN 'AUTHENTICATED_INSERT_PRESENT' END,
      CASE WHEN authenticated_delete THEN 'AUTHENTICATED_DELETE_PRESENT' END,
      CASE WHEN anon_select OR anon_insert OR anon_update OR anon_delete
        THEN 'ANON_TABLE_PRIVILEGE_PRESENT' END,
      CASE WHEN NOT admin_set_profile_role_exists THEN 'ROLE_RPC_MISSING' END,
      CASE WHEN NOT admin_set_profile_role_security_definer THEN 'ROLE_RPC_NOT_SECURITY_DEFINER' END,
      CASE WHEN NOT admin_set_profile_role_owner_ok THEN 'ROLE_RPC_OWNER_INVALID' END,
      CASE WHEN NOT admin_set_profile_role_search_path_safe THEN 'ROLE_RPC_SEARCH_PATH_UNSAFE' END,
      CASE WHEN NOT admin_set_profile_role_acl_ok THEN 'ROLE_RPC_ACL_INVALID' END,
      CASE WHEN NOT admin_set_profile_status_exists THEN 'STATUS_RPC_MISSING' END,
      CASE WHEN NOT admin_set_profile_status_security_definer THEN 'STATUS_RPC_NOT_SECURITY_DEFINER' END,
      CASE WHEN NOT admin_set_profile_status_owner_ok THEN 'STATUS_RPC_OWNER_INVALID' END,
      CASE WHEN NOT admin_set_profile_status_search_path_safe THEN 'STATUS_RPC_SEARCH_PATH_UNSAFE' END,
      CASE WHEN NOT admin_set_profile_status_acl_ok THEN 'STATUS_RPC_ACL_INVALID' END,
      CASE WHEN NOT handle_new_auth_user_exists THEN 'FOUNDATION_HANDLER_MISSING' END,
      CASE WHEN NOT is_admin_exists THEN 'FOUNDATION_IS_ADMIN_MISSING' END,
      CASE WHEN NOT on_auth_user_created_ok THEN 'FOUNDATION_TRIGGER_INVALID' END
    ], NULL) AS blocking_reasons
  FROM checks
)
SELECT jsonb_build_object(
  'profiles_rls_enabled', profiles_rls_enabled,
  'profiles_force_rls', profiles_force_rls,
  'profiles_select_own_ok', profiles_select_own_ok,
  'profiles_select_admin_ok', profiles_select_admin_ok,
  'profiles_update_own_ok', profiles_update_own_ok,
  'anon_applicable_policy_count', anon_applicable_policy_count,
  'authenticated_select', authenticated_select,
  'authenticated_table_update', authenticated_table_update,
  'authenticated_update_full_name', authenticated_update_full_name,
  'authenticated_update_phone', authenticated_update_phone,
  'authenticated_update_id', authenticated_update_id,
  'authenticated_update_role', authenticated_update_role,
  'authenticated_update_status', authenticated_update_status,
  'authenticated_update_created_at', authenticated_update_created_at,
  'authenticated_insert', authenticated_insert,
  'authenticated_delete', authenticated_delete,
  'anon_select', anon_select,
  'anon_insert', anon_insert,
  'anon_update', anon_update,
  'anon_delete', anon_delete,
  'admin_set_profile_role_exists', admin_set_profile_role_exists,
  'admin_set_profile_role_security_definer', admin_set_profile_role_security_definer,
  'admin_set_profile_role_owner_ok', admin_set_profile_role_owner_ok,
  'admin_set_profile_role_search_path_safe', admin_set_profile_role_search_path_safe,
  'admin_set_profile_role_acl_ok', admin_set_profile_role_acl_ok,
  'admin_set_profile_status_exists', admin_set_profile_status_exists,
  'admin_set_profile_status_security_definer', admin_set_profile_status_security_definer,
  'admin_set_profile_status_owner_ok', admin_set_profile_status_owner_ok,
  'admin_set_profile_status_search_path_safe', admin_set_profile_status_search_path_safe,
  'admin_set_profile_status_acl_ok', admin_set_profile_status_acl_ok,
  'handle_new_auth_user_exists', handle_new_auth_user_exists,
  'is_admin_exists', is_admin_exists,
  'on_auth_user_created_ok', on_auth_user_created_ok,
  'decision', CASE
    WHEN postcheck_passed THEN 'POSTCHECK_PASSED'
    ELSE 'POSTCHECK_FAILED'
  END,
  'blocking_reasons', to_jsonb(blocking_reasons)
) AS profiles_rls_postcheck
FROM decision_state;

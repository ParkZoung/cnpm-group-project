-- ============================================================================
-- GoStay - Profiles RLS and Privilege Hardening
-- ============================================================================
-- The first admin is NOT provisioned by this migration.
-- After a real Auth user has been created and verified, postgres must explicitly
-- promote that user's existing profile through a separately approved operation.
-- No email, UUID, metadata role, or inferred identity is used here.
-- ============================================================================

-- Preconditions: Foundation must be intact and target policy/RPC names must be free.
DO $preconditions$
BEGIN
  IF pg_catalog.to_regprocedure('public.handle_new_auth_user()') IS NULL
     OR pg_catalog.to_regprocedure('public.is_admin()') IS NULL
  THEN
    RAISE EXCEPTION 'Profiles hardening stopped: Auth/Profile Foundation is incomplete.';
  END IF;

  IF NOT (
    SELECT p.prosecdef
    FROM pg_catalog.pg_proc AS p
    WHERE p.oid = 'public.is_admin()'::regprocedure
  )
  THEN
    RAISE EXCEPTION 'Profiles hardening stopped: public.is_admin() is not SECURITY DEFINER.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy AS policy
    WHERE policy.polrelid = 'public.profiles'::regclass
      AND policy.polname IN (
        'profiles_select_own',
        'profiles_select_admin',
        'profiles_update_own'
      )
  )
  THEN
    RAISE EXCEPTION 'Profiles hardening stopped: a target policy name already exists.';
  END IF;

  IF pg_catalog.to_regprocedure(
       'public.admin_set_profile_role(uuid,character varying)'
     ) IS NOT NULL
     OR pg_catalog.to_regprocedure(
       'public.admin_set_profile_status(uuid,character varying)'
     ) IS NOT NULL
  THEN
    RAISE EXCEPTION 'Profiles hardening stopped: a target admin RPC already exists.';
  END IF;
END;
$preconditions$;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles NO FORCE ROW LEVEL SECURITY;

CREATE POLICY profiles_select_own
ON public.profiles
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (id = auth.uid());

CREATE POLICY profiles_select_admin
ON public.profiles
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (public.is_admin());

CREATE POLICY profiles_update_own
ON public.profiles
AS PERMISSIVE
FOR UPDATE
TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- Remove broad and inherited frontend access, including known column grants.
REVOKE ALL PRIVILEGES ON TABLE public.profiles FROM PUBLIC;
REVOKE ALL PRIVILEGES ON TABLE public.profiles FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.profiles FROM authenticated;

REVOKE ALL PRIVILEGES (
  id,
  full_name,
  phone,
  role,
  status,
  created_at
) ON TABLE public.profiles FROM PUBLIC;
REVOKE ALL PRIVILEGES (
  id,
  full_name,
  phone,
  role,
  status,
  created_at
) ON TABLE public.profiles FROM anon;
REVOKE ALL PRIVILEGES (
  id,
  full_name,
  phone,
  role,
  status,
  created_at
) ON TABLE public.profiles FROM authenticated;

GRANT SELECT ON TABLE public.profiles TO authenticated;
GRANT UPDATE (full_name, phone) ON TABLE public.profiles TO authenticated;

-- Narrow role-management RPC. It never accepts a caller ID.
CREATE FUNCTION public.admin_set_profile_role(
  target_user_id uuid,
  new_role character varying
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  target_current_role character varying;
  target_current_status character varying;
  active_admin_count bigint;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required.'
      USING ERRCODE = '42501';
  END IF;

  IF new_role IS NULL OR new_role NOT IN ('customer', 'admin') THEN
    RAISE EXCEPTION 'Invalid profile role.'
      USING ERRCODE = '22023';
  END IF;

  -- Shared lock key serializes all role/status changes affecting admin continuity.
  PERFORM pg_catalog.pg_advisory_xact_lock(270720260031);

  SELECT p.role, p.status
  INTO target_current_role, target_current_status
  FROM public.profiles AS p
  WHERE p.id = target_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target profile does not exist.'
      USING ERRCODE = 'P0002';
  END IF;

  IF target_current_role = 'admin'
     AND target_current_status = 'active'
     AND new_role <> 'admin'
  THEN
    SELECT count(*)
    INTO active_admin_count
    FROM public.profiles AS p
    WHERE p.role = 'admin'
      AND p.status = 'active';

    IF active_admin_count <= 1 THEN
      RAISE EXCEPTION 'Cannot demote the last active admin.'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  UPDATE public.profiles AS p
  SET role = new_role
  WHERE p.id = target_user_id;
END;
$function$;

ALTER FUNCTION public.admin_set_profile_role(uuid, character varying)
OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION
  public.admin_set_profile_role(uuid, character varying)
FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION
  public.admin_set_profile_role(uuid, character varying)
FROM anon;
REVOKE EXECUTE ON FUNCTION
  public.admin_set_profile_role(uuid, character varying)
FROM authenticated;
GRANT EXECUTE ON FUNCTION
  public.admin_set_profile_role(uuid, character varying)
TO authenticated;

-- Narrow status-management RPC. It shares the continuity lock with role changes.
CREATE FUNCTION public.admin_set_profile_status(
  target_user_id uuid,
  new_status character varying
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  target_current_role character varying;
  target_current_status character varying;
  active_admin_count bigint;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required.'
      USING ERRCODE = '42501';
  END IF;

  IF new_status IS NULL
     OR new_status NOT IN ('active', 'inactive', 'blocked')
  THEN
    RAISE EXCEPTION 'Invalid profile status.'
      USING ERRCODE = '22023';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(270720260031);

  SELECT p.role, p.status
  INTO target_current_role, target_current_status
  FROM public.profiles AS p
  WHERE p.id = target_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target profile does not exist.'
      USING ERRCODE = 'P0002';
  END IF;

  IF target_current_role = 'admin'
     AND target_current_status = 'active'
     AND new_status <> 'active'
  THEN
    SELECT count(*)
    INTO active_admin_count
    FROM public.profiles AS p
    WHERE p.role = 'admin'
      AND p.status = 'active';

    IF active_admin_count <= 1 THEN
      RAISE EXCEPTION 'Cannot deactivate or block the last active admin.'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  UPDATE public.profiles AS p
  SET status = new_status
  WHERE p.id = target_user_id;
END;
$function$;

ALTER FUNCTION public.admin_set_profile_status(uuid, character varying)
OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION
  public.admin_set_profile_status(uuid, character varying)
FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION
  public.admin_set_profile_status(uuid, character varying)
FROM anon;
REVOKE EXECUTE ON FUNCTION
  public.admin_set_profile_status(uuid, character varying)
FROM authenticated;
GRANT EXECUTE ON FUNCTION
  public.admin_set_profile_status(uuid, character varying)
TO authenticated;

-- Postconditions: fail the migration if RLS, policies, grants, RPC security,
-- or Foundation objects differ from the approved design.
DO $postconditions$
DECLARE
  role_rpc_oid oid :=
    'public.admin_set_profile_role(uuid,character varying)'::regprocedure::oid;
  status_rpc_oid oid :=
    'public.admin_set_profile_status(uuid,character varying)'::regprocedure::oid;
  authenticated_oid oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'authenticated');
  anon_oid oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'anon');
BEGIN
  IF NOT (
    SELECT c.relrowsecurity AND NOT c.relforcerowsecurity
    FROM pg_catalog.pg_class AS c
    WHERE c.oid = 'public.profiles'::regclass
  )
  THEN
    RAISE EXCEPTION 'Profiles hardening verification failed: RLS state is incorrect.';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_policy AS policy
    WHERE policy.polrelid = 'public.profiles'::regclass
      AND policy.polname IN (
        'profiles_select_own',
        'profiles_select_admin',
        'profiles_update_own'
      )
  ) <> 3
  THEN
    RAISE EXCEPTION 'Profiles hardening verification failed: policy count is incorrect.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy AS policy
    WHERE policy.polrelid = 'public.profiles'::regclass
      AND policy.polname = 'profiles_select_own'
      AND policy.polcmd = 'r'
      AND policy.polroles = ARRAY[authenticated_oid]
      AND pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
          ~ 'id = auth[.]uid[(][)]'
  )
  OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy AS policy
    WHERE policy.polrelid = 'public.profiles'::regclass
      AND policy.polname = 'profiles_select_admin'
      AND policy.polcmd = 'r'
      AND policy.polroles = ARRAY[authenticated_oid]
      AND pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
          ~ 'is_admin[(][)]'
  )
  OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy AS policy
    WHERE policy.polrelid = 'public.profiles'::regclass
      AND policy.polname = 'profiles_update_own'
      AND policy.polcmd = 'w'
      AND policy.polroles = ARRAY[authenticated_oid]
      AND pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
          ~ 'id = auth[.]uid[(][)]'
      AND pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
          ~ 'id = auth[.]uid[(][)]'
  )
  THEN
    RAISE EXCEPTION 'Profiles hardening verification failed: policy definition is incorrect.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy AS policy
    WHERE policy.polrelid = 'public.profiles'::regclass
      AND (policy.polroles = ARRAY[0::oid] OR anon_oid = ANY(policy.polroles))
  )
  THEN
    RAISE EXCEPTION 'Profiles hardening verification failed: anon-applicable policy exists.';
  END IF;

  IF pg_catalog.has_table_privilege('authenticated', 'public.profiles', 'UPDATE')
     OR pg_catalog.has_table_privilege('authenticated', 'public.profiles', 'INSERT')
     OR pg_catalog.has_table_privilege('authenticated', 'public.profiles', 'DELETE')
     OR pg_catalog.has_table_privilege('anon', 'public.profiles', 'SELECT')
     OR pg_catalog.has_table_privilege('anon', 'public.profiles', 'INSERT')
     OR pg_catalog.has_table_privilege('anon', 'public.profiles', 'UPDATE')
     OR pg_catalog.has_table_privilege('anon', 'public.profiles', 'DELETE')
  THEN
    RAISE EXCEPTION 'Profiles hardening verification failed: broad frontend table privilege exists.';
  END IF;

  IF NOT pg_catalog.has_table_privilege('authenticated', 'public.profiles', 'SELECT')
     OR NOT pg_catalog.has_column_privilege(
       'authenticated', 'public.profiles', 'full_name', 'UPDATE'
     )
     OR NOT pg_catalog.has_column_privilege(
       'authenticated', 'public.profiles', 'phone', 'UPDATE'
     )
     OR pg_catalog.has_column_privilege(
       'authenticated', 'public.profiles', 'id', 'UPDATE'
     )
     OR pg_catalog.has_column_privilege(
       'authenticated', 'public.profiles', 'role', 'UPDATE'
     )
     OR pg_catalog.has_column_privilege(
       'authenticated', 'public.profiles', 'status', 'UPDATE'
     )
     OR pg_catalog.has_column_privilege(
       'authenticated', 'public.profiles', 'created_at', 'UPDATE'
     )
  THEN
    RAISE EXCEPTION 'Profiles hardening verification failed: column privileges are incorrect.';
  END IF;

  IF pg_catalog.to_regprocedure('public.handle_new_auth_user()') IS NULL
     OR pg_catalog.to_regprocedure('public.is_admin()') IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_trigger AS trigger
       WHERE trigger.tgrelid = 'auth.users'::regclass
         AND trigger.tgname = 'on_auth_user_created'
         AND NOT trigger.tgisinternal
         AND trigger.tgenabled <> 'D'
         AND trigger.tgfoid = 'public.handle_new_auth_user()'::regprocedure
     )
  THEN
    RAISE EXCEPTION 'Profiles hardening verification failed: Foundation object is missing.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS p
    WHERE p.oid IN (role_rpc_oid, status_rpc_oid)
      AND (
        NOT p.prosecdef
        OR pg_catalog.pg_get_userbyid(p.proowner) <> 'postgres'
        OR NOT EXISTS (
          SELECT 1
          FROM pg_catalog.unnest(p.proconfig) AS config(setting)
          WHERE pg_catalog.split_part(config.setting, '=', 1) = 'search_path'
            AND pg_catalog.replace(
              pg_catalog.split_part(config.setting, '=', 2), '"', ''
            ) = ''
        )
      )
  )
  THEN
    RAISE EXCEPTION 'Profiles hardening verification failed: RPC security is incorrect.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS p
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
    ) AS acl
    WHERE p.oid IN (role_rpc_oid, status_rpc_oid)
      AND acl.privilege_type = 'EXECUTE'
      AND acl.grantee = 0
  )
  OR pg_catalog.has_function_privilege('anon', role_rpc_oid, 'EXECUTE')
  OR pg_catalog.has_function_privilege('anon', status_rpc_oid, 'EXECUTE')
  OR NOT pg_catalog.has_function_privilege('authenticated', role_rpc_oid, 'EXECUTE')
  OR NOT pg_catalog.has_function_privilege('authenticated', status_rpc_oid, 'EXECUTE')
  THEN
    RAISE EXCEPTION 'Profiles hardening verification failed: RPC ACL is incorrect.';
  END IF;
END;
$postconditions$;

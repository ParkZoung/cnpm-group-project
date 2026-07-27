-- ============================================================================
-- GoStay - Auth/Profile Foundation
-- ============================================================================
-- Scope:
--   - Create one public.profiles row for every newly created Auth user.
--   - Create a safe current-caller admin helper for later RLS policies.
--
-- This migration intentionally does not enable RLS or create RLS policies.
-- It does not infer authority from email or Auth metadata.
-- ============================================================================

-- Trigger function for new Auth users.
-- Only full_name and phone are read from the metadata allowlist.
-- Role and status are fixed database literals.
CREATE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  INSERT INTO public.profiles (
    id,
    full_name,
    phone,
    role,
    status
  )
  VALUES (
    NEW.id,
    nullif(pg_catalog.btrim(NEW.raw_user_meta_data ->> 'full_name'), ''),
    nullif(pg_catalog.btrim(NEW.raw_user_meta_data ->> 'phone'), ''),
    'customer',
    'active'
  );

  RETURN NEW;
END;
$function$;

ALTER FUNCTION public.handle_new_auth_user() OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.handle_new_auth_user() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.handle_new_auth_user() FROM anon;
REVOKE EXECUTE ON FUNCTION public.handle_new_auth_user() FROM authenticated;

-- The database invokes this trigger function after an Auth user is created.
-- A profile failure aborts the same transaction instead of leaving an orphan user.
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_auth_user();

-- Current-caller admin helper for future RLS policies.
-- It accepts no caller-supplied user ID and returns false for anon, missing,
-- inactive, blocked, or customer profiles.
CREATE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT coalesce(
    EXISTS (
      SELECT 1
      FROM public.profiles AS p
      WHERE p.id = auth.uid()
        AND p.role = 'admin'
        AND p.status = 'active'
    ),
    false
  );
$function$;

ALTER FUNCTION public.is_admin() OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.is_admin() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.is_admin() FROM anon;
REVOKE EXECUTE ON FUNCTION public.is_admin() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

-- Deployment assertions for owner, SECURITY DEFINER, fixed search_path,
-- signatures, and explicit function privileges.
DO $verification$
DECLARE
  handle_oid oid := 'public.handle_new_auth_user()'::regprocedure::oid;
  admin_oid oid := 'public.is_admin()'::regprocedure::oid;
BEGIN
  IF pg_catalog.pg_get_userbyid(
       (SELECT p.proowner FROM pg_catalog.pg_proc AS p WHERE p.oid = handle_oid)
     ) <> 'postgres'
     OR pg_catalog.pg_get_userbyid(
       (SELECT p.proowner FROM pg_catalog.pg_proc AS p WHERE p.oid = admin_oid)
     ) <> 'postgres'
  THEN
    RAISE EXCEPTION 'Auth/Profile Foundation verification failed: unexpected function owner.';
  END IF;

  IF NOT (SELECT p.prosecdef FROM pg_catalog.pg_proc AS p WHERE p.oid = handle_oid)
     OR NOT (SELECT p.prosecdef FROM pg_catalog.pg_proc AS p WHERE p.oid = admin_oid)
  THEN
    RAISE EXCEPTION 'Auth/Profile Foundation verification failed: SECURITY DEFINER is required.';
  END IF;

  IF NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS p
       CROSS JOIN LATERAL pg_catalog.unnest(p.proconfig) AS config(setting)
       WHERE p.oid = handle_oid
         AND pg_catalog.split_part(config.setting, '=', 1) = 'search_path'
         AND pg_catalog.replace(
           pg_catalog.split_part(config.setting, '=', 2),
           '"',
           ''
         ) = ''
     )
     OR NOT EXISTS (
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
  THEN
    RAISE EXCEPTION 'Auth/Profile Foundation verification failed: search_path is not fixed.';
  END IF;

  IF EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS p
       CROSS JOIN LATERAL pg_catalog.aclexplode(
         coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
       ) AS acl
       WHERE p.oid = handle_oid
         AND acl.grantee = 0
         AND acl.privilege_type = 'EXECUTE'
     )
     OR pg_catalog.has_function_privilege('anon', handle_oid, 'EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated', handle_oid, 'EXECUTE')
  THEN
    RAISE EXCEPTION 'Auth/Profile Foundation verification failed: trigger function is externally executable.';
  END IF;

  IF EXISTS (
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
     OR NOT pg_catalog.has_function_privilege('authenticated', admin_oid, 'EXECUTE')
  THEN
    RAISE EXCEPTION 'Auth/Profile Foundation verification failed: is_admin privileges are incorrect.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS t
    WHERE t.tgrelid = 'auth.users'::regclass
      AND t.tgname = 'on_auth_user_created'
      AND NOT t.tgisinternal
      AND t.tgfoid = handle_oid
  )
  THEN
    RAISE EXCEPTION 'Auth/Profile Foundation verification failed: Auth trigger is missing or incorrect.';
  END IF;
END;
$verification$;

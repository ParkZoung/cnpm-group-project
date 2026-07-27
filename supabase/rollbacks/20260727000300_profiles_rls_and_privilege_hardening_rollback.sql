-- ============================================================================
-- GoStay - Profiles RLS and Privilege Hardening rollback
-- ============================================================================
-- Fail-closed rollback:
--   - Keep profiles RLS enabled.
--   - Do not restore previous broad grants.
--   - Remove only this task's policies and RPCs.
--   - Preserve all profiles, Auth users, Foundation trigger, and public.is_admin().
-- ============================================================================

REVOKE ALL PRIVILEGES ON TABLE public.profiles FROM PUBLIC;
REVOKE ALL PRIVILEGES ON TABLE public.profiles FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.profiles FROM authenticated;

REVOKE EXECUTE ON FUNCTION
  public.admin_set_profile_role(uuid, character varying)
FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION
  public.admin_set_profile_status(uuid, character varying)
FROM PUBLIC, anon, authenticated;

DROP POLICY profiles_update_own ON public.profiles;
DROP POLICY profiles_select_admin ON public.profiles;
DROP POLICY profiles_select_own ON public.profiles;

DROP FUNCTION public.admin_set_profile_role(uuid, character varying);
DROP FUNCTION public.admin_set_profile_status(uuid, character varying);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles NO FORCE ROW LEVEL SECURITY;

DO $verification$
BEGIN
  IF NOT (
    SELECT c.relrowsecurity AND NOT c.relforcerowsecurity
    FROM pg_catalog.pg_class AS c
    WHERE c.oid = 'public.profiles'::regclass
  )
  THEN
    RAISE EXCEPTION 'Fail-closed rollback failed: profiles RLS state is incorrect.';
  END IF;

  IF pg_catalog.to_regprocedure('public.admin_set_profile_role(uuid,character varying)')
       IS NOT NULL
     OR pg_catalog.to_regprocedure('public.admin_set_profile_status(uuid,character varying)')
       IS NOT NULL
  THEN
    RAISE EXCEPTION 'Fail-closed rollback failed: an admin RPC still exists.';
  END IF;

  IF pg_catalog.to_regprocedure('public.handle_new_auth_user()') IS NULL
     OR pg_catalog.to_regprocedure('public.is_admin()') IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_trigger AS trigger
       WHERE trigger.tgrelid = 'auth.users'::regclass
         AND trigger.tgname = 'on_auth_user_created'
         AND NOT trigger.tgisinternal
     )
  THEN
    RAISE EXCEPTION 'Fail-closed rollback failed: Foundation object is missing.';
  END IF;
END;
$verification$;

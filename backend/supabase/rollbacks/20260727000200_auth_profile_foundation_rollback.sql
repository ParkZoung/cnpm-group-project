-- ============================================================================
-- GoStay - Auth/Profile Foundation rollback
-- ============================================================================
-- This file is intentionally outside backend/supabase/migrations so it is not applied
-- automatically after the foundation migration.
--
-- Rollback removes only the trigger and functions introduced by foundation.
-- Existing Auth users and public.profiles data are preserved.
-- ============================================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_auth_user();
DROP FUNCTION IF EXISTS public.is_admin();

-- Rollback verification.
DO $verification$
BEGIN
  IF pg_catalog.to_regprocedure('public.handle_new_auth_user()') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.is_admin()') IS NOT NULL
  THEN
    RAISE EXCEPTION 'Auth/Profile Foundation rollback failed: a function still exists.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS t
    WHERE t.tgrelid = 'auth.users'::regclass
      AND t.tgname = 'on_auth_user_created'
      AND NOT t.tgisinternal
  )
  THEN
    RAISE EXCEPTION 'Auth/Profile Foundation rollback failed: trigger still exists.';
  END IF;
END;
$verification$;

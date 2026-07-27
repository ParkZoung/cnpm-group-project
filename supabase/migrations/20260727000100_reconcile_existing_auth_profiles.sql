-- ============================================================================
-- GoStay - Reconcile existing Auth users without public profiles
-- ============================================================================
-- Scope:
--   1. Verify that the audited number of missing profiles is still exactly one.
--   2. Create a customer/active profile for every Auth user currently missing one.
--   3. Verify that no Auth user remains without a profile.
--
-- Security rules:
--   - Only full_name and phone are read from raw_user_meta_data.
--   - Role and status are fixed database literals.
--   - No authority is inferred from email or any metadata field.
--   - Existing public.profiles rows are not modified.
--   - This migration does not enable RLS and does not create foundation triggers.
-- ============================================================================

-- Precondition:
-- The approved preflight found exactly one valid Auth user without a profile.
-- Stop immediately if the database has drifted since that audit.
DO $precondition$
DECLARE
  missing_profile_count bigint;
BEGIN
  SELECT count(*)
  INTO missing_profile_count
  FROM auth.users AS u
  LEFT JOIN public.profiles AS p
    ON p.id = u.id
  WHERE p.id IS NULL;

  IF missing_profile_count <> 1 THEN
    RAISE EXCEPTION
      'Auth/Profile reconciliation stopped: expected 1 Auth user without a profile, found %.',
      missing_profile_count;
  END IF;
END;
$precondition$;

-- Controlled backfill:
-- Only Auth users without a matching profile are selected.
-- Empty allowlisted metadata strings become NULL after trimming.
-- Existing profiles cannot match the WHERE condition and remain unchanged.
INSERT INTO public.profiles (
  id,
  full_name,
  phone,
  role,
  status
)
SELECT
  u.id,
  nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
  nullif(btrim(u.raw_user_meta_data ->> 'phone'), ''),
  'customer',
  'active'
FROM auth.users AS u
LEFT JOIN public.profiles AS p
  ON p.id = u.id
WHERE p.id IS NULL;

-- Postcondition:
-- The one-to-one foundation cannot proceed while any Auth user lacks a profile.
DO $postcondition$
DECLARE
  remaining_missing_profile_count bigint;
BEGIN
  SELECT count(*)
  INTO remaining_missing_profile_count
  FROM auth.users AS u
  LEFT JOIN public.profiles AS p
    ON p.id = u.id
  WHERE p.id IS NULL;

  IF remaining_missing_profile_count <> 0 THEN
    RAISE EXCEPTION
      'Auth/Profile reconciliation failed: % Auth user(s) still have no profile.',
      remaining_missing_profile_count;
  END IF;
END;
$postcondition$;

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_list_profiles_with_email()
RETURNS TABLE(
  id uuid,
  email text,
  full_name character varying,
  phone character varying,
  role character varying,
  status character varying,
  branch_id bigint,
  branch_name character varying,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Administrator authorization is required.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    profile.id,
    auth_user.email::text,
    profile.full_name,
    profile.phone,
    profile.role,
    profile.status,
    profile.branch_id,
    branch.name,
    profile.created_at
  FROM public.profiles AS profile
  JOIN auth.users AS auth_user ON auth_user.id = profile.id
  LEFT JOIN public.branches AS branch ON branch.id = profile.branch_id
  ORDER BY profile.created_at DESC;
END;
$$;

ALTER FUNCTION public.admin_list_profiles_with_email() OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.admin_list_profiles_with_email() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_profiles_with_email() TO authenticated;

COMMIT;

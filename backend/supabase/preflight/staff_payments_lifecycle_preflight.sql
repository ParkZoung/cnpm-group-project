DO $$
BEGIN
  IF to_regclass('public.profiles') IS NULL OR to_regclass('public.bookings') IS NULL
     OR to_regclass('public.rooms') IS NULL OR to_regclass('public.branches') IS NULL THEN
    RAISE EXCEPTION 'Staff/payment lifecycle preflight failed: required tables are missing.';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name='branch_id')
     OR to_regclass('public.payment_transactions') IS NOT NULL
     OR to_regclass('public.online_checkins') IS NOT NULL THEN
    RAISE EXCEPTION 'Staff/payment lifecycle preflight failed: target objects already exist.';
  END IF;
  IF to_regprocedure('public.is_admin()') IS NULL OR to_regprocedure('public.create_booking(bigint,date,date,integer,text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'Staff/payment lifecycle preflight failed: foundation RPCs are missing.';
  END IF;
END;
$$;

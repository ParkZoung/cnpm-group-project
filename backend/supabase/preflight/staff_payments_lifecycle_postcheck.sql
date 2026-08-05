DO $$
BEGIN
  IF to_regclass('public.payment_transactions') IS NULL
     OR to_regprocedure('public.staff_check_in(uuid)') IS NULL
     OR to_regprocedure('public.staff_check_out(uuid)') IS NULL
     OR to_regprocedure('public.customer_start_online_checkin(uuid,character varying)') IS NULL
     OR to_regprocedure('public.staff_consume_checkin_token(uuid)') IS NULL
     OR to_regclass('public.online_checkins') IS NULL THEN
    RAISE EXCEPTION 'Staff/payment lifecycle postcheck failed: required objects are missing.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name='branch_id')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='bookings' AND column_name='paid_amount') THEN
    RAISE EXCEPTION 'Staff/payment lifecycle postcheck failed: required columns are missing.';
  END IF;
END;
$$;

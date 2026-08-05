BEGIN;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_staff_branch_check;
UPDATE public.profiles SET branch_id = NULL WHERE role = 'staff';
ALTER TABLE public.profiles ADD CONSTRAINT profiles_branch_deprecated_check CHECK (branch_id IS NULL);

CREATE TABLE public.staff_work_sessions (
  staff_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  branch_id bigint NOT NULL REFERENCES public.branches(id) ON DELETE RESTRICT,
  selected_at timestamptz NOT NULL DEFAULT statement_timestamp()
);
ALTER TABLE public.staff_work_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.staff_work_sessions FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.staff_select_working_branch(p_branch_id bigint)
RETURNS TABLE(branch_id bigint, branch_name character varying)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role = 'staff' AND p.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Active staff authorization required.' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.branches b WHERE b.id = p_branch_id AND b.status = 'active') THEN
    RAISE EXCEPTION 'Branch is not available.' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.staff_work_sessions(staff_id, branch_id, selected_at)
  VALUES(auth.uid(), p_branch_id, statement_timestamp())
  ON CONFLICT (staff_id) DO UPDATE
    SET branch_id = EXCLUDED.branch_id, selected_at = EXCLUDED.selected_at;
  RETURN QUERY SELECT b.id, b.name FROM public.branches b WHERE b.id = p_branch_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_staff_for_branch(p_branch_id bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    JOIN public.staff_work_sessions s ON s.staff_id = p.id
    WHERE p.id = auth.uid() AND p.role = 'staff' AND p.status = 'active'
      AND s.branch_id = p_branch_id
  );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_booking(p_booking_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.is_admin() OR EXISTS (
    SELECT 1 FROM public.bookings b
    JOIN public.rooms r ON r.id = b.room_id
    WHERE b.id = p_booking_id AND public.is_staff_for_branch(r.branch_id)
  );
$$;

CREATE OR REPLACE FUNCTION public.customer_start_online_checkin(
  p_booking_id uuid, p_payment_option character varying
)
RETURNS TABLE(online_checkin_id uuid, booking_id uuid, booking_code character varying, payment_option character varying, requested_amount bigint, expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE b public.bookings%ROWTYPE; required_amount bigint; checkin_id uuid; expiry timestamptz;
BEGIN
  SELECT * INTO b FROM public.bookings
  WHERE id = p_booking_id AND user_id = auth.uid() FOR UPDATE;
  IF NOT FOUND OR b.booking_status <> 'confirmed' OR b.paid_amount <> 0 THEN
    RAISE EXCEPTION 'Booking is not eligible for online check-in.' USING ERRCODE = 'P0001';
  END IF;
  IF (statement_timestamp() AT TIME ZONE 'Asia/Bangkok')::date >= b.check_out_date THEN
    RAISE EXCEPTION 'Online check-in is no longer available.' USING ERRCODE = 'P0001';
  END IF;
  IF p_payment_option NOT IN ('full', 'deposit') OR (b.number_of_nights = 1 AND p_payment_option <> 'full') THEN
    RAISE EXCEPTION 'Invalid payment option.' USING ERRCODE = '22023';
  END IF;
  required_amount := CASE WHEN p_payment_option = 'full' THEN b.total_amount
    ELSE round(b.price_per_night::numeric * (100 + b.tax_rate) / 100)::bigint END;
  UPDATE public.bookings SET payment_option = p_payment_option,
    upfront_amount = required_amount, payment_method = 'online', payment_status = 'unpaid'
  WHERE id = b.id;
  expiry := (b.check_out_date::timestamp AT TIME ZONE 'Asia/Bangkok');
  INSERT INTO public.online_checkins(booking_id,status,payment_option,requested_amount,expires_at,rejection_reason,updated_at)
  VALUES(b.id,'not_started',p_payment_option,required_amount,expiry,NULL,statement_timestamp())
  ON CONFLICT ON CONSTRAINT online_checkins_booking_id_key DO UPDATE SET status='not_started',payment_option=EXCLUDED.payment_option,
    requested_amount=EXCLUDED.requested_amount,expires_at=EXCLUDED.expires_at,rejection_reason=NULL,
    payment_claimed_at=NULL,reviewed_at=NULL,reviewed_by=NULL,updated_at=statement_timestamp()
  WHERE public.online_checkins.status IN ('not_started','rejected')
  RETURNING id INTO checkin_id;
  IF checkin_id IS NULL THEN RAISE EXCEPTION 'Online check-in is already being processed.' USING ERRCODE='P0001'; END IF;
  RETURN QUERY SELECT checkin_id,b.id,b.booking_code,p_payment_option,required_amount,expiry;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_assign_profile_access(target_user_id uuid, new_role character varying, new_branch_id bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE current_role character varying; current_status character varying; active_admins bigint;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required.' USING ERRCODE='42501'; END IF;
  IF new_role NOT IN ('customer','staff','admin') THEN
    RAISE EXCEPTION 'Invalid role.' USING ERRCODE='22023';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(270720260031);
  SELECT role,status INTO current_role,current_status FROM public.profiles WHERE id=target_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Target profile does not exist.' USING ERRCODE='P0002'; END IF;
  IF current_role='admin' AND current_status='active' AND new_role<>'admin' THEN
    SELECT count(*) INTO active_admins FROM public.profiles WHERE role='admin' AND status='active';
    IF active_admins <= 1 THEN RAISE EXCEPTION 'Cannot demote the last active admin.' USING ERRCODE='23514'; END IF;
  END IF;
  UPDATE public.profiles SET role=new_role, branch_id=NULL WHERE id=target_user_id;
  IF new_role <> 'staff' THEN DELETE FROM public.staff_work_sessions WHERE staff_id=target_user_id; END IF;
END;
$$;

ALTER FUNCTION public.staff_select_working_branch(bigint) OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.staff_select_working_branch(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.staff_select_working_branch(bigint) TO authenticated;

COMMIT;

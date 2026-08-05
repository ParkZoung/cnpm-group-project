BEGIN;

-- Staff assignment and role expansion.
ALTER TABLE public.profiles ADD COLUMN branch_id bigint REFERENCES public.branches(id) ON DELETE RESTRICT;

DO $block$
DECLARE constraint_name text;
BEGIN
  SELECT con.conname INTO constraint_name
  FROM pg_catalog.pg_constraint con
  WHERE con.conrelid = 'public.profiles'::regclass
    AND con.contype = 'c'
    AND pg_catalog.pg_get_constraintdef(con.oid) ILIKE '%role%customer%admin%'
  LIMIT 1;
  IF constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.profiles DROP CONSTRAINT %I', constraint_name);
  END IF;
END;
$block$;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check CHECK (role IN ('customer', 'staff', 'admin')),
  ADD CONSTRAINT profiles_staff_branch_check CHECK (
    (role = 'staff' AND branch_id IS NOT NULL) OR
    (role <> 'staff' AND branch_id IS NULL)
  );

-- Booking payment snapshot and lifecycle audit.
ALTER TABLE public.bookings
  ADD COLUMN payment_option character varying,
  ADD COLUMN upfront_amount bigint NOT NULL DEFAULT 0,
  ADD COLUMN paid_amount bigint NOT NULL DEFAULT 0,
  ADD COLUMN checked_in_at timestamptz,
  ADD COLUMN checked_in_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  ADD COLUMN checked_out_at timestamptz,
  ADD COLUMN checked_out_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT;

UPDATE public.bookings
SET payment_option = CASE WHEN payment_status = 'paid' THEN 'full' ELSE NULL END,
    upfront_amount = CASE WHEN payment_status = 'paid' THEN total_amount ELSE 0 END,
    paid_amount = CASE WHEN payment_status = 'paid' THEN total_amount ELSE 0 END;

ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_payment_option_check CHECK (payment_option IS NULL OR payment_option IN ('full', 'deposit')),
  ADD CONSTRAINT bookings_payment_amounts_check CHECK (
    upfront_amount >= 0 AND paid_amount >= 0 AND paid_amount <= total_amount
  ),
  ADD CONSTRAINT bookings_checkin_audit_check CHECK (
    (checked_in_at IS NULL) = (checked_in_by IS NULL)
  ),
  ADD CONSTRAINT bookings_checkout_audit_check CHECK (
    (checked_out_at IS NULL) = (checked_out_by IS NULL)
  );

DO $block$
DECLARE constraint_name text;
BEGIN
  SELECT con.conname INTO constraint_name
  FROM pg_catalog.pg_constraint con
  WHERE con.conrelid = 'public.bookings'::regclass
    AND con.contype = 'c'
    AND pg_catalog.pg_get_constraintdef(con.oid) ILIKE '%payment_status%unpaid%pending%paid%'
  LIMIT 1;
  IF constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.bookings DROP CONSTRAINT %I', constraint_name);
  END IF;
END;
$block$;

ALTER TABLE public.bookings ADD CONSTRAINT bookings_payment_status_check
  CHECK (payment_status IN ('unpaid', 'pending', 'partially_paid', 'paid', 'failed', 'refunded'));

CREATE TABLE public.payment_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES public.bookings(id) ON DELETE RESTRICT,
  transaction_type character varying NOT NULL CHECK (transaction_type IN ('online_payment', 'staff_collection', 'refund')),
  amount bigint NOT NULL CHECK (amount > 0),
  status character varying NOT NULL CHECK (status IN ('pending', 'succeeded', 'failed')),
  performed_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  provider_reference text,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp()
);
CREATE INDEX payment_transactions_booking_created_idx
  ON public.payment_transactions(booking_id, created_at DESC);

CREATE TABLE public.online_checkins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL UNIQUE REFERENCES public.bookings(id) ON DELETE RESTRICT,
  status character varying NOT NULL DEFAULT 'not_started'
    CHECK (status IN ('not_started','payment_claimed','approved','rejected','consumed','expired')),
  payment_option character varying CHECK (payment_option IN ('full','deposit')),
  requested_amount bigint CHECK (requested_amount > 0),
  rejection_reason text,
  payment_claimed_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  consumed_at timestamptz,
  consumed_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp()
);
CREATE INDEX online_checkins_status_created_idx ON public.online_checkins(status, created_at DESC);

CREATE OR REPLACE FUNCTION public.is_staff_for_branch(p_branch_id bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role = 'staff' AND p.status = 'active'
      AND p.branch_id = p_branch_id
  );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_booking(p_booking_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.is_admin() OR EXISTS (
    SELECT 1 FROM public.bookings b
    JOIN public.rooms r ON r.id = b.room_id
    JOIN public.profiles p ON p.id = auth.uid()
    WHERE b.id = p_booking_id AND p.role = 'staff' AND p.status = 'active'
      AND p.branch_id = r.branch_id
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
  IF (statement_timestamp() AT TIME ZONE 'Asia/Bangkok')::date < b.check_in_date - 1
     OR (statement_timestamp() AT TIME ZONE 'Asia/Bangkok')::date >= b.check_out_date THEN
    RAISE EXCEPTION 'Online check-in is not open.' USING ERRCODE = 'P0001';
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

CREATE OR REPLACE FUNCTION public.customer_claim_online_payment(p_booking_id uuid)
RETURNS TABLE(online_checkin_id uuid, online_checkin_status character varying, claimed_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE checkin_id uuid; at_time timestamptz := statement_timestamp();
BEGIN
  UPDATE public.online_checkins o SET status='payment_claimed',payment_claimed_at=at_time,
    rejection_reason=NULL,updated_at=at_time
  FROM public.bookings b WHERE o.booking_id=b.id AND b.id=p_booking_id AND b.user_id=auth.uid()
    AND b.booking_status='confirmed' AND o.status IN ('not_started','rejected') AND o.expires_at>at_time
  RETURNING o.id INTO checkin_id;
  IF checkin_id IS NULL THEN RAISE EXCEPTION 'Online payment cannot be claimed.' USING ERRCODE='P0001'; END IF;
  RETURN QUERY SELECT checkin_id,'payment_claimed'::character varying,at_time;
END;
$$;

CREATE OR REPLACE FUNCTION public.customer_get_online_checkin_payment(p_booking_id uuid)
RETURNS TABLE(booking_code character varying,requested_amount bigint,online_checkin_status character varying)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT b.booking_code,o.requested_amount,o.status
  FROM public.online_checkins o JOIN public.bookings b ON b.id=o.booking_id
  WHERE b.id=p_booking_id AND b.user_id=auth.uid() AND o.expires_at>statement_timestamp();
$$;

CREATE OR REPLACE FUNCTION public.staff_confirm_booking(p_booking_id uuid)
RETURNS TABLE(booking_id uuid, booking_status character varying) LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NOT public.can_manage_booking(p_booking_id) THEN RAISE EXCEPTION 'Staff authorization required.' USING ERRCODE='42501'; END IF;
  UPDATE public.bookings AS booking
  SET booking_status='confirmed'
  WHERE booking.id=p_booking_id AND booking.booking_status='pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'Booking cannot be confirmed.' USING ERRCODE='P0001'; END IF;
  RETURN QUERY SELECT p_booking_id,'confirmed'::character varying;
END; $$;

CREATE OR REPLACE FUNCTION public.staff_review_online_payment(p_booking_id uuid, p_approve boolean, p_rejection_reason text DEFAULT NULL)
RETURNS TABLE(online_checkin_id uuid, online_checkin_status character varying, paid_amount bigint, payment_status character varying)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE b public.bookings%ROWTYPE; o public.online_checkins%ROWTYPE; new_paid bigint; new_payment character varying;
BEGIN
  IF NOT public.can_manage_booking(p_booking_id) THEN RAISE EXCEPTION 'Staff authorization required.' USING ERRCODE='42501'; END IF;
  SELECT * INTO b FROM public.bookings WHERE id=p_booking_id FOR UPDATE;
  SELECT * INTO o FROM public.online_checkins WHERE booking_id=p_booking_id FOR UPDATE;
  IF NOT FOUND OR o.status<>'payment_claimed' OR o.expires_at<=statement_timestamp() THEN
    RAISE EXCEPTION 'Online payment claim cannot be reviewed.' USING ERRCODE='P0001';
  END IF;
  IF NOT p_approve THEN
    UPDATE public.online_checkins SET status='rejected',rejection_reason=nullif(btrim(p_rejection_reason),''),
      reviewed_at=statement_timestamp(),reviewed_by=auth.uid(),updated_at=statement_timestamp() WHERE id=o.id;
    RETURN QUERY SELECT o.id,'rejected'::character varying,b.paid_amount,b.payment_status; RETURN;
  END IF;
  new_paid := b.paid_amount + o.requested_amount;
  IF new_paid>b.total_amount THEN RAISE EXCEPTION 'Payment exceeds booking balance.' USING ERRCODE='P0001'; END IF;
  new_payment := CASE WHEN new_paid=b.total_amount THEN 'paid' ELSE 'partially_paid' END;
  INSERT INTO public.payment_transactions(booking_id,transaction_type,amount,status,performed_by,provider_reference)
  VALUES(b.id,'online_payment',o.requested_amount,'succeeded',auth.uid(),b.booking_code);
  UPDATE public.bookings SET paid_amount=new_paid,payment_status=new_payment WHERE id=b.id;
  UPDATE public.online_checkins SET status='approved',reviewed_at=statement_timestamp(),reviewed_by=auth.uid(),
    rejection_reason=NULL,updated_at=statement_timestamp() WHERE id=o.id;
  RETURN QUERY SELECT o.id,'approved'::character varying,new_paid,new_payment;
END; $$;

CREATE OR REPLACE FUNCTION public.staff_lookup_checkin_token(p_token uuid)
RETURNS TABLE(booking_id uuid,booking_code character varying,guest_name character varying,room_id bigint,online_checkin_status character varying,expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  RETURN QUERY SELECT b.id,b.booking_code,b.guest_name,b.room_id,o.status,o.expires_at
  FROM public.online_checkins o JOIN public.bookings b ON b.id=o.booking_id
  WHERE o.id=p_token AND public.can_manage_booking(b.id);
END; $$;

CREATE OR REPLACE FUNCTION public.staff_consume_checkin_token(p_token uuid)
RETURNS TABLE(booking_id uuid,booking_status character varying,checked_in_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o public.online_checkins%ROWTYPE; b public.bookings%ROWTYPE; at_time timestamptz:=statement_timestamp();
BEGIN
  SELECT * INTO o FROM public.online_checkins WHERE id=p_token FOR UPDATE;
  IF NOT FOUND OR NOT public.can_manage_booking(o.booking_id) OR o.status<>'approved' OR o.expires_at<=at_time THEN
    RAISE EXCEPTION 'Check-in credential is invalid, expired, or already used.' USING ERRCODE='P0001';
  END IF;
  SELECT * INTO b FROM public.bookings WHERE id=o.booking_id FOR UPDATE;
  IF b.booking_status<>'confirmed' OR b.paid_amount<b.upfront_amount
     OR (at_time AT TIME ZONE 'Asia/Bangkok')::date < b.check_in_date
     OR (at_time AT TIME ZONE 'Asia/Bangkok')::date >= b.check_out_date THEN
    RAISE EXCEPTION 'Booking is not eligible for check-in.' USING ERRCODE='P0001';
  END IF;
  UPDATE public.bookings SET booking_status='checked_in',checked_in_at=at_time,checked_in_by=auth.uid() WHERE id=b.id;
  UPDATE public.online_checkins SET status='consumed',consumed_at=at_time,consumed_by=auth.uid(),updated_at=at_time WHERE id=o.id;
  RETURN QUERY SELECT b.id,'checked_in'::character varying,at_time;
END; $$;

CREATE OR REPLACE FUNCTION public.staff_collect_balance(p_booking_id uuid)
RETURNS TABLE(booking_id uuid, paid_amount bigint, balance_amount bigint, payment_status character varying)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE b public.bookings%ROWTYPE; amount_due bigint;
BEGIN
  IF NOT public.can_manage_booking(p_booking_id) THEN RAISE EXCEPTION 'Staff authorization required.' USING ERRCODE='42501'; END IF;
  SELECT * INTO b FROM public.bookings WHERE id = p_booking_id FOR UPDATE;
  amount_due := b.total_amount - b.paid_amount;
  IF b.booking_status NOT IN ('confirmed', 'checked_in') OR amount_due <= 0 THEN
    RAISE EXCEPTION 'Booking has no collectible balance.' USING ERRCODE='P0001';
  END IF;
  INSERT INTO public.payment_transactions(booking_id, transaction_type, amount, status, performed_by)
  VALUES (b.id, 'staff_collection', amount_due, 'succeeded', auth.uid());
  UPDATE public.bookings AS booking SET paid_amount = booking.total_amount, payment_status = 'paid' WHERE id = b.id;
  RETURN QUERY SELECT b.id, b.total_amount, 0::bigint, 'paid'::character varying;
END;
$$;

CREATE OR REPLACE FUNCTION public.staff_check_in(p_booking_id uuid)
RETURNS TABLE(booking_id uuid, booking_status character varying, checked_in_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE b public.bookings%ROWTYPE; at_time timestamptz := statement_timestamp();
BEGIN
  RAISE EXCEPTION 'A valid online check-in credential is required.' USING ERRCODE='P0001';
END;
$$;

CREATE OR REPLACE FUNCTION public.staff_check_out(p_booking_id uuid)
RETURNS TABLE(booking_id uuid, booking_status character varying, checked_out_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE b public.bookings%ROWTYPE; at_time timestamptz := statement_timestamp();
BEGIN
  IF NOT public.can_manage_booking(p_booking_id) THEN RAISE EXCEPTION 'Staff authorization required.' USING ERRCODE='42501'; END IF;
  SELECT * INTO b FROM public.bookings WHERE id = p_booking_id FOR UPDATE;
  IF b.booking_status <> 'checked_in' OR b.paid_amount <> b.total_amount THEN
    RAISE EXCEPTION 'Booking is not eligible for check-out.' USING ERRCODE='P0001';
  END IF;
  UPDATE public.bookings SET booking_status='completed', checked_out_at=at_time, checked_out_by=auth.uid() WHERE id=b.id;
  RETURN QUERY SELECT b.id, 'completed'::character varying, at_time;
END;
$$;

CREATE OR REPLACE FUNCTION public.staff_record_refund(p_booking_id uuid)
RETURNS TABLE(booking_id uuid, refunded_amount bigint, payment_status character varying)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE b public.bookings%ROWTYPE;
BEGIN
  IF NOT public.can_manage_booking(p_booking_id) THEN RAISE EXCEPTION 'Staff authorization required.' USING ERRCODE='42501'; END IF;
  SELECT * INTO b FROM public.bookings WHERE id=p_booking_id FOR UPDATE;
  IF b.booking_status <> 'cancelled' OR b.paid_amount <= 0 OR b.payment_status = 'refunded' THEN
    RAISE EXCEPTION 'Booking is not eligible for refund.' USING ERRCODE='P0001';
  END IF;
  INSERT INTO public.payment_transactions(booking_id, transaction_type, amount, status, performed_by)
  VALUES(b.id, 'refund', b.paid_amount, 'succeeded', auth.uid());
  UPDATE public.bookings AS booking SET paid_amount=0, payment_status='refunded' WHERE id=b.id;
  RETURN QUERY SELECT b.id, b.paid_amount, 'refunded'::character varying;
END;
$$;

-- Preserve the existing admin RPC signatures while routing lifecycle and money
-- transitions through the new invariant-enforcing operations.
CREATE OR REPLACE FUNCTION public.admin_update_booking_status(p_booking_id uuid, p_new_status character varying)
RETURNS TABLE(booking_id uuid, old_status character varying, new_status character varying, updated_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE previous_status character varying; changed_at timestamptz;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Administrator authorization is required.' USING ERRCODE='42501'; END IF;
  SELECT booking_status INTO previous_status FROM public.bookings WHERE id=p_booking_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'The booking was not found.' USING ERRCODE='P0002'; END IF;
  IF p_new_status='checked_in' THEN
    PERFORM * FROM public.staff_check_in(p_booking_id);
  ELSIF p_new_status='completed' THEN
    PERFORM * FROM public.staff_check_out(p_booking_id);
  ELSIF (previous_status='pending' AND p_new_status IN ('confirmed','cancelled'))
     OR (previous_status='confirmed' AND p_new_status='cancelled') THEN
    UPDATE public.bookings SET booking_status=p_new_status,
      cancelled_at=CASE WHEN p_new_status='cancelled' THEN statement_timestamp() ELSE NULL END
    WHERE id=p_booking_id;
  ELSE
    RAISE EXCEPTION 'The requested booking status transition is not allowed.' USING ERRCODE='P0001';
  END IF;
  SELECT b.updated_at INTO changed_at FROM public.bookings b WHERE b.id=p_booking_id;
  RETURN QUERY SELECT p_booking_id,previous_status,p_new_status,changed_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_update_payment_status(p_booking_id uuid, p_new_payment_status character varying)
RETURNS TABLE(booking_id uuid, old_payment_status character varying, new_payment_status character varying, updated_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE previous_status character varying; changed_at timestamptz;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Administrator authorization is required.' USING ERRCODE='42501'; END IF;
  SELECT payment_status INTO previous_status FROM public.bookings WHERE id=p_booking_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'The booking was not found.' USING ERRCODE='P0002'; END IF;
  IF p_new_payment_status='paid' THEN
    PERFORM * FROM public.staff_collect_balance(p_booking_id);
  ELSIF p_new_payment_status='refunded' THEN
    PERFORM * FROM public.staff_record_refund(p_booking_id);
  ELSE
    RAISE EXCEPTION 'Use the payment workflow for monetary status changes.' USING ERRCODE='P0001';
  END IF;
  SELECT b.payment_status,b.updated_at INTO p_new_payment_status,changed_at FROM public.bookings b WHERE b.id=p_booking_id;
  RETURN QUERY SELECT p_booking_id,previous_status,p_new_payment_status,changed_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_assign_profile_access(target_user_id uuid, new_role character varying, new_branch_id bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE current_role character varying; current_status character varying; active_admins bigint;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required.' USING ERRCODE='42501'; END IF;
  IF new_role NOT IN ('customer','staff','admin') OR (new_role='staff') <> (new_branch_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Invalid role and branch assignment.' USING ERRCODE='22023';
  END IF;
  IF new_branch_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.branches WHERE id=new_branch_id) THEN
    RAISE EXCEPTION 'Branch does not exist.' USING ERRCODE='22023';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(270720260031);
  SELECT role,status INTO current_role,current_status FROM public.profiles WHERE id=target_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Target profile does not exist.' USING ERRCODE='P0002'; END IF;
  IF current_role='admin' AND current_status='active' AND new_role<>'admin' THEN
    SELECT count(*) INTO active_admins FROM public.profiles WHERE role='admin' AND status='active';
    IF active_admins <= 1 THEN RAISE EXCEPTION 'Cannot demote the last active admin.' USING ERRCODE='23514'; END IF;
  END IF;
  UPDATE public.profiles SET role=new_role, branch_id=new_branch_id WHERE id=target_user_id;
END;
$$;

ALTER TABLE public.payment_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.online_checkins ENABLE ROW LEVEL SECURITY;
CREATE POLICY payment_transactions_customer_select ON public.payment_transactions FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.bookings b WHERE b.id=booking_id AND b.user_id=auth.uid()));
CREATE POLICY payment_transactions_manager_select ON public.payment_transactions FOR SELECT TO authenticated
USING (public.can_manage_booking(booking_id));
CREATE POLICY online_checkins_customer_select ON public.online_checkins FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.bookings b WHERE b.id=booking_id AND b.user_id=auth.uid()));
CREATE POLICY online_checkins_manager_select ON public.online_checkins FOR SELECT TO authenticated
USING (public.can_manage_booking(booking_id));
CREATE POLICY bookings_select_staff ON public.bookings FOR SELECT TO authenticated
USING (public.can_manage_booking(id));

GRANT SELECT ON public.payment_transactions TO authenticated;
GRANT SELECT ON public.online_checkins TO authenticated;
REVOKE ALL ON public.payment_transactions FROM anon;
REVOKE ALL ON public.online_checkins FROM anon;

DO $grant$
DECLARE fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.is_staff_for_branch(bigint)', 'public.can_manage_booking(uuid)',
    'public.customer_start_online_checkin(uuid,character varying)',
    'public.customer_claim_online_payment(uuid)', 'public.staff_confirm_booking(uuid)',
    'public.customer_get_online_checkin_payment(uuid)',
    'public.staff_review_online_payment(uuid,boolean,text)',
    'public.staff_lookup_checkin_token(uuid)', 'public.staff_consume_checkin_token(uuid)',
    'public.staff_collect_balance(uuid)',
    'public.staff_check_in(uuid)', 'public.staff_check_out(uuid)',
    'public.staff_record_refund(uuid)',
    'public.admin_assign_profile_access(uuid,character varying,bigint)'
  ] LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO postgres', fn);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', fn);
  END LOOP;
END;
$grant$;

COMMIT;

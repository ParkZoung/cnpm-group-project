BEGIN;
DROP FUNCTION IF EXISTS public.admin_assign_profile_access(uuid,character varying,bigint);
DROP FUNCTION IF EXISTS public.staff_consume_checkin_token(uuid);
DROP FUNCTION IF EXISTS public.staff_lookup_checkin_token(uuid);
DROP FUNCTION IF EXISTS public.staff_review_online_payment(uuid,boolean,text);
DROP FUNCTION IF EXISTS public.staff_confirm_booking(uuid);
DROP FUNCTION IF EXISTS public.customer_get_online_checkin_payment(uuid);
DROP FUNCTION IF EXISTS public.customer_claim_online_payment(uuid);
DROP FUNCTION IF EXISTS public.customer_start_online_checkin(uuid,character varying);
DROP FUNCTION IF EXISTS public.staff_record_refund(uuid);
DROP FUNCTION IF EXISTS public.staff_check_out(uuid);
DROP FUNCTION IF EXISTS public.staff_check_in(uuid);
DROP FUNCTION IF EXISTS public.staff_collect_balance(uuid);
DROP FUNCTION IF EXISTS public.can_manage_booking(uuid);
DROP FUNCTION IF EXISTS public.is_staff_for_branch(bigint);
DROP TABLE IF EXISTS public.online_checkins;
DROP TABLE IF EXISTS public.payment_transactions;
UPDATE public.bookings SET payment_status = CASE
  WHEN payment_status = 'partially_paid' THEN 'unpaid'
  ELSE payment_status END;
ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_payment_status_check;
ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_checkout_audit_check;
ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_checkin_audit_check;
ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_payment_amounts_check;
ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_payment_option_check;
ALTER TABLE public.bookings DROP COLUMN IF EXISTS checked_out_by, DROP COLUMN IF EXISTS checked_out_at,
  DROP COLUMN IF EXISTS checked_in_by, DROP COLUMN IF EXISTS checked_in_at, DROP COLUMN IF EXISTS paid_amount,
  DROP COLUMN IF EXISTS upfront_amount, DROP COLUMN IF EXISTS payment_option;
ALTER TABLE public.bookings ADD CONSTRAINT bookings_payment_status_check
  CHECK (payment_status IN ('unpaid','pending','paid','failed','refunded'));
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_staff_branch_check;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
UPDATE public.profiles SET role='customer' WHERE role='staff';
ALTER TABLE public.profiles DROP COLUMN IF EXISTS branch_id;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check CHECK (role IN ('customer','admin'));

CREATE OR REPLACE FUNCTION public.admin_update_booking_status(p_booking_id uuid, p_new_status character varying)
RETURNS TABLE(booking_id uuid, old_status character varying, new_status character varying, updated_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE previous_status character varying; changed_at timestamptz;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Administrator authorization is required.' USING ERRCODE='42501'; END IF;
  SELECT booking_status INTO previous_status FROM public.bookings WHERE id=p_booking_id FOR UPDATE;
  IF NOT FOUND OR NOT ((previous_status='pending' AND p_new_status IN ('confirmed','cancelled')) OR (previous_status='confirmed' AND p_new_status IN ('checked_in','cancelled')) OR (previous_status='checked_in' AND p_new_status='completed')) THEN
    RAISE EXCEPTION 'The requested booking status transition is not allowed.' USING ERRCODE='P0001';
  END IF;
  UPDATE public.bookings SET booking_status=p_new_status,cancelled_at=CASE WHEN p_new_status='cancelled' THEN statement_timestamp() ELSE NULL END WHERE id=p_booking_id RETURNING public.bookings.updated_at INTO changed_at;
  RETURN QUERY SELECT p_booking_id,previous_status,p_new_status,changed_at;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_update_payment_status(p_booking_id uuid, p_new_payment_status character varying)
RETURNS TABLE(booking_id uuid, old_payment_status character varying, new_payment_status character varying, updated_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE previous_status character varying; booking_state character varying; changed_at timestamptz;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Administrator authorization is required.' USING ERRCODE='42501'; END IF;
  SELECT payment_status,booking_status INTO previous_status,booking_state FROM public.bookings WHERE id=p_booking_id FOR UPDATE;
  IF NOT FOUND OR NOT ((booking_state<>'cancelled' AND previous_status='unpaid' AND p_new_payment_status IN ('pending','paid')) OR (booking_state<>'cancelled' AND previous_status='pending' AND p_new_payment_status IN ('paid','failed')) OR (booking_state<>'cancelled' AND previous_status='failed' AND p_new_payment_status IN ('pending','paid')) OR (booking_state='cancelled' AND previous_status='paid' AND p_new_payment_status='refunded')) THEN
    RAISE EXCEPTION 'The requested payment status transition is not allowed.' USING ERRCODE='P0001';
  END IF;
  UPDATE public.bookings SET payment_status=p_new_payment_status WHERE id=p_booking_id RETURNING public.bookings.updated_at INTO changed_at;
  RETURN QUERY SELECT p_booking_id,previous_status,p_new_payment_status,changed_at;
END; $$;
COMMIT;

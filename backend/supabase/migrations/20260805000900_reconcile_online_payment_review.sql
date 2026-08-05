BEGIN;

-- A staff-side collection can settle a booking while an earlier online claim is
-- still waiting for review. Reconcile against the live balance so approving that
-- claim is idempotent and never credits more than the booking total.
CREATE OR REPLACE FUNCTION public.staff_review_online_payment(
  p_booking_id uuid,
  p_approve boolean,
  p_rejection_reason text DEFAULT NULL
)
RETURNS TABLE(
  online_checkin_id uuid,
  online_checkin_status character varying,
  paid_amount bigint,
  payment_status character varying
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  b public.bookings%ROWTYPE;
  o public.online_checkins%ROWTYPE;
  remaining_amount bigint;
  credited_amount bigint;
  new_paid bigint;
  new_payment character varying;
BEGIN
  IF NOT public.can_manage_booking(p_booking_id) THEN
    RAISE EXCEPTION 'Staff authorization required.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO b FROM public.bookings WHERE id = p_booking_id FOR UPDATE;
  SELECT * INTO o FROM public.online_checkins WHERE booking_id = p_booking_id FOR UPDATE;

  IF NOT FOUND OR o.status <> 'payment_claimed' OR o.expires_at <= statement_timestamp() THEN
    RAISE EXCEPTION 'Online payment claim cannot be reviewed.' USING ERRCODE = 'P0001';
  END IF;

  IF NOT p_approve THEN
    UPDATE public.online_checkins
    SET status = 'rejected', rejection_reason = nullif(btrim(p_rejection_reason), ''),
        reviewed_at = statement_timestamp(), reviewed_by = auth.uid(), updated_at = statement_timestamp()
    WHERE id = o.id;
    RETURN QUERY SELECT o.id, 'rejected'::character varying, b.paid_amount, b.payment_status;
    RETURN;
  END IF;

  remaining_amount := greatest(b.total_amount - b.paid_amount, 0);
  credited_amount := least(o.requested_amount, remaining_amount);
  new_paid := b.paid_amount + credited_amount;
  new_payment := CASE
    WHEN new_paid >= b.total_amount THEN 'paid'
    WHEN new_paid > 0 THEN 'partially_paid'
    ELSE b.payment_status
  END;

  IF credited_amount > 0 THEN
    INSERT INTO public.payment_transactions(
      booking_id, transaction_type, amount, status, performed_by, provider_reference
    ) VALUES (
      b.id, 'online_payment', credited_amount, 'succeeded', auth.uid(), b.booking_code
    );
  END IF;

  UPDATE public.bookings
  SET paid_amount = new_paid, payment_status = new_payment
  WHERE id = b.id;

  UPDATE public.online_checkins
  SET status = 'approved', reviewed_at = statement_timestamp(), reviewed_by = auth.uid(),
      rejection_reason = NULL, updated_at = statement_timestamp()
  WHERE id = o.id;

  RETURN QUERY SELECT o.id, 'approved'::character varying, new_paid, new_payment;
END;
$$;

ALTER FUNCTION public.staff_review_online_payment(uuid, boolean, text) OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.staff_review_online_payment(uuid, boolean, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.staff_review_online_payment(uuid, boolean, text) TO authenticated;

COMMIT;

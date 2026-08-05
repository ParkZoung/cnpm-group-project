BEGIN;

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
  ON CONFLICT ON CONSTRAINT online_checkins_booking_id_key DO UPDATE
    SET status='not_started',payment_option=EXCLUDED.payment_option,
      requested_amount=EXCLUDED.requested_amount,expires_at=EXCLUDED.expires_at,rejection_reason=NULL,
      payment_claimed_at=NULL,reviewed_at=NULL,reviewed_by=NULL,updated_at=statement_timestamp()
  WHERE public.online_checkins.status IN ('not_started','rejected')
  RETURNING id INTO checkin_id;
  IF checkin_id IS NULL THEN RAISE EXCEPTION 'Online check-in is already being processed.' USING ERRCODE='P0001'; END IF;
  RETURN QUERY SELECT checkin_id,b.id,b.booking_code,p_payment_option,required_amount,expiry;
END;
$$;

ALTER FUNCTION public.customer_start_online_checkin(uuid, character varying) OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.customer_start_online_checkin(uuid, character varying) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_start_online_checkin(uuid, character varying) TO authenticated;

COMMIT;

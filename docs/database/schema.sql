-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.profiles (
  id uuid NOT NULL,
  full_name character varying,
  phone character varying,
  role character varying NOT NULL DEFAULT 'customer'::character varying CHECK (role::text = ANY (ARRAY['customer'::character varying, 'staff'::character varying, 'admin'::character varying]::text[])),
  branch_id bigint CHECK (branch_id IS NULL),
  status character varying NOT NULL DEFAULT 'active'::character varying CHECK (status::text = ANY (ARRAY['active'::character varying, 'inactive'::character varying, 'blocked'::character varying]::text[])),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT profiles_pkey PRIMARY KEY (id),
  CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id),
  CONSTRAINT profiles_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id)
);
CREATE TABLE public.branches (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name character varying NOT NULL UNIQUE,
  address text NOT NULL,
  city character varying NOT NULL,
  phone character varying,
  status character varying NOT NULL DEFAULT 'active'::character varying CHECK (status::text = ANY (ARRAY['active'::character varying, 'inactive'::character varying]::text[])),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT branches_pkey PRIMARY KEY (id)
);
CREATE TABLE public.room_types (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name character varying NOT NULL UNIQUE,
  description text,
  capacity integer NOT NULL CHECK (capacity > 0),
  bed_type character varying,
  area_m2 numeric CHECK (area_m2 > 0::numeric),
  base_price bigint NOT NULL CHECK (base_price > 0),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT room_types_pkey PRIMARY KEY (id)
);
CREATE TABLE public.rooms (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  branch_id bigint NOT NULL,
  room_type_id bigint NOT NULL,
  room_number character varying NOT NULL,
  name character varying NOT NULL,
  price_per_night bigint NOT NULL CHECK (price_per_night > 0),
  description text,
  status character varying NOT NULL DEFAULT 'available'::character varying CHECK (status::text = ANY (ARRAY['available'::character varying, 'maintenance'::character varying, 'inactive'::character varying]::text[])),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT rooms_pkey PRIMARY KEY (id),
  CONSTRAINT rooms_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id),
  CONSTRAINT rooms_room_type_id_fkey FOREIGN KEY (room_type_id) REFERENCES public.room_types(id)
);
CREATE TABLE public.bookings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  booking_code character varying NOT NULL UNIQUE,
  user_id uuid,
  room_id bigint NOT NULL,
  guest_name character varying NOT NULL,
  guest_email character varying NOT NULL,
  guest_phone character varying NOT NULL,
  check_in_date date NOT NULL,
  check_out_date date NOT NULL,
  number_of_nights integer NOT NULL CHECK (number_of_nights > 0),
  number_of_guests integer NOT NULL DEFAULT 1 CHECK (number_of_guests > 0),
  special_request text,
  price_per_night bigint NOT NULL CHECK (price_per_night > 0),
  subtotal bigint NOT NULL CHECK (subtotal >= 0),
  tax_rate numeric NOT NULL DEFAULT 10.00 CHECK (tax_rate >= 0::numeric AND tax_rate <= 100::numeric),
  tax_amount bigint NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
  discount_amount bigint NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
  total_amount bigint NOT NULL CHECK (total_amount >= 0),
  booking_status character varying NOT NULL DEFAULT 'pending'::character varying CHECK (booking_status::text = ANY (ARRAY['pending'::character varying, 'confirmed'::character varying, 'checked_in'::character varying, 'completed'::character varying, 'cancelled'::character varying]::text[])),
  payment_method character varying NOT NULL DEFAULT 'pay_at_hotel'::character varying CHECK (payment_method::text = ANY (ARRAY['pay_at_hotel'::character varying, 'online'::character varying, 'bank_transfer'::character varying]::text[])),
  payment_status character varying NOT NULL DEFAULT 'unpaid'::character varying CHECK (payment_status::text = ANY (ARRAY['unpaid'::character varying, 'pending'::character varying, 'partially_paid'::character varying, 'paid'::character varying, 'failed'::character varying, 'refunded'::character varying]::text[])),
  payment_option character varying CHECK (payment_option IS NULL OR payment_option IN ('full', 'deposit')),
  upfront_amount bigint NOT NULL DEFAULT 0 CHECK (upfront_amount >= 0),
  paid_amount bigint NOT NULL DEFAULT 0 CHECK (paid_amount >= 0 AND paid_amount <= total_amount),
  checked_in_at timestamp with time zone,
  checked_in_by uuid,
  checked_out_at timestamp with time zone,
  checked_out_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  cancelled_at timestamp with time zone,
  promotion_id bigint,
  CONSTRAINT bookings_pkey PRIMARY KEY (id),
  CONSTRAINT bookings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id),
  CONSTRAINT bookings_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.rooms(id),
  CONSTRAINT bookings_promotion_id_fkey FOREIGN KEY (promotion_id) REFERENCES public.promotions(id),
  CONSTRAINT bookings_checked_in_by_fkey FOREIGN KEY (checked_in_by) REFERENCES public.profiles(id),
  CONSTRAINT bookings_checked_out_by_fkey FOREIGN KEY (checked_out_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.staff_work_sessions (
  staff_id uuid NOT NULL,
  branch_id bigint NOT NULL,
  selected_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
  CONSTRAINT staff_work_sessions_pkey PRIMARY KEY (staff_id),
  CONSTRAINT staff_work_sessions_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.profiles(id),
  CONSTRAINT staff_work_sessions_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id)
);
CREATE TABLE public.payment_transactions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL,
  transaction_type character varying NOT NULL CHECK (transaction_type IN ('online_payment', 'staff_collection', 'refund')),
  amount bigint NOT NULL CHECK (amount > 0),
  status character varying NOT NULL CHECK (status IN ('pending', 'succeeded', 'failed')),
  performed_by uuid,
  provider_reference text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT payment_transactions_pkey PRIMARY KEY (id),
  CONSTRAINT payment_transactions_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id),
  CONSTRAINT payment_transactions_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.online_checkins (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL UNIQUE,
  status character varying NOT NULL DEFAULT 'not_started' CHECK (status IN ('not_started','payment_claimed','approved','rejected','consumed','expired')),
  payment_option character varying CHECK (payment_option IN ('full','deposit')),
  requested_amount bigint CHECK (requested_amount > 0),
  rejection_reason text,
  payment_claimed_at timestamp with time zone,
  reviewed_at timestamp with time zone,
  reviewed_by uuid,
  consumed_at timestamp with time zone,
  consumed_by uuid,
  expires_at timestamp with time zone NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT online_checkins_pkey PRIMARY KEY (id),
  CONSTRAINT online_checkins_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id),
  CONSTRAINT online_checkins_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.profiles(id),
  CONSTRAINT online_checkins_consumed_by_fkey FOREIGN KEY (consumed_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.promotions (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name character varying NOT NULL,
  code character varying UNIQUE,
  description text,
  discount_type character varying NOT NULL CHECK (discount_type::text = ANY (ARRAY['percentage'::character varying, 'fixed_amount'::character varying]::text[])),
  discount_value bigint NOT NULL CHECK (discount_value > 0),
  min_booking_amount bigint NOT NULL DEFAULT 0 CHECK (min_booking_amount >= 0),
  max_discount_amount bigint CHECK (max_discount_amount IS NULL OR max_discount_amount >= 0),
  start_at timestamp with time zone NOT NULL,
  end_at timestamp with time zone NOT NULL,
  usage_limit integer CHECK (usage_limit IS NULL OR usage_limit > 0),
  used_count integer NOT NULL DEFAULT 0 CHECK (used_count >= 0),
  status character varying NOT NULL DEFAULT 'active'::character varying CHECK (status::text = ANY (ARRAY['active'::character varying, 'inactive'::character varying, 'expired'::character varying]::text[])),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT promotions_pkey PRIMARY KEY (id)
);
CREATE TABLE public.room_images (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  room_id bigint NOT NULL,
  image_url text NOT NULL,
  alt_text character varying,
  is_primary boolean NOT NULL DEFAULT false,
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT room_images_pkey PRIMARY KEY (id),
  CONSTRAINT room_images_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.rooms(id)
);
CREATE TABLE public.amenities (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name character varying NOT NULL UNIQUE,
  icon character varying,
  description text,
  status character varying NOT NULL DEFAULT 'active'::character varying CHECK (status::text = ANY (ARRAY['active'::character varying, 'inactive'::character varying]::text[])),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT amenities_pkey PRIMARY KEY (id)
);
CREATE TABLE public.room_amenities (
  room_id bigint NOT NULL,
  amenity_id bigint NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT room_amenities_pkey PRIMARY KEY (room_id, amenity_id),
  CONSTRAINT room_amenities_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.rooms(id),
  CONSTRAINT room_amenities_amenity_id_fkey FOREIGN KEY (amenity_id) REFERENCES public.amenities(id)
);
CREATE TABLE public.promotion_usages (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  promotion_id bigint NOT NULL,
  booking_id uuid NOT NULL UNIQUE,
  user_id uuid,
  discount_amount bigint NOT NULL CHECK (discount_amount >= 0),
  used_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT promotion_usages_pkey PRIMARY KEY (id),
  CONSTRAINT promotion_usages_promotion_id_fkey FOREIGN KEY (promotion_id) REFERENCES public.promotions(id),
  CONSTRAINT promotion_usages_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id),
  CONSTRAINT promotion_usages_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.booking_status_history (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  booking_id uuid NOT NULL,
  old_status character varying CHECK (old_status IS NULL OR (old_status::text = ANY (ARRAY['pending'::character varying, 'confirmed'::character varying, 'checked_in'::character varying, 'completed'::character varying, 'cancelled'::character varying]::text[]))),
  new_status character varying NOT NULL CHECK (new_status::text = ANY (ARRAY['pending'::character varying, 'confirmed'::character varying, 'checked_in'::character varying, 'completed'::character varying, 'cancelled'::character varying]::text[])),
  changed_by uuid,
  note text,
  changed_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT booking_status_history_pkey PRIMARY KEY (id),
  CONSTRAINT booking_status_history_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id),
  CONSTRAINT booking_status_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.profiles(id)
);

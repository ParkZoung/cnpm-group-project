/*
 * GoStay catalog v1 — fail-closed cleanup.
 * The seed creates no room_images, room_amenities, or bookings. If any such
 * dependent data exists, cleanup aborts instead of deleting data it does not own.
 */

BEGIN;

SELECT pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('gostay_catalog_v1', 0)
);

DO $cleanup$
DECLARE
  item record;
  existing record;
  target_branch_id bigint;
  target_room_type_id bigint;
  target_capacity integer;
  expected_description text;
  outside_branch_room_count bigint;
  outside_type_room_count bigint;
  image_dependency_count bigint;
  amenity_dependency_count bigint;
  booking_dependency_count bigint;
  duplicate_room_count bigint;
  remaining_branch_count bigint;
  remaining_type_count bigint;
  remaining_room_count bigint;
BEGIN
  IF pg_catalog.to_regclass('public.branches') IS NULL
     OR pg_catalog.to_regclass('public.room_types') IS NULL
     OR pg_catalog.to_regclass('public.rooms') IS NULL
     OR pg_catalog.to_regclass('public.room_images') IS NULL
     OR pg_catalog.to_regclass('public.room_amenities') IS NULL
     OR pg_catalog.to_regclass('public.bookings') IS NULL
  THEN
    RAISE EXCEPTION 'GoStay catalog cleanup stopped: required tables are missing.';
  END IF;

  FOR item IN
    SELECT * FROM (VALUES
      ('GoStay Resort & Spa Phú Quốc', 'Phú Quốc', 'Khu Bãi Dài, Phú Quốc', NULL::varchar, 'active'),
      ('GoStay Resort Nha Trang', 'Nha Trang', 'Khu Hòn Tre, Nha Trang', NULL::varchar, 'active'),
      ('GoStay Resort & Golf Nam Hội An', 'Nam Hội An', 'Khu ven biển Nam Hội An, Quảng Nam', NULL::varchar, 'active'),
      ('GoStay Resort & Spa Hạ Long', 'Hạ Long', 'Khu Bãi Cháy, Hạ Long, Quảng Ninh', NULL::varchar, 'active')
    ) AS seed_branch(name, city, address, phone, status)
  LOOP
    SELECT branch.id, branch.city, branch.address, branch.phone, branch.status
    INTO existing
    FROM public.branches AS branch
    WHERE branch.name = item.name;

    IF FOUND AND (
      existing.city IS DISTINCT FROM item.city
      OR existing.address IS DISTINCT FROM item.address
      OR existing.phone IS DISTINCT FROM item.phone
      OR existing.status IS DISTINCT FROM item.status
    ) THEN
      RAISE EXCEPTION
        'GoStay catalog cleanup stopped: branch "%" no longer matches the exact seed identity.',
        item.name;
    END IF;
  END LOOP;

  FOR item IN
    SELECT * FROM (VALUES
      ('Deluxe Hướng Vườn 2 Giường Đơn', 'Phòng rộng rãi với hai giường đơn và tầm nhìn hướng khu vườn xanh mát.', 2, '2 giường đơn', 38::numeric, 750000::bigint),
      ('Deluxe Hướng Vườn Giường Đôi', 'Phòng giường đôi dành cho hai khách, có không gian nghỉ thoáng và hướng vườn.', 2, '1 giường King', 38::numeric, 900000::bigint),
      ('Deluxe Hướng Biển 2 Giường Đơn', 'Phòng hai giường đơn với ban công thoáng, đón ánh sáng tự nhiên và hướng biển.', 2, '2 giường đơn', 40::numeric, 1050000::bigint),
      ('Deluxe Hướng Biển Giường Đôi', 'Phòng giường đôi với không gian nghỉ tiện nghi và tầm nhìn hướng biển.', 2, '1 giường King', 40::numeric, 1200000::bigint),
      ('Deluxe Hướng Vịnh Giường Đôi', 'Phòng giường đôi có cửa sổ rộng và tầm nhìn hướng vịnh Hạ Long.', 2, '1 giường King', 42::numeric, 1200000::bigint),
      ('Junior Suite Hướng Vườn Giường Đôi', 'Suite hướng vườn gồm khu vực nghỉ và tiếp khách, phù hợp cho kỳ lưu trú dài ngày.', 3, '1 giường King và sofa', 50::numeric, 1350000::bigint),
      ('Junior Suite Hướng Biển Giường Đôi', 'Suite hướng biển có khu vực nghỉ và tiếp khách riêng, mang lại không gian thoải mái.', 3, '1 giường King và sofa', 52::numeric, 1550000::bigint),
      ('Phòng Gia Đình', 'Phòng dành cho gia đình, bố trí nhiều chỗ ngủ và khu vực sinh hoạt chung.', 4, '1 giường King và 2 giường đơn', 65::numeric, 1700000::bigint),
      ('Biệt Thự 3 Phòng Ngủ Có Hồ Bơi', 'Biệt thự ba phòng ngủ có hồ bơi và không gian sinh hoạt riêng, phù hợp tối đa sáu khách.', 6, '3 giường King', 180::numeric, 2000000::bigint)
    ) AS seed_type(name, description, capacity, bed_type, area_m2, base_price)
  LOOP
    SELECT room_type.id, room_type.description, room_type.capacity,
      room_type.bed_type, room_type.area_m2, room_type.base_price
    INTO existing
    FROM public.room_types AS room_type
    WHERE room_type.name = item.name;

    IF FOUND AND (
      existing.description IS DISTINCT FROM item.description
      OR existing.capacity IS DISTINCT FROM item.capacity
      OR existing.bed_type IS DISTINCT FROM item.bed_type
      OR existing.area_m2 IS DISTINCT FROM item.area_m2
      OR existing.base_price IS DISTINCT FROM item.base_price
    ) THEN
      RAISE EXCEPTION
        'GoStay catalog cleanup stopped: room type "%" no longer matches the exact seed identity.',
        item.name;
    END IF;
  END LOOP;

  FOR item IN
    SELECT * FROM (VALUES
      ('GoStay Resort & Spa Phú Quốc','101','Deluxe Hướng Biển 2 Giường Đơn 101','Deluxe Hướng Biển 2 Giường Đơn',1100000::bigint,'available'),
      ('GoStay Resort & Spa Phú Quốc','102','Deluxe Hướng Biển Giường Đôi 102','Deluxe Hướng Biển Giường Đôi',1250000::bigint,'available'),
      ('GoStay Resort & Spa Phú Quốc','201','Junior Suite Hướng Biển Giường Đôi 201','Junior Suite Hướng Biển Giường Đôi',1600000::bigint,'available'),
      ('GoStay Resort & Spa Phú Quốc','301','Phòng Gia Đình 301','Phòng Gia Đình',1750000::bigint,'available'),
      ('GoStay Resort & Spa Phú Quốc','V01','Biệt Thự 3 Phòng Ngủ Có Hồ Bơi V01','Biệt Thự 3 Phòng Ngủ Có Hồ Bơi',2000000::bigint,'inactive'),
      ('GoStay Resort Nha Trang','101','Deluxe Hướng Biển 2 Giường Đơn 101','Deluxe Hướng Biển 2 Giường Đơn',1050000::bigint,'available'),
      ('GoStay Resort Nha Trang','102','Deluxe Hướng Biển Giường Đôi 102','Deluxe Hướng Biển Giường Đôi',1200000::bigint,'available'),
      ('GoStay Resort Nha Trang','201','Deluxe Hướng Biển 2 Giường Đơn 201','Deluxe Hướng Biển 2 Giường Đơn',1150000::bigint,'available'),
      ('GoStay Resort Nha Trang','301','Junior Suite Hướng Biển Giường Đôi 301','Junior Suite Hướng Biển Giường Đôi',1550000::bigint,'available'),
      ('GoStay Resort Nha Trang','401','Phòng Gia Đình 401','Phòng Gia Đình',1700000::bigint,'maintenance'),
      ('GoStay Resort & Golf Nam Hội An','101','Deluxe Hướng Vườn 2 Giường Đơn 101','Deluxe Hướng Vườn 2 Giường Đơn',750000::bigint,'available'),
      ('GoStay Resort & Golf Nam Hội An','102','Deluxe Hướng Vườn Giường Đôi 102','Deluxe Hướng Vườn Giường Đôi',900000::bigint,'available'),
      ('GoStay Resort & Golf Nam Hội An','201','Deluxe Hướng Vườn 2 Giường Đơn 201','Deluxe Hướng Vườn 2 Giường Đơn',790000::bigint,'available'),
      ('GoStay Resort & Golf Nam Hội An','301','Junior Suite Hướng Vườn Giường Đôi 301','Junior Suite Hướng Vườn Giường Đôi',1350000::bigint,'maintenance'),
      ('GoStay Resort & Golf Nam Hội An','V01','Biệt Thự 3 Phòng Ngủ Có Hồ Bơi V01','Biệt Thự 3 Phòng Ngủ Có Hồ Bơi',2000000::bigint,'available'),
      ('GoStay Resort & Spa Hạ Long','101','Deluxe Hướng Vịnh Giường Đôi 101','Deluxe Hướng Vịnh Giường Đôi',1200000::bigint,'available'),
      ('GoStay Resort & Spa Hạ Long','102','Deluxe Hướng Vịnh Giường Đôi 102','Deluxe Hướng Vịnh Giường Đôi',1250000::bigint,'available'),
      ('GoStay Resort & Spa Hạ Long','201','Deluxe Hướng Vịnh Giường Đôi 201','Deluxe Hướng Vịnh Giường Đôi',1350000::bigint,'available'),
      ('GoStay Resort & Spa Hạ Long','202','Deluxe Hướng Vịnh Giường Đôi 202','Deluxe Hướng Vịnh Giường Đôi',1300000::bigint,'maintenance'),
      ('GoStay Resort & Spa Hạ Long','301','Phòng Gia Đình 301','Phòng Gia Đình',1750000::bigint,'inactive')
    ) AS seed_room(branch_name, room_number, room_name, room_type_name, price, status)
  LOOP
    SELECT branch.id INTO target_branch_id
    FROM public.branches AS branch
    WHERE branch.name = item.branch_name;
    IF NOT FOUND THEN CONTINUE; END IF;

    SELECT room_type.id, room_type.capacity
    INTO target_room_type_id, target_capacity
    FROM public.room_types AS room_type
    WHERE room_type.name = item.room_type_name;
    IF NOT FOUND THEN
      RAISE EXCEPTION
        'GoStay catalog cleanup stopped: expected room type "%" is missing while branch data remains.',
        item.room_type_name;
    END IF;

    expected_description := pg_catalog.format(
      'Phòng %s tại %s thuộc hạng %s, được bố trí phù hợp tối đa %s khách.',
      item.room_number, item.branch_name, item.room_type_name, target_capacity
    );

    SELECT room.id, room.room_type_id, room.name, room.price_per_night,
      room.description, room.status
    INTO existing
    FROM public.rooms AS room
    WHERE room.branch_id = target_branch_id
      AND room.room_number = item.room_number;

    IF FOUND AND (
      existing.room_type_id IS DISTINCT FROM target_room_type_id
      OR existing.name IS DISTINCT FROM item.room_name
      OR existing.price_per_night IS DISTINCT FROM item.price
      OR existing.description IS DISTINCT FROM expected_description
      OR existing.status IS DISTINCT FROM item.status
    ) THEN
      RAISE EXCEPTION
        'GoStay catalog cleanup stopped: room % in branch "%" no longer matches exact seed data.',
        item.room_number, item.branch_name;
    END IF;
  END LOOP;

  WITH expected(branch_name, room_number, room_name, room_type_name, price, status) AS (
    VALUES
      ('GoStay Resort & Spa Phú Quốc','101','Deluxe Hướng Biển 2 Giường Đơn 101','Deluxe Hướng Biển 2 Giường Đơn',1100000::bigint,'available'),
      ('GoStay Resort & Spa Phú Quốc','102','Deluxe Hướng Biển Giường Đôi 102','Deluxe Hướng Biển Giường Đôi',1250000::bigint,'available'),
      ('GoStay Resort & Spa Phú Quốc','201','Junior Suite Hướng Biển Giường Đôi 201','Junior Suite Hướng Biển Giường Đôi',1600000::bigint,'available'),
      ('GoStay Resort & Spa Phú Quốc','301','Phòng Gia Đình 301','Phòng Gia Đình',1750000::bigint,'available'),
      ('GoStay Resort & Spa Phú Quốc','V01','Biệt Thự 3 Phòng Ngủ Có Hồ Bơi V01','Biệt Thự 3 Phòng Ngủ Có Hồ Bơi',2000000::bigint,'inactive'),
      ('GoStay Resort Nha Trang','101','Deluxe Hướng Biển 2 Giường Đơn 101','Deluxe Hướng Biển 2 Giường Đơn',1050000::bigint,'available'),
      ('GoStay Resort Nha Trang','102','Deluxe Hướng Biển Giường Đôi 102','Deluxe Hướng Biển Giường Đôi',1200000::bigint,'available'),
      ('GoStay Resort Nha Trang','201','Deluxe Hướng Biển 2 Giường Đơn 201','Deluxe Hướng Biển 2 Giường Đơn',1150000::bigint,'available'),
      ('GoStay Resort Nha Trang','301','Junior Suite Hướng Biển Giường Đôi 301','Junior Suite Hướng Biển Giường Đôi',1550000::bigint,'available'),
      ('GoStay Resort Nha Trang','401','Phòng Gia Đình 401','Phòng Gia Đình',1700000::bigint,'maintenance'),
      ('GoStay Resort & Golf Nam Hội An','101','Deluxe Hướng Vườn 2 Giường Đơn 101','Deluxe Hướng Vườn 2 Giường Đơn',750000::bigint,'available'),
      ('GoStay Resort & Golf Nam Hội An','102','Deluxe Hướng Vườn Giường Đôi 102','Deluxe Hướng Vườn Giường Đôi',900000::bigint,'available'),
      ('GoStay Resort & Golf Nam Hội An','201','Deluxe Hướng Vườn 2 Giường Đơn 201','Deluxe Hướng Vườn 2 Giường Đơn',790000::bigint,'available'),
      ('GoStay Resort & Golf Nam Hội An','301','Junior Suite Hướng Vườn Giường Đôi 301','Junior Suite Hướng Vườn Giường Đôi',1350000::bigint,'maintenance'),
      ('GoStay Resort & Golf Nam Hội An','V01','Biệt Thự 3 Phòng Ngủ Có Hồ Bơi V01','Biệt Thự 3 Phòng Ngủ Có Hồ Bơi',2000000::bigint,'available'),
      ('GoStay Resort & Spa Hạ Long','101','Deluxe Hướng Vịnh Giường Đôi 101','Deluxe Hướng Vịnh Giường Đôi',1200000::bigint,'available'),
      ('GoStay Resort & Spa Hạ Long','102','Deluxe Hướng Vịnh Giường Đôi 102','Deluxe Hướng Vịnh Giường Đôi',1250000::bigint,'available'),
      ('GoStay Resort & Spa Hạ Long','201','Deluxe Hướng Vịnh Giường Đôi 201','Deluxe Hướng Vịnh Giường Đôi',1350000::bigint,'available'),
      ('GoStay Resort & Spa Hạ Long','202','Deluxe Hướng Vịnh Giường Đôi 202','Deluxe Hướng Vịnh Giường Đôi',1300000::bigint,'maintenance'),
      ('GoStay Resort & Spa Hạ Long','301','Phòng Gia Đình 301','Phòng Gia Đình',1750000::bigint,'inactive')
  )
  SELECT count(*) INTO outside_branch_room_count
  FROM public.rooms AS room
  JOIN public.branches AS branch ON branch.id = room.branch_id
  LEFT JOIN public.room_types AS room_type ON room_type.id = room.room_type_id
  WHERE branch.name IN (
    'GoStay Resort & Spa Phú Quốc', 'GoStay Resort Nha Trang',
    'GoStay Resort & Golf Nam Hội An', 'GoStay Resort & Spa Hạ Long'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM expected
    WHERE expected.branch_name = branch.name
      AND expected.room_number = room.room_number
      AND expected.room_name = room.name
      AND expected.room_type_name = room_type.name
      AND expected.price = room.price_per_night
      AND expected.status = room.status
      AND room.description = pg_catalog.format(
        'Phòng %s tại %s thuộc hạng %s, được bố trí phù hợp tối đa %s khách.',
        expected.room_number, expected.branch_name, expected.room_type_name, room_type.capacity
      )
  );

  IF outside_branch_room_count > 0 THEN
    RAISE EXCEPTION
      'GoStay catalog cleanup stopped: % room(s) in seed branches are outside the exact 20-room seed.',
      outside_branch_room_count;
  END IF;

  WITH expected(branch_name, room_number, room_name, room_type_name, price, status) AS (
    VALUES
      ('GoStay Resort & Spa Phú Quốc','101','Deluxe Hướng Biển 2 Giường Đơn 101','Deluxe Hướng Biển 2 Giường Đơn',1100000::bigint,'available'),
      ('GoStay Resort & Spa Phú Quốc','102','Deluxe Hướng Biển Giường Đôi 102','Deluxe Hướng Biển Giường Đôi',1250000::bigint,'available'),
      ('GoStay Resort & Spa Phú Quốc','201','Junior Suite Hướng Biển Giường Đôi 201','Junior Suite Hướng Biển Giường Đôi',1600000::bigint,'available'),
      ('GoStay Resort & Spa Phú Quốc','301','Phòng Gia Đình 301','Phòng Gia Đình',1750000::bigint,'available'),
      ('GoStay Resort & Spa Phú Quốc','V01','Biệt Thự 3 Phòng Ngủ Có Hồ Bơi V01','Biệt Thự 3 Phòng Ngủ Có Hồ Bơi',2000000::bigint,'inactive'),
      ('GoStay Resort Nha Trang','101','Deluxe Hướng Biển 2 Giường Đơn 101','Deluxe Hướng Biển 2 Giường Đơn',1050000::bigint,'available'),
      ('GoStay Resort Nha Trang','102','Deluxe Hướng Biển Giường Đôi 102','Deluxe Hướng Biển Giường Đôi',1200000::bigint,'available'),
      ('GoStay Resort Nha Trang','201','Deluxe Hướng Biển 2 Giường Đơn 201','Deluxe Hướng Biển 2 Giường Đơn',1150000::bigint,'available'),
      ('GoStay Resort Nha Trang','301','Junior Suite Hướng Biển Giường Đôi 301','Junior Suite Hướng Biển Giường Đôi',1550000::bigint,'available'),
      ('GoStay Resort Nha Trang','401','Phòng Gia Đình 401','Phòng Gia Đình',1700000::bigint,'maintenance'),
      ('GoStay Resort & Golf Nam Hội An','101','Deluxe Hướng Vườn 2 Giường Đơn 101','Deluxe Hướng Vườn 2 Giường Đơn',750000::bigint,'available'),
      ('GoStay Resort & Golf Nam Hội An','102','Deluxe Hướng Vườn Giường Đôi 102','Deluxe Hướng Vườn Giường Đôi',900000::bigint,'available'),
      ('GoStay Resort & Golf Nam Hội An','201','Deluxe Hướng Vườn 2 Giường Đơn 201','Deluxe Hướng Vườn 2 Giường Đơn',790000::bigint,'available'),
      ('GoStay Resort & Golf Nam Hội An','301','Junior Suite Hướng Vườn Giường Đôi 301','Junior Suite Hướng Vườn Giường Đôi',1350000::bigint,'maintenance'),
      ('GoStay Resort & Golf Nam Hội An','V01','Biệt Thự 3 Phòng Ngủ Có Hồ Bơi V01','Biệt Thự 3 Phòng Ngủ Có Hồ Bơi',2000000::bigint,'available'),
      ('GoStay Resort & Spa Hạ Long','101','Deluxe Hướng Vịnh Giường Đôi 101','Deluxe Hướng Vịnh Giường Đôi',1200000::bigint,'available'),
      ('GoStay Resort & Spa Hạ Long','102','Deluxe Hướng Vịnh Giường Đôi 102','Deluxe Hướng Vịnh Giường Đôi',1250000::bigint,'available'),
      ('GoStay Resort & Spa Hạ Long','201','Deluxe Hướng Vịnh Giường Đôi 201','Deluxe Hướng Vịnh Giường Đôi',1350000::bigint,'available'),
      ('GoStay Resort & Spa Hạ Long','202','Deluxe Hướng Vịnh Giường Đôi 202','Deluxe Hướng Vịnh Giường Đôi',1300000::bigint,'maintenance'),
      ('GoStay Resort & Spa Hạ Long','301','Phòng Gia Đình 301','Phòng Gia Đình',1750000::bigint,'inactive')
  )
  SELECT count(*) INTO outside_type_room_count
  FROM public.rooms AS room
  JOIN public.room_types AS room_type ON room_type.id = room.room_type_id
  LEFT JOIN public.branches AS branch ON branch.id = room.branch_id
  WHERE room_type.name IN (
    'Deluxe Hướng Vườn 2 Giường Đơn', 'Deluxe Hướng Vườn Giường Đôi',
    'Deluxe Hướng Biển 2 Giường Đơn', 'Deluxe Hướng Biển Giường Đôi',
    'Deluxe Hướng Vịnh Giường Đôi', 'Junior Suite Hướng Vườn Giường Đôi',
    'Junior Suite Hướng Biển Giường Đôi', 'Phòng Gia Đình', 'Biệt Thự 3 Phòng Ngủ Có Hồ Bơi'
  )
  AND NOT EXISTS (
    SELECT 1 FROM expected
    WHERE expected.branch_name = branch.name
      AND expected.room_number = room.room_number
      AND expected.room_name = room.name
      AND expected.room_type_name = room_type.name
      AND room.description = pg_catalog.format(
        'Phòng %s tại %s thuộc hạng %s, được bố trí phù hợp tối đa %s khách.',
        expected.room_number, expected.branch_name, expected.room_type_name,
        room_type.capacity
      )
  );

  IF outside_type_room_count > 0 THEN
    RAISE EXCEPTION
      'GoStay catalog cleanup stopped: % non-seed room(s) use a marked seed room type.',
      outside_type_room_count;
  END IF;

  SELECT count(*) INTO duplicate_room_count
  FROM (
    SELECT room.branch_id, room.room_number
    FROM public.rooms AS room
    JOIN public.branches AS branch ON branch.id = room.branch_id
    WHERE branch.name IN (
      'GoStay Resort & Spa Phú Quốc', 'GoStay Resort Nha Trang',
      'GoStay Resort & Golf Nam Hội An', 'GoStay Resort & Spa Hạ Long'
    )
    GROUP BY room.branch_id, room.room_number
    HAVING count(*) > 1
  ) AS duplicates;

  IF duplicate_room_count > 0 THEN
    RAISE EXCEPTION
      'GoStay catalog cleanup stopped: % duplicate branch-and-room-number group(s) exist; cleanup will not guess ownership.',
      duplicate_room_count;
  END IF;

  WITH seed_rooms AS (
    SELECT room.id
    FROM public.rooms AS room
    JOIN public.branches AS branch ON branch.id = room.branch_id
    WHERE branch.name IN (
      'GoStay Resort & Spa Phú Quốc', 'GoStay Resort Nha Trang',
      'GoStay Resort & Golf Nam Hội An', 'GoStay Resort & Spa Hạ Long'
    )
      AND (branch.name, room.room_number) IN (
        ('GoStay Resort & Spa Phú Quốc','101'), ('GoStay Resort & Spa Phú Quốc','102'),
        ('GoStay Resort & Spa Phú Quốc','201'), ('GoStay Resort & Spa Phú Quốc','301'),
        ('GoStay Resort & Spa Phú Quốc','V01'),
        ('GoStay Resort Nha Trang','101'), ('GoStay Resort Nha Trang','102'),
        ('GoStay Resort Nha Trang','201'), ('GoStay Resort Nha Trang','301'),
        ('GoStay Resort Nha Trang','401'),
        ('GoStay Resort & Golf Nam Hội An','101'), ('GoStay Resort & Golf Nam Hội An','102'),
        ('GoStay Resort & Golf Nam Hội An','201'), ('GoStay Resort & Golf Nam Hội An','301'),
        ('GoStay Resort & Golf Nam Hội An','V01'),
        ('GoStay Resort & Spa Hạ Long','101'), ('GoStay Resort & Spa Hạ Long','102'),
        ('GoStay Resort & Spa Hạ Long','201'), ('GoStay Resort & Spa Hạ Long','202'),
        ('GoStay Resort & Spa Hạ Long','301')
      )
  )
  SELECT
    (SELECT count(*) FROM public.room_images AS image JOIN seed_rooms ON seed_rooms.id = image.room_id),
    (SELECT count(*) FROM public.room_amenities AS link JOIN seed_rooms ON seed_rooms.id = link.room_id),
    (SELECT count(*) FROM public.bookings AS booking JOIN seed_rooms ON seed_rooms.id = booking.room_id)
  INTO image_dependency_count, amenity_dependency_count, booking_dependency_count;

  IF image_dependency_count > 0 OR amenity_dependency_count > 0 OR booking_dependency_count > 0 THEN
    RAISE EXCEPTION
      'GoStay catalog cleanup stopped: dependent data exists (images %, amenities %, bookings %). No dependent rows were created by this seed, so cleanup will not delete them.',
      image_dependency_count, amenity_dependency_count, booking_dependency_count;
  END IF;

  FOR item IN
    SELECT * FROM (VALUES
      ('GoStay Resort & Spa Phú Quốc','101','Deluxe Hướng Biển 2 Giường Đơn 101','Deluxe Hướng Biển 2 Giường Đơn',1100000::bigint,'available'),
      ('GoStay Resort & Spa Phú Quốc','102','Deluxe Hướng Biển Giường Đôi 102','Deluxe Hướng Biển Giường Đôi',1250000::bigint,'available'),
      ('GoStay Resort & Spa Phú Quốc','201','Junior Suite Hướng Biển Giường Đôi 201','Junior Suite Hướng Biển Giường Đôi',1600000::bigint,'available'),
      ('GoStay Resort & Spa Phú Quốc','301','Phòng Gia Đình 301','Phòng Gia Đình',1750000::bigint,'available'),
      ('GoStay Resort & Spa Phú Quốc','V01','Biệt Thự 3 Phòng Ngủ Có Hồ Bơi V01','Biệt Thự 3 Phòng Ngủ Có Hồ Bơi',2000000::bigint,'inactive'),
      ('GoStay Resort Nha Trang','101','Deluxe Hướng Biển 2 Giường Đơn 101','Deluxe Hướng Biển 2 Giường Đơn',1050000::bigint,'available'),
      ('GoStay Resort Nha Trang','102','Deluxe Hướng Biển Giường Đôi 102','Deluxe Hướng Biển Giường Đôi',1200000::bigint,'available'),
      ('GoStay Resort Nha Trang','201','Deluxe Hướng Biển 2 Giường Đơn 201','Deluxe Hướng Biển 2 Giường Đơn',1150000::bigint,'available'),
      ('GoStay Resort Nha Trang','301','Junior Suite Hướng Biển Giường Đôi 301','Junior Suite Hướng Biển Giường Đôi',1550000::bigint,'available'),
      ('GoStay Resort Nha Trang','401','Phòng Gia Đình 401','Phòng Gia Đình',1700000::bigint,'maintenance'),
      ('GoStay Resort & Golf Nam Hội An','101','Deluxe Hướng Vườn 2 Giường Đơn 101','Deluxe Hướng Vườn 2 Giường Đơn',750000::bigint,'available'),
      ('GoStay Resort & Golf Nam Hội An','102','Deluxe Hướng Vườn Giường Đôi 102','Deluxe Hướng Vườn Giường Đôi',900000::bigint,'available'),
      ('GoStay Resort & Golf Nam Hội An','201','Deluxe Hướng Vườn 2 Giường Đơn 201','Deluxe Hướng Vườn 2 Giường Đơn',790000::bigint,'available'),
      ('GoStay Resort & Golf Nam Hội An','301','Junior Suite Hướng Vườn Giường Đôi 301','Junior Suite Hướng Vườn Giường Đôi',1350000::bigint,'maintenance'),
      ('GoStay Resort & Golf Nam Hội An','V01','Biệt Thự 3 Phòng Ngủ Có Hồ Bơi V01','Biệt Thự 3 Phòng Ngủ Có Hồ Bơi',2000000::bigint,'available'),
      ('GoStay Resort & Spa Hạ Long','101','Deluxe Hướng Vịnh Giường Đôi 101','Deluxe Hướng Vịnh Giường Đôi',1200000::bigint,'available'),
      ('GoStay Resort & Spa Hạ Long','102','Deluxe Hướng Vịnh Giường Đôi 102','Deluxe Hướng Vịnh Giường Đôi',1250000::bigint,'available'),
      ('GoStay Resort & Spa Hạ Long','201','Deluxe Hướng Vịnh Giường Đôi 201','Deluxe Hướng Vịnh Giường Đôi',1350000::bigint,'available'),
      ('GoStay Resort & Spa Hạ Long','202','Deluxe Hướng Vịnh Giường Đôi 202','Deluxe Hướng Vịnh Giường Đôi',1300000::bigint,'maintenance'),
      ('GoStay Resort & Spa Hạ Long','301','Phòng Gia Đình 301','Phòng Gia Đình',1750000::bigint,'inactive')
    ) AS seed_room(branch_name, room_number, room_name, room_type_name, price, status)
  LOOP
    SELECT branch.id INTO target_branch_id
    FROM public.branches AS branch WHERE branch.name = item.branch_name;
    IF NOT FOUND THEN CONTINUE; END IF;

    SELECT room_type.id, room_type.capacity
    INTO target_room_type_id, target_capacity
    FROM public.room_types AS room_type WHERE room_type.name = item.room_type_name;
    IF NOT FOUND THEN CONTINUE; END IF;

    expected_description := pg_catalog.format(
      'Phòng %s tại %s thuộc hạng %s, được bố trí phù hợp tối đa %s khách.',
      item.room_number, item.branch_name, item.room_type_name, target_capacity
    );

    DELETE FROM public.rooms AS room
    WHERE room.branch_id = target_branch_id
      AND room.room_type_id = target_room_type_id
      AND room.room_number = item.room_number
      AND room.name = item.room_name
      AND room.price_per_night = item.price
      AND room.status = item.status
      AND room.description = expected_description;
  END LOOP;

  DELETE FROM public.branches AS branch
  WHERE (branch.name, branch.city, branch.address, branch.status) IN (
    ('GoStay Resort & Spa Phú Quốc','Phú Quốc','Khu Bãi Dài, Phú Quốc','active'),
    ('GoStay Resort Nha Trang','Nha Trang','Khu Hòn Tre, Nha Trang','active'),
    ('GoStay Resort & Golf Nam Hội An','Nam Hội An','Khu ven biển Nam Hội An, Quảng Nam','active'),
    ('GoStay Resort & Spa Hạ Long','Hạ Long','Khu Bãi Cháy, Hạ Long, Quảng Ninh','active')
  )
    AND branch.phone IS NULL
    AND NOT EXISTS (SELECT 1 FROM public.rooms AS room WHERE room.branch_id = branch.id);

  DELETE FROM public.room_types AS room_type
  WHERE room_type.name IN (
    'Deluxe Hướng Vườn 2 Giường Đơn', 'Deluxe Hướng Vườn Giường Đôi',
    'Deluxe Hướng Biển 2 Giường Đơn', 'Deluxe Hướng Biển Giường Đôi',
    'Deluxe Hướng Vịnh Giường Đôi', 'Junior Suite Hướng Vườn Giường Đôi',
    'Junior Suite Hướng Biển Giường Đôi', 'Phòng Gia Đình', 'Biệt Thự 3 Phòng Ngủ Có Hồ Bơi'
  )
    AND NOT EXISTS (
      SELECT 1 FROM public.rooms AS room WHERE room.room_type_id = room_type.id
    );

  SELECT count(*) INTO remaining_branch_count
  FROM public.branches
  WHERE name IN (
    'GoStay Resort & Spa Phú Quốc', 'GoStay Resort Nha Trang',
    'GoStay Resort & Golf Nam Hội An', 'GoStay Resort & Spa Hạ Long'
  );

  SELECT count(*) INTO remaining_type_count
  FROM public.room_types
  WHERE name IN (
    'Deluxe Hướng Vườn 2 Giường Đơn', 'Deluxe Hướng Vườn Giường Đôi',
    'Deluxe Hướng Biển 2 Giường Đơn', 'Deluxe Hướng Biển Giường Đôi',
    'Deluxe Hướng Vịnh Giường Đôi', 'Junior Suite Hướng Vườn Giường Đôi',
    'Junior Suite Hướng Biển Giường Đôi', 'Phòng Gia Đình', 'Biệt Thự 3 Phòng Ngủ Có Hồ Bơi'
  );

  SELECT count(*) INTO remaining_room_count
  FROM public.rooms AS room
  JOIN public.branches AS branch ON branch.id = room.branch_id
  WHERE (branch.name, room.room_number) IN (
    ('GoStay Resort & Spa Phú Quốc','101'), ('GoStay Resort & Spa Phú Quốc','102'),
    ('GoStay Resort & Spa Phú Quốc','201'), ('GoStay Resort & Spa Phú Quốc','301'),
    ('GoStay Resort & Spa Phú Quốc','V01'),
    ('GoStay Resort Nha Trang','101'), ('GoStay Resort Nha Trang','102'),
    ('GoStay Resort Nha Trang','201'), ('GoStay Resort Nha Trang','301'),
    ('GoStay Resort Nha Trang','401'),
    ('GoStay Resort & Golf Nam Hội An','101'), ('GoStay Resort & Golf Nam Hội An','102'),
    ('GoStay Resort & Golf Nam Hội An','201'), ('GoStay Resort & Golf Nam Hội An','301'),
    ('GoStay Resort & Golf Nam Hội An','V01'),
    ('GoStay Resort & Spa Hạ Long','101'), ('GoStay Resort & Spa Hạ Long','102'),
    ('GoStay Resort & Spa Hạ Long','201'), ('GoStay Resort & Spa Hạ Long','202'),
    ('GoStay Resort & Spa Hạ Long','301')
  );

  IF remaining_branch_count <> 0 OR remaining_type_count <> 0 OR remaining_room_count <> 0 THEN
    RAISE EXCEPTION
      'GoStay catalog cleanup postcheck failed: remaining branches %, room types %, rooms %.',
      remaining_branch_count, remaining_type_count, remaining_room_count;
  END IF;

  RAISE NOTICE 'PASS | cleanup.postcheck | Exact GoStay catalog v1 rows were removed; no external dependent data was deleted.';
END;
$cleanup$;

COMMIT;

/*
 * GoStay catalog v1.
 * Idempotent, fail-closed seed for 4 branches, 9 room types, and 20 rooms.
 * No room_images are inserted.
 */

BEGIN;

SELECT pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('gostay_catalog_v1', 0)
);

DO $seed$
DECLARE
  item record;
  existing record;
  target_branch_id bigint;
  target_room_type_id bigint;
  target_capacity integer;
  expected_description text;
  image_count_before bigint;
  image_count_after bigint;
  branch_count integer;
  room_type_count integer;
  room_count integer;
  available_count integer;
  maintenance_count integer;
  inactive_count integer;
  budget_count integer;
  orphan_count integer;
  duplicate_count integer;
  below_base_count integer;
BEGIN
  IF pg_catalog.to_regclass('public.branches') IS NULL
     OR pg_catalog.to_regclass('public.room_types') IS NULL
     OR pg_catalog.to_regclass('public.rooms') IS NULL
     OR pg_catalog.to_regclass('public.room_images') IS NULL
  THEN
    RAISE EXCEPTION 'GoStay catalog seed stopped: required catalog tables are missing.';
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

    IF FOUND THEN
      IF existing.city IS DISTINCT FROM item.city
         OR existing.address IS DISTINCT FROM item.address
         OR existing.phone IS DISTINCT FROM item.phone
         OR existing.status IS DISTINCT FROM item.status
      THEN
        RAISE EXCEPTION
          'GoStay catalog seed stopped: branch "%" exists with different content.', item.name;
      END IF;
    ELSE
      INSERT INTO public.branches (name, city, address, phone, status)
      VALUES (item.name, item.city, item.address, item.phone, item.status);
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

    IF FOUND THEN
      IF existing.description IS DISTINCT FROM item.description
         OR existing.capacity IS DISTINCT FROM item.capacity
         OR existing.bed_type IS DISTINCT FROM item.bed_type
         OR existing.area_m2 IS DISTINCT FROM item.area_m2
         OR existing.base_price IS DISTINCT FROM item.base_price
      THEN
        RAISE EXCEPTION
          'GoStay catalog seed stopped: room type "%" exists with different content.', item.name;
      END IF;
    ELSE
      INSERT INTO public.room_types (
        name, description, capacity, bed_type, area_m2, base_price
      )
      VALUES (
        item.name, item.description, item.capacity,
        item.bed_type, item.area_m2, item.base_price
      );
    END IF;
  END LOOP;

  WITH expected(branch_name, room_number) AS (
    VALUES
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
  SELECT count(*)
  INTO image_count_before
  FROM public.room_images AS image
  JOIN public.rooms AS room ON room.id = image.room_id
  JOIN public.branches AS branch ON branch.id = room.branch_id
  JOIN expected
    ON expected.branch_name = branch.name
   AND expected.room_number = room.room_number;

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
    SELECT branch.id
    INTO STRICT target_branch_id
    FROM public.branches AS branch
    WHERE branch.name = item.branch_name;

    SELECT room_type.id, room_type.capacity
    INTO STRICT target_room_type_id, target_capacity
    FROM public.room_types AS room_type
    WHERE room_type.name = item.room_type_name;

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

    IF FOUND THEN
      IF existing.room_type_id IS DISTINCT FROM target_room_type_id
         OR existing.name IS DISTINCT FROM item.room_name
         OR existing.price_per_night IS DISTINCT FROM item.price
         OR existing.description IS DISTINCT FROM expected_description
         OR existing.status IS DISTINCT FROM item.status
      THEN
        RAISE EXCEPTION
          'GoStay catalog seed stopped: room % in branch "%" exists with different content.',
          item.room_number, item.branch_name;
      END IF;
    ELSE
      INSERT INTO public.rooms (
        branch_id, room_type_id, room_number, name,
        price_per_night, description, status
      )
      VALUES (
        target_branch_id, target_room_type_id, item.room_number, item.room_name,
        item.price, expected_description, item.status
      );
    END IF;
  END LOOP;

  WITH expected(name, city, address) AS (
    VALUES
      ('GoStay Resort & Spa Phú Quốc','Phú Quốc','Khu Bãi Dài, Phú Quốc'),
      ('GoStay Resort Nha Trang','Nha Trang','Khu Hòn Tre, Nha Trang'),
      ('GoStay Resort & Golf Nam Hội An','Nam Hội An','Khu ven biển Nam Hội An, Quảng Nam'),
      ('GoStay Resort & Spa Hạ Long','Hạ Long','Khu Bãi Cháy, Hạ Long, Quảng Ninh')
  )
  SELECT count(*) INTO branch_count
  FROM expected
  JOIN public.branches AS branch
    ON branch.name = expected.name AND branch.city = expected.city
   AND branch.address = expected.address AND branch.phone IS NULL
   AND branch.status = 'active';

  SELECT count(*) INTO room_type_count
  FROM public.room_types
  WHERE name IN (
      'Deluxe Hướng Vườn 2 Giường Đơn', 'Deluxe Hướng Vườn Giường Đôi',
      'Deluxe Hướng Biển 2 Giường Đơn', 'Deluxe Hướng Biển Giường Đôi',
      'Deluxe Hướng Vịnh Giường Đôi', 'Junior Suite Hướng Vườn Giường Đôi',
      'Junior Suite Hướng Biển Giường Đôi', 'Phòng Gia Đình', 'Biệt Thự 3 Phòng Ngủ Có Hồ Bơi'
    );

  SELECT
    count(*),
    count(*) FILTER (WHERE room.status = 'available'),
    count(*) FILTER (WHERE room.status = 'maintenance'),
    count(*) FILTER (WHERE room.status = 'inactive'),
    count(*) FILTER (WHERE room.price_per_night < 800000),
    count(*) FILTER (WHERE branch.id IS NULL OR room_type.id IS NULL),
    count(*) FILTER (WHERE room.price_per_night < room_type.base_price)
  INTO room_count, available_count, maintenance_count, inactive_count,
    budget_count, orphan_count, below_base_count
  FROM public.rooms AS room
  LEFT JOIN public.branches AS branch ON branch.id = room.branch_id
  LEFT JOIN public.room_types AS room_type ON room_type.id = room.room_type_id
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

  SELECT count(*) INTO duplicate_count
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

  WITH expected(branch_name, room_number) AS (
    VALUES
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
  SELECT count(*)
  INTO image_count_after
  FROM public.room_images AS image
  JOIN public.rooms AS room ON room.id = image.room_id
  JOIN public.branches AS branch ON branch.id = room.branch_id
  JOIN expected
    ON expected.branch_name = branch.name
   AND expected.room_number = room.room_number;

  IF branch_count <> 4 OR room_type_count <> 9 OR room_count <> 20
     OR available_count <> 15 OR maintenance_count <> 3 OR inactive_count <> 2
     OR budget_count <> 2 OR orphan_count <> 0 OR duplicate_count <> 0
     OR below_base_count <> 0 OR image_count_after <> image_count_before
  THEN
    RAISE EXCEPTION
      'GoStay catalog seed postcheck failed: branches %, room_types %, rooms %, statuses %/%/%, budget %, orphans %, duplicates %, below_base %, images_before/after %/%',
      branch_count, room_type_count, room_count,
      available_count, maintenance_count, inactive_count,
      budget_count, orphan_count, duplicate_count, below_base_count,
      image_count_before, image_count_after;
  END IF;

  RAISE NOTICE
    'PASS | seed.postcheck | 4 branches, 9 room types, 20 rooms (15/3/2), 2 budget rooms, no duplicates/orphans/below-base prices, and no new room images.';
END;
$seed$;

COMMIT;

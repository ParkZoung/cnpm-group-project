/*
 * GoStay catalog v1 — read-only preflight.
 * This file performs no INSERT, UPDATE, DELETE, DDL, or persistent writes.
 */

DO $preflight$
DECLARE
  missing_table_count integer;
  missing_column_count integer;
  invalid_constraint_count integer := 0;
  branch_match_count integer;
  branch_conflict_count integer;
  room_type_match_count integer;
  room_type_conflict_count integer;
  room_match_count integer;
  room_conflict_count integer;
  room_duplicate_count integer;
BEGIN
  SELECT count(*)
  INTO missing_table_count
  FROM (VALUES
    ('branches'),
    ('room_types'),
    ('rooms'),
    ('room_images')
  ) AS expected(table_name)
  WHERE pg_catalog.to_regclass('public.' || expected.table_name) IS NULL;

  IF missing_table_count > 0 THEN
    RAISE NOTICE 'FAIL | schema.tables | % required catalog table(s) are missing.', missing_table_count;
    RAISE NOTICE 'FAIL | preflight | Remaining checks skipped because the schema is incomplete.';
    RETURN;
  END IF;
  RAISE NOTICE 'PASS | schema.tables | All 4 required catalog tables exist.';

  WITH expected(table_name, column_name, data_type, nullable) AS (
    VALUES
      ('branches', 'id', 'bigint', 'NO'),
      ('branches', 'name', 'character varying', 'NO'),
      ('branches', 'address', 'text', 'NO'),
      ('branches', 'city', 'character varying', 'NO'),
      ('branches', 'phone', 'character varying', 'YES'),
      ('branches', 'status', 'character varying', 'NO'),
      ('branches', 'created_at', 'timestamp with time zone', 'NO'),
      ('room_types', 'id', 'bigint', 'NO'),
      ('room_types', 'name', 'character varying', 'NO'),
      ('room_types', 'description', 'text', 'YES'),
      ('room_types', 'capacity', 'integer', 'NO'),
      ('room_types', 'bed_type', 'character varying', 'YES'),
      ('room_types', 'area_m2', 'numeric', 'YES'),
      ('room_types', 'base_price', 'bigint', 'NO'),
      ('room_types', 'created_at', 'timestamp with time zone', 'NO'),
      ('rooms', 'id', 'bigint', 'NO'),
      ('rooms', 'branch_id', 'bigint', 'NO'),
      ('rooms', 'room_type_id', 'bigint', 'NO'),
      ('rooms', 'room_number', 'character varying', 'NO'),
      ('rooms', 'name', 'character varying', 'NO'),
      ('rooms', 'price_per_night', 'bigint', 'NO'),
      ('rooms', 'description', 'text', 'YES'),
      ('rooms', 'status', 'character varying', 'NO'),
      ('rooms', 'created_at', 'timestamp with time zone', 'NO'),
      ('rooms', 'updated_at', 'timestamp with time zone', 'NO'),
      ('room_images', 'id', 'bigint', 'NO'),
      ('room_images', 'room_id', 'bigint', 'NO'),
      ('room_images', 'image_url', 'text', 'NO'),
      ('room_images', 'alt_text', 'character varying', 'YES'),
      ('room_images', 'is_primary', 'boolean', 'NO'),
      ('room_images', 'sort_order', 'integer', 'NO'),
      ('room_images', 'created_at', 'timestamp with time zone', 'NO')
  )
  SELECT count(*)
  INTO missing_column_count
  FROM expected
  LEFT JOIN information_schema.columns AS actual
    ON actual.table_schema = 'public'
   AND actual.table_name = expected.table_name
   AND actual.column_name = expected.column_name
   AND actual.data_type = expected.data_type
   AND actual.is_nullable = expected.nullable
  WHERE actual.column_name IS NULL;

  IF missing_column_count = 0 THEN
    RAISE NOTICE 'PASS | schema.columns | All required columns, types, and nullability rules match.';
  ELSE
    RAISE NOTICE 'FAIL | schema.columns | % required column definition(s) are missing or different.', missing_column_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS con
    JOIN pg_catalog.pg_class AS rel ON rel.oid = con.conrelid
    JOIN pg_catalog.pg_namespace AS ns ON ns.oid = rel.relnamespace
    WHERE ns.nspname = 'public' AND rel.relname = 'branches'
      AND con.contype = 'u'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) = 'UNIQUE (name)'
  ) THEN invalid_constraint_count := invalid_constraint_count + 1; END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS con
    JOIN pg_catalog.pg_class AS rel ON rel.oid = con.conrelid
    JOIN pg_catalog.pg_namespace AS ns ON ns.oid = rel.relnamespace
    WHERE ns.nspname = 'public' AND rel.relname = 'room_types'
      AND con.contype = 'u'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) = 'UNIQUE (name)'
  ) THEN invalid_constraint_count := invalid_constraint_count + 1; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS con
    WHERE con.conrelid = 'public.rooms'::regclass AND con.contype = 'f'
      AND pg_catalog.pg_get_constraintdef(con.oid, true)
        = 'FOREIGN KEY (branch_id) REFERENCES branches(id)'
  ) THEN invalid_constraint_count := invalid_constraint_count + 1; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS con
    WHERE con.conrelid = 'public.rooms'::regclass AND con.contype = 'f'
      AND pg_catalog.pg_get_constraintdef(con.oid, true)
        = 'FOREIGN KEY (room_type_id) REFERENCES room_types(id)'
  ) THEN invalid_constraint_count := invalid_constraint_count + 1; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS con
    WHERE con.conrelid = 'public.room_images'::regclass AND con.contype = 'f'
      AND pg_catalog.pg_get_constraintdef(con.oid, true)
        = 'FOREIGN KEY (room_id) REFERENCES rooms(id)'
  ) THEN invalid_constraint_count := invalid_constraint_count + 1; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS con
    WHERE con.conrelid = 'public.branches'::regclass AND con.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%active%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%inactive%'
  ) THEN invalid_constraint_count := invalid_constraint_count + 1; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS con
    WHERE con.conrelid = 'public.rooms'::regclass AND con.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%available%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%maintenance%'
      AND pg_catalog.pg_get_constraintdef(con.oid, true) ILIKE '%inactive%'
  ) THEN invalid_constraint_count := invalid_constraint_count + 1; END IF;

  IF invalid_constraint_count = 0 THEN
    RAISE NOTICE 'PASS | schema.constraints | Unique, foreign-key, and status constraints match seed assumptions.';
  ELSE
    RAISE NOTICE 'FAIL | schema.constraints | % required constraint assumption(s) differ.', invalid_constraint_count;
  END IF;

  WITH expected(name, city, address, phone, status) AS (
    VALUES
      ('GoStay Resort & Spa Phú Quốc', 'Phú Quốc', 'Khu Bãi Dài, Phú Quốc', NULL::varchar, 'active'),
      ('GoStay Resort Nha Trang', 'Nha Trang', 'Khu Hòn Tre, Nha Trang', NULL::varchar, 'active'),
      ('GoStay Resort & Golf Nam Hội An', 'Nam Hội An', 'Khu ven biển Nam Hội An, Quảng Nam', NULL::varchar, 'active'),
      ('GoStay Resort & Spa Hạ Long', 'Hạ Long', 'Khu Bãi Cháy, Hạ Long, Quảng Ninh', NULL::varchar, 'active')
  )
  SELECT
    count(*) FILTER (WHERE branch.id IS NOT NULL AND branch.city = expected.city
      AND branch.address = expected.address AND branch.phone IS NOT DISTINCT FROM expected.phone
      AND branch.status = expected.status),
    count(*) FILTER (WHERE branch.id IS NOT NULL AND NOT (
      branch.city = expected.city AND branch.address = expected.address
      AND branch.phone IS NOT DISTINCT FROM expected.phone AND branch.status = expected.status))
  INTO branch_match_count, branch_conflict_count
  FROM expected
  LEFT JOIN public.branches AS branch ON branch.name = expected.name;

  IF branch_conflict_count > 0 THEN
    RAISE NOTICE 'FAIL | data.branches | % same-name branch record(s) have different content.', branch_conflict_count;
  ELSIF branch_match_count > 0 THEN
    RAISE NOTICE 'PASS | data.branches | % matching branch record(s) can be safely reused; % will be inserted.',
      branch_match_count, 4 - branch_match_count;
  ELSE
    RAISE NOTICE 'PASS | data.branches | No branch-name conflicts; all 4 branches can be inserted.';
  END IF;

  WITH expected(name, description, capacity, bed_type, area_m2, base_price) AS (
    VALUES
      ('Deluxe Hướng Vườn 2 Giường Đơn', 'Phòng rộng rãi với hai giường đơn và tầm nhìn hướng khu vườn xanh mát.', 2, '2 giường đơn', 38::numeric, 750000::bigint),
      ('Deluxe Hướng Vườn Giường Đôi', 'Phòng giường đôi dành cho hai khách, có không gian nghỉ thoáng và hướng vườn.', 2, '1 giường King', 38::numeric, 900000::bigint),
      ('Deluxe Hướng Biển 2 Giường Đơn', 'Phòng hai giường đơn với ban công thoáng, đón ánh sáng tự nhiên và hướng biển.', 2, '2 giường đơn', 40::numeric, 1050000::bigint),
      ('Deluxe Hướng Biển Giường Đôi', 'Phòng giường đôi với không gian nghỉ tiện nghi và tầm nhìn hướng biển.', 2, '1 giường King', 40::numeric, 1200000::bigint),
      ('Deluxe Hướng Vịnh Giường Đôi', 'Phòng giường đôi có cửa sổ rộng và tầm nhìn hướng vịnh Hạ Long.', 2, '1 giường King', 42::numeric, 1200000::bigint),
      ('Junior Suite Hướng Vườn Giường Đôi', 'Suite hướng vườn gồm khu vực nghỉ và tiếp khách, phù hợp cho kỳ lưu trú dài ngày.', 3, '1 giường King và sofa', 50::numeric, 1350000::bigint),
      ('Junior Suite Hướng Biển Giường Đôi', 'Suite hướng biển có khu vực nghỉ và tiếp khách riêng, mang lại không gian thoải mái.', 3, '1 giường King và sofa', 52::numeric, 1550000::bigint),
      ('Phòng Gia Đình', 'Phòng dành cho gia đình, bố trí nhiều chỗ ngủ và khu vực sinh hoạt chung.', 4, '1 giường King và 2 giường đơn', 65::numeric, 1700000::bigint),
      ('Biệt Thự 3 Phòng Ngủ Có Hồ Bơi', 'Biệt thự ba phòng ngủ có hồ bơi và không gian sinh hoạt riêng, phù hợp tối đa sáu khách.', 6, '3 giường King', 180::numeric, 2000000::bigint)
  )
  SELECT
    count(*) FILTER (WHERE room_type.id IS NOT NULL
      AND room_type.description IS NOT DISTINCT FROM expected.description
      AND room_type.capacity IS NOT DISTINCT FROM expected.capacity
      AND room_type.bed_type IS NOT DISTINCT FROM expected.bed_type
      AND room_type.area_m2 IS NOT DISTINCT FROM expected.area_m2
      AND room_type.base_price IS NOT DISTINCT FROM expected.base_price),
    count(*) FILTER (WHERE room_type.id IS NOT NULL AND (
      room_type.description IS DISTINCT FROM expected.description
      OR room_type.capacity IS DISTINCT FROM expected.capacity
      OR room_type.bed_type IS DISTINCT FROM expected.bed_type
      OR room_type.area_m2 IS DISTINCT FROM expected.area_m2
      OR room_type.base_price IS DISTINCT FROM expected.base_price))
  INTO room_type_match_count, room_type_conflict_count
  FROM expected
  LEFT JOIN public.room_types AS room_type ON room_type.name = expected.name;

  IF room_type_conflict_count > 0 THEN
    RAISE NOTICE 'FAIL | data.room_types | % same-name room type record(s) have different content.', room_type_conflict_count;
  ELSIF room_type_match_count > 0 THEN
    RAISE NOTICE 'PASS | data.room_types | % matching room type record(s) can be reused; % will be inserted.',
      room_type_match_count, 9 - room_type_match_count;
  ELSE
    RAISE NOTICE 'PASS | data.room_types | No room-type-name conflicts; all 9 room types can be inserted.';
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
  ),
  collisions AS (
    SELECT expected.*, room.id, room.name AS actual_name, actual_type.name AS actual_type_name,
      room.price_per_night AS actual_price, room.status AS actual_status,
      room.description AS actual_description,
      pg_catalog.format(
        'Phòng %s tại %s thuộc hạng %s, được bố trí phù hợp tối đa %s khách.',
        expected.room_number, expected.branch_name, expected.room_type_name, expected_type.capacity
      ) AS expected_description
    FROM expected
    JOIN public.branches AS branch ON branch.name = expected.branch_name
    JOIN public.rooms AS room
      ON room.branch_id = branch.id AND room.room_number = expected.room_number
    LEFT JOIN public.room_types AS actual_type ON actual_type.id = room.room_type_id
    LEFT JOIN public.room_types AS expected_type ON expected_type.name = expected.room_type_name
  )
  SELECT
    count(*) FILTER (WHERE actual_name IS NOT DISTINCT FROM room_name
      AND actual_type_name IS NOT DISTINCT FROM room_type_name
      AND actual_price IS NOT DISTINCT FROM price
      AND actual_status IS NOT DISTINCT FROM status
      AND actual_description IS NOT DISTINCT FROM expected_description),
    count(*) FILTER (WHERE actual_name IS DISTINCT FROM room_name
      OR actual_type_name IS DISTINCT FROM room_type_name
      OR actual_price IS DISTINCT FROM price
      OR actual_status IS DISTINCT FROM status
      OR actual_description IS DISTINCT FROM expected_description)
  INTO room_match_count, room_conflict_count
  FROM collisions;

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
  INTO room_duplicate_count
  FROM (
    SELECT room.branch_id, room.room_number
    FROM expected
    JOIN public.branches AS branch ON branch.name = expected.branch_name
    JOIN public.rooms AS room
      ON room.branch_id = branch.id AND room.room_number = expected.room_number
    GROUP BY room.branch_id, room.room_number
    HAVING count(*) > 1
  ) AS duplicates;

  IF room_duplicate_count > 0 THEN
    RAISE NOTICE 'FAIL | data.rooms | % duplicate branch-and-room-number group(s) exist.', room_duplicate_count;
  ELSIF room_conflict_count > 0 THEN
    RAISE NOTICE 'FAIL | data.rooms | % branch-and-room-number collision(s) contain different data.', room_conflict_count;
  ELSIF room_match_count > 0 THEN
    RAISE NOTICE 'WARNING | data.rooms | % matching physical room(s) already exist and would be reused.', room_match_count;
  ELSE
    RAISE NOTICE 'PASS | data.rooms | No room-number collisions were found in existing seed branches.';
  END IF;

  IF missing_column_count = 0 AND invalid_constraint_count = 0
     AND branch_conflict_count = 0 AND room_type_conflict_count = 0
     AND room_conflict_count = 0 AND room_duplicate_count = 0 THEN
    RAISE NOTICE 'PASS | preflight.summary | Seed assumptions and existing same-name data are compatible.';
  ELSE
    RAISE NOTICE 'FAIL | preflight.summary | Resolve reported failures before running the seed.';
  END IF;
END;
$preflight$;

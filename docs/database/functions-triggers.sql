-- =========================================================
-- GOSTAY DATABASE FUNCTIONS AND TRIGGERS
-- Nguồn: Supabase PostgreSQL hiện tại
-- Mục đích: tài liệu hóa và phục vụ audit
--
-- CẢNH BÁO:
-- Không chạy lại toàn bộ file trên production
-- nếu chưa kiểm tra kỹ.
-- =========================================================


-- =========================================================
-- 1. EVENT TRIGGER FUNCTION: AUTO ENABLE RLS
-- =========================================================

-- Tự động bật Row Level Security khi một bảng mới
-- được tạo trong schema public.

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN (
      'CREATE TABLE',
      'CREATE TABLE AS',
      'SELECT INTO'
    )
      AND object_type IN ('table', 'partitioned table')
  LOOP
    IF cmd.schema_name IS NOT NULL
       AND cmd.schema_name IN ('public')
       AND cmd.schema_name NOT IN ('pg_catalog', 'information_schema')
       AND cmd.schema_name NOT LIKE 'pg_toast%'
       AND cmd.schema_name NOT LIKE 'pg_temp%'
    THEN
      BEGIN
        EXECUTE format(
          'alter table if exists %s enable row level security',
          cmd.object_identity
        );

        RAISE LOG
          'rls_auto_enable: enabled RLS on %',
          cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG
            'rls_auto_enable: failed to enable RLS on %',
            cmd.object_identity;
      END;
    ELSE
      RAISE LOG
        'rls_auto_enable: skip % (either system schema or not in enforced list: %.)',
        cmd.object_identity,
        cmd.schema_name;
    END IF;
  END LOOP;
END;
$function$;
-- =========================================================
-- EVENT TRIGGER: AUTOMATICALLY ENABLE RLS
-- =========================================================

-- Khi một bảng mới được tạo trong schema public,
-- event trigger này gọi public.rls_auto_enable()
-- để tự động bật Row Level Security.

CREATE EVENT TRIGGER ensure_rls
ON ddl_command_end
WHEN TAG IN (
  'CREATE TABLE',
  'CREATE TABLE AS',
  'SELECT INTO'
)
EXECUTE FUNCTION public.rls_auto_enable();

-- =========================================================
-- 2. TRIGGER FUNCTION: UPDATE updated_at
-- =========================================================

-- Tự động cập nhật cột updated_at trước khi bản ghi được sửa.

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;


-- =========================================================
-- 3. TABLE TRIGGERS
-- =========================================================

-- Tự động cập nhật bookings.updated_at.

CREATE TRIGGER trg_bookings_updated_at
BEFORE UPDATE ON public.bookings
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();


-- Tự động cập nhật rooms.updated_at.

CREATE TRIGGER trg_rooms_updated_at
BEFORE UPDATE ON public.rooms
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();


-- =========================================================
-- 4. CURRENT FUNCTION PRIVILEGES
-- =========================================================

-- public.rls_auto_enable
-- PUBLIC: EXECUTE
-- postgres: EXECUTE
--
-- public.set_updated_at
-- PUBLIC: EXECUTE
-- postgres: EXECUTE
--
-- Hai function này có kiểu trả về event_trigger và trigger,
-- nên không phải RPC thông thường để frontend gọi trực tiếp.
-- Codex vẫn cần kiểm tra quyền và mục đích sử dụng.


-- =========================================================
-- 5. CURRENT AUDIT NOTES
-- =========================================================

-- HIỆN ĐÃ CÓ:
--
-- 1. Tự động bật RLS khi tạo bảng mới trong schema public.
-- 2. Tự động cập nhật bookings.updated_at.
-- 3. Tự động cập nhật rooms.updated_at.


-- CHƯA TÌM THẤY:
--
-- 1. Trigger tự động tạo profiles sau khi đăng ký Supabase Auth.
-- 2. Function/RPC tạo booking an toàn.
-- 3. Function kiểm tra phòng trống.
-- 4. Function hoặc constraint chống booking trùng thời gian.
-- 5. Function tự tính number_of_nights.
-- 6. Function tự tính subtotal, tax_amount và total_amount.
-- 7. Trigger ghi booking_status_history.
-- 8. Trigger tự cập nhật promotions.updated_at.
-- 9. Function kiểm tra role admin.


-- TODO GIAI ĐOẠN 1:
--
-- 1. Thiết kế RPC tạo booking an toàn.
-- 2. Không tin giá, tổng tiền và user_id do frontend gửi.
-- 3. Gắn booking với auth.uid() tại database/server.
-- 4. Chống hai booking cùng phòng bị trùng ngày.
-- 5. Tính giá tại database hoặc server.
-- 6. Ghi lịch sử thay đổi booking_status.
-- 7. Kiểm tra việc tạo profile sau khi đăng ký.
-- =========================================================
-- CURRENT AUDIT NOTES
-- =========================================================

-- ĐÃ XÁC NHẬN:
--
-- 1. Event trigger ensure_rls đang ENABLED.
-- 2. Khi tạo bảng mới trong public, RLS sẽ được tự động bật.
-- 3. Function này chỉ bật RLS, không tự tạo policy.
--
-- RỦI RO:
--
-- Bảng mới có thể rơi vào trạng thái:
-- RLS ENABLED nhưng không có policy.
-- Khi đó frontend dùng anon/authenticated có thể không truy cập được.
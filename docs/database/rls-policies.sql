-- =========================================================
-- GOSTAY ROW LEVEL SECURITY
-- Trạng thái thực tế được xuất từ Supabase
-- File dùng để tài liệu hóa và audit.
-- Không chạy trực tiếp trên production khi chưa kiểm tra.
-- =========================================================


-- =========================================================
-- CURRENT RLS STATUS
-- =========================================================

-- amenities: ENABLED
-- booking_status_history: ENABLED
-- bookings: DISABLED
-- branches: DISABLED
-- profiles: DISABLED
-- promotion_usages: ENABLED
-- promotions: ENABLED
-- room_amenities: ENABLED
-- room_images: ENABLED
-- room_types: DISABLED
-- rooms: DISABLED



CREATE POLICY "Public read active branches" ON public.branches AS PERMISSIVE FOR SELECT TO anon, authenticated USING (((status)::text = 'active'::text));
CREATE POLICY "Public read room types" ON public.room_types AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "Public read available rooms" ON public.rooms AS PERMISSIVE FOR SELECT TO anon, authenticated USING (((status)::text = 'available'::text));


-- =========================================================
-- CURRENT SECURITY GAPS
-- =========================================================

-- CRITICAL:
-- profiles đang tắt RLS.
-- Người dùng có thể có nguy cơ đọc hoặc thay đổi profile/role
-- nếu quyền bảng và API cho phép.

-- CRITICAL:
-- bookings đang tắt RLS.
-- Chưa có lớp RLS bảo đảm người dùng chỉ xem hoặc sửa
-- booking của chính mình.

-- HIGH:
-- branches, room_types và rooms có policy nhưng RLS đang tắt.
-- Các policy này không có tác dụng cho đến khi RLS được bật.

-- HIGH:
-- Các bảng sau đang bật RLS nhưng hiện chưa ghi nhận policy:
-- amenities
-- booking_status_history
-- promotion_usages
-- promotions
-- room_amenities
-- room_images
--
-- Với người dùng anon/authenticated, các bảng này có thể bị
-- chặn hoàn toàn qua Supabase API nếu không có policy phù hợp.

-- TODO GIAI ĐOẠN 1:
-- 1. Bật RLS cho profiles.
-- 2. Bật RLS cho bookings.
-- 3. Bật RLS cho branches.
-- 4. Bật RLS cho room_types.
-- 5. Bật RLS cho rooms.
-- 6. Tạo policy profile theo auth.uid().
-- 7. Không cho customer tự sửa role thành admin.
-- 8. Customer chỉ xem và hủy booking của mình.
-- 9. Admin được quản lý dữ liệu theo role trong profiles.
-- 10. Kiểm tra policy cho các bảng phụ.
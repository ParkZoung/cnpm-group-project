# Báo cáo security hiện trạng của GoStay

## Thông tin lần kiểm tra

| Thuộc tính | Giá trị |
|---|---|
| Ngày kiểm tra | 2026-08-06, múi giờ Asia/Bangkok |
| Commit làm mốc kiểm tra | `d6c648f468838c2c0d242fa20422f60856c15108` |
| Môi trường local | Rà soát repository; kiểm tra syntax, migration và contract |
| Môi trường Supabase | Production project `wpecaxsuadawaxadxqhj` |
| Chế độ kiểm tra Supabase | Chỉ đọc qua Supabase Dashboard |

Không có SQL, migration hoặc cấu hình production nào được thay đổi trong lần
kiểm tra này.

## Các cơ chế đã xác minh

- Authentication sử dụng Supabase Auth thông qua Edge Function `api`.
- API route được bảo vệ xác minh bearer token bằng `auth.getUser()`.
- `window.gostaySupabase` là API facade và không chứa Supabase key.
- API sử dụng allowlist cho các table và RPC được phép truy cập.
- Các bảng ứng dụng chính trên production đã bật RLS với policy cho
  `customer`, `staff` và `admin`.
- Giá booking và quyền sở hữu booking được PostgreSQL RPC quyết định.
- Database có cơ chế ngăn các booking còn hiệu lực bị trùng thời gian.
- Production đang có hai Edge Function: `api` và `recommend-rooms`.

## Các vấn đề còn mở

### 1. Migration history chưa khớp repository

- Production ghi nhận 14 migration, trong khi commit được kiểm tra có 17 file.
- Object tương ứng với các migration từ `20260805000800` đến `20260805001000`
  đã tồn tại nhưng thiếu bản ghi history.
- Version `20260805000500` trên production có tên `room_image_storage`, trong khi
  repository dùng version này cho `admin_profiles_with_email`.

Không được chạy lại trực tiếp các migration trên cho tới khi export schema và
repair/baseline migration history.

### 2. Cảnh báo từ Supabase Security Advisor

Kết quả tại thời điểm kiểm tra:

| Mức độ | Số lượng |
|---|---:|
| Error | 0 |
| Warning | 30 |
| Thông tin | 3 |

Các warning đáng chú ý gồm:

- `set_updated_at` có `search_path` có thể thay đổi;
- function `rls_auto_enable` cho phép public execute;
- bucket `room-images` có quyền liệt kê public rộng;
- một số `SECURITY DEFINER` RPC cấp quyền execute cho role `authenticated`.

Các RPC trên cần được xác minh rằng luôn kiểm tra role và phạm vi dữ liệu bên
trong function trước khi thay đổi grant.

### 3. Staging, backup và logs

- Dashboard chưa cho thấy staging project hoặc branch độc lập.
- Dashboard chưa hiển thị backup/restore point đã cấu hình.
- Màn hình Postgres logs mới không trả về bản ghi, nên chưa thể đối chiếu các số
  liệu lỗi tổng quan.

## Kết luận hiện tại

Repository đã được gia cố đáng kể so với
[`STAGE1_AUDIT.md`](STAGE1_AUDIT.md) và phù hợp với luồng demo MVP hiện tại.
Tuy nhiên, chưa an toàn để replay hoặc tự động push migration lên production.

Trước lần phát hành database tiếp theo, cần:

1. tạo Supabase staging độc lập;
2. đối chiếu schema và migration history;
3. chạy runtime security cùng core/admin E2E trên staging;
4. chuẩn bị backup, restore point và phương án rollback.

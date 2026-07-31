# Ranh giới bảo mật FE–BE–DB

## Kiến trúc bắt buộc

```text
Browser (FE) ──HTTPS/JSON──> Edge Function `api` (BE) ──Supabase SDK──> PostgreSQL
```

Frontend không chứa Supabase publishable/service key và không khởi tạo database
client. `frontend/js/supabase-client.js` là adapter của API ứng dụng; tên global
được giữ lại để các màn hình cũ không phải thay đổi đồng loạt.

## Xác thực

- Đăng ký, đăng nhập và làm mới phiên đi qua `/api/auth/register`,
  `/api/auth/login` và `/api/auth/refresh`.
- Supabase Auth lưu mật khẩu dưới dạng hash; mật khẩu thô không được lưu trong
  profile, localStorage, log hoặc database nghiệp vụ.
- Middleware `requireUser` xác minh JWT bằng `auth.getUser()` trước mọi thao tác
  ghi và RPC được bảo vệ.
- Payload đăng ký chỉ cho phép `full_name` và `phone`. `role` và `status` không
  được nhận từ client; trigger database luôn tạo tài khoản `customer/active`.
- Browser lưu access/refresh token của phiên ứng dụng, không lưu database
  credential.

## Chống SQL injection

API không nhận hoặc thực thi câu SQL. Tên bảng, RPC và function đều dùng
allowlist; tên cột/operator được kiểm tra định dạng; giá trị được truyền qua
Supabase SDK dưới dạng tham số. Không được bổ sung endpoint nhận raw SQL hoặc
nối chuỗi dữ liệu người dùng vào truy vấn.

RLS và quyền PostgreSQL vẫn là lớp bảo vệ cuối cùng. API sử dụng JWT của người
dùng với anon key phía server, không dùng `service_role` để bỏ qua RLS.

## Triển khai

Deploy Edge Function `api` với cấu hình `verify_jwt = false` vì endpoint login và
register chưa có JWT. Đây không phải là bỏ xác thực: các route bảo vệ gọi
`requireUser` rõ ràng trong function. `SUPABASE_URL` và `SUPABASE_ANON_KEY` phải
chỉ tồn tại trong environment của Edge Function.

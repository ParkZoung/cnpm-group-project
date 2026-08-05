# Cấu trúc dự án GoStay

## Phạm vi các thư mục

| Thư mục | Trách nhiệm |
|---|---|
| `frontend/` | Giao diện chạy trên trình duyệt: HTML, CSS và JavaScript. |
| `backend/supabase/` | Edge Functions, migrations và cấu hình triển khai Supabase. |
| `tests/` | Kiểm thử end-to-end, contract và runtime security. |
| `docs/` | Tài liệu sản phẩm, kiến trúc, database, bảo mật và kiểm thử. |

Việc đặt dự án Supabase trong `backend/` chỉ nhằm tổ chức repository. Thay đổi này
không đổi tên nền tảng Supabase, biến môi trường, package npm, Edge Function đã
triển khai hoặc URL production.

## Luồng request

```text
HTML
  -> controller của trang
  -> service / API client phía frontend
  -> Edge Function api
  -> controller phía backend
  -> repository / RPC
  -> PostgreSQL
```

`frontend/js/core/api-client.js` chịu trách nhiệm gửi request. Cấu hình public
theo môi trường nằm trong `frontend/js/config/environment.js`. Luồng tạo và hủy
booking đã dùng `frontend/js/services/booking-api.js`; các màn hình catalog,
profile và admin vẫn dùng compatibility facade trong thời gian được tách dần.

### Vai trò của `window.gostaySupabase`

`window.gostaySupabase` được giữ lại để các trang cũ tiếp tục hoạt động trong quá
trình chuyển đổi. Dù có tên như vậy, đối tượng này:

- không phải Supabase database client chạy trong trình duyệt;
- không chứa database credential hoặc service-role key;
- chỉ là compatibility facade gọi `frontend/js/core/api-client.js`;
- không kết nối trực tiếp tới PostgreSQL.

Request được gửi tới Edge Function `api`, sau đó được xác thực bằng JWT và kiểm
soát quyền bằng RLS cùng các RPC đã review. Kiểm tra role trên frontend chỉ hỗ trợ
trải nghiệm người dùng, không phải ranh giới bảo mật.

Role và trạng thái nghiệp vụ chuẩn được mô tả tại
[`DOMAIN_TERMS.md`](DOMAIN_TERMS.md).

## Luồng booking hiện tại

```text
Tìm phòng
  -> RPC search_available_rooms
  -> xem chi tiết phòng
  -> giỏ hàng local
  -> booking-api
  -> RPC create_booking
  -> lịch sử booking
  -> booking-api
  -> RPC cancel_own_booking
```

Các mutation của Admin tiếp tục đi qua RPC dành riêng cho Admin. Cơ chế phân
quyền RLS/RPC không thay đổi và được kiểm tra bằng `npm run test:security`.

## Quy tắc khi thay đổi cấu trúc

- Giữ nguyên các HTML route công khai trong thời gian tách module MVC.
- Duy trì API response contract hiện tại khi tách backend.
- Không chuyển trách nhiệm phân quyền ra khỏi RLS hoặc `SECURITY DEFINER` RPC.
- Không chạy lại migration lịch sử trên production trước khi xử lý schema drift
  và migration history.
- Chỉ refactor từng feature customer/admin và chạy lại E2E sau mỗi đợt.

## Đổi tên được hoãn lại

`admin-products.html` và `admin-categories.html` hiện lần lượt phục vụ quản lý
phòng và chi nhánh. Chỉ đổi thành `admin-rooms.html`, `admin-branches.html` và
tách CSS theo feature sau khi bản MVP/demo ổn định. Đổi tên ở thời điểm hiện tại
sẽ ảnh hưởng route công khai, navigation link và đường dẫn E2E.

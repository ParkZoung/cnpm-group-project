# Thuật ngữ nghiệp vụ chuẩn của GoStay

Các giá trị tiếng Anh bên dưới là giá trị chuẩn dùng trong JavaScript, API và
SQL. Giao diện có thể dịch sang tiếng Việt, nhưng không được tự tạo thêm trạng
thái hoặc dùng nhãn hiển thị làm giá trị gửi tới backend.

## Role tài khoản

| Giá trị | Ý nghĩa |
|---|---|
| `customer` | Khách hàng tìm phòng, đặt phòng và quản lý booking của chính mình. |
| `staff` | Nhân viên đang hoạt động tại chi nhánh được chọn trong phiên làm việc. |
| `admin` | Quản trị viên quản lý catalog, booking và quyền truy cập. |

## Trạng thái profile

| Giá trị | Ý nghĩa |
|---|---|
| `active` | Tài khoản được sử dụng các chức năng phù hợp với role. |
| `inactive` | Tài khoản hiện không hoạt động. |
| `blocked` | Tài khoản bị quản trị viên chặn truy cập. |

## Trạng thái booking

| Giá trị | Ý nghĩa |
|---|---|
| `pending` | Booking đang chờ xác nhận. |
| `confirmed` | Booking đã được xác nhận và giữ chỗ. |
| `checked_in` | Khách đã nhận phòng. |
| `completed` | Khách đã trả phòng và hoàn tất kỳ lưu trú. |
| `cancelled` | Booking đã bị hủy. |

Các trạng thái `pending`, `confirmed` và `checked_in` giữ tồn kho phòng. Quy tắc
chuyển trạng thái do PostgreSQL RPC thực thi; nhãn trên frontend không quyết định
luồng nghiệp vụ.

## Trạng thái và hình thức thanh toán

### `payment_status`

| Giá trị | Ý nghĩa |
|---|---|
| `unpaid` | Chưa ghi nhận thanh toán. |
| `pending` | Đang chờ xử lý hoặc xác minh thanh toán. |
| `partially_paid` | Đã thanh toán một phần. |
| `paid` | Đã thanh toán đủ. |
| `failed` | Thanh toán thất bại. |
| `refunded` | Khoản tiền đã được hoàn lại. |

### `payment_option`

| Giá trị | Ý nghĩa |
|---|---|
| `deposit` | Thanh toán tiền đặt cọc. |
| `full` | Thanh toán toàn bộ. |

Database là nguồn quyết định số tiền cuối cùng. Việc customer khai báo đã chuyển
khoản không đồng nghĩa giao dịch đã được duyệt; Staff phải xác minh trước khi hệ
thống ghi nhận số tiền đã thanh toán.

## Trạng thái online check-in

| Giá trị | Ý nghĩa |
|---|---|
| `not_started` | Online check-in đã được tạo nhưng chưa khai báo thanh toán. |
| `payment_claimed` | Customer khai báo đã chuyển khoản. |
| `approved` | Staff đã duyệt thanh toán; token check-in có thể được sử dụng. |
| `rejected` | Staff từ chối yêu cầu và cung cấp lý do. |
| `consumed` | Token check-in dùng một lần đã được sử dụng. |
| `expired` | Thông tin online check-in đã hết hiệu lực. |

## Quy tắc đặt tên

- Dùng **booking** cho đơn đặt phòng và `booking_status` cho vòng đời booking.
- Dùng **payment transaction** cho một giao dịch tiền và `payment_status` cho
  trạng thái thanh toán tổng hợp của booking.
- Dùng **online check-in** cho luồng VietQR, khai báo thanh toán và cấp token.
- `window.gostaySupabase` luôn có nghĩa là API compatibility facade, không phải
  kết nối trực tiếp từ trình duyệt tới database.

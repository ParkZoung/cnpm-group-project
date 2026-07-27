# GoStay Database Notes

## 1. Mục đích tài liệu

Tài liệu này mô tả trạng thái hiện tại của database GoStay trên Supabase PostgreSQL.

Tài liệu được dùng để:

- Giúp thành viên nhóm hiểu cấu trúc dữ liệu.
- Giúp Codex đọc và audit database.
- Chuẩn bị triển khai Giai đoạn 1: Auth, phân quyền và booking an toàn.
- Chuẩn bị triển khai Giai đoạn 2: hoàn thiện luồng dữ liệu thật.
- Ghi nhận những phần database đã có và những phần còn thiếu.

> Lưu ý: Đây là tài liệu mô tả trạng thái hiện tại, không phải file migration.
> Không dùng nội dung trong tài liệu này để chạy trực tiếp trên production.

---

## 2. Công nghệ sử dụng

- Database: PostgreSQL
- Nền tảng: Supabase
- Authentication: Supabase Auth
- Schema nghiệp vụ chính: `public`
- Schema tài khoản do Supabase quản lý: `auth`

Frontend hiện kết nối với Supabase để đọc và ghi dữ liệu.

---

## 3. Danh sách bảng

Database hiện có 11 bảng trong schema `public`:

1. `profiles`
2. `branches`
3. `room_types`
4. `rooms`
5. `bookings`
6. `promotions`
7. `room_images`
8. `amenities`
9. `room_amenities`
10. `promotion_usages`
11. `booking_status_history`

---

## 4. Mô tả từng bảng

### 4.1. `profiles`

Lưu thông tin mở rộng của người dùng Supabase Auth.

Khóa chính:

- `id`

Quan hệ:

- `profiles.id` tham chiếu `auth.users.id`

Các trường quan trọng:

- `id`: ID tài khoản, kiểu UUID.
- `full_name`: họ tên người dùng.
- `phone`: số điện thoại.
- `role`: vai trò của người dùng.
- `status`: trạng thái tài khoản.
- `created_at`: thời điểm tạo profile.

Giá trị hợp lệ của `role`:

- `customer`
- `admin`

Giá trị hợp lệ của `status`:

- `active`
- `inactive`
- `blocked`

Trạng thái hiện tại:

- RLS đang tắt.
- Chưa ghi nhận RLS policy dành cho bảng này.
- Chưa tìm thấy trigger tự động tạo profile sau khi tài khoản được tạo trong `auth.users`.

Rủi ro cần kiểm tra:

- Người dùng có thể tự thay đổi `role` thành `admin`.
- Người dùng có thể đọc hoặc sửa profile của người khác.
- Tài khoản bị `blocked` có thực sự bị ngăn sử dụng hệ thống hay không.

---

### 4.2. `branches`

Lưu thông tin các chi nhánh thuộc chuỗi khách sạn GoStay.

Khóa chính:

- `id`

Các trường quan trọng:

- `name`: tên chi nhánh, không được trùng.
- `address`: địa chỉ.
- `city`: thành phố.
- `phone`: số điện thoại.
- `status`: trạng thái chi nhánh.
- `created_at`: thời điểm tạo.

Giá trị hợp lệ của `status`:

- `active`
- `inactive`

Trạng thái hiện tại:

- RLS đang tắt.
- Có policy tên `public read active branches`.
- Vì RLS đang tắt nên policy chưa có tác dụng bảo vệ dữ liệu.

---

### 4.3. `room_types`

Lưu các loại phòng của GoStay.

Khóa chính:

- `id`

Các trường quan trọng:

- `name`: tên loại phòng, không được trùng.
- `description`: mô tả.
- `capacity`: sức chứa tối đa, phải lớn hơn 0.
- `bed_type`: loại giường.
- `area_m2`: diện tích, phải lớn hơn 0 nếu có dữ liệu.
- `base_price`: giá cơ sở, phải lớn hơn 0.
- `created_at`: thời điểm tạo.

Trạng thái hiện tại:

- RLS đang tắt.
- Có policy tên `public read room types`.
- Vì RLS đang tắt nên policy chưa có tác dụng bảo vệ dữ liệu.

---

### 4.4. `rooms`

Lưu từng phòng cụ thể tại mỗi chi nhánh.

Khóa chính:

- `id`

Khóa ngoại:

- `branch_id` tham chiếu `branches.id`
- `room_type_id` tham chiếu `room_types.id`

Các trường quan trọng:

- `branch_id`: chi nhánh sở hữu phòng.
- `room_type_id`: loại phòng.
- `room_number`: số phòng.
- `name`: tên hiển thị của phòng.
- `price_per_night`: giá một đêm, phải lớn hơn 0.
- `description`: mô tả.
- `status`: trạng thái vận hành.
- `created_at`: thời điểm tạo.
- `updated_at`: thời điểm cập nhật gần nhất.

Giá trị hợp lệ của `status`:

- `available`
- `maintenance`
- `inactive`

Trạng thái hiện tại:

- RLS đang tắt.
- Có policy tên `public read available rooms`.
- Vì RLS đang tắt nên policy chưa có tác dụng bảo vệ dữ liệu.
- Có trigger `trg_rooms_updated_at` tự cập nhật `updated_at`.

Vấn đề cần kiểm tra:

- Chưa thấy constraint bảo đảm `room_number` là duy nhất trong từng chi nhánh.
- Trạng thái `available` chỉ phản ánh trạng thái vận hành, không thể thay thế việc kiểm tra phòng trống theo khoảng ngày booking.
- Cần xác định giá dùng khi đặt phòng lấy từ `rooms.price_per_night` hay `room_types.base_price`.

---

### 4.5. `bookings`

Lưu các đơn đặt phòng.

Khóa chính:

- `id`

Khóa ngoại:

- `user_id` tham chiếu `profiles.id`
- `room_id` tham chiếu `rooms.id`
- `promotion_id` tham chiếu `promotions.id`

Các trường quan trọng:

- `booking_code`: mã booking, không được trùng.
- `user_id`: người dùng đã đăng nhập tạo booking.
- `room_id`: phòng được đặt.
- `guest_name`: tên khách.
- `guest_email`: email khách.
- `guest_phone`: số điện thoại khách.
- `check_in_date`: ngày nhận phòng.
- `check_out_date`: ngày trả phòng.
- `number_of_nights`: số đêm.
- `number_of_guests`: số khách.
- `special_request`: yêu cầu đặc biệt.
- `price_per_night`: giá một đêm tại thời điểm đặt.
- `subtotal`: tiền phòng trước thuế và giảm giá.
- `tax_rate`: tỷ lệ thuế.
- `tax_amount`: số tiền thuế.
- `discount_amount`: số tiền giảm.
- `total_amount`: tổng tiền cuối cùng.
- `booking_status`: trạng thái booking.
- `payment_method`: phương thức thanh toán.
- `payment_status`: trạng thái thanh toán.
- `cancelled_at`: thời điểm hủy.
- `created_at`: thời điểm tạo.
- `updated_at`: thời điểm cập nhật.

Giá trị hợp lệ của `booking_status`:

- `pending`
- `confirmed`
- `checked_in`
- `completed`
- `cancelled`

Giá trị hợp lệ của `payment_method`:

- `pay_at_hotel`
- `online`
- `bank_transfer`

Giá trị hợp lệ của `payment_status`:

- `unpaid`
- `pending`
- `paid`
- `failed`
- `refunded`

Trạng thái hiện tại:

- `user_id` cho phép `NULL`, do đó schema hiện có khả năng hỗ trợ khách vãng lai.
- RLS đang tắt.
- Chưa ghi nhận RLS policy dành cho booking.
- Có trigger `trg_bookings_updated_at` tự cập nhật `updated_at`.
- Chưa tìm thấy RPC tạo booking an toàn.
- Chưa tìm thấy function chống đặt trùng.
- Chưa tìm thấy function tự tính giá booking.

Vấn đề cần kiểm tra:

- Chưa có constraint bảo đảm `check_out_date > check_in_date`.
- `number_of_nights` có thể không khớp với ngày nhận và ngày trả.
- `number_of_guests` chưa được kiểm tra với sức chứa của loại phòng.
- Frontend có thể đang gửi `price_per_night`, `subtotal`, `tax_amount` và `total_amount`.
- Database chưa chứng minh rằng tổng tiền được tự tính từ dữ liệu thật.
- Chưa có cơ chế database ngăn hai booking cùng phòng bị trùng thời gian.
- Chưa xác định booking phải tự động gắn với `auth.uid()` như thế nào.
- Chưa xác định cơ chế bảo vệ booking của khách vãng lai.
- Chưa xác định trạng thái nào được tính là đang giữ phòng khi kiểm tra trùng.

---

### 4.6. `promotions`

Lưu chương trình khuyến mãi.

Khóa chính:

- `id`

Các trường quan trọng:

- `name`: tên chương trình.
- `code`: mã khuyến mãi, không được trùng nếu có.
- `description`: mô tả.
- `discount_type`: loại giảm giá.
- `discount_value`: giá trị giảm.
- `min_booking_amount`: giá trị booking tối thiểu.
- `max_discount_amount`: số tiền giảm tối đa.
- `start_at`: thời điểm bắt đầu.
- `end_at`: thời điểm kết thúc.
- `usage_limit`: giới hạn lượt sử dụng.
- `used_count`: số lượt đã sử dụng.
- `status`: trạng thái.
- `created_at`: thời điểm tạo.
- `updated_at`: thời điểm cập nhật.

Giá trị hợp lệ của `discount_type`:

- `percentage`
- `fixed_amount`

Giá trị hợp lệ của `status`:

- `active`
- `inactive`
- `expired`

Trạng thái hiện tại:

- RLS đang bật.
- Chưa ghi nhận policy dành cho bảng này.
- Có cột `updated_at` nhưng chưa tìm thấy trigger tự động cập nhật.
- Chưa thấy constraint bảo đảm `end_at > start_at`.
- Chưa thấy constraint bảo đảm giảm phần trăm không vượt quá 100%.

---

### 4.7. `room_images`

Lưu hình ảnh của từng phòng.

Khóa chính:

- `id`

Khóa ngoại:

- `room_id` tham chiếu `rooms.id`

Các trường quan trọng:

- `image_url`: đường dẫn ảnh.
- `alt_text`: nội dung thay thế cho ảnh.
- `is_primary`: ảnh đại diện chính.
- `sort_order`: thứ tự hiển thị.
- `created_at`: thời điểm tạo.

Trạng thái hiện tại:

- RLS đang bật.
- Chưa ghi nhận policy dành cho bảng này.
- Chưa thấy constraint bảo đảm mỗi phòng chỉ có một ảnh chính.

---

### 4.8. `amenities`

Lưu danh mục tiện nghi.

Khóa chính:

- `id`

Các trường quan trọng:

- `name`: tên tiện nghi, không được trùng.
- `icon`: tên hoặc mã icon.
- `description`: mô tả.
- `status`: trạng thái.
- `created_at`: thời điểm tạo.

Giá trị hợp lệ của `status`:

- `active`
- `inactive`

Trạng thái hiện tại:

- RLS đang bật.
- Chưa ghi nhận policy dành cho bảng này.

---

### 4.9. `room_amenities`

Bảng trung gian thể hiện quan hệ nhiều-nhiều giữa phòng và tiện nghi.

Khóa chính tổng hợp:

- `room_id`
- `amenity_id`

Khóa ngoại:

- `room_id` tham chiếu `rooms.id`
- `amenity_id` tham chiếu `amenities.id`

Trạng thái hiện tại:

- RLS đang bật.
- Chưa ghi nhận policy dành cho bảng này.

---

### 4.10. `promotion_usages`

Lưu lịch sử sử dụng khuyến mãi.

Khóa chính:

- `id`

Khóa ngoại:

- `promotion_id` tham chiếu `promotions.id`
- `booking_id` tham chiếu `bookings.id`
- `user_id` tham chiếu `profiles.id`

Các trường quan trọng:

- `booking_id`: mỗi booking chỉ có tối đa một bản ghi sử dụng khuyến mãi.
- `discount_amount`: số tiền đã giảm.
- `used_at`: thời điểm sử dụng.

Trạng thái hiện tại:

- RLS đang bật.
- Chưa ghi nhận policy dành cho bảng này.
- Chưa thấy function đồng bộ `used_count` của promotion.
- Chưa thấy transaction bảo đảm booking và promotion usage được tạo đồng thời.

---

### 4.11. `booking_status_history`

Lưu lịch sử thay đổi trạng thái booking.

Khóa chính:

- `id`

Khóa ngoại:

- `booking_id` tham chiếu `bookings.id`
- `changed_by` tham chiếu `profiles.id`

Các trường quan trọng:

- `old_status`: trạng thái cũ.
- `new_status`: trạng thái mới.
- `changed_by`: người thực hiện thay đổi.
- `note`: ghi chú.
- `changed_at`: thời điểm thay đổi.

Trạng thái hiện tại:

- RLS đang bật.
- Chưa ghi nhận policy dành cho bảng này.
- Chưa tìm thấy trigger tự động ghi lịch sử khi `bookings.booking_status` thay đổi.

---

## 5. Quan hệ giữa các bảng

Các quan hệ chính:

```text
auth.users
    │
    │ 1 - 1
    ▼
profiles
    │
    │ 1 - N
    ▼
bookings
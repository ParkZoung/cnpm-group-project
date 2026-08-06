# GoStay — Yêu cầu sản phẩm

> **Phiên bản:** 3.0
>
> **Cập nhật:** 2026-08-06
>
> **Nguồn thuật ngữ:** [`DOMAIN_TERMS.md`](../architecture/DOMAIN_TERMS.md)
>
> **Phạm vi chuẩn:** [`PRODUCT_DIRECTION.md`](PRODUCT_DIRECTION.md)

## 1. Tổng quan

GoStay là website đặt phòng cho một chuỗi khách sạn nhỏ có nhiều chi nhánh. Hệ
thống có ba role chuẩn: `customer`, `staff` và `admin`. Đăng nhập, tìm phòng còn
trống, đặt phòng và quản trị catalog/booking là lõi sản phẩm. AI gợi ý phòng,
VietQR/online check-in và nghiệp vụ Staff là extension; các extension không được
làm gián đoạn luồng booking lõi khi dịch vụ phụ trợ gặp lỗi.

Booking hiện sử dụng `check_in_date` và `check_out_date` theo ngày. GoStay không
hỗ trợ đặt phòng theo giờ.

## 2. Vai trò

- **Customer:** quản lý tài khoản, tìm phòng, đặt/hủy phòng của chính mình, xem
  lịch sử và chủ động sử dụng các extension dành cho khách.
- **Staff:** chọn chi nhánh làm việc trong phiên, xử lý booking và giao dịch thuộc
  chi nhánh đó, xác nhận check-in/check-out và hoàn tiền theo quy trình.
- **Admin:** quản trị toàn hệ thống, bao gồm catalog, tài khoản và booking.

Mọi quyền truy cập dữ liệu phải được kiểm tra tại Edge Function và PostgreSQL
RLS/RPC. Kiểm tra role trên giao diện chỉ phục vụ trải nghiệm người dùng.

## 3. Phạm vi lõi

- Đăng ký, đăng nhập, đăng xuất và duy trì phiên bằng Supabase Auth.
- Đăng nhập Google, xác nhận email và khôi phục mật khẩu bằng OTP.
- Xem chi nhánh, loại/hạng phòng, phòng, hình ảnh và tiện nghi đang hoạt động.
- Tìm phòng còn trống theo chi nhánh, ngày lưu trú, số khách, giá và loại phòng.
- Xem chi tiết phòng và thêm lựa chọn vào giỏ hàng cục bộ.
- Tạo booking bằng giá authoritative từ database; ngăn khoảng ngày không hợp lệ,
  booking trùng và hai request đồng thời giữ cùng một phòng.
- Customer xem lịch sử và hủy booking thuộc quyền sở hữu của mình khi hợp lệ.
- Admin xem dashboard; quản lý chi nhánh, phòng, loại/hạng phòng, hình ảnh, giá,
  trạng thái, booking và tài khoản người dùng.
- Phân quyền `customer`/`staff`/`admin`, trạng thái profile và ownership bằng
  RLS, RPC, constraint và transaction phía PostgreSQL.

## 4. Phạm vi extension hiện có

### 4.1. AI gợi ý phòng

- Customer chủ động nhập nhu cầu và yêu cầu gợi ý.
- Hệ thống chỉ gửi tiêu chí cùng metadata phòng đủ điều kiện cho Edge Function
  `recommend-rooms` và Gemini.
- AI chỉ xếp hạng phòng có thật và giải thích lựa chọn; không được tạo room ID,
  giá hoặc booking.
- Khi AI lỗi, hết quota hoặc không có gợi ý, tìm kiếm thông thường vẫn hoạt động.
- Kết quả phải được gắn nhãn nội dung do AI tạo.

### 4.2. VietQR và online check-in

- Customer chọn thanh toán đủ hoặc đặt cọc theo quy tắc của database.
- Customer xem VietQR và khai báo đã chuyển khoản; khai báo không đồng nghĩa tiền
  đã được ghi nhận.
- Staff phải duyệt hoặc từ chối yêu cầu thanh toán.
- Sau khi được duyệt, hệ thống cấp thông tin/token check-in dùng một lần.
- VietQR hiện là quy trình đối chiếu thủ công, không phải cổng thanh toán tự động
  hay kết nối ngân hàng thời gian thực.

### 4.3. Staff operations

- Staff đang hoạt động chọn một chi nhánh làm việc trong phiên.
- Staff chỉ xem và xử lý booking thuộc chi nhánh đã chọn.
- Staff xác nhận booking, duyệt thanh toán, thu số dư, check-in, check-out và ghi
  nhận hoàn tiền theo transition hợp lệ.
- Không cho check-in trước ngày đến hoặc check-out trước ngày trả phòng.

## 5. Ngoài phạm vi

- Cổng thanh toán tự động, webhook ngân hàng và đối soát thời gian thực.
- Voucher, loyalty hoặc tích điểm thành viên.
- Marketplace cho nhiều khách sạn độc lập.
- Bản đồ nâng cao, chatbot, voice assistant và dynamic pricing bằng AI.
- AI tự tạo phòng, tự sửa giá hoặc tự xác nhận booking.
- Email/SMS nhắc lịch và đánh giá sau lưu trú.

## 6. User stories và acceptance criteria

### AUTH-01 — Đăng ký và xác thực tài khoản

**Role:** Customer

**Priority:** P0

- Given email chưa được sử dụng, when customer đăng ký với dữ liệu hợp lệ, then
  Supabase Auth tạo tài khoản và hệ thống hướng dẫn xác nhận email theo cấu hình.
- Given dữ liệu không hợp lệ hoặc email đã tồn tại, when đăng ký, then hệ thống
  báo lỗi an toàn và không tạo profile sai lệch.

### AUTH-02 — Đăng nhập, đăng xuất và điều hướng theo role

**Role:** Customer, Staff, Admin

**Priority:** P0

- Given tài khoản active và thông tin đúng, when đăng nhập, then hệ thống tạo
  session và điều hướng tới giao diện phù hợp với role.
- Given tài khoản bị blocked/inactive hoặc thông tin sai, when đăng nhập, then
  quyền truy cập bị từ chối.
- When người dùng đăng xuất, then session được xóa và route bảo vệ không còn truy
  cập được.

### AUTH-03 — Google OAuth và khôi phục mật khẩu

**Role:** Customer

**Priority:** P1

- Customer có thể bắt đầu đăng nhập Google và quay về đúng callback của GoStay.
- Customer có thể yêu cầu OTP khôi phục, xác minh OTP và đặt mật khẩu mới mà
  không làm lộ thông tin tài khoản.

### CAT-01 — Xem catalog và chi tiết phòng

**Role:** Public, Customer

**Priority:** P0

- Chỉ chi nhánh, phòng, loại phòng và tiện nghi được phép công khai mới xuất hiện.
- Trang chi tiết hiển thị đúng chi nhánh, giá, sức chứa, hình ảnh, tiện nghi và
  trạng thái vận hành của phòng.
- Phòng inactive/maintenance không được trình bày như phòng có thể đặt.

### SEARCH-01 — Tìm phòng còn trống

**Role:** Public, Customer

**Priority:** P0

- Given khoảng ngày hợp lệ, when tìm kiếm, then hệ thống chỉ trả phòng phù hợp
  tiêu chí và không bị booking active khác giữ trong khoảng giao nhau.
- Given ngày trả không sau ngày nhận hoặc ngày nhận ở quá khứ, then request bị từ
  chối với thông báo phù hợp.
- Given không có kết quả, then giao diện hiển thị trạng thái rỗng và cho phép đổi
  tiêu chí.

### BOOK-01 — Tạo booking an toàn

**Role:** Customer

**Priority:** P0

- Given customer đã đăng nhập và chọn phòng còn trống, when xác nhận, then
  database tự xác định giá/tổng tiền và tạo booking thuộc customer đó.
- Client không được tự quyết định `user_id`, tổng tiền, payment status hoặc trạng
  thái xác nhận.
- Hai request đồng thời cho cùng phòng và khoảng ngày xung đột chỉ được phép có
  tối đa một request thành công.

### BOOK-02 — Lịch sử và hủy booking

**Role:** Customer

**Priority:** P0

- Customer chỉ xem được booking thuộc `auth.uid()` của mình.
- Customer hủy đúng booking của mình khi trạng thái cho phép; không thể hủy hoặc
  đọc booking của customer khác dù biết UUID hay booking code.
- Lịch sử hiển thị phòng, khoảng ngày, tổng tiền và trạng thái nghiệp vụ chuẩn.

### ADMIN-01 — Quản lý catalog

**Role:** Admin

**Priority:** P0

- Admin có thể quản lý chi nhánh, phòng, loại/hạng phòng, giá, trạng thái, tiện
  nghi và hình ảnh thông qua API/RPC được bảo vệ.
- Thay đổi catalog được validate ở backend; customer hoặc staff không thể gọi
  mutation dành cho Admin.

### ADMIN-02 — Quản lý booking và tài khoản

**Role:** Admin

**Priority:** P0

- Admin có thể xem booking, cập nhật trạng thái theo transition hợp lệ và hủy
  booking khi nghiệp vụ cho phép.
- Admin có thể xem profile kèm email và quản lý trạng thái tài khoản.
- Admin không thể bỏ qua invariant giá, ownership hoặc booking overlap.

### AI-01 — Nhận gợi ý phòng

**Role:** Customer

**Priority:** P1 — Extension

- Given danh sách phòng đủ điều kiện, when customer yêu cầu AI gợi ý, then kết
  quả chỉ chứa room ID hợp lệ từ danh sách đó và lý do ngắn dựa trên metadata.
- AI không tạo booking và không thay đổi giá.
- Given dịch vụ AI lỗi hoặc không trả kết quả hợp lệ, then UI thông báo phù hợp
  và customer vẫn có thể tìm phòng thủ công.

### PAY-01 — Khai báo thanh toán VietQR

**Role:** Customer

**Priority:** P1 — Extension

- Customer chọn `full` hoặc phương án đặt cọc được database cho phép và nhận QR
  tương ứng với số tiền authoritative.
- Khi customer khai báo đã chuyển khoản, trạng thái chuyển sang chờ Staff duyệt;
  `paid_amount` không tự tăng trước khi duyệt.

### STAFF-01 — Chọn chi nhánh và xử lý booking

**Role:** Staff

**Priority:** P1 — Extension

- Staff active chọn chi nhánh làm việc và chỉ truy cập booking thuộc chi nhánh đó.
- Staff có thể xác nhận booking và duyệt/từ chối payment claim theo quyền.
- Staff ở chi nhánh khác hoặc không có phiên làm việc không được xử lý booking.

### STAFF-02 — Check-in, check-out, thu tiền và hoàn tiền

**Role:** Staff

**Priority:** P1 — Extension

- Token check-in chỉ dùng cho booking tương ứng, sau khi payment claim được duyệt,
  và không thể tái sử dụng sau khi hoàn tất.
- Staff không thể check-in trước ngày nhận hoặc check-out trước ngày trả.
- Check-out yêu cầu số tiền đã thu đáp ứng quy tắc; mọi khoản thu/hoàn tiền được
  ghi vào `payment_transactions` để audit.

## 7. Yêu cầu phi chức năng

- **Bảo mật:** không đưa secret/service-role key vào frontend; không dùng
  localStorage làm nguồn phân quyền; dữ liệu động phải được render an toàn.
- **Toàn vẹn:** database là nguồn quyết định ownership, availability, giá, tiền
  và transition trạng thái.
- **Khả dụng:** lỗi AI không được chặn tìm kiếm hoặc booking lõi.
- **Kiểm thử:** duy trì static checks, migration version check, customer/admin E2E,
  runtime security và Staff/payment contract tests.
- **Triển khai:** không chạy `supabase db push` lên production cho tới khi schema
  và migration history được baseline/reconcile theo tài liệu deployment safety.

## 8. Truy vết tài liệu

- Phạm vi sản phẩm: [`PRODUCT_DIRECTION.md`](PRODUCT_DIRECTION.md)
- Thuật ngữ và trạng thái: [`DOMAIN_TERMS.md`](../architecture/DOMAIN_TERMS.md)
- Kiến trúc: [`PROJECT_STRUCTURE.md`](../architecture/PROJECT_STRUCTURE.md)
- Ranh giới bảo mật: [`API_SECURITY_BOUNDARY.md`](../architecture/API_SECURITY_BOUNDARY.md)
- Trạng thái bảo mật: [`CURRENT_SECURITY_STATUS.md`](../security/CURRENT_SECURITY_STATUS.md)
- Kiểm thử: [`E2E.md`](../testing/E2E.md)

# GoStay — Hướng sản phẩm (Product Direction)

## Phạm vi phát hành hiện hành

Từ ngày 2026-08-06, GoStay phân chia chức năng thành hai lớp:

- **Core:** Supabase Auth; tìm kiếm phòng khả dụng; xem chi tiết; tạo, xem và
  hủy booking; Admin quản lý catalog, booking và tài khoản.
- **Extension:** AI gợi ý phòng; VietQR và online check-in; Staff xử lý booking,
  đối chiếu thanh toán, check-in/check-out và hoàn tiền tại chi nhánh.

Extension là phần mở rộng đã có trong sản phẩm, không còn được mô tả là chưa
triển khai. Khi một extension không khả dụng, luồng booking core vẫn phải hoạt
động. Phân loại này thay thế các mô tả phạm vi MVP cũ nếu có mâu thuẫn.

## 1. Tổng quan dự án

**GoStay** là website đặt phòng cho một chuỗi khách sạn nhỏ mang thương hiệu GoStay. Hệ thống giúp khách hàng tìm chi nhánh/phòng trong chuỗi GoStay, xem thông tin phòng, chọn thời gian nhận/trả phòng và đặt phòng nhanh. Ở phía quản trị, admin hoặc nhân viên quản lý chuỗi GoStay có thể quản lý chi nhánh, phòng, giá, tiện ích, hình ảnh và trạng thái phòng.

**Mục tiêu giai đoạn đầu:** Xây dựng **MVP** – phiên bản tối thiểu đủ luồng đặt phòng cốt lõi, phù hợp dự án môn Công nghệ phần mềm. GoStay không xây marketplace trung gian nhiều khách sạn độc lập như Booking/Traveloka/Agoda, mà tập trung vào một chuỗi khách sạn nhỏ với các chi nhánh và phòng thuộc hệ thống GoStay.

Ứng dụng hướng tới người cần chỗ ở ngắn hạn như khách du lịch, người đi công tác, sinh viên, khách lẻ; đồng thời hỗ trợ admin/chủ chuỗi khách sạn quản lý thông tin chi nhánh, phòng, giá, tình trạng phòng trống và đơn đặt phòng.

---

## 2. Đối tượng người dùng (Target Users)

| Nhóm | Nhu cầu chính |
|------|----------------|
| **Khách hàng cá nhân** | Đặt phòng nhanh theo giờ hoặc theo ngày |
| **Du khách / người đi công tác** | Quy trình đặt phòng đơn giản, ít bước |
| **Admin / chủ chuỗi khách sạn** | Quản lý chi nhánh, phòng, giá, tiện ích, trạng thái phòng và đơn đặt phòng |

---

## 3. Vấn đề cần giải quyết (Problems)

- Người dùng mất nhiều thời gian tìm chi nhánh/phòng phù hợp nếu thông tin trong hệ thống không rõ ràng.
- Giá và thông tin phòng không luôn rõ ràng, dễ gây nhầm lẫn.
- Một số nền tảng không linh hoạt cho đặt phòng ngắn hạn hoặc theo giờ.
- Admin cần cách đơn giản để cập nhật trạng thái phòng và tránh trùng đặt trong chuỗi GoStay.
- Quy trình đặt phòng cần ngắn gọn, dễ hiểu cho người dùng mới.

GoStay tập trung giải quyết các vấn đề trên **ở mức cơ bản** trong MVP, không giải quyết toàn bộ thị trường đặt phòng.

---

## 4. Phạm vi MVP (In Scope)

Phiên bản MVP đầu tiên chỉ gồm **luồng đặt phòng cốt lõi**:

1. **Đăng ký / đăng nhập** người dùng. Core phục vụ `customer` và `admin`;
   `staff` thuộc extension vận hành tại chi nhánh.
2. **Tìm kiếm chi nhánh/phòng GoStay** theo khu vực, tên chi nhánh, loại phòng hoặc khoảng giá.
3. **Xem chi tiết** chi nhánh và phòng.
4. **Chọn thời gian** nhận phòng (check-in) và trả phòng (check-out).
5. **Tạo đặt phòng** (booking) với trạng thái và tổng tiền do database quyết định.
6. **Xem lịch sử đặt phòng** của khách.
7. **Admin** thêm/sửa thông tin chi nhánh/phòng và cập nhật trạng thái phòng.
### Nguyên tắc thiết kế MVP

- Giao diện và luồng nghiệp vụ **đơn giản**, dễ demo cho giảng viên.
- Ưu tiên **một luồng chính** hoàn chỉnh: tìm → xem → chọn ngày/giờ → đặt → xem lại.
- Dữ liệu mẫu (seed) có thể dùng để demo nếu chưa có nhiều khách sạn thật.
- Tài liệu và mã nguồn rõ ràng để cả nhóm cùng phát triển.

---

## 5. Ngoài phạm vi MVP (Out of Scope)

Các tính năng sau **không** làm trong MVP đầu tiên (có thể ghi nhận ý tưởng tương lai):

- Tích hợp thanh toán trực tuyến phức tạp / nhiều cổng thanh toán
- Hệ thống voucher, khuyến mãi
- Bản đồ nâng cao (tìm theo bản đồ tương tác)
- Chatbot hỗ trợ
- Điểm thưởng / loyalty
- Thanh toán tự động qua cổng thanh toán và đối soát ngân hàng thời gian thực

AI gợi ý phòng, VietQR/online check-in và Staff operations đã tồn tại dưới dạng
extension. Chúng không thuộc core và phải có thể tắt mà không làm hỏng luồng booking.

Nếu nhóm muốn mở rộng sau khi MVP ổn định, cần cập nhật lại tài liệu này và thống nhất với giảng viên.

---

## 6. Hướng phát triển sau MVP (tham khảo, không bắt buộc)

- Tích hợp cổng thanh toán tự động và đối soát giao dịch.
- Thông báo email khi đặt thành công.
- Đánh giá phòng cơ bản.

*Phần này chỉ mang tính định hướng dài hạn; ưu tiên hoàn thành MVP trước.*

---

## 7. Tiêu chí thành công MVP (đề xuất cho nhóm)

- Một khách có thể **đăng nhập**, **tìm chi nhánh/phòng GoStay**, **đặt phòng** với ngày/giờ rõ ràng và **xem lại** trong lịch sử.
- Một admin có thể **thêm/sửa chi nhánh/phòng** và **đổi trạng thái** để tránh hiển thị phòng đã đặt là còn trống.
- Demo được end-to-end trong buổi báo cáo tuần/milestone của môn học.

---

*Tài liệu này là nguồn tham chiếu chính cho phạm vi sản phẩm GoStay. Khi thay đổi phạm vi, nhóm cần cập nhật file và thông báo cho cả team.*

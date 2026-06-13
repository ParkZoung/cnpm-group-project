# GoStay — Hướng sản phẩm (Product Direction)

## 1. Tổng quan dự án

**GoStay** là website đặt phòng cho một chuỗi khách sạn nhỏ mang thương hiệu GoStay. Hệ thống giúp khách hàng tìm chi nhánh/phòng trong chuỗi GoStay, xem thông tin phòng, chọn thời gian nhận/trả phòng và đặt phòng nhanh. Ở phía quản trị, admin hoặc nhân viên quản lý chuỗi GoStay có thể quản lý chi nhánh, phòng, giá, tiện ích, hình ảnh và trạng thái phòng.

**Mục tiêu giai đoạn đầu:** Xây dựng **MVP** — phiên bản tối thiểu đủ luồng đặt phòng cốt lõi, phù hợp dự án môn Công nghệ phần mềm. GoStay không xây marketplace trung gian nhiều khách sạn độc lập như Booking/Traveloka/Agoda.

---

## 2. Đối tượng người dùng (Target Users)

| Nhóm | Nhu cầu chính |
|------|----------------|
| **Khách hàng cá nhân** | Đặt phòng nhanh theo giờ hoặc theo ngày |
| **Du khách / người đi công tác** | Quy trình đặt phòng đơn giản, ít bước |
Admin / nhân viên quản lý chuỗi GoStay | Quản lý chi nhánh, phòng, giá, tiện ích, hình ảnh; cập nhật trạng thái phòng và đơn đặt phòng

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

1.**Đăng ký / đăng nhập** người dùng với hai vai trò chính: Khách hàng và Admin.
2. **Tìm kiếm chi nhánh/phòng GoStay** theo khu vực, tên chi nhánh, loại phòng hoặc khoảng giá.
3. **Xem chi tiết** chi nhánh và phòng
4. **Chọn thời gian** nhận phòng (check-in) và trả phòng (check-out).
5. **Tạo đặt phòng** (booking) — có thể ghi nhận trạng thái “chờ xác nhận” hoặc “đã đặt” tùy thiết kế nhóm, **chưa** tích hợp thanh toán trực tuyến phức tạp.
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
- Check-in bằng QR
- Chatbot hỗ trợ
- Điểm thưởng / loyalty
- Gợi ý phòng bằng AI phức tạp

Nếu nhóm muốn mở rộng sau khi MVP ổn định, cần cập nhật lại tài liệu này và thống nhất với giảng viên.

---

## 6. Hướng phát triển sau MVP (tham khảo, không bắt buộc)

- Thanh toán đơn giản (mô phỏng hoặc một cổng duy nhất).
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

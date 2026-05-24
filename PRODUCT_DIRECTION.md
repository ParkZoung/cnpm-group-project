# GoStay — Hướng sản phẩm (Product Direction)

## 1. Tổng quan dự án

**GoStay** là ứng dụng đặt phòng khách sạn giúp người dùng tìm khách sạn, xem thông tin phòng, so sánh thông tin cơ bản, chọn thời gian nhận/trả phòng và đặt phòng nhanh.

Ứng dụng hướng tới người cần chỗ ở ngắn hạn (du lịch, công tác, sinh viên, khách lẻ) và hỗ trợ chủ khách sạn/đối tác quản lý thông tin phòng cùng tình trạng phòng trống.

**Mục tiêu giai đoạn đầu:** Xây dựng **MVP** — phiên bản tối thiểu chỉ đủ luồng đặt phòng cốt lõi, phù hợp dự án môn Công nghệ phần mềm (nhóm sinh viên), **không** xây nền tảng đặt phòng đầy đủ như các ứng dụng thương mại lớn.

---

## 2. Đối tượng người dùng (Target Users)

| Nhóm | Nhu cầu chính |
|------|----------------|
| **Khách hàng cá nhân** | Đặt phòng nhanh theo giờ hoặc theo ngày |
| **Du khách / người đi công tác** | Quy trình đặt phòng đơn giản, ít bước |
| **Chủ khách sạn / đối tác** | Thêm/sửa thông tin phòng, giá, tiện ích; cập nhật phòng trống/đã đặt |

---

## 3. Vấn đề cần giải quyết (Problems)

- Người dùng mất nhiều thời gian tìm phòng phù hợp từ nhiều nguồn khác nhau.
- Giá và thông tin phòng không luôn rõ ràng, dễ gây nhầm lẫn.
- Một số nền tảng không linh hoạt cho đặt phòng ngắn hạn hoặc theo giờ.
- Chủ khách sạn cần cách đơn giản để cập nhật phòng trống và tránh trùng đặt.
- Quy trình đặt phòng cần ngắn gọn, dễ hiểu cho người dùng mới.

GoStay tập trung giải quyết các vấn đề trên **ở mức cơ bản** trong MVP, không giải quyết toàn bộ thị trường đặt phòng.

---

## 4. Phạm vi MVP (In Scope)

Phiên bản MVP đầu tiên chỉ gồm **luồng đặt phòng cốt lõi**:

1. **Đăng ký / đăng nhập** người dùng (khách và chủ khách sạn nếu nhóm phân quyền đơn giản).
2. **Tìm kiếm khách sạn** theo tên, địa điểm hoặc khoảng giá.
3. **Xem chi tiết** khách sạn và phòng (mô tả cơ bản, giá, tiện ích chính).
4. **Chọn thời gian** nhận phòng (check-in) và trả phòng (check-out).
5. **Tạo đặt phòng** (booking) — có thể ghi nhận trạng thái “chờ xác nhận” hoặc “đã đặt” tùy thiết kế nhóm, **chưa** tích hợp thanh toán trực tuyến phức tạp.
6. **Xem lịch sử đặt phòng** của khách.
7. **Chủ khách sạn:** thêm/sửa thông tin phòng và **cập nhật trạng thái phòng** (ví dụ: trống, đã đặt, bảo trì).

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

- Một khách có thể **đăng nhập**, **tìm khách sạn**, **đặt phòng** với ngày/giờ rõ ràng và **xem lại** trong lịch sử.
- Một chủ khách sạn có thể **thêm/sửa phòng** và **đổi trạng thái** để tránh hiển thị phòng đã đặt là còn trống.
- Demo được end-to-end trong buổi báo cáo tuần/milestone của môn học.

---

*Tài liệu này là nguồn tham chiếu chính cho phạm vi sản phẩm GoStay. Khi thay đổi phạm vi, nhóm cần cập nhật file và thông báo cho cả team.*

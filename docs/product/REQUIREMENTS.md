# REQUIREMENTS.md — GoStay

> **Dự án:** GoStay — website đặt phòng cho chuỗi khách sạn nhỏ
> **Phiên bản tài liệu:** 2.0 (Tuần 04)

---

## 1. Product Overview

GoStay là website đặt phòng dành cho một chuỗi khách sạn nhỏ. Khách hàng có thể tìm phòng, xem chi tiết, chọn ngày/giờ nhận trả và đặt phòng. Admin có thể quản lý phòng, cập nhật giá và trạng thái để đảm bảo dữ liệu đồng bộ với trải nghiệm khách.

---

## 2. User Roles

- **Customer**: Người dùng đặt phòng, tìm kiếm phòng, xem chi tiết và quản lý lịch sử booking.
- **Staff**: Nhân viên một chi nhánh, tiếp nhận khách, thu số dư và hoàn tất trả phòng.
- **Admin**: Người quản lý hệ thống GoStay, thêm/sửa/xóa phòng và cập nhật trạng thái, giá cả, thông tin phòng.

---

## 3. MVP Scope

- Đăng ký, đăng nhập cho khách và admin.
- Danh sách chi nhánh/phòng của chuỗi GoStay.
- Tìm kiếm và lọc phòng theo vị trí, giá, loại phòng.
- Xem chi tiết phòng.
- Đặt phòng chọn ngày/giờ và xác nhận.
- Lịch sử đặt phòng cho khách.
- Quản lý phòng, giá và trạng thái bởi admin.
- AI gợi ý phòng phù hợp theo nhu cầu.

---

## 4. Out of Scope

- Thanh toán online thật.
- Voucher / mã giảm giá.
- Tích điểm thành viên.
- QR check-in.
- Chatbot hỗ trợ.
- Bản đồ vị trí khách sạn.
- Hệ thống đa nền tảng nhiều khách sạn độc lập.
- Tính năng đặt phòng tự động qua AI.

---

## 5. User Stories

### US1 — Đăng ký tài khoản
- ID: US1
- User role: Customer
- Goal: Tôi muốn đăng ký tài khoản để bắt đầu tìm và đặt phòng.
- Benefit: Khách có thể lưu booking và quản lý thông tin cá nhân.
- Acceptance Criteria:
  - Given tôi chưa có tài khoản,
  - When tôi điền email và mật khẩu hợp lệ và bấm Đăng ký,
  - Then hệ thống tạo tài khoản và chuyển tôi đến trang danh sách phòng.
- Priority: Cao
- Difficulty: Trung bình
- AI involved: No

### US2 — Đăng nhập
- ID: US2
- User role: Customer
- Goal: Tôi muốn đăng nhập vào GoStay để sử dụng các chức năng đặt phòng.
- Benefit: Khách có thể xem lịch sử và đặt phòng nhanh hơn.
- Acceptance Criteria:
  - Given tôi đã có tài khoản,
  - When tôi nhập email và mật khẩu đúng và bấm Đăng nhập,
  - Then tôi được chuyển đến trang phù hợp với vai trò của mình.
  - Given tôi nhập sai mật khẩu,
  - When tôi bấm Đăng nhập,
  - Then hệ thống hiển thị thông báo lỗi.
- Priority: Cao
- Difficulty: Dễ
- AI involved: No

### US3 — Xem danh sách phòng và chi nhánh
- ID: US3
- User role: Customer
- Goal: Tôi muốn xem các phòng và chi nhánh đang có trong chuỗi GoStay.
- Benefit: Giúp tôi biết được lựa chọn phòng hiện có.
- Acceptance Criteria:
  - Given tôi mở trang chính,
  - When danh sách phòng được tải,
  - Then tôi thấy tên phòng, giá, địa điểm và trạng thái cơ bản.
- Priority: Cao
- Difficulty: Dễ
- AI involved: No

### US4 — Tìm kiếm và lọc phòng
- ID: US4
- User role: Customer
- Goal: Tôi muốn tìm phòng theo vị trí, mức giá hoặc loại phòng.
- Benefit: Giúp tôi tìm nhanh phòng phù hợp với nhu cầu.
- Acceptance Criteria:
  - Given có nhiều phòng trong hệ thống,
  - When tôi nhập vị trí hoặc chọn khoảng giá và bấm tìm,
  - Then danh sách chỉ còn phòng phù hợp.
  - Given không có kết quả phù hợp,
  - When tôi tìm kiếm,
  - Then hệ thống hiển thị thông báo "Không tìm thấy phòng".
- Priority: Cao
- Difficulty: Trung bình
- AI involved: No

### US5 — Xem chi tiết phòng
- ID: US5
- User role: Customer
- Goal: Tôi muốn xem thông tin chi tiết một phòng trước khi đặt.
- Benefit: Tôi có thể kiểm tra giá, tiện ích và trạng thái phòng.
- Acceptance Criteria:
  - Given tôi chọn một phòng trong danh sách,
  - When tôi vào trang chi tiết phòng,
  - Then tôi thấy ảnh, mô tả, giá, tiện nghi và trạng thái.
  - Given phòng đang bảo trì,
  - When tôi xem chi tiết,
  - Then nút đặt phòng bị vô hiệu hóa hoặc có cảnh báo.
- Priority: Cao
- Difficulty: Trung bình
- AI involved: No

### US6 — Chọn ngày/giờ nhận và trả phòng
- ID: US6
- User role: Customer
- Goal: Tôi muốn chọn thời gian nhận và trả phòng khi đặt.
- Benefit: Đảm bảo booking có thời gian chính xác.
- Acceptance Criteria:
  - Given tôi đang đặt một phòng còn trống,
  - When tôi chọn check-in và check-out hợp lệ,
  - Then hệ thống tính tổng tiền ước tính.
  - Given thời gian không hợp lệ,
  - When tôi chọn check-out trước check-in,
  - Then hệ thống báo lỗi và không cho tiếp tục.
- Priority: Cao
- Difficulty: Trung bình
- AI involved: No

### US7 — Xác nhận đặt phòng
- ID: US7
- User role: Customer
- Goal: Tôi muốn xác nhận thông tin trước khi hoàn tất đặt phòng.
- Benefit: Giảm rủi ro đặt sai phòng hoặc sai ngày.
- Acceptance Criteria:
  - Given tôi đã chọn phòng và thời gian,
  - When tôi bấm tiếp tục,
  - Then hệ thống hiển thị màn xác nhận với thông tin rõ ràng.
  - When tôi bấm Xác nhận,
  - Then booking được tạo và hiển thị thông báo thành công.
- Priority: Cao
- Difficulty: Trung bình
- AI involved: No

### US8 — Xem lịch sử đặt phòng
- ID: US8
- User role: Customer
- Goal: Tôi muốn xem lại các booking đã đặt trước đó.
- Benefit: Giúp tôi quản lý và theo dõi các chuyến đi.
- Acceptance Criteria:
  - Given tôi đã đăng nhập và có booking,
  - When tôi mở trang lịch sử đặt phòng,
  - Then tôi thấy danh sách booking với thông tin phòng, thời gian và trạng thái.
  - Given tôi chưa có booking nào,
  - When tôi mở trang lịch sử,
  - Then hệ thống hiển thị thông báo phù hợp.
- Priority: Trung bình
- Difficulty: Dễ
- AI involved: No

### US9 — Admin thêm phòng mới
- ID: US9
- User role: Admin
- Goal: Tôi muốn thêm phòng mới cho chuỗi GoStay.
- Benefit: Giúp hệ thống cập nhật nhanh phòng còn trống.
- Acceptance Criteria:
  - Given tôi đăng nhập với quyền admin,
  - When tôi điền thông tin phòng mới và lưu,
  - Then phòng xuất hiện trong danh sách quản lý.
- Priority: Cao
- Difficulty: Trung bình
- AI involved: No

### US10 — Admin cập nhật trạng thái và giá phòng
- ID: US10
- User role: Admin
- Goal: Tôi muốn cập nhật trạng thái và giá phòng.
- Benefit: Giúp khách thấy thông tin phòng chính xác.
- Acceptance Criteria:
  - Given tôi ở trang quản lý phòng,
  - When tôi chỉnh trạng thái hoặc giá và lưu,
  - Then hệ thống cập nhật thông tin tương ứng.
  - Given chọn trạng thái bảo trì,
  - When lưu thay đổi,
  - Then phòng không hiển thị là có thể đặt.
- Priority: Cao
- Difficulty: Trung bình
- AI involved: No

### US11 — AI gợi ý phòng phù hợp theo nhu cầu
- ID: US11
- User role: Customer
- Goal: Tôi muốn nhận gợi ý phòng phù hợp dựa trên nhu cầu của mình.
- Benefit: Giúp tôi tìm phòng nhanh hơn khi chưa rõ nên chọn phòng nào.
- Acceptance Criteria:
  - Given tôi nhập yêu cầu như vị trí, giá và tiện nghi,
  - When tôi bấm Gợi ý phòng,
  - Then hệ thống hiển thị phòng gợi ý kèm lý do ngắn.
  - Given AI không tìm thấy gợi ý phù hợp,
  - When tôi yêu cầu gợi ý,
  - Then hệ thống thông báo và vẫn cho phép tìm kiếm tay.
- Priority: Trung bình
- Difficulty: Trung bình
- AI involved: Yes

---

## 6. Summary

- Product Overview: Website đặt phòng cho chuỗi khách sạn nhỏ.
- User roles: `customer`, `staff`, `admin` (Staff operations là extension).
- Core scope: đăng ký/đăng nhập, tìm/filter, chi tiết phòng, booking, lịch sử và quản trị.
- Extension scope: AI gợi ý, VietQR/online check-in và Staff operations.
- Out of scope: cổng thanh toán tự động có webhook, voucher, loyalty, chatbot, bản đồ và nhiều khách sạn độc lập. VietQR đối soát thủ công và QR check-in thuộc phạm vi hiện tại.
- User stories: 11 stories, trong đó US11 là AI gợi ý phòng.

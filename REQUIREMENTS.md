# REQUIREMENTS.md — GoStay

> **Dự án:** GoStay — website đặt phòng khách sạn (MVP)  
> **Phiên bản tài liệu:** 1.0 (Tuần 03)

---

## 1. Product Vision

**GoStay** là nền tảng web đặt phòng khách sạn **đơn giản và tập trung**, giúp người dùng tìm phòng, xem thông tin rõ ràng, đặt phòng theo ngày hoặc giờ và quản lý lịch sử đặt phòng. Hệ thống hỗ trợ chủ khách sạn và admin quản lý phòng, giá và trạng thái. GoStay học hỏi từ các app lớn (Booking, Traveloka, Agoda) nhưng **không** nhắm tới bản sao đầy đủ tính năng — chỉ **MVP phù hợp nhóm sinh viên**.

---

## 2. Target Users

| Nhóm | Nhu cầu chính |
|------|----------------|
| **Khách du lịch** | Tìm KS gần địa điểm du lịch, giá hợp lý, xem ảnh, đặt nhanh |
| **Người đi công tác** | Đặt gần nơi làm việc/họp, quản lý lịch đặt phòng |
| **Sinh viên / ở ngắn hạn** | Giá phù hợp, đặt theo giờ hoặc ngày, thao tác đơn giản |
| **Chủ khách sạn / đối tác** | Quản lý phòng trống, giá, tiện ích, ảnh, tình trạng đặt |
| **Admin hệ thống** | Quản lý người dùng, danh sách KS/phòng, theo dõi hoạt động cơ bản |

---

## 3. Problems / Pain Points

- Người dùng mất thời gian tìm phòng trên nhiều nguồn hoặc app có quá nhiều tùy chọn.
- Giá và thông tin phòng trên app lớn đôi khi khó hiểu, khó so sánh.
- Nhu cầu đặt **theo giờ** hoặc **ngắn hạn** chưa được hỗ trợ tốt ở mức đơn giản.
- Chủ khách sạn cần cập nhật phòng trống/đã đặt nhanh, tránh trùng booking.
- Luồng đặt phòng trên app thương mại thường dài (addon, thanh toán, khuyến mãi).

GoStay giải quyết các vấn đề trên **ở mức cơ bản** trong MVP.

---

## 4. MVP Scope

| Chức năng | Mô tả ngắn |
|-----------|------------|
| Đăng ký, đăng nhập | Tài khoản khách, admin/chủ KS (phân quyền đơn giản) |
| Danh sách KS/phòng | Xem danh sách với ảnh, giá, trạng thái |
| Tìm kiếm & lọc | Theo địa điểm, giá, loại phòng |
| Chi tiết phòng | Ảnh, giá, tiện nghi, vị trí (text), trạng thái |
| Đặt phòng | Chọn phòng, check-in/out, xác nhận — **chưa thanh toán thật** |
| Lịch sử đặt phòng | Khách xem booking đã tạo |
| Quản lý phòng (admin) | Thêm, sửa, xóa; cập nhật giá và trạng thái |
| AI gợi ý phòng | Gợi ý theo nhu cầu; user tự xem chi tiết và xác nhận đặt |

**Nguyên tắc:** Một luồng end-to-end: *tìm → xem → đặt → lịch sử*. Có thể dùng **dữ liệu mẫu (seed)**.

---

## 5. Out of Scope

| Tính năng | Lý do |
|-----------|--------|
| Thanh toán online thật | Phức tạp, không cần cho demo MVP |
| Voucher / mã giảm giá | Cần rule engine, dễ trượt scope |
| Tích điểm thành viên | Không cốt lõi booking |
| QR check-in | Cần mobile + luồng vận hành riêng |
| Chatbot hỗ trợ | Khó kiểm soát, không cần cho MVP |
| Bản đồ vị trí KS | API map tốn thời gian; dùng text địa điểm |

---

## 6. User Stories

### US0 — Đăng ký / Đăng nhập

| Trường | Nội dung |
|--------|----------|
| **ID** | US0 |
| **User role** | Khách, Chủ khách sạn, Admin |
| **Goal** | Tôi muốn đăng ký tài khoản và đăng nhập vào GoStay |
| **Benefit** | Để đặt phòng, xem lịch sử và (nếu có quyền) quản lý phòng |
| **Acceptance Criteria** | **Given** tôi chưa đăng nhập, **When** tôi nhập email và mật khẩu hợp lệ và bấm Đăng nhập, **Then** hệ thống chuyển tôi vào trang phù hợp với vai trò. **Given** tôi chưa có tài khoản, **When** tôi điền form đăng ký hợp lệ, **Then** tài khoản được tạo và tôi có thể đăng nhập. **Given** sai mật khẩu, **When** tôi đăng nhập, **Then** hiển thị thông báo lỗi. |
| **Priority** | Cao (P0) |
| **Difficulty** | Trung bình |
| **AI involved** | No |

---

### US1 — Tìm kiếm phòng theo địa điểm

| Trường | Nội dung |
|--------|----------|
| **ID** | US1 |
| **User role** | Khách (du lịch, công tác, sinh viên) |
| **Goal** | Tôi muốn tìm phòng theo địa điểm hoặc tên khách sạn |
| **Benefit** | Để nhanh chóng thấy các phòng gần nơi tôi cần |
| **Acceptance Criteria** | **Given** có danh sách phòng trong hệ thống, **When** tôi nhập từ khóa địa điểm (ví dụ "Quận 1") và bấm Tìm, **Then** hiển thị các phòng/KS khớp địa điểm. **Given** không có kết quả, **When** tôi tìm kiếm, **Then** hiển thị thông báo "Không tìm thấy phòng". |
| **Priority** | Cao (P0) |
| **Difficulty** | Dễ–Trung bình |
| **AI involved** | No |

---

### US2 — Lọc phòng theo mức giá

| Trường | Nội dung |
|--------|----------|
| **ID** | US2 |
| **User role** | Khách |
| **Goal** | Tôi muốn lọc phòng theo khoảng giá |
| **Benefit** | Để chọn phòng phù hợp ngân sách (đặc biệt sinh viên, du lịch tiết kiệm) |
| **Acceptance Criteria** | **Given** danh sách phòng đang hiển thị, **When** tôi chọn giá từ X đến Y và áp dụng lọc, **Then** chỉ hiển thị phòng có giá trong khoảng đó. **Given** tôi xóa bộ lọc, **When** bấm Xóa lọc, **Then** danh sách trở về trạng thái trước đó. |
| **Priority** | Cao (P0) |
| **Difficulty** | Dễ |
| **AI involved** | No |

---

### US3 — Xem thông tin chi tiết phòng

| Trường | Nội dung |
|--------|----------|
| **ID** | US3 |
| **User role** | Khách |
| **Goal** | Tôi muốn xem chi tiết một phòng trước khi đặt |
| **Benefit** | Để biết giá, ảnh, tiện nghi, vị trí và trạng thái phòng |
| **Acceptance Criteria** | **Given** tôi chọn một phòng từ danh sách, **When** tôi bấm Xem chi tiết, **Then** trang hiển thị ảnh, tên, giá (ngày/giờ), tiện nghi, địa điểm (text), trạng thái. **Given** phòng đang bảo trì, **When** xem chi tiết, **Then** nút Đặt phòng bị vô hiệu hoặc hiển thị cảnh báo. |
| **Priority** | Cao (P0) |
| **Difficulty** | Dễ |
| **AI involved** | No |

---

### US4 — Chọn ngày/giờ nhận phòng và trả phòng

| Trường | Nội dung |
|--------|----------|
| **ID** | US4 |
| **User role** | Khách |
| **Goal** | Tôi muốn chọn thời gian nhận và trả phòng khi đặt |
| **Benefit** | Để đặt theo ngày hoặc theo giờ tùy nhu cầu ngắn hạn |
| **Acceptance Criteria** | **Given** tôi đang đặt một phòng còn trống, **When** tôi chọn check-in và check-out hợp lệ (check-out sau check-in), **Then** hệ thống hiển thị tổng tiền ước tính. **Given** thời gian không hợp lệ, **When** tôi chọn, **Then** hiển thị lỗi và không cho tiếp tục. |
| **Priority** | Cao (P0) |
| **Difficulty** | Trung bình |
| **AI involved** | No |

---

### US5 — Xác nhận đặt phòng

| Trường | Nội dung |
|--------|----------|
| **ID** | US5 |
| **User role** | Khách |
| **Goal** | Tôi muốn xem lại và xác nhận thông tin trước khi hoàn tất đặt phòng |
| **Benefit** | Để tránh nhầm phòng hoặc nhầm thời gian |
| **Acceptance Criteria** | **Given** tôi đã điền form đặt phòng, **When** tôi bấm Tiếp tục, **Then** màn xác nhận hiển thị đủ thông tin phòng, thời gian, tổng tiền. **When** tôi bấm Xác nhận đặt phòng, **Then** booking được tạo với trạng thái (ví dụ "Đã đặt") và hiển thị màn thành công. **Không** có bước thanh toán online thật trong MVP. |
| **Priority** | Cao (P0) |
| **Difficulty** | Trung bình |
| **AI involved** | No |

---

### US6 — Xem lịch sử đặt phòng

| Trường | Nội dung |
|--------|----------|
| **ID** | US6 |
| **User role** | Khách |
| **Goal** | Tôi muốn xem các phòng đã đặt trước đó |
| **Benefit** | Để theo dõi lịch công tác, du lịch hoặc các lần ở ngắn hạn |
| **Acceptance Criteria** | **Given** tôi đã đăng nhập và có ít nhất một booking, **When** tôi mở Lịch sử đặt phòng, **Then** hiển thị danh sách mã booking, phòng, thời gian, tổng tiền, trạng thái. **Given** chưa có booking nào, **When** tôi mở trang, **Then** hiển thị thông báo trống phù hợp. |
| **Priority** | Trung bình (P1) |
| **Difficulty** | Dễ |
| **AI involved** | No |

---

### US7 — AI gợi ý phòng phù hợp

| Trường | Nội dung |
|--------|----------|
| **ID** | US7 |
| **User role** | Khách |
| **Goal** | Tôi muốn nhận gợi ý phòng dựa trên nhu cầu mô tả của tôi |
| **Benefit** | Để tìm phòng nhanh hơn so với lọc thủ công nhiều trường |
| **Acceptance Criteria** | **Given** tôi nhập nhu cầu (text hoặc form: địa điểm, giá, tiện nghi…), **When** tôi bấm Gợi ý phòng, **Then** hệ thống hiển thị 3–5 phòng gợi ý kèm lý do ngắn. **When** tôi chọn Xem chi tiết một gợi ý, **Then** chuyển sang trang chi tiết phòng. **AI không tự tạo booking** — người dùng phải tự đặt qua US4–US5. **Given** API AI lỗi, **When** gợi ý thất bại, **Then** thông báo lỗi và vẫn dùng được tìm kiếm thường. |
| **Priority** | Trung bình (P1) |
| **Difficulty** | Trung bình |
| **AI involved** | **Yes** |

---

### US8 — Admin thêm / cập nhật khách sạn / phòng

| Trường | Nội dung |
|--------|----------|
| **ID** | US8 |
| **User role** | Admin, Chủ khách sạn |
| **Goal** | Tôi muốn thêm và chỉnh sửa thông tin khách sạn và phòng |
| **Benefit** | Để cập nhật giá, ảnh, tiện ích cho khách xem và đặt |
| **Acceptance Criteria** | **Given** tôi đăng nhập với quyền admin/chủ KS, **When** tôi thêm phòng mới với thông tin bắt buộc (tên, giá, loại, KS), **Then** phòng xuất hiện trong danh sách. **When** tôi sửa thông tin phòng và lưu, **Then** thay đổi hiển thị trên trang khách. **When** tôi xóa phòng (nếu nhóm hỗ trợ), **Then** phòng không còn hiển thị cho khách đặt mới. |
| **Priority** | Cao (P0) |
| **Difficulty** | Trung bình |
| **AI involved** | No |

---

### US9 — Admin cập nhật trạng thái phòng

| Trường | Nội dung |
|--------|----------|
| **ID** | US9 |
| **User role** | Admin, Chủ khách sạn |
| **Goal** | Tôi muốn đổi trạng thái phòng (trống / đã đặt / bảo trì) |
| **Benefit** | Để tránh khách đặt phòng không còn trống hoặc đang sửa chữa |
| **Acceptance Criteria** | **Given** một phòng trong danh sách quản trị, **When** tôi đổi trạng thái sang "Bảo trì", **Then** khách không thể đặt phòng đó (hoặc hiển thị cảnh báo). **When** đổi sang "Trống", **Then** phòng có thể được đặt nếu không trùng thời gian booking khác. |
| **Priority** | Cao (P0) |
| **Difficulty** | Dễ–Trung bình |
| **AI involved** | No |

---

### US10 — Xem danh sách khách sạn / phòng

| Trường | Nội dung |
|--------|----------|
| **ID** | US10 |
| **User role** | Khách (và có thể Admin xem toàn bộ) |
| **Goal** | Tôi muốn xem danh sách khách sạn và phòng có sẵn |
| **Benefit** | Để duyệt và chọn phòng trước khi tìm kiếm chi tiết hoặc đặt |
| **Acceptance Criteria** | **Given** hệ thống có dữ liệu phòng, **When** tôi mở trang Danh sách phòng, **Then** hiển thị card/bảng gồm ảnh, tên, địa điểm, giá, loại, trạng thái. **When** tôi bấm một phòng, **Then** chuyển tới chi tiết (US3) hoặc hiển thị thêm thông tin. |
| **Priority** | Cao (P0) |
| **Difficulty** | Dễ |
| **AI involved** | No |

---

## 7. Tóm tắt User Stories

| ID | Tên ngắn | Priority | Difficulty | AI |
|----|----------|----------|------------|-----|
| US0 | Đăng ký / Đăng nhập | P0 | Trung bình | No |
| US1 | Tìm theo địa điểm | P0 | Dễ–TB | No |
| US2 | Lọc theo giá | P0 | Dễ | No |
| US3 | Chi tiết phòng | P0 | Dễ | No |
| US4 | Chọn ngày/giờ | P0 | Trung bình | No |
| US5 | Xác nhận đặt phòng | P0 | Trung bình | No |
| US6 | Lịch sử đặt phòng | P1 | Dễ | No |
| US7 | AI gợi ý phòng | P1 | Trung bình | **Yes** |
| US8 | Admin CRUD phòng/KS | P0 | Trung bình | No |
| US9 | Admin cập nhật trạng thái | P0 | Dễ–TB | No |
| US10 | Danh sách KS/phòng | P0 | Dễ | No |

---

## 8. Thứ tự triển khai gợi ý (cho nhóm sinh viên)

1. US0, US10 — nền tảng và danh sách (mock data)
2. US1, US2, US3 — tìm và xem
3. US4, US5, US6 — luồng đặt phòng
4. US8, US9 — phía admin
5. US7 — AI gợi ý (sau khi luồng chính ổn)

---

*Tài liệu tham chiếu: `PRODUCT_DIRECTION.md`, `UX_PROTOTYPE.md`, `AI_FEATURE_PROPOSAL.md`*

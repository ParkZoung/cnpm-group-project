# PRODUCT_ANALYSIS.md

> **Dự án:** GoStay — ứng dụng web đặt phòng khách sạn (MVP)  
> **Vai trò tài liệu:** Phân tích sản phẩm (Business Analyst / Product Owner)  
> **Lưu ý:** GoStay học hỏi một số ý tưởng thiết kế từ các app đặt phòng lớn, nhưng chỉ tập trung vào một chuỗi khách sạn nhỏ với **MVP đơn giản** phù hợp nhóm sinh viên .

---

## 1. Product Overview

**GoStay** là ứng dụng web giúp người dùng tìm khách sạn hoặc phòng, xem thông tin chi tiết, so sánh giá và tiện ích cơ bản, đặt phòng theo **ngày** hoặc **giờ**, và xem lại lịch sử đặt phòng. Phía quản trị, chủ khách sạn hoặc admin có thể quản lý phòng, giá, trạng thái còn trống, hình ảnh và thông tin khách sạn ở mức cơ bản.

**Vấn đề GoStay muốn giải quyết:**

- Người dùng thường mất thời gian khi phải mở nhiều nguồn hoặc lọc quá nhiều tùy chọn trên các app lớn.
- Giá, tiện ích và tình trạng phòng đôi khi không rõ ràng, gây khó so sánh và quyết định.
- Nhu cầu ở **ngắn hạn** (vài giờ, nửa ngày) chưa được nhiều nền tảng hỗ trợ tốt ở mức đơn giản.
- Chủ khách sạn cần cách **nhanh** để cập nhật phòng trống/đã đặt, tránh trùng booking.

GoStay không cạnh tranh trực tiếp với các nền tảng thương mại toàn cầu. Đây là sản phẩm học tập, tập trung **một luồng đặt phòng rõ ràng** thay vì xây hệ sinh thái du lịch đầy đủ.

---

## 2. Target Users

| Nhóm người dùng | Nhu cầu chính |
|-----------------|---------------|
| **Khách hàng cá nhân (Individual customers)** | Tìm và đặt phòng nhanh; xem giá, tiện ích; theo dõi booking đã đặt |
| **Du khách (Tourists)** | Tìm phòng theo địa điểm/tên khách sạn; quy trình đặt ngắn gọn khi đi du lịch |
| **Người đi công tác (Business travelers)** | Đặt phòng theo ngày hoặc vài giờ nghỉ giữa chuyến; cần thông tin rõ, ít bước |
| **Sinh viên / người cần ở ngắn hạn** | Giá phù hợp túi tiền; đặt theo giờ hoặc theo ngày; giao diện dễ hiểu |
| **Admin / chủ chuỗi khách sạn (Hotel chain owner)** | Thêm/sửa phòng, giá, ảnh, tiện ích; cập nhật trạng thái phòng (trống, đã đặt, bảo trì) |
| **Quản trị hệ thống (System admin)** | Quản lý tài khoản cơ bản; duy trì dữ liệu mẫu; hỗ trợ demo và vận hành MVP |

**Tóm lại:** Phía khách tập trung vào **tìm → so sánh cơ bản → đặt → xem lại**; phía chủ KS/admin tập trung vào **quản lý thông tin phòng và tình trạng trống** — không cần dashboard phức tạp như app thương mại.

---

## 3. Pain Points in Existing Products

Phân tích các điểm yếu thường gặp trên các app đặt phòng lớn — từ đó rút ra hướng đơn giản hóa cho GoStay:

| Pain point | Mô tả | Gợi ý hướng GoStay (MVP) |
|------------|--------|---------------------------|
| **Quá nhiều tính năng** | Filter, gợi ý, combo, vé máy bay, tour… dễ làm người mới bối rối | Chỉ giữ tìm kiếm/lọc cơ bản: tên, địa điểm, khoảng giá |
| **Luồng đặt phòng dài** | Nhiều bước: chọn phòng → addon → bảo hiểm → thanh toán → xác nhận | Rút gọn: chọn phòng → chọn thời gian → xác nhận đặt (chưa thanh toán thật) |
| **So sánh giá khó** | Giá hiển thị thay đổi theo ưu đãi, thuế, loại giá ẩn | Hiển thị giá/ngày hoặc giá/giờ **rõ ràng** trên danh sách và trang chi tiết |
| **Tình trạng phòng không rõ** | “Còn X phòng” đôi khi không đồng bộ với thực tế | Trạng thái đơn giản: **còn trống / đã đặt / bảo trì**, cập nhật từ phía chủ KS |
| **Hỗ trợ đặt theo giờ hạn chế** | Nhiều nền tảng ưu tiên đặt qua đêm, ít linh hoạt cho ở ngắn | Cho phép chọn **theo ngày hoặc theo giờ** (logic đơn giản trong MVP) |
| **Khuyến mãi & thanh toán phức tạp** | Voucher, điểm, nhiều cổng thanh toán, điều kiện khó hiểu | **Không** làm voucher/thanh toán thật trong MVP; có thể mô phỏng trạng thái “đã đặt” |
| **Chủ KS khó cập nhật nhanh** | Portal đối tác phức tạp, nhiều màn hình | Form CRUD phòng đơn giản: giá, ảnh, tiện ích, trạng thái |

GoStay **không** khẳng định các app trên “kém”; chúng phục vụ quy mô lớn. Nhóm chỉ **học ý tưởng** (tìm kiếm, chi tiết phòng, booking) rồi **cắt bớt** phần không cần cho MVP sinh viên.

---

## 4. Simpler MVP Scope

Phạm vi MVP thực tế cho nhóm sinh viên — **một web app** với luồng chính hoàn chỉnh, có thể dùng **dữ liệu mẫu (seed)**:

| Hạng mục | Trong MVP |
|----------|-----------|
| Đăng ký / đăng nhập | Có — phân quyền đơn giản: khách, chủ KS, admin (nếu nhóm chọn) |
| Xem danh sách khách sạn/phòng | Có — danh sách + ảnh, giá, tiện ích cơ bản |
| Tìm kiếm & lọc | Có — theo tên, địa điểm, khoảng giá (không cần bản đồ) |
| Xem chi tiết phòng | Có — mô tả, giá, tiện ích, trạng thái |
| Đặt phòng | Có — chọn check-in/check-out (ngày hoặc giờ); tạo booking |
| Lịch sử đặt phòng | Có — khách xem các booking của mình |
| Quản lý phòng (chủ KS / admin) | Có — thêm/sửa phòng, giá, ảnh, cập nhật trạng thái |
| Dữ liệu mẫu | Có — seed vài khách sạn/phòng để demo không cần nhập tay nhiều |

**Nguyên tắc giữ MVP nhỏ:**

- Ưu tiên **một stack** thống nhất (frontend + backend + DB) do giảng viên/nhóm chốt.
- Một luồng demo end-to-end: *đăng nhập → tìm phòng → đặt → xem lịch sử* và *chủ KS cập nhật phòng*.
- Giao diện đơn giản, đủ dùng; không cần mobile app riêng trong MVP.

---

## 5. Five Core Features

Đề xuất **đúng 5** tính năng cốt lõi cho MVP:

| # | Tên tính năng | Mô tả | Vì sao quan trọng | Mức ưu tiên |
|---|---------------|--------|-------------------|-------------|
| 1 | **Đăng ký & đăng nhập** | Người dùng tạo tài khoản, đăng nhập; phân biệt khách và chủ khách sạn (hoặc admin) | Nền tảng cho booking cá nhân hóa và quản lý phòng theo quyền | **Cao (P0)** |
| 2 | **Tìm kiếm & lọc phòng/khách sạn** | Tìm theo tên, địa điểm, khoảng giá; hiển thị danh sách kết quả | Giải quyết pain point “mất thời gian tìm kiếm”; là bước đầu của luồng chính | **Cao (P0)** |
| 3 | **Xem chi tiết phòng & so sánh cơ bản** | Trang chi tiết: giá (ngày/giờ), tiện ích, ảnh, trạng thái; có thể xem 2–3 phòng để so sánh thủ công | Giúp quyết định nhanh, minh bạch giá và thông tin | **Cao (P0)** |
| 4 | **Đặt phòng (Booking)** | Chọn thời gian nhận/trả; tạo booking; ghi nhận trạng thái (ví dụ: đã đặt / chờ xác nhận) | Lõi của sản phẩm; thể hiện giá trị GoStay so với chỉ “xem catalog” | **Cao (P0)** |
| 5 | **Quản lý phòng cho chủ KS & lịch sử cho khách** | Chủ KS: CRUD phòng, cập nhật giá/trạng thái. Khách: xem booking đã tạo | Tránh trùng đặt; đóng vòng vòng đời booking; đủ demo hai phía user | **Trung bình–Cao (P1)** |

*Ghi chú:* Nếu nhóm thiếu thời gian, có thể gộp “lịch sử booking” vào cùng mục 5 thay vì tách feature riêng — vẫn đủ 5 mục cốt lõi như trên.

---

## 6. Three Possible AI Features

Ba ý tưởng AI **cho tương lai** (không bắt buộc trong MVP đầu tiên). Mỗi ý tưởng nhỏ, dễ demo, dễ kiểm soát:

### 6.1. Gợi ý phòng theo mô tả ngắn

| Hạng mục | Nội dung |
|----------|----------|
| **Mô tả** | Người dùng nhập câu ngắn (ví dụ: “phòng gần trung tâm, có WiFi, dưới 500k”) → hệ thống gợi ý vài phòng phù hợp |
| **Input** | Câu text tiếng Việt + (tuỳ chọn) ngân sách, thành phố |
| **Output** | Danh sách 3–5 phòng kèm lý do ngắn |
| **Giá trị** | Tìm nhanh hơn so với lọc thủ công nhiều trường |
| **Độ khó (nhóm sinh viên)** | **Trung bình** — cần gọi API LLM + map kết quả với DB phòng có sẵn |

### 6.2. Tóm tắt đánh giá / mô tả phòng

| Hạng mục | Nội dung |
|----------|----------|
| **Mô tả** | AI tóm tắt mô tả dài của phòng hoặc vài comment mẫu thành 2–3 câu dễ đọc |
| **Input** | Text mô tả phòng hoặc danh sách comment |
| **Output** | Đoạn tóm tắt ngắn (bullet hoặc paragraph) |
| **Giá trị** | Giúp khách nắm nhanh điểm nổi bật / hạn chế |
| **Độ khó** | **Thấp–Trung bình** — prompt cố định, dễ demo trên 1 trang chi tiết |

### 6.3. Hỗ trợ nhập liệu cho chủ khách sạn

| Hạng mục | Nội dung |
|----------|----------|
| **Mô tả** | Từ vài gợi ý (tên phòng, loại, tiện ích), AI sinh mô tả marketing ngắn hoặc gợi ý tiện ích phù hợp |
| **Input** | Tên phòng, loại (single/double), danh sách tiện ích đã chọn |
| **Output** | Mô tả phòng 1 đoạn + gợi ý tiện ích bổ sung (optional) |
| **Giá trị** | Chủ KS tiết kiệm thời gian điền form |
| **Độ khó** | **Thấp** — form + nút “Gợi ý bằng AI”, không ảnh hưởng luồng booking cốt lõi |

**Lưu ý:** Cả ba tính năng trên là **optional** sau MVP. Nhóm nên hoàn thành booking thủ công trước khi thêm AI.

---

## 7. Out-of-Scope Features

Các tính năng **không** đưa vào MVP đầu tiên:

| Tính năng | Lý do out-of-scope |
|-----------|---------------------|
| **Cổng thanh toán trực tuyến thật** | Tích hợp PCI, webhook, hoàn tiền — quá phức tạp và không cần để demo luồng đặt phòng |
| **Hệ thống voucher / khuyến mãi phức tạp** | Cần rule engine, stack mã, thời hạn — dễ làm trượt scope |
| **Điểm thưởng (Loyalty)** | Yêu cầu tích lũy, đổi thưởng, báo cáo — không cốt lõi MVP |
| **Bản đồ nâng cao (map integration)** | API bản đồ, geocoding, marker — tốn thời gian; MVP có thể chỉ cần text địa điểm |
| **Chatbot AI đầy đủ** | Cần context dài, xử lý nhiều intent — khó kiểm soát chất lượng cho nhóm mới |
| **Dynamic pricing (giá động theo AI)** | Thuật toán + dữ liệu lịch sử — vượt năng lực và thời gian dự án học |
| **Check-in bằng QR nâng cao trên mobile** | Bản web hiện có online check-in token trong extension; ứng dụng mobile/quét camera riêng vẫn ngoài phạm vi |
| **Đa ngôn ngữ (Multi-language)** | i18n toàn site — ưu tiên tiếng Việt trước cho MVP |

Các mục trên có thể ghi vào backlog **sau khi** MVP chạy ổn và được giảng viên đồng ý mở rộng.

---

## 8. Risks for a Student Team

| Rủi ro | Mô tả | Cách giảm thiểu (gợi ý) |
|--------|--------|---------------------------|
| **Scope quá lớn** | Muốn làm giống Traveloka/Agoda → không kịp deadline | Bám `PRODUCT_DIRECTION.md` và 5 core features; từ chối tính năng mới không qua họp nhóm |
| **Thiếu kinh nghiệm hệ thống booking** | Overlap thời gian, double booking, timezone | Thiết kế DB đơn giản: booking có `room_id`, `start`, `end`, `status`; kiểm tra trùng cơ bản |
| **Khó thiết kế database** | Quan hệ User–Hotel–Room–Booking phức tạp | Vẽ ERD sớm; bắt đầu với 4–5 bảng; dùng seed data |
| **Quản lý thời gian kém** | Dồn code sát deadline | Chia milestone theo tuần; demo luồng tìm → đặt sớm |
| **Phân công không đều** | Một người làm nhiều, người khác ít | Ghi task rõ trên board; rotate phần review/test |
| **Phụ thuộc quá nhiều vào AI** | Copy code không hiểu → không bảo vệ được | Review code tay; ghi `ai-logs/`; mỗi người giải thích phần mình làm |
| **Khó test luồng booking** | Edge case: cùng phòng cùng giờ, hủy booking | Viết vài test case thủ công + checklist; test 2 user đặt cùng phòng |
| **Khó deploy** | Lỗi môi trường, DB, env | Deploy sớm bản “hello world”; dùng Docker hoặc host miễn phí theo hướng dẫn môn học |

---

## 9. Final MVP Decision

**Quyết định MVP cuối cùng:** GoStay sẽ là **ứng dụng web đặt phòng tập trung cho một chuỗi khách sạn nhỏ**, không phải một marketplace hay nền tảng tổng hợp. Phiên bản đầu tiên cho phép **khách hàng** đăng ký/đăng nhập, tìm và lọc chi nhánh/phòng trong GoStay, xem chi tiết và so sánh thông tin cơ bản giữa các phòng hoặc chi nhánh (giá, tiện ích), **đặt phòng theo ngày hoặc giờ**, và **xem lịch sử đặt phòng**. **Admin hoặc chủ chuỗi khách sạn** có thể quản lý thông tin phòng, giá, hình ảnh và **cập nhật trạng thái phòng** để tránh hiển thị sai tình trạng còn trống. Hệ thống có thể chạy với **dữ liệu mẫu** để demo ổn định. Các tính năng nặng như **thanh toán thật, voucher, loyalty, bản đồ nâng cao, chatbot và AI pricing** được **loại khỏi MVP**; AI chỉ xem xét ở dạng **tính năng nhỏ, demo được** sau khi luồng booking cốt lõi hoạt động tốt. Mục tiêu là nhóm sinh viên hoàn thành **một luồng end-to-end rõ ràng**, đủ báo cáo và bảo vệ đồ án, đồng thời học được cách phân tích sản phẩm từ các nền tảng lớn rồi **đơn giản hóa** cho phạm vi thực tế.

---

*Tài liệu tham chiếu liên quan: `PRODUCT_DIRECTION.md`, `AGENT_GUIDE.md`, `AI_USAGE_POLICY.md`*

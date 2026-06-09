# Week 03 AI Usage Log

**Dự án:** GoStay — website đặt phòng khách sạn (MVP)  
**Tuần:** 03  
**Ngày ghi:** 07/06/2026  

---

## 1. Tóm tắt Tuần 03

Tuần 03, nhóm tập trung **thiết kế UX prototype** và **viết yêu cầu chức năng (requirements)** trước khi code nhiều. Mục tiêu là mô tả màn hình, luồng người dùng và user stories cho MVP GoStay — **chưa** triển khai backend đầy đủ.

**File đã tạo trong Tuần 03:**

- `UX_PROTOTYPE.md`
- `REQUIREMENTS.md`
- `ai-logs/week-03.md` (file này)

---

## 2. Công cụ AI đã dùng

| Công cụ | Mục đích |
|---------|----------|
| **ChatGPT** | Thảo luận danh sách màn hình, gợi ý user stories, kiểm tra acceptance criteria có quá phức tạp không |
| **Cursor** | Tạo và chỉnh sửa file Markdown trong repository (`UX_PROTOTYPE.md`, `REQUIREMENTS.md`, `ai-logs/week-03.md`) |

---

## 3. Mục đích sử dụng AI trong Tuần 3

- Soạn **khung tài liệu** UX prototype: màn hình, luồng, mock data.
- Soạn **khung REQUIREMENTS**: vision, user stories US0–US10, Given-When-Then.
- Tiết kiệm thời gian định dạng bảng Markdown và đảm bảo không thiếu mục bài nộp.
- Tham khảo cách mô tả luồng đặt phòng đơn giản cho sinh viên năm nhất.

**AI không** thay nhóm quyết định stack, không viết code ứng dụng trong tuần này.

---

## 4. Một số prompt mẫu đã dùng

### Prompt tạo `UX_PROTOTYPE.md`

> Vai trò SE Assistant cho nhóm sinh viên năm nhất. Dự án GoStay — MVP đặt phòng web. Tạo UX_PROTOTYPE.md tiếng Việt: giới thiệu, mục tiêu prototype, 12 màn hình (Home, Login, List, Search, Detail, Booking, Confirmation, Success, History, Admin Dashboard, Admin Room, AI Recommendation), luồng tìm→đặt thành công, mock data, ghi rõ chỉ dùng dữ liệu mẫu chưa backend sớm. Không thêm thanh toán, voucher, chatbot, bản đồ.

### Prompt tạo `REQUIREMENTS.md`

> Viết REQUIREMENTS.md cho GoStay MVP: Product Vision, target users, pain points, MVP scope, out of scope. User stories US0–US10 đầy đủ ID, role, goal, benefit, Given-When-Then, priority, difficulty, AI yes/no. Khớp MVP đã thống nhất từ tuần 2. Không thêm tính năng ngoài phạm vi.

### Prompt tạo `ai-logs/week-03.md`

> Viết nhật ký AI tuần 3 trung thực: công cụ, mục đích, prompt mẫu, kết quả, review của nhóm, bài học. Nhấn mạnh nhóm không copy nguyên AI mà có kiểm tra và chỉnh theo GoStay.

---

## 5. Kết quả AI hỗ trợ

AI (ChatGPT + Cursor) giúp nhóm:

| Hạng mục | Kết quả từ AI |
|----------|----------------|
| **Danh sách màn hình** | 12 màn hình bám MVP, tách luồng khách và admin |
| **Mô tả UI** | Thành phần cơ bản từng màn (ô tìm kiếm, card phòng, form booking…) |
| **Luồng người dùng** | Sơ đồ tìm phòng → đặt thành công; luồng AI gợi ý tách riêng |
| **Mock data** | 3 khách sạn, 5 phòng, booking và tài khoản demo mẫu |
| **User stories** | US0–US10 với acceptance criteria dạng Given-When-Then |
| **Phân loại AI** | Chỉ US7 gắn AI; các US khác No |

---

## 6. Nhóm đã kiểm tra / chỉnh sửa như thế nào

**Lưu ý:** Nhóm **không** copy hoàn toàn output AI. Các bước review:

- **Đối chiếu MVP Tuần 2** — bỏ màn hình/thuật ngữ không có trong phạm vi (thanh toán, voucher, map).
- **Rút gọn mô tả** — một số gợi ý AI quá chi tiết (biểu đồ admin, nhiều loại filter); nhóm giữ filter cơ bản: địa điểm, giá, loại phòng.
- **Sắp xếp user stories** — thống nhất US10 (danh sách) tách với US1/US2 (tìm/lọc) cho dễ hiểu khi báo cáo.
- **US7 (AI)** — nhấn mạnh AI chỉ gợi ý, không auto-book; thêm tiêu chí khi API lỗi vẫn dùng search thường.
- **Mock data** — chọn tên KS và giá VNĐ quen thuộc (Q1, Đà Lạt, Hà Nội) thay vì tên AI đề xuất chung chung.
- **Thứ tự triển khai** — nhóm tự thêm mục “triển khai gợi ý” trong REQUIREMENTS: làm booking trước, AI sau.

*Người review:* _(điền tên sau họp nhóm)_

---

## 7. Bài học rút ra khi dùng AI

| Bài học | Chi tiết |
|---------|----------|
| **Prompt có ngữ cảnh GoStay + MVP** | Giúp AI ít đề xuất tính năng app du lịch lớn |
| **AI tốt cho khung tài liệu** | Bảng user story, danh sách màn hình — tiết kiệm thời gian format |
| **Vẫn cần đọc Given-When-Then** | AI đôi khi viết criteria mơ hồ; nhóm phải sửa cho đo được được |
| **Prototype ≠ sản phẩm thật** | Nhóm hiểu rõ tuần 3 chỉ mô tả UX + requirements, chưa code backend |
| **Ghi log minh bạch** | Tuân thủ `AI_USAGE_POLICY.md` và yêu cầu môn học |

---

## 8. Hạn chế khi dùng AI (Tuần 03)

- AI có thể gợi ý **quá nhiều màn hình phụ** (profile, đánh giá, thông báo…) — nhóm đã cắt bớt.
- Acceptance criteria đôi khi **trùng lặp** giữa các US — nhóm gộp và làm rõ từng US.
- AI **không biết** deadline và số thành viên nhóm — thứ tự triển khai do nhóm tự quyết.
- Một số câu tiếng Việt cần **chỉnh tay** cho tự nhiên hơn.

---

## 9. Checklist nội bộ (Tuần 03)

- [ ] Cả nhóm đã đọc `UX_PROTOTYPE.md`
- [ ] Cả nhóm đã đọc `REQUIREMENTS.md`
- [ ] Đã thống nhất mock data demo
- [ ] Sẵn sàng chuyển sang thiết kế DB / code (Tuần 4+) khi giảng viên yêu cầu

---

*Nhật ký Tuần 03 — UX prototype và requirements cho GoStay; AI hỗ trợ soạn thảo, nhóm review và chịu trách nhiệm nội dung cuối.*

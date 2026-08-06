# GoStay — Chính sách sử dụng AI (AI Usage Policy)

Chính sách này áp dụng cho **toàn bộ nhóm** dự án GoStay khi dùng công cụ AI (ChatGPT, Cursor, Codex, Copilot, v.v.) trong học tập và phát triển phần mềm.

---

## 1. Mục tiêu

- Dùng AI **hợp pháp và trung thực** theo quy định môn học / trường.
- Tăng hiệu quả làm việc nhóm mà **không** che giấu việc học hoặc vi phạm đạo đức học thuật.
- Bảo vệ dữ liệu nhóm và người dùng (không lộ secret, thông tin cá nhân).

---

## 2. Nguyên tắc chung

| Nguyên tắc | Ý nghĩa |
|------------|---------|
| **Minh bạch** | Ghi nhận khi dùng AI cho tài liệu hoặc code quan trọng (`ai-logs/`) |
| **Có trách nhiệm** | Thành viên phải hiểu và chịu trách nhiệm nội dung đưa vào repo |
| **Đúng phạm vi** | Chỉ hỗ trợ MVP GoStay, không mở rộng tùy tiện |
| **An toàn** | Không đưa dữ liệu nhạy cảm lên công cụ AI công cộng |

---

## 3. Việc được phép

- Dùng AI để **soạn/tham khảo** tài liệu dự án (product direction, hướng dẫn, README).
- Dùng AI **gợi ý** cấu trúc code, sửa lỗi, viết test đơn giản **sau khi** thành viên review.
- Dùng AI **giải thích** khái niệm (REST API, authentication, v.v.) để học.
- Ghi log trong `ai-logs/week-XX.md` theo từng tuần hoặc milestone.

---

## 4. Việc không được phép

- Nộp bài **hoàn toàn do AI viết** mà không đọc, không chỉnh, không hiểu.
- **Gian lận**: giấu việc dùng AI khi môn học yêu cầu khai báo.
- Dán vào AI: **mật khẩu**, connection string database production, **API key**, token JWT thật, dữ liệu cá nhân thật của người dùng.
- Dùng AI để tạo tính năng **ngoài MVP** (thanh toán phức tạp, loyalty, chatbot, v.v.) mà không có thống nhất nhóm và giảng viên.
- Copy code từ nguồn không rõ bản quyền mà không kiểm tra.

---

## 5. Quy trình an toàn khi dùng AI

### 5.1. Trước khi prompt

- Đọc [`docs/product/PRODUCT_DIRECTION.md`](docs/product/PRODUCT_DIRECTION.md) và
  [`docs/product/REQUIREMENTS.md`](docs/product/REQUIREMENTS.md) để xác định phạm vi hiện hành.
- Loại bỏ thông tin nhạy cảm khỏi nội dung gửi AI (dùng biến giả, `.env.example`).

### 5.2. Sau khi nhận kết quả từ AI

- Đọc toàn bộ diff / đoạn code.
- Chạy thử local; sửa lỗi và comment nếu cần.
- Đảm bảo phù hợp quy ước code của nhóm.

### 5.3. Ghi log

Mỗi tuần (hoặc khi có milestone), cập nhật `ai-logs/week-XX.md` với:

- Công cụ đã dùng (ChatGPT, Cursor, …)
- Mục đích (tài liệu, API, UI, …)
- File / khu vực ảnh hưởng chính
- Ai review (tên thành viên hoặc “cả nhóm”)

---

## 6. Trách nhiệm cá nhân và nhóm

- **Mỗi thành viên** chịu trách nhiệm phần mình commit hoặc merge.
- **Trưởng nhóm** nhắc nhở tuân thủ policy và kiểm tra `ai-logs/` định kỳ.
- Khi báo cáo với giảng viên, nhóm **khai báo trung thực** mức độ hỗ trợ của AI theo yêu cầu môn học.

---

## 7. Dữ liệu và bảo mật

- File `.env` chứa secret **không** commit lên Git; chỉ commit `.env.example` (không có giá trị thật).
- Dữ liệu demo dùng tên/email giả.
- Nếu lỡ gửi secret lên AI: **đổi secret ngay**, báo trưởng nhóm, không commit secret vào repo.

---

## 8. Liên quan đạo đức học thuật

- Tuân thủ quy định của **trường, khoa và môn Công nghệ phần mềm**.
- AI là **công cụ hỗ trợ**, không thay thế hiểu biết của sinh viên.
- Trong báo cáo / slide, nên có mục **“Công cụ AI đã sử dụng”** nếu giảng viên yêu cầu.

---

## 9. Xử lý vi phạm (nội bộ nhóm)

1. Revert hoặc sửa phần vi phạm phạm vi / bảo mật.
2. Ghi nhận sự cố trong `ai-logs/` tuần đó.
3. Họp nhóm ngắn để thống nhất lại quy trình.

---

## 10. Tài liệu tham chiếu trong repo

- [`docs/product/PRODUCT_DIRECTION.md`](docs/product/PRODUCT_DIRECTION.md)
- [`docs/product/REQUIREMENTS.md`](docs/product/REQUIREMENTS.md)
- [`AGENT_GUIDE.md`](AGENT_GUIDE.md)
- `ai-logs/` — nhật ký theo tuần

---

*Chính sách có hiệu lực từ Tuần 1. Nhóm cập nhật khi giảng viên có hướng dẫn bổ sung.*

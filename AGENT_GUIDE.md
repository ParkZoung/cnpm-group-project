# GoStay — Hướng dẫn làm việc với AI Agent (Cursor / Codex)

> **Cập nhật theo repository ngày 2026-08-06.** Phạm vi chuẩn nằm tại
> [`docs/product/PRODUCT_DIRECTION.md`](docs/product/PRODUCT_DIRECTION.md) và
> [`docs/product/REQUIREMENTS.md`](docs/product/REQUIREMENTS.md).

Tài liệu này giúp nhóm dự án **GoStay** dùng AI Agent (ví dụ: Cursor, Codex) một cách thống nhất, tránh làm lệch phạm vi MVP.

---

## 1. Mục đích

- Tăng tốc viết tài liệu, thiết kế, và mã nguồn **trong phạm vi MVP**.
- Giữ chất lượng và tính nhất quán giữa các thành viên.
- Tránh AI “thêm” quá nhiều tính năng ngoài `docs/product/PRODUCT_DIRECTION.md`.

---

## 2. AI Agent là gì trong dự án này?

**AI Agent** là trợ lý lập trình tích hợp trong IDE (ví dụ Cursor) hoặc công cụ tương tự (Codex), có thể:

- Đọc và chỉnh sửa file trong repository
- Gợi ý cấu trúc thư mục, API, giao diện
- Giải thích lỗi và đề xuất cách sửa
- Viết test hoặc tài liệu khi được yêu cầu rõ ràng

Agent **không** thay thế việc nhóm tự hiểu yêu cầu, phân công và review code.

---

## 3. Nguyên tắc khi nhờ Agent làm việc

### 3.1. Luôn gắn với GoStay và MVP

Mỗi prompt nên nêu rõ:

- Tên dự án: **GoStay**
- Việc cần làm thuộc MVP hay không (tham chiếu `docs/product/PRODUCT_DIRECTION.md`)
- Vai trò chuẩn: `customer`, `staff` hoặc `admin` (nếu liên quan)

**Ví dụ prompt tốt:**

> “Trong dự án GoStay, bổ sung bộ lọc sức chứa vào Availability Search. Giữ
> nguyên ranh giới Edge Function → RPC/RLS, không thay đổi extension VietQR.”

**Ví dụ prompt kém:**

> “Làm app đặt phòng khách sạn đầy đủ tính năng.”

### 3.2. Một việc một lần

Chia nhỏ yêu cầu: tài liệu → thiết kế DB → API → giao diện. Tránh một prompt quá dài gây thiếu kiểm soát.

### 3.3. Chỉ rõ ràng buộc kỹ thuật (nếu nhóm đã chốt)

- Stack hiện tại: HTML, CSS, JavaScript thuần, Supabase Edge Functions và PostgreSQL
- Cấu trúc thư mục hiện có
- Quy ước đặt tên (tiếng Anh cho code, tiếng Việt cho tài liệu user-facing nếu cần)

Nếu chưa chốt stack, yêu cầu Agent **đề xuất phương án đơn giản** phù hợp sinh viên, không chọn kiến trúc quá phức tạp.

### 3.4. Review trước khi merge

Thành viên được giao task phải:

1. Đọc diff do Agent tạo
2. Chạy thử (build, test cơ bản)
3. Đảm bảo không vi phạm `AI_USAGE_POLICY.md`

---

## 4. Quy trình đề xuất cho nhóm

```text
Yêu cầu / issue → Prompt có ngữ cảnh GoStay + MVP
    → Agent tạo/sửa file → Thành viên review
    → Ghi log tại ai-logs/ (tuần tương ứng)
    → Commit / PR theo quy ước nhóm
```

### Vai trò gợi ý

| Vai trò | Việc với Agent |
|--------|----------------|
| **Trưởng nhóm / PM** | Kiểm tra prompt có đúng phạm vi MVP |
| **Dev** | Dùng Agent viết/sửa code, tự review |
| **QA / tester** | Nhờ Agent viết checklist test đơn giản |
| **Tất cả** | Ghi nhận dùng AI trong `ai-logs/` |

---

## 5. Việc nên nhờ Agent

- Soạn hoặc chỉnh `docs/product/PRODUCT_DIRECTION.md`, README, hướng dẫn cài đặt
- API đăng ký/đăng nhập, catalog, availability, booking và quản trị
- Form chọn check-in / check-out
- Trang danh sách booking history
- CRUD catalog cho Admin và nghiệp vụ chi nhánh cho Staff
- Test E2E, runtime security, migration và Staff/payment contract
- Giải thích lỗi biên dịch / runtime

---

## 6. Việc không nên (hoặc cần thận trọng)

- Tự ý thêm voucher, loyalty, chatbot, bản đồ nâng cao, cổng thanh toán tự động
  hoặc AI tự đặt phòng — đây là các tính năng ngoài phạm vi hiện tại
- Mở rộng VietQR, online check-in, Staff operations hoặc AI mà không giữ booking
  core hoạt động độc lập
- Copy nguyên code không hiểu → khó bảo vệ và sửa lỗi
- Dán **mật khẩu, API key, token** vào chat Agent
- Tin hoàn toàn output mà không chạy thử

---

## 7. Cấu trúc repository hiện tại

```text
/frontend          — HTML, CSS, JavaScript phía trình duyệt
/backend/supabase  — Edge Functions, migrations và cấu hình Supabase
/tests             — E2E, runtime security và contract tests
/docs              — tài liệu sản phẩm, kiến trúc, database và vận hành
/ai-logs           — nhật ký sử dụng AI
```

Backend đã được triển khai. Khi thay đổi, giữ luồng frontend → Edge Function →
RPC/RLS và không đưa Supabase database key hoặc quyền quyết định nghiệp vụ vào
trình duyệt. Xem [`docs/architecture/PROJECT_STRUCTURE.md`](docs/architecture/PROJECT_STRUCTURE.md).

---

## 8. Xử lý khi Agent làm sai phạm vi

1. Dừng merge
2. Prompt lại: “Chỉ làm MVP GoStay, bỏ [tính năng X], tham chiếu docs/product/PRODUCT_DIRECTION.md”
3. Ghi lại lesson learned trong `ai-logs/` tuần đó

---

## 9. Liên kết tài liệu liên quan

- [`docs/product/PRODUCT_DIRECTION.md`](docs/product/PRODUCT_DIRECTION.md) — phạm vi sản phẩm
- [`docs/product/REQUIREMENTS.md`](docs/product/REQUIREMENTS.md) — yêu cầu hiện hành
- [`docs/architecture/DOMAIN_TERMS.md`](docs/architecture/DOMAIN_TERMS.md) — role và trạng thái chuẩn
- [`AI_USAGE_POLICY.md`](AI_USAGE_POLICY.md) — quy tắc dùng AI an toàn, có trách nhiệm
- `ai-logs/week-XX.md` — nhật ký từng tuần

---

*Nhóm cập nhật file này khi đổi công cụ AI hoặc quy trình làm việc.*

# GoStay — Hướng dẫn làm việc với AI Agent (Cursor / Codex)

Tài liệu này giúp nhóm dự án **GoStay** dùng AI Agent (ví dụ: Cursor, Codex) một cách thống nhất, tránh làm lệch phạm vi MVP.

---

## 1. Mục đích

- Tăng tốc viết tài liệu, thiết kế, và mã nguồn **trong phạm vi MVP**.
- Giữ chất lượng và tính nhất quán giữa các thành viên.
- Tránh AI “thêm” quá nhiều tính năng ngoài `PRODUCT_DIRECTION.md`.

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
- Việc cần làm thuộc MVP hay không (tham chiếu `PRODUCT_DIRECTION.md`)
- Vai trò: khách hàng / chủ khách sạn (nếu liên quan)

**Ví dụ prompt tốt:**

> “Trong dự án GoStay (MVP), tạo API GET danh sách khách sạn theo tên và địa điểm. Không thêm thanh toán hay voucher.”

**Ví dụ prompt kém:**

> “Làm app đặt phòng khách sạn đầy đủ tính năng.”

### 3.2. Một việc một lần

Chia nhỏ yêu cầu: tài liệu → thiết kế DB → API → giao diện. Tránh một prompt quá dài gây thiếu kiểm soát.

### 3.3. Chỉ rõ ràng buộc kỹ thuật (nếu nhóm đã chốt)

- Ngôn ngữ / framework (ví dụ: Node + React, hoặc stack giảng viên yêu cầu)
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

- Soạn hoặc chỉnh `PRODUCT_DIRECTION.md`, README, hướng dẫn cài đặt
- Skeleton API: đăng ký, đăng nhập, tìm khách sạn, tạo booking
- Form chọn check-in / check-out
- Trang danh sách booking history
- CRUD phòng cho chủ khách sạn (cơ bản)
- Giải thích lỗi biên dịch / runtime

---

## 6. Việc không nên (hoặc cần thận trọng)

- Nhờ Agent thêm **thanh toán**, **voucher**, **bản đồ nâng cao**, **AI gợi ý** — đã **out of scope** MVP
- Copy nguyên code không hiểu → khó bảo vệ và sửa lỗi
- Dán **mật khẩu, API key, token** vào chat Agent
- Tin hoàn toàn output mà không chạy thử

---

## 7. Cấu trúc repository (gợi ý khi bắt đầu code)

Khi nhóm bắt đầu code, có thể yêu cầu Agent tuân theo hướng đơn giản, ví dụ:

```text
/backend    — API, database
/frontend   — giao diện người dùng
/docs       — tài liệu bổ sung (nếu cần)
/ai-logs    — nhật ký sử dụng AI theo tuần
```

Chi tiết stack do nhóm và giảng viên quyết định; Agent chỉ triển khai **sau khi** nhóm thống nhất.

---

## 8. Xử lý khi Agent làm sai phạm vi

1. Dừng merge
2. Prompt lại: “Chỉ làm MVP GoStay, bỏ [tính năng X], tham chiếu PRODUCT_DIRECTION.md”
3. Ghi lại lesson learned trong `ai-logs/` tuần đó

---

## 9. Liên kết tài liệu liên quan

- `PRODUCT_DIRECTION.md` — phạm vi sản phẩm
- `AI_USAGE_POLICY.md` — quy tắc dùng AI an toàn, có trách nhiệm
- `ai-logs/week-XX.md` — nhật ký từng tuần

---

*Nhóm cập nhật file này khi đổi công cụ AI hoặc quy trình làm việc.*

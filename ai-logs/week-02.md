# Week 02 AI Usage Log

**Dự án:** GoStay — ứng dụng web đặt phòng khách sạn (MVP)  
**Tuần:** 02  
**Ngày ghi:** 24/05/2026  

---

## 1. Week 02 Summary

Tuần 02, nhóm **chưa bắt đầu code** mà tập trung **phân tích sản phẩm** trước khi triển khai. Mục tiêu là làm rõ ý tưởng GoStay (ứng dụng đặt phòng đơn giản, học hỏi từ Booking.com, Traveloka, Agoda nhưng không sao chép toàn bộ tính năng).

Công việc chính trong tuần:

| Hạng mục | Nội dung đã phân tích |
|----------|------------------------|
| **Product analysis** | Tổng quan sản phẩm, vấn đề cần giải quyết |
| **Target users** | Khách lẻ, du khách, công tác, sinh viên, chủ KS, admin |
| **User pain points** | App lớn quá phức tạp, luồng đặt dài, giá/ phòng không rõ, ít hỗ trợ đặt theo giờ |
| **MVP scope** | Phạm vi nhỏ, phù hợp nhóm sinh viên, có thể dùng dữ liệu mẫu |
| **Core features** | 5 tính năng cốt lõi cho MVP |
| **Possible AI features** | 3 ý tưởng AI nhỏ cho giai đoạn sau |
| **Out-of-scope features** | Thanh toán thật, voucher phức tạp, loyalty, chatbot đầy đủ, v.v. |
| **Risks** | Scope quá lớn, thiếu kinh nghiệm booking, DB, thời gian, phụ thuộc AI |

**File đã tạo trong Tuần 02:**

- `PRODUCT_ANALYSIS.md`
- `AI_FEATURE_PROPOSAL.md`
- `ai-logs/week-02.md` (file này)

---

## 2. AI Tools Used

| Công cụ | Cách nhóm sử dụng |
|---------|-------------------|
| **ChatGPT** | Thảo luận ý tưởng, gợi ý cấu trúc tài liệu, cải thiện prompt, kiểm tra lại hướng sản phẩm GoStay có bám MVP hay không |
| **Cursor** | Tạo và cập nhật file Markdown (`PRODUCT_ANALYSIS.md`, `AI_FEATURE_PROPOSAL.md`, `ai-logs/week-02.md`) trực tiếp trong repository GitHub |

Nhóm **không** dùng AI để viết code ứng dụng trong tuần này.

---

## 3. Prompts Used

Dưới đây là **tóm tắt** các prompt chính (không copy nguyên văn toàn bộ hội thoại):

### Prompt tạo `PRODUCT_ANALYSIS.md`

> Vai trò Business Analyst / Product Owner. Dự án GoStay — app đặt phòng web đơn giản, MVP cho sinh viên. Viết `PRODUCT_ANALYSIS.md` bằng tiếng Việt gồm: tổng quan, đối tượng người dùng, pain point của app lớn, phạm vi MVP, 5 core features, 3 AI features tương lai, out-of-scope, rủi ro nhóm sinh viên, quyết định MVP cuối. Không làm quá phức tạp, không clone Booking.com/Traveloka/Agoda.

### Prompt tạo `AI_FEATURE_PROPOSAL.md`

> Đọc `PRODUCT_ANALYSIS.md` nếu có. Viết `AI_FEATURE_PROPOSAL.md` tiếng Việt: nguyên tắc chọn AI feature, đúng 3 tính năng (gợi ý phòng, tóm tắt review, trợ lý mô tả phòng), chọn gợi ý phòng làm mở rộng MVP, luồng AI cơ bản, rủi ro & giảm thiểu, tính năng AI không nên làm, khuyến nghị cuối. AI hỗ trợ UX, không thay luồng booking; người dùng kiểm soát output.

### Prompt tạo `ai-logs/week-02.md`

> Viết nhật ký AI Tuần 02 cho nhóm sinh viên GoStay: tóm tắt công việc phân tích sản phẩm, công cụ AI, prompt tóm tắt, output AI, review của nhóm, quyết định cuối, hạn chế, bài học. Giọng văn trung thực — AI không làm hết bài, nhóm vẫn review và quyết định.

---

## 4. AI Output Summary

AI (ChatGPT + Cursor) hỗ trợ **soạn nháp và cấu trúc** nội dung; nhóm dùng làm điểm bắt đầu, không copy nguyên xi mà không đọc.

AI gợi ý / giúp tổng hợp các phần sau:

| Chủ đề | Gợi ý từ AI (tóm tắt) |
|--------|------------------------|
| **Nhóm người dùng chính** | Khách cá nhân, du khách, công tác, sinh viên/ở ngắn hạn, chủ KS, admin |
| **Pain point sản phẩm hiện có** | Quá nhiều tính năng, luồng dài, so sánh giá khó, trạng thái phòng không rõ, ít đặt theo giờ, khuyến mãi/thanh toán phức tạp |
| **MVP đơn giản hơn** | Web app một luồng: tìm → xem → đặt → lịch sử; quản lý phòng cơ bản; seed data |
| **5 core features** | Đăng nhập, tìm/lọc, chi tiết & so sánh cơ bản, booking, quản lý phòng + lịch sử |
| **3 AI features có thể** | Gợi ý phòng theo nhu cầu; tóm tắt mô tả/review; trợ lý viết mô tả cho chủ KS |
| **Out-of-scope** | Thanh toán thật, voucher, loyalty, map nâng cao, chatbot full, dynamic pricing, QR, đa ngôn ngữ |
| **Rủi ro & hạn chế** | Scope trượt, DB booking khó, phân công lệch, over-rely AI, deploy khó |

---

## 5. Human Review and Modification

**Lưu ý:** Tuần 02 **không phải** AI tự hoàn thành toàn bộ bài tập. Thành viên nhóm đọc, chỉnh và thống nhất nội dung trước khi coi là bản cuối.

Các bước review của nhóm:

- **Đối chiếu với ý tưởng GoStay** — bỏ hoặc sửa phần không khớp (ví dụ: tính năng giống app du lịch all-in-one).
- **Loại bỏ tính năng quá phức tạp** — AI đôi khi gợi ý thêm map, payment gateway, recommendation nâng cao; nhóm cắt bớt cho đúng MVP sinh viên.
- **Thu hẹp MVP** — giữ một luồng demo end-to-end thay vì nhiều module song song.
- **Chọn core features thực tế** — 5 tính năng đủ demo, không thêm module phụ không cần thiết.
- **Giữ AI features nhỏ, kiểm soát được** — không chatbot tự đặt phòng; AI chỉ gợi ý / tóm tắt / hỗ trợ viết text.
- **Quyết định cuối do nhóm** — chốt out-of-scope, ưu tiên AI gợi ý phòng, và timeline tuần sau (có thể bắt đầu thiết kế/code khi giảng viên yêu cầu).

*Người review:* _(điền tên thành viên sau họp nhóm)_

---

## 6. Final Decisions Made by the Team

Sau khi xem xét gợi ý AI, nhóm **tự quyết định** các điểm sau:

| Quyết định | Nội dung |
|------------|----------|
| **Trọng tâm sản phẩm** | GoStay tập trung **đặt phòng khách sạn/phòng**, không làm hệ sinh thái du lịch lớn |
| **Phạm vi MVP** | Tìm kiếm/lọc, xem chi tiết phòng, đặt phòng (ngày/giờ), lịch sử booking, quản lý phòng cho chủ KS/admin |
| **Out of scope (giai đoạn 1)** | Thanh toán online thật, voucher phức tạp, loyalty, chatbot đầy đủ, AI pricing, map nâng cao |
| **AI feature phù hợp nhất (mở rộng sau MVP)** | **Gợi ý phòng theo nhu cầu người dùng** — form/mô tả nhu cầu → gợi ý vài phòng |
| **Nguyên tắc AI** | AI **chỉ gợi ý**; người dùng xem chi tiết và **tự xác nhận đặt phòng**; hệ thống booking vẫn chạy khi không có AI |

---

## 7. Problems or Limitations

Hạn chế khi dùng AI trong Tuần 02:

- **Gợi ý quá rộng** — AI dễ liệt kê thêm tính năng “đẹp trên giấy” nhưng nhóm không kịp làm (payment, loyalty, chatbot).
- **Độ phức tạp không đồng đều** — một số mục (dynamic pricing, fraud detection) vượt trình độ và thời gian môn học.
- **Cần verify và viết lại** — nhóm vẫn phải đọc từng section, chỉnh tiếng Việt, thống nhất thuật ngữ (check-in, booking, MVP).
- **AI không biết workload thật** — số thành viên, deadline, stack đã chốt hay chưa; nhóm tự điều chỉnh scope cho realistic.
- **Rủi ro trùng lặp tài liệu** — `PRODUCT_ANALYSIS.md` và `AI_FEATURE_PROPOSAL.md` có phần overlap; nhóm chấp nhận vì mỗi file phục vụ mục đích báo cáo khác nhau.

---

## 8. Lessons Learned

| Bài học | Chi tiết |
|---------|----------|
| **Prompt rõ ràng → output tốt hơn** | Ghi tên dự án GoStay, MVP, sinh viên, out-of-scope ngay trong prompt giúp AI ít “phóng đại” |
| **AI hữu ích cho brainstorm & tài liệu** | Tiết kiệm thời gian khung outline, bảng so sánh, danh sách rủi ro |
| **Vẫn phải kiểm tra kết quả cuối** | Không merge tài liệu nếu chưa có ít nhất một thành viên đọc kỹ |
| **AI hỗ trợ quy trình SE, không thay hiểu biết** | Mọi người cần giải thích được MVP và core features khi báo cáo — không chỉ dựa vào file AI tạo |
| **Ghi log giúp minh bạch** | Tuân thủ `AI_USAGE_POLICY.md` và yêu cầu môn học về khai báo dùng AI |

---

## Checklist nội bộ (Tuần 02)

- [ ] Cả nhóm đã đọc `PRODUCT_ANALYSIS.md`
- [ ] Cả nhóm đã đọc `AI_FEATURE_PROPOSAL.md`
- [ ] Đã họp thống nhất MVP và out-of-scope trước Tuần 03

---

*Nhật ký Tuần 02 — phân tích sản phẩm và đề xuất AI cho GoStay; chưa triển khai code.*

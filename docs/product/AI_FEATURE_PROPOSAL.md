# AI_FEATURE_PROPOSAL.md

> **Trạng thái: Historical proposal — một phần đã triển khai.** Tính năng
> `recommend-rooms` hiện đã dùng Gemini để xếp hạng phòng có thật. Các ý tưởng
> tóm tắt nội dung và trợ lý viết mô tả vẫn chỉ là đề xuất. Yêu cầu hiện hành xem
> tại [`REQUIREMENTS.md`](REQUIREMENTS.md).

> **Dự án:** GoStay — ứng dụng web đặt phòng khách sạn (MVP)  
> **Vai trò tài liệu:** Product Owner & AI Consultant  
> **Tham chiếu:** `PRODUCT_ANALYSIS.md`, `PRODUCT_DIRECTION.md`, `AI_USAGE_POLICY.md`

---

## 1. Overview

GoStay là ứng dụng đặt phòng tập trung vào luồng **tìm → xem → đặt → quản lý phòng**. Tài liệu này ban đầu đề xuất ba hướng AI; hiện hướng gợi ý phòng đã được triển khai, còn hai hướng kia vẫn có thể **hỗ trợ trải nghiệm người dùng** trong tương lai mà **không thay thế** luồng đặt phòng chính.

**Nguyên tắc quan trọng:**

- Luồng booking cốt lõi (đăng nhập, tìm kiếm, xem chi tiết, đặt phòng, lịch sử, quản lý phòng) phải **hoạt động đầy đủ khi không có AI**.
- AI là **tính năng bổ trợ tùy chọn**, người dùng chủ động bật hoặc bỏ qua.
- GoStay **không** trở thành “sản phẩm AI”; vẫn là **ứng dụng đặt phòng** với AI hỗ trợ ở vài điểm nhỏ, dễ demo.

---

## 2. AI Feature Selection Principles

Các nguyên tắc chọn tính năng AI cho dự án GoStay (nhóm sinh viên):

| Nguyên tắc | Ý nghĩa trong GoStay |
|------------|----------------------|
| **Nhỏ (Small)** | Một màn hình hoặc một nút bấm; không cần hệ thống AI phức tạp |
| **Dễ demo (Easy to demo)** | Demo được trong 2–3 phút trước giảng viên với dữ liệu mẫu |
| **Input rõ ràng** | Chỉ gửi tiêu chí tìm kiếm, mô tả phòng, comment — không gửi dữ liệu thừa |
| **Output rõ ràng** | Danh sách gợi ý, đoạn tóm tắt, hoặc bản mô tả đề xuất — dễ hiển thị trên UI |
| **Không dùng dữ liệu cá nhân không cần thiết** | Không gửi email, SĐT, thông tin thanh toán lên API AI |
| **Người dùng kiểm soát (Controlled by user)** | AI chỉ gợi ý; người dùng chọn xem, sửa, hoặc bỏ qua |
| **Không tự quyết định quan trọng** | AI **không** tự đặt phòng, **không** tự đổi giá, **không** khóa phòng |
| **Phù hợp nhóm mới (Beginner-friendly)** | Có thể triển khai bằng gọi API LLM + logic map với database phòng sẵn có |

---

## 3. Proposed AI Features

Đề xuất **đúng 3** tính năng AI, nhất quán với phân tích trong `PRODUCT_ANALYSIS.md` (mục 6).

---

### 3.1. Gợi ý phòng theo nhu cầu người dùng (AI Room Recommendation)

#### Mô tả

Người dùng mô tả nhu cầu bằng text hoặc form ngắn (địa điểm, ngân sách, số người, tiện ích, thời gian check-in). Hệ thống kết hợp dữ liệu phòng **còn trống** trong database với AI để trả về **3–5 phòng phù hợp**, kèm lý do ngắn cho từng gợi ý.

#### Vấn đề người dùng giải quyết

- Mất thời gian lọc thủ công nhiều trường trên app lớn.
- Khó chọn phòng khi có nhiều lựa chọn tương tự trong seed data / danh sách khách sạn.

#### Input

| Loại dữ liệu | Ví dụ |
|--------------|--------|
| Câu mô tả nhu cầu (text) | “Phòng gần trung tâm Q1, có WiFi, dưới 500k/đêm, 2 người” |
| Tiêu chí có cấu trúc (form) | Địa điểm, khoảng giá, số người, check-in/check-out, tiện ích ưa thích |
| Danh sách phòng ứng viên (từ DB) | `room_id`, tên, giá, tiện ích, trạng thái, địa điểm — **không** gửi thông tin cá nhân user |

#### Output

- Danh sách 3–5 `room_id` được xếp hạng.
- Mỗi phòng: 1–2 câu giải thích vì sao phù hợp (do AI sinh).
- (Tuỳ chọn) Cảnh báo nếu không có phòng khớp hoàn toàn.

#### Kiểm soát của người dùng

- Người dùng **chủ động nhấn** “Gợi ý phòng bằng AI” — không tự chạy nền.
- Xem danh sách gợi ý → **bấm xem chi tiết** hoặc **bỏ qua**.
- Có thể **sửa lại** tiêu chí và gợi ý lại.
- **Đặt phòng** vẫn qua form booking thông thường; AI không tạo booking.

#### Mức độ khó

**Medium (Trung bình)**

#### Vì sao hữu ích

Gắn trực tiếp với pain point “tìm phòng mất thời gian” của GoStay; tăng giá trị demo so với chỉ filter form cơ bản; vẫn giữ luồng booking thủ công làm trung tâm.

---

### 3.2. Tóm tắt đánh giá / mô tả phòng (AI Review & Description Summary)

#### Mô tả

Trên trang chi tiết phòng, AI tóm tắt **mô tả dài** của phòng hoặc **vài đánh giá/comment mẫu** (nếu nhóm có seed review) thành 2–4 bullet hoặc một đoạn ngắn: điểm mạnh, điểm cần lưu ý.

#### Vấn đề người dùng giải quyết

- Mô tả phòng dài, khó đọc nhanh.
- Khó so sánh nhanh giữa các phòng khi chỉ có text dài hoặc nhiều comment rời rạc.

#### Input

| Loại dữ liệu | Ví dụ |
|--------------|--------|
| Mô tả phòng (text) | Nội dung do chủ KS nhập trong CRUD |
| Danh sách review (nếu có) | 5–10 comment mẫu: nội dung + điểm (1–5) |
| Metadata công khai | Tên phòng, tiện ích chính (không cần thông tin khách) |

#### Output

- Đoạn tóm tắt ngắn (tiếng Việt).
- Hoặc 2–4 gạch đầu dòng: “Ưu điểm”, “Lưu ý”.

#### Kiểm soát của người dùng

- Nút **“Xem tóm tắt AI”** — không hiển thị mặc định nếu API lỗi.
- Người dùng có thể **đóng** panel tóm tắt và đọc mô tả gốc.
- Ghi chú UI: *“Tóm tắt do AI tạo, có thể không chính xác 100%”*.

#### Mức độ khó

**Easy (Dễ)**

#### Vì sao hữu ích

Triển khai nhanh (một API call + prompt cố định); hỗ trợ tính năng core “xem chi tiết phòng”; không ảnh hưởng booking nếu tắt AI.

---

### 3.3. Trợ lý viết lại mô tả phòng cho chủ khách sạn (AI Room Description Assistant)

#### Mô tả

Trong form thêm/sửa phòng (phía chủ KS hoặc admin), nút **“Gợi ý mô tả bằng AI”** sinh hoặc viết lại mô tả marketing ngắn từ thông tin có sẵn: tên phòng, loại giường, giá, tiện ích đã chọn.

#### Vấn đề người dùng giải quyết

- Chủ KS mất thời gian viết mô tả đẹp, thống nhất.
- Mô tả sơ sài khiến khách khó quyết định trên GoStay.

#### Input

| Loại dữ liệu | Ví dụ |
|--------------|--------|
| Tên phòng | “Deluxe Double — View sông” |
| Loại / sức chứa | Double, 2 người |
| Giá (ngày/giờ) | 450.000đ/đêm |
| Tiện ích đã chọn | WiFi, điều hòa, bữa sáng |
| (Tuỳ chọn) Giọng văn | Ngắn gọn / thân thiện |

#### Output

- Một đoạn mô tả phòng (khoảng 3–5 câu) bằng tiếng Việt.
- (Tuỳ chọn) Gợi ý thêm 1–2 tiện ích phù hợp loại phòng.

#### Kiểm soát của người dùng

- Chủ KS **xem trước** text AI trong textarea → **Chấp nhận**, **Chỉnh sửa tay**, hoặc **Hủy**.
- Không tự lưu vào DB khi chưa bấm Save của form.
- Có thể generate lại nhiều lần.

#### Mức độ khó

**Easy (Dễ)**

#### Vì sao hữu ích

Hỗ trợ phía quản lý phòng (core feature #5 trong `PRODUCT_ANALYSIS.md`); tách biệt hoàn toàn luồng khách đặt phòng; demo rõ ràng trong màn admin.

---

### Tóm tắt 3 tính năng

| # | Tên tính năng | Đối tượng | Độ khó | Giai đoạn đề xuất |
|---|---------------|-----------|--------|-------------------|
| 1 | Gợi ý phòng theo nhu cầu | Khách hàng | Medium | Mở rộng MVP (ưu tiên) |
| 2 | Tóm tắt đánh giá / mô tả phòng | Khách hàng | Easy | Sau MVP hoặc song song nếu rảnh |
| 3 | Trợ lý viết mô tả phòng | Chủ KS / Admin | Easy | Sau MVP hoặc song song nếu rảnh |

---

## 4. Recommended AI Feature for MVP Extension

**Lựa chọn đề xuất:** **Gợi ý phòng theo nhu cầu người dùng (AI Room Recommendation)**

Nếu nhóm có thêm thời gian sau khi MVP booking chạy ổn, nên ưu tiên tính năng này trước hai tính năng còn lại.

| Lý do | Giải thích |
|-------|------------|
| **Đúng domain booking** | Trực tiếp hỗ trợ bước “tìm phòng” — trọng tâm của GoStay |
| **Giúp tìm phòng nhanh hơn** | Giảm ma sát so với lọc thủ công; thể hiện giá trị tìm phòng trong chuỗi GoStay ở mức đơn giản |
| **Dễ demo hơn chatbot** | Một form + danh sách kết quả; không cần hội thoại đa vòng, không cần xử lý nhiều intent |
| **Không tự đặt phòng** | AI chỉ gợi ý `room_id`; booking vẫn do user xác nhận — an toàn về nghiệp vụ và pháp lý học thuật |
| **Người dùng vẫn kiểm soát** | Có thể bỏ qua gợi ý, xem chi tiết, đổi tiêu chí; phù hợp nguyên tắc “human in the loop” |

Hai tính năng Easy (tóm tắt, viết mô tả) phù hợp làm **bổ sung nhẹ** nếu nhóm còn bandwidth; không nên làm cả ba cùng lúc nếu MVP core chưa xong.

---

## 5. Basic AI Flow

Luồng AI đơn giản cho tính năng **Gợi ý phòng theo nhu cầu** (recommended):

```text
[1] Người dùng nhập nhu cầu
    → địa điểm, ngân sách, check-in/check-out, số người, tiện ích ưa thích
         ↓
[2] Backend lọc sơ bộ phòng trong DB (trạng thái: còn trống, trong khoảng giá)
         ↓
[3] Gửi sang AI CHỈ: tiêu chí user + metadata phòng ứng viên (không PII)
         ↓
[4] AI trả về danh sách 3–5 phòng + lý do ngắn
         ↓
[5] UI hiển thị "Gợi ý từ AI" — user xem, so sánh
         ↓
[6] User chọn: "Xem chi tiết" HOẶC "Bỏ qua" HOẶC "Tìm lại"
         ↓
[7] Nếu đặt phòng → user điền form booking THỦ CÔNG và xác nhận
```

**Lưu ý triển khai:**

- Bước 2 (lọc DB) giúp AI không “bịa” phòng không tồn tại.
- Nếu API AI lỗi → fallback về **tìm kiếm/lọc thông thường** (MVP không AI vẫn chạy).
- Không lưu prompt chứa dữ liệu nhạy cảm; tuân thủ `AI_USAGE_POLICY.md`.

---

## 6. Risks and Mitigation

| Rủi ro | Mô tả | Cách giảm thiểu |
|--------|--------|------------------|
| **AI gợi ý phòng không phù hợp** | LLM chọn phòng không khớp ngân sách/tiện ích thực tế | Lọc DB trước; giới hạn AI chọn trong danh sách `room_id` hợp lệ; hiển thị giá & tiện ích rõ trên card gợi ý |
| **AI sinh giải thích không chính xác** | “Có hồ bơi” trong khi phòng không có | Prompt yêu cầu chỉ dựa trên field đã gửi; disclaimer trên UI; chủ KS duy trì dữ liệu phòng đúng |
| **Người dùng tin AI quá mức** | Book phòng không đọc kỹ chi tiết | Nhãn “Gợi ý AI — vui lòng kiểm tra trước khi đặt”; bắt buộc màn xác nhận booking |
| **Rủi ro quyền riêng tư** | Gửi email, lịch sử booking, payment lên API | Chỉ gửi tiêu chí tìm kiếm + metadata phòng công khai; không gửi PII; dùng `.env` cho API key |
| **API AI lỗi / hết quota** | Timeout, 429, key hết hạn | Try/catch + thông báo thân thiện; fallback search thường; cache kết quả ngắn hạn (tuỳ chọn); giới hạn số lần gọi/user trong demo |

---

## 7. Features Not Recommended Now

Các tính năng AI **không nên** làm ở giai đoạn đầu (MVP và mở rộng ngắn hạn):

| Tính năng | Lý do chưa phù hợp |
|-----------|---------------------|
| **Chatbot AI đầy đủ** | Cần quản lý context, nhiều intent, xử lý lỗi hội thoại — vượt thời gian và kỹ năng nhóm mới |
| **AI tự động đặt phòng** | Rủi ro nghiệp vụ cao (double booking, sai thời gian); trái nguyên tắc human confirmation |
| **AI dynamic pricing** | Cần dữ liệu lịch sử, rule giá, A/B test — out of scope như `PRODUCT_ANALYSIS.md` mục 7 |
| **AI phát hiện gian lận (fraud detection)** | Cần dataset và mô hình ML — không liên quan MVP booking cơ bản |
| **Trợ lý đặt phòng bằng giọng nói** | Thêm speech-to-text, mobile, UX phức tạp — không cần cho web MVP |
| **Hệ gợi ý cá nhân hóa nâng cao** | Collaborative filtering, hành vi dài hạn — quá lớn; gợi ý theo nhu cầu một lần là đủ demo |

Nhóm nên **hoàn thành MVP không AI** trước, sau đó thêm **một** tính năng AI nhỏ (ưu tiên gợi ý phòng) nếu còn thời gian và được giảng viên đồng ý.

---

## 8. Final Recommendation

**Khuyến nghị cuối cùng cho nhóm GoStay:**

1. **Hoàn thành MVP booking trước** — tìm kiếm, chi tiết phòng, đặt phòng, lịch sử, quản lý phòng — **không phụ thuộc AI**.
2. Nếu mở rộng, triển khai **Gợi ý phòng theo nhu cầu** làm tính năng AI đầu tiên: form nhu cầu → lọc DB → AI gợi ý 3–5 phòng → user tự quyết định xem chi tiết và **đặt phòng thủ công**.
3. Cân nhắc thêm **Tóm tắt mô tả phòng** hoặc **Trợ lý viết mô tả** nếu còn thời gian — cả hai độ khó Easy, ít rủi ro nghiệp vụ.
4. Luôn ghi log dùng AI trong `ai-logs/`, review output trước khi merge, và hiển thị disclaimer cho người dùng.

AI là **lớp hỗ trợ trải nghiệm**, không phải lõi sản phẩm. GoStay vẫn là ứng dụng đặt phòng **đơn giản, tập trung MVP** — học hỏi từ các nền tảng lớn nhưng không sao chép hệ sinh thái AI phức tạp của họ.

---

*Tài liệu này bổ sung cho `PRODUCT_ANALYSIS.md` (mục 6) và hướng dẫn triển khai AI an toàn theo `AI_USAGE_POLICY.md`.*

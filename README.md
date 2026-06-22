# GoStay - Ứng dụng đặt phòng khách sạn

## 1. Giới thiệu dự án

GoStay là một website đặt phòng cho chuỗi khách sạn nhỏ mang thương hiệu GoStay, được xây dựng theo hướng MVP cho đồ án môn Công nghệ phần mềm. Trong phạm vi MVP, GoStay gồm nhiều chi nhánh và nhiều loại phòng thuộc cùng một hệ thống. Mục tiêu của GoStay là giúp khách hàng tìm chi nhánh/phòng phù hợp, xem thông tin chi tiết, đặt phòng theo ngày hoặc theo giờ và quản lý lịch sử đặt phòng một cách nhanh chóng, rõ ràng và dễ sử dụng.


## 2. Mục tiêu sản phẩm

GoStay tập trung giải quyết các vấn đề chính:

* Người dùng mất nhiều thời gian để tìm phòng phù hợp.
* Thông tin phòng, giá, tiện nghi và trạng thái phòng chưa rõ ràng.
* Quy trình đặt phòng còn nhiều bước.
* Admin / nhân viên quản lý chuỗi GoStay cần công cụ đơn giản để quản lý chi nhánh, phòng, giá và trạng thái phòng.
* Người dùng cần gợi ý phòng phù hợp với nhu cầu cá nhân.

## 3. Đối tượng người dùng

Các nhóm người dùng chính của GoStay gồm:

* Khách du lịch.
* Người đi công tác.
* Sinh viên hoặc người cần chỗ ở ngắn hạn.
* Admin / nhân viên quản lý chuỗi GoStay.

## 4. Phạm vi MVP

Các chức năng chính trong MVP:

* Đăng ký, đăng nhập.
* Xem danh sách chi nhánh/phòng thuộc chuỗi GoStay.
* Tìm kiếm và lọc chi nhánh/phòng theo khu vực, mức giá, loại phòng.
* Xem chi tiết phòng.
* Đặt phòng.
* Xem lịch sử đặt phòng.
* Admin thêm, sửa, xóa chi nhánh/phòng và cập nhật giá, hình ảnh, trạng thái phòng.
* AI gợi ý phòng phù hợp theo nhu cầu người dùng.

Các chức năng chưa làm trong MVP:

* Thanh toán online thật.
* Voucher/mã giảm giá.
* Tích điểm thành viên.
* QR check-in.
* Chatbot hỗ trợ.
* Bản đồ vị trí khách sạn.

## 5. Kết quả tuần 1

Nhóm đã hoàn thành các tài liệu định hướng ban đầu:

* docs/product/PRODUCT_DIRECTION.md
* AGENT_GUIDE.md
* AI_USAGE_POLICY.md
* ai-logs/week-01.md

## 6. Kết quả tuần 2

Nhóm đã hoàn thành phân tích ý tưởng sản phẩm và đề xuất tính năng AI:

* docs/product/PRODUCT_ANALYSIS.md
* docs/product/AI_FEATURE_PROPOSAL.md
* ai-logs/week-02.md

## 7. Kết quả tuần 3

Nhóm đã hoàn thành tài liệu UX prototype và cập nhật yêu cầu chức năng cho GoStay:

* docs/product/UX_PROTOTYPE.md
* docs/product/REQUIREMENTS.md
* ai-logs/week-03.md

Trong tuần 3, nhóm tập trung vào việc mô tả prototype giao diện, luồng người dùng, mock data và cập nhật requirements cho MVP. Nhóm chưa tập trung vào backend phức tạp mà ưu tiên làm rõ phạm vi sản phẩm và trải nghiệm người dùng.

## 8. Cấu trúc repository

```text
GoStay/
├── README.md
├── AGENT_GUIDE.md
├── AI_USAGE_POLICY.md
├── PROMPTS.md
├── .gitignore
├── ai-logs/
├── docs/
│   ├── product/
│   └── weekly/
```

* `docs/product/` chứa tài liệu sản phẩm như định hướng, phân tích, requirements, UX prototype và đề xuất tính năng AI.
* `docs/weekly/` chứa các bài nộp theo tuần cho môn Công nghệ phần mềm.
* `ai-logs/` chứa nhật ký sử dụng AI theo tuần.

## 9. Công cụ sử dụng

Nhóm sử dụng các công cụ hỗ trợ trong quá trình làm đồ án:

* GitHub để quản lý source code và tài liệu.
* Cursor/AI Agent để hỗ trợ tạo tài liệu, phân tích yêu cầu và đề xuất prototype.
* Figma để thiết kế wireframe/prototype.
* Markdown để viết tài liệu dự án.

## 10. Ghi chú

Dự án hiện đang ở giai đoạn tuần 3: thiết kế UX prototype, mô tả luồng người dùng, cập nhật requirements và user stories cho MVP.

Nhóm sử dụng AI như một công cụ hỗ trợ, nhưng vẫn kiểm tra, chỉnh sửa và chịu trách nhiệm với nội dung cuối cùng.

# GoStay - Website đặt phòng khách sạn

## 1. Giới thiệu

GoStay là website hỗ trợ khách hàng tìm kiếm và đặt phòng trong một chuỗi khách sạn nhỏ.

Hệ thống có hai vai trò chính:

- Khách hàng: tìm kiếm phòng, xem chi tiết phòng, đặt phòng và xem lịch sử đặt phòng.
- Admin: quản lý chi nhánh, phòng, giá phòng, trạng thái phòng và booking.

GoStay được xây dựng theo phạm vi MVP, tập trung vào các chức năng đặt phòng cơ bản và một tính năng AI gợi ý phòng.

## 2. Chức năng chính

### Khách hàng

- Đăng ký, đăng nhập và đăng xuất.
- Tìm kiếm và lọc phòng.
- Xem danh sách phòng còn trống.
- Xem thông tin chi tiết phòng.
- Chọn ngày nhận phòng và trả phòng.
- Đặt phòng.
- Xem và hủy booking.
- Nhận gợi ý phòng từ AI.

### Admin

- Quản lý chi nhánh.
- Quản lý phòng.
- Cập nhật giá và trạng thái phòng.
- Xem và quản lý booking.
- Xem thống kê cơ bản.

## 3. Tính năng AI

Tính năng AI hỗ trợ gợi ý phòng phù hợp dựa trên:

- Khu vực hoặc chi nhánh.
- Ngân sách.
- Số lượng khách.
- Thời gian lưu trú.
- Tiện nghi mong muốn.

AI chỉ gợi ý từ danh sách phòng có thật trong hệ thống và không tự tạo thông tin phòng mới.

Kết quả được đánh dấu là nội dung do AI tạo. Người dùng có thể bỏ qua kết quả và tự lựa chọn phòng.

## 4. Tiến độ hiện tại - Tuần 8

Dự án hiện đang ở tuần 8 theo lộ trình học phần.

Nhóm đã hoàn thành:

- Phân tích sản phẩm và xác định phạm vi MVP.
- Persona, Scenario, User Story và Product Backlog.
- Thiết kế giao diện và luồng người dùng.
- Thiết kế kiến trúc hệ thống và mô hình dữ liệu.
- Triển khai chức năng cốt lõi của hệ thống.
- Triển khai tính năng AI gợi ý phòng.
- Tạo các GitHub Issues và Pull Requests cho từng chức năng.

Trong tuần 8, nhóm tập trung:

- Kiểm thử các luồng chức năng chính.
- Kiểm tra đăng nhập và phân quyền.
- Kiểm tra dữ liệu đầu vào.
- Kiểm tra nguy cơ đặt trùng phòng.
- Rà soát bảo mật và thông tin cấu hình.
- Kiểm tra AI có tạo thông tin sai hoặc gây hiểu nhầm hay không.
- Hoàn thiện tài liệu kiểm thử và an toàn AI.

## 5. Công nghệ sử dụng

- Frontend: HTML, CSS, JavaScript.
- Database và Authentication: Supabase.
- Quản lý mã nguồn: GitHub.
- Thiết kế giao diện: Figma.
- AI Agent: Codex, Cursor hoặc công cụ tương đương.
- AI Feature: API mô hình ngôn ngữ hoặc SDK phù hợp.

## 6. Cấu trúc repository

```text
GoStay/
├── frontend/
│   ├── css/
│   ├── js/
│   ├── images/
│   └── các trang HTML
├── docs/
│   ├── product/
│   ├── architecture/
│   └── testing/
├── ai-logs/
├── README.md
├── AGENT_GUIDE.md
├── AI_USAGE_POLICY.md
├── PROMPTS.md
└── .gitignore

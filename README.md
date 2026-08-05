# GoStay - Ứng dụng đặt phòng khách sạn

GoStay là website đặt phòng dành cho một chuỗi khách sạn nhỏ có nhiều chi nhánh. Dự án tập trung vào hai nhóm người dùng: khách hàng tìm và đặt phòng; Admin quản lý dữ liệu và hoạt động vận hành.

Website production: [https://gostay-hotel.vercel.app](https://gostay-hotel.vercel.app)

## Chức năng chính

### Khách hàng

- Đăng ký, đăng nhập, đăng xuất và duy trì phiên làm việc.
- Đăng nhập bằng Google, xác nhận email và khôi phục mật khẩu bằng OTP.
- Tìm kiếm, lọc và xem phòng còn trống theo thời gian lưu trú.
- Xem thông tin phòng, giá, loại phòng, chi nhánh và tiện nghi.
- Đặt phòng, xem lịch sử và hủy booking của chính mình.
- Nhận gợi ý phòng bằng AI dựa trên nhu cầu và các phòng có thật trong hệ thống.

### Admin

- Theo dõi số liệu tổng quan trên dashboard.
- Quản lý chi nhánh, phòng và loại phòng.
- Cập nhật giá, tiện nghi và trạng thái phòng.
- Xem và quản lý booking.
- Xem và quản lý tài khoản người dùng.

## AI gợi ý phòng

GoStay sử dụng Gemini thông qua Supabase Edge Function `recommend-rooms`. AI chỉ xếp hạng và giải thích lựa chọn từ danh sách phòng có thật, còn trống và phù hợp với tiêu chí tìm kiếm; AI không tự tạo phòng hoặc giá mới.

Người dùng luôn có thể bỏ qua kết quả AI và sử dụng chức năng tìm kiếm thông thường. Kết quả gợi ý được đánh dấu là nội dung do AI tạo.

## Công nghệ

- Frontend: HTML, CSS và JavaScript thuần.
- Backend: Supabase Edge Functions.
- Cơ sở dữ liệu: PostgreSQL trên Supabase.
- Xác thực: Supabase Auth và Google OAuth.
- Bảo mật dữ liệu: Row Level Security (RLS), RPC và phân quyền Customer/Admin.
- AI: Google Gemini API.
- Kiểm thử: Playwright E2E và Node.js runtime security tests.
- CI/CD: GitHub Actions và Vercel.

## Kiến trúc triển khai

Frontend được triển khai trên Vercel. Các dịch vụ PostgreSQL, Auth, RLS, RPC và Edge Functions chạy trên Supabase Cloud. Trình duyệt gọi API ứng dụng qua Edge Function; thông tin kết nối cơ sở dữ liệu và secret không được đưa vào mã frontend.

## Chạy dự án tại máy cá nhân

### Yêu cầu

- Git.
- Node.js 20 trở lên nếu cần chạy kiểm thử.
- Python 3 hoặc một static web server tương đương để phục vụ frontend.

### Cài đặt

```bash
git clone https://github.com/ParkZoung/cnpm-group-project.git
cd cnpm-group-project
npm ci
```

Khởi chạy frontend tại cổng `4173`:

```bash
python -m http.server 4173 --directory frontend
```

Sau đó mở [http://127.0.0.1:4173](http://127.0.0.1:4173). Frontend hiện sử dụng API Supabase development đã được cấu hình trong dự án.

Backend Supabase được đặt tại `backend/supabase`. Có thể chạy local từ thư mục gốc:

```bash
npm run backend:start
npm run backend:serve:api
```

Không chạy `npm run backend:db:push` với production trước khi đối chiếu schema và
lịch sử migration. Xem thêm [`backend/README.md`](backend/README.md) và
[`docs/architecture/PROJECT_STRUCTURE.md`](docs/architecture/PROJECT_STRUCTURE.md).

## Cấu hình kiểm thử

Sao chép `.env.example` thành `.env`, sau đó thay các giá trị mẫu bằng tài khoản và API dành riêng cho môi trường development/test. Không chạy bộ kiểm thử ghi dữ liệu trên production và không commit file `.env`.

Các lệnh chính:

```bash
npm run test:e2e
npm run test:e2e:admin
npm run test:security
```

- `test:e2e`: kiểm tra luồng đặt phòng của khách hàng.
- `test:e2e:admin`: kiểm tra các luồng quản trị.
- `test:security`: kiểm tra phân quyền và hành vi bảo mật khi chạy thực tế.

Chi tiết xem tại [`docs/testing/E2E.md`](docs/testing/E2E.md) và thư mục [`docs/security`](docs/security).

## Bảo mật và tính toàn vẹn dữ liệu

- Customer chỉ được xem và thay đổi dữ liệu thuộc quyền sở hữu của mình.
- Admin được kiểm tra quyền ở cả giao diện và backend.
- RLS, RPC, constraint và transaction phía PostgreSQL bảo vệ các thao tác quan trọng.
- Cơ chế kiểm tra khả dụng và ràng buộc cơ sở dữ liệu hạn chế đặt trùng phòng.
- Nội dung động được đưa vào DOM bằng API an toàn để giảm nguy cơ XSS.
- Secret và thông tin môi trường không được commit vào repository.

## Cấu trúc repository

```text
cnpm-group-project/
├── frontend/              # Trang HTML, CSS, JavaScript và hình ảnh
├── backend/
│   └── supabase/          # Backend giữ cấu trúc chuẩn của Supabase CLI
│       ├── functions/     # API và Edge Function gợi ý phòng
│       ├── migrations/    # Migration cơ sở dữ liệu
│       ├── seeds/         # Dữ liệu catalog mẫu
│       ├── preflight/     # Kiểm tra trước khi triển khai
│       └── rollbacks/     # Kịch bản rollback được kiểm soát
├── tests/
│   ├── e2e/               # Kiểm thử Playwright
│   └── security/          # Runtime security tests
├── docs/                  # Tài liệu sản phẩm, kiến trúc, DB và kiểm thử
├── ai-logs/               # Nhật ký sử dụng AI theo tuần
├── .github/workflows/     # GitHub Actions CI
├── .env.example           # Mẫu biến môi trường, không chứa secret
└── package.json           # Lệnh và dependency kiểm thử
```

## Phạm vi và hạn chế hiện tại

GoStay đã hoàn thành các luồng cốt lõi của MVP nhưng chưa tích hợp thanh toán trực tuyến, email/SMS nhắc lịch, đánh giá sau lưu trú, voucher hoặc bản đồ nâng cao. AI vẫn phụ thuộc vào dịch vụ bên ngoài và cần tiếp tục hoàn thiện rate limit trước khi mở rộng production. Giao diện mobile và accessibility cũng còn có thể tối ưu thêm.

## Tài liệu dự án

- [`docs/product`](docs/product): định hướng, yêu cầu và phân tích sản phẩm.
- [`docs/architecture`](docs/architecture): kiến trúc hệ thống.
- [`docs/database`](docs/database): thiết kế và ghi chú cơ sở dữ liệu.
- [`docs/testing`](docs/testing): kế hoạch và hướng dẫn kiểm thử.
- [`docs/security`](docs/security): kiểm tra và tài liệu bảo mật.
- [`AI_USAGE_POLICY.md`](AI_USAGE_POLICY.md): chính sách sử dụng AI của nhóm.

# GoStay - Ứng dụng đặt phòng khách sạn

GoStay là website đặt phòng dành cho một chuỗi khách sạn nhỏ có nhiều chi nhánh. Dự án có ba role chuẩn: `customer`, `staff` và `admin`. Booking, authentication và quản trị là core; AI, VietQR/online check-in và Staff operations là extension.

Website production: [https://gostay-hotel.vercel.app](https://gostay-hotel.vercel.app)

## Chức năng chính

### Khách hàng

- Đăng ký, đăng nhập, đăng xuất và duy trì phiên làm việc.
- Đăng nhập bằng Google, xác nhận email và khôi phục mật khẩu bằng OTP.
- Tìm kiếm, lọc và xem phòng còn trống theo thời gian lưu trú.
- Xem thông tin phòng, giá, loại phòng, chi nhánh và tiện nghi.
- Đặt phòng, xem lịch sử và hủy booking của chính mình.
- Nhận gợi ý phòng bằng AI dựa trên nhu cầu và các phòng có thật trong hệ thống.
- Khởi tạo online check-in, chọn thanh toán đủ hoặc đặt cọc và gửi xác nhận chuyển khoản VietQR.

### Admin

- Theo dõi số liệu tổng quan trên dashboard.
- Quản lý chi nhánh, phòng và loại phòng.
- Cập nhật giá, tiện nghi và trạng thái phòng.
- Xem và quản lý booking.
- Xem và quản lý tài khoản người dùng.

### Staff (extension)

- Xác nhận booking thuộc chi nhánh được phân công.
- Đối chiếu yêu cầu thanh toán VietQR, thu phần tiền còn lại và ghi nhận hoàn tiền.
- Kiểm tra token online check-in, check-in và check-out khách.

## AI gợi ý phòng

GoStay sử dụng Gemini thông qua Supabase Edge Function `recommend-rooms`. AI chỉ xếp hạng và giải thích lựa chọn từ danh sách phòng có thật, còn trống và phù hợp với tiêu chí tìm kiếm; AI không tự tạo phòng hoặc giá mới.

Người dùng luôn có thể bỏ qua kết quả AI và sử dụng chức năng tìm kiếm thông thường. Kết quả gợi ý được đánh dấu là nội dung do AI tạo.

## Công nghệ

- Frontend: HTML, CSS và JavaScript thuần.
- Backend: Supabase Edge Functions.
- Cơ sở dữ liệu: PostgreSQL trên Supabase.
- Xác thực: Supabase Auth và Google OAuth.
- Bảo mật dữ liệu: Row Level Security (RLS), RPC và phân quyền `customer`/`staff`/`admin`.
- AI: Google Gemini API.
- Kiểm thử: Playwright E2E và Node.js runtime security tests.
- CI/CD: GitHub Actions và Vercel.

## Kiến trúc triển khai

Frontend được triển khai trên Vercel. Các dịch vụ PostgreSQL, Auth, RLS, RPC và Edge Functions chạy trên Supabase Cloud. Trình duyệt gọi API ứng dụng qua Edge Function; thông tin kết nối cơ sở dữ liệu và secret không được đưa vào mã frontend. Biến toàn cục `window.gostaySupabase` chỉ là compatibility facade giữ API cũ cho frontend, không phải Supabase database client và không kết nối trực tiếp tới PostgreSQL.

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
npm run backend:serve:recommendations
```

Không chạy `supabase db push` với production trước khi đối chiếu schema và lịch
sử migration; dự án cố ý không cung cấp npm script cho thao tác này. Xem thêm
[`backend/README.md`](backend/README.md) và
[`docs/architecture/PROJECT_STRUCTURE.md`](docs/architecture/PROJECT_STRUCTURE.md).

## Cấu hình kiểm thử

Sao chép `.env.example` thành `.env`, sau đó thay các giá trị mẫu bằng tài khoản và API dành riêng cho môi trường development/test. Không chạy bộ kiểm thử ghi dữ liệu trên production và không commit file `.env`.

Các lệnh chính:

```bash
npm run test:e2e
npm run test:e2e:admin
npm run test:security
npm run test:staff-contract
```

- `test:e2e`: kiểm tra luồng đặt phòng của khách hàng.
- `test:e2e:admin`: kiểm tra các luồng quản trị.
- `test:security`: kiểm tra phân quyền và hành vi bảo mật khi chạy thực tế.
- `test:staff-contract`: kiểm tra contract Staff, payment và online check-in.

Chi tiết xem tại [`docs/testing/E2E.md`](docs/testing/E2E.md) và thư mục [`docs/security`](docs/security).

## Quy trình triển khai

1. Chạy kiểm tra syntax, migration và các test phù hợp ở local.
2. Đối chiếu schema cùng migration history trước khi áp dụng database; không replay
   migration đã có object trên production.
3. Áp dụng thay đổi database tương thích ngược trước, sau đó deploy Edge Functions
   và frontend.
4. Kiểm tra lại authentication, booking core và Admin trên môi trường đích; chỉ bật
   lần lượt Staff, VietQR và AI sau khi core ổn định.
5. Với production, phải có backup/restore point và phương án rollback. Xem trạng
   thái kiểm tra gần nhất trong
   [`docs/security/CURRENT_SECURITY_STATUS.md`](docs/security/CURRENT_SECURITY_STATUS.md).

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

GoStay đã hoàn thành các luồng core của MVP. VietQR hiện là quy trình khách khai báo chuyển khoản và Staff duyệt, chưa phải cổng thanh toán tự động hoặc đối soát ngân hàng thời gian thực. Email/SMS nhắc lịch, đánh giá sau lưu trú, voucher và bản đồ nâng cao chưa được tích hợp. AI vẫn phụ thuộc vào dịch vụ bên ngoài và cần tiếp tục hoàn thiện rate limit trước khi mở rộng production. Các extension phải có thể ngừng hoạt động mà không chặn booking core.

## Tài liệu dự án

- [`docs/product`](docs/product): định hướng, yêu cầu và phân tích sản phẩm.
- [`docs/architecture`](docs/architecture): kiến trúc hệ thống.
- [`docs/architecture/DOMAIN_TERMS.md`](docs/architecture/DOMAIN_TERMS.md): role và trạng thái nghiệp vụ chuẩn.
- [`docs/database`](docs/database): thiết kế và ghi chú cơ sở dữ liệu.
- [`docs/testing`](docs/testing): kế hoạch và hướng dẫn kiểm thử.
- [`docs/security`](docs/security): kiểm tra và tài liệu bảo mật.
- [`docs/security/CURRENT_SECURITY_STATUS.md`](docs/security/CURRENT_SECURITY_STATUS.md): báo cáo security hiện trạng theo commit và môi trường.
- [`AI_USAGE_POLICY.md`](AI_USAGE_POLICY.md): chính sách sử dụng AI của nhóm.

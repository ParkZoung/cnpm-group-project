# GoStay customer booking E2E

Repository này có đúng một bài Playwright E2E bảo vệ luồng booking customer:

```text
đăng nhập → tìm phòng trống → xem chi tiết → tạo booking
→ xem lịch sử → hủy đúng booking → tìm lại đúng phòng
```

Test chỉ chạy trên Chromium, một worker, không retry và không chạy song song.

## Điều kiện môi trường

Chỉ chạy test với Supabase demo/test, không chạy trên production. Tài khoản phải là
customer test riêng, có profile `active`. Test không dùng Admin, service-role key,
SQL hoặc API cleanup riêng; tạo và hủy booking đều đi qua giao diện hiện tại.

Các biến bắt buộc:

```text
GOSTAY_E2E_EMAIL
GOSTAY_E2E_PASSWORD
GOSTAY_E2E_GUEST_NAME
GOSTAY_E2E_GUEST_PHONE
```

`GOSTAY_E2E_BASE_URL` là tùy chọn và mặc định là
`http://127.0.0.1:4173`.

Sao chép `.env.example` thành `.env`, thay bằng thông tin của customer test:

```powershell
Copy-Item .env.example .env
```

Không commit `.env`. Playwright không tự động đọc file này. Script npm của dự án
chủ động gọi Node với `--env-file-if-exists=.env`; nếu không có `.env`, các biến
có thể được truyền từ shell hoặc GitHub Actions.

## Cài đặt và chạy

```powershell
npm.cmd ci
npx.cmd playwright install chromium
npm.cmd run test:e2e
```

Chạy ba lần tuần tự:

```powershell
npm.cmd run test:e2e:three
```

Trên macOS/Linux dùng `npm` và `npx` thay cho `npm.cmd` và `npx.cmd`.

HTML report được tạo tại `playwright-report/`. Screenshot và trace của lần lỗi
được giữ trong `test-results/`. Không chia sẻ các artifact ngoài phạm vi tin cậy:
trace trình duyệt có thể chứa dữ liệu của customer test dù workflow không upload
storage state, cookie hoặc session token riêng.

## An toàn dữ liệu

- Ngày được tính theo lịch local và luôn nằm trong tương lai.
- Test thử tối đa ba khoảng ngày và chọn phòng động từ Availability Search.
- Booking được nhận diện bằng UUID, booking code, room ID và khoảng ngày.
- Nút hủy chỉ được lấy trong hàng chứa đúng booking code.
- `afterEach` cleanup lại qua giao diện nếu test lỗi sau khi tạo booking.
- Nếu không xác định chính xác một hàng, cleanup dừng và báo UUID/code đã biết;
  test không đoán hoặc hủy booking khác.

## GitHub Actions

Giai đoạn đầu, E2E chỉ chạy khi chọn **Run workflow** (`workflow_dispatch`).
Repository secrets cần cấu hình:

```text
GOSTAY_E2E_EMAIL
GOSTAY_E2E_PASSWORD
GOSTAY_E2E_GUEST_NAME
GOSTAY_E2E_GUEST_PHONE
```

Nếu thiếu secret, job ghi rõ tên biến thiếu rồi skip các bước E2E. Workflow dùng
concurrency group `gostay-shared-e2e`, không hủy lượt đang chạy, để tránh hai lượt
cùng giữ phòng trên Supabase demo.

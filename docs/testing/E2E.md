# Kiểm thử GoStay

Tài liệu này mô tả các bộ kiểm thử tự động hiện có trong repository. Chỉ chạy
test có ghi dữ liệu với Supabase development/demo dành riêng; không chạy trên
production.

## Bộ kiểm thử

| Lệnh | File chính | Phạm vi |
|---|---|---|
| `npm run test:e2e` | `tests/e2e/core-booking.spec.js` | Customer đăng nhập, tìm phòng, đặt, xem lịch sử, hủy và tìm lại phòng |
| `npm run test:e2e:three` | `tests/e2e/core-booking.spec.js` | Lặp tuần tự luồng customer ba lần |
| `npm run test:e2e:admin` | `tests/e2e/admin.spec.js` | Authentication, dashboard, catalog, profile và booking của Admin |
| `npx playwright test tests/e2e/ui-audit.spec.js` | `tests/e2e/ui-audit.spec.js` | Audit các route và hành vi UI chính |
| `npm run test:security` | `tests/security/runtime-security.test.js` | RLS, authorization, ownership và booking đồng thời trên môi trường runtime |
| `npm run test:staff-contract` | `tests/security/staff-payment-contract.test.js` | Staff branch session, payment, online check-in và duplicate-booking contract |

Ngoài ra, `tests/security/admin-profile-email-contract.test.js` kiểm tra contract
profile Admin. CI chạy syntax check và migration version check trước các test phù
hợp với từng event.

## Biến môi trường

Sao chép `.env.example` thành `.env` và thay placeholder bằng tài khoản/API của
môi trường test. Không commit `.env`.

Customer E2E cần:

```text
GOSTAY_E2E_EMAIL
GOSTAY_E2E_PASSWORD
GOSTAY_E2E_GUEST_NAME
GOSTAY_E2E_GUEST_PHONE
```

Admin E2E và runtime security cần thêm các tài khoản được liệt kê trong
`.env.example`, gồm Admin và customer thứ hai. `GOSTAY_E2E_BASE_URL` là tùy chọn,
mặc định `http://127.0.0.1:4173`.

Các npm script dùng `--env-file-if-exists=.env`; biến cũng có thể được truyền từ
shell hoặc GitHub Actions.

## Cài đặt và chạy

```powershell
npm.cmd ci
npx.cmd playwright install chromium
npm.cmd run test:e2e
npm.cmd run test:e2e:admin
npm.cmd run test:security
npm.cmd run test:staff-contract
```

Trên macOS/Linux dùng `npm` và `npx` thay cho `npm.cmd` và `npx.cmd`.

## An toàn dữ liệu và cleanup

- Customer E2E chọn ngày tương lai và phòng động từ Availability Search.
- Booking test được nhận diện bằng UUID, booking code, room ID và khoảng ngày.
- Cleanup chỉ hủy đúng booking đã tạo; không đoán hoặc hủy booking khác.
- Admin/runtime test phải dùng tài khoản và dữ liệu dành riêng cho test.
- HTML report nằm trong `playwright-report/`; screenshot và trace nằm trong
  `test-results/`. Artifact có thể chứa dữ liệu phiên test và chỉ được chia sẻ
  trong phạm vi tin cậy.

## GitHub Actions

- Static checks chạy khi push hoặc pull request vào `main`.
- Runtime security chạy khi push `main` hoặc `workflow_dispatch` nếu đủ secrets.
- Customer booking E2E chỉ chạy qua `workflow_dispatch` trong giai đoạn ổn định.
- Nếu thiếu secret, workflow nêu tên biến thiếu và bỏ qua phần E2E tương ứng.
- Concurrency group ngăn hai lượt test dùng chung môi trường cùng giữ phòng.

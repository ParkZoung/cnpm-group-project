const { test, expect } = require('@playwright/test');

const REQUIRED_ENVIRONMENT_VARIABLES = [
  'GOSTAY_E2E_EMAIL',
  'GOSTAY_E2E_PASSWORD',
  'GOSTAY_E2E_GUEST_NAME',
  'GOSTAY_E2E_GUEST_PHONE'
];
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function requireTestEnvironment() {
  const missing = REQUIRED_ENVIRONMENT_VARIABLES.filter(function (name) {
    return !String(process.env[name] || '').trim();
  });

  if (missing.length) {
    throw new Error(
      `Missing required E2E environment variables: ${missing.join(', ')}.`
    );
  }

  return {
    email: process.env.GOSTAY_E2E_EMAIL.trim(),
    password: process.env.GOSTAY_E2E_PASSWORD,
    guestName: process.env.GOSTAY_E2E_GUEST_NAME.trim(),
    guestPhone: process.env.GOSTAY_E2E_GUEST_PHONE.trim()
  };
}

function localDateString(daysFromToday) {
  const date = new Date();
  date.setHours(12, 0, 0, 0);
  date.setDate(date.getDate() + daysFromToday);

  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function displayDate(isoDate) {
  return isoDate.split('-').reverse().join('/');
}

async function waitForSearchOutcome(page) {
  const count = page.locator('#catalog-result-count');
  const empty = page.locator('#catalog-empty');
  const error = page.locator('#catalog-error');
  const validationError = page.locator('#availability-validation-error');

  await expect.poll(async function () {
    if (await count.isVisible()) return 'results';
    if (await empty.isVisible()) return 'empty';
    if (await error.isVisible()) return 'error';
    if (await validationError.isVisible()) return 'validation-error';
    return 'pending';
  }, {
    message: 'Availability Search did not reach a terminal UI state',
    timeout: 30_000
  }).not.toBe('pending');

  if (await validationError.isVisible()) {
    throw new Error(`Availability Search validation failed: ${await validationError.textContent()}`);
  }

  if (await error.isVisible()) {
    throw new Error(`Availability Search failed: ${await error.textContent()}`);
  }

  return (await count.isVisible()) ? 'results' : 'empty';
}

async function searchForAvailableRoom(page) {
  await page.goto('/search.html');
  await expect.poll(
    () => page.locator('#branch-filter option').count(),
    {
      message: 'Availability Search metadata did not finish loading',
      timeout: 30_000
    }
  ).toBeGreaterThan(1);

  for (let attempt = 0; attempt < 3; attempt += 1) {
    const checkIn = localDateString(14 + attempt * 7);
    const checkOut = localDateString(16 + attempt * 7);

    await page.getByLabel('Ngày nhận phòng').fill(checkIn);
    await page.getByLabel('Ngày trả phòng').fill(checkOut);
    await page.getByLabel('Số khách').fill('1');
    await expect(page.getByLabel('Ngày nhận phòng')).toHaveValue(checkIn);
    await expect(page.getByLabel('Ngày trả phòng')).toHaveValue(checkOut);
    await page.getByRole('button', { name: 'Kiểm tra phòng trống' }).click();

    const outcome = await waitForSearchOutcome(page);
    if (outcome === 'empty') continue;

    const roomLink = page.locator('#catalog-room-list')
      .getByRole('link', { name: 'Xem chi tiết' })
      .first();
    await expect(roomLink).toBeVisible();

    const href = await roomLink.getAttribute('href');
    const roomUrl = new URL(href, page.url());
    const roomId = roomUrl.searchParams.get('id');

    if (!roomId || !/^[1-9]\d*$/.test(roomId)) {
      throw new Error('Selected availability result did not contain a valid room ID.');
    }

    const roomCard = roomLink.locator('xpath=ancestor::article[1]');
    const roomLabel = (await roomCard.getByRole('heading').textContent()).trim();

    return { checkIn, checkOut, roomId, roomLabel, roomLink };
  }

  throw new Error('No available room was found in the three permitted future date ranges.');
}

function bookingRowByCode(page, bookingCode) {
  return page.locator('#booking-history-body tr').filter({
    has: page.locator('td').filter({ hasText: new RegExp(`^${escapeRegExp(bookingCode)}$`) })
  });
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

async function acceptCancellation(page, row) {
  const dialogPromise = page.waitForEvent('dialog').then(async function (dialog) {
    expect(dialog.type()).toBe('confirm');
    await dialog.accept();
  });
  await row.getByRole('button', { name: 'Hủy booking' }).click();
  await dialogPromise;
}

async function cleanupCreatedBooking(page, booking) {
  if (booking.cancelled || (!booking.id && !booking.code)) return;

  await page.goto('/booking-history.html');
  await expect(page.locator('#history-table-container')).toBeVisible();

  let row;
  if (booking.code) {
    row = bookingRowByCode(page, booking.code);
  } else {
    row = page.locator(
      `#booking-history-body tr:has(button[data-booking-id="${booking.id}"])`
    );
  }

  if (await row.count() !== 1) {
    throw new Error(
      `Cleanup could not identify exactly one booking row (UUID: ${booking.id || 'unknown'}, `
      + `code: ${booking.code || 'unknown'}). No booking was guessed or cancelled.`
    );
  }

  const cancelButton = row.getByRole('button', { name: 'Hủy booking' });
  if (await cancelButton.count() === 0) {
    await expect(row).toContainText('Đã hủy');
    booking.cancelled = true;
    return;
  }

  await acceptCancellation(page, row);
  await expect(page.locator('#history-success')).toHaveText('Đã hủy booking thành công.');

  if (booking.code) {
    await expect(bookingRowByCode(page, booking.code)).toContainText('Đã hủy');
  }
  booking.cancelled = true;
}

async function recoverBookingIdentityFromSuccessPage(page, booking) {
  if (booking.id && booking.code) return;

  const currentUrl = new URL(page.url());
  if (currentUrl.pathname.endsWith('/bookingsuccess.html')) {
    const bookingId = currentUrl.searchParams.get('id');
    if (bookingId && UUID_PATTERN.test(bookingId)) {
      booking.id = bookingId;
    }

    const code = page.locator('#success-booking-code');
    if (await code.isVisible()) {
      booking.code = (await code.textContent()).trim() || booking.code;
    }
  }
}

test.describe('GoStay customer booking core flow', function () {
  let booking;

  test.beforeEach(function () {
    booking = {
      id: null,
      code: null,
      roomId: null,
      checkIn: null,
      checkOut: null,
      cancelled: false
    };
  });

  test.afterEach(async function ({ page }, testInfo) {
    await recoverBookingIdentityFromSuccessPage(page, booking);
    if (!booking.id && !booking.code) return;

    try {
      await cleanupCreatedBooking(page, booking);
    } catch (cleanupError) {
      await testInfo.attach('cleanup-failure.txt', {
        body: Buffer.from(
          `Booking cleanup failed. UUID: ${booking.id || 'unknown'}; `
          + `code: ${booking.code || 'unknown'}; error: ${cleanupError.message}`
        ),
        contentType: 'text/plain'
      });
      throw cleanupError;
    }
  });

  test('customer can book, cancel, and find the same room again', async ({ page }) => {
    const credentials = requireTestEnvironment();

    await page.goto('/login.html');
    await page.getByLabel('Email').fill(credentials.email);
    await page.getByLabel('Mật khẩu').fill(credentials.password);
    await page.locator('#login-submit').click();

    await expect(page).toHaveURL(/\/index\.html$/);
    await expect(page.getByRole('link', { name: 'Đăng xuất' })).toBeVisible();

    const selection = await searchForAvailableRoom(page);
    booking.roomId = selection.roomId;
    booking.checkIn = selection.checkIn;
    booking.checkOut = selection.checkOut;

    await selection.roomLink.click();
    await expect(page).toHaveURL(new RegExp(
      `/room-detail\\.html\\?.*id=${selection.roomId}(?:&|$)`
    ));
    await expect(page.locator('#room-detail-title')).toBeVisible();
    await expect(page.getByLabel('Ngày nhận phòng')).toHaveValue(selection.checkIn);
    await expect(page.getByLabel('Ngày trả phòng')).toHaveValue(selection.checkOut);
    await expect(page.getByLabel('Số lượng khách')).toHaveValue('1');

    await page.getByRole('button', { name: 'Đặt phòng ngay' }).click();
    await expect(page).toHaveURL(/\/booking\.html$/);
    await expect(page.getByLabel('Địa chỉ email *')).toHaveValue(credentials.email);
    await expect(page.locator('#booking-cart-summary')).toContainText(selection.roomLabel.split(' — ')[0]);

    await page.getByLabel('Họ và tên khách hàng *').fill(credentials.guestName);
    await page.getByLabel('Số điện thoại liên hệ *').fill(credentials.guestPhone);

    await page.getByRole('button', { name: 'Xác nhận đặt phòng' }).click();
    await expect(page).toHaveURL(
      /\/bookingsuccess\.html\?id=[0-9a-f-]+$/,
      { timeout: 30_000 }
    );
    booking.id = new URL(page.url()).searchParams.get('id');
    expect(booking.id).toMatch(UUID_PATTERN);

    await expect(page.locator('#success-booking-code')).not.toHaveText('');
    booking.code = (await page.locator('#success-booking-code').textContent()).trim();
    expect(booking.code).toBeTruthy();
    await expect(page.locator('#success-booking-code')).toHaveText(booking.code);
    await expect(page.locator('#success-booking-details')).toContainText(displayDate(selection.checkIn));
    await expect(page.locator('#success-booking-details')).toContainText(displayDate(selection.checkOut));

    await page.getByRole('link', { name: 'Xem lịch sử đặt phòng' }).click();
    await expect(page).toHaveURL(/\/booking-history\.html$/);

    const bookingRow = bookingRowByCode(page, booking.code);
    await expect(bookingRow).toHaveCount(1);
    await expect(bookingRow).toContainText(selection.roomLabel.split(' — ')[0]);
    await expect(bookingRow).toContainText(displayDate(selection.checkIn));
    await expect(bookingRow).toContainText(displayDate(selection.checkOut));

    await acceptCancellation(page, bookingRow);
    await expect(page.locator('#history-success')).toHaveText('Đã hủy booking thành công.');
    await expect(bookingRowByCode(page, booking.code)).toContainText('Đã hủy');
    booking.cancelled = true;

    await page.goto(
      `/search.html?check_in=${selection.checkIn}&check_out=${selection.checkOut}&guests=1`
    );
    expect(await waitForSearchOutcome(page)).toBe('results');

    const matchingRoom = page.locator(
      `#catalog-room-list a[href*="room-detail.html?id=${selection.roomId}&"]`
    );
    await expect(matchingRoom).toHaveCount(1);
    await expect(matchingRoom).toBeVisible();
  });
});

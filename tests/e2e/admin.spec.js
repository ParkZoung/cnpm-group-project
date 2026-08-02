const { test, expect } = require('@playwright/test');

const REQUIRED_ENV = [
  'GOSTAY_E2E_EMAIL',
  'GOSTAY_E2E_PASSWORD',
  'GOSTAY_E2E_ADMIN_EMAIL',
  'GOSTAY_E2E_ADMIN_PASSWORD',
  'GOSTAY_E2E_ADMIN_ROOM_ID',
  'GOSTAY_SECURITY_API_URL'
];
const ROOM_MARKER = 'Admin E2E <b>Room Test</b>';
const BOOKING_MARKER = 'Admin E2E <b>Booking Test</b>';
const MUTABLE_ROOM_FIELDS = [
  'branch_id',
  'room_type_id',
  'room_number',
  'name',
  'price_per_night',
  'description',
  'status',
  'created_at'
];

const state = {
  booking: null,
  roomSnapshot: null,
  admin: null,
  customer: null
};

function environment() {
  const missing = REQUIRED_ENV.filter(name => !String(process.env[name] || '').trim());
  if (missing.length) {
    throw new Error(`Missing required Admin E2E environment variables: ${missing.join(', ')}`);
  }

  const roomId = Number(process.env.GOSTAY_E2E_ADMIN_ROOM_ID);
  if (!Number.isSafeInteger(roomId) || roomId < 1) {
    throw new Error('GOSTAY_E2E_ADMIN_ROOM_ID must be a positive integer.');
  }

  return {
    apiUrl: process.env.GOSTAY_SECURITY_API_URL.trim().replace(/\/$/, ''),
    roomId,
    admin: {
      email: process.env.GOSTAY_E2E_ADMIN_EMAIL.trim(),
      password: process.env.GOSTAY_E2E_ADMIN_PASSWORD
    },
    customer: {
      email: process.env.GOSTAY_E2E_EMAIL.trim(),
      password: process.env.GOSTAY_E2E_PASSWORD
    }
  };
}

const config = environment();

async function api(path, body, token) {
  const response = await fetch(`${config.apiUrl}${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {})
    },
    body: JSON.stringify(body)
  });
  const payload = await response.json();
  return { ok: response.ok, ...payload };
}

async function apiLogin(credentials) {
  const result = await api('/auth/login', credentials);
  if (!result.ok || !result.data?.session?.access_token) {
    throw new Error('Admin E2E API login failed.');
  }
  return {
    id: result.data.user.id,
    token: result.data.session.access_token
  };
}

async function query(table, token, filters = []) {
  return api('/query', {
    table,
    operation: 'select',
    columns: '*',
    filters,
    orders: []
  }, token);
}

async function update(table, values, token, filters) {
  return api('/query', {
    table,
    operation: 'update',
    columns: '*',
    returning: true,
    values,
    filters,
    orders: []
  }, token);
}

function rpc(name, args, token) {
  return api('/rpc', { name, args }, token);
}

async function loginThroughUi(page, credentials) {
  await page.goto('/login.html');
  await page.locator('#login-email').fill(credentials.email);
  await page.locator('#login-password').fill(credentials.password);
  await page.locator('#login-submit').click();
}

function roomRow(page) {
  return page.locator(`#room-table-body tr[data-id="${config.roomId}"]`);
}

async function openAdminRooms(page) {
  await loginThroughUi(page, config.admin);
  await expect(page).toHaveURL(/\/admin-dashboard\.html$/);
  await page.goto('/admin-products.html');
  await expect(roomRow(page)).toBeVisible({ timeout: 20_000 });
}

function dateFromToday(days) {
  const date = new Date();
  date.setUTCHours(12, 0, 0, 0);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

async function findAvailableRoom() {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const checkIn = dateFromToday(120 + attempt * 7);
    const checkOut = dateFromToday(122 + attempt * 7);
    const result = await rpc('search_available_rooms', {
      p_check_in_date: checkIn,
      p_check_out_date: checkOut,
      p_guests: 1,
      p_branch_id: null,
      p_room_type_id: null,
      p_min_price: null,
      p_max_price: null
    });
    if (result.ok && result.data?.length) {
      return { roomId: result.data[0].room_id, checkIn, checkOut };
    }
  }
  throw new Error('No available room was found for the Admin E2E booking.');
}

async function createTestBooking() {
  const slot = await findAvailableRoom();
  const result = await rpc('create_booking', {
    p_room_id: slot.roomId,
    p_check_in_date: slot.checkIn,
    p_check_out_date: slot.checkOut,
    p_number_of_guests: 1,
    p_guest_name: BOOKING_MARKER,
    p_guest_email: 'admin-e2e@example.invalid',
    p_guest_phone: '0000000000',
    p_special_request: `admin-e2e-${Date.now()}`
  }, state.customer.token);

  if (!result.ok || !result.data?.[0]?.booking_id) {
    throw new Error('Could not create the Admin E2E booking.');
  }
  state.booking = {
    id: result.data[0].booking_id,
    code: result.data[0].booking_code
  };
}

async function bookingStatus() {
  if (!state.booking) return null;
  const result = await query('bookings', state.admin.token, [
    { operator: 'eq', column: 'id', value: state.booking.id }
  ]);
  if (!result.ok || result.data?.length !== 1) return null;
  return result.data[0].booking_status;
}

test.beforeAll(async () => {
  [state.admin, state.customer] = await Promise.all([
    apiLogin(config.admin),
    apiLogin(config.customer)
  ]);

  const roomResult = await query('rooms', state.admin.token, [
    { operator: 'eq', column: 'id', value: config.roomId }
  ]);
  if (!roomResult.ok || roomResult.data?.length !== 1) {
    throw new Error('GOSTAY_E2E_ADMIN_ROOM_ID does not identify an accessible demo room.');
  }
  state.roomSnapshot = roomResult.data[0];
  if (state.roomSnapshot.status !== 'available') {
    throw new Error('The dedicated Admin E2E room must start with status available.');
  }
});

test.afterAll(async () => {
  const cleanupErrors = [];

  if (state.booking && state.admin) {
    const currentStatus = await bookingStatus();
    if (currentStatus === 'pending' || currentStatus === 'confirmed') {
      const cancelResult = await rpc('admin_update_booking_status', {
        p_booking_id: state.booking.id,
        p_new_status: 'cancelled'
      }, state.admin.token);
      if (!cancelResult.ok) cleanupErrors.push('booking cancellation');
    } else if (currentStatus !== 'cancelled') {
      cleanupErrors.push('booking status verification');
    }
  }

  if (state.roomSnapshot && state.admin) {
    const restored = Object.fromEntries(
      MUTABLE_ROOM_FIELDS.map(field => [field, state.roomSnapshot[field]])
    );
    const restoreResult = await update('rooms', restored, state.admin.token, [
      { operator: 'eq', column: 'id', value: config.roomId }
    ]);
    if (!restoreResult.ok) {
      cleanupErrors.push('room restoration');
    } else {
      const verification = await query('rooms', state.admin.token, [
        { operator: 'eq', column: 'id', value: config.roomId }
      ]);
      const restoredRoom = verification.data?.[0];
      const differs = MUTABLE_ROOM_FIELDS.some(
        field => restoredRoom?.[field] !== state.roomSnapshot[field]
      );
      if (!verification.ok || differs) cleanupErrors.push('room restoration verification');
    }
  }

  if (cleanupErrors.length) {
    throw new Error(`Admin E2E cleanup failed: ${cleanupErrors.join(', ')}`);
  }
});

test('1. admin logs in successfully', async ({ page }) => {
  await loginThroughUi(page, config.admin);
  await expect(page).toHaveURL(/\/admin-dashboard\.html$/);
  await expect(page.locator('#adminUserName')).toContainText('Admin');
});

test('2. customer is blocked from Admin pages', async ({ page }) => {
  await loginThroughUi(page, config.customer);
  await expect(page).toHaveURL(/\/index\.html$/);
  await page.goto('/admin-dashboard.html');
  await expect(page).toHaveURL(/\/login\.html$/);
  await expect(page.locator('#totalRoomsValue')).toHaveCount(0);
});

test('3. Admin Dashboard loads live data', async ({ page }) => {
  await loginThroughUi(page, config.admin);
  await expect(page).toHaveURL(/\/admin-dashboard\.html$/);

  const metricIds = [
    'totalRoomsValue',
    'availableRoomsValue',
    'bookingsTodayValue',
    'totalCustomersValue',
    'revenueValue'
  ];
  for (const id of metricIds) {
    await expect(page.locator(`#${id}`)).toHaveAttribute('aria-busy', 'false');
    await expect(page.locator(`#${id}`)).not.toHaveText('—');
  }
  await expect(page.locator('#dashboardFeedback')).toBeHidden();
  await expect.poll(() => page.locator('#recentBookingsTableBody tr').count()).toBeGreaterThan(0);
});

test('4. room list displays the dedicated test room', async ({ page }) => {
  await openAdminRooms(page);
  await expect(roomRow(page).locator('td')).toHaveCount(7);
  await expect(roomRow(page)).toContainText(state.roomSnapshot.room_number);
});

test('5 and 8. admin edits the test room and XSS-safe action buttons still work', async ({ page }) => {
  await openAdminRooms(page);
  const row = roomRow(page);

  page.once('dialog', async dialog => {
    expect(dialog.message()).toContain(state.roomSnapshot.room_number);
    await dialog.dismiss();
  });
  await row.locator('[data-action="view"]').click();

  await row.locator('[data-action="edit"]').click();
  await expect(page.locator('#room-id')).toHaveValue(String(config.roomId));
  await page.locator('#room-name').fill(ROOM_MARKER);
  await page.locator('#room-submit-btn').click();
  await expect(roomRow(page)).toContainText(ROOM_MARKER);
  await expect(roomRow(page).locator('b')).toHaveCount(0);

  await roomRow(page).locator('[data-action="edit"]').click();
  await expect(page.locator('#room-name')).toHaveValue(ROOM_MARKER);
  await page.locator('#room-reset-btn').click();
});

test('6. admin deactivates and reactivates only the dedicated test room', async ({ page }) => {
  await openAdminRooms(page);

  page.once('dialog', dialog => dialog.accept());
  await roomRow(page).locator('[data-action="toggle-active"]').click();
  await expect(roomRow(page).locator('[data-action="toggle-active"]')).toContainText('Kích hoạt lại');

  page.once('dialog', dialog => dialog.accept());
  await roomRow(page).locator('[data-action="toggle-active"]').click();
  await expect(roomRow(page).locator('[data-action="toggle-active"]')).toContainText('Ngừng hoạt động');
});

test('7 and 8. admin changes a safe-rendered booking pending to confirmed to cancelled', async ({ page }) => {
  await createTestBooking();
  await loginThroughUi(page, config.admin);
  await expect(page).toHaveURL(/\/admin-dashboard\.html$/);
  await page.goto('/admin-bookings.html');
  await page.locator('#bookingSearch').fill(state.booking.code);

  const row = page.locator('#bookingsTableBody tr', { hasText: state.booking.code });
  await expect(row).toBeVisible({ timeout: 20_000 });
  await expect(row).toContainText(BOOKING_MARKER);
  await expect(row.locator('b')).toHaveCount(0);

  await row.locator('[data-action="detail"]').click();
  await expect(page.locator('#bookingDetailModal')).toBeVisible();
  await expect(page.locator('#bookingDetailContent')).toContainText(BOOKING_MARKER);
  await expect(page.locator('#bookingDetailContent b')).toHaveCount(0);
  await page
    .locator('#bookingDetailModal .booking-modal__header button[aria-label="Đóng"]')
    .click();

  await row.locator('[data-action="edit"]').click();
  await page.locator('#bookingStatus').selectOption('confirmed');
  await page.locator('#bookingSubmitButton').click();
  await expect(row).toContainText('Đã xác nhận');
  await expect.poll(bookingStatus).toBe('confirmed');

  page.once('dialog', dialog => dialog.accept());
  await row.locator('[data-action="cancel"]').click();
  await expect(row).toContainText('Đã hủy');
  await expect.poll(bookingStatus).toBe('cancelled');
});

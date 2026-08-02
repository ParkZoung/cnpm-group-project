const { after, before, describe, it } = require('node:test');
const assert = require('node:assert/strict');

const REQUIRED_ENV = [
  'GOSTAY_SECURITY_API_URL',
  'GOSTAY_E2E_EMAIL',
  'GOSTAY_E2E_PASSWORD',
  'GOSTAY_E2E_CUSTOMER_B_EMAIL',
  'GOSTAY_E2E_CUSTOMER_B_PASSWORD',
  'GOSTAY_E2E_ADMIN_EMAIL',
  'GOSTAY_E2E_ADMIN_PASSWORD'
];

function environment() {
  const missing = REQUIRED_ENV.filter((name) => !String(process.env[name] || '').trim());
  assert.deepEqual(missing, [], `Missing environment variables: ${missing.join(', ')}`);
  return {
    apiUrl: process.env.GOSTAY_SECURITY_API_URL.trim(),
    customerA: { email: process.env.GOSTAY_E2E_EMAIL, password: process.env.GOSTAY_E2E_PASSWORD },
    customerB: { email: process.env.GOSTAY_E2E_CUSTOMER_B_EMAIL, password: process.env.GOSTAY_E2E_CUSTOMER_B_PASSWORD },
    admin: { email: process.env.GOSTAY_E2E_ADMIN_EMAIL, password: process.env.GOSTAY_E2E_ADMIN_PASSWORD }
  };
}

let apiUrl;

async function request(path, body, token) {
  const response = await fetch(`${apiUrl}${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {})
    },
    body: JSON.stringify(body)
  });
  const payload = await response.json();
  return { ok: response.ok, status: response.status, ...payload };
}

async function login(credentials) {
  const result = await request('/auth/login', credentials);
  assert.equal(result.ok, true, 'Test account login failed');
  assert.ok(result.data?.session?.access_token, 'Login returned no session');
  return {
    id: result.data.user.id,
    token: result.data.session.access_token
  };
}

function query(table, token, filters = []) {
  return request('/query', {
    table,
    operation: 'select',
    columns: '*',
    filters,
    orders: []
  }, token);
}

function rpc(name, args, token) {
  return request('/rpc', { name, args }, token);
}

function dateFromToday(days) {
  const date = new Date();
  date.setUTCHours(12, 0, 0, 0);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

async function availableRoom(days) {
  const checkIn = dateFromToday(days);
  const checkOut = dateFromToday(days + 2);
  const result = await rpc('search_available_rooms', {
    p_check_in_date: checkIn,
    p_check_out_date: checkOut,
    p_guests: 1,
    p_branch_id: null,
    p_room_type_id: null,
    p_min_price: null,
    p_max_price: null
  });
  assert.equal(result.ok, true, 'Availability search failed');
  assert.ok(result.data?.length, `No room is available for ${checkIn} - ${checkOut}`);
  return { roomId: result.data[0].room_id, checkIn, checkOut };
}

describe('GoStay runtime RLS, authorization and booking concurrency', { concurrency: false }, () => {
  const state = { created: [], marker: `security-test-${Date.now()}` };

  before(async () => {
    const credentials = environment();
    apiUrl = credentials.apiUrl;
    [state.customerA, state.customerB, state.admin] = await Promise.all([
      login(credentials.customerA),
      login(credentials.customerB),
      login(credentials.admin)
    ]);
  });

  after(async () => {
    const failures = [];
    for (const booking of state.created) {
      const result = await rpc('admin_update_booking_status', {
        p_booking_id: booking.id,
        p_new_status: 'cancelled'
      }, state.admin?.token);

      if (!result.ok && !/transition is not allowed/i.test(result.error?.message || '')) {
        failures.push(booking.id);
      }
    }
    assert.deepEqual(failures, [], `Could not cancel test bookings: ${failures.join(', ')}`);
  });

  it('1. anonymous cannot read profiles', async () => {
    const result = await query('profiles');
    assert.equal(result.ok, false);
    assert.equal(result.data, null);
  });

  it('2. anonymous cannot read bookings', async () => {
    const result = await query('bookings');
    assert.equal(result.ok, false);
    assert.equal(result.data, null);
  });

  it('3. Customer A can read only their profile', async () => {
    const result = await query('profiles', state.customerA.token);
    assert.equal(result.ok, true);
    assert.deepEqual(result.data.map((profile) => profile.id), [state.customerA.id]);
  });

  it('4-5. Customer A reads only their bookings, not Customer B booking', async () => {
    const slotA = await availableRoom(70);
    const slotB = await availableRoom(80);
    const bookingA = await createBooking(state.customerA, slotA, `${state.marker}-a`);
    state.created.push(bookingA);
    const bookingB = await createBooking(state.customerB, slotB, `${state.marker}-b`);
    state.created.push(bookingB);

    const own = await query('bookings', state.customerA.token);
    assert.equal(own.ok, true);
    assert.ok(own.data.some((booking) => booking.id === bookingA.id));
    assert.ok(own.data.every((booking) => booking.user_id === state.customerA.id));

    const otherProfile = await query('profiles', state.customerA.token, [
      { operator: 'eq', column: 'id', value: state.customerB.id }
    ]);
    const otherBooking = await query('bookings', state.customerA.token, [
      { operator: 'eq', column: 'id', value: bookingB.id }
    ]);
    assert.equal(otherProfile.ok, true);
    assert.deepEqual(otherProfile.data, []);
    assert.equal(otherBooking.ok, true);
    assert.deepEqual(otherBooking.data, []);

    state.bookingA = bookingA;
  });

  it('6. customer cannot call an Admin RPC', async () => {
    const result = await rpc('admin_update_booking_status', {
      p_booking_id: state.bookingA.id,
      p_new_status: 'confirmed'
    }, state.customerA.token);
    assert.equal(result.ok, false);
    assert.match(result.error?.message || '', /administrator authorization is required/i);
  });

  it('7. admin performs a valid management operation', async () => {
    const result = await rpc('admin_update_booking_status', {
      p_booking_id: state.bookingA.id,
      p_new_status: 'confirmed'
    }, state.admin.token);
    assert.equal(result.ok, true);
    assert.equal(result.data?.[0]?.new_status, 'confirmed');
  });

  it('8. two concurrent create_booking requests yield exactly one success', async () => {
    const slot = await availableRoom(90);
    const args = bookingArgs(slot, `${state.marker}-race`);
    const results = await Promise.all([
      rpc('create_booking', args, state.customerA.token),
      rpc('create_booking', args, state.customerA.token)
    ]);
    const successes = results.filter((result) => result.ok);
    for (const result of successes) {
      if (result.data?.[0]?.booking_id) {
        state.created.push({ id: result.data[0].booking_id });
      }
    }
    assert.equal(successes.length, 1);
    assert.equal(results.filter((result) => !result.ok).length, 1);
    assert.ok(successes[0].data?.[0]?.booking_id);
  });
});

function bookingArgs(slot, marker) {
  return {
    p_room_id: slot.roomId,
    p_check_in_date: slot.checkIn,
    p_check_out_date: slot.checkOut,
    p_number_of_guests: 1,
    p_guest_name: 'GoStay Security Test',
    p_guest_email: 'security-test@example.invalid',
    p_guest_phone: '0000000000',
    p_special_request: marker
  };
}

async function createBooking(account, slot, marker) {
  const result = await rpc('create_booking', bookingArgs(slot, marker), account.token);
  assert.equal(result.ok, true, 'Test booking creation failed');
  assert.ok(result.data?.[0]?.booking_id, 'create_booking returned no booking ID');
  return { id: result.data[0].booking_id };
}

(function () {
  'use strict';

  const CART_KEY = 'gostayCart';
  const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

  document.addEventListener('DOMContentLoaded', function () {
    if (document.getElementById('booking-checkout-form')) {
      initializeCheckout();
    }

    if (document.getElementById('success-booking-loading')) {
      initializeBookingSuccess();
    }
  }, { once: true });

  async function initializeCheckout() {
    const elements = getCheckoutElements();

    if (!elements) {
      return;
    }

    if (!window.gostaySupabase) {
      showCheckoutError(elements, 'Không thể khởi tạo dịch vụ đặt phòng. Vui lòng tải lại trang.');
      return;
    }

    const cartResult = readValidCart();

    if (cartResult.error) {
      showCheckoutError(elements, cartResult.error + ' Vui lòng quay lại trang tìm phòng.');
      return;
    }

    try {
      const { data, error } = await window.gostaySupabase.auth.getSession();

      if (error) {
        throw error;
      }

      if (!data.session || !data.session.user) {
        showLoginRequired(elements);
        return;
      }

      if (!data.session.user.email) {
        showCheckoutError(elements, 'Tài khoản đăng nhập không có email hợp lệ để đặt phòng.');
        return;
      }

      elements.email.value = data.session.user.email;
      renderCartSummary(elements, cartResult.cart);
      elements.sessionStatus.hidden = true;
      elements.form.hidden = false;
      bindCheckoutSubmit(elements, cartResult.cart, data.session);
    } catch (error) {
      showCheckoutError(elements, friendlyBookingError(error, 'Không thể kiểm tra phiên đăng nhập.'));
    }
  }

  function bindCheckoutSubmit(elements, cart, session) {
    if (elements.form.dataset.bookingBound === 'true') {
      return;
    }

    elements.form.dataset.bookingBound = 'true';

    elements.form.addEventListener('submit', async function (event) {
      event.preventDefault();

      if (elements.submit.dataset.submitting === 'true') {
        return;
      }

      const guestName = elements.name.value.trim();
      const guestPhone = elements.phone.value.trim();
      const specialRequest = elements.specialRequest.value.trim();

      if (!guestName) {
        showCheckoutError(elements, 'Vui lòng nhập họ và tên khách lưu trú.', false);
        elements.name.focus();
        return;
      }

      if (guestPhone.replace(/\D/g, '').length < 9) {
        showCheckoutError(elements, 'Vui lòng nhập số điện thoại hợp lệ.', false);
        elements.phone.focus();
        return;
      }

      const payload = {
        p_room_id: cart.room_id,
        p_check_in_date: cart.check_in_date,
        p_check_out_date: cart.check_out_date,
        p_number_of_guests: cart.number_of_guests,
        p_guest_name: guestName,
        p_guest_email: session.user.email,
        p_guest_phone: guestPhone,
        p_special_request: specialRequest || null
      };

      setCheckoutSubmitting(elements, true);

      try {
        const { data, error } = await window.gostaySupabase.rpc('create_booking', payload);

        if (error) {
          throw error;
        }

        const booking = normalizeCreateBookingResponse(data);

        if (!booking) {
          throw new Error('create_booking did not return a valid booking row.');
        }

        elements.error.hidden = true;
        elements.success.textContent =
          'Đã tạo đặt phòng ' + booking.booking_code + '. Tổng chính thức: ' + formatMoney(booking.total_amount) + '.';
        elements.success.hidden = false;
        localStorage.removeItem(CART_KEY);
        window.location.assign('bookingsuccess.html?id=' + encodeURIComponent(booking.booking_id));
      } catch (error) {
        showCheckoutError(elements, friendlyBookingError(error, 'Không thể đặt phòng. Vui lòng thử lại.'), false);
        setCheckoutSubmitting(elements, false);
      }
    });
  }

  function normalizeCreateBookingResponse(data) {
    const row = Array.isArray(data) ? data[0] : data;

    if (!row
      || !UUID_PATTERN.test(String(row.booking_id || ''))
      || !row.booking_code
      || !Number.isFinite(Number(row.total_amount))) {
      return null;
    }

    return row;
  }

  async function initializeBookingSuccess() {
    const elements = getSuccessElements();

    if (!elements) {
      return;
    }

    const bookingId = new URLSearchParams(window.location.search).get('id');

    if (!bookingId || !UUID_PATTERN.test(bookingId)) {
      showSuccessError(elements, 'Không tìm thấy booking hoặc bạn không có quyền xem.');
      return;
    }

    if (!window.gostaySupabase) {
      showSuccessError(elements, 'Không thể khởi tạo dịch vụ dữ liệu booking. Vui lòng tải lại trang.');
      return;
    }

    try {
      const { data: sessionData, error: sessionError } =
        await window.gostaySupabase.auth.getSession();

      if (sessionError) {
        throw sessionError;
      }

      if (!sessionData.session) {
        showSuccessError(elements, 'Không tìm thấy booking hoặc bạn không có quyền xem.');
        return;
      }

      const { data, error } = await window.gostaySupabase
        .from('bookings')
        .select(`
          id,
          booking_code,
          room_id,
          check_in_date,
          check_out_date,
          number_of_guests,
          total_amount,
          booking_status,
          payment_status,
          room:rooms!bookings_room_id_fkey(
            id,
            room_number,
            branch:branches!rooms_branch_id_fkey(id, name),
            room_type:room_types!rooms_room_type_id_fkey(id, name)
          )
        `)
        .eq('id', bookingId)
        .maybeSingle();

      if (error) {
        throw error;
      }

      if (!data) {
        showSuccessError(elements, 'Không tìm thấy booking hoặc bạn không có quyền xem.');
        return;
      }

      renderBookingSuccess(elements, data);
    } catch (error) {
      const message = friendlyBookingError(
        error,
        'Không thể tải booking. Vui lòng thử lại sau.'
      );
      showSuccessError(elements, message);
    }
  }

  function readValidCart() {
    const storedCart = localStorage.getItem(CART_KEY);

    if (!storedCart) {
      return { error: 'Không tìm thấy phòng đã chọn.' };
    }

    try {
      const cart = JSON.parse(storedCart);

      if (Array.isArray(cart)) {
        return { error: 'Dữ liệu phòng đã chọn thuộc định dạng cũ.' };
      }

      const dateError = validateBookingDates(cart && cart.check_in_date, cart && cart.check_out_date);

      if (!cart
        || !Number.isSafeInteger(Number(cart.room_id))
        || Number(cart.room_id) <= 0
        || !Number.isSafeInteger(Number(cart.number_of_guests))
        || Number(cart.number_of_guests) <= 0
        || !cart.display
        || typeof cart.display !== 'object'
        || !cart.display.room_number
        || !cart.display.branch_name
        || !cart.display.room_type_name
        || !Number.isFinite(Number(cart.display.estimated_price_per_night))
        || Number(cart.display.estimated_price_per_night) <= 0) {
        return { error: 'Dữ liệu phòng đã chọn không hợp lệ.' };
      }

      if (dateError) {
        return { error: dateError };
      }

      return {
        cart: {
          room_id: Number(cart.room_id),
          check_in_date: cart.check_in_date,
          check_out_date: cart.check_out_date,
          number_of_guests: Number(cart.number_of_guests),
          display: cart.display
        }
      };
    } catch (error) {
      return { error: 'Dữ liệu phòng đã chọn bị lỗi.' };
    }
  }

  function validateBookingDates(checkIn, checkOut) {
    if (!isIsoDate(checkIn) || !isIsoDate(checkOut)) {
      return 'Ngày nhận hoặc trả phòng không hợp lệ.';
    }

    if (checkIn < getTodayDateString()) {
      return 'Ngày nhận phòng không được trước ngày hiện tại.';
    }

    return checkOut > checkIn ? '' : 'Ngày trả phòng phải sau ngày nhận phòng.';
  }

  function isIsoDate(value) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(String(value || ''))) {
      return false;
    }

    const date = new Date(value + 'T00:00:00Z');
    return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
  }

  function renderCartSummary(elements, cart) {
    const display = cart.display;
    const lines = [
      'Phòng ' + display.room_number,
      display.branch_name,
      display.room_type_name,
      'Nhận phòng: ' + formatDate(cart.check_in_date),
      'Trả phòng: ' + formatDate(cart.check_out_date),
      'Số khách: ' + cart.number_of_guests
    ];

    elements.summary.innerHTML = '';
    lines.forEach(function (text) {
      const line = document.createElement('div');
      line.className = 'mini-room-line';
      line.textContent = text;
      elements.summary.appendChild(line);
    });

    elements.estimatedPrice.textContent =
      formatMoney(display.estimated_price_per_night) + ' / đêm';
  }

  function renderBookingSuccess(elements, booking) {
    const room = booking.room;
    const roomDescription = room
      ? 'Phòng ' + room.room_number
        + (room.room_type ? ' — ' + room.room_type.name : '')
        + (room.branch ? ' tại ' + room.branch.name : '')
      : 'Phòng #' + booking.room_id;

    elements.code.textContent = booking.booking_code;
    elements.details.innerHTML = '';
    appendDetail(elements.details, 'Phòng', roomDescription);
    appendDetail(elements.details, 'Ngày nhận phòng', formatDate(booking.check_in_date));
    appendDetail(elements.details, 'Ngày trả phòng', formatDate(booking.check_out_date));
    appendDetail(elements.details, 'Số khách', booking.number_of_guests);
    appendDetail(elements.details, 'Trạng thái', bookingStatusLabel(booking.booking_status));
    appendDetail(elements.details, 'Thanh toán', paymentStatusLabel(booking.payment_status));
    appendDetail(elements.details, 'Tổng tiền chính thức', formatMoney(booking.total_amount));
    elements.loading.hidden = true;
    elements.error.hidden = true;
    elements.content.hidden = false;
  }

  function getCheckoutElements() {
    const elements = {
      form: document.getElementById('booking-checkout-form'),
      sessionStatus: document.getElementById('booking-session-status'),
      error: document.getElementById('booking-page-error'),
      success: document.getElementById('booking-page-success'),
      name: document.getElementById('full_name'),
      phone: document.getElementById('phone_number'),
      email: document.getElementById('email_address'),
      specialRequest: document.getElementById('special_requests'),
      summary: document.getElementById('booking-cart-summary'),
      estimatedPrice: document.getElementById('booking-estimated-price'),
      submit: document.getElementById('booking-submit')
    };

    return Object.values(elements).every(Boolean) ? elements : null;
  }

  function getSuccessElements() {
    const elements = {
      loading: document.getElementById('success-booking-loading'),
      error: document.getElementById('success-booking-error'),
      content: document.getElementById('success-booking-content'),
      code: document.getElementById('success-booking-code'),
      details: document.getElementById('success-booking-details')
    };

    return Object.values(elements).every(Boolean) ? elements : null;
  }

  function showCheckoutError(elements, message, hideForm) {
    elements.sessionStatus.hidden = true;
    elements.error.textContent = message;
    elements.error.hidden = false;

    if (hideForm !== false) {
      elements.form.hidden = true;
    }
  }

  function showLoginRequired(elements) {
    elements.sessionStatus.hidden = true;
    elements.form.hidden = true;
    elements.error.innerHTML = '';
    elements.error.classList.add('auth-required-card');

    const title = document.createElement('h2');
    title.textContent = 'Đăng nhập để đặt phòng';

    const text = document.createElement('p');
    text.textContent = 'Đăng nhập để tiếp tục xác nhận thông tin và hoàn tất đặt phòng.';

    const link = document.createElement('a');
    link.href = 'login.html';
    link.textContent = 'Đăng nhập';

    elements.error.appendChild(title);
    elements.error.appendChild(text);
    elements.error.appendChild(link);
    elements.error.hidden = false;
  }

  function showSuccessError(elements, message) {
    elements.loading.hidden = true;
    elements.content.hidden = true;
    elements.error.textContent = message;
    elements.error.hidden = false;
  }

  function setCheckoutSubmitting(elements, isSubmitting) {
    elements.submit.dataset.submitting = String(isSubmitting);
    elements.submit.disabled = isSubmitting;
    elements.submit.textContent = isSubmitting ? 'Đang tạo đặt phòng...' : 'Xác nhận đặt phòng';
  }

  function friendlyBookingError(error, fallback) {
    const message = String(error && error.message ? error.message : '').toLowerCase();

    if (message.includes('authentication is required')) {
      return 'Bạn cần đăng nhập trước khi đặt phòng.';
    }

    if (message.includes('authenticated profile is not allowed')) {
      return 'Tài khoản hiện tại không được phép đặt phòng.';
    }

    if (message.includes('booking date range is invalid')) {
      return 'Ngày nhận hoặc trả phòng không hợp lệ.';
    }

    if (message.includes('guest count exceeds')) {
      return 'Số khách vượt quá sức chứa của phòng.';
    }

    if (message.includes('guest count is invalid')) {
      return 'Số khách không hợp lệ.';
    }

    if (message.includes('no longer available for those dates')) {
      return 'Phòng đã được đặt trong khoảng ngày này. Vui lòng chọn ngày hoặc phòng khác.';
    }

    if (message.includes('selected room is not available')) {
      return 'Phòng hoặc chi nhánh không còn hoạt động để nhận đặt phòng.';
    }

    if (message.includes('required guest contact information is invalid')) {
      return 'Thông tin liên hệ của khách không hợp lệ.';
    }

    if (message.includes('failed to fetch') || message.includes('network')) {
      return 'Không thể kết nối hệ thống đặt phòng. Vui lòng kiểm tra mạng và thử lại.';
    }

    return fallback;
  }

  function appendDetail(container, label, value) {
    const paragraph = document.createElement('p');
    const strong = document.createElement('strong');
    strong.textContent = label + ': ';
    paragraph.appendChild(strong);
    paragraph.appendChild(document.createTextNode(String(value == null ? '—' : value)));
    container.appendChild(paragraph);
  }

  function bookingStatusLabel(status) {
    return {
      pending: 'Chờ xác nhận',
      confirmed: 'Đã xác nhận',
      checked_in: 'Đã nhận phòng',
      completed: 'Hoàn thành',
      cancelled: 'Đã hủy'
    }[status] || status || '—';
  }

  function paymentStatusLabel(status) {
    return {
      unpaid: 'Chưa thanh toán',
      pending: 'Đang xử lý',
      paid: 'Đã thanh toán',
      failed: 'Thất bại',
      refunded: 'Đã hoàn tiền'
    }[status] || status || '—';
  }

  function formatMoney(value) {
    return Number(value || 0).toLocaleString('vi-VN') + 'đ';
  }

  function formatDate(value) {
    const parts = String(value || '').split('-');
    return parts.length === 3 ? parts.reverse().join('/') : value || '—';
  }

  function getTodayDateString() {
    const now = new Date();
    const localDate = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
    return localDate.toISOString().slice(0, 10);
  }
}());

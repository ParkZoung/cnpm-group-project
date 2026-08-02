(function () {
  'use strict';

  const CANCELLABLE_STATUSES = new Set(['pending', 'confirmed']);
  const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

  document.addEventListener('DOMContentLoaded', initializeBookingHistory, { once: true });

  async function initializeBookingHistory() {
    const elements = getHistoryElements();

    if (!elements) {
      return;
    }

    bindHistoryActions(elements);

    if (!window.gostaySupabase) {
      showHistoryError(elements, 'Không thể khởi tạo dịch vụ đặt phòng. Vui lòng tải lại trang.');
      return;
    }

    try {
      const { data, error } = await window.gostaySupabase.auth.getSession();

      if (error) {
        throw error;
      }

      if (!data.session) {
        showLoginRequired(elements);
        return;
      }

      elements.sessionStatus.hidden = true;
      await loadBookingHistory(elements);
    } catch (error) {
      showHistoryError(elements, friendlyHistoryError(error, 'Không thể kiểm tra phiên đăng nhập.'));
    }
  }

  async function loadBookingHistory(elements) {
    setHistoryLoading(elements, true);
    elements.error.hidden = true;
    elements.empty.hidden = true;
    elements.tableContainer.hidden = true;

    try {
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
          created_at,
          room:rooms!bookings_room_id_fkey(
            id,
            room_number,
            branch:branches!rooms_branch_id_fkey(id, name),
            room_type:room_types!rooms_room_type_id_fkey(id, name)
          )
        `)
        .order('created_at', { ascending: false });

      if (error) {
        throw error;
      }

      const bookings = Array.isArray(data) ? data : [];
      renderBookingHistory(elements, bookings);
    } catch (error) {
      showHistoryError(elements, friendlyHistoryError(error, 'Không thể tải lịch sử đặt phòng.'));
    } finally {
      setHistoryLoading(elements, false);
    }
  }

  function renderBookingHistory(elements, bookings) {
    elements.body.innerHTML = '';

    if (!bookings.length) {
      elements.empty.hidden = false;
      elements.tableContainer.hidden = true;
      return;
    }

    bookings.forEach(function (booking) {
      elements.body.appendChild(createBookingRow(booking));
    });

    elements.empty.hidden = true;
    elements.tableContainer.hidden = false;
  }

  function createBookingRow(booking) {
    const row = document.createElement('tr');

    appendCell(row, booking.booking_code || booking.id);
    appendCell(row, roomLabel(booking));
    appendCell(
      row,
      formatDate(booking.check_in_date) + ' – ' + formatDate(booking.check_out_date)
    );
    appendCell(row, booking.number_of_guests);
    appendCell(row, formatMoney(booking.total_amount), 'table-price');
    appendCell(row, bookingStatusLabel(booking.booking_status));
    appendCell(row, paymentStatusLabel(booking.payment_status));

    const actionCell = document.createElement('td');

    if (CANCELLABLE_STATUSES.has(booking.booking_status)
      && UUID_PATTERN.test(String(booking.id || ''))) {
      const cancelButton = document.createElement('button');
      cancelButton.type = 'button';
      cancelButton.className = 'btn-remove-cart';
      cancelButton.dataset.action = 'cancel-booking';
      cancelButton.dataset.bookingId = booking.id;
      cancelButton.textContent = 'Hủy đặt phòng';
      actionCell.appendChild(cancelButton);
    } else {
      actionCell.textContent = '—';
    }

    row.appendChild(actionCell);
    return row;
  }

  function bindHistoryActions(elements) {
    if (elements.body.dataset.historyBound === 'true') {
      return;
    }

    elements.body.dataset.historyBound = 'true';

    elements.body.addEventListener('click', function (event) {
      const button = event.target.closest('[data-action="cancel-booking"]');

      if (!button || !elements.body.contains(button)) {
        return;
      }

      cancelBooking(elements, button);
    });
  }

  async function cancelBooking(elements, button) {
    const bookingId = button.dataset.bookingId;

    if (!UUID_PATTERN.test(String(bookingId || ''))) {
      showHistoryError(elements, 'Mã đặt phòng không hợp lệ.');
      return;
    }

    if (!window.confirm('Bạn có chắc muốn hủy đặt phòng này không?')) {
      return;
    }

    if (button.dataset.submitting === 'true') {
      return;
    }

    button.dataset.submitting = 'true';
    button.disabled = true;
    button.textContent = 'Đang hủy...';
    elements.error.hidden = true;
    elements.success.hidden = true;

    try {
      const { data, error } = await window.gostaySupabase.rpc('cancel_own_booking', {
        p_booking_id: bookingId
      });

      if (error) {
        throw error;
      }

      const result = normalizeCancelResponse(data);

      if (!result) {
        throw new Error('cancel_own_booking did not return a valid row.');
      }

      elements.success.textContent = 'Đã hủy đặt phòng thành công.';
      elements.success.hidden = false;
      await loadBookingHistory(elements);
    } catch (error) {
      showHistoryError(elements, friendlyHistoryError(error, 'Không thể hủy đặt phòng.'));
      button.dataset.submitting = 'false';
      button.disabled = false;
      button.textContent = 'Hủy đặt phòng';
    }
  }

  function normalizeCancelResponse(data) {
    const row = Array.isArray(data) ? data[0] : data;

    if (!row
      || !UUID_PATTERN.test(String(row.booking_id || ''))
      || row.booking_status !== 'cancelled'
      || !row.cancelled_at) {
      return null;
    }

    return row;
  }

  function getHistoryElements() {
    const elements = {
      sessionStatus: document.getElementById('history-session-status'),
      loading: document.getElementById('history-loading'),
      error: document.getElementById('history-error'),
      empty: document.getElementById('history-empty'),
      success: document.getElementById('history-success'),
      tableContainer: document.getElementById('history-table-container'),
      body: document.getElementById('booking-history-body')
    };

    return Object.values(elements).every(Boolean) ? elements : null;
  }

  function showLoginRequired(elements) {
    elements.sessionStatus.hidden = true;
    elements.loading.hidden = true;
    elements.tableContainer.hidden = true;
    elements.empty.hidden = true;
    elements.error.innerHTML = '';

    const message = document.createElement('p');
    message.textContent = 'Bạn cần đăng nhập để xem lịch sử đặt phòng.';

    const link = document.createElement('a');
    link.href = 'login.html';
    link.textContent = 'Đăng nhập';

    elements.error.appendChild(message);
    elements.error.appendChild(link);
    elements.error.hidden = false;
  }

  function showHistoryError(elements, message) {
    elements.sessionStatus.hidden = true;
    elements.loading.hidden = true;
    elements.error.textContent = message;
    elements.error.hidden = false;
  }

  function setHistoryLoading(elements, isLoading) {
    elements.loading.hidden = !isLoading;
    elements.tableContainer.setAttribute('aria-busy', String(isLoading));
  }

  function friendlyHistoryError(error, fallback) {
    const message = String(error && error.message ? error.message : '').toLowerCase();

    if (message.includes('authentication is required to cancel')) {
      return 'Bạn cần đăng nhập để hủy đặt phòng.';
    }

    if (message.includes('booking cannot be cancelled')) {
      return 'Đặt phòng không tồn tại, không thuộc tài khoản này hoặc trạng thái hiện tại không cho phép hủy.';
    }

    if (message.includes('failed to fetch') || message.includes('network')) {
      return 'Không thể kết nối hệ thống đặt phòng. Vui lòng kiểm tra mạng và thử lại.';
    }

    return fallback;
  }

  function roomLabel(booking) {
    const room = booking.room;

    if (!room) {
      return 'Phòng #' + booking.room_id;
    }

    return 'Phòng ' + room.room_number
      + (room.room_type ? ' — ' + room.room_type.name : '')
      + (room.branch ? ' tại ' + room.branch.name : '');
  }

  function appendCell(row, value, className) {
    const cell = document.createElement('td');
    cell.textContent = String(value == null ? '—' : value);

    if (className) {
      cell.className = className;
    }

    row.appendChild(cell);
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
}());

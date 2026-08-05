(function () {
  'use strict';

  const CANCELLABLE_STATUSES = new Set(['pending', 'confirmed']);
  const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  let currentBookings = [];

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
          paid_amount,
          payment_option,
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
      const checkinResult = await window.gostaySupabase.from('online_checkins')
        .select('id,booking_id,status,payment_option,requested_amount,rejection_reason,expires_at');
      if (checkinResult.error) throw checkinResult.error;
      const byBooking = new Map((checkinResult.data || []).map(item => [item.booking_id, item]));
      bookings.forEach(booking => { booking.online_checkin = byBooking.get(booking.id) || null; });
      currentBookings = bookings;
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
    appendCell(row, paymentStatusLabel(booking.payment_status) + ' ('
      + formatMoney(booking.paid_amount) + ' / ' + formatMoney(booking.total_amount) + ')');

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
    }
    if (booking.booking_status === 'confirmed' && UUID_PATTERN.test(String(booking.id || ''))) {
      const checkinButton = document.createElement('button');
      checkinButton.type = 'button';
      checkinButton.className = 'btn-remove-cart';
      checkinButton.dataset.action = 'online-checkin';
      checkinButton.dataset.bookingId = booking.id;
      const windowOpen = isOnlineCheckinOpen(booking);
      checkinButton.textContent = booking.online_checkin && booking.online_checkin.status === 'approved'
        ? 'QR check-in' : 'Check-in online';
      checkinButton.disabled = !windowOpen && !(booking.online_checkin && booking.online_checkin.status === 'approved');
      actionCell.appendChild(checkinButton);
    }
    if (!actionCell.childNodes.length) {
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
      const button = event.target.closest('[data-action]');

      if (!button || !elements.body.contains(button)) {
        return;
      }

      if (button.dataset.action === 'cancel-booking') cancelBooking(elements, button);
      if (button.dataset.action === 'online-checkin') openOnlineCheckin(elements, button.dataset.bookingId);
    });
    document.getElementById('close-online-checkin').addEventListener('click', closeOnlineCheckin);
    document.querySelector('[data-close-checkin]').addEventListener('click', closeOnlineCheckin);
  }

  async function openOnlineCheckin(elements, bookingId) {
    const booking = currentBookings.find(item => item.id === bookingId);
    if (!booking) return;
    const modal = document.getElementById('online-checkin-modal');
    const content = document.getElementById('online-checkin-content');
    modal.hidden = false;
    if (booking.online_checkin && booking.online_checkin.status === 'approved') {
      if (new Date(booking.online_checkin.expires_at) <= new Date()) {
        content.innerHTML = '<p>QR check-in đã hết hạn. Vui lòng liên hệ khách sạn.</p>';
        return;
      }
      content.innerHTML = '<p>Check-in online đã được duyệt. Đưa QR này cho staff khi đến khách sạn.</p><canvas id="guest-checkin-qr"></canvas><p>Mã dự phòng:</p><p class="checkin-code">' + booking.online_checkin.id + '</p><p>QR hết hạn: ' + new Date(booking.online_checkin.expires_at).toLocaleString('vi-VN') + '. Vui lòng mang giấy tờ tùy thân.</p>';
      if (window.QRCode) window.QRCode.toCanvas(document.getElementById('guest-checkin-qr'), 'gostay:checkin:' + booking.online_checkin.id, { width:280 });
      return;
    }
    if (booking.online_checkin && booking.online_checkin.status === 'payment_claimed') {
      content.innerHTML = '<p>Bạn đã báo chuyển khoản. Staff đang đối chiếu giao dịch trước khi cấp QR check-in.</p>';
      return;
    }
    content.innerHTML = (booking.online_checkin && booking.online_checkin.status === 'rejected' ? '<p>Giao dịch chưa được xác nhận: ' + escapeText(booking.online_checkin.rejection_reason || 'Vui lòng kiểm tra và thử lại.') + '</p>' : '') + '<p>Chọn số tiền thanh toán để bắt đầu check-in online.</p><div class="checkin-options"><button data-option="full" class="selected">Thanh toán toàn bộ</button>'
      + (Number(booking.number_of_nights || daysBetween(booking.check_in_date, booking.check_out_date)) > 1 ? '<button data-option="deposit">Cọc 1 đêm + thuế</button>' : '')
      + '</div><button id="start-online-checkin" class="checkin-action">Tạo VietQR</button><div id="vietqr-result"></div>';
    let option = 'full';
    content.querySelectorAll('[data-option]').forEach(button => button.addEventListener('click', () => {
      option = button.dataset.option; content.querySelectorAll('[data-option]').forEach(node => node.classList.toggle('selected', node === button));
    }));
    document.getElementById('start-online-checkin').addEventListener('click', async () => {
      try {
        const started = await window.GoStayBookingApi.startOnlineCheckin(booking.id, option);
        if (started.error) throw started.error;
        const qr = await window.GoStayApiClient.authenticatedRequest('/vietqr', { booking_id: booking.id });
        if (qr.error) throw qr.error;
        document.getElementById('vietqr-result').innerHTML = '<img class="vietqr-image" src="' + qr.data.qr_url + '" alt="VietQR thanh toán"><p>Chuyển <strong>' + formatMoney(qr.data.amount) + '</strong> với nội dung <strong>' + qr.data.booking_code + '</strong>.</p><button id="claim-payment" class="checkin-action">Tôi đã thanh toán</button>';
        document.getElementById('claim-payment').addEventListener('click', async () => {
          const claimed = await window.GoStayBookingApi.claimOnlinePayment(booking.id);
          if (claimed.error) { showHistoryError(elements, claimed.error.message); return; }
          content.innerHTML = '<p>Đã gửi thông báo. Staff sẽ đối chiếu tiền và cấp QR check-in.</p>';
          await loadBookingHistory(elements);
        });
      } catch (error) { document.getElementById('vietqr-result').textContent = error.message || 'Không thể tạo VietQR.'; }
    });
  }

  function closeOnlineCheckin() { document.getElementById('online-checkin-modal').hidden = true; }
  function daysBetween(start,end) { return Math.round((new Date(end)-new Date(start))/86400000); }
  function previousDate(value) { const d=new Date(value+'T00:00:00'); d.setDate(d.getDate()-1); return d.toISOString().slice(0,10); }
  function isOnlineCheckinOpen(booking) { const today=new Date(); const local=new Date(today.getTime()-today.getTimezoneOffset()*60000).toISOString().slice(0,10); return booking.booking_status === 'confirmed' && local<booking.check_out_date; }
  function escapeText(value) { const span=document.createElement('span'); span.textContent=String(value); return span.innerHTML; }

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
      const { data, error } = await window.GoStayBookingApi.cancel(bookingId);

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
    elements.error.classList.add('auth-required-card');

    const title = document.createElement('h2');
    title.textContent = 'Đăng nhập để xem lịch sử';

    const message = document.createElement('p');
    message.textContent = 'Đăng nhập để xem và quản lý các đặt phòng của bạn.';

    const link = document.createElement('a');
    link.href = 'login.html';
    link.textContent = 'Đăng nhập';

    elements.error.appendChild(title);
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
      return 'Thông tin phòng';
    }

    return (room.room_type ? room.room_type.name : 'Thông tin phòng')
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
      partially_paid: 'Đã đặt cọc',
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

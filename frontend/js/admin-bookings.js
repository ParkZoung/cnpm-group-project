/* Quản lý booking Admin: chỉ đọc bảng bookings và đổi trạng thái qua RPC. */
(function () {
  'use strict';

  const state = {
    rooms: [],
    bookings: [],
    search: '',
    status: 'all',
    sort: 'newest',
    editingBooking: null,
    isUpdating: false
  };

  const $ = id => document.getElementById(id);
  const db = () => {
    if (!window.gostaySupabase) throw new Error('Supabase chưa được khởi tạo.');
    return window.gostaySupabase;
  };
  const escapeHtml = value => String(value == null ? '' : value).replace(
    /[&<>"']/g,
    character => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#039;'
    })[character]
  );
  const money = value => Number(value || 0).toLocaleString('vi-VN') + 'đ';
  const date = value => value
    ? String(value).slice(0, 10).split('-').reverse().join('/')
    : '—';
  const findRoom = id => state.rooms.find(room => String(room.id) === String(id));
  const roomLabel = room => room
    ? 'Phòng ' + (room.room_number || room.id) + (room.name ? ' — ' + room.name : '')
    : 'Không xác định';
  const bookingCode = booking => booking.booking_code || '—';
  const bookingStatusLabel = value => ({
    pending: 'Chờ xác nhận',
    confirmed: 'Đã xác nhận',
    checked_in: 'Đã nhận phòng',
    completed: 'Hoàn thành',
    cancelled: 'Đã hủy'
  })[value] || value || '—';
  const paymentStatusLabel = value => ({
    unpaid: 'Chưa thanh toán',
    pending: 'Đang xử lý',
    paid: 'Đã thanh toán',
    failed: 'Thất bại',
    refunded: 'Đã hoàn tiền'
  })[value] || value || '—';
  const statusClass = value =>
    value === 'cancelled' || value === 'failed'
      ? 'status-danger'
      : value === 'completed' || value === 'paid' || value === 'refunded'
        ? 'status-success'
        : 'status-warning';

  function feedback(message, type) {
    const node = $('bookingFeedback');
    node.textContent = message || '';
    node.className = message
      ? 'booking-feedback is-visible ' + (type === 'success' ? 'is-success' : 'is-error')
      : 'booking-feedback';
  }

  async function loadRooms() {
    const response = await db()
      .from('rooms')
      .select('id, room_number, name')
      .order('room_number');

    if (response.error) throw response.error;
    state.rooms = response.data || [];
  }

  async function loadBookings() {
    const response = await db()
      .from('bookings')
      .select('*')
      .order('created_at', { ascending: false });

    if (response.error) throw response.error;
    state.bookings = response.data || [];
    renderBookings();
  }

  function bookingTransitions(status) {
    return {
      pending: ['confirmed', 'cancelled'],
      confirmed: ['checked_in', 'cancelled'],
      checked_in: ['completed']
    }[status] || [];
  }

  function paymentTransitions(bookingStatus, paymentStatus) {
    if (bookingStatus === 'cancelled') {
      return paymentStatus === 'paid' ? ['refunded'] : [];
    }

    return {
      unpaid: ['pending', 'paid'],
      pending: ['paid', 'failed'],
      failed: ['pending', 'paid']
    }[paymentStatus] || [];
  }

  function visibleBookings() {
    const query = state.search.trim().toLocaleLowerCase('vi-VN');

    return state.bookings.filter(booking => {
      const searchableText = [
        bookingCode(booking),
        booking.guest_name,
        booking.guest_email,
        roomLabel(findRoom(booking.room_id))
      ].join(' ').toLocaleLowerCase('vi-VN');

      return (!query || searchableText.includes(query)) &&
        (state.status === 'all' || booking.booking_status === state.status);
    }).sort((left, right) => {
      if (state.sort === 'oldest') {
        return String(left.created_at).localeCompare(String(right.created_at));
      }
      if (state.sort === 'checkin-asc') {
        return String(left.check_in_date).localeCompare(String(right.check_in_date));
      }
      return String(right.created_at).localeCompare(String(left.created_at));
    });
  }

  function renderBookings() {
    const body = $('bookingsTableBody');
    const rows = visibleBookings();

    if (!rows.length) {
      body.innerHTML = '<tr><td colspan="11">Không có đặt phòng phù hợp.</td></tr>';
      return;
    }

    body.innerHTML = rows.map(booking => {
      const canCancel = bookingTransitions(booking.booking_status).includes('cancelled');
      const canEdit = bookingTransitions(booking.booking_status).length > 0 ||
        paymentTransitions(booking.booking_status, booking.payment_status).length > 0;

      return '<tr>' +
        '<td><strong>' + escapeHtml(bookingCode(booking)) + '</strong></td>' +
        '<td>' + escapeHtml(booking.guest_name) + '<br><small>' +
          escapeHtml(booking.guest_email) + '</small></td>' +
        '<td>' + escapeHtml(roomLabel(findRoom(booking.room_id))) + '</td>' +
        '<td>' + escapeHtml(date(booking.check_in_date)) + '</td>' +
        '<td>' + escapeHtml(date(booking.check_out_date)) + '</td>' +
        '<td>' + escapeHtml(booking.number_of_guests) + '</td>' +
        '<td>' + escapeHtml(money(booking.total_amount)) + '</td>' +
        '<td>' + escapeHtml(booking.payment_method || '—') + '</td>' +
        '<td><span class="status-badge ' + statusClass(booking.payment_status) + '">' +
          escapeHtml(paymentStatusLabel(booking.payment_status)) + '</span></td>' +
        '<td><span class="status-badge ' + statusClass(booking.booking_status) + '">' +
          escapeHtml(bookingStatusLabel(booking.booking_status)) + '</span></td>' +
        '<td><div class="action-buttons">' +
          '<button type="button" class="btn-action edit" data-action="detail" data-id="' +
            escapeHtml(booking.id) + '">Xem</button>' +
          (canEdit
            ? '<button type="button" class="btn-action edit" data-action="edit" data-id="' +
                escapeHtml(booking.id) + '">Cập nhật trạng thái</button>'
            : '') +
          (canCancel
            ? '<button type="button" class="btn-action delete" data-action="cancel" data-id="' +
                escapeHtml(booking.id) + '">Hủy</button>'
            : '') +
        '</div></td></tr>';
    }).join('');
  }

  function openModal(id) {
    if (state.isUpdating) return;
    $(id).hidden = false;
  }

  function closeModal(id, force) {
    if (state.isUpdating && !force) return;
    $(id).hidden = true;
    if (id === 'bookingFormModal') state.editingBooking = null;
  }

  function setMutationLock(locked) {
    state.isUpdating = locked;
    document.querySelectorAll('[data-action], [data-close-modal]').forEach(button => {
      button.disabled = locked;
    });

    const booking = state.editingBooking;
    const hasTransition = booking && (
      bookingTransitions(booking.booking_status).length > 0 ||
      paymentTransitions(booking.booking_status, booking.payment_status).length > 0
    );
    $('bookingSubmitButton').disabled = locked || !hasTransition;
  }

  function setImmutableFields(booking) {
    $('bookingId').value = booking.id;
    $('bookingGuestName').value = booking.guest_name || '';
    $('bookingGuestEmail').value = booking.guest_email || '';
    $('bookingGuestPhone').value = booking.guest_phone || '';
    $('bookingRoomId').innerHTML = '<option value="' + escapeHtml(booking.room_id) + '">' +
      escapeHtml(roomLabel(findRoom(booking.room_id))) + '</option>';
    $('bookingRoomId').value = booking.room_id;
    $('bookingCheckIn').value = String(booking.check_in_date || '').slice(0, 10);
    $('bookingCheckOut').value = String(booking.check_out_date || '').slice(0, 10);
    $('bookingGuests').value = booking.number_of_guests || '';
    $('bookingTotal').value = booking.total_amount || 0;
    $('bookingPaymentMethod').innerHTML = '<option value="' +
      escapeHtml(booking.payment_method || '') + '">' +
      escapeHtml(booking.payment_method || '—') + '</option>';

    [
      'bookingGuestName',
      'bookingGuestEmail',
      'bookingGuestPhone',
      'bookingRoomId',
      'bookingCheckIn',
      'bookingCheckOut',
      'bookingGuests',
      'bookingTotal',
      'bookingPaymentMethod'
    ].forEach(id => {
      $(id).disabled = true;
    });
  }

  function populateTransitionSelect(select, transitions, labelFunction) {
    select.innerHTML = '<option value="">-- Không thay đổi --</option>' +
      transitions.map(status =>
        '<option value="' + escapeHtml(status) + '">' +
          escapeHtml(labelFunction(status)) + '</option>'
      ).join('');
    select.disabled = transitions.length === 0;
  }

  function editBooking(id) {
    if (state.isUpdating) return;
    const booking = state.bookings.find(item => String(item.id) === String(id));
    if (!booking) return;

    state.editingBooking = booking;
    setImmutableFields(booking);

    const allowedBookingStatuses = bookingTransitions(booking.booking_status);
    const allowedPaymentStatuses = paymentTransitions(
      booking.booking_status,
      booking.payment_status
    );

    populateTransitionSelect(
      $('bookingStatus'),
      allowedBookingStatuses,
      bookingStatusLabel
    );
    populateTransitionSelect(
      $('bookingPaymentStatus'),
      allowedPaymentStatuses,
      paymentStatusLabel
    );

    $('bookingFormTitle').textContent = 'Cập nhật trạng thái ' + bookingCode(booking);
    $('bookingSubmitButton').disabled =
      allowedBookingStatuses.length === 0 && allowedPaymentStatuses.length === 0;
    openModal('bookingFormModal');
  }

  function showDetail(id) {
    if (state.isUpdating) return;
    const booking = state.bookings.find(item => String(item.id) === String(id));
    if (!booking) return;

    $('bookingDetailContent').innerHTML =
      '<dl class="booking-detail-list">' +
      '<div><dt>Mã đặt phòng</dt><dd>' + escapeHtml(bookingCode(booking)) + '</dd></div>' +
      '<div><dt>Khách hàng</dt><dd>' + escapeHtml(booking.guest_name) + '</dd></div>' +
      '<div><dt>Phòng</dt><dd>' +
        escapeHtml(roomLabel(findRoom(booking.room_id))) + '</dd></div>' +
      '<div><dt>Ngày nhận</dt><dd>' +
        escapeHtml(date(booking.check_in_date)) + '</dd></div>' +
      '<div><dt>Ngày trả</dt><dd>' +
        escapeHtml(date(booking.check_out_date)) + '</dd></div>' +
      '<div><dt>Tổng tiền</dt><dd>' +
        escapeHtml(money(booking.total_amount)) + '</dd></div>' +
      '</dl>';
    openModal('bookingDetailModal');
  }

  function friendlyTransitionError(error) {
    const message = String(error && error.message ? error.message : '');
    const normalized = message.toLowerCase();

    if (normalized.includes('transition is not allowed')) {
      return 'Trạng thái đặt phòng đã thay đổi hoặc bước chuyển không hợp lệ.';
    }
    if (normalized.includes('booking was not found')) {
      return 'Không tìm thấy đặt phòng cần cập nhật.';
    }
    if (normalized.includes('authorization')) {
      return 'Phiên đăng nhập không còn quyền quản trị.';
    }
    return 'Không thể cập nhật trạng thái. Vui lòng thử lại.';
  }

  function logTransitionError(error) {
    console.error('Admin booking transition failed', {
      code: error?.code,
      message: error?.message,
      details: error?.details,
      hint: error?.hint
    });
  }

  async function updateBookingStatus(id, newStatus) {
    return db().rpc('admin_update_booking_status', {
      p_booking_id: id,
      p_new_status: newStatus
    });
  }

  async function updatePaymentStatus(id, newStatus) {
    return db().rpc('admin_update_payment_status', {
      p_booking_id: id,
      p_new_payment_status: newStatus
    });
  }

  async function reloadAfterRpcFailure(message) {
    try {
      await loadBookings();
      feedback(message, 'error');
    } catch (reloadError) {
      console.error('Admin booking reload failed after rejected transition', reloadError);
      feedback(message + ' Không thể tải lại dữ liệu; vui lòng bấm “Tải lại”.', 'error');
    }
  }

  async function reloadAfterMutationSuccess(successMessage) {
    try {
      await loadBookings();
      feedback(successMessage, 'success');
    } catch (reloadError) {
      console.error('Admin booking reload failed after successful transition', reloadError);
      feedback(
        'Đã cập nhật thành công, nhưng chưa thể tải lại danh sách. Vui lòng bấm Tải lại.',
        'error'
      );
    }
  }

  async function saveStatusTransition() {
    if (state.isUpdating) return;

    const booking = state.editingBooking;
    const newBookingStatus = $('bookingStatus').value;
    const newPaymentStatus = $('bookingPaymentStatus').value;

    if (!booking) return;
    if (!newBookingStatus && !newPaymentStatus) {
      feedback('Vui lòng chọn một trạng thái mới.', 'error');
      return;
    }
    if (newBookingStatus && newPaymentStatus) {
      feedback('Mỗi lần chỉ cập nhật một loại trạng thái để tránh dữ liệu dở dang.', 'error');
      return;
    }

    setMutationLock(true);

    try {
      try {
        const response = newBookingStatus
          ? await updateBookingStatus(booking.id, newBookingStatus)
          : await updatePaymentStatus(booking.id, newPaymentStatus);

        if (response.error) throw response.error;
      } catch (rpcError) {
        logTransitionError(rpcError);
        await reloadAfterRpcFailure(friendlyTransitionError(rpcError));
        closeModal('bookingFormModal', true);
        return;
      }

      closeModal('bookingFormModal', true);
      await reloadAfterMutationSuccess('Đã cập nhật trạng thái đặt phòng.');
    } finally {
      setMutationLock(false);
    }
  }

  async function cancelBooking(id) {
    if (state.isUpdating) return;
    if (!window.confirm('Bạn có muốn hủy đặt phòng này không?')) return;

    setMutationLock(true);

    try {
      try {
        const response = await updateBookingStatus(id, 'cancelled');
        if (response.error) throw response.error;
      } catch (rpcError) {
        logTransitionError(rpcError);
        await reloadAfterRpcFailure(friendlyTransitionError(rpcError));
        return;
      }

      await reloadAfterMutationSuccess('Đã hủy đặt phòng.');
    } finally {
      setMutationLock(false);
    }
  }

  function bindEvents() {
    $('reloadBookingsButton').addEventListener('click', initialize);
    $('bookingSearch').addEventListener('input', event => {
      state.search = event.target.value;
      renderBookings();
    });
    $('topbarBookingSearch').addEventListener('input', event => {
      $('bookingSearch').value = event.target.value;
      state.search = event.target.value;
      renderBookings();
    });
    $('bookingStatusFilter').addEventListener('change', event => {
      state.status = event.target.value;
      renderBookings();
    });
    $('bookingSort').addEventListener('change', event => {
      state.sort = event.target.value;
      renderBookings();
    });
    $('bookingForm').addEventListener('submit', event => {
      event.preventDefault();
      saveStatusTransition();
    });
    document.addEventListener('click', event => {
      if (state.isUpdating) return;

      const closeButton = event.target.closest('[data-close-modal]');
      if (closeButton) closeModal(closeButton.dataset.closeModal);

      const button = event.target.closest('[data-action]');
      if (!button) return;
      if (button.dataset.action === 'detail') showDetail(button.dataset.id);
      if (button.dataset.action === 'edit') editBooking(button.dataset.id);
      if (button.dataset.action === 'cancel') cancelBooking(button.dataset.id);
    });
  }

  async function initialize() {
    try {
      await loadRooms();
      await loadBookings();
      feedback('Đã tải dữ liệu đặt phòng.', 'success');
    } catch (error) {
      feedback('Không thể tải dữ liệu đặt phòng: ' + error.message, 'error');
    }
  }

  document.addEventListener('DOMContentLoaded', async () => {
    try {
      const adminContext = await window.gostayAdminReady;
      if (!adminContext) return;
      bindEvents();
      await initialize();
    } catch (_error) {
      return;
    }
  });
}());

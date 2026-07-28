/* Quản lý booking admin: dùng trực tiếp bảng bookings và rooms trên Supabase. */
(function () {
  'use strict';
  const state = { rooms: [], bookings: [], search: '', status: 'all', sort: 'newest' };
  const $ = id => document.getElementById(id);
  const db = () => { if (!window.gostaySupabase) throw new Error('Supabase chưa được khởi tạo.'); return window.gostaySupabase; };
  const escapeHtml = value => String(value == null ? '' : value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[c]));
  const money = value => Number(value || 0).toLocaleString('vi-VN') + 'đ';
  const date = value => value ? String(value).slice(0, 10).split('-').reverse().join('/') : '—';
  const findRoom = id => state.rooms.find(room => String(room.id) === String(id));
  const roomLabel = room => room ? 'Phòng ' + (room.room_number || room.id) + (room.name ? ' — ' + room.name : '') : 'Không xác định';
  const bookingCode = booking => booking.booking_code || ('GS-' + String(booking.id).slice(0, 8));
  const bookingStatus = value => ({ confirmed: 'Đã xác nhận', cancelled: 'Đã hủy', completed: 'Hoàn thành' }[value] || value || '—');
  const statusClass = value => value === 'cancelled' ? 'status-danger' : value === 'completed' || value === 'paid' ? 'status-success' : 'status-warning';

  function feedback(message, type) {
    const node = $('bookingFeedback');
    node.textContent = message || '';
    node.className = message ? 'booking-feedback is-visible ' + (type === 'success' ? 'is-success' : 'is-error') : 'booking-feedback';
  }

  async function loadRooms() {
    const response = await db().from('rooms').select('*').eq('status', 'available').order('room_number');
    if (response.error) throw response.error;
    state.rooms = response.data || [];
    $('bookingRoomId').innerHTML = '<option value="">Chọn phòng</option>' + state.rooms.map(room => '<option value="' + escapeHtml(room.id) + '">' + escapeHtml(roomLabel(room)) + '</option>').join('');
  }

  async function loadBookings() {
    const response = await db().from('bookings').select('*').order('created_at', { ascending: false });
    if (response.error) throw response.error;
    state.bookings = response.data || [];
    renderBookings();
  }

  function visibleBookings() {
    const query = state.search.trim().toLocaleLowerCase('vi-VN');
    return state.bookings.filter(booking => {
      const text = [bookingCode(booking), booking.guest_name, booking.guest_email, roomLabel(findRoom(booking.room_id))].join(' ').toLocaleLowerCase('vi-VN');
      return (!query || text.includes(query)) && (state.status === 'all' || booking.booking_status === state.status);
    }).sort((left, right) => {
      if (state.sort === 'oldest') return String(left.created_at).localeCompare(String(right.created_at));
      if (state.sort === 'checkin-asc') return String(left.check_in_date).localeCompare(String(right.check_in_date));
      return String(right.created_at).localeCompare(String(left.created_at));
    });
  }

  function renderBookings() {
    const body = $('bookingsTableBody');
    const rows = visibleBookings();
    if (!rows.length) { body.innerHTML = '<tr><td colspan="11">Không có booking phù hợp.</td></tr>'; return; }
    body.innerHTML = rows.map(booking => '<tr>' +
      '<td><strong>' + escapeHtml(bookingCode(booking)) + '</strong></td>' +
      '<td>' + escapeHtml(booking.guest_name) + '<br><small>' + escapeHtml(booking.guest_email) + '</small></td>' +
      '<td>' + escapeHtml(roomLabel(findRoom(booking.room_id))) + '</td>' +
      '<td>' + escapeHtml(date(booking.check_in_date)) + '</td>' +
      '<td>' + escapeHtml(date(booking.check_out_date)) + '</td>' +
      '<td>' + escapeHtml(booking.number_of_guests) + '</td>' +
      '<td>' + escapeHtml(money(booking.total_amount)) + '</td>' +
      '<td>' + escapeHtml(booking.payment_method || '—') + '</td>' +
      '<td><span class="status-badge ' + statusClass(booking.payment_status) + '">' + escapeHtml(booking.payment_status === 'paid' ? 'Đã thanh toán' : 'Chưa thanh toán') + '</span></td>' +
      '<td><span class="status-badge ' + statusClass(booking.booking_status) + '">' + escapeHtml(bookingStatus(booking.booking_status)) + '</span></td>' +
      '<td><div class="action-buttons"><button type="button" class="btn-action edit" data-action="detail" data-id="' + escapeHtml(booking.id) + '">Xem</button><button type="button" class="btn-action edit" data-action="edit" data-id="' + escapeHtml(booking.id) + '">Sửa</button><button type="button" class="btn-action delete" data-action="cancel" data-id="' + escapeHtml(booking.id) + '">Hủy</button></div></td>' +
      '</tr>').join('');
  }

  function openModal(id) { $(id).hidden = false; }
  function closeModal(id) { $(id).hidden = true; }

  function resetForm() {
    $('bookingForm').reset();
    $('bookingId').value = '';
    $('bookingGuests').value = '1';
    $('bookingTotal').value = '0';
    $('bookingPaymentMethod').value = 'pay_at_hotel';
    $('bookingPaymentStatus').value = 'unpaid';
    $('bookingStatus').value = 'confirmed';
    $('bookingFormTitle').textContent = 'Tạo booking';
    $('bookingSubmitButton').textContent = 'Tạo booking';
  }

  function recalculateTotal() {
    const room = findRoom($('bookingRoomId').value);
    const days = (Date.parse($('bookingCheckOut').value) - Date.parse($('bookingCheckIn').value)) / 86400000;
    if (room && days > 0) $('bookingTotal').value = String(Number(room.price_per_night || 0) * days);
  }

  function formData() {
    return { id: $('bookingId').value, guest_name: $('bookingGuestName').value.trim(), guest_email: $('bookingGuestEmail').value.trim(), guest_phone: $('bookingGuestPhone').value.trim(), room_id: $('bookingRoomId').value, check_in: $('bookingCheckIn').value, check_out: $('bookingCheckOut').value, guests: Number($('bookingGuests').value), total: Number($('bookingTotal').value), payment_method: $('bookingPaymentMethod').value, payment_status: $('bookingPaymentStatus').value, booking_status: $('bookingStatus').value };
  }

  async function saveBooking() {
    const value = formData();
    const room = findRoom(value.room_id);
    const numberOfNights = (Date.parse(value.check_out) - Date.parse(value.check_in)) / 86400000;
    if (!value.guest_name || !value.guest_email.includes('@') || !value.guest_phone || !room || !value.check_in || numberOfNights < 1 || value.guests < 1 || value.total < 0) {
      feedback('Vui lòng nhập đầy đủ thông tin booking hợp lệ.', 'error');
      return;
    }
    const payload = { guest_name: value.guest_name, guest_email: value.guest_email, guest_phone: value.guest_phone, room_id: Number(value.room_id), check_in_date: value.check_in, check_out_date: value.check_out, number_of_nights: numberOfNights, number_of_guests: value.guests, price_per_night: Number(room.price_per_night || 0), subtotal: value.total, tax_rate: 0, tax_amount: 0, discount_amount: 0, total_amount: value.total, payment_method: value.payment_method, payment_status: value.payment_status, booking_status: value.booking_status };
    if (!value.id) payload.booking_code = 'GS' + new Date().toISOString().slice(0, 10).replaceAll('-', '') + String(Date.now()).slice(-4);
    const response = value.id ? await db().from('bookings').update(payload).eq('id', value.id).select().single() : await db().from('bookings').insert(payload).select().single();
    if (response.error) { feedback('Không thể lưu booking: ' + response.error.message, 'error'); return; }
    closeModal('bookingFormModal');
    await loadBookings();
    feedback('Đã lưu booking trên Supabase.', 'success');
  }

  function editBooking(id) {
    const booking = state.bookings.find(item => String(item.id) === String(id));
    if (!booking) return;
    resetForm();
    $('bookingId').value = booking.id;
    $('bookingGuestName').value = booking.guest_name || '';
    $('bookingGuestEmail').value = booking.guest_email || '';
    $('bookingGuestPhone').value = booking.guest_phone || '';
    $('bookingRoomId').value = booking.room_id;
    $('bookingCheckIn').value = String(booking.check_in_date).slice(0, 10);
    $('bookingCheckOut').value = String(booking.check_out_date).slice(0, 10);
    $('bookingGuests').value = booking.number_of_guests || 1;
    $('bookingTotal').value = booking.total_amount || 0;
    $('bookingPaymentMethod').value = booking.payment_method || 'pay_at_hotel';
    $('bookingPaymentStatus').value = booking.payment_status || 'unpaid';
    $('bookingStatus').value = booking.booking_status || 'confirmed';
    $('bookingFormTitle').textContent = 'Sửa booking ' + bookingCode(booking);
    $('bookingSubmitButton').textContent = 'Lưu thay đổi';
    openModal('bookingFormModal');
  }

  function showDetail(id) {
    const booking = state.bookings.find(item => String(item.id) === String(id));
    if (!booking) return;
    $('bookingDetailContent').innerHTML = '<dl class="booking-detail-list"><div><dt>Mã booking</dt><dd>' + escapeHtml(bookingCode(booking)) + '</dd></div><div><dt>Khách hàng</dt><dd>' + escapeHtml(booking.guest_name) + '</dd></div><div><dt>Phòng</dt><dd>' + escapeHtml(roomLabel(findRoom(booking.room_id))) + '</dd></div><div><dt>Ngày nhận</dt><dd>' + escapeHtml(date(booking.check_in_date)) + '</dd></div><div><dt>Ngày trả</dt><dd>' + escapeHtml(date(booking.check_out_date)) + '</dd></div><div><dt>Tổng tiền</dt><dd>' + escapeHtml(money(booking.total_amount)) + '</dd></div></dl>';
    openModal('bookingDetailModal');
  }

  async function cancelBooking(id) {
    if (!confirm('Bạn có muốn hủy booking này không?')) return;
    const response = await db().from('bookings').update({ booking_status: 'cancelled', cancelled_at: new Date().toISOString() }).eq('id', id);
    if (response.error) { feedback('Không thể hủy booking: ' + response.error.message, 'error'); return; }
    await loadBookings();
    feedback('Đã hủy booking trên Supabase.', 'success');
  }

  function bindEvents() {
    $('createBookingButton').addEventListener('click', () => { resetForm(); openModal('bookingFormModal'); });
    $('reloadBookingsButton').addEventListener('click', initialize);
    $('bookingSearch').addEventListener('input', event => { state.search = event.target.value; renderBookings(); });
    $('topbarBookingSearch').addEventListener('input', event => { $('bookingSearch').value = event.target.value; state.search = event.target.value; renderBookings(); });
    $('bookingStatusFilter').addEventListener('change', event => { state.status = event.target.value; renderBookings(); });
    $('bookingSort').addEventListener('change', event => { state.sort = event.target.value; renderBookings(); });
    ['bookingRoomId', 'bookingCheckIn', 'bookingCheckOut'].forEach(id => $(id).addEventListener('change', recalculateTotal));
    $('bookingForm').addEventListener('submit', event => { event.preventDefault(); saveBooking(); });
    document.addEventListener('click', event => { const close = event.target.closest('[data-close-modal]'); if (close) closeModal(close.dataset.closeModal); const button = event.target.closest('[data-action]'); if (!button) return; if (button.dataset.action === 'detail') showDetail(button.dataset.id); if (button.dataset.action === 'edit') editBooking(button.dataset.id); if (button.dataset.action === 'cancel') cancelBooking(button.dataset.id); });
  }

  async function initialize() {
    try { await Promise.all([loadRooms(), loadBookings()]); feedback('Đã tải dữ liệu thực từ Supabase.', 'success'); }
    catch (error) { feedback('Không thể tải Supabase: ' + error.message, 'error'); }
  }

  document.addEventListener('DOMContentLoaded', async () => {
    const adminContext = await window.gostayAdminReady;
    if (!adminContext) return;
    bindEvents();
    initialize();
  });
}());

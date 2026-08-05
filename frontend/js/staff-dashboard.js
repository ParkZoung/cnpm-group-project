(function () {
  'use strict';
  const WORKING_BRANCH_KEY = 'gostay_staff_working_branch';
  const state = { bookings: [], branches: [], activeBranch: null, filter: 'action_required', search: '' };
  const $ = id => document.getElementById(id);
  const money = value => Number(value || 0).toLocaleString('vi-VN') + 'đ';
  const date = value => value ? String(value).slice(0, 10).split('-').reverse().join('/') : '—';
  const escapeHtml = value => String(value == null ? '' : value).replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  })[c]);
  const statusLabel = value => ({ pending:'Chờ xác nhận', confirmed:'Đã xác nhận', checked_in:'Đang lưu trú', completed:'Đã check-out', cancelled:'Đã hủy' })[value] || value;
  const paymentLabel = value => ({ unpaid:'Chưa thanh toán', pending:'Đang xử lý', partially_paid:'Đã cọc', paid:'Đã thanh toán', failed:'Thất bại', refunded:'Đã hoàn tiền' })[value] || value;

  document.addEventListener('DOMContentLoaded', async function () {
    const context = await window.gostayStaffReady;
    if (!context) return;
    $('staffName').textContent = context.profile.full_name || 'Staff';
    bind();
    await loadBranches();
    await restoreWorkingBranch();
  }, { once:true });

  function bind() {
    $('staffSearch').addEventListener('input', event => { state.search = event.target.value; render(); });
    $('staffFilter').addEventListener('change', event => { state.filter = event.target.value; render(); });
    $('reloadStaffBookings').addEventListener('click', load);
    $('startBranchSession').addEventListener('click', selectWorkingBranch);
    $('changeBranch').addEventListener('click', showBranchGate);
    $('lookupCheckinToken').addEventListener('click', () => lookupToken($('manualCheckinToken').value));
    $('closeStaffDetail').addEventListener('click', () => { $('staffDetailModal').hidden = true; });
    $('staffDetailModal').addEventListener('click', event => {
      if (event.target === $('staffDetailModal')) $('staffDetailModal').hidden = true;
    });
    document.addEventListener('keydown', event => {
      if (event.key === 'Escape' && !$('staffDetailModal').hidden) $('staffDetailModal').hidden = true;
    });
    $('staffBookingsBody').addEventListener('click', async event => {
      const button = event.target.closest('[data-action]');
      if (!button || button.disabled) return;
      if (button.dataset.action === 'detail') {
        await showDetail(button.dataset.id);
        return;
      }
      button.disabled = true;
      const names = { confirm:'staff_confirm_booking', collect:'staff_collect_balance', checkout:'staff_check_out', refund:'staff_record_refund' };
      try {
        let result;
        if (button.dataset.action === 'approve-payment' || button.dataset.action === 'reject-payment') {
          result = await window.gostaySupabase.rpc('staff_review_online_payment', {
            p_booking_id: button.dataset.id,
            p_approve: button.dataset.action === 'approve-payment',
            p_rejection_reason: button.dataset.action === 'reject-payment' ? 'Không xác nhận được giao dịch' : null
          });
        } else {
          result = await window.gostaySupabase.rpc(names[button.dataset.action], { p_booking_id: button.dataset.id });
        }
        if (result.error) throw result.error;
        notify('Thao tác thành công.', true);
        await load();
      } catch (error) {
        notify(error.message || 'Không thể thực hiện thao tác.');
        button.disabled = false;
      }
    });
    $('staffLogout').addEventListener('click', async event => {
      event.preventDefault();
      window.sessionStorage.removeItem(WORKING_BRANCH_KEY);
      await window.gostaySupabase.auth.signOut();
      window.location.replace('login.html');
    });
  }

  async function loadBranches() {
    const result = await window.gostaySupabase.from('branches').select('id,name').eq('status','active').order('name');
    if (result.error) {
      $('branchGateNotice').textContent = result.error.message || 'Không thể tải danh sách chi nhánh.';
      $('branchGateNotice').className = 'notice error';
      return;
    }
    state.branches = result.data || [];
    $('workingBranch').innerHTML = '<option value="">Chọn chi nhánh</option>' + state.branches.map(branch =>
      `<option value="${branch.id}">${escapeHtml(branch.name)}</option>`).join('');
  }

  async function selectWorkingBranch() {
    const branchId = Number($('workingBranch').value);
    if (!Number.isSafeInteger(branchId)) {
      $('branchGateNotice').textContent = 'Vui lòng chọn chi nhánh.';
      $('branchGateNotice').className = 'notice error';
      return;
    }
    const button = $('startBranchSession');
    button.disabled = true;
    const result = await window.gostaySupabase.rpc('staff_select_working_branch', { p_branch_id: branchId });
    button.disabled = false;
    if (result.error) {
      $('branchGateNotice').textContent = result.error.message || 'Không thể chọn chi nhánh.';
      $('branchGateNotice').className = 'notice error';
      return;
    }
    state.activeBranch = state.branches.find(branch => Number(branch.id) === branchId) || null;
    window.sessionStorage.setItem(WORKING_BRANCH_KEY, String(branchId));
    $('branchName').textContent = state.activeBranch ? state.activeBranch.name : 'Chi nhánh đã chọn';
    $('branchGate').hidden = true;
    $('staffWorkspace').hidden = false;
    await load();
  }

  async function restoreWorkingBranch() {
    const savedBranchId = Number(window.sessionStorage.getItem(WORKING_BRANCH_KEY));
    if (!Number.isSafeInteger(savedBranchId) || !state.branches.some(branch => Number(branch.id) === savedBranchId)) {
      window.sessionStorage.removeItem(WORKING_BRANCH_KEY);
      return;
    }
    $('workingBranch').value = String(savedBranchId);
    await selectWorkingBranch();
  }

  function showBranchGate() {
    $('staffWorkspace').hidden = true;
    $('branchGate').hidden = false;
    $('branchGateNotice').className = 'notice';
    $('branchGateNotice').textContent = '';
  }

  async function load() {
    $('staffBookingsBody').innerHTML = '<tr><td colspan="9">Đang tải...</td></tr>';
    const result = await window.gostaySupabase.from('bookings').select(`
      id,booking_code,guest_name,guest_email,guest_phone,check_in_date,check_out_date,
      number_of_nights,total_amount,paid_amount,upfront_amount,payment_option,payment_status,
      booking_status,checked_in_at,checked_out_at,
      room:rooms!bookings_room_id_fkey(id,room_number,name,branch_id)
    `).order('check_in_date', { ascending:true });
    if (result.error) { notify(result.error.message); state.bookings=[]; }
    else {
      state.bookings = result.data || [];
      const checkins = await window.gostaySupabase.from('online_checkins')
        .select('id,booking_id,status,payment_option,requested_amount,rejection_reason,expires_at');
      if (checkins.error) { notify(checkins.error.message); }
      const map = new Map((checkins.data || []).map(item => [item.booking_id,item]));
      state.bookings.forEach(booking => { booking.online_checkin = map.get(booking.id) || null; });
    }
    render();
  }

  function visible() {
    const term = state.search.trim().toLocaleLowerCase('vi');
    return state.bookings.filter(b => {
      const text = [b.booking_code,b.guest_name,b.guest_phone,b.guest_email].join(' ').toLocaleLowerCase('vi');
      const needsAction = b.booking_status === 'pending' ||
        (b.online_checkin && b.online_checkin.status === 'payment_claimed') ||
        (['confirmed','checked_in'].includes(b.booking_status) && Number(b.paid_amount) < Number(b.total_amount));
      const category = state.filter === 'all' ||
        (state.filter === 'action_required' && needsAction) ||
        (state.filter === 'awaiting_arrival' && b.booking_status === 'confirmed') ||
        (state.filter === 'staying' && b.booking_status === 'checked_in') ||
        (state.filter === 'finished' && ['completed','cancelled'].includes(b.booking_status));
      return category && (!term || text.includes(term));
    });
  }

  function render() {
    const rows = visible();
    $('totalBookings').textContent = state.bookings.length;
    $('arrivalsToday').textContent = state.bookings.filter(b => b.check_in_date === new Date().toISOString().slice(0,10)).length;
    $('currentGuests').textContent = state.bookings.filter(b => b.booking_status === 'checked_in').length;
    if (!rows.length) { $('staffBookingsBody').innerHTML='<tr><td colspan="9">Không có booking phù hợp.</td></tr>'; return; }
    $('staffBookingsBody').innerHTML = rows.map(b => {
      const balance = Number(b.total_amount) - Number(b.paid_amount);
      const actions = [`<button data-action="detail" data-id="${b.id}">Chi tiết</button>`];
      if (b.booking_status === 'pending') actions.push(`<button data-action="confirm" data-id="${b.id}">Xác nhận phòng</button>`);
      if (b.online_checkin && b.online_checkin.status === 'payment_claimed') {
        actions.push(`<button data-action="approve-payment" data-id="${b.id}">Duyệt tiền</button>`);
        actions.push(`<button data-action="reject-payment" data-id="${b.id}">Từ chối</button>`);
      }
      if (['confirmed','checked_in'].includes(b.booking_status) && balance > 0) actions.push(`<button data-action="collect" data-id="${b.id}">Thu ${money(balance)}</button>`);
      if (b.booking_status === 'checked_in' && balance === 0) actions.push(`<button data-action="checkout" data-id="${b.id}">Check-out</button>`);
      if (b.booking_status === 'cancelled' && Number(b.paid_amount)>0 && b.payment_status!=='refunded') actions.push(`<button data-action="refund" data-id="${b.id}">Hoàn tiền</button>`);
      const roomName = roomDisplayName(b.room);
      return `<tr><td><strong>${escapeHtml(b.booking_code)}</strong></td><td>${escapeHtml(b.guest_name)}<small>${escapeHtml(b.guest_phone)}</small></td><td>${escapeHtml(roomName)}</td><td>${date(b.check_in_date)}</td><td>${date(b.check_out_date)}</td><td>${escapeHtml(statusLabel(b.booking_status))}</td><td>${escapeHtml(paymentLabel(b.payment_status))}<small>${money(b.paid_amount)} / ${money(b.total_amount)}</small></td><td>${money(balance)}</td><td class="staff-actions">${actions.join(' ') || '—'}</td></tr>`;
    }).join('');
  }

  function notify(message, success) {
    $('staffNotice').textContent=message; $('staffNotice').className=success?'notice success':'notice error';
  }

  async function showDetail(bookingId) {
    const booking = state.bookings.find(item => item.id === bookingId);
    if (!booking) return;
    const result = await window.gostaySupabase.from('payment_transactions')
      .select('id,transaction_type,amount,status,provider_reference,created_at')
      .eq('booking_id', bookingId).order('created_at', { ascending:false });
    if (result.error) { notify(result.error.message); return; }
    const labels = { online_payment:'Thanh toán online', staff_collection:'Thu tại quầy', refund:'Hoàn tiền' };
    const statuses = { succeeded:'Thành công', pending:'Đang xử lý', failed:'Thất bại' };
    const balance = Math.max(0, Number(booking.total_amount) - Number(booking.paid_amount));
    const transactions = (result.data || []).map(item => {
      const timestamp = new Date(item.created_at);
      const statusClass = ['succeeded','pending','failed'].includes(item.status) ? item.status : 'pending';
      return `<article class="transaction-row">
        <div class="transaction-type"><span class="transaction-mark" aria-hidden="true"></span><div><strong>${escapeHtml(labels[item.transaction_type] || item.transaction_type)}</strong><small>${escapeHtml(item.provider_reference || 'Giao dịch GoStay')}</small></div></div>
        <strong class="transaction-amount">${money(item.amount)}</strong>
        <div class="transaction-meta"><span class="transaction-status ${statusClass}">${escapeHtml(statuses[item.status] || item.status)}</span><time datetime="${escapeHtml(item.created_at)}">${timestamp.toLocaleDateString('vi-VN')}<small>${timestamp.toLocaleTimeString('vi-VN', { hour:'2-digit', minute:'2-digit' })}</small></time></div>
      </article>`;
    }).join('');
    $('staffDetailContent').innerHTML = `<section class="payment-booking-summary">
        <div class="payment-booking-id"><span>MÃ BOOKING</span><strong>${escapeHtml(booking.booking_code)}</strong><small>${escapeHtml(booking.guest_name)}</small></div>
        <div class="payment-total paid"><span>ĐÃ THANH TOÁN</span><strong>${money(booking.paid_amount)}</strong></div>
        <div class="payment-total balance"><span>CÒN LẠI</span><strong>${money(balance)}</strong></div>
      </section>
      <div class="transaction-list-heading"><span>LỊCH SỬ GIAO DỊCH</span><small>${result.data.length} giao dịch</small></div>
      <section class="transaction-list">${transactions || '<div class="transaction-empty"><span>₫</span><strong>Chưa có giao dịch</strong><small>Các khoản thanh toán sẽ xuất hiện tại đây.</small></div>'}</section>`;
    $('staffDetailModal').hidden = false;
    $('closeStaffDetail').focus();
  }

  function normalizeToken(value) {
    const raw = String(value || '').trim();
    const prefix = 'gostay:checkin:';
    return raw.toLowerCase().startsWith(prefix) ? raw.slice(prefix.length) : raw;
  }

  function roomDisplayName(room, fallbackId) {
    if (room && String(room.room_number || '').trim()) return 'Phòng ' + String(room.room_number).trim();
    if (room && String(room.name || '').trim()) return String(room.name).trim();
    return fallbackId ? 'Mã phòng nội bộ ' + fallbackId : '—';
  }

  function bangkokIsoDate() {
    const parts = new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Asia/Bangkok', year: 'numeric', month: '2-digit', day: '2-digit'
    }).formatToParts(new Date()).reduce((result, part) => {
      result[part.type] = part.value; return result;
    }, {});
    return parts.year + '-' + parts.month + '-' + parts.day;
  }

  async function lookupToken(value) {
    const token = normalizeToken(value);
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(token)) { $('scanResult').textContent='Mã QR không hợp lệ.'; return; }
    const result = await window.gostaySupabase.rpc('staff_lookup_checkin_token', { p_token:token });
    const row = Array.isArray(result.data) ? result.data[0] : result.data;
    if (result.error || !row) { $('scanResult').textContent='Không tìm thấy credential hợp lệ cho chi nhánh này.'; return; }
    const booking = state.bookings.find(item => item.id === row.booking_id);
    const roomName = roomDisplayName(booking && booking.room, row.room_id);
    const expiry = row.expires_at ? new Date(row.expires_at).toLocaleString('vi-VN') : 'Không xác định';
    const today = bangkokIsoDate();
    const beforeArrival = booking && today < booking.check_in_date;
    const afterDeparture = booking && today >= booking.check_out_date;
    const canConfirmArrival = Boolean(booking && !beforeArrival && !afterDeparture);
    const eligibilityNote = beforeArrival
      ? 'Có thể xác nhận khách đến từ ngày ' + date(booking.check_in_date) + '.'
      : afterDeparture
        ? 'Booking đã quá ngày trả phòng và không thể check-in.'
        : canConfirmArrival
          ? 'Đã đến ngày nhận phòng. Hãy xác nhận khi khách có mặt tại quầy.'
          : 'Không tải được ngày nhận phòng. Vui lòng tải lại danh sách booking.';
    $('scanResult').innerHTML = `<article class="qr-lookup-card">
      <header class="qr-lookup-header"><div><span class="qr-lookup-kicker">THÔNG TIN CHECK-IN</span><strong>${escapeHtml(row.booking_code)}</strong></div><span class="qr-status-badge">QR đã duyệt</span></header>
      <dl class="qr-lookup-details">
        <div><dt>Khách hàng</dt><dd>${escapeHtml(row.guest_name)}</dd></div>
        <div><dt>Phòng lưu trú</dt><dd>${escapeHtml(roomName)}</dd></div>
        <div class="qr-lookup-wide"><dt>Hiệu lực đến</dt><dd>${escapeHtml(expiry)}</dd></div>
      </dl>
      <p class="qr-lookup-note"><span aria-hidden="true">i</span> ${escapeHtml(eligibilityNote)}</p>
      <button id="consumeCheckinToken" class="checkin-action qr-confirm-action" type="button"${canConfirmArrival ? '' : ' disabled'}>${beforeArrival ? 'Chưa đến ngày nhận phòng' : afterDeparture ? 'Đã quá ngày nhận phòng' : 'Xác nhận khách đã đến'} <span aria-hidden="true">→</span></button>
    </article>`;
    if (!canConfirmArrival) return;
    $('consumeCheckinToken').addEventListener('click', async () => {
      const consumed = await window.gostaySupabase.rpc('staff_consume_checkin_token', { p_token:token });
      if (consumed.error) { $('scanResult').textContent=consumed.error.message; return; }
      $('scanResult').innerHTML='<div class="qr-success-card"><span aria-hidden="true">✓</span><div><strong>Check-in thành công</strong><p>Khách đã chuyển sang trạng thái đang lưu trú. Mã QR này không thể sử dụng lại.</p></div></div>';
      await load();
    });
  }

  if (window.Html5QrcodeScanner) {
    const scanner = new window.Html5QrcodeScanner('qr-reader', { fps:8, qrbox:220 }, false);
    scanner.render(decoded => { $('manualCheckinToken').value=decoded; lookupToken(decoded); }, () => {});
  }
}());

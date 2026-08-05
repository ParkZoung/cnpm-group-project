(function () {
  'use strict';
  const WORKING_BRANCH_KEY = 'gostay_staff_working_branch';
  const state = { bookings: [], branches: [], activeBranch: null, filter: 'today', search: '' };
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
    const today = new Date().toISOString().slice(0,10);
    const term = state.search.trim().toLocaleLowerCase('vi');
    return state.bookings.filter(b => {
      const text = [b.booking_code,b.guest_name,b.guest_phone,b.guest_email].join(' ').toLocaleLowerCase('vi');
      const category = state.filter === 'all' ||
        (state.filter === 'today' && b.check_in_date === today) ||
        (state.filter === 'payment_claimed' && b.online_checkin && b.online_checkin.status === 'payment_claimed') ||
        (state.filter === 'upcoming' && b.booking_status === 'confirmed' && b.check_in_date > today) ||
        (state.filter === 'staying' && b.booking_status === 'checked_in') ||
        (state.filter === 'balance' && Number(b.paid_amount) < Number(b.total_amount) && !['cancelled','completed'].includes(b.booking_status));
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
      const roomName = b.room ? String(b.room.name || 'Thông tin phòng').replace(/\s+\d+\s*$/, '').trim() : '—';
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
    const labels = { online_payment:'Online mô phỏng', staff_collection:'Thu tại quầy', refund:'Hoàn tiền' };
    $('staffDetailContent').innerHTML = `<p><strong>${escapeHtml(booking.booking_code)}</strong> — ${escapeHtml(booking.guest_name)}</p><p>Đã trả: ${money(booking.paid_amount)} · Còn lại: ${money(Number(booking.total_amount)-Number(booking.paid_amount))}</p>`
      + ((result.data || []).map(item => `<div class="transaction-row"><span>${escapeHtml(labels[item.transaction_type] || item.transaction_type)}</span><strong>${money(item.amount)}</strong><small>${escapeHtml(item.status)} · ${new Date(item.created_at).toLocaleString('vi-VN')}</small></div>`).join('') || '<p>Chưa có giao dịch.</p>');
    $('staffDetailModal').hidden = false;
  }

  function normalizeToken(value) {
    const raw = String(value || '').trim();
    return raw.toLowerCase().startsWith('gostay:checkin:') ? raw.slice(16) : raw;
  }

  async function lookupToken(value) {
    const token = normalizeToken(value);
    if (!/^[0-9a-f-]{36}$/i.test(token)) { $('scanResult').textContent='Mã QR không hợp lệ.'; return; }
    const result = await window.gostaySupabase.rpc('staff_lookup_checkin_token', { p_token:token });
    const row = Array.isArray(result.data) ? result.data[0] : result.data;
    if (result.error || !row) { $('scanResult').textContent='Không tìm thấy credential hợp lệ cho chi nhánh này.'; return; }
    $('scanResult').innerHTML = `<p><strong>${escapeHtml(row.booking_code)}</strong> — ${escapeHtml(row.guest_name)} — Phòng #${escapeHtml(row.room_id)}</p><p>Trạng thái QR: ${escapeHtml(row.online_checkin_status)}</p><button id="consumeCheckinToken" class="checkin-action">Xác nhận khách đã đến</button>`;
    $('consumeCheckinToken').addEventListener('click', async () => {
      const consumed = await window.gostaySupabase.rpc('staff_consume_checkin_token', { p_token:token });
      if (consumed.error) { $('scanResult').textContent=consumed.error.message; return; }
      $('scanResult').textContent='Check-in thành công. QR đã được vô hiệu hóa.'; await load();
    });
  }

  if (window.Html5QrcodeScanner) {
    const scanner = new window.Html5QrcodeScanner('qr-reader', { fps:8, qrbox:220 }, false);
    scanner.render(decoded => { $('manualCheckinToken').value=decoded; lookupToken(decoded); }, () => {});
  }
}());

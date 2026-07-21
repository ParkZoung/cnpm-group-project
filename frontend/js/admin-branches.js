(function () {
  'use strict';

  const TABLE_NAME = 'branches';
  let branches = [];
  let editingId = null;

  document.addEventListener('DOMContentLoaded', init);

  function init() {
    const page = document.querySelector('.admin-page-container');
    if (!page) return;

    injectStyles();
    page.innerHTML = `
      <section class="branch-summary" aria-label="Thống kê chi nhánh">
        <article class="branch-stat-card"><span>Tổng chi nhánh</span><strong id="branch-total">—</strong></article>
        <article class="branch-stat-card active"><span>Đang hoạt động</span><strong id="branch-active">—</strong></article>
        <article class="branch-stat-card inactive"><span>Ngừng hoạt động</span><strong id="branch-inactive">—</strong></article>
      </section>
      <section class="admin-card-section branch-list-card">
        <div class="section-header-row branch-heading">
          <div><h2>Danh sách chi nhánh</h2><p>Quản lý thông tin các chi nhánh khách sạn GoStay</p></div>
          <button id="branch-add-button" type="button" class="btn-primary-admin">＋ Thêm chi nhánh</button>
        </div>
        <div id="branch-toolbar" class="branch-toolbar">
          <label class="branch-search"><span>⌕</span><input id="branch-search" type="search" placeholder="Tìm theo tên, địa chỉ, thành phố..." autocomplete="off"></label>
          <select id="branch-status-filter" aria-label="Lọc trạng thái">
            <option value="all">Tất cả trạng thái</option>
            <option value="active">Đang hoạt động</option>
            <option value="inactive">Ngừng hoạt động</option>
          </select>
          <button id="branch-refresh" class="branch-refresh" type="button" title="Tải lại dữ liệu">↻ Tải lại</button>
        </div>
        <div id="branch-notice" class="branch-notice" role="status" aria-live="polite"></div>
        <div class="admin-table-wrapper branch-table-wrapper">
          <table class="admin-table branch-table">
            <thead><tr><th>ID</th><th>Chi nhánh</th><th>Địa chỉ</th><th>Liên hệ</th><th>Trạng thái</th><th>Ngày tạo</th><th>Thao tác</th></tr></thead>
            <tbody id="branch-table-body"></tbody>
          </table>
          <div id="branch-empty" class="branch-empty" hidden></div>
        </div>
        <div class="branch-table-footer"><span id="branch-result-count">Đang tải dữ liệu...</span></div>
      </section>
      <div id="branch-modal" class="branch-modal" hidden>
        <div class="branch-modal-backdrop" data-close-modal></div>
        <section class="branch-modal-panel" role="dialog" aria-modal="true" aria-labelledby="branch-modal-title">
          <header><div><h2 id="branch-modal-title">Thêm chi nhánh</h2><p>Nhập đầy đủ thông tin bên dưới</p></div><button type="button" class="branch-modal-close" data-close-modal aria-label="Đóng">×</button></header>
          <form id="branch-form" novalidate>
            <div class="branch-form-grid">
              <label class="branch-field full"><span>Tên chi nhánh <b>*</b></span><input id="branch-name" name="name" type="text" maxlength="150" required placeholder="Ví dụ: GoStay Đà Nẵng"><small></small></label>
              <label class="branch-field full"><span>Địa chỉ <b>*</b></span><textarea id="branch-address" name="address" maxlength="500" required rows="3" placeholder="Số nhà, đường, phường/xã..."></textarea><small></small></label>
              <label class="branch-field"><span>Thành phố <b>*</b></span><input id="branch-city" name="city" type="text" maxlength="100" required placeholder="Đà Nẵng"><small></small></label>
              <label class="branch-field"><span>Số điện thoại</span><input id="branch-phone" name="phone" type="tel" maxlength="20" placeholder="0901 234 567"><small></small></label>
              <label class="branch-field full"><span>Trạng thái <b>*</b></span><select id="branch-status" name="status" required><option value="active">Đang hoạt động</option><option value="inactive">Ngừng hoạt động</option></select><small></small></label>
            </div>
            <footer><button type="button" class="branch-cancel" data-close-modal>Hủy</button><button id="branch-submit" type="submit" class="btn-primary-admin">Lưu chi nhánh</button></footer>
          </form>
        </section>
      </div>`;

    bindEvents();
    loadBranches();
  }

  function bindEvents() {
    byId('branch-add-button').addEventListener('click', openCreateModal);
    byId('branch-refresh').addEventListener('click', loadBranches);
    byId('branch-search').addEventListener('input', renderBranches);
    byId('branch-status-filter').addEventListener('change', renderBranches);
    byId('branch-form').addEventListener('submit', saveBranch);
    document.querySelectorAll('[data-close-modal]').forEach((node) => node.addEventListener('click', closeModal));
    byId('branch-table-body').addEventListener('click', handleTableAction);
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape' && !byId('branch-modal').hidden) closeModal();
    });

    const oldSearch = document.querySelector('.topbar-search input');
    if (oldSearch) {
      oldSearch.addEventListener('input', () => {
        byId('branch-search').value = oldSearch.value;
        renderBranches();
      });
    }
  }

  async function loadBranches() {
    setLoading(true);
    clearNotice();
    try {
      const client = getClient();
      const { data, error } = await client.from(TABLE_NAME).select('id,name,address,city,phone,status,created_at').order('created_at', { ascending: false });
      if (error) throw error;
      branches = data || [];
      renderBranches();
      updateStats();
    } catch (error) {
      console.error('Không thể tải danh sách chi nhánh:', error);
      branches = [];
      renderBranches();
      updateStats();
      showNotice(readableError(error, 'Không thể tải dữ liệu chi nhánh.'), 'error');
    } finally {
      setLoading(false);
    }
  }

  function renderBranches() {
    const body = byId('branch-table-body');
    const empty = byId('branch-empty');
    const keyword = normalize(byId('branch-search').value);
    const status = byId('branch-status-filter').value;
    const filtered = branches.filter((branch) => {
      const haystack = normalize([branch.name, branch.address, branch.city, branch.phone].join(' '));
      return (!keyword || haystack.includes(keyword)) && (status === 'all' || branch.status === status);
    });

    body.replaceChildren();
    filtered.forEach((branch) => body.appendChild(createRow(branch)));
    empty.hidden = filtered.length !== 0;
    empty.textContent = branches.length ? 'Không tìm thấy chi nhánh phù hợp.' : 'Chưa có chi nhánh nào. Hãy thêm chi nhánh đầu tiên.';
    byId('branch-result-count').textContent = `Hiển thị ${filtered.length} / ${branches.length} chi nhánh`;
  }

  function createRow(branch) {
    const row = document.createElement('tr');
    row.dataset.id = branch.id;
    appendCell(row, branch.id);

    const nameCell = document.createElement('td');
    const name = document.createElement('strong');
    name.className = 'branch-name';
    name.textContent = branch.name || '—';
    nameCell.appendChild(name);
    appendSubtext(nameCell, branch.city || 'Chưa có thành phố');
    row.appendChild(nameCell);

    appendCell(row, branch.address || '—', 'branch-address-cell');
    appendCell(row, branch.phone || 'Chưa cập nhật');

    const statusCell = document.createElement('td');
    const badge = document.createElement('span');
    const isActive = branch.status === 'active';
    badge.className = `branch-status ${isActive ? 'is-active' : 'is-inactive'}`;
    badge.textContent = isActive ? 'Đang hoạt động' : 'Ngừng hoạt động';
    statusCell.appendChild(badge);
    row.appendChild(statusCell);

    appendCell(row, formatDate(branch.created_at));
    const actionCell = document.createElement('td');
    actionCell.innerHTML = `<div class="branch-actions"><button type="button" data-action="edit" aria-label="Sửa chi nhánh">✎ Sửa</button><button type="button" data-action="delete" class="danger" aria-label="Xóa chi nhánh">♲ Xóa</button></div>`;
    row.appendChild(actionCell);
    return row;
  }

  function appendCell(row, value, className) {
    const cell = document.createElement('td');
    if (className) cell.className = className;
    cell.textContent = String(value ?? '—');
    row.appendChild(cell);
  }

  function appendSubtext(cell, value) {
    const small = document.createElement('small');
    small.textContent = value;
    cell.appendChild(small);
  }

  function updateStats() {
    byId('branch-total').textContent = branches.length;
    byId('branch-active').textContent = branches.filter((item) => item.status === 'active').length;
    byId('branch-inactive').textContent = branches.filter((item) => item.status === 'inactive').length;
  }

  function handleTableAction(event) {
    const button = event.target.closest('button[data-action]');
    const row = event.target.closest('tr[data-id]');
    if (!button || !row) return;

    const branch = branches.find((item) => String(item.id) === row.dataset.id);
    if (!branch) {
      showNotice('Không xác định được chi nhánh cần thao tác.', 'error');
      return;
    }

    if (button.dataset.action === 'edit') openEditModal(branch);
    if (button.dataset.action === 'delete') deleteBranch(branch, button);
  }

  function openCreateModal() {
    editingId = null;
    byId('branch-form').reset();
    clearFieldErrors();
    byId('branch-status').value = 'active';
    byId('branch-modal-title').textContent = 'Thêm chi nhánh';
    byId('branch-submit').textContent = 'Thêm chi nhánh';
    showModal();
  }

  function openEditModal(branch) {
    editingId = branch.id;
    clearFieldErrors();
    byId('branch-name').value = branch.name || '';
    byId('branch-address').value = branch.address || '';
    byId('branch-city').value = branch.city || '';
    byId('branch-phone').value = branch.phone || '';
    byId('branch-status').value = branch.status === 'inactive' ? 'inactive' : 'active';
    byId('branch-modal-title').textContent = 'Cập nhật chi nhánh';
    byId('branch-submit').textContent = 'Lưu thay đổi';
    showModal();
  }

  function showModal() {
    byId('branch-modal').hidden = false;
    document.body.classList.add('branch-modal-open');
    setTimeout(() => byId('branch-name').focus(), 0);
  }

  function closeModal() {
    byId('branch-modal').hidden = true;
    document.body.classList.remove('branch-modal-open');
    editingId = null;
  }

  async function saveBranch(event) {
    event.preventDefault();
    const payload = {
      name: byId('branch-name').value.trim(),
      address: byId('branch-address').value.trim(),
      city: byId('branch-city').value.trim(),
      phone: byId('branch-phone').value.trim() || null,
      status: byId('branch-status').value
    };
    if (!validate(payload)) return;

    const submit = byId('branch-submit');
    const originalText = submit.textContent;
    submit.disabled = true;
    submit.textContent = 'Đang lưu...';
    const wasEditing = editingId !== null;

    try {
      const client = getClient();
      const query = editingId
        ? client.from(TABLE_NAME).update(payload).eq('id', editingId).select().single()
        : client.from(TABLE_NAME).insert(payload).select().single();
      const { error } = await query;
      if (error) throw error;
    } catch (error) {
      console.error('Không thể lưu chi nhánh:', error);
      showNotice(readableError(error, 'Không thể lưu chi nhánh.'), 'error', true);
      submit.disabled = false;
      submit.textContent = originalText;
      return;
    }

    submit.disabled = false;
    submit.textContent = originalText;
    closeModal();
    await loadBranches();
    showNotice(wasEditing ? 'Cập nhật chi nhánh thành công.' : 'Thêm chi nhánh thành công.', 'success');
  }

  async function deleteBranch(branch, button) {
    if (!window.confirm(`Bạn có chắc muốn xóa chi nhánh “${branch.name}”?\nThao tác này không thể hoàn tác.`)) return;

    button.disabled = true;
    try {
      const { error } = await getClient().from(TABLE_NAME).delete().eq('id', branch.id);
      if (error) throw error;
    } catch (error) {
      console.error('Không thể xóa chi nhánh:', error);
      button.disabled = false;
      showNotice(readableError(error, 'Không thể xóa chi nhánh.'), 'error');
      return;
    }

    branches = branches.filter((item) => item.id !== branch.id);
    renderBranches();
    updateStats();
    showNotice('Đã xóa chi nhánh thành công.', 'success');
  }

  function validate(payload) {
    clearFieldErrors();
    let valid = true;

    if (!payload.name) valid = setFieldError('branch-name', 'Vui lòng nhập tên chi nhánh.');
    if (!payload.address) valid = setFieldError('branch-address', 'Vui lòng nhập địa chỉ.');
    if (!payload.city) valid = setFieldError('branch-city', 'Vui lòng nhập thành phố.');
    if (payload.phone && !/^[0-9+().\s-]{8,20}$/.test(payload.phone)) {
      valid = setFieldError('branch-phone', 'Số điện thoại không hợp lệ.');
    }

    return valid;
  }
  function setFieldError(id, message) {
    const input = byId(id);
    input.classList.add('invalid');
    input.closest('.branch-field').querySelector('small').textContent = message;
    return false;
  }

  function clearFieldErrors() {
    document.querySelectorAll('.branch-field .invalid').forEach((node) => node.classList.remove('invalid'));
    document.querySelectorAll('.branch-field small').forEach((node) => { node.textContent = ''; });
  }

  function setLoading(loading) {
    const body = byId('branch-table-body');
    byId('branch-refresh').disabled = loading;
    if (loading) {
      body.innerHTML = '<tr><td colspan="7"><div class="branch-loading"><i></i><span>Đang tải dữ liệu chi nhánh...</span></div></td></tr>';
      byId('branch-empty').hidden = true;
      byId('branch-result-count').textContent = 'Đang tải dữ liệu...';
    }
  }

  function showNotice(message, type, inModal) {
    const notice = byId('branch-notice');
    if (!notice) {
      console.warn(message);
      return;
    }

    notice.textContent = message;
    notice.className = `branch-notice show ${type || 'error'}${inModal ? ' modal-level' : ''}`;
    const modalForm = byId('branch-form');
    const toolbar = byId('branch-toolbar');

    if (inModal && modalForm) modalForm.prepend(notice);
    else if (toolbar) toolbar.after(notice);
    else document.querySelector('.branch-list-card')?.prepend(notice);

    window.clearTimeout(showNotice.timer);
    showNotice.timer = window.setTimeout(clearNotice, 5000);
  }

  function clearNotice() {
    const notice = byId('branch-notice');
    if (!notice) return;
    notice.className = 'branch-notice';
    notice.textContent = '';
    const toolbar = byId('branch-toolbar');
    if (toolbar && notice.parentElement && notice.parentElement.id === 'branch-form') toolbar.after(notice);
  }

  function getClient() {
    if (!window.gostaySupabase) throw new Error('Chưa khởi tạo được kết nối Supabase.');
    return window.gostaySupabase;
  }

  function readableError(error, fallback) {
    if (!error) return fallback;
    if (error.code === '23505') return 'Tên chi nhánh đã tồn tại. Vui lòng chọn tên khác.';
    if (error.code === '23503') return 'Không thể xóa vì chi nhánh đang được sử dụng bởi dữ liệu khác.';
    if (error.code === '42501') {
      return `Supabase từ chối quyền thao tác: ${error.message || 'hãy kiểm tra quyền GRANT của bảng và sequence branches.'}`;
    }
    return error.message ? `${fallback} ${error.message}` : fallback;
  }

  function formatDate(value) {
    if (!value) return '—';
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? '—' : new Intl.DateTimeFormat('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric' }).format(date);
  }

  function normalize(value) {
    return String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  }

  function byId(id) { return document.getElementById(id); }

  function injectStyles() {
    const style = document.createElement('style');
    style.textContent = `
      .branch-summary{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:20px;margin-bottom:24px}.branch-stat-card{position:relative;overflow:hidden;background:#fff;border:1px solid #e2e8f0;border-radius:14px;padding:20px 22px;box-shadow:0 5px 18px rgba(15,23,42,.04)}.branch-stat-card:before{content:"";position:absolute;left:0;top:0;bottom:0;width:4px;background:#2563eb}.branch-stat-card.active:before{background:#16a34a}.branch-stat-card.inactive:before{background:#ef4444}.branch-stat-card span{display:block;color:#64748b;font-size:13px;font-weight:600;margin-bottom:8px}.branch-stat-card strong{font-size:28px;color:#0f172a}.branch-list-card{padding:0!important}.branch-heading{padding:25px 28px 20px;margin:0!important}.branch-heading h2{font-size:20px}.branch-heading p{margin:6px 0 0;color:#64748b;font-size:13px}.branch-toolbar{display:flex;gap:12px;padding:16px 28px;background:#f8fafc;border-top:1px solid #e2e8f0;border-bottom:1px solid #e2e8f0}.branch-search{display:flex;align-items:center;gap:9px;flex:1;max-width:480px;background:#fff;border:1px solid #cbd5e1;border-radius:9px;padding:0 13px;color:#64748b}.branch-search input{width:100%;border:0;outline:0;padding:10px 0;font-size:13px}.branch-toolbar select,.branch-refresh{background:#fff;border:1px solid #cbd5e1;border-radius:9px;padding:9px 12px;color:#475569;font-size:13px;cursor:pointer}.branch-table-wrapper{margin:22px 28px 0;overflow-x:auto}.branch-table{min-width:970px}.branch-table td{vertical-align:middle}.branch-table td:first-child{color:#64748b;font-family:monospace;font-size:12px;max-width:90px;overflow:hidden;text-overflow:ellipsis}.branch-name{display:block;color:#0f172a;margin-bottom:5px}.branch-table td small{display:block;color:#64748b;font-size:12px}.branch-address-cell{min-width:190px;max-width:280px;white-space:normal}.branch-status{display:inline-flex;align-items:center;gap:6px;border-radius:999px;padding:5px 10px;font-size:11px;font-weight:700;white-space:nowrap}.branch-status:before{content:"";width:6px;height:6px;border-radius:50%;background:currentColor}.branch-status.is-active{background:#dcfce7;color:#15803d}.branch-status.is-inactive{background:#fee2e2;color:#b91c1c}.branch-actions{display:flex;gap:7px}.branch-actions button{border:1px solid #cbd5e1;background:#fff;color:#334155;border-radius:7px;padding:6px 9px;font-size:12px;font-weight:600;cursor:pointer;white-space:nowrap}.branch-actions button:hover{border-color:#0ea5a8;color:#0f8e9e}.branch-actions button.danger:hover{border-color:#ef4444;color:#dc2626;background:#fef2f2}.branch-table-footer{padding:18px 28px 24px;color:#64748b;font-size:12px}.branch-empty{text-align:center;padding:52px 20px;color:#64748b}.branch-loading{display:flex;justify-content:center;align-items:center;gap:10px;padding:30px;color:#64748b}.branch-loading i{width:17px;height:17px;border:2px solid #cbd5e1;border-top-color:#0ea5a8;border-radius:50%;animation:branch-spin .7s linear infinite}@keyframes branch-spin{to{transform:rotate(360deg)}}.branch-notice{display:none}.branch-notice.show{display:block;margin:14px 28px 0;padding:11px 14px;border-radius:8px;font-size:13px}.branch-notice.success{background:#ecfdf5;color:#047857;border:1px solid #a7f3d0}.branch-notice.error{background:#fef2f2;color:#b91c1c;border:1px solid #fecaca}.branch-notice.modal-level{margin:0 0 18px}.branch-modal[hidden]{display:none}.branch-modal{position:fixed;inset:0;z-index:9999;display:grid;place-items:center;padding:20px}.branch-modal-backdrop{position:absolute;inset:0;background:rgba(15,23,42,.62);backdrop-filter:blur(2px)}.branch-modal-panel{position:relative;width:min(650px,100%);max-height:calc(100vh - 40px);overflow:auto;background:#fff;border-radius:16px;box-shadow:0 24px 60px rgba(15,23,42,.28)}.branch-modal-panel>header{display:flex;justify-content:space-between;align-items:flex-start;padding:22px 26px;border-bottom:1px solid #e2e8f0}.branch-modal-panel h2{margin:0;color:#0f172a;font-size:20px}.branch-modal-panel header p{margin:5px 0 0;color:#64748b;font-size:13px}.branch-modal-close{border:0;background:#f1f5f9;border-radius:8px;width:34px;height:34px;font-size:24px;color:#64748b;cursor:pointer}.branch-modal-panel form{padding:24px 26px}.branch-form-grid{display:grid;grid-template-columns:1fr 1fr;gap:18px}.branch-field{display:flex;flex-direction:column;gap:7px;color:#334155;font-size:13px;font-weight:600}.branch-field.full{grid-column:1/-1}.branch-field b{color:#ef4444}.branch-field input,.branch-field textarea,.branch-field select{width:100%;box-sizing:border-box;border:1px solid #cbd5e1;border-radius:8px;padding:10px 12px;background:#fff;color:#0f172a;font:inherit;font-weight:400;outline:0}.branch-field textarea{resize:vertical}.branch-field input:focus,.branch-field textarea:focus,.branch-field select:focus{border-color:#0ea5a8;box-shadow:0 0 0 3px rgba(14,165,168,.12)}.branch-field .invalid{border-color:#ef4444}.branch-field small{min-height:14px;color:#dc2626;font-weight:400}.branch-modal-panel form>footer{display:flex;justify-content:flex-end;gap:10px;margin-top:8px;padding-top:20px;border-top:1px solid #e2e8f0}.branch-cancel{border:1px solid #cbd5e1;background:#fff;border-radius:8px;padding:9px 18px;color:#475569;font-weight:600;cursor:pointer}.branch-modal-open{overflow:hidden}@media(max-width:900px){.branch-summary{grid-template-columns:1fr}.branch-toolbar{flex-wrap:wrap}.branch-search{min-width:100%;max-width:none}.branch-form-grid{grid-template-columns:1fr}.branch-field.full{grid-column:auto}}@media(max-width:650px){.admin-page-container{padding:20px!important}.branch-heading{align-items:flex-start;gap:15px;flex-direction:column}.branch-toolbar,.branch-heading{padding-left:18px;padding-right:18px}.branch-table-wrapper{margin-left:18px;margin-right:18px}.branch-toolbar select,.branch-refresh{flex:1}.branch-modal-panel form,.branch-modal-panel>header{padding-left:20px;padding-right:20px}}
    `;
    document.head.appendChild(style);
  }
})();

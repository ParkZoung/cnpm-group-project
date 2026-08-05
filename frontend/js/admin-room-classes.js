(function () {
  'use strict';

  let classes = [];
  const byId = id => document.getElementById(id);

  async function loadClasses() {
    const { data, error } = await window.gostaySupabase
      .from('room_classes')
      .select('id,name,description,sort_order,status')
      .order('sort_order', { ascending: true });
    if (error) {
      window.GoStayDialog.alert('Không thể tải hạng phòng: ' + error.message);
      return;
    }
    classes = data || [];
    renderClasses();
  }

  function renderClasses() {
    const body = byId('roomClassTable');
    body.replaceChildren();
    classes.forEach(item => {
      const row = document.createElement('tr');
      [item.name, item.description || '', item.status === 'active' ? 'Đang hoạt động' : 'Ngừng hoạt động']
        .forEach(value => {
          const cell = document.createElement('td');
          cell.textContent = value;
          row.appendChild(cell);
        });
      const actions = document.createElement('td');
      const edit = document.createElement('button');
      edit.type = 'button';
      edit.className = 'btn-action edit';
      edit.textContent = 'Sửa';
      edit.addEventListener('click', () => editClass(item));
      actions.appendChild(edit);
      row.appendChild(actions);
      body.appendChild(row);
    });
  }

  function editClass(item) {
    byId('roomClassId').value = item.id;
    byId('roomClassName').value = item.name;
    byId('roomClassDescription').value = item.description || '';
    byId('roomClassSort').value = item.sort_order;
    byId('roomClassStatus').value = item.status;
  }

  async function saveClass(event) {
    event.preventDefault();
    const id = byId('roomClassId').value;
    const payload = {
      name: byId('roomClassName').value.trim(),
      description: byId('roomClassDescription').value.trim() || null,
      sort_order: Number(byId('roomClassSort').value || 0),
      status: byId('roomClassStatus').value,
      updated_at: new Date().toISOString()
    };
    const query = id
      ? window.gostaySupabase.from('room_classes').update(payload).eq('id', id)
      : window.gostaySupabase.from('room_classes').insert(payload);
    const { error } = await query;
    if (error) {
      window.GoStayDialog.alert('Không thể lưu hạng phòng: ' + error.message);
      return;
    }
    event.target.reset();
    byId('roomClassId').value = '';
    await loadClasses();
  }

  document.addEventListener('DOMContentLoaded', async () => {
    const admin = await window.gostayAdminReady;
    if (!admin) return;
    byId('roomClassForm').addEventListener('submit', saveClass);
    byId('roomClassForm').addEventListener('reset', () => { byId('roomClassId').value = ''; });
    await loadClasses();
  });
}());

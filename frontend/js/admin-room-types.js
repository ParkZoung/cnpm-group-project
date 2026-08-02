// file: js/room-types.js

// Lấy đúng đối tượng kết nối được khởi tạo từ file js/supabase.js của bạn
const db = window.gostaySupabase;

// Khai báo các phần tử DOM đồng nhất tuyệt đối với ID trong HTML
const roomTypeForm = document.getElementById('roomTypeForm');
const idInput = document.getElementById('id');
const nameInput = document.getElementById('name');
const descriptionInput = document.getElementById('description');
const capacityInput = document.getElementById('capacity');
const bedTypeSelect = document.getElementById('bed_type');
const areaInput = document.getElementById('area_m2');
const basePriceInput = document.getElementById('base_price');

const roomTypeTable = document.getElementById('roomTypeTable');
const searchInput = document.getElementById('search');
const btnUpdate = document.getElementById('btnUpdate');

if (btnUpdate) btnUpdate.style.display = 'none';
let listRoomTypes = [];

// Hàm chặn lỗi an toàn nếu file cấu hình chưa kịp chạy hoặc lỗi tên file
function checkConnection() {
    if (!window.gostaySupabase) {
        console.error("LỖI KẾT NỐI: Không tìm thấy hệ thống Supabase. Hãy chắc chắn bạn đã đổi tên file cấu hình thành 'js/supabase.js'!");
        alert("Lỗi hệ thống: Ứng dụng chưa kết nối được tới cơ sở dữ liệu.");
        return false;
    }
    return true;
}

// ==========================================
// 1. READ: Tải danh sách từ cơ sở dữ liệu
// ==========================================
async function fetchRoomTypes() {
    if (!checkConnection()) return;

    try {
        const { data, error } = await window.gostaySupabase
            .from('room_types')
            .select('*')
            .order('created_at', { ascending: false });

        if (error) throw error;

        listRoomTypes = data;
        renderRoomTypes(listRoomTypes);
    } catch (error) {
        console.error('Lỗi khi tải bảng room_types:', error.message);
        alert('Không thể lấy dữ liệu loại phòng: ' + error.message);
    }
}

function renderRoomTypes(data) {
    roomTypeTable.replaceChildren();

    if (data.length === 0) {
        const emptyRow = document.createElement('tr');
        const emptyCell = document.createElement('td');
        emptyCell.colSpan = 8;
        emptyCell.style.textAlign = 'center';
        emptyCell.textContent = 'Không có dữ liệu loại phòng nào được tìm thấy';
        emptyRow.appendChild(emptyCell);
        roomTypeTable.appendChild(emptyRow);
        return;
    }

    data.forEach(item => {
        const row = document.createElement('tr');
        const formattedPrice = new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(item.base_price);
        const formattedDate = new Date(item.created_at).toLocaleDateString('vi-VN');

        const idCell = document.createElement('td');
        idCell.textContent = item.id;

        const nameCell = document.createElement('td');
        const name = document.createElement('strong');
        name.textContent = item.name;
        const description = document.createElement('small');
        description.style.color = '#666';
        description.textContent = item.description || '';
        nameCell.append(name, document.createElement('br'), description);

        const capacityCell = document.createElement('td');
        capacityCell.textContent = `${item.capacity} người`;

        const bedTypeCell = document.createElement('td');
        bedTypeCell.textContent = item.bed_type || 'N/A';

        const areaCell = document.createElement('td');
        areaCell.textContent = `${item.area_m2} m²`;

        const priceCell = document.createElement('td');
        priceCell.textContent = formattedPrice;

        const dateCell = document.createElement('td');
        dateCell.textContent = formattedDate;

        const actionCell = document.createElement('td');
        const editButton = document.createElement('button');
        editButton.type = 'button';
        editButton.className = 'btn-action edit';
        editButton.textContent = 'Sửa';
        editButton.addEventListener('click', () => editRoomType(item.id));

        const deleteButton = document.createElement('button');
        deleteButton.type = 'button';
        deleteButton.className = 'btn-action delete';
        deleteButton.dataset.action = 'delete-room-type';
        deleteButton.textContent = 'Xóa';
        deleteButton.addEventListener('click', () => deleteRoomType(item, deleteButton));
        actionCell.append(editButton, deleteButton);

        row.append(
            idCell,
            nameCell,
            capacityCell,
            bedTypeCell,
            areaCell,
            priceCell,
            dateCell,
            actionCell
        );
        roomTypeTable.appendChild(row);
    });
}

// ==========================================
// 2. CREATE & UPDATE: Tạo mới và Lưu cập nhật
// ==========================================
function initializeRoomTypes() {
roomTypeForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (!checkConnection()) return;

    const id = idInput.value;
    const roomTypeData = {
        name: nameInput.value.trim(),
        description: descriptionInput.value.trim(),
        capacity: parseInt(capacityInput.value),
        bed_type: bedTypeSelect.value || null,
        area_m2: parseFloat(areaInput.value),
        base_price: parseInt(basePriceInput.value)
    };

    // Kiểm tra ràng buộc dữ liệu đầu vào > 0
    if (roomTypeData.capacity <= 0 || roomTypeData.area_m2 <= 0 || roomTypeData.base_price <= 0) {
        alert('Yêu cầu nhập sức chứa, diện tích và giá trị lớn hơn 0!');
        return;
    }

    try {
        if (!id) {
            // Thêm mới dữ liệu
            const { error } = await window.gostaySupabase
                .from('room_types')
                .insert([roomTypeData]);

            if (error) throw error;
            alert('Thêm loại phòng thành công!');
        } else {
            // Cập nhật dữ liệu cũ theo ID
            const { error } = await window.gostaySupabase
                .from('room_types')
                .update(roomTypeData)
                .eq('id', id);

            if (error) throw error;
            alert('Cập nhật dữ liệu thành công!');
        }

        resetForm();
        fetchRoomTypes();
    } catch (error) {
        console.error('Lỗi lưu trữ:', error.message);
        alert('Thao tác không thành công: ' + error.message);
    }
});

// Kích hoạt sự kiện submit khi nhấn nút Cập Nhật độc lập
if (btnUpdate) {
    btnUpdate.addEventListener('click', () => {
        roomTypeForm.requestSubmit();
    });
}

// ==========================================
// 3. EDIT & DELETE: Chọn để sửa và Thực thi xóa
// ==========================================
window.editRoomType = function(id) {
    const item = listRoomTypes.find(room => room.id === id);
    if (!item) return;

    idInput.value = item.id;
    nameInput.value = item.name;
    descriptionInput.value = item.description || '';
    capacityInput.value = item.capacity;
    bedTypeSelect.value = item.bed_type || '';
    areaInput.value = item.area_m2;
    basePriceInput.value = item.base_price;

    if (btnUpdate) btnUpdate.style.display = 'inline-block';
};

async function deleteRoomType(item, button) {
    if (!checkConnection()) return;

    const originalLabel = button.textContent;
    button.disabled = true;
    button.textContent = 'Đang kiểm tra...';

    try {
        const { count, error: countError } = await window.gostaySupabase
            .from('rooms')
            .select('id', { count: 'exact', head: true })
            .eq('room_type_id', item.id);

        if (countError) throw countError;

        if (Number(count || 0) > 0) {
            alert(
                `Không thể xóa loại phòng "${item.name}" vì đang được ${count} phòng sử dụng. ` +
                'Vui lòng chuyển các phòng sang loại khác trước.'
            );
            return;
        }

        button.textContent = 'Xóa';
        if (!confirm(
            `Xóa loại phòng "${item.name}"?\n\n` +
            'Chỉ loại phòng không được phòng nào sử dụng mới có thể xóa.'
        )) return;

        button.textContent = 'Đang xóa...';
        const { error: deleteError } = await window.gostaySupabase
            .from('room_types')
            .delete()
            .eq('id', item.id);

        if (deleteError) throw deleteError;

        alert(`Đã xóa loại phòng "${item.name}".`);
        if (String(idInput.value) === String(item.id)) resetForm();
        await fetchRoomTypes();
    } catch (error) {
        console.error('Lỗi khi xóa loại phòng:', error);
        if (error && error.code === '23503') {
            alert(
                `Không thể xóa loại phòng "${item.name}" vì loại phòng vừa được gán cho một phòng. ` +
                'Vui lòng chuyển phòng đó sang loại khác trước.'
            );
        } else {
            alert('Không thể kiểm tra hoặc xóa loại phòng. Vui lòng thử lại.');
        }
    } finally {
        if (button.isConnected) {
            button.disabled = false;
            button.textContent = originalLabel;
        }
    }
}

// ==========================================
// 4. SEARCH & RESET: Lọc trực tiếp & Làm sạch Form
// ==========================================
if (searchInput) {
    searchInput.addEventListener('input', (e) => {
        const keyword = e.target.value.toLowerCase().trim();
        const filtered = listRoomTypes.filter(item => 
            item.name.toLowerCase().includes(keyword) || 
            (item.description && item.description.toLowerCase().includes(keyword))
        );
        renderRoomTypes(filtered);
    });
}

function resetForm() {
    roomTypeForm.reset();
    idInput.value = '';
    if (btnUpdate) btnUpdate.style.display = 'none';
}

roomTypeForm.addEventListener('reset', () => {
    idInput.value = '';
    if (btnUpdate) btnUpdate.style.display = 'none';
});
}

// Chỉ khởi tạo CRUD sau khi session và quyền Admin đã được xác minh.
document.addEventListener('DOMContentLoaded', async () => {
    try {
        const adminContext = await window.gostayAdminReady;
        if (!adminContext) return;
        initializeRoomTypes();
        await fetchRoomTypes();
    } catch (_error) {
        return;
    }
});

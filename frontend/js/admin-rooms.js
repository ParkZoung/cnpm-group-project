/* ==========================================================
   GoStay Admin - js/admin-rooms.js
   Người phụ trách: Bách
   Bảng CHÍNH (Create/Update/Delete): rooms
   Bảng liên quan (chỉ Read để đổ dropdown): branches, room_types

   Schema rooms (đã xác nhận, KHÔNG suy đoán):
     id bigint (tự sinh)
     branch_id bigint, bắt buộc -> branches.id
     room_type_id bigint, bắt buộc -> room_types.id
     room_number varchar, bắt buộc
     name varchar, bắt buộc
     price_per_night bigint > 0
     description text
     status: available | maintenance | inactive
     created_at, updated_at (tự sinh)

   Lưu ý: bảng rooms KHÔNG có cột "capacity/sức chứa" nên form
   không có trường này (dù tài liệu phân công có nhắc tới, nhưng
   đó là cột của room_types, không phải rooms).
   ========================================================== */

const ROOM_STATUS_LABELS = {
  available: { label: "Đang hoạt động", cssClass: "status-success" },
  maintenance: { label: "Đang bảo trì", cssClass: "status-warning" },
  inactive: { label: "Ngừng hoạt động", cssClass: "status-danger" },
};

let cachedBranches = [];
let cachedRoomTypes = [];

document.addEventListener("DOMContentLoaded", async () => {
  const adminContext = await window.gostayAdminReady;
  if (!adminContext) return;

  await loadRoomReferences();
  await loadRooms();

  document.getElementById("room-form").addEventListener("submit", handleRoomFormSubmit);
  document.getElementById("room-reset-btn").addEventListener("click", resetRoomForm);

  document.getElementById("room-search").addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      e.preventDefault();
      searchRooms();
    }
  });
  document.getElementById("room-filter-btn").addEventListener("click", filterRooms);
  document.getElementById("room-sort").addEventListener("change", sortRooms);
});

/* ---------- ĐỌC DỮ LIỆU THAM CHIẾU (branches, room_types) ---------- */

async function loadRoomReferences() {
  console.log("[branches] Đang tải danh sách chi nhánh cho dropdown...");
  const { data: branches, error: branchError } = await window.gostaySupabase
    .from("branches")
    .select("id, name")
    .order("name", { ascending: true });

  if (branchError) {
    console.error("[branches] Lỗi khi tải:", branchError.message);
  } else {
    cachedBranches = branches;
    fillSelectOptions("room-branch", branches, "-- Chọn chi nhánh --");
    fillSelectOptions("room-filter-branch", branches, "Tất cả chi nhánh");
  }

  console.log("[room_types] Đang tải danh sách loại phòng cho dropdown...");
  const { data: roomTypes, error: roomTypeError } = await window.gostaySupabase
    .from("room_types")
    .select("id, name")
    .order("name", { ascending: true });

  if (roomTypeError) {
    console.error("[room_types] Lỗi khi tải:", roomTypeError.message);
  } else {
    cachedRoomTypes = roomTypes;
    fillSelectOptions("room-type", roomTypes, "-- Chọn loại phòng --");
  }
}

function fillSelectOptions(selectId, rows, placeholderLabel) {
  const select = document.getElementById(selectId);
  const placeholderValue = select.options[0] ? select.options[0].value : "";
  select.innerHTML = "";

  const placeholderOption = document.createElement("option");
  placeholderOption.value = "";
  placeholderOption.textContent = placeholderLabel;
  select.appendChild(placeholderOption);

  rows.forEach((row) => {
    const option = document.createElement("option");
    option.value = row.id;
    option.textContent = row.name;
    select.appendChild(option);
  });
}

function getBranchName(branchId) {
  const branch = cachedBranches.find((b) => String(b.id) === String(branchId));
  return branch ? branch.name : "";
}

function getRoomTypeName(roomTypeId) {
  const roomType = cachedRoomTypes.find((t) => String(t.id) === String(roomTypeId));
  return roomType ? roomType.name : "";
}

/* ---------- READ: loadRooms / renderRooms ---------- */

function getRoomFiltersState() {
  return {
    keyword: document.getElementById("room-search").value.trim(),
    branchId: document.getElementById("room-filter-branch").value,
    status: document.getElementById("room-filter-status").value,
    sort: document.getElementById("room-sort").value,
  };
}

async function loadRooms(filters = {}) {
  console.log("[rooms] Đang tải dữ liệu với bộ lọc:", filters);

  let query = window.gostaySupabase
    .from("rooms")
    .select(
      "id, branch_id, room_type_id, room_number, name, price_per_night, description, status, created_at, updated_at, branches(name), room_types(name)"
    );

  if (filters.branchId) {
    query = query.eq("branch_id", filters.branchId);
  }
  if (filters.status) {
    query = query.eq("status", filters.status);
  }
  if (filters.keyword) {
    query = query.or(
      `name.ilike.%${filters.keyword}%,room_number.ilike.%${filters.keyword}%`
    );
  }

  if (filters.sort === "price-asc") {
    query = query.order("price_per_night", { ascending: true });
  } else if (filters.sort === "price-desc") {
    query = query.order("price_per_night", { ascending: false });
  } else {
    query = query.order("room_number", { ascending: true });
  }

  const { data, error } = await query;

  if (error) {
    console.error("[rooms] Lỗi khi tải:", error.message);
    showRoomMessage("Không tải được danh sách phòng: " + error.message, true);
    return;
  }

  console.log("[rooms] Nhận được", data.length, "dòng:", data);
  renderRooms(data);
}

function renderRooms(rows) {
  const tbody = document.getElementById("room-table-body");
  tbody.replaceChildren();

  if (rows.length === 0) {
    const emptyRow = document.createElement("tr");
    const emptyCell = document.createElement("td");
    emptyCell.colSpan = 7;
    emptyCell.textContent = "Không tìm thấy phòng phù hợp.";
    emptyRow.appendChild(emptyCell);
    tbody.appendChild(emptyRow);
    return;
  }

  rows.forEach((row) => {
    const statusInfo = ROOM_STATUS_LABELS[row.status] || {
      label: row.status,
      cssClass: "status-warning",
    };

    const tr = document.createElement("tr");
    tr.dataset.id = row.id;

    const roomNumberCell = document.createElement("td");
    roomNumberCell.textContent = row.room_number;

    const nameCell = document.createElement("td");
    const roomName = document.createElement("strong");
    roomName.textContent = row.name;
    nameCell.appendChild(roomName);

    const roomTypeCell = document.createElement("td");
    roomTypeCell.textContent = row.room_types ? row.room_types.name : "";

    const branchCell = document.createElement("td");
    branchCell.textContent = row.branches ? row.branches.name : "";

    const priceCell = document.createElement("td");
    priceCell.textContent = formatPrice(row.price_per_night);

    const statusCell = document.createElement("td");
    const statusBadge = document.createElement("span");
    statusBadge.className = `status-badge ${statusInfo.cssClass}`;
    statusBadge.textContent = statusInfo.label;
    statusCell.appendChild(statusBadge);

    const actionCell = document.createElement("td");
    const actionButtons = document.createElement("div");
    actionButtons.className = "action-buttons";

    const viewButton = document.createElement("button");
    viewButton.type = "button";
    viewButton.className = "btn-action edit";
    viewButton.dataset.action = "view";
    viewButton.textContent = "Xem";
    viewButton.addEventListener("click", () => viewRoomDetail(row));

    const editButton = document.createElement("button");
    editButton.type = "button";
    editButton.className = "btn-action edit";
    editButton.dataset.action = "edit";
    editButton.textContent = "Sửa";
    editButton.addEventListener("click", () => startEditRoom(row));

    const toggleButton = document.createElement("button");
    toggleButton.type = "button";
    toggleButton.className = "btn-action delete";
    toggleButton.dataset.action = "toggle-active";
    toggleButton.textContent = row.status === "inactive" ? "Kích hoạt lại" : "Ngừng hoạt động";
    toggleButton.addEventListener("click", () => toggleRoomActiveStatus(row, toggleButton));

    actionButtons.append(viewButton, editButton, toggleButton);
    actionCell.appendChild(actionButtons);
    tr.append(
      roomNumberCell,
      nameCell,
      roomTypeCell,
      branchCell,
      priceCell,
      statusCell,
      actionCell
    );
    tbody.appendChild(tr);
  });
}

/* ---------- SEARCH / FILTER / SORT (đều nạp lại qua Supabase) ---------- */

function searchRooms() {
  loadRooms(getRoomFiltersState());
}

function filterRooms() {
  loadRooms(getRoomFiltersState());
}

function sortRooms() {
  loadRooms(getRoomFiltersState());
}

/* ---------- XEM CHI TIẾT ---------- */

function viewRoomDetail(row) {
  const statusInfo = ROOM_STATUS_LABELS[row.status] || { label: row.status };
  alert(
    `Mã phòng: ${row.room_number}\n` +
    `Tên phòng: ${row.name}\n` +
    `Chi nhánh: ${row.branches ? row.branches.name : ""}\n` +
    `Loại phòng: ${row.room_types ? row.room_types.name : ""}\n` +
    `Giá / đêm: ${formatPrice(row.price_per_night)}\n` +
    `Mô tả: ${row.description || "(không có)"}\n` +
    `Trạng thái: ${statusInfo.label}\n` +
    `Tạo lúc: ${formatDateTime(row.created_at)}\n` +
    `Cập nhật lúc: ${formatDateTime(row.updated_at)}`
  );
}

/* ---------- FORM: CREATE / UPDATE ---------- */

function readRoomForm() {
  return {
    roomNumber: document.getElementById("room-number").value.trim(),
    name: document.getElementById("room-name").value.trim(),
    branchId: document.getElementById("room-branch").value,
    roomTypeId: document.getElementById("room-type").value,
    price: Number(document.getElementById("room-price").value),
    description: document.getElementById("room-description").value.trim() || null,
    status: document.getElementById("room-status").value,
  };
}

function validateRoomForm(form) {
  if (!form.roomNumber) return "Vui lòng nhập số/mã phòng.";
  if (!form.name) return "Vui lòng nhập tên phòng.";
  if (!form.branchId) return "Vui lòng chọn chi nhánh.";
  if (!form.roomTypeId) return "Vui lòng chọn loại phòng.";
  if (!form.price || form.price <= 0) return "Giá / đêm phải lớn hơn 0.";
  return "";
}

function handleRoomFormSubmit(event) {
  event.preventDefault();
  const roomId = document.getElementById("room-id").value;

  if (roomId) {
    updateRoom(roomId);
  } else {
    createRoom();
  }
}

async function createRoom() {
  const form = readRoomForm();
  const errorMessage = validateRoomForm(form);
  if (errorMessage) {
    showRoomMessage(errorMessage, true);
    return;
  }

  const { error } = await window.gostaySupabase.from("rooms").insert({
    room_number: form.roomNumber,
    name: form.name,
    branch_id: form.branchId,
    room_type_id: form.roomTypeId,
    price_per_night: form.price,
    description: form.description,
    status: form.status,
  });

  if (error) {
    console.error("[rooms] Lỗi khi thêm:", error.message);
    showRoomMessage("Thêm phòng thất bại: " + error.message, true);
    return;
  }

  console.log("[rooms] Đã thêm phòng:", form.roomNumber);
  showRoomMessage("Đã thêm phòng " + form.roomNumber + " thành công.", false);
  resetRoomForm();
  loadRooms(getRoomFiltersState());
}

function startEditRoom(row) {
  document.getElementById("room-id").value = row.id;
  document.getElementById("room-number").value = row.room_number;
  document.getElementById("room-name").value = row.name;
  document.getElementById("room-branch").value = row.branch_id;
  document.getElementById("room-type").value = row.room_type_id;
  document.getElementById("room-price").value = row.price_per_night;
  document.getElementById("room-description").value = row.description || "";
  document.getElementById("room-status").value = row.status;

  document.getElementById("room-form-title").textContent = "Cập nhật phòng: " + row.room_number;
  document.getElementById("room-submit-btn").textContent = "Cập nhật phòng";
  showRoomMessage("", false);

  if (typeof document.getElementById("room-form").scrollIntoView === "function") {
    document.getElementById("room-form").scrollIntoView({ behavior: "smooth" });
  }
}

async function updateRoom(roomId) {
  const form = readRoomForm();
  const errorMessage = validateRoomForm(form);
  if (errorMessage) {
    showRoomMessage(errorMessage, true);
    return;
  }

  const { error } = await window.gostaySupabase
    .from("rooms")
    .update({
      room_number: form.roomNumber,
      name: form.name,
      branch_id: form.branchId,
      room_type_id: form.roomTypeId,
      price_per_night: form.price,
      description: form.description,
      status: form.status,
      updated_at: new Date().toISOString(),
    })
    .eq("id", roomId);

  if (error) {
    console.error("[rooms] Lỗi khi cập nhật:", error.message);
    showRoomMessage("Cập nhật thất bại: " + error.message, true);
    return;
  }

  console.log("[rooms] Đã cập nhật phòng:", roomId);
  showRoomMessage("Đã cập nhật phòng " + form.roomNumber + " thành công.", false);
  resetRoomForm();
  loadRooms(getRoomFiltersState());
}

async function toggleRoomActiveStatus(row, button) {
  const isReactivating = row.status === "inactive";
  const nextStatus = isReactivating ? "available" : "inactive";
  const confirmationMessage = isReactivating
    ? `Kích hoạt lại phòng "${row.name}" (${row.room_number})?\n\nPhòng sẽ có thể xuất hiện trong kết quả tìm kiếm cho những ngày còn trống.`
    : `Ngừng hoạt động phòng "${row.name}" (${row.room_number})?\n\nPhòng sẽ không còn xuất hiện trong tìm kiếm của khách hàng. Các booking hiện tại và lịch sử booking vẫn được giữ nguyên.`;

  if (!confirm(confirmationMessage)) {
    return;
  }

  const originalLabel = button.textContent;
  button.disabled = true;
  button.textContent = "Đang xử lý...";

  try {
    const { error } = await window.gostaySupabase
      .from("rooms")
      .update({ status: nextStatus })
      .eq("id", row.id);

    if (error) throw error;

    console.log(
      isReactivating ? "[rooms] Đã kích hoạt lại phòng:" : "[rooms] Đã ngừng hoạt động phòng:",
      row.id
    );
    showRoomMessage(
      isReactivating
        ? "Đã kích hoạt lại phòng " + row.room_number + "."
        : "Đã ngừng hoạt động phòng " + row.room_number + ".",
      false
    );
    await loadRooms(getRoomFiltersState());
  } catch (error) {
    console.error("[rooms] Lỗi khi cập nhật trạng thái:", error);
    showRoomMessage(
      isReactivating
        ? "Không thể kích hoạt lại phòng. Vui lòng thử lại."
        : "Không thể ngừng hoạt động phòng. Vui lòng thử lại.",
      true
    );
    button.disabled = false;
    button.textContent = originalLabel;
  }
}

function resetRoomForm() {
  document.getElementById("room-form").reset();
  document.getElementById("room-id").value = "";
  document.getElementById("room-form-title").textContent = "Thêm phòng mới";
  document.getElementById("room-submit-btn").textContent = "Lưu phòng";
}

/* ---------- TIỆN ÍCH ---------- */

function showRoomMessage(text, isError) {
  const el = document.getElementById("room-message");
  el.textContent = text;
  el.style.color = isError ? "#dc2626" : "#16a34a";
}

function formatPrice(price) {
  return Number(price || 0).toLocaleString("vi-VN") + "đ";
}

function formatDateTime(isoString) {
  if (!isoString) return "";
  const d = new Date(isoString);
  if (isNaN(d.getTime())) return isoString;
  return d.toLocaleString("vi-VN");
}

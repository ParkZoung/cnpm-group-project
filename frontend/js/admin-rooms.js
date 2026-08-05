

const ROOM_STATUS_LABELS = {
  available: { label: "Đang hoạt động", cssClass: "status-success" },
  maintenance: { label: "Đang bảo trì", cssClass: "status-warning" },
  inactive: { label: "Ngừng hoạt động", cssClass: "status-danger" },
};

function cleanCatalogText(value) {
  return String(value || "")
    .replace(/\[GOSTAY_DEMO_V1\]/gi, "")
    .replace(/\s{2,}/g, " ")
    .trim();
}

function displayRoomName(name, roomTypeName) {
  return cleanCatalogText(name || roomTypeName || "Thông tin phòng")
    .replace(/\s+\d+\s*$/, "")
    .trim();
}

let cachedBranches = [];
let cachedRoomTypes = [];
let cachedRoomClasses = [];
let cachedAmenities = [];
let amenitiesLoaded = false;
let amenitySelectionEditable = false;
let selectedRoomImageFile = null;
let removeRoomImageRequested = false;
let roomImageObjectUrl = null;

document.addEventListener("DOMContentLoaded", async () => {
  const adminContext = await window.gostayAdminReady;
  if (!adminContext) return;

  await loadRoomReferences();
  await loadRooms();

  document.getElementById("room-form").addEventListener("submit", handleRoomFormSubmit);
  document.getElementById("room-reset-btn").addEventListener("click", resetRoomForm);
  document.getElementById("room-image-file").addEventListener("change", handleRoomImageChange);
  document.getElementById("room-image-remove").addEventListener("click", removeRoomImagePreview);

  document.getElementById("room-search").addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      e.preventDefault();
      searchRooms();
    }
  });
  document.getElementById("room-filter-btn").addEventListener("click", filterRooms);
  document.getElementById("room-sort").addEventListener("change", sortRooms);
});



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
    fillSelectOptions("room-filter-type", roomTypes, "Tất cả loại phòng");
  }

  const { data: roomClasses, error: roomClassError } = await window.gostaySupabase
    .from("room_classes")
    .select("id, name")
    .eq("status", "active")
    .order("sort_order", { ascending: true });
  if (roomClassError) {
    console.error("[room_classes] Lỗi khi tải:", roomClassError.message);
  } else {
    cachedRoomClasses = roomClasses || [];
    fillSelectOptions("room-class", cachedRoomClasses, "-- Chọn hạng phòng --");
    fillSelectOptions("room-filter-class", cachedRoomClasses, "Tất cả hạng phòng");
  }

  const { data: amenities, error: amenityError } = await window.gostaySupabase
    .from("amenities")
    .select("id, name, icon")
    .eq("status", "active")
    .order("name", { ascending: true });

  if (amenityError) {
    console.error("[amenities] Lỗi khi tải:", amenityError.message);
    renderAmenityOptions([], "Không thể tải danh sách tiện nghi.");
  } else {
    cachedAmenities = amenities || [];
    amenitiesLoaded = true;
    amenitySelectionEditable = true;
    renderAmenityOptions(cachedAmenities);
  }
}

function renderAmenityOptions(amenities, emptyMessage) {
  const container = document.getElementById("room-amenities-options");
  container.replaceChildren();

  if (!amenities.length) {
    const message = document.createElement("span");
    message.className = "room-amenities-placeholder";
    message.textContent = emptyMessage || "Chưa có tiện nghi đang hoạt động.";
    container.appendChild(message);
    return;
  }

  amenities.forEach((amenity) => {
    const label = document.createElement("label");
    label.className = "room-amenity-option";

    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.name = "room-amenity";
    checkbox.value = String(amenity.id);

    const text = document.createElement("span");
    text.textContent = amenity.name;
    label.append(checkbox, text);
    container.appendChild(label);
  });
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



function getRoomFiltersState() {
  return {
    keyword: document.getElementById("room-search").value.trim(),
    branchId: document.getElementById("room-filter-branch").value,
    roomTypeId: document.getElementById("room-filter-type").value,
    roomClassId: document.getElementById("room-filter-class").value,
    status: document.getElementById("room-filter-status").value,
    sort: document.getElementById("room-sort").value,
  };
}

async function loadRooms(filters = {}) {
  console.log("[rooms] Đang tải dữ liệu với bộ lọc:", filters);

  let query = window.gostaySupabase
    .from("rooms")
    .select(
      "id, branch_id, room_type_id, room_class_id, inventory_count, name, price_per_night, description, status, created_at, updated_at, branches(name), room_types(name), room_classes(name)"
    );

  if (filters.branchId) {
    query = query.eq("branch_id", filters.branchId);
  }
  if (filters.roomTypeId) {
    query = query.eq("room_type_id", filters.roomTypeId);
  }
  if (filters.roomClassId) {
    query = query.eq("room_class_id", filters.roomClassId);
  }
  if (filters.status) {
    query = query.eq("status", filters.status);
  }
  if (filters.keyword) {
    query = query.ilike("name", `%${filters.keyword}%`);
  }

  if (filters.sort === "price-asc") {
    query = query.order("price_per_night", { ascending: true });
  } else if (filters.sort === "price-desc") {
    query = query.order("price_per_night", { ascending: false });
  } else {
    query = query.order("name", { ascending: true });
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

    const nameCell = document.createElement("td");
    const roomName = document.createElement("strong");
    roomName.textContent = displayRoomName(row.name, row.room_types && row.room_types.name);
    nameCell.appendChild(roomName);

    const roomTypeCell = document.createElement("td");
    roomTypeCell.textContent = row.room_types ? cleanCatalogText(row.room_types.name) : "";

    const roomClassCell = document.createElement("td");
    roomClassCell.textContent = row.room_classes ? cleanCatalogText(row.room_classes.name) : "";

    const branchCell = document.createElement("td");
    branchCell.textContent = row.branches ? cleanCatalogText(row.branches.name) : "";

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
      nameCell,
      roomTypeCell,
      roomClassCell,
      branchCell,
      priceCell,
      statusCell,
      actionCell
    );
    tbody.appendChild(tr);
  });
}



function searchRooms() {
  loadRooms(getRoomFiltersState());
}

function filterRooms() {
  loadRooms(getRoomFiltersState());
}

function sortRooms() {
  loadRooms(getRoomFiltersState());
}



function viewRoomDetail(row) {
  const params = new URLSearchParams({ id: String(row.id) });
  window.GoStayDialog.preview(
    'room-detail.html?' + params.toString(),
    'Xem trước: ' + displayRoomName(row.name, row.room_types && row.room_types.name)
  );
}



function readRoomForm() {
  return {
    name: document.getElementById("room-name").value.trim(),
    branchId: document.getElementById("room-branch").value,
    roomTypeId: document.getElementById("room-type").value,
    roomClassId: document.getElementById("room-class").value,
    inventoryCount: Number(document.getElementById("room-inventory").value),
    price: Number(document.getElementById("room-price").value),
    description: document.getElementById("room-description").value.trim() || null,
    status: document.getElementById("room-status").value,
    amenityIds: Array.from(document.querySelectorAll('input[name="room-amenity"]:checked'))
      .map((input) => Number(input.value)),
  };
}

function handleRoomImageChange(event) {
  const file = event.target.files && event.target.files[0];
  if (!file) return;
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
    window.GoStayDialog.alert('Chỉ hỗ trợ ảnh JPG, PNG hoặc WebP.', 'Ảnh không hợp lệ');
    event.target.value = '';
    return;
  }
  if (file.size > 5 * 1024 * 1024) {
    window.GoStayDialog.alert('Dung lượng ảnh không được vượt quá 5 MB.', 'Ảnh quá lớn');
    event.target.value = '';
    return;
  }
  selectedRoomImageFile = file;
  removeRoomImageRequested = false;
  if (roomImageObjectUrl) URL.revokeObjectURL(roomImageObjectUrl);
  roomImageObjectUrl = URL.createObjectURL(file);
  showRoomImagePreview(roomImageObjectUrl);
}

function showRoomImagePreview(url) {
  const image = document.getElementById('room-image-preview');
  image.src = url;
  image.hidden = false;
  document.getElementById('room-image-placeholder').hidden = true;
  document.getElementById('room-image-remove').hidden = false;
}

function removeRoomImagePreview() {
  selectedRoomImageFile = null;
  removeRoomImageRequested = true;
  document.getElementById('room-image-file').value = '';
  const image = document.getElementById('room-image-preview');
  image.removeAttribute('src');
  image.hidden = true;
  document.getElementById('room-image-placeholder').hidden = false;
  document.getElementById('room-image-remove').hidden = true;
  if (roomImageObjectUrl) URL.revokeObjectURL(roomImageObjectUrl);
  roomImageObjectUrl = null;
}

async function loadRoomImageSelection(roomId) {
  selectedRoomImageFile = null;
  removeRoomImageRequested = false;
  document.getElementById('room-image-file').value = '';
  const { data, error } = await window.gostaySupabase
    .from('room_images')
    .select('image_url')
    .eq('room_id', roomId)
    .eq('is_primary', true)
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  if (data && data.image_url) showRoomImagePreview(data.image_url);
  else removeRoomImagePreview();
  removeRoomImageRequested = false;
}

async function syncRoomImage(roomId, roomName) {
  if (!selectedRoomImageFile && !removeRoomImageRequested) return;
  let payload = { roomId: Number(roomId) };
  if (removeRoomImageRequested) {
    payload.action = 'delete';
  } else {
    payload.mimeType = selectedRoomImageFile.type;
    payload.base64 = await fileToBase64(selectedRoomImageFile);
    payload.altText = roomName + ' tại GoStay';
  }
  const result = await window.GoStayApiClient.authenticatedRequest('/room-image', payload);
  if (result.error) throw result.error;
}

function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error('Không thể đọc tệp ảnh.'));
    reader.onload = () => resolve(String(reader.result).split(',')[1] || '');
    reader.readAsDataURL(file);
  });
}

async function syncRoomAmenities(roomId, amenityIds) {
  if (!amenitiesLoaded || !amenitySelectionEditable) return;

  const { data: currentLinks, error: readError } = await window.gostaySupabase
    .from("room_amenities")
    .select("amenity_id")
    .eq("room_id", roomId);
  if (readError) throw readError;

  const currentIds = new Set((currentLinks || []).map((item) => Number(item.amenity_id)));
  const selectedIds = new Set(amenityIds.map(Number));
  const linksToAdd = amenityIds
    .filter((amenityId) => !currentIds.has(Number(amenityId)))
    .map((amenityId) => ({ room_id: Number(roomId), amenity_id: Number(amenityId) }));

  if (linksToAdd.length) {
    const { error: insertError } = await window.gostaySupabase
      .from("room_amenities")
      .insert(linksToAdd);
    if (insertError) throw insertError;
  }

  const linksToRemove = Array.from(currentIds).filter((amenityId) => !selectedIds.has(amenityId));
  for (const amenityId of linksToRemove) {
    const { error: deleteError } = await window.gostaySupabase
      .from("room_amenities")
      .delete()
      .eq("room_id", roomId)
      .eq("amenity_id", amenityId);
    if (deleteError) throw deleteError;
  }
}

function validateRoomForm(form) {
  if (!form.name) return "Vui lòng nhập tên phòng.";
  if (!form.branchId) return "Vui lòng chọn chi nhánh.";
  if (!form.roomTypeId) return "Vui lòng chọn loại phòng.";
  if (!form.roomClassId) return "Vui lòng chọn hạng phòng.";
  if (!Number.isInteger(form.inventoryCount) || form.inventoryCount < 1) return "Số lượng phòng phải từ 1 trở lên.";
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

  const { data: createdRoom, error } = await window.gostaySupabase
    .from("rooms")
    .insert({
      room_number: null,
      name: form.name,
      branch_id: form.branchId,
      room_type_id: form.roomTypeId,
      room_class_id: form.roomClassId,
      inventory_count: form.inventoryCount,
      price_per_night: form.price,
      description: form.description,
      status: form.status,
    })
    .select("id")
    .single();

  if (error) {
    console.error("[rooms] Lỗi khi thêm:", error.message);
    showRoomMessage("Thêm phòng thất bại: " + error.message, true);
    return;
  }

  try {
    await syncRoomAmenities(createdRoom.id, form.amenityIds);
    await syncRoomImage(createdRoom.id, form.name);
  } catch (amenityError) {
    console.error("[room_amenities] Phòng đã tạo nhưng lưu tiện nghi thất bại:", amenityError.message);
    document.getElementById("room-id").value = createdRoom.id;
    showRoomMessage("Phòng đã được tạo nhưng chưa lưu được tiện nghi. Hãy thử cập nhật lại.", true);
    await loadRooms(getRoomFiltersState());
    return;
  }

  console.log("[rooms] Đã thêm cấu hình phòng:", form.name);
  showRoomMessage("Đã thêm phòng thành công.", false);
  resetRoomForm();
  loadRooms(getRoomFiltersState());
}

async function startEditRoom(row) {
  document.getElementById("room-id").value = row.id;
  document.getElementById("room-name").value = cleanCatalogText(row.name);
  document.getElementById("room-branch").value = row.branch_id;
  document.getElementById("room-type").value = row.room_type_id;
  document.getElementById("room-class").value = row.room_class_id;
  document.getElementById("room-inventory").value = row.inventory_count;
  document.getElementById("room-price").value = row.price_per_night;
  document.getElementById("room-description").value = cleanCatalogText(row.description);
  document.getElementById("room-status").value = row.status;
  showRoomMessage("", false);

  await loadRoomAmenitySelection(row.id);
  await loadRoomImageSelection(row.id);

  document.getElementById("room-form-title").textContent = "Cập nhật: " + displayRoomName(row.name, row.room_types && row.room_types.name);
  document.getElementById("room-submit-btn").textContent = "Cập nhật phòng";

  if (typeof document.getElementById("room-form").scrollIntoView === "function") {
    document.getElementById("room-form").scrollIntoView({ behavior: "smooth" });
  }
}

async function loadRoomAmenitySelection(roomId) {
  document.querySelectorAll('input[name="room-amenity"]').forEach((input) => {
    input.checked = false;
  });
  amenitySelectionEditable = false;
  if (!amenitiesLoaded) return;

  const submitButton = document.getElementById("room-submit-btn");
  submitButton.disabled = true;
  try {
    const { data, error } = await window.gostaySupabase
      .from("room_amenities")
      .select("amenity_id")
      .eq("room_id", roomId);
    if (error) throw error;

    const selectedIds = new Set((data || []).map((item) => String(item.amenity_id)));
    document.querySelectorAll('input[name="room-amenity"]').forEach((input) => {
      input.checked = selectedIds.has(input.value);
    });
    amenitySelectionEditable = true;
  } catch (error) {
    console.error("[room_amenities] Không thể tải tiện nghi của phòng:", error.message);
    showRoomMessage("Không thể tải tiện nghi hiện tại; các tiện nghi sẽ được giữ nguyên khi cập nhật.", true);
  } finally {
    submitButton.disabled = false;
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
      room_number: null,
      name: form.name,
      branch_id: form.branchId,
      room_type_id: form.roomTypeId,
      room_class_id: form.roomClassId,
      inventory_count: form.inventoryCount,
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

  try {
    await syncRoomAmenities(roomId, form.amenityIds);
    await syncRoomImage(roomId, form.name);
  } catch (amenityError) {
    console.error("[room_amenities] Phòng đã cập nhật nhưng lưu tiện nghi thất bại:", amenityError.message);
    showRoomMessage("Thông tin phòng đã cập nhật nhưng chưa lưu được tiện nghi. Hãy thử lại.", true);
    await loadRooms(getRoomFiltersState());
    return;
  }

  console.log("[rooms] Đã cập nhật phòng:", roomId);
  showRoomMessage("Đã cập nhật phòng thành công.", false);
  resetRoomForm();
  loadRooms(getRoomFiltersState());
}

async function toggleRoomActiveStatus(row, button) {
  const isReactivating = row.status === "inactive";
  const nextStatus = isReactivating ? "available" : "inactive";
  const confirmationMessage = isReactivating
    ? `Kích hoạt lại phòng "${displayRoomName(row.name, row.room_types && row.room_types.name)}"?\n\nPhòng sẽ có thể xuất hiện trong kết quả tìm kiếm cho những ngày còn trống.`
    : `Ngừng hoạt động phòng "${displayRoomName(row.name, row.room_types && row.room_types.name)}"?\n\nPhòng sẽ không còn xuất hiện trong tìm kiếm của khách hàng. Các đặt phòng hiện tại và lịch sử đặt phòng vẫn được giữ nguyên.`;

  if (!(await window.GoStayDialog.confirm(confirmationMessage))) {
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
        ? "Đã kích hoạt lại phòng thành công."
        : "Đã ngừng hoạt động phòng thành công.",
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
  amenitySelectionEditable = amenitiesLoaded;
  document.querySelectorAll('input[name="room-amenity"]').forEach((input) => {
    input.checked = false;
  });
  selectedRoomImageFile = null;
  removeRoomImageRequested = false;
  document.getElementById('room-image-file').value = '';
  const image = document.getElementById('room-image-preview');
  image.removeAttribute('src');
  image.hidden = true;
  document.getElementById('room-image-placeholder').hidden = false;
  document.getElementById('room-image-remove').hidden = true;
  if (roomImageObjectUrl) URL.revokeObjectURL(roomImageObjectUrl);
  roomImageObjectUrl = null;
}



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



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
let cachedAmenities = [];
let amenitiesLoaded = false;
let amenitySelectionEditable = false;
let pendingRoomImages = [];
const ROOM_IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const ROOM_IMAGE_MAX_BYTES = 5 * 1024 * 1024;
const ROOM_IMAGE_MAX_FILES = 5;

document.addEventListener("DOMContentLoaded", async () => {
  const adminContext = await window.gostayAdminReady;
  if (!adminContext) return;

  await loadRoomReferences();
  await loadRooms();

  document.getElementById("room-form").addEventListener("submit", handleRoomFormSubmit);
  document.getElementById("room-reset-btn").addEventListener("click", resetRoomForm);
  document.getElementById("room-images").addEventListener("change", handleRoomImageSelection);

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
    emptyCell.colSpan = 6;
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
  const statusInfo = ROOM_STATUS_LABELS[row.status] || { label: row.status };
  alert(
    `Tên phòng: ${displayRoomName(row.name, row.room_types && row.room_types.name)}\n` +
    `Chi nhánh: ${row.branches ? cleanCatalogText(row.branches.name) : ""}\n` +
    `Loại phòng: ${row.room_types ? cleanCatalogText(row.room_types.name) : ""}\n` +
    `Giá / đêm: ${formatPrice(row.price_per_night)}\n` +
    `Mô tả: ${cleanCatalogText(row.description) || "(không có)"}\n` +
    `Trạng thái: ${statusInfo.label}\n` +
    `Tạo lúc: ${formatDateTime(row.created_at)}\n` +
    `Cập nhật lúc: ${formatDateTime(row.updated_at)}`
  );
}



function readRoomForm() {
  return {
    roomNumber: document.getElementById("room-number").value.trim() || `R${Date.now()}`,
    name: document.getElementById("room-name").value.trim(),
    branchId: document.getElementById("room-branch").value,
    roomTypeId: document.getElementById("room-type").value,
    price: Number(document.getElementById("room-price").value),
    description: document.getElementById("room-description").value.trim() || null,
    status: document.getElementById("room-status").value,
    amenityIds: Array.from(document.querySelectorAll('input[name="room-amenity"]:checked'))
      .map((input) => Number(input.value)),
  };
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

  const { data: createdRoom, error } = await window.gostaySupabase
    .from("rooms")
    .insert({
      room_number: form.roomNumber,
      name: form.name,
      branch_id: form.branchId,
      room_type_id: form.roomTypeId,
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
    await uploadPendingRoomImages(createdRoom.id, form.name);
  } catch (relatedDataError) {
    console.error("[rooms] Phòng đã tạo nhưng tiện nghi hoặc ảnh lưu thất bại:", relatedDataError.message);
    document.getElementById("room-id").value = createdRoom.id;
    showRoomMessage("Phòng đã được tạo nhưng tiện nghi hoặc ảnh chưa lưu đầy đủ: " + relatedDataError.message, true);
    await loadRooms(getRoomFiltersState());
    return;
  }

  console.log("[rooms] Đã thêm phòng:", form.roomNumber);
  showRoomMessage("Đã thêm phòng thành công.", false);
  resetRoomForm();
  loadRooms(getRoomFiltersState());
}

async function startEditRoom(row) {
  clearPendingRoomImages();
  document.getElementById("room-id").value = row.id;
  document.getElementById("room-number").value = row.room_number;
  document.getElementById("room-name").value = cleanCatalogText(row.name);
  document.getElementById("room-branch").value = row.branch_id;
  document.getElementById("room-type").value = row.room_type_id;
  document.getElementById("room-price").value = row.price_per_night;
  document.getElementById("room-description").value = cleanCatalogText(row.description);
  document.getElementById("room-status").value = row.status;
  showRoomMessage("", false);

  await loadRoomAmenitySelection(row.id);
  await loadExistingRoomImages(row.id);

  document.getElementById("room-form-title").textContent = "Cập nhật: " + displayRoomName(row.name, row.room_types && row.room_types.name);
  document.getElementById("room-submit-btn").textContent = "Cập nhật phòng";

  if (typeof document.getElementById("room-form").scrollIntoView === "function") {
    document.getElementById("room-form").scrollIntoView({ behavior: "smooth" });
  }
}

function handleRoomImageSelection(event) {
  const files = Array.from(event.target.files || []);
  if (files.length > ROOM_IMAGE_MAX_FILES) {
    showImageFeedback("Mỗi lần chỉ được chọn tối đa 5 ảnh.", true);
    event.target.value = "";
    return;
  }
  const invalid = files.find((file) =>
    !ROOM_IMAGE_TYPES.has(file.type) || file.size > ROOM_IMAGE_MAX_BYTES
  );
  if (invalid) {
    showImageFeedback(`Ảnh "${invalid.name}" không đúng định dạng hoặc vượt quá 5 MB.`, true);
    event.target.value = "";
    return;
  }
  pendingRoomImages.forEach((item) => URL.revokeObjectURL(item.previewUrl));
  pendingRoomImages = files.map((file) => ({ file, previewUrl: URL.createObjectURL(file) }));
  showImageFeedback(files.length ? `Đã chọn ${files.length} ảnh.` : "", false);
  renderPendingRoomImages();
}

function renderPendingRoomImages() {
  const container = document.getElementById("room-image-preview");
  container.replaceChildren();
  pendingRoomImages.forEach((item, index) => {
    const card = createImageCard(item.previewUrl, item.file.name, false);
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = "Xóa";
    button.addEventListener("click", () => {
      URL.revokeObjectURL(item.previewUrl);
      pendingRoomImages.splice(index, 1);
      renderPendingRoomImages();
      showImageFeedback(pendingRoomImages.length ? `Đã chọn ${pendingRoomImages.length} ảnh.` : "", false);
    });
    card.appendChild(button);
    container.appendChild(card);
  });
}

function createImageCard(url, label, isPrimary) {
  const card = document.createElement("div");
  card.className = "room-image-card" + (isPrimary ? " room-image-primary" : "");
  const image = document.createElement("img");
  image.src = url;
  image.alt = label || "Ảnh phòng";
  const caption = document.createElement("span");
  caption.textContent = label || "Ảnh phòng";
  card.append(image, caption);
  return card;
}

function showImageFeedback(text, isError) {
  const element = document.getElementById("room-image-feedback");
  element.textContent = text;
  element.style.color = isError ? "#dc2626" : "#475569";
}

function clearPendingRoomImages() {
  pendingRoomImages.forEach((item) => URL.revokeObjectURL(item.previewUrl));
  pendingRoomImages = [];
  document.getElementById("room-images").value = "";
  document.getElementById("room-image-preview").replaceChildren();
}

function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).split(",")[1] || "");
    reader.onerror = () => reject(new Error("Không thể đọc file ảnh."));
    reader.readAsDataURL(file);
  });
}

async function uploadPendingRoomImages(roomId, roomName) {
  const total = pendingRoomImages.length;
  let completed = 0;
  while (pendingRoomImages.length) {
    showImageFeedback(`Đang tải ảnh ${completed + 1}/${total}...`, false);
    const item = pendingRoomImages[0];
    const result = await window.GoStayApiClient.authenticatedRequest("/room-image", {
      action: "upload",
      roomId: Number(roomId),
      mimeType: item.file.type,
      base64: await fileToBase64(item.file),
      altText: `${roomName} - ảnh ${completed + 1}`,
    });
    if (result.error) throw new Error(result.error.message);
    URL.revokeObjectURL(item.previewUrl);
    pendingRoomImages.shift();
    completed += 1;
    renderPendingRoomImages();
  }
}

async function loadExistingRoomImages(roomId) {
  const container = document.getElementById("room-existing-images");
  container.replaceChildren();
  const { data, error } = await window.gostaySupabase.from("room_images")
    .select("id, image_url, alt_text, is_primary, sort_order")
    .eq("room_id", roomId)
    .order("is_primary", { ascending: false })
    .order("sort_order", { ascending: true });
  if (error) {
    showImageFeedback("Không thể tải danh sách ảnh hiện tại.", true);
    return;
  }
  (data || []).forEach((roomImage) => {
    const card = createImageCard(roomImage.image_url, roomImage.alt_text, roomImage.is_primary);
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = "Xóa";
    button.addEventListener("click", () => deleteExistingRoomImage(roomImage.id, roomId));
    card.appendChild(button);
    container.appendChild(card);
  });
}

async function deleteExistingRoomImage(imageId, roomId) {
  if (!confirm("Xóa ảnh này khỏi phòng?")) return;
  showImageFeedback("Đang xóa ảnh...", false);
  const result = await window.GoStayApiClient.authenticatedRequest("/room-image", {
    action: "delete",
    imageId: Number(imageId),
  });
  if (result.error) {
    showImageFeedback("Xóa ảnh thất bại: " + result.error.message, true);
    return;
  }
  showImageFeedback("Đã xóa ảnh.", false);
  await loadExistingRoomImages(roomId);
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

  try {
    await syncRoomAmenities(roomId, form.amenityIds);
    await uploadPendingRoomImages(roomId, form.name);
  } catch (relatedDataError) {
    console.error("[rooms] Phòng đã cập nhật nhưng tiện nghi hoặc ảnh lưu thất bại:", relatedDataError.message);
    showRoomMessage("Thông tin phòng đã cập nhật nhưng tiện nghi hoặc ảnh chưa lưu đầy đủ: " + relatedDataError.message, true);
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
  clearPendingRoomImages();
  document.getElementById("room-existing-images").replaceChildren();
  showImageFeedback("", false);
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

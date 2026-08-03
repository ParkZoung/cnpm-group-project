(function () {
  'use strict';

  const FALLBACK_ROOM_IMAGE =
    'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=400&q=80';
  let latestRequestId = 0;
  let metadata = { branches: [], roomTypes: [] };

  document.addEventListener('DOMContentLoaded', initializeAvailabilitySearch, { once: true });

  async function initializeAvailabilitySearch() {
    const elements = getElements();
    if (!elements) return;

    setMinimumDates(elements);
    bindEvents(elements);
    if (!window.gostaySupabase) {
      showRpcError(elements, 'Không thể khởi tạo dịch vụ tìm kiếm phòng. Vui lòng tải lại trang.');
      return;
    }

    try {
      metadata = await loadFilterMetadata();
      populateMetadataFilters(elements);
      applyUrlValues(elements);
      applyLegacyLocation(elements);
    } catch (error) {
      showRpcError(elements, friendlyError(error));
      return;
    }

    if (hasRequiredSearchValues(elements)) {
      runAvailabilitySearch(elements);
    } else {
      showIncomplete(elements);
    }
  }

  function getElements() {
    const elements = {
      form: document.getElementById('availability-search-form'),
      checkIn: document.getElementById('check-in-filter'),
      checkOut: document.getElementById('check-out-filter'),
      guests: document.getElementById('guests-filter'),
      branch: document.getElementById('branch-filter'),
      roomType: document.getElementById('room-type-filter'),
      minPrice: document.getElementById('min-price-filter'),
      submit: document.querySelector('.btn-apply-filter'),
      validation: document.getElementById('availability-validation-error'),
      incomplete: document.getElementById('catalog-incomplete'),
      loading: document.getElementById('catalog-loading'),
      error: document.getElementById('catalog-error'),
      retry: document.getElementById('catalog-retry'),
      empty: document.getElementById('catalog-empty'),
      count: document.getElementById('catalog-result-count'),
      list: document.getElementById('catalog-room-list')
    };
    return Object.values(elements).every(Boolean) ? elements : null;
  }

  function bindEvents(elements) {
    elements.form.addEventListener('submit', function (event) {
      event.preventDefault();
      runAvailabilitySearch(elements);
    });
    elements.retry.addEventListener('click', function () {
      runAvailabilitySearch(elements);
    });
    elements.checkIn.addEventListener('change', function () {
      elements.checkOut.min = elements.checkIn.value || todayString();
    });
  }

  async function loadFilterMetadata() {
    const results = await Promise.all([
      window.gostaySupabase
        .from('branches')
        .select('id, name, city, address, status')
        .eq('status', 'active')
        .order('name', { ascending: true }),
      window.gostaySupabase
        .from('room_types')
        .select('id, name, capacity')
        .order('name', { ascending: true })
    ]);

    if (results[0].error) throw results[0].error;
    if (results[1].error) throw results[1].error;

    return {
      branches: results[0].data || [],
      roomTypes: results[1].data || []
    };
  }

  function populateMetadataFilters(elements) {
    const selectedBranch = elements.branch.value;
    const selectedRoomType = elements.roomType.value;

    metadata.branches.forEach(function (branch) {
      elements.branch.appendChild(createOption(
        branch.id,
        branch.name + (branch.city ? ' — ' + branch.city : '')
      ));
    });
    metadata.roomTypes.forEach(function (roomType) {
      elements.roomType.appendChild(createOption(
        roomType.id,
        roomType.name + ' (' + roomType.capacity + ' khách)'
      ));
    });

    if (metadata.branches.some(function (branch) {
      return String(branch.id) === selectedBranch;
    })) {
      elements.branch.value = selectedBranch;
    }
    if (metadata.roomTypes.some(function (roomType) {
      return String(roomType.id) === selectedRoomType;
    })) {
      elements.roomType.value = selectedRoomType;
    }
  }

  function applyUrlValues(elements) {
    const params = new URLSearchParams(window.location.search);
    elements.checkIn.value = params.get('check_in') || params.get('checkin') || '';
    elements.checkOut.value = params.get('check_out') || params.get('checkout') || '';
    elements.guests.value = deriveGuests(params);
    elements.branch.value = positiveIntegerParam(params.get('branch_id')) || '';
    elements.roomType.value = positiveIntegerParam(
      params.get('room_type_id') || params.get('room_type')
    ) || '';
    elements.minPrice.value = nonNegativeIntegerParam(params.get('min_price')) || '';
    elements.checkOut.min = elements.checkIn.value || todayString();
  }

  function applyLegacyLocation(elements) {
    if (elements.branch.value) return;

    const params = new URLSearchParams(window.location.search);
    const legacyLocation = params.get('location') || params.get('branch') || params.get('hotel') || '';
    if (!legacyLocation) return;

    const normalized = legacyLocation.trim().toLocaleLowerCase('vi');
    const match = metadata.branches.find(function (branch) {
      const name = String(branch.name).toLocaleLowerCase('vi');
      const city = String(branch.city).toLocaleLowerCase('vi');
      const address = String(branch.address || '').toLocaleLowerCase('vi');
      return name === normalized
        || city === normalized
        || name.includes(normalized)
        || normalized.includes(city)
        || address.includes(normalized);
    });
    if (match) elements.branch.value = String(match.id);
  }

  function deriveGuests(params) {
    const direct = positiveIntegerParam(params.get('guests'));
    if (direct) return direct;

    const adults = nonNegativeIntegerParam(params.get('adults'));
    const children = nonNegativeIntegerParam(params.get('children'));
    const combined = Number(adults || 0) + Number(children || 0);
    return combined >= 1 ? String(combined) : '1';
  }

  async function runAvailabilitySearch(elements) {
    const filters = readAndValidate(elements);
    if (filters.error) {
      showValidationError(elements, filters.error);
      return;
    }

    const requestId = ++latestRequestId;
    showLoading(elements);
    updateUrl(filters);

    const { data, error } = await window.gostaySupabase.rpc('search_available_rooms', {
      p_check_in_date: filters.checkIn,
      p_check_out_date: filters.checkOut,
      p_guests: filters.guests,
      p_branch_id: filters.branchId,
      p_room_type_id: filters.roomTypeId,
      p_min_price: filters.minPrice,
      p_max_price: filters.maxPrice
    });

    if (requestId !== latestRequestId) return;

    if (error) {
      showRpcError(elements, friendlyError(error));
      return;
    }

    renderSuccess(elements, data || [], filters);
  }

  function readAndValidate(elements) {
    const checkIn = elements.checkIn.value;
    const checkOut = elements.checkOut.value;
    const guests = Number(elements.guests.value);
    const minPrice = optionalInteger(elements.minPrice.value);

    if (!checkIn || !checkOut) {
      return { error: 'Vui lòng chọn ngày nhận phòng và ngày trả phòng.' };
    }
    if (checkIn < todayString()) {
      return { error: 'Ngày nhận phòng không được ở trong quá khứ.' };
    }
    if (checkOut <= checkIn) {
      return { error: 'Ngày trả phòng phải sau ngày nhận phòng.' };
    }
    if (!Number.isSafeInteger(guests) || guests < 1) {
      return { error: 'Số khách phải là số nguyên lớn hơn hoặc bằng 1.' };
    }
    if (minPrice === false) {
      return { error: 'Giá phải là số nguyên không âm.' };
    }

    return {
      checkIn: checkIn,
      checkOut: checkOut,
      guests: guests,
      branchId: optionalPositiveInteger(elements.branch.value),
      roomTypeId: optionalPositiveInteger(elements.roomType.value),
      minPrice: minPrice,
      maxPrice: null
    };
  }

  function renderSuccess(elements, rooms, filters) {
    resetStates(elements);
    elements.list.innerHTML = '';
    elements.list.setAttribute('aria-busy', 'false');
    elements.submit.disabled = false;
    elements.submit.textContent = 'Kiểm tra phòng trống';

    if (!rooms.length) {
      elements.empty.hidden = false;
      return;
    }

    rooms.forEach(function (room) {
      elements.list.appendChild(createRoomCard(room, filters));
    });
    elements.count.textContent = 'Tìm thấy ' + rooms.length + ' phòng trống từ '
      + formatDate(filters.checkIn) + ' đến ' + formatDate(filters.checkOut)
      + ' cho ' + filters.guests + ' khách.';
    elements.count.hidden = false;
  }

  function createRoomCard(room, filters) {
    const card = document.createElement('article');
    card.className = 'room-search-card';

    const imageWrap = document.createElement('div');
    imageWrap.className = 'room-img-wrap';
    const image = document.createElement('img');
    image.src = room.image_url || FALLBACK_ROOM_IMAGE;
    image.alt = room.image_alt_text || ('Phòng ' + room.room_number + ' tại ' + room.branch_name);
    image.addEventListener('error', function () {
      if (image.src !== FALLBACK_ROOM_IMAGE) image.src = FALLBACK_ROOM_IMAGE;
    });
    imageWrap.appendChild(image);

    const body = document.createElement('div');
    body.className = 'room-search-body';
    appendElement(body, 'h3', 'Phòng ' + room.room_number + ' — ' + room.room_type_name);
    appendElement(body, 'div', '📍 ' + room.branch_name + ', ' + room.branch_city, 'room-meta');
    appendElement(
      body,
      'div',
      'Sức chứa: ' + room.room_type_capacity + ' khách'
        + (room.room_type_bed_type ? ' • ' + room.room_type_bed_type : ''),
      'room-meta'
    );
    appendElement(body, 'div', formatPrice(room.price_per_night), 'room-price');
    appendElement(body, 'div', 'Còn trống trong thời gian đã chọn', 'room-status status-available');

    const link = document.createElement('a');
    link.className = 'btn-view-detail';
    const params = new URLSearchParams({
      id: String(room.room_id),
      check_in: filters.checkIn,
      check_out: filters.checkOut,
      guests: String(filters.guests)
    });
    link.href = 'room-detail.html?' + params.toString();
    link.textContent = 'Xem chi tiết';
    body.appendChild(link);

    card.appendChild(imageWrap);
    card.appendChild(body);
    return card;
  }

  function updateUrl(filters) {
    const params = new URLSearchParams();
    params.set('check_in', filters.checkIn);
    params.set('check_out', filters.checkOut);
    params.set('guests', String(filters.guests));
    if (filters.branchId !== null) params.set('branch_id', String(filters.branchId));
    if (filters.roomTypeId !== null) params.set('room_type_id', String(filters.roomTypeId));
    if (filters.minPrice !== null) params.set('min_price', String(filters.minPrice));
    window.history.replaceState(null, '', 'search.html?' + params.toString());
  }

  function showIncomplete(elements) {
    resetStates(elements);
    elements.list.innerHTML = '';
    elements.incomplete.hidden = false;
  }

  function showLoading(elements) {
    resetStates(elements);
    elements.list.innerHTML = '';
    elements.loading.hidden = false;
    elements.list.setAttribute('aria-busy', 'true');
    elements.submit.disabled = true;
    elements.submit.textContent = 'Đang kiểm tra...';
  }

  function showValidationError(elements, message) {
    latestRequestId += 1;
    resetStates(elements);
    elements.list.innerHTML = '';
    elements.validation.textContent = message;
    elements.validation.hidden = false;
    elements.submit.disabled = false;
    elements.submit.textContent = 'Kiểm tra phòng trống';
  }

  function showRpcError(elements, message) {
    resetStates(elements);
    elements.list.innerHTML = '';
    elements.list.setAttribute('aria-busy', 'false');
    elements.error.textContent = message;
    elements.error.hidden = false;
    elements.retry.hidden = false;
    elements.submit.disabled = false;
    elements.submit.textContent = 'Kiểm tra phòng trống';
  }

  function resetStates(elements) {
    elements.incomplete.hidden = true;
    elements.loading.hidden = true;
    elements.error.hidden = true;
    elements.retry.hidden = true;
    elements.empty.hidden = true;
    elements.count.hidden = true;
    elements.validation.hidden = true;
  }

  function hasRequiredSearchValues(elements) {
    return Boolean(elements.checkIn.value && elements.checkOut.value && elements.guests.value);
  }

  function setMinimumDates(elements) {
    const today = todayString();
    elements.checkIn.min = today;
    elements.checkOut.min = today;
  }

  function optionalInteger(value) {
    if (value === '') return null;
    if (!/^\d+$/.test(value)) return false;
    const number = Number(value);
    return Number.isSafeInteger(number) ? number : false;
  }

  function optionalPositiveInteger(value) {
    return value === '' ? null : Number(value);
  }

  function positiveIntegerParam(value) {
    return value && /^[1-9]\d*$/.test(value) ? value : '';
  }

  function nonNegativeIntegerParam(value) {
    return value && /^\d+$/.test(value) ? value : '';
  }

  function todayString() {
    const now = new Date();
    return new Date(now.getTime() - now.getTimezoneOffset() * 60000)
      .toISOString().slice(0, 10);
  }

  function createOption(value, label) {
    const option = document.createElement('option');
    option.value = String(value);
    option.textContent = label;
    return option;
  }

  function appendElement(parent, tag, text, className) {
    const element = document.createElement(tag);
    if (className) element.className = className;
    element.textContent = text;
    parent.appendChild(element);
  }

  function formatDate(value) {
    const parts = value.split('-');
    return parts[2] + '/' + parts[1] + '/' + parts[0];
  }

  function formatPrice(value) {
    return Number(value || 0).toLocaleString('vi-VN') + ' VNĐ / đêm';
  }

  function friendlyError(error) {
    const message = String(error && error.message ? error.message : '').toLowerCase();
    if (message.includes('failed to fetch') || message.includes('network')) {
      return 'Không thể kết nối dịch vụ tìm kiếm. Vui lòng kiểm tra mạng và thử lại.';
    }
    if (message.includes('date range')) return 'Khoảng ngày tìm kiếm không hợp lệ.';
    if (message.includes('guest count')) return 'Số khách tìm kiếm không hợp lệ.';
    if (message.includes('price range')) return 'Khoảng giá tìm kiếm không hợp lệ.';
    return 'Không thể kiểm tra phòng trống. Vui lòng thử lại sau.';
  }
}());

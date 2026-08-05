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
      loadRoomCatalog(elements);
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
      if (hasRequiredSearchValues(elements)) {
        runAvailabilitySearch(elements);
      } else {
        loadRoomCatalog(elements);
      }
    });
    elements.checkIn.addEventListener('change', function () {
      elements.checkOut.min = elements.checkIn.value || todayString();
    });
    elements.branch.addEventListener('change', function () {
      if (!elements.checkIn.value && !elements.checkOut.value) {
        loadRoomCatalog(elements);
      }
    });
    elements.roomType.addEventListener('change', function () {
      if (!elements.checkIn.value && !elements.checkOut.value) loadRoomCatalog(elements);
    });
  }

  async function loadRoomCatalog(elements) {
    const requestId = ++latestRequestId;
    showLoading(elements, false);

    let query = window.gostaySupabase
      .from('rooms')
      .select(`
        id,
        name,
        room_number,
        price_per_night,
        status,
        branch:branches!rooms_branch_id_fkey!inner(id, name, city, status),
        room_type:room_types!rooms_room_type_id_fkey!inner(id, name, capacity, bed_type),
        room_class:room_classes!rooms_room_class_id_fkey!inner(id, name, sort_order, status)
      `)
      .eq('status', 'available')
      .eq('branch.status', 'active')
      .eq('room_class.status', 'active')
      .neq('branch.city', 'New York')
      .order('id', { ascending: false });

    const branchId = optionalPositiveInteger(elements.branch.value);
    if (branchId !== null) query = query.eq('branch_id', branchId);
    const roomTypeId = optionalPositiveInteger(elements.roomType.value);
    if (roomTypeId !== null) query = query.eq('room_type_id', roomTypeId);

    const { data, error } = await query;
    if (requestId !== latestRequestId) return;

    if (error) {
      showRpcError(elements, friendlyError(error));
      return;
    }

    const rooms = (data || []).filter(function (room) {
      return room && room.branch && room.room_type && room.room_class;
    });
    await attachCatalogImages(rooms);
    if (requestId !== latestRequestId) return;

    renderCatalog(elements, rooms);
  }

  async function attachCatalogImages(rooms) {
    const roomIds = rooms.map(function (room) { return room.id; });
    if (!roomIds.length) return;

    const { data, error } = await window.gostaySupabase
      .from('room_images')
      .select('id, room_id, image_url, alt_text, is_primary, sort_order')
      .in('room_id', roomIds)
      .order('is_primary', { ascending: false })
      .order('sort_order', { ascending: true })
      .order('id', { ascending: true });

    if (error) {
      console.warn('[room-catalog] Không thể tải ảnh phòng, đang sử dụng ảnh mặc định.', error);
      return;
    }

    const firstImages = new Map();
    (data || []).forEach(function (image) {
      const key = String(image.room_id);
      if (!firstImages.has(key)) firstImages.set(key, image);
    });
    rooms.forEach(function (room) {
      room.first_image = firstImages.get(String(room.id)) || null;
    });
  }

  function renderCatalog(elements, rooms) {
    resetStates(elements);
    elements.list.innerHTML = '';
    elements.list.setAttribute('aria-busy', 'false');
    elements.submit.disabled = false;
    elements.submit.textContent = 'Kiểm tra phòng trống';

    if (!rooms.length) {
      elements.empty.textContent = 'Hiện chưa có phòng đang hoạt động tại chi nhánh đã chọn.';
      elements.empty.hidden = false;
      return;
    }

    const catalogOfferings = rooms.map(function (room) {
      return {
        room_id: room.id,
        branch_id: room.branch.id,
        room_type_id: room.room_type.id,
        price_per_night: room.price_per_night,
        branch_name: room.branch.name,
        branch_city: room.branch.city,
        room_type_name: room.room_type.name + ' - ' + room.room_class.name,
        room_name: room.name,
        room_type_capacity: room.room_type.capacity,
        room_type_bed_type: room.room_type.bed_type,
        image_url: room.first_image && room.first_image.image_url,
        image_alt_text: room.first_image && room.first_image.alt_text
      };
    });
    const catalogGroups = groupRoomOfferings(catalogOfferings);
    catalogGroups.forEach(function (group) {
      elements.list.appendChild(createGroupedRoomCard(group, null));
    });
    elements.count.textContent = 'Danh sách ' + catalogGroups.length
      + ' phòng. Chọn ngày nhận, ngày trả và số khách để kiểm tra phòng trống.';
    elements.count.hidden = false;
  }

  async function loadFilterMetadata() {
    const results = await Promise.all([
      window.gostaySupabase
        .from('branches')
        .select('id, name, city, address, status')
        .eq('status', 'active')
        .neq('city', 'New York')
        .order('name', { ascending: true }),
      window.gostaySupabase
        .from('room_types')
        .select('id, name')
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

    metadata.branches.forEach(function (branch) {
      elements.branch.appendChild(createOption(
        branch.id,
        branchOptionLabel(branch, metadata.branches)
      ));
    });
    metadata.roomTypes.forEach(function (roomType) {
      elements.roomType.appendChild(createOption(roomType.id, cleanRoomName(roomType.name)));
    });
    if (metadata.branches.some(function (branch) {
      return String(branch.id) === selectedBranch;
    })) {
      elements.branch.value = selectedBranch;
    }
  }

  function applyUrlValues(elements) {
    const params = new URLSearchParams(window.location.search);
    elements.checkIn.value = params.get('check_in') || params.get('checkin') || '';
    elements.checkOut.value = params.get('check_out') || params.get('checkout') || '';
    elements.guests.value = deriveGuests(params);
    elements.branch.value = positiveIntegerParam(params.get('branch_id')) || '';
    elements.roomType.value = positiveIntegerParam(params.get('room_type_id')) || '';
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
    showLoading(elements, true);
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
      elements.empty.textContent = 'Không có phòng trống phù hợp trong thời gian đã chọn.';
      elements.empty.hidden = false;
      return;
    }

    const groupedRooms = groupRoomOfferings(rooms);
    groupedRooms.forEach(function (group) {
      elements.list.appendChild(createGroupedRoomCard(group, filters));
    });
    elements.count.textContent = 'Tìm thấy ' + groupedRooms.length + ' phòng, có '
      + rooms.length + ' hạng còn trống từ '
      + formatDate(filters.checkIn) + ' đến ' + formatDate(filters.checkOut)
      + ' cho ' + filters.guests + ' khách.';
    elements.count.hidden = false;
  }

  function groupRoomOfferings(rooms) {
    const groups = new Map();
    rooms.forEach(function (room) {
      const key = String(room.branch_id) + ':' + String(room.room_type_id);
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(room);
    });
    return Array.from(groups.values()).map(function (variants) {
      variants.sort(function (a, b) {
        return Number(a.price_per_night) - Number(b.price_per_night);
      });
      return variants;
    });
  }

  function splitOfferingName(value) {
    const parts = String(value || '').split(' - ');
    return {
      roomType: cleanRoomName(parts.shift() || ''),
      roomClass: parts.join(' - ') || 'Standard'
    };
  }

  function createGroupedRoomCard(variants, filters) {
    const selectedRoom = variants[0];
    const card = createRoomCard(selectedRoom, filters);
    const body = card.querySelector('.room-search-body');
    const title = body.querySelector('h3');
    const price = body.querySelector('.room-price');
    const detailLink = body.querySelector('.btn-view-detail');
    title.textContent = splitOfferingName(
      selectedRoom.room_name || selectedRoom.room_type_name
    ).roomType;

    const label = document.createElement('label');
    label.className = 'room-variant-label';
    label.appendChild(document.createTextNode('Chọn hạng phòng'));
    const select = document.createElement('select');
    select.className = 'room-variant-select';
    variants.forEach(function (variant) {
      const option = document.createElement('option');
      option.value = String(variant.room_id);
      option.textContent = splitOfferingName(variant.room_type_name).roomClass
        + ' — ' + formatPrice(variant.price_per_night);
      select.appendChild(option);
    });
    label.appendChild(select);
    body.insertBefore(label, price);

    select.addEventListener('change', function () {
      const chosen = variants.find(function (variant) {
        return String(variant.room_id) === select.value;
      }) || variants[0];
      price.textContent = formatPrice(chosen.price_per_night);
      const params = new URLSearchParams(detailLink.href.split('?')[1] || '');
      params.set('id', String(chosen.room_id));
      detailLink.href = 'room-detail.html?' + params.toString();
    });
    return card;
  }

  function createRoomCard(room, filters) {
    const card = document.createElement('article');
    card.className = 'room-search-card';

    const imageWrap = document.createElement('div');
    imageWrap.className = 'room-img-wrap';
    const image = document.createElement('img');
    image.loading = 'lazy';
    image.decoding = 'async';
    image.fetchPriority = 'low';
    image.src = room.image_url || FALLBACK_ROOM_IMAGE;
    image.alt = room.image_alt_text || (cleanRoomName(room.room_type_name) + ' tại ' + room.branch_name);
    image.addEventListener('error', function () {
      if (image.src !== FALLBACK_ROOM_IMAGE) image.src = FALLBACK_ROOM_IMAGE;
    });
    imageWrap.appendChild(image);

    const body = document.createElement('div');
    body.className = 'room-search-body';
    appendElement(body, 'h3', cleanRoomName(room.room_type_name));
    appendElement(body, 'div', '📍 ' + room.branch_name + ', ' + room.branch_city, 'room-meta');
    appendElement(
      body,
      'div',
      'Sức chứa: ' + room.room_type_capacity + ' khách'
        + (room.room_type_bed_type ? ' • ' + room.room_type_bed_type : ''),
      'room-meta'
    );
    appendElement(body, 'div', formatPrice(room.price_per_night), 'room-price');
    appendElement(
      body,
      'div',
      filters ? 'Còn trống trong thời gian đã chọn' : 'Chọn ngày để kiểm tra tình trạng phòng',
      'room-status status-available'
    );

    const link = document.createElement('a');
    link.className = 'btn-view-detail';
    const params = new URLSearchParams({ id: String(room.room_id) });
    if (filters) {
      params.set('check_in', filters.checkIn);
      params.set('check_out', filters.checkOut);
      params.set('guests', String(filters.guests));
    }
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

  function showLoading(elements, checkingAvailability) {
    resetStates(elements);
    elements.list.innerHTML = '';
    elements.loading.textContent = checkingAvailability
      ? 'Đang kiểm tra phòng trống...'
      : 'Đang tải danh sách phòng...';
    elements.loading.hidden = false;
    elements.list.setAttribute('aria-busy', 'true');
    elements.submit.disabled = true;
    elements.submit.textContent = checkingAvailability ? 'Đang kiểm tra...' : 'Đang tải...';
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

  function branchOptionLabel(branch, branches) {
    if (!branch.city) return branch.name;

    const sameCityCount = branches.filter(function (item) {
      return item.city === branch.city;
    }).length;
    const baseLabel = 'GoStay ' + branch.city;

    if (sameCityCount <= 1) return baseLabel;

    const escapedCity = branch.city.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const qualifier = String(branch.name || '')
      .replace(/^GoStay\s*/i, '')
      .replace(new RegExp('\\s*' + escapedCity + '\\s*$', 'i'), '')
      .trim();

    return qualifier ? baseLabel + ' — ' + qualifier : baseLabel;
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

  function cleanRoomName(value) {
    return String(value || 'Thông tin phòng').replace(/\s+\d+\s*$/, '').trim();
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

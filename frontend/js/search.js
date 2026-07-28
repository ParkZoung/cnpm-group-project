(function () {
  'use strict';

  const catalogState = {
    rooms: []
  };
  const FALLBACK_ROOM_IMAGE =
    'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=400&q=80';

  document.addEventListener('DOMContentLoaded', initializeCatalogSearch, { once: true });

  async function initializeCatalogSearch() {
    const elements = getCatalogElements();

    if (!elements) {
      return;
    }

    bindCatalogFilters(elements);

    if (!window.gostaySupabase) {
      showCatalogError(elements, 'Không thể khởi tạo dịch vụ dữ liệu phòng. Vui lòng tải lại trang.');
      return;
    }

    setCatalogLoading(elements, true);

    try {
      const { data, error } = await window.gostaySupabase
        .from('rooms')
        .select(`
          id,
          branch_id,
          room_type_id,
          room_number,
          price_per_night,
          status,
          branch:branches!rooms_branch_id_fkey!inner(id, name, city, status),
          room_type:room_types!rooms_room_type_id_fkey(
            id, name, capacity, bed_type, area_m2
          )
        `)
        .eq('status', 'available')
        .eq('branch.status', 'active')
        .order('branch_id', { ascending: true })
        .order('room_number', { ascending: true });

      if (error) {
        throw error;
      }

      catalogState.rooms = normalizeCatalogRooms(data || []);
      await attachFirstRoomImages(catalogState.rooms);
      populateCatalogFilters(elements);
      applyUrlFilters(elements);
      renderFilteredCatalog(elements);
    } catch (error) {
      showCatalogError(elements, friendlyCatalogError(error));
    } finally {
      setCatalogLoading(elements, false);
    }
  }

  async function attachFirstRoomImages(rooms) {
    const roomIds = rooms.map(function (room) {
      return room.id;
    });

    if (!roomIds.length) {
      return;
    }

    try {
      const { data, error } = await window.gostaySupabase
        .from('room_images')
        .select('id, room_id, image_url, alt_text, sort_order')
        .in('room_id', roomIds)
        .order('sort_order', { ascending: true })
        .order('id', { ascending: true });

      if (error) {
        throw error;
      }

      const firstImages = new Map();
      (data || []).forEach(function (image) {
        const key = String(image.room_id);
        if (!firstImages.has(key)) {
          firstImages.set(key, image);
        }
      });

      rooms.forEach(function (room) {
        room.first_image = firstImages.get(String(room.id)) || null;
      });
    } catch (error) {
      console.warn('[room-catalog] Không thể tải ảnh phòng, đang sử dụng ảnh fallback.', error);
    }
  }

  function getCatalogElements() {
    const elements = {
      form: document.querySelector('.filter-sidebar form'),
      branchFilter: document.getElementById('branch-filter'),
      hotelFilter: document.getElementById('hotel-filter'),
      priceFilter: document.getElementById('price-filter'),
      roomTypeFilters: document.getElementById('room-type-filters'),
      applyButton: document.querySelector('.btn-apply-filter'),
      list: document.getElementById('catalog-room-list'),
      loading: document.getElementById('catalog-loading'),
      error: document.getElementById('catalog-error'),
      empty: document.getElementById('catalog-empty'),
      resultCount: document.getElementById('catalog-result-count')
    };

    return Object.values(elements).every(Boolean) ? elements : null;
  }

  function bindCatalogFilters(elements) {
    if (elements.form.dataset.catalogBound === 'true') {
      return;
    }

    elements.form.dataset.catalogBound = 'true';

    elements.branchFilter.addEventListener('change', function () {
      populateBranchOptions(elements);
    });

    elements.applyButton.addEventListener('click', function () {
      renderFilteredCatalog(elements);
    });

    elements.form.addEventListener('submit', function (event) {
      event.preventDefault();
      renderFilteredCatalog(elements);
    });
  }

  function normalizeCatalogRooms(rows) {
    return rows.filter(function (room) {
      return room
        && Number.isInteger(Number(room.id))
        && room.status === 'available'
        && room.branch
        && room.branch.status === 'active'
        && room.room_type;
    });
  }

  function compactRoomTypeName(name) {
    return String(name || '')
      .replace('Biệt Thự 3 Phòng Ngủ Có Hồ Bơi', 'Villa 3 Phòng Ngủ')
      .replace('Three-Bedroom Pool Villa', 'Villa 3 Phòng Ngủ')
      .replace('Junior Suite Hướng Vườn Giường Đôi', 'Junior Suite Vườn')
      .replace('Junior Suite Hướng Biển Giường Đôi', 'Junior Suite Biển')
      .replace('Junior Suite Garden View', 'Junior Suite Vườn')
      .replace('Junior Suite Ocean View', 'Junior Suite Biển')
      .replace('Deluxe Hướng Vườn 2 Giường Đơn', 'Deluxe Vườn Twin')
      .replace('Deluxe Hướng Vườn Giường Đôi', 'Deluxe Vườn King')
      .replace('Deluxe Hướng Biển 2 Giường Đơn', 'Deluxe Biển Twin')
      .replace('Deluxe Hướng Biển Giường Đôi', 'Deluxe Biển King')
      .replace('Deluxe Hướng Vịnh Giường Đôi', 'Deluxe Vịnh King')
      .replace('Deluxe Garden View Twin', 'Deluxe Vườn Twin')
      .replace('Deluxe Garden View King', 'Deluxe Vườn King')
      .replace('Deluxe Ocean View Twin', 'Deluxe Biển Twin')
      .replace('Deluxe Ocean View King', 'Deluxe Biển King')
      .replace('Deluxe Bay View King', 'Deluxe Vịnh King')
      .replace('Family Suite', 'Phòng Gia Đình');
  }

  function roomTypeCategory(name) {
    const normalizedName = String(name || '').toLocaleLowerCase('vi');

    if (normalizedName.includes('deluxe')) {
      return 'Deluxe';
    }
    if (normalizedName.includes('junior suite')) {
      return 'Junior Suite';
    }
    if (normalizedName.includes('villa') || normalizedName.includes('biệt thự')) {
      return 'Villa';
    }
    if (normalizedName.includes('family') || normalizedName.includes('gia đình')) {
      return 'Gia đình';
    }
    if (normalizedName.includes('vip')) {
      return 'VIP';
    }

    return compactRoomTypeName(name);
  }

  function populateCatalogFilters(elements) {
    const cities = uniqueSorted(catalogState.rooms.map(function (room) {
      return room.branch.city;
    }).filter(Boolean));

    elements.branchFilter.innerHTML = '<option value="">Tất cả chi nhánh</option>';
    cities.forEach(function (city) {
      elements.branchFilter.appendChild(createOption(city, city));
    });

    const roomTypeCategories = new Set();
    catalogState.rooms.forEach(function (room) {
      roomTypeCategories.add(roomTypeCategory(room.room_type.name));
    });

    elements.roomTypeFilters.innerHTML = '';
    Array.from(roomTypeCategories)
      .sort(function (left, right) {
        return left.localeCompare(right, 'vi');
      })
      .forEach(function (category) {
        const label = document.createElement('label');
        const checkbox = document.createElement('input');
        checkbox.type = 'checkbox';
        checkbox.value = category;
        label.appendChild(checkbox);
        label.appendChild(document.createTextNode(' ' + category));
        elements.roomTypeFilters.appendChild(label);
      });

    populateBranchOptions(elements);
  }

  function populateBranchOptions(elements) {
    const selectedCity = elements.branchFilter.value;
    const previousBranchId = elements.hotelFilter.value;
    const branches = new Map();

    catalogState.rooms.forEach(function (room) {
      if (!selectedCity || room.branch.city === selectedCity) {
        branches.set(String(room.branch.id), room.branch.name);
      }
    });

    elements.hotelFilter.innerHTML = '';
    elements.hotelFilter.appendChild(createOption('', selectedCity ? 'Tất cả khách sạn' : 'Chọn chi nhánh trước'));

    Array.from(branches.entries())
      .sort(function (left, right) {
        return String(left[1]).localeCompare(String(right[1]), 'vi');
      })
      .forEach(function (entry) {
        elements.hotelFilter.appendChild(createOption(entry[0], entry[1]));
      });

    elements.hotelFilter.disabled = !selectedCity;

    if (branches.has(previousBranchId)) {
      elements.hotelFilter.value = previousBranchId;
    }
  }

  function applyUrlFilters(elements) {
    const params = new URLSearchParams(window.location.search);
    const requestedLocation = params.get('branch') || params.get('location') || '';
    const requestedHotel = params.get('hotel') || '';
    const matchingRoom = catalogState.rooms.find(function (room) {
      return room.branch.city === requestedLocation || room.branch.name === requestedLocation;
    });

    if (matchingRoom) {
      elements.branchFilter.value = matchingRoom.branch.city;
      populateBranchOptions(elements);
    }

    const matchingBranch = catalogState.rooms.find(function (room) {
      return room.branch.name === requestedHotel;
    });

    if (matchingBranch && matchingBranch.branch.city === elements.branchFilter.value) {
      elements.hotelFilter.value = String(matchingBranch.branch.id);
    }
  }

  function renderFilteredCatalog(elements) {
    const rooms = getFilteredRooms(elements);

    elements.list.innerHTML = '';
    elements.error.hidden = true;
    elements.empty.hidden = rooms.length !== 0;
    elements.resultCount.hidden = false;
    elements.resultCount.textContent = 'Tìm thấy ' + rooms.length + ' phòng phù hợp.';

    rooms.forEach(function (room) {
      elements.list.appendChild(createRoomCard(room));
    });
  }

  function getFilteredRooms(elements) {
    const city = elements.branchFilter.value;
    const branchId = elements.hotelFilter.value;
    const priceRange = elements.priceFilter.value;
    const roomTypeCategories = Array.from(
      elements.roomTypeFilters.querySelectorAll('input[type="checkbox"]:checked')
    ).map(function (checkbox) {
      return checkbox.value;
    });

    return catalogState.rooms.filter(function (room) {
      return (!city || room.branch.city === city)
        && (!branchId || String(room.branch.id) === branchId)
        && (!roomTypeCategories.length
          || roomTypeCategories.includes(roomTypeCategory(room.room_type.name)))
        && priceMatches(Number(room.price_per_night), priceRange);
    });
  }

  function createRoomCard(room) {
    const card = document.createElement('article');
    card.className = 'room-search-card';
    card.dataset.roomId = String(room.id);

    const imageWrap = document.createElement('div');
    imageWrap.className = 'room-img-wrap';

    const image = document.createElement('img');
    image.src = room.first_image && room.first_image.image_url
      ? room.first_image.image_url
      : FALLBACK_ROOM_IMAGE;
    image.alt = room.first_image && room.first_image.alt_text
      ? room.first_image.alt_text
      : 'Phòng ' + room.room_number + ' tại ' + room.branch.name;
    imageWrap.appendChild(image);

    const body = document.createElement('div');
    body.className = 'room-search-body';

    const title = document.createElement('h3');
    title.textContent = 'Phòng ' + room.room_number + ' — '
      + compactRoomTypeName(room.room_type.name);

    const location = document.createElement('div');
    location.className = 'room-meta';
    location.textContent = '📍 ' + room.branch.name + ', ' + room.branch.city;

    const details = document.createElement('div');
    details.className = 'room-meta';
    details.textContent = 'Sức chứa: ' + room.room_type.capacity + ' khách'
      + (room.room_type.bed_type ? ' • ' + room.room_type.bed_type : '');

    const price = document.createElement('div');
    price.className = 'room-price';
    price.textContent = formatPrice(room.price_per_night) + ' / đêm';

    const status = document.createElement('div');
    status.className = 'room-status status-available';
    status.textContent = 'Đang hoạt động';

    const detailLink = document.createElement('a');
    detailLink.className = 'btn-view-detail';
    detailLink.href = 'room-detail.html?id=' + encodeURIComponent(room.id);
    detailLink.textContent = 'Xem chi tiết';

    body.appendChild(title);
    body.appendChild(location);
    body.appendChild(details);
    body.appendChild(price);
    body.appendChild(status);
    body.appendChild(detailLink);
    card.appendChild(imageWrap);
    card.appendChild(body);

    return card;
  }

  function setCatalogLoading(elements, isLoading) {
    elements.loading.hidden = !isLoading;
    elements.list.setAttribute('aria-busy', String(isLoading));
  }

  function showCatalogError(elements, message) {
    elements.list.innerHTML = '';
    elements.empty.hidden = true;
    elements.resultCount.hidden = true;
    elements.error.textContent = message;
    elements.error.hidden = false;
  }

  function friendlyCatalogError(error) {
    const message = String(error && error.message ? error.message : '').toLowerCase();

    if (message.includes('failed to fetch') || message.includes('network')) {
      return 'Không thể kết nối dữ liệu phòng. Vui lòng kiểm tra mạng và thử lại.';
    }

    return 'Không thể tải danh sách phòng từ hệ thống. Vui lòng thử lại sau.';
  }

  function priceMatches(price, range) {
    if (!range) {
      return true;
    }

    if (range === '0-500') {
      return price < 500000;
    }

    if (range === '500-1000') {
      return price >= 500000 && price <= 1000000;
    }

    return range === '1000+' ? price > 1000000 : true;
  }

  function createOption(value, label) {
    const option = document.createElement('option');
    option.value = value;
    option.textContent = label;
    return option;
  }

  function uniqueSorted(values) {
    return Array.from(new Set(values)).sort(function (left, right) {
      return String(left).localeCompare(String(right), 'vi');
    });
  }

  function formatPrice(value) {
    return Number(value || 0).toLocaleString('vi-VN') + 'đ';
  }
}());

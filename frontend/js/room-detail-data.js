(function () {
  'use strict';

  window.gostayRoomDetailState = {
    loading: true,
    room: null,
    error: null
  };

  document.addEventListener('DOMContentLoaded', initializeRoomDetail, { once: true });

  async function initializeRoomDetail() {
    const elements = getRoomDetailElements();

    if (!elements) {
      return;
    }

    elements.image.addEventListener('error', function () {
      const fallback = elements.image.dataset.fallbackSrc;
      if (fallback && elements.image.src !== fallback) elements.image.src = fallback;
    });

    const roomId = getRoomIdFromUrl();

    if (roomId.error) {
      showRoomDetailError(elements, roomId.error);
      return;
    }

    if (!window.gostaySupabase) {
      showRoomDetailError(elements, 'Không thể khởi tạo dịch vụ dữ liệu phòng. Vui lòng tải lại trang.');
      return;
    }

    try {
      const { data, error } = await window.gostaySupabase
        .from('rooms')
        .select(`
          id,
          branch_id,
          room_type_id,
          room_class_id,
          room_number,
          name,
          price_per_night,
          description,
          status,
          branch:branches!rooms_branch_id_fkey(
            id, name, address, city, phone, status
          ),
          room_type:room_types!rooms_room_type_id_fkey(
            id, name, description, capacity, bed_type, area_m2, base_price
          ),
          room_class:room_classes!rooms_room_class_id_fkey(
            id, name, description, status
          )
        `)
        .eq('id', roomId.value)
        .eq('status', 'available')
        .maybeSingle();

      if (error) {
        throw error;
      }

      if (!data) {
        showRoomDetailError(
          elements,
          'Phòng không tồn tại hoặc không còn được công khai. Vui lòng chọn phòng khác.'
        );
        return;
      }

      if (!isPublicRoom(data)) {
        showRoomDetailError(
          elements,
          'Phòng không còn ở trạng thái hoạt động hoặc chi nhánh đã ngừng hoạt động.'
        );
        return;
      }

      const roomExtras = await Promise.all([
        loadFirstRoomImage(roomId.value),
        loadRoomAmenities(roomId.value)
      ]);
      data.first_image = roomExtras[0];
      data.amenities = roomExtras[1];
      window.gostayRoomDetailState.loading = false;
      window.gostayRoomDetailState.room = data;
      renderRoomDetail(elements, data);
      document.dispatchEvent(new CustomEvent('gostay:room-loaded', { detail: { room: data } }));
    } catch (error) {
      showRoomDetailError(elements, friendlyRoomDetailError(error));
    }
  }

  async function loadFirstRoomImage(roomId) {
    try {
      const { data, error } = await window.gostaySupabase
        .from('room_images')
        .select('image_url, alt_text, is_primary, sort_order')
        .eq('room_id', roomId)
        .order('is_primary', { ascending: false })
        .order('sort_order', { ascending: true })
        .order('id', { ascending: true })
        .limit(1)
        .maybeSingle();

      if (error) {
        throw error;
      }

      return data || null;
    } catch (error) {
      console.warn('[room-detail] Không thể tải ảnh phòng, đang sử dụng ảnh fallback.', error);
      return null;
    }
  }

  async function loadRoomAmenities(roomId) {
    try {
      const { data, error } = await window.gostaySupabase
        .from('room_amenities')
        .select(`
          amenity:amenities!room_amenities_amenity_id_fkey(
            id, name, icon, description, status
          )
        `)
        .eq('room_id', roomId);

      if (error) throw error;

      return (data || [])
        .map(function (item) { return item.amenity; })
        .filter(function (amenity) { return amenity && amenity.status === 'active'; })
        .sort(function (left, right) {
          return String(left.name).localeCompare(String(right.name), 'vi');
        });
    } catch (error) {
      console.warn('[room-detail] Không thể tải tiện nghi phòng.', error);
      return [];
    }
  }

  function getRoomIdFromUrl() {
    const rawId = new URLSearchParams(window.location.search).get('id');

    if (rawId === null || rawId.trim() === '') {
      return { error: 'Thiếu mã phòng. Vui lòng quay lại trang tìm kiếm và chọn một phòng.' };
    }

    if (!/^[1-9]\d*$/.test(rawId)) {
      return { error: 'Thông tin phòng không hợp lệ. Vui lòng chọn lại phòng từ trang tìm kiếm.' };
    }

    const roomId = Number(rawId);

    if (!Number.isSafeInteger(roomId)) {
      return { error: 'Thông tin phòng không hợp lệ. Vui lòng chọn lại phòng từ trang tìm kiếm.' };
    }

    return { value: roomId };
  }

  function getRoomDetailElements() {
    const elements = {
      loading: document.getElementById('room-detail-loading'),
      error: document.getElementById('room-detail-error'),
      errorMessage: document.getElementById('room-detail-error-message'),
      content: document.getElementById('room-detail-content'),
      widget: document.getElementById('room-booking-widget'),
      title: document.getElementById('room-detail-title'),
      meta: document.getElementById('room-detail-meta'),
      specs: document.getElementById('room-detail-specs'),
      description: document.getElementById('room-detail-description'),
      roomTypeDescription: document.getElementById('room-type-description'),
      amenities: document.getElementById('room-detail-amenities'),
      amenitiesList: document.getElementById('room-amenities-list'),
      price: document.getElementById('room-estimated-price'),
      image: document.querySelector('#room-detail-content .detail-gallery img')
    };

    return Object.values(elements).every(Boolean) ? elements : null;
  }

  function isPublicRoom(room) {
    return room.status === 'available'
      && room.branch
      && room.branch.status === 'active'
      && room.room_type
      && Number(room.room_type.capacity) > 0;
  }

  function renderRoomDetail(elements, room) {
    const roomLabel = cleanDisplayText(room.name || room.room_type.name).replace(/\s+\d+\s*$/, '').trim();
    document.title = roomLabel + ' - ' + room.branch.name + ' | GoStay';

    elements.title.textContent = roomLabel;
    if (room.first_image && room.first_image.image_url) {
      elements.image.src = room.first_image.image_url;
    }
    elements.image.alt = room.first_image && room.first_image.alt_text
      ? room.first_image.alt_text
      : roomLabel + ' tại ' + room.branch.name;
    elements.meta.innerHTML = '';
    appendTextItem(elements.meta, '📍 ' + room.branch.name + ', ' + room.branch.city);
    appendTextItem(elements.meta, '🏨 ' + room.room_type.name + ' · ' + (room.room_class ? room.room_class.name : 'Standard'));
    appendTextItem(elements.meta, 'Trạng thái: Phòng đang hoạt động');

    elements.specs.innerHTML = '';
    appendRoomSpec(elements.specs, 'Sức chứa', room.room_type.capacity + ' khách');
    appendRoomSpec(elements.specs, 'Loại giường', room.room_type.bed_type || 'Chưa cập nhật');
    appendRoomSpec(
      elements.specs,
      'Diện tích',
      room.room_type.area_m2 ? room.room_type.area_m2 + ' m²' : 'Chưa cập nhật'
    );

    elements.description.textContent = cleanDisplayText(room.description) || 'Không gian nghỉ tiện nghi tại hệ thống GoStay.';
    elements.roomTypeDescription.textContent =
      cleanDisplayText(room.room_type.description) || 'Thông tin hạng phòng đang được cập nhật.';

    const displayAmenities = buildDisplayAmenities(room);
    elements.amenitiesList.replaceChildren();
    displayAmenities.forEach(function (amenity) {
      const item = document.createElement('li');
      item.textContent = '✓ ' + amenity.name;
      elements.amenitiesList.appendChild(item);
      item.textContent = amenity.name;
      item.dataset.icon = amenityIcon(amenity.name);
    });
    elements.amenities.hidden = false;

    elements.price.textContent = formatRoomPrice(room.price_per_night);
    elements.loading.hidden = true;
    elements.error.hidden = true;
    elements.content.hidden = false;
    elements.widget.hidden = false;
  }

  function showRoomDetailError(elements, message) {
    window.gostayRoomDetailState.loading = false;
    window.gostayRoomDetailState.room = null;
    window.gostayRoomDetailState.error = message;
    elements.loading.hidden = true;
    elements.content.hidden = true;
    elements.widget.hidden = true;
    elements.errorMessage.textContent = message;
    elements.error.hidden = false;
    document.dispatchEvent(new CustomEvent('gostay:room-error', { detail: { message: message } }));
  }

  function friendlyRoomDetailError(error) {
    const message = String(error && error.message ? error.message : '').toLowerCase();

    if (message.includes('failed to fetch') || message.includes('network')) {
      return 'Không thể kết nối dữ liệu phòng. Vui lòng kiểm tra mạng và thử lại.';
    }

    return 'Không thể tải thông tin phòng từ hệ thống. Vui lòng thử lại sau.';
  }

  function appendTextItem(container, text) {
    const item = document.createElement('p');
    item.textContent = text;
    container.appendChild(item);
  }

  function appendRoomSpec(container, label, value) {
    const item = document.createElement('div');
    item.className = 'room-spec';

    const labelElement = document.createElement('span');
    labelElement.textContent = label;

    const valueElement = document.createElement('strong');
    valueElement.textContent = value;

    item.appendChild(labelElement);
    item.appendChild(valueElement);
    container.appendChild(item);
  }

  function formatRoomPrice(price) {
    return Number(price || 0).toLocaleString('vi-VN') + ' VNĐ / đêm';
  }

  function buildDisplayAmenities(room) {
    const catalog = new Map();
    (room.amenities || []).forEach(function (amenity) {
      catalog.set(String(amenity.name).toLocaleLowerCase('vi'), amenity);
    });

    const common = [
      { name: 'Wi-Fi tốc độ cao' },
      { name: 'Điều hòa không khí' },
      { name: 'TV màn hình phẳng' },
      { name: 'Phòng tắm riêng' }
    ];
    const typeName = String(room.room_type && room.room_type.name || '').toLowerCase();
    const className = String(room.room_class && room.room_class.name || '').toLowerCase();
    const tailored = [];

    if (typeName.includes('family')) {
      tailored.push({ name: 'Không gian gia đình' }, { name: 'Khu vực sinh hoạt' });
    } else if (typeName.includes('suite')) {
      tailored.push({ name: 'Khu tiếp khách riêng' }, { name: 'Bàn làm việc' });
    } else {
      tailored.push({ name: 'Tủ quần áo' }, { name: 'Bàn làm việc' });
    }

    if (['deluxe', 'premium', 'luxury'].some(function (name) { return className.includes(name); })) {
      tailored.push({ name: 'Minibar trong phòng' }, { name: 'Áo choàng & dép đi trong phòng' });
    }

    common.concat(tailored).forEach(function (amenity) {
      const key = amenity.name.toLocaleLowerCase('vi');
      if (!catalog.has(key)) catalog.set(key, amenity);
    });
    return Array.from(catalog.values()).slice(0, 8);
  }

  function amenityIcon(name) {
    const value = String(name || '').toLocaleLowerCase('vi');
    if (value.includes('wi-fi') || value.includes('wifi')) return '📶';
    if (value.includes('điều hòa')) return '❄️';
    if (value.includes('tv') || value.includes('tivi')) return '📺';
    if (value.includes('tắm')) return '🚿';
    if (value.includes('tiếp khách') || value.includes('sinh hoạt')) return '🛋️';
    if (value.includes('làm việc')) return '💼';
    if (value.includes('gia đình')) return '👪';
    if (value.includes('minibar')) return '🥤';
    if (value.includes('tủ quần áo')) return '👔';
    if (value.includes('áo choàng') || value.includes('dép')) return '🩴';
    if (value.includes('đỗ xe')) return '🅿️';
    if (value.includes('két')) return '🔐';
    if (value.includes('ăn sáng') || value.includes('nhà hàng')) return '🍽️';
    return '✨';
  }

  function cleanDisplayText(value) {
    return String(value || '').replace(/\[GOSTAY_DEMO_V1\]/gi, '').replace(/\s{2,}/g, ' ').trim();
  }
}());

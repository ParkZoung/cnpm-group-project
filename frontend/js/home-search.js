document.addEventListener('DOMContentLoaded', function () {
  const searchBox = document.querySelector('.search-box');
  if (!searchBox) return;

  const triggers = searchBox.querySelectorAll('.search-trigger');
  const panels = searchBox.querySelectorAll('.search-panel');

  function closePanels(exceptId) {
    panels.forEach(function (panel) {
      if (panel.id !== exceptId) panel.hidden = true;
    });
    triggers.forEach(function (trigger) {
      trigger.setAttribute('aria-expanded', trigger.dataset.panel === exceptId ? 'true' : 'false');
    });
  }

  triggers.forEach(function (trigger) {
    trigger.addEventListener('click', function () {
      const panel = document.getElementById(trigger.dataset.panel);
      const willOpen = panel.hidden;
      closePanels(willOpen ? panel.id : null);
      panel.hidden = !willOpen;
    });
  });

  document.addEventListener('click', function (event) {
    if (!event.composedPath().includes(searchBox)) closePanels();
  });

  searchBox.querySelectorAll('.place-option').forEach(function (option) {
    option.addEventListener('click', function () {
      const displayLabel = option.querySelector('strong');
      document.getElementById('destination-value').textContent = displayLabel
        ? displayLabel.textContent
        : option.dataset.place;
      document.getElementById('destination-input').value = option.dataset.place;
      closePanels();
    });
  });

  let guestCount = 1;

  searchBox.querySelectorAll('.guest-row button').forEach(function (button) {
    button.addEventListener('click', function () {
      const row = button.closest('.guest-row');
      guestCount = Math.max(1, Math.min(10, guestCount + Number(button.dataset.change)));
      row.querySelector('b').textContent = guestCount;
      document.getElementById('total-guests-input').value = guestCount;
      document.getElementById('guests-value').textContent = guestCount + ' khách';
    });
  });

  const today = new Date();
  today.setHours(0, 0, 0, 0);
  let checkin = null;
  let checkout = null;
  let visibleMonthOffset = 0;
  const previousMonthButton = document.getElementById('calendar-prev');
  const nextMonthButton = document.getElementById('calendar-next');
  const weekdays = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'CN'];

  function isoDate(date) {
    const offsetDate = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
    return offsetDate.toISOString().slice(0, 10);
  }

  function shortDate(date) {
    return String(date.getDate()).padStart(2, '0') + '/' + String(date.getMonth() + 1).padStart(2, '0');
  }

  function renderCalendar() {
    const months = document.getElementById('calendar-months');
    months.innerHTML = '';
    previousMonthButton.disabled = visibleMonthOffset === 0;

    [0, 1].forEach(function (offset) {
      const monthDate = new Date(
        today.getFullYear(),
        today.getMonth() + visibleMonthOffset + offset,
        1
      );
      const month = document.createElement('div');
      month.className = 'calendar-month';
      month.innerHTML = '<h4>tháng ' + (monthDate.getMonth() + 1) + ' năm ' + monthDate.getFullYear() + '</h4>';
      const grid = document.createElement('div');
      grid.className = 'calendar-grid';
      weekdays.forEach(function (day) {
        const label = document.createElement('span');
        label.textContent = day;
        grid.appendChild(label);
      });

      const firstDay = (monthDate.getDay() + 6) % 7;
      for (let blank = 0; blank < firstDay; blank += 1) grid.appendChild(document.createElement('i'));
      const totalDays = new Date(monthDate.getFullYear(), monthDate.getMonth() + 1, 0).getDate();

      for (let day = 1; day <= totalDays; day += 1) {
        const date = new Date(monthDate.getFullYear(), monthDate.getMonth(), day);
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'calendar-day';
        button.textContent = day;
        button.disabled = date < today;
        button.dataset.date = isoDate(date);
        if ((checkin && date.getTime() === checkin.getTime()) || (checkout && date.getTime() === checkout.getTime())) button.classList.add('selected');
        if (checkin && checkout && date > checkin && date < checkout) button.classList.add('in-range');
        button.addEventListener('click', function () { selectDate(date); });
        grid.appendChild(button);
      }
      month.appendChild(grid);
      months.appendChild(month);
    });
  }

  previousMonthButton.addEventListener('click', function () {
    if (visibleMonthOffset === 0) return;
    visibleMonthOffset -= 1;
    renderCalendar();
  });

  nextMonthButton.addEventListener('click', function () {
    visibleMonthOffset += 1;
    renderCalendar();
  });

  function selectDate(date) {
    if (!checkin || checkout || date <= checkin) {
      checkin = date;
      checkout = null;
      document.getElementById('checkin-value').textContent = shortDate(date);
      document.getElementById('checkout-value').textContent = 'Trả phòng';
      document.getElementById('checkin-input').value = isoDate(date);
      document.getElementById('checkout-input').value = '';
      document.getElementById('calendar-hint').textContent = 'Chọn ngày trả phòng';
    } else {
      checkout = date;
      document.getElementById('checkout-value').textContent = shortDate(date);
      document.getElementById('checkout-input').value = isoDate(date);
      document.getElementById('calendar-hint').textContent = 'Đã chọn ngày nhận và trả phòng';
      setTimeout(closePanels, 180);
    }
    renderCalendar();
  }

  renderCalendar();

  searchBox.addEventListener('submit', function (event) {
    const checkInValue = document.getElementById('checkin-input').value;
    const checkOutValue = document.getElementById('checkout-input').value;
    if (!checkInValue || !checkOutValue || checkOutValue <= checkInValue) {
      event.preventDefault();
      document.getElementById('calendar-hint').textContent =
        'Vui lòng chọn ngày nhận phòng và ngày trả phòng hợp lệ';
      const calendarPanel = document.getElementById('calendar-panel');
      closePanels(calendarPanel.id);
      calendarPanel.hidden = false;
    }
  });
});

(function () {
  'use strict';

  const FALLBACK_ROOM_IMAGE =
    'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=800&q=80';

  document.addEventListener('DOMContentLoaded', initializeFeaturedRooms, { once: true });

  async function initializeFeaturedRooms() {
    const elements = getFeaturedRoomElements();

    if (!elements) {
      return;
    }

    if (!window.gostaySupabase) {
      showFeaturedError(elements, 'Không thể khởi tạo dịch vụ dữ liệu phòng.');
      return;
    }

    try {
      const { data, error } = await window.gostaySupabase
        .from('rooms')
        .select(`
          id,
          room_number,
          name,
          description,
          price_per_night,
          status,
          branch:branches!rooms_branch_id_fkey!inner(id, name, city, status),
          room_type:room_types!rooms_room_type_id_fkey(id, name)
        `)
        .eq('status', 'available')
        .eq('branch.status', 'active')
        .order('id', { ascending: false })
        .limit(4);

      if (error) {
        throw error;
      }

      const rooms = (data || []).filter(function (room) {
        return room
          && Number.isSafeInteger(Number(room.id))
          && room.status === 'available'
          && room.branch
          && room.branch.status === 'active'
          && room.room_type;
      });

      await attachFirstRoomImages(rooms);
      renderFeaturedRooms(elements, rooms);
    } catch (error) {
      const message = String(error && error.message ? error.message : '').toLowerCase();
      showFeaturedError(
        elements,
        message.includes('failed to fetch') || message.includes('network')
          ? 'Không thể kết nối dữ liệu phòng. Vui lòng kiểm tra mạng và thử lại.'
          : 'Không thể tải phòng nổi bật. Vui lòng thử lại sau.'
      );
    }
  }

  function getFeaturedRoomElements() {
    const elements = {
      list: document.getElementById('featured-room-list'),
      loading: document.getElementById('featured-rooms-loading'),
      empty: document.getElementById('featured-rooms-empty'),
      error: document.getElementById('featured-rooms-error')
    };

    return Object.values(elements).every(Boolean) ? elements : null;
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
        .select('id, room_id, image_url, alt_text, is_primary, sort_order')
        .in('room_id', roomIds)
        .order('is_primary', { ascending: false })
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
      console.warn('[featured-rooms] Không thể tải ảnh phòng, đang sử dụng ảnh fallback.', error);
    }
  }

  function renderFeaturedRooms(elements, rooms) {
    elements.list.innerHTML = '';
    rooms.forEach(function (room) {
      elements.list.appendChild(createFeaturedRoomCard(room));
    });

    elements.loading.hidden = true;
    elements.empty.hidden = rooms.length !== 0;
    elements.error.hidden = true;
    elements.list.setAttribute('aria-busy', 'false');
  }

  function createFeaturedRoomCard(room) {
    const card = document.createElement('article');
    card.className = 'hotel-card';
    card.dataset.roomId = String(room.id);

    const image = document.createElement('img');
    image.loading = 'lazy';
    image.decoding = 'async';
    image.fetchPriority = 'low';
    image.src = room.first_image && room.first_image.image_url
      ? room.first_image.image_url
      : FALLBACK_ROOM_IMAGE;
    image.alt = room.first_image && room.first_image.alt_text
      ? room.first_image.alt_text
      : roomLabel(room) + ' tại ' + room.branch.name;
    image.addEventListener('error', function () {
      if (image.src !== FALLBACK_ROOM_IMAGE) image.src = FALLBACK_ROOM_IMAGE;
    });

    const body = document.createElement('div');
    body.className = 'hotel-body';

    const title = document.createElement('h3');
    title.textContent = roomLabel(room);

    const sub = document.createElement('div');
    sub.className = 'sub';
    sub.textContent = room.branch.name + ', ' + room.branch.city + ' • ' + room.room_type.name;

    const description = document.createElement('p');
    description.textContent = cleanDisplayText(room.description) || 'Không gian nghỉ tiện nghi tại hệ thống GoStay.';

    const price = document.createElement('div');
    price.className = 'price';
    price.textContent = formatRoomPrice(room.price_per_night);

    const link = document.createElement('a');
    link.className = 'btn btn-detail';
    link.href = 'room-detail.html?id=' + encodeURIComponent(room.id);
    link.textContent = 'Xem chi tiết';

    body.appendChild(title);
    body.appendChild(sub);
    body.appendChild(description);
    body.appendChild(price);
    body.appendChild(link);
    card.appendChild(image);
    card.appendChild(body);

    return card;
  }

  function showFeaturedError(elements, message) {
    elements.list.innerHTML = '';
    elements.loading.hidden = true;
    elements.empty.hidden = true;
    elements.error.textContent = message;
    elements.error.hidden = false;
    elements.list.setAttribute('aria-busy', 'false');
  }

  function roomLabel(room) {
    return cleanDisplayText(room.name || room.room_type.name).replace(/\s+\d+\s*$/, '').trim();
  }

  function cleanDisplayText(value) {
    return String(value || '').replace(/\[GOSTAY_DEMO_V1\]/gi, '').replace(/\s{2,}/g, ' ').trim();
  }

  function formatRoomPrice(value) {
    return Number(value || 0).toLocaleString('vi-VN') + ' VNĐ / đêm';
  }
}());

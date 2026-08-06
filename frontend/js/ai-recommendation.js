(function () {
  'use strict';

  const INITIAL_RESULT_COUNT = 3;
  const MAX_RESULT_COUNT = 10;
  const FALLBACK_ROOM_IMAGE =
    'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=800&q=80';

  document.addEventListener('DOMContentLoaded', initialize, { once: true });

  function initialize() {
    const elements = getElements();
    if (!elements) return;

    let recommendations = [];
    let lastPayload = null;

    const branchesReady = loadBranches(elements);

    elements.form.addEventListener('submit', async function (event) {
      event.preventDefault();
      await branchesReady;
      const payload = buildPayload(elements);
      if (payload.error) {
        showValidation(elements, payload.error);
        return;
      }

      lastPayload = payload.value;
      requestRecommendations(elements, lastPayload).then(function (rooms) {
        if (rooms === null) return;
        recommendations = rooms;
        renderRecommendations(elements, recommendations, INITIAL_RESULT_COUNT, lastPayload);
      });
    });

    elements.retry.addEventListener('click', function () {
      if (!lastPayload) return;
      requestRecommendations(elements, lastPayload).then(function (rooms) {
        if (rooms === null) return;
        recommendations = rooms;
        renderRecommendations(elements, recommendations, INITIAL_RESULT_COUNT, lastPayload);
      });
    });

    elements.more.addEventListener('click', function () {
      renderRecommendations(elements, recommendations, MAX_RESULT_COUNT, lastPayload);
    });

    elements.dismiss.addEventListener('click', function () {
      recommendations = [];
      elements.content.innerHTML = '';
      elements.result.hidden = true;
      elements.need.focus();
    });

  }

  function getElements() {
    const elements = {
      form: document.getElementById('ai-room-suggestion-form'),
      need: document.getElementById('ai-room-needs'),
      submit: document.getElementById('ai-room-submit'),
      validation: document.getElementById('ai-room-validation'),
      loading: document.getElementById('ai-room-loading'),
      error: document.getElementById('ai-room-error'),
      errorMessage: document.getElementById('ai-room-error-message'),
      retry: document.getElementById('ai-room-retry'),
      result: document.getElementById('ai-room-result'),
      content: document.getElementById('ai-room-result-content'),
      dismiss: document.getElementById('ai-room-dismiss'),
      more: document.getElementById('ai-room-more'),
      homeCheckIn: document.getElementById('checkin-input'),
      homeCheckOut: document.getElementById('checkout-input'),
      homeGuests: document.getElementById('total-guests-input'),
      homeDestination: document.getElementById('destination-input'),
      branches: []
    };
    const required = [
      'form', 'need', 'submit', 'validation', 'loading', 'error', 'errorMessage',
      'retry', 'result', 'content', 'dismiss', 'more'
    ];
    return required.every(function (key) { return Boolean(elements[key]); }) ? elements : null;
  }

  async function loadBranches(elements) {
    if (!window.gostaySupabase) return;

    try {
      const response = await window.gostaySupabase
        .from('branches')
        .select('id, name, city')
        .eq('status', 'active')
        .order('name', { ascending: true });
      if (response.error) throw response.error;

      (response.data || []).forEach(function (branch) {
        elements.branches.push({
          id: Number(branch.id),
          searchText: normalizeText([branch.name, branch.city].filter(Boolean).join(' '))
        });
      });
    } catch (error) {
      console.warn('[ai-recommendation] Không thể tải danh sách chi nhánh.', error);
    }
  }

  function homepageBranchId(elements) {
    const destination = normalizeText(valueOf(elements.homeDestination));
    if (!destination) return null;
    const destinationCore = destination.replace(/^gostay\s+/, '');

    const match = elements.branches.find(function (branch) {
      const text = branch.searchText;
      return text && (
        text.includes(destination) ||
        destination.includes(text) ||
        (destinationCore && text.includes(destinationCore))
      );
    });
    return match ? match.id : null;
  }

  function buildPayload(elements) {
    const need = elements.need.value.trim();
    const checkIn = valueOf(elements.homeCheckIn);
    const checkOut = valueOf(elements.homeCheckOut);
    const formGuests = positiveInteger(valueOf(elements.homeGuests));
    const requestedGuests = readRequestedGuests(need);
    const guests = formGuests ? Math.max(formGuests, requestedGuests || 0) : null;
    const areaConstraint = readRequestedAreaConstraint(need);
    const branchId = homepageBranchId(elements);

    if (!need) return { error: 'Vui lòng mô tả nhu cầu về phòng.' };
    if (!validIsoDate(checkIn) || !validIsoDate(checkOut)) {
      return { error: 'Vui lòng chọn ngày nhận và ngày trả tại form tìm kiếm phía trên.' };
    }
    if (checkOut <= checkIn) return { error: 'Ngày trả phòng phải sau ngày nhận phòng.' };
    if (!guests) return { error: 'Vui lòng bổ sung số khách tại form tìm kiếm phía trên.' };

    const result = {
      value: {
        need: need,
        check_in_date: checkIn,
        check_out_date: checkOut,
        guests: guests,
        branch_id: branchId,
        min_price: null,
        max_price: null
      }
    };
    if (areaConstraint) {
      result.value.minimum_area_m2 = areaConstraint.value;
      result.value.area_exclusive = areaConstraint.exclusive;
    }
    return result;
  }

  async function requestRecommendations(elements, payload) {
    showLoading(elements);
    if (!window.gostaySupabase) {
      showRequestError(elements, 'Không thể khởi tạo dịch vụ gợi ý. Vui lòng tải lại trang.');
      return null;
    }

    try {
      const response = await window.gostaySupabase.functions.invoke('recommend-rooms', {
        body: payload
      });
      if (response.error) throw response.error;

      const appliedGuests = Number(
        response.data && response.data.appliedCriteria && response.data.appliedCriteria.guests
      );
      if (Number.isSafeInteger(appliedGuests) && appliedGuests > payload.guests) {
        payload.guests = appliedGuests;
      }
      const appliedAreaM2 = Number(
        response.data && response.data.appliedCriteria && response.data.appliedCriteria.minimum_area_m2
      );
      if (Number.isFinite(appliedAreaM2) && appliedAreaM2 > 0) {
        payload.minimum_area_m2 = appliedAreaM2;
        payload.area_exclusive = Boolean(response.data.appliedCriteria.area_exclusive);
      }

      const rooms = response.data && Array.isArray(response.data.recommendations)
        ? response.data.recommendations.slice(0, MAX_RESULT_COUNT)
        : [];
      return rooms.filter(function (room) {
        return isValidRecommendation(room) &&
          Number(room.room_type_capacity) >= payload.guests &&
          (!payload.minimum_area_m2 || (payload.area_exclusive
            ? Number(room.room_type_area_m2) > payload.minimum_area_m2
            : Number(room.room_type_area_m2) >= payload.minimum_area_m2));
      });
    } catch (error) {
      showRequestError(elements, friendlyError(error));
      return null;
    }
  }

  function renderRecommendations(elements, rooms, visibleCount, payload) {
    elements.content.innerHTML = '';
    rooms.slice(0, visibleCount).forEach(function (room, index) {
      elements.content.appendChild(createRoomCard(room, index, payload));
    });

    if (!rooms.length) {
      appendText(
        elements.content,
        'p',
        'Không tìm thấy phòng trống phù hợp với các tiêu chí đã chọn.',
        'ai-room-assistant__empty'
      );
    }

    elements.loading.hidden = true;
    elements.loading.setAttribute('aria-busy', 'false');
    elements.submit.disabled = false;
    elements.error.hidden = true;
    elements.result.hidden = false;
    elements.more.hidden = rooms.length <= INITIAL_RESULT_COUNT || visibleCount >= rooms.length;
  }

  function createRoomCard(room, index, payload) {
    const card = document.createElement('article');
    card.className = 'ai-recommendation-card';
    card.dataset.roomId = String(room.room_id);

    const image = document.createElement('img');
    image.loading = 'lazy';
    image.decoding = 'async';
    image.fetchPriority = 'low';
    image.alt = room.image_alt_text || roomLabel(room) + ' tại ' + room.branch_name;
    image.addEventListener('error', function handleImageError() {
      image.removeEventListener('error', handleImageError);
      image.src = FALLBACK_ROOM_IMAGE;
    });
    image.src = room.image_url || FALLBACK_ROOM_IMAGE;

    const body = document.createElement('div');
    body.className = 'ai-recommendation-card__body';
    appendText(body, 'h3', '#' + (index + 1) + ' ' + roomLabel(room));
    appendText(body, 'div', room.branch_name + ', ' + room.branch_city, 'ai-recommendation-card__meta');
    appendText(
      body,
      'div',
      room.room_type_name + ' · ' + room.room_type_area_m2 + ' m² · Tối đa ' +
        room.room_type_capacity + ' khách',
      'ai-recommendation-card__meta'
    );
    appendText(
      body,
      'div',
      Number(room.price_per_night).toLocaleString('vi-VN') + ' VND / đêm',
      'ai-recommendation-card__price'
    );
    appendText(body, 'p', room.ai_reason, 'ai-recommendation-card__reason');

    const link = document.createElement('a');
    link.className = 'ai-recommendation-card__link';
    link.textContent = 'Xem chi tiết';
    link.href = 'room-detail.html?' + new URLSearchParams({
      id: String(room.room_id),
      check_in: payload.check_in_date,
      check_out: payload.check_out_date,
      guests: String(payload.guests)
    }).toString();
    body.appendChild(link);

    card.appendChild(image);
    card.appendChild(body);
    return card;
  }

  function showLoading(elements) {
    elements.validation.hidden = true;
    elements.loading.hidden = false;
    elements.error.hidden = true;
    elements.result.hidden = true;
    elements.submit.disabled = true;
    elements.loading.setAttribute('aria-busy', 'true');
  }

  function showValidation(elements, message) {
    elements.validation.textContent = message;
    elements.validation.hidden = false;
    elements.error.hidden = true;
    elements.result.hidden = true;
  }

  function showRequestError(elements, message) {
    elements.loading.hidden = true;
    elements.loading.setAttribute('aria-busy', 'false');
    elements.submit.disabled = false;
    elements.errorMessage.textContent = message;
    elements.error.hidden = false;
    elements.result.hidden = true;
  }

  function friendlyError(error) {
    const message = String(error && error.message ? error.message : '').toLowerCase();
    if (message.includes('failed to fetch') || message.includes('network')) {
      return 'Không thể kết nối dịch vụ gợi ý. Vui lòng kiểm tra mạng và thử lại.';
    }
    return 'GoStay chưa thể tạo gợi ý lúc này. Vui lòng thử lại.';
  }

  function isValidRecommendation(room) {
    return room &&
      Number.isSafeInteger(Number(room.room_id)) &&
      Number(room.room_id) > 0 &&
      typeof room.ai_reason === 'string' &&
      Boolean(room.ai_reason.trim()) &&
      Number.isFinite(Number(room.price_per_night));
  }

  function appendText(parent, tag, text, className) {
    const element = document.createElement(tag);
    if (className) element.className = className;
    element.textContent = text;
    parent.appendChild(element);
  }

  function roomLabel(room) {
    return String(room.room_name || room.room_type_name || 'Thông tin phòng')
      .replace(/\s+\d+\s*$/, '')
      .trim();
  }

  function valueOf(input) {
    return input ? String(input.value || '').trim() : '';
  }

  function validIsoDate(value) {
    return /^\d{4}-\d{2}-\d{2}$/.test(String(value || ''));
  }

  function positiveInteger(value) {
    if (!/^[1-9]\d*$/.test(String(value || ''))) return null;
    const number = Number(value);
    return Number.isSafeInteger(number) ? number : null;
  }

  function normalizeText(value) {
    return String(value || '')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLocaleLowerCase('vi')
      .trim();
  }

  function readRequestedGuests(need) {
    const normalized = normalizeText(need).replace(/đ/g, 'd');
    const match = normalized.match(
      /\b(tren|hon|tu|it nhat|toi thieu|khoang)?\s*(\d{1,2})\s*(?:nguoi|khach)\b/
    );
    if (!match) return null;

    const guests = Number(match[2]);
    if (!Number.isSafeInteger(guests) || guests < 1) return null;
    return /^(tren|hon)$/.test(match[1] || '') ? guests + 1 : guests;
  }

  function readRequestedAreaConstraint(need) {
    const normalized = normalizeText(need).replace(/đ/g, 'd').replace(/²/g, '2');
    const match = normalized.match(
      /\b(tren|hon|tu|it nhat|toi thieu|khoang)?\s*(\d{1,4}(?:[.,]\d+)?)\s*(?:m2|met vuong)\b/
    );
    if (!match) return null;

    const areaM2 = Number(match[2].replace(',', '.'));
    if (!Number.isFinite(areaM2) || areaM2 <= 0) return null;
    return {
      value: areaM2,
      exclusive: /^(tren|hon)$/.test(match[1] || '')
    };
  }
}());

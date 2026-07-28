(function () {
  'use strict';

  const CART_KEY = 'gostayCart';

  document.addEventListener('DOMContentLoaded', initializeRoomSelection, { once: true });

  function initializeRoomSelection() {
    const form = document.getElementById('room-booking-form');

    if (!form) {
      return;
    }

    removeLegacyCart();

    if (form.dataset.cartBound === 'true') {
      return;
    }

    form.dataset.cartBound = 'true';
    setMinimumDates();
    applySearchValuesFromUrl();
    updateRoomSelectionState();

    document.addEventListener('gostay:room-loaded', updateRoomSelectionState);
    document.addEventListener('gostay:room-error', updateRoomSelectionState);

    form.addEventListener('submit', handleRoomSelection);
  }

  function handleRoomSelection(event) {
    event.preventDefault();

    const form = event.currentTarget;
    const room = getLoadedRoom();
    const checkInInput = document.getElementById('check-in-date');
    const checkOutInput = document.getElementById('check-out-date');
    const guestInput = document.getElementById('guest-count');
    const submitButton = document.getElementById('room-booking-submit');
    const errorElement = document.getElementById('room-booking-error');

    if (!room || !checkInInput || !checkOutInput || !guestInput || !submitButton || !errorElement) {
      showRoomSelectionError(errorElement, 'Thông tin phòng chưa sẵn sàng. Vui lòng tải lại trang.');
      return;
    }

    const validationError = validateRoomSelection(
      checkInInput.value,
      checkOutInput.value,
      guestInput.value,
      Number(room.room_type.capacity)
    );

    if (validationError) {
      showRoomSelectionError(errorElement, validationError);
      return;
    }

    const cart = {
      room_id: Number(room.id),
      check_in_date: checkInInput.value,
      check_out_date: checkOutInput.value,
      number_of_guests: Number(guestInput.value),
      display: {
        room_number: String(room.room_number),
        branch_name: String(room.branch.name),
        room_type_name: String(room.room_type.name),
        estimated_price_per_night: Number(room.price_per_night)
      }
    };

    submitButton.disabled = true;
    submitButton.textContent = 'Đang chuyển đến đặt phòng...';
    errorElement.hidden = true;
    localStorage.setItem(CART_KEY, JSON.stringify(cart));
    window.location.assign('booking.html');
  }

  function validateRoomSelection(checkIn, checkOut, guestValue, capacity) {
    if (!checkIn || !checkOut) {
      return 'Vui lòng chọn ngày nhận phòng và ngày trả phòng.';
    }

    const today = getTodayDateString();

    if (checkIn < today) {
      return 'Ngày nhận phòng không được trước ngày hiện tại.';
    }

    if (checkOut <= checkIn) {
      return 'Ngày trả phòng phải sau ngày nhận phòng.';
    }

    if (!/^[1-9]\d*$/.test(String(guestValue))) {
      return 'Số khách phải là số nguyên lớn hơn 0.';
    }

    const guests = Number(guestValue);

    if (!Number.isSafeInteger(guests) || guests > capacity) {
      return 'Số khách không được vượt quá sức chứa ' + capacity + ' khách của phòng.';
    }

    return '';
  }

  function updateRoomSelectionState() {
    const room = getLoadedRoom();
    const submitButton = document.getElementById('room-booking-submit');
    const guestInput = document.getElementById('guest-count');

    if (!submitButton || !guestInput) {
      return;
    }

    submitButton.disabled = !room;
    guestInput.max = room ? String(room.room_type.capacity) : '';
  }

  function getLoadedRoom() {
    const state = window.gostayRoomDetailState;
    const room = state && state.room;

    if (!room
      || !Number.isSafeInteger(Number(room.id))
      || Number(room.id) <= 0
      || room.status !== 'available'
      || !room.branch
      || room.branch.status !== 'active'
      || !room.room_type
      || Number(room.room_type.capacity) <= 0) {
      return null;
    }

    return room;
  }

  function removeLegacyCart() {
    const storedCart = localStorage.getItem(CART_KEY);

    if (!storedCart) {
      return;
    }

    try {
      const cart = JSON.parse(storedCart);

      if (!isCurrentCartShape(cart)) {
        localStorage.removeItem(CART_KEY);
        showRoomSelectionError(
          document.getElementById('room-booking-error'),
          'Dữ liệu phòng đã chọn trước đây không còn hợp lệ. Vui lòng chọn lại ngày và số khách.'
        );
      }
    } catch (error) {
      localStorage.removeItem(CART_KEY);
      showRoomSelectionError(
        document.getElementById('room-booking-error'),
        'Dữ liệu phòng đã chọn trước đây bị lỗi. Vui lòng chọn lại.'
      );
    }
  }

  function isCurrentCartShape(cart) {
    const allowedRootKeys = [
      'room_id',
      'check_in_date',
      'check_out_date',
      'number_of_guests',
      'display'
    ];
    const allowedDisplayKeys = [
      'room_number',
      'branch_name',
      'room_type_name',
      'estimated_price_per_night'
    ];

    return cart
      && !Array.isArray(cart)
      && Number.isSafeInteger(Number(cart.room_id))
      && Number(cart.room_id) > 0
      && typeof cart.display === 'object'
      && cart.display !== null
      && Object.keys(cart).every(function (key) {
        return allowedRootKeys.includes(key);
      })
      && Object.keys(cart.display).every(function (key) {
        return allowedDisplayKeys.includes(key);
      });
  }

  function setMinimumDates() {
    const checkInInput = document.getElementById('check-in-date');
    const checkOutInput = document.getElementById('check-out-date');
    const today = getTodayDateString();

    if (checkInInput) {
      checkInInput.min = today;
      checkInInput.addEventListener('change', function () {
        if (checkOutInput) {
          checkOutInput.min = checkInInput.value || today;
        }
      });
    }

    if (checkOutInput) {
      checkOutInput.min = today;
    }
  }

  function applySearchValuesFromUrl() {
    const params = new URLSearchParams(window.location.search);
    const checkIn = params.get('check_in') || params.get('checkin') || '';
    const checkOut = params.get('check_out') || params.get('checkout') || '';
    const guests = params.get('guests') || '';
    const checkInInput = document.getElementById('check-in-date');
    const checkOutInput = document.getElementById('check-out-date');
    const guestInput = document.getElementById('guest-count');

    if (checkInInput && /^\d{4}-\d{2}-\d{2}$/.test(checkIn)) {
      checkInInput.value = checkIn;
    }
    if (checkOutInput && /^\d{4}-\d{2}-\d{2}$/.test(checkOut)) {
      checkOutInput.value = checkOut;
      checkOutInput.min = checkIn || getTodayDateString();
    }
    if (guestInput && /^[1-9]\d*$/.test(guests)) {
      guestInput.value = guests;
    }
  }

  function getTodayDateString() {
    const now = new Date();
    const localDate = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
    return localDate.toISOString().slice(0, 10);
  }

  function showRoomSelectionError(errorElement, message) {
    if (!errorElement) {
      return;
    }

    errorElement.textContent = message;
    errorElement.hidden = false;
  }
}());

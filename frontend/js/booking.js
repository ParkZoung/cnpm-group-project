document.addEventListener('DOMContentLoaded', function () {
  renderLatestBookingSuccess();
  renderBookingHistory();

  const bookingForm = document.querySelector('.cart-split-layout');
  const fullNameInput = document.getElementById('full_name');
  const phoneInput = document.getElementById('phone_number');
  const emailInput = document.getElementById('email_address');
  const checkinInput = document.getElementById('checkin_date');
  const checkoutInput = document.getElementById('checkout_date');
  const miniSummary = document.querySelector('.mini-rooms-summary');
  const billingRows = document.querySelectorAll('.billing-row');
  const finalPriceElement = document.querySelector('.billing-final-price');
  const submitButton = document.querySelector('.btn-checkout-action-submit');

  const selectedRoom = getSelectedRoom();

  showSelectedRoom();
  prefillStoredDates();
  updatePriceSummary();

  if (checkinInput) {
    checkinInput.addEventListener('change', updatePriceSummary);
  }

  if (checkoutInput) {
    checkoutInput.addEventListener('change', updatePriceSummary);
  }

  if (bookingForm) {
    bookingForm.addEventListener('submit', function (event) {
      event.preventDefault();

      const message = validateBookingForm();

      if (message !== '') {
        alert(message);
        return;
      }

      const nights = calculateNights(checkinInput.value, checkoutInput.value);
      const totalPrice = selectedRoom.price * nights;
      const booking = createBooking(selectedRoom, nights, totalPrice);

      saveBooking(booking);
      clearSelectedRoom();
      alert('Đặt phòng thành công! Mã đặt phòng: ' + booking.bookingCode);
      window.location.href = 'bookingsuccess.html';
    });
  }

  function showSelectedRoom() {
    if (!miniSummary) {
      return;
    }

    if (!selectedRoom) {
      miniSummary.innerHTML =
        '<div class="mini-room-line">Chưa có phòng nào được chọn.</div>' +
        '<div class="mini-room-line"><a href="search.html">Quay lại tìm phòng</a></div>';

      if (submitButton) {
        submitButton.disabled = true;
        submitButton.textContent = 'Vui lòng chọn phòng trước';
      }

      return;
    }

    miniSummary.innerHTML =
      '<div class="mini-room-line">✓ ' + selectedRoom.roomName + '</div>' +
      '<div class="mini-room-line">' + selectedRoom.location + ' • ' + selectedRoom.roomType + '</div>' +
      '<div class="mini-room-line">Giá mỗi đêm: ' + formatPrice(selectedRoom.price) + '</div>' +
      '<div class="mini-room-line" id="nights-summary">Vui lòng chọn ngày nhận và trả phòng</div>';
  }

  function prefillStoredDates() {
    if (!selectedRoom || !checkinInput || !checkoutInput) {
      return;
    }

    if (selectedRoom.checkin) {
      checkinInput.value = selectedRoom.checkin;
    }

    if (selectedRoom.checkout) {
      checkoutInput.value = selectedRoom.checkout;
    }
  }

  function validateBookingForm() {
    if (!selectedRoom) {
      return 'Vui lòng chọn một phòng trước khi đặt.';
    }

    const customerName = fullNameInput ? fullNameInput.value.trim() : '';
    const phone = phoneInput ? phoneInput.value.trim() : '';
    const email = emailInput ? emailInput.value.trim() : '';
    const checkin = checkinInput ? checkinInput.value : '';
    const checkout = checkoutInput ? checkoutInput.value : '';
    const phoneDigits = phone.replace(/\D/g, '');

    if (customerName === '') {
      return 'Vui lòng nhập họ và tên.';
    }

    if (!email.includes('@')) {
      return 'Vui lòng nhập email hợp lệ.';
    }

    if (phoneDigits.length < 9) {
      return 'Số điện thoại phải có ít nhất 9 chữ số.';
    }

    if (checkin === '' || checkout === '') {
      return 'Vui lòng chọn ngày nhận phòng và ngày trả phòng.';
    }

    if (calculateNights(checkin, checkout) <= 0) {
      return 'Ngày trả phòng phải sau ngày nhận phòng.';
    }

    return '';
  }

  function updatePriceSummary() {
    if (!checkinInput || !checkoutInput) {
      return;
    }

    const nights = calculateNights(checkinInput.value, checkoutInput.value);
    const safeNights = nights > 0 ? nights : 0;
    const subtotal = selectedRoom ? selectedRoom.price * safeNights : 0;
    const tax = Math.round(subtotal * 0.1);
    const finalTotal = subtotal + tax;
    const nightsSummary = document.getElementById('nights-summary');

    if (nightsSummary) {
      nightsSummary.textContent = safeNights > 0
        ? 'Số đêm: ' + safeNights
        : 'Vui lòng chọn ngày nhận và trả phòng';
    }

    if (billingRows[0] && billingRows[0].querySelector('span:last-child')) {
      billingRows[0].querySelector('span:last-child').textContent = formatPrice(subtotal);
    }

    if (billingRows[1] && billingRows[1].querySelector('span:last-child')) {
      billingRows[1].querySelector('span:last-child').textContent = formatPrice(tax);
    }

    if (finalPriceElement) {
      finalPriceElement.textContent = formatPrice(finalTotal);
    }
  }

  function createBooking(room, nights, totalPrice) {
    return {
      bookingCode: 'GST' + Date.now(),
      customerName: fullNameInput.value.trim(),
      email: emailInput.value.trim(),
      phone: phoneInput.value.trim(),
      roomName: room.roomName,
      location: room.location,
      roomType: room.roomType,
      pricePerNight: room.price,
      checkin: checkinInput.value,
      checkout: checkoutInput.value,
      nights: nights,
      totalPrice: totalPrice,
      status: 'Đã xác nhận',
      createdAt: new Date().toISOString()
    };
  }
});

function getCart() {
  const savedCart = localStorage.getItem('gostayCart');

  if (!savedCart) {
    return [];
  }

  try {
    const parsedCart = JSON.parse(savedCart);

    if (!Array.isArray(parsedCart)) {
      localStorage.removeItem('gostayCart');
      return [];
    }

    return parsedCart.slice(0, 1);
  } catch (error) {
    localStorage.removeItem('gostayCart');
    return [];
  }
}

function getSelectedRoom() {
  const cart = getCart();
  const selectedRoom = cart[0];

  if (!selectedRoom || !selectedRoom.roomName || !Number(selectedRoom.price)) {
    return null;
  }

  return selectedRoom;
}

function clearSelectedRoom() {
  localStorage.removeItem('gostayCart');
}

function calculateNights(checkin, checkout) {
  if (checkin === '' || checkout === '') {
    return 0;
  }

  const checkinDate = new Date(checkin);
  const checkoutDate = new Date(checkout);
  const oneDay = 1000 * 60 * 60 * 24;

  return Math.round((checkoutDate - checkinDate) / oneDay);
}

function saveBooking(booking) {
  const bookings = getBookings();

  localStorage.setItem('gostayLatestBooking', JSON.stringify(booking));
  bookings.push(booking);
  localStorage.setItem('gostayBookings', JSON.stringify(bookings));
}

function renderLatestBookingSuccess() {
  const bookingCodeElement = document.getElementById('success-booking-code');
  const bookingDetailsElement = document.getElementById('success-booking-details');

  if (!bookingCodeElement || !bookingDetailsElement) {
    return;
  }

  const latestBooking = getLatestBooking();

  if (!latestBooking) {
    bookingCodeElement.textContent = '';
    bookingDetailsElement.textContent = 'Không tìm thấy thông tin đặt phòng gần nhất.';
    return;
  }

  bookingCodeElement.textContent = latestBooking.bookingCode;
  bookingDetailsElement.innerHTML =
    '<p><strong>Khách hàng:</strong> ' + latestBooking.customerName + '</p>' +
    '<p><strong>Phòng:</strong> ' + latestBooking.roomName + '</p>' +
    '<p><strong>Địa điểm:</strong> ' + latestBooking.location + '</p>' +
    '<p><strong>Loại phòng:</strong> ' + latestBooking.roomType + '</p>' +
    '<p><strong>Ngày nhận phòng:</strong> ' + latestBooking.checkin + '</p>' +
    '<p><strong>Ngày trả phòng:</strong> ' + latestBooking.checkout + '</p>' +
    '<p><strong>Số đêm:</strong> ' + latestBooking.nights + '</p>' +
    '<p><strong>Tổng tiền phòng:</strong> ' + formatPrice(latestBooking.totalPrice) + '</p>' +
    '<p><strong>Trạng thái:</strong> ' + latestBooking.status + '</p>';
}

function getLatestBooking() {
  const savedBooking = localStorage.getItem('gostayLatestBooking');

  if (!savedBooking) {
    return null;
  }

  try {
    return JSON.parse(savedBooking);
  } catch (error) {
    localStorage.removeItem('gostayLatestBooking');
    return null;
  }
}

function renderBookingHistory() {
  const historyBody = document.getElementById('booking-history-body');

  if (!historyBody) {
    return;
  }

  const bookings = getBookings();
  historyBody.innerHTML = '';

  if (bookings.length === 0) {
    historyBody.innerHTML =
      '<tr>' +
      '<td colspan="5">Bạn chưa có lịch sử đặt phòng.</td>' +
      '</tr>';
    return;
  }

  bookings.forEach(function (booking, index) {
    const row = document.createElement('tr');
    const statusClass = booking.status === 'Đã hủy' ? 'cancelled' : 'completed';
    const actionButton = booking.status === 'Đã xác nhận'
      ? '<button type="button" class="btn-remove-cart" data-booking-index="' + index + '">Hủy booking</button>'
      : '';

    row.innerHTML =
      '<td class="col-code">' + booking.bookingCode + '</td>' +
      '<td>' +
      '<div class="table-room-name">' + booking.roomName + '</div>' +
      '<div class="table-branch-name">Chi nhánh: ' + booking.location + ' • ' + booking.roomType + '</div>' +
      '</td>' +
      '<td>' + booking.checkin + ' - ' + booking.checkout + '</td>' +
      '<td class="table-price">' + formatPrice(booking.totalPrice) + '</td>' +
      '<td><span class="status-pill ' + statusClass + '">' + booking.status + '</span><br>' + actionButton + '</td>';

    historyBody.appendChild(row);
  });

  const cancelButtons = historyBody.querySelectorAll('[data-booking-index]');

  cancelButtons.forEach(function (button) {
    button.addEventListener('click', function () {
      const index = Number(button.dataset.bookingIndex);
      cancelBooking(index);
    });
  });
}

function getBookings() {
  const savedBookings = localStorage.getItem('gostayBookings');

  if (!savedBookings) {
    return [];
  }

  try {
    const bookings = JSON.parse(savedBookings);
    return Array.isArray(bookings) ? bookings : [];
  } catch (error) {
    return [];
  }
}

function cancelBooking(index) {
  const confirmed = confirm('Bạn có chắc muốn hủy booking này không?');

  if (!confirmed) {
    return;
  }

  const bookings = getBookings();

  if (!bookings[index]) {
    return;
  }

  bookings[index].status = 'Đã hủy';
  localStorage.setItem('gostayBookings', JSON.stringify(bookings));

  const latestBooking = getLatestBooking();

  if (latestBooking && latestBooking.bookingCode === bookings[index].bookingCode) {
    localStorage.setItem('gostayLatestBooking', JSON.stringify(bookings[index]));
  }

  renderBookingHistory();
}

function formatPrice(price) {
  return Number(price || 0).toLocaleString('vi-VN') + 'đ';
}

document.addEventListener('DOMContentLoaded', function () {
  setupAddToCartButtons();
  setupDetailBookingForm();
  renderCartPage();
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

function saveCart(cart) {
  const singleRoomCart = Array.isArray(cart) ? cart.slice(0, 1) : [];
  localStorage.setItem('gostayCart', JSON.stringify(singleRoomCart));
}

function clearCart() {
  localStorage.removeItem('gostayCart');
}

function setupAddToCartButtons() {
  const roomCards = document.querySelectorAll('.room-search-card');

  roomCards.forEach(function (card) {
    const detailButton = card.querySelector('.btn-view-detail');

    if (!detailButton || card.querySelector('.btn-add-cart')) {
      return;
    }

    const addButton = document.createElement('button');
    addButton.type = 'button';
    addButton.className = 'btn-view-detail btn-add-cart';
    addButton.textContent = 'Chọn phòng';

    addButton.addEventListener('click', function () {
      selectRoomForBooking(getRoomDataFromCard(card), false);
    });

    detailButton.insertAdjacentElement('afterend', addButton);
  });
}

function setupDetailBookingForm() {
  const detailForm = document.querySelector('.booking-form');

  if (!detailForm || !document.querySelector('.detail-main')) {
    return;
  }

  detailForm.addEventListener('submit', function (event) {
    event.preventDefault();

    const checkinInput = detailForm.querySelector('input[type="date"]');
    const checkoutInput = detailForm.querySelectorAll('input[type="date"]')[1];
    const guestSelect = detailForm.querySelector('select');

    if (!checkinInput || !checkoutInput || !guestSelect) {
      alert('Không tìm thấy đầy đủ thông tin đặt phòng.');
      return;
    }

    if (checkinInput.value === '' || checkoutInput.value === '') {
      alert('Vui lòng chọn ngày nhận phòng và ngày trả phòng.');
      return;
    }

    if (calculateNights(checkinInput.value, checkoutInput.value) <= 0) {
      alert('Ngày trả phòng phải sau ngày nhận phòng.');
      return;
    }

    const room = getRoomDataFromDetailPage();
    room.checkin = checkinInput.value;
    room.checkout = checkoutInput.value;
    room.guests = guestSelect.value;
    room.nights = calculateNights(checkinInput.value, checkoutInput.value);
    room.total = room.price * room.nights;

    if (selectRoomForBooking(room, true)) {
      window.location.href = 'cart.html';
    }
  });
}

function selectRoomForBooking(room, redirectAfterSelect) {
  const cart = getCart();
  const currentRoom = cart[0];
  const isSameRoom = currentRoom && currentRoom.roomName === room.roomName;

  if (currentRoom && !isSameRoom) {
    const confirmed = confirm(
      'Mỗi giao dịch chỉ đặt một phòng. Phòng mới sẽ thay thế phòng đang chọn. Bạn có muốn tiếp tục?'
    );

    if (!confirmed) {
      return false;
    }
  }

  saveCart([room]);

  if (!redirectAfterSelect) {
    alert('Đã chọn phòng này cho giao dịch hiện tại. Mỗi giao dịch chỉ đặt một phòng.');
  }

  return true;
}

function getRoomDataFromCard(card) {
  const nameElement = card.querySelector('h3');
  const metaElement = card.querySelector('.room-meta');
  const priceElement = card.querySelector('.room-price');
  const imageElement = card.querySelector('img');
  const metaText = metaElement ? metaElement.textContent : '';
  const metaParts = metaText.split('•');
  const price = getNumberFromText(priceElement ? priceElement.textContent : '');

  return {
    roomName: nameElement ? nameElement.textContent.trim() : 'GoStay Room',
    location: metaParts[0] ? metaParts[0].replace(/[^\p{L}\p{N}\s]/gu, '').trim() : 'GoStay',
    roomType: metaParts[1] ? metaParts[1].replace(/[^\p{L}\p{N}\s-]/gu, '').trim() : 'Phòng nghỉ',
    price: price,
    image: imageElement ? imageElement.src : '',
    quantity: 1,
    nights: 1,
    total: price
  };
}

function getRoomDataFromDetailPage() {
  const titleElement = document.querySelector('.detail-header-info h1');
  const metaElements = document.querySelectorAll('.detail-meta-row p');
  const priceElement = document.querySelector('.widget-price');
  const imageElement = document.querySelector('.detail-gallery img');
  const price = getNumberFromText(priceElement ? priceElement.textContent : '');

  return {
    roomName: titleElement ? titleElement.textContent.trim() : document.title.replace(' - GoStay', ''),
    location: metaElements[0] ? metaElements[0].textContent.replace(/[^\p{L}\p{N}\s]/gu, '').trim() : 'GoStay',
    roomType: metaElements[1] ? metaElements[1].textContent.replace(/[^\p{L}\p{N}\s-]/gu, '').trim() : 'Phòng nghỉ',
    price: price,
    image: imageElement ? imageElement.src : '',
    quantity: 1,
    nights: 1,
    total: price
  };
}

function renderCartPage() {
  const cartList = document.querySelector('.cart-left-block');
  const summaryCard = document.querySelector('.billing-summary-card');

  if (!cartList || !summaryCard) {
    return;
  }

  const cart = getCart();
  const selectedRoom = cart[0];

  cartList.innerHTML = '';

  if (!selectedRoom) {
    cartList.innerHTML =
      '<p>Giỏ đặt phòng của bạn đang trống. Vui lòng chọn một phòng trước khi đặt.</p>' +
      '<div class="cart-left-footer">' +
      '<a class="btn-back-to-rooms" href="search.html">← Tiếp tục tìm kiếm phòng</a>' +
      '</div>';
    renderEmptyCartSummary(summaryCard);
    return;
  }

  cartList.appendChild(createCartItem(selectedRoom));
  cartList.insertAdjacentHTML(
    'beforeend',
    '<div class="cart-left-footer">' +
    '<a class="btn-back-to-rooms" href="search.html">← Chọn phòng khác</a>' +
    '</div>'
  );

  renderCartSummary(summaryCard, selectedRoom.total || selectedRoom.price || 0);
}

function createCartItem(item) {
  const itemElement = document.createElement('div');
  itemElement.className = 'cart-bundle-item';

  itemElement.innerHTML =
    '<div class="cart-item-img-container">' +
    '<img src="' + item.image + '" alt="' + item.roomName + '">' +
    '</div>' +
    '<div class="cart-item-info-container">' +
    '<h3>' + item.roomName + '</h3>' +
    '<div class="cart-item-sub">' + item.location + ' • ' + item.roomType + '</div>' +
    '<div class="cart-date-meta">' +
    '<span><strong>Số lượng:</strong> 1 phòng</span>' +
    '<span class="nights-count">' + (item.nights || 1) + ' đêm</span>' +
    '</div>' +
    '</div>' +
    '<div class="cart-item-price-container">' +
    '<div class="cart-item-price">' + formatPrice(item.price || 0) + ' <small>/đêm</small></div>' +
    '<button type="button" class="btn-remove-cart">× Xóa phòng</button>' +
    '</div>';

  const removeButton = itemElement.querySelector('.btn-remove-cart');

  if (removeButton) {
    removeButton.addEventListener('click', function () {
      clearCart();
      renderCartPage();
    });
  }

  return itemElement;
}

function renderCartSummary(summaryCard, total) {
  const tax = Math.round(total * 0.1);
  const finalTotal = total + tax;

  summaryCard.innerHTML =
    '<h3>Tóm tắt chi phí</h3>' +
    '<div class="billing-row">' +
    '<span>Tạm tính tiền phòng</span>' +
    '<span>' + formatPrice(total) + '</span>' +
    '</div>' +
    '<div class="billing-row">' +
    '<span>Thuế & Phí dịch vụ (10%)</span>' +
    '<span>' + formatPrice(tax) + '</span>' +
    '</div>' +
    '<div class="billing-divider"></div>' +
    '<div class="billing-row total-row">' +
    '<span>Tổng cộng</span>' +
    '<span class="billing-final-price">' + formatPrice(finalTotal) + '</span>' +
    '</div>' +
    '<a class="btn-checkout-action" href="booking.html">Tiến hành đặt phòng</a>';
}

function renderEmptyCartSummary(summaryCard) {
  summaryCard.innerHTML =
    '<h3>Tóm tắt chi phí</h3>' +
    '<p>Chưa có phòng nào được chọn.</p>' +
    '<a class="btn-checkout-action" href="search.html">Tìm phòng</a>';
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

function getNumberFromText(text) {
  const numberText = text.replace(/\D/g, '');
  return Number(numberText);
}

function formatPrice(price) {
  return Number(price || 0).toLocaleString('vi-VN') + 'đ';
}

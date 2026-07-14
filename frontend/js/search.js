document.addEventListener('DOMContentLoaded', function () {
  const filterForm = document.querySelector('.filter-sidebar form');
  const keywordInput = document.querySelector('.filter-sidebar input[type="text"]');
  const locationSelect = document.querySelectorAll('.filter-sidebar select')[0];
  const priceSelect = document.querySelectorAll('.filter-sidebar select')[1];
  const roomTypeCheckboxes = document.querySelectorAll('.checkbox-group input[type="checkbox"]');
  const applyButton = document.querySelector('.btn-apply-filter');
  const roomCards = document.querySelectorAll('.room-search-card');
  const resultsHeader = document.querySelector('.results-header');

  const rooms = [
    { name: 'Sunrise Premier Room Sunrise Hotel', location: 'Hà Nội', price: 850000, type: 'doi-vip' },
    { name: 'Ocean Vista Studio Coastal Resort', location: 'Nha Trang', price: 1250000, type: 'don-vip' },
    { name: 'Green Valley Suite Eco Lodge', location: 'Đà Nẵng', price: 620000, type: 'doi-basic' },
    { name: 'Cozy Standard Room Urban Hotel', location: 'Hà Nội', price: 350000, type: 'don-basic' },
    { name: 'Grand Luxury Suite Palace Hotel', location: 'Nha Trang', price: 2500000, type: 'doi-vip' },
    { name: 'City View Twin Room Central Hotel', location: 'Đà Nẵng', price: 500000, type: 'doi-basic' },
    { name: 'Sunset Beach Villa Phu Quoc Resort', location: 'Phú Quốc', price: 3200000, type: 'doi-vip' },
    { name: 'Mountain View Bungalow Sapa Lodge', location: 'Sa Pa', price: 450000, type: 'don-basic' },
    { name: 'Saigon City Studio Urban Oasis', location: 'Hồ Chí Minh', price: 1100000, type: 'don-vip' },
    { name: 'Golden Bridge Suite Danang Riverside', location: 'Đà Nẵng', price: 1800000, type: 'doi-vip' }
  ];

  if (!filterForm || !keywordInput || !locationSelect || !priceSelect || !applyButton) {
    return;
  }

  roomCards.forEach(function (card, index) {
    const room = rooms[index];

    if (!room) {
      return;
    }

    // Store simple searchable data on each card for beginner-friendly filtering.
    card.dataset.name = normalizeText(room.name);
    card.dataset.location = normalizeText(room.location);
    card.dataset.price = room.price;
    card.dataset.roomType = room.type;
  });

  showAllRooms();

  const resultCountMessage = document.createElement('p');
  resultCountMessage.textContent = 'Tìm thấy ' + roomCards.length + ' phòng phù hợp';
  resultCountMessage.style.display = 'none';
  resultsHeader.appendChild(resultCountMessage);

  const noResultsMessage = document.createElement('p');
  noResultsMessage.textContent = 'Không tìm thấy phòng phù hợp.';
  noResultsMessage.style.display = 'none';
  resultsHeader.appendChild(noResultsMessage);

  applyButton.addEventListener('click', filterRooms);

  filterForm.addEventListener('submit', function (event) {
    event.preventDefault();
    filterRooms();
  });

  function filterRooms() {
    const keyword = normalizeText(keywordInput.value);
    const selectedLocation = locationSelect.value;
    const selectedPrice = priceSelect.value;
    const selectedRoomTypes = getSelectedRoomTypes();
    let visibleCount = 0;

    roomCards.forEach(function (card) {
      const matchesKeyword = isKeywordMatch(card, keyword);
      const matchesLocation = isLocationMatch(card, selectedLocation);
      const matchesPrice = isPriceMatch(card, selectedPrice);
      const matchesRoomType = isRoomTypeMatch(card, selectedRoomTypes);

      if (matchesKeyword && matchesLocation && matchesPrice && matchesRoomType) {
        showRoomCard(card);
        card.dataset.filterVisible = 'true';
        visibleCount++;
      } else {
        hideRoomCard(card);
        card.dataset.filterVisible = 'false';
      }
    });

    resultCountMessage.textContent = 'Tìm thấy ' + visibleCount + ' phòng phù hợp';
    resultCountMessage.style.display = 'block';
    noResultsMessage.style.display = visibleCount === 0 ? 'block' : 'none';
  }

  function getSelectedRoomTypes() {
    const selectedTypes = [];

    roomTypeCheckboxes.forEach(function (checkbox) {
      if (checkbox.checked) {
        selectedTypes.push(checkbox.value);
      }
    });

    return selectedTypes;
  }

  function isKeywordMatch(card, keyword) {
    if (keyword === '') {
      return true;
    }

    const cardText = card.dataset.name + ' ' + card.dataset.location + ' ' + card.dataset.roomType;
    return cardText.includes(keyword);
  }

  function isLocationMatch(card, selectedLocation) {
    if (selectedLocation === '') {
      return true;
    }

    return card.dataset.location.includes(selectedLocation);
  }

  function isPriceMatch(card, selectedPrice) {
    const price = Number(card.dataset.price);

    if (selectedPrice === '') {
      return true;
    }

    if (selectedPrice === '0-500') {
      return price < 500000;
    }

    if (selectedPrice === '500-1000') {
      return price >= 500000 && price <= 1000000;
    }

    if (selectedPrice === '1000+') {
      return price > 1000000;
    }

    return true;
  }

  function isRoomTypeMatch(card, selectedRoomTypes) {
    if (selectedRoomTypes.length === 0) {
      return true;
    }

    return selectedRoomTypes.includes(card.dataset.roomType);
  }

  function showAllRooms() {
    roomCards.forEach(function (card) {
      showRoomCard(card);
    });
  }

  function showRoomCard(card) {
    // Show the card again and let the original CSS layout control its appearance.
    card.hidden = false;
    card.removeAttribute('aria-hidden');
    card.style.removeProperty('display');
  }

  function hideRoomCard(card) {
    // The CSS uses display: flex !important, so JS must hide the card strongly.
    card.hidden = true;
    card.setAttribute('aria-hidden', 'true');
    card.style.setProperty('display', 'none', 'important');
  }

  function normalizeText(text) {
    // Make text easier to compare: lowercase, remove accents, and remove spaces.
    return text
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/đ/g, 'd')
      .replace(/\s+/g, '');
  }
});

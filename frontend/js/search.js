document.addEventListener('DOMContentLoaded', function () {
  const filterForm = document.querySelector('.filter-sidebar form');
  const locationSelect = document.getElementById('branch-filter');
  const hotelSelect = document.getElementById('hotel-filter');
  const priceSelect = document.getElementById('price-filter');
  const roomTypeCheckboxes = document.querySelectorAll('.checkbox-group input[type="checkbox"]');
  const applyButton = document.querySelector('.btn-apply-filter');
  const roomCards = document.querySelectorAll('.room-search-card');
  const resultsHeader = document.querySelector('.results-header');

  const rooms = [
    { name: 'Deluxe Hướng Vườn Giường Đôi', hotel: 'GoStay Fiesta Phú Quốc', location: 'Phú Quốc', price: 850000, type: 'doi-vip' },
    { name: 'Deluxe Hướng Biển 2 Giường Đơn', hotel: 'GoStay Wonderworld Phú Quốc', location: 'Phú Quốc', price: 1250000, type: 'don-vip' },
    { name: 'Junior Suite Hướng Vườn Giường Đôi', hotel: 'GoStay Resort & Spa Phú Quốc', location: 'Phú Quốc', price: 620000, type: 'doi-basic' },
    { name: 'Deluxe Hướng Vịnh Giường Đôi', hotel: 'GoStay Hòn Tằm Resort', location: 'Nha Trang', price: 350000, type: 'don-basic' },
    { name: 'Executive Suite Hướng Biển', hotel: 'GoStay Resort & Spa Nha Trang Bay', location: 'Nha Trang', price: 2500000, type: 'doi-vip' },
    { name: 'Deluxe Hướng Biển 2 Giường Đơn', hotel: 'GoStay Resort Nha Trang', location: 'Nha Trang', price: 500000, type: 'doi-basic' },
    { name: 'Deluxe Hướng Biển Giường Đôi', hotel: 'GoStay Resort & Golf Nam Hội An', location: 'Hội An', price: 3200000, type: 'doi-vip' },
    { name: 'Biệt Thự 2 Phòng Ngủ Hướng Vườn', hotel: 'GoStay Cửa Sót Resort', location: 'Hà Tĩnh', price: 450000, type: 'don-basic' },
    { name: 'Deluxe Hướng Biển Giường Đôi', hotel: 'GoStay Cửa Hội Resort', location: 'Nghệ An', price: 1100000, type: 'don-vip' },
    { name: 'Deluxe Hướng Vịnh Giường Đôi', hotel: 'GoStay Resort & Spa Hạ Long', location: 'Quảng Ninh', price: 1800000, type: 'doi-vip' }
  ];

  const branchHotels = {
    'Phú Quốc': ['GoStay Fiesta Phú Quốc', 'GoStay Wonderworld Phú Quốc', 'GoStay Resort & Spa Phú Quốc'],
    'Nha Trang': ['GoStay Hòn Tằm Resort', 'GoStay Resort & Spa Nha Trang Bay', 'GoStay Resort Nha Trang', 'GoStay Luxury Nha Trang', 'GoStay Beachfront Nha Trang', 'GoStay Empire Nha Trang'],
    'Hội An': ['GoStay Resort & Golf Nam Hội An'],
    'Hà Tĩnh': ['GoStay Cửa Sót Resort', 'GoStay Hà Tĩnh'],
    'Nghệ An': ['GoStay Cửa Hội Resort'],
    'Bắc Ninh': ['GoStay Hotel Bắc Ninh'],
    'Quảng Ninh': ['GoStay Resort & Spa Hạ Long']
  };

  if (!filterForm || !locationSelect || !hotelSelect || !priceSelect || !applyButton) {
    return;
  }

  roomCards.forEach(function (card, index) {
    const room = rooms[index];

    if (!room) {
      return;
    }

    // Store simple searchable data on each card for beginner-friendly filtering.
    card.dataset.name = normalizeText(room.name + ' ' + room.hotel);
    card.dataset.hotel = normalizeText(room.hotel);
    card.dataset.location = normalizeText(room.location);
    card.dataset.price = room.price;
    card.dataset.roomType = room.type;
  });

  showAllRooms();
  locationSelect.addEventListener('change', updateHotelOptions);

  const resultCountMessage = document.createElement('p');
  resultCountMessage.textContent = 'Tìm thấy ' + roomCards.length + ' phòng phù hợp';
  resultCountMessage.style.display = 'none';
  resultsHeader.appendChild(resultCountMessage);

  const noResultsMessage = document.createElement('p');
  noResultsMessage.textContent = 'Không tìm thấy phòng phù hợp.';
  noResultsMessage.style.display = 'none';
  resultsHeader.appendChild(noResultsMessage);

  applyUrlFilters();

  applyButton.addEventListener('click', filterRooms);

  filterForm.addEventListener('submit', function (event) {
    event.preventDefault();
    filterRooms();
  });

  function applyUrlFilters() {
    const params = new URLSearchParams(window.location.search);
    let requestedBranch = params.get('branch') || params.get('location') || '';
    const requestedHotel = params.get('hotel') || '';
    const branchAliases = { 'Hạ Long': 'Quảng Ninh' };

    requestedBranch = branchAliases[requestedBranch] || requestedBranch;

    const hasBranch = Array.from(locationSelect.options).some(function (option) {
      return option.value === requestedBranch;
    });

    if (!hasBranch || requestedBranch === '') return;

    locationSelect.value = requestedBranch;
    updateHotelOptions();

    const hasHotel = Array.from(hotelSelect.options).some(function (option) {
      return option.value === requestedHotel;
    });

    if (hasHotel) hotelSelect.value = requestedHotel;

    const resultsTitle = document.createElement('h2');
    resultsTitle.className = 'branch-results-title';
    resultsTitle.textContent = 'Khách sạn và phòng tại ' + (requestedBranch === 'Quảng Ninh' ? 'Hạ Long' : requestedBranch);
    resultsHeader.insertBefore(resultsTitle, resultCountMessage);
    filterRooms();
  }

  function filterRooms() {
    const selectedLocation = locationSelect.value;
    const selectedHotel = hotelSelect.value;
    const selectedPrice = priceSelect.value;
    const selectedRoomTypes = getSelectedRoomTypes();
    let visibleCount = 0;

    roomCards.forEach(function (card) {
      const matchesLocation = isLocationMatch(card, selectedLocation);
      const matchesHotel = isHotelMatch(card, selectedHotel);
      const matchesPrice = isPriceMatch(card, selectedPrice);
      const matchesRoomType = isRoomTypeMatch(card, selectedRoomTypes);

      if (matchesLocation && matchesHotel && matchesPrice && matchesRoomType) {
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

  function isLocationMatch(card, selectedLocation) {
    if (selectedLocation === '') {
      return true;
    }

    return card.dataset.location === normalizeText(selectedLocation);
  }

  function isHotelMatch(card, selectedHotel) {
    return selectedHotel === '' || card.dataset.hotel === normalizeText(selectedHotel);
  }

  function updateHotelOptions() {
    const selectedLocation = locationSelect.value;
    const hotels = [];

    if (selectedLocation !== '' && branchHotels[selectedLocation]) {
      branchHotels[selectedLocation].forEach(function (hotel) {
        hotels.push(hotel);
      });
    }

    hotelSelect.innerHTML = '';
    const defaultOption = document.createElement('option');
    defaultOption.value = '';
    defaultOption.textContent = selectedLocation === '' ? 'Chọn chi nhánh trước' : 'Tất cả khách sạn';
    hotelSelect.appendChild(defaultOption);

    hotels.forEach(function (hotel) {
      const option = document.createElement('option');
      option.value = hotel;
      option.textContent = hotel;
      hotelSelect.appendChild(option);
    });

    hotelSelect.disabled = selectedLocation === '';
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

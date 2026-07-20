document.addEventListener('DOMContentLoaded', function () {
  const pageName = window.location.pathname.split('/').pop() || 'room-detail.html';
  const roomKey = pageName === 'room-detail.html' ? 'room1.html' : pageName;
  const room = roomDetails[roomKey];

  if (!room || !document.querySelector('.detail-main')) return;

  document.title = room.name + ' - ' + room.hotel + ' | GoStay';

  const heading = document.querySelector('.detail-header-info h1');
  const image = document.querySelector('.detail-gallery img');
  const metaRow = document.querySelector('.detail-meta-row');
  const description = document.querySelector('.detail-description');
  const amenitiesList = document.querySelector('.amenities-list');
  const price = document.querySelector('.widget-price');

  heading.textContent = room.name + ' - ' + room.hotel;
  image.alt = room.name + ' tại ' + room.hotel;
  price.textContent = formatRoomPrice(room.price) + 'đ / đêm';

  metaRow.innerHTML = '';
  [
    '📍 ' + room.address,
    '🏨 ' + room.hotel,
    '☎ ' + room.phone
  ].forEach(function (text) {
    const item = document.createElement('p');
    item.textContent = text;
    metaRow.appendChild(item);
  });

  const specs = document.createElement('div');
  specs.className = 'room-specs';
  specs.innerHTML = [
    ['Diện tích', room.area],
    ['Sức chứa', room.capacity],
    ['Loại giường', room.bed],
    ['Hướng phòng', room.view]
  ].map(function (spec) {
    return '<div class="room-spec"><span>' + spec[0] + '</span><strong>' + spec[1] + '</strong></div>';
  }).join('');
  document.querySelector('.detail-header-info').insertAdjacentElement('afterend', specs);

  description.innerHTML = '<h3>Thông tin hạng phòng</h3><p>' + room.description + '</p><p>' + room.experience + '</p>';
  amenitiesList.innerHTML = room.amenities.map(function (amenity) {
    return '<li>' + amenity + '</li>';
  }).join('');
});

function formatRoomPrice(price) {
  return new Intl.NumberFormat('vi-VN').format(price);
}

const sharedAmenities = [
  'WiFi tốc độ cao miễn phí',
  'Smart TV màn hình phẳng',
  'Điều hòa nhiệt độ',
  'Minibar và nước uống hằng ngày',
  'Két an toàn trong phòng',
  'Áo choàng tắm và dép đi trong phòng',
  'Máy sấy tóc và bộ đồ dùng phòng tắm',
  'Dịch vụ phòng và lễ tân 24 giờ'
];

const roomDetails = {
  'room1.html': {
    name: 'Deluxe Hướng Vườn Giường Đôi', hotel: 'GoStay Fiesta Phú Quốc',
    address: 'Bãi Dài, Gành Dầu, Phú Quốc', phone: '0297 3550 550',
    area: '46 m²', capacity: '2 người lớn và 2 trẻ em', bed: '1 giường King', view: 'Vườn nhiệt đới', price: 850000,
    description: 'Với diện tích 46 m², Deluxe Hướng Vườn Giường Đôi sở hữu thiết kế hiện đại, tông màu ấm và ban công riêng nhìn ra khu vườn nhiệt đới.',
    experience: 'Không gian phù hợp cho cặp đôi, gia đình nhỏ hoặc khách công tác muốn tận hưởng kỳ lưu trú thư thái gần Bãi Dài.', amenities: sharedAmenities
  },
  'room2.html': {
    name: 'Deluxe Hướng Biển 2 Giường Đơn', hotel: 'GoStay Wonderworld Phú Quốc',
    address: 'Khu du lịch Bãi Dài, Gành Dầu, Phú Quốc', phone: '0297 3550 551',
    area: '46 m²', capacity: '2 người lớn và 2 trẻ em', bed: '2 giường đơn', view: 'Biển', price: 1250000,
    description: 'Hạng phòng rộng 46 m² có ban công hướng biển, thiết kế thanh lịch và hai giường đơn tiện nghi.',
    experience: 'Tầm nhìn đại dương và ánh sáng tự nhiên mang đến không gian nghỉ dưỡng thoáng đãng cho bạn bè, gia đình nhỏ hoặc khách công tác.', amenities: sharedAmenities
  },
  'room3.html': {
    name: 'Junior Suite Hướng Vườn Giường Đôi', hotel: 'GoStay Resort & Spa Phú Quốc',
    address: 'Bãi Dài, Gành Dầu, Phú Quốc', phone: '0297 3550 552',
    area: '86 m²', capacity: '2 người lớn và 2 trẻ em', bed: '1 giường King', view: 'Vườn nhiệt đới', price: 620000,
    description: 'Junior Suite rộng 86 m² gồm phòng khách và phòng ngủ riêng, kết hợp nội thất sang trọng với ban công lớn.',
    experience: 'Hướng vườn xanh mát và không gian sinh hoạt rộng rãi phù hợp cho kỳ nghỉ dài ngày của cặp đôi hoặc gia đình nhỏ.', amenities: sharedAmenities.concat(['Phòng khách riêng', 'Bồn tắm nằm'])
  },
  'room4.html': {
    name: 'Deluxe Hướng Vịnh Giường Đôi', hotel: 'GoStay Hòn Tằm Resort',
    address: 'Đảo Hòn Tằm, Nha Trang, Khánh Hòa', phone: '0258 3597 777',
    area: '52 m²', capacity: '2 người lớn và 2 trẻ em', bed: '1 giường King', view: 'Vịnh Nha Trang', price: 350000,
    description: 'Phòng Deluxe rộng 52 m² nổi bật với vật liệu tự nhiên, ban công riêng và tầm nhìn khoáng đạt ra vịnh Nha Trang.',
    experience: 'Không gian yên tĩnh trên đảo phù hợp cho du khách tìm kiếm trải nghiệm nghỉ dưỡng gần biển và thiên nhiên.', amenities: sharedAmenities.concat(['Ban công riêng'])
  },
  'room5.html': {
    name: 'Executive Suite Hướng Biển', hotel: 'GoStay Resort & Spa Nha Trang Bay',
    address: 'Đảo Hòn Tre, Nha Trang, Khánh Hòa', phone: '0258 3598 900',
    area: '90 m²', capacity: '2 người lớn và 2 trẻ em', bed: '1 giường King', view: 'Biển', price: 2500000,
    description: 'Executive Suite 90 m² có phòng khách riêng, phòng ngủ lớn và ban công hướng thẳng ra biển.',
    experience: 'Thiết kế tinh tế cùng tầm nhìn vịnh biển tạo nên lựa chọn cao cấp cho kỳ nghỉ lãng mạn hoặc chuyến đi đặc biệt.', amenities: sharedAmenities.concat(['Phòng khách riêng', 'Bồn tắm nằm', 'Máy pha cà phê'])
  },
  'room6.html': {
    name: 'Deluxe Hướng Biển 2 Giường Đơn', hotel: 'GoStay Resort Nha Trang',
    address: 'Đảo Hòn Tre, Nha Trang, Khánh Hòa', phone: '0258 3598 222',
    area: '45 m²', capacity: '2 người lớn và 2 trẻ em', bed: '2 giường đơn', view: 'Biển', price: 500000,
    description: 'Phòng Deluxe 45 m² được bố trí hai giường đơn, khu vực thư giãn và ban công hướng biển.',
    experience: 'Hạng phòng cân bằng giữa tiện nghi hiện đại và cảnh quan đại dương, phù hợp cho bạn bè hoặc gia đình nhỏ.', amenities: sharedAmenities
  },
  'room7.html': {
    name: 'Deluxe Hướng Biển Giường Đôi', hotel: 'GoStay Resort & Golf Nam Hội An',
    address: 'Đường Võ Chí Công, Nam Hội An', phone: '0235 3676 888',
    area: '48 m²', capacity: '2 người lớn và 2 trẻ em', bed: '1 giường King', view: 'Biển', price: 3200000,
    description: 'Deluxe Hướng Biển rộng 48 m² có thiết kế đương đại, ban công riêng và tầm nhìn ôm trọn bờ biển miền Trung.',
    experience: 'Vị trí gần sân golf và khu vui chơi giúp hạng phòng phù hợp cho cả nghỉ dưỡng gia đình lẫn chuyến đi kết hợp thể thao.', amenities: sharedAmenities.concat(['Ban công riêng'])
  },
  'room8.html': {
    name: 'Biệt Thự 2 Phòng Ngủ Hướng Vườn', hotel: 'GoStay Cửa Sót Resort',
    address: 'Bãi biển Xuân Hải, Lộc Hà, Hà Tĩnh', phone: '0239 3788 888',
    area: '180 m²', capacity: '4 người lớn và 2 trẻ em', bed: '1 giường King và 2 giường đơn', view: 'Vườn', price: 450000,
    description: 'Biệt thự 180 m² gồm hai phòng ngủ, phòng khách, khu vực ăn uống và khu vườn riêng xanh mát.',
    experience: 'Không gian biệt lập và rộng rãi là lựa chọn lý tưởng cho gia đình hoặc nhóm bạn muốn tận hưởng kỳ nghỉ riêng tư.', amenities: sharedAmenities.concat(['Phòng khách riêng', 'Bếp nhỏ', 'Sân vườn riêng'])
  },
  'room9.html': {
    name: 'Deluxe Hướng Biển Giường Đôi', hotel: 'GoStay Cửa Hội Resort',
    address: 'Bãi biển Cửa Hội, Nghệ An', phone: '0238 8765 888',
    area: '42 m²', capacity: '2 người lớn và 2 trẻ em', bed: '1 giường King', view: 'Biển Cửa Hội', price: 1100000,
    description: 'Hạng phòng 42 m² được thiết kế hiện đại với giường King, góc thư giãn và cửa kính lớn hướng biển.',
    experience: 'Sắc màu nhẹ nhàng và cảnh biển Cửa Hội mang lại cảm giác thư thái cho cặp đôi hoặc gia đình nhỏ.', amenities: sharedAmenities
  },
  'room10.html': {
    name: 'Deluxe Hướng Vịnh Giường Đôi', hotel: 'GoStay Resort & Spa Hạ Long',
    address: 'Đảo Rều, Bãi Cháy, Hạ Long, Quảng Ninh', phone: '0203 3857 858',
    area: '45 m²', capacity: '2 người lớn và 2 trẻ em', bed: '1 giường King', view: 'Vịnh Hạ Long', price: 1800000,
    description: 'Deluxe Hướng Vịnh rộng 45 m² có ban công riêng và tầm nhìn trực diện ra cảnh quan kỳ vĩ của vịnh Hạ Long.',
    experience: 'Nội thất trang nhã cùng vị trí biệt lập trên đảo mang đến trải nghiệm nghỉ dưỡng yên bình cho cặp đôi và gia đình.', amenities: sharedAmenities.concat(['Ban công hướng vịnh', 'Bồn tắm nằm'])
  }
};

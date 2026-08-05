/* Danh mục tiện nghi cơ bản dùng cho form quản lý phòng. */
INSERT INTO public.amenities (name, icon, description, status)
VALUES
  ('Wi-Fi miễn phí', 'wifi', 'Kết nối Wi-Fi miễn phí trong phòng.', 'active'),
  ('Điều hòa', 'air-conditioner', 'Điều hòa nhiệt độ riêng trong phòng.', 'active'),
  ('TV', 'tv', 'TV phục vụ nhu cầu giải trí.', 'active'),
  ('Minibar', 'minibar', 'Tủ lạnh hoặc minibar trong phòng.', 'active'),
  ('Phòng tắm riêng', 'bathroom', 'Phòng tắm riêng dành cho khách lưu trú.', 'active'),
  ('Máy sấy tóc', 'hair-dryer', 'Máy sấy tóc được trang bị trong phòng.', 'active'),
  ('Ấm đun nước', 'kettle', 'Ấm đun nước phục vụ đồ uống nóng.', 'active'),
  ('Két an toàn', 'safe', 'Két an toàn để bảo quản tài sản cá nhân.', 'active')
ON CONFLICT (name) DO NOTHING;

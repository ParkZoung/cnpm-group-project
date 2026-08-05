# Kiểm tra bảo mật giai đoạn 1 — tài liệu lịch sử

> **Trạng thái: Archived.** Báo cáo này phản ánh repository trước khi Supabase
> Auth, RLS, RPC và cơ chế chống booking đồng thời được triển khai. Nhiều phát
> hiện bên dưới không còn mô tả code hiện tại. Không dùng tài liệu này làm kết
> luận bảo mật hiện hành; xem `CURRENT_SECURITY_STATUS.md`.

Kết luận audit
Giai đoạn 1 hiện chưa an toàn để triển khai production.
Các rủi ro nghiêm trọng nhất:
Đăng nhập và phân quyền admin hoàn toàn giả, dựa vào localStorage.
profiles và bookings đang tắt RLS.
Frontend gửi trực tiếp giá, tổng tiền, trạng thái thanh toán và trạng thái booking.
Booking không được gắn với auth.uid().
Không có constraint/RPC chống hai giao dịch đặt trùng cùng một phòng.
Một số trang admin không chạy kiểm tra admin; các trang khác chỉ kiểm tra giá trị do trình duyệt tự tạo.
Có mật khẩu admin mẫu được commit.
Audit này chỉ đọc repository; không sửa file, chạy SQL hay truy cập Supabase.
Giới hạn bằng chứng: các file database mô tả trạng thái được xuất từ Supabase, nhưng không chứa toàn bộ GRANT/REVOKE. Vì vậy, với bảng tắt RLS, khả năng khai thác trực tiếp còn phụ thuộc table privileges. Tuy nhiên frontend hiện gọi trực tiếp các bảng bằng publishable key, nên phải coi đây là rủi ro có thể khai thác cho đến khi chứng minh ngược lại.

Các phát hiện
1. Đăng nhập và đăng ký vẫn hoàn toàn giả
Mức độ: Critical
Liên quan: [auth.js (line 8)](C:/Users/pnvto/cnpm-group-project/frontend/js/auth.js:8), [login.html (line 84)](C:/Users/pnvto/cnpm-group-project/frontend/login.html:84), [register.html (line 108)](C:/Users/pnvto/cnpm-group-project/frontend/register.html:108)
Nguyên nhân
getCurrentUser() đọc gostayCurrentUser từ localStorage.
Đăng nhập không gọi supabase.auth.signInWithPassword().
Mọi email/mật khẩu không rỗng đều đăng nhập thành customer.
Đăng ký chỉ thêm một object vào gostayUsers trong localStorage; không tạo tài khoản Supabase Auth.
Đăng xuất chỉ xóa localStorage, không gọi supabase.auth.signOut().
Cách lỗi xảy ra
Người dùng có thể mở DevTools và chạy:
localStorage.setItem('gostayCurrentUser', JSON.stringify({
  email: 'attacker@example.com',
  role: 'admin'
}))
Sau đó giao diện coi họ là người đã đăng nhập hoặc admin.
Cách sửa đề xuất
Thay toàn bộ login/register/logout bằng Supabase Auth.
Lấy phiên bằng auth.getSession() và xác thực người dùng bằng auth.getUser().
Theo dõi thay đổi phiên bằng onAuthStateChange().
Không duy trì một “user session” thứ hai trong localStorage.
Có trigger an toàn tạo profiles khi auth.users được tạo.
Cách kiểm thử
Email/mật khẩu sai phải bị từ chối.
Sau khi xóa/sửa gostayCurrentUser, quyền truy cập không thay đổi.
Logout phải làm access token hết hiệu lực.
Tài khoản đăng ký phải xuất hiện trong auth.users và có đúng một profiles tương ứng.
2. Admin hard-code và có mật khẩu mẫu trong source
Mức độ: Critical
Liên quan: [auth.js (line 84)](C:/Users/pnvto/cnpm-group-project/frontend/js/auth.js:84)
Nguyên nhân
Frontend hard-code:
Email: admin@gostay.vn
Mật khẩu: admin123
Role: admin
Cách lỗi xảy ra
Bất kỳ ai đọc source trên trình duyệt hoặc repository đều có thông tin đăng nhập admin mẫu. Thực tế không cần dùng mật khẩu này vì cũng có thể tự ghi object admin vào localStorage.
Cách sửa đề xuất
Xóa hoàn toàn nhánh đăng nhập hard-code.
Admin phải là Supabase Auth user thật.
Role chỉ lấy từ profiles.role, được database bảo vệ.
Không dùng shared/default admin password.
Cách kiểm thử
Tìm toàn repository không còn admin123 hoặc nhánh so sánh email admin.
Đăng nhập bằng chuỗi cũ phải thất bại.
Customer thật không thể truy cập dữ liệu admin dù sửa JavaScript hoặc URL.
3. Kiểm tra admin chỉ dựa vào localStorage
Mức độ: Critical
Liên quan: [admin-auth.js (line 1)](C:/Users/pnvto/cnpm-group-project/frontend/js/admin-auth.js:1)
Nguyên nhân
admin-auth.js chỉ kiểm tra:
currentUser.role === 'admin'
Role không được lấy từ profiles, không có Supabase session, và không có kiểm soát phía database.
Cách lỗi xảy ra
Attacker tự ghi role: "admin" vào localStorage, mở trang admin và frontend gửi trực tiếp lệnh CRUD đến Supabase.
Ngay cả một frontend guard đúng hơn cũng không thể thay thế RLS: attacker có thể bỏ qua trang web và gọi REST API trực tiếp.
Cách sửa đề xuất
Guard giao diện dựa trên Supabase session và profile đọc từ database.
Quyền thật phải được áp dụng tại RLS/RPC.
Xây dựng helper database như is_admin() dựa trên auth.uid() và profiles.
Không dùng metadata do người dùng tự sửa làm nguồn quyền.
Cách kiểm thử
Customer sửa DOM, JavaScript hoặc localStorage vẫn không đọc/ghi được bảng admin.
Gọi Supabase REST trực tiếp bằng access token customer phải bị từ chối.
Admin thật thực hiện được đúng các thao tác được phép.
4. Các trang admin không được bảo vệ nhất quán
Mức độ: High
Liên quan: [admin-users.html (line 138)](C:/Users/pnvto/cnpm-group-project/frontend/admin-users.html:138), [admin-profiles.js (line 71)](C:/Users/pnvto/cnpm-group-project/frontend/js/admin-profiles.js:71), [admin-products.html (line 142)](C:/Users/pnvto/cnpm-group-project/frontend/admin-products.html:142)
Nguyên nhân
admin-users.html tải Supabase và admin-profiles.js nhưng không tải admin-auth.js.
admin-profiles.js lập tức đọc, sửa, xóa profile và role.
Một số trang tải script CRUD trước admin-auth.js; kiểm tra redirect phía client không bảo đảm ngăn các request khởi tạo.
admin-dashboard.html chỉ có fake guard và không khởi tạo Supabase Auth.
Cách lỗi xảy ra
Người không đăng nhập có thể mở trực tiếp admin-users.html. Nếu table privileges cho anon/authenticated cho phép, họ có thể xem tất cả profile, đổi role hoặc xóa profile.
Cách sửa đề xuất
Thống nhất một auth bootstrap cho tất cả trang.
Không khởi chạy chức năng admin trước khi có session hợp lệ và profile admin.
Quan trọng hơn, RLS phải chặn mọi thao tác bất kể script guard có chạy hay không.
Cách kiểm thử
Mở từng URL admin ở cửa sổ ẩn danh.
Theo dõi Network: không được trả về dữ liệu nhạy cảm trước redirect.
Gọi CRUD trực tiếp không qua UI với token anon/customer phải bị từ chối.
5. profiles tắt RLS; customer có thể đọc/sửa người khác và tự nâng role
Mức độ: Critical
Liên quan: [rls-policies.sql (line 12)](C:/Users/pnvto/cnpm-group-project/docs/database/rls-policies.sql:12), bảng profiles, [admin-profiles.js (line 119)](C:/Users/pnvto/cnpm-group-project/frontend/js/admin-profiles.js:119)
Nguyên nhân
RLS của profiles đang disabled.
Không có policy giới hạn row theo auth.uid().
role và status nằm trong payload update thông thường.
Frontend gửi trực tiếp role lấy từ form tại dòng 140–150.
Khi tạo tài khoản, frontend còn gửi role trong Auth metadata tại dòng 107–111.
Cách lỗi xảy ra
Nếu role anon hoặc authenticated có quyền update bảng:
Customer cập nhật row của mình thành role='admin'.
Customer cập nhật/xóa profile người khác.
Attacker liệt kê tên, số điện thoại, trạng thái của toàn bộ người dùng.
Cách sửa đề xuất
Bật RLS cho profiles.
Customer chỉ SELECT profile của chính mình.
Customer chỉ update các trường cho phép như full_name, phone; không được update role, status, id.
Admin management qua policy admin được kiểm soát hoặc RPC riêng.
Không tin raw_user_meta_data.role; profile mới luôn mặc định customer.
Role admin chỉ được cấp qua quy trình đặc quyền.
Cách kiểm thử
Customer A không select/update/delete profile B.
Customer A update role='admin' phải thất bại.
Customer A update full_name của mình phải thành công.
Sign-up với metadata {role: "admin"} vẫn sinh profile customer.
6. bookings tắt RLS; dữ liệu booking của người khác không được cô lập
Mức độ: Critical
Liên quan: [rls-policies.sql (line 15)](C:/Users/pnvto/cnpm-group-project/docs/database/rls-policies.sql:15), bảng bookings, [booking.js (line 13)](C:/Users/pnvto/cnpm-group-project/frontend/js/booking.js:13), [admin-bookings.js (line 29)](C:/Users/pnvto/cnpm-group-project/frontend/js/admin-bookings.js:29)
Nguyên nhân
RLS của bookings đang disabled.
Không có policy owner/admin.
Trang success đọc booking chỉ bằng ID từ localStorage.
Admin frontend select toàn bộ booking.
Customer history xác định chủ sở hữu bằng guest_email, không phải user_id = auth.uid().
Cách lỗi xảy ra
Nếu API role có table privileges:
Biết hoặc lấy được booking UUID là có thể đọc chi tiết booking.
Thay email giả trong localStorage có thể liệt kê booking theo email người khác.
Gửi update theo booking ID có thể hủy hoặc sửa booking của người khác.
Dữ liệu cá nhân như email, tên và số điện thoại có thể bị lộ.
Cách sửa đề xuất
Bật RLS.
Customer select booking khi user_id = auth.uid().
Customer không được update tùy ý; chỉ hủy booking của mình thông qua RPC hạn chế trạng thái.
Admin select/update dựa trên role thật trong profiles.
Không dùng guest_email làm authorization.
Trang success/history luôn truy vấn row theo quyền RLS, không tin ID trong localStorage.
Cách kiểm thử
Customer A không đọc booking B kể cả biết UUID/email.
Customer A không sửa giá, payment status hoặc booking status của B.
Customer chỉ hủy được booking của mình trong trạng thái cho phép.
Anon không liệt kê được booking.
7. Booking không gắn với auth.uid()
Mức độ: Critical
Liên quan: [schema.sql (line 50)](C:/Users/pnvto/cnpm-group-project/docs/database/schema.sql:50), [booking.js (line 15)](C:/Users/pnvto/cnpm-group-project/frontend/js/booking.js:15), bảng bookings.user_id
Nguyên nhân
user_id cho phép NULL.
Customer payload không gửi user_id.
Database không có RPC/trigger gán user_id := auth.uid().
Luồng booking hiện cho phép booking ẩn danh dù yêu cầu Giai đoạn 1 tập trung vào Auth.
Cách lỗi xảy ra
Booking được tạo không có owner đáng tin cậy. Sau đó hệ thống phải dựa vào email do người đặt tự nhập, khiến authorization không thể bảo đảm.
Nếu sau này frontend bắt đầu gửi user_id, attacker có thể gửi ID của người khác nếu database tiếp tục tin payload.
Cách sửa đề xuất
Chốt Giai đoạn 1: yêu cầu authenticated customer khi tạo booking.
Đặt bookings.user_id NOT NULL.
RPC tạo booking tự lấy auth.uid(); không nhận user_id từ frontend.
Kiểm tra profile tồn tại và status='active'.
Cách kiểm thử
Gọi RPC khi chưa đăng nhập phải thất bại.
Truyền user_id giả không được chấp nhận hoặc bị bỏ qua.
Booking tạo thành công luôn có user_id đúng bằng caller.
User bị blocked không tạo được booking.
8. Frontend hoàn toàn kiểm soát giá và trạng thái booking
Mức độ: Critical
Liên quan: [booking.js (line 15)](C:/Users/pnvto/cnpm-group-project/frontend/js/booking.js:15), [admin-bookings.js (line 88)](C:/Users/pnvto/cnpm-group-project/frontend/js/admin-bookings.js:88), [admin-bookings.html (line 153)](C:/Users/pnvto/cnpm-group-project/frontend/admin-bookings.html:153)
Nguyên nhân
Customer gửi trực tiếp:
price_per_night
subtotal
tax_rate
tax_amount
discount_amount
total_amount
booking_status: confirmed
payment_status: unpaid
Admin form còn cho sửa trực tiếp tổng tiền, payment status và booking status. Không có function database tái tính hoặc kiểm tra các giá trị.
Cách lỗi xảy ra
Attacker sửa request thành:
{
  "price_per_night": 1,
  "subtotal": 0,
  "tax_amount": 0,
  "total_amount": 0,
  "booking_status": "confirmed",
  "payment_status": "paid"
}
Các constraint hiện tại vẫn chấp nhận phần lớn payload này: subtotal và total_amount chỉ cần >= 0.
Cách sửa đề xuất
Tạo RPC booking nhận tối thiểu: room_id, dates, guest count, guest contact, special request.
Giá lấy từ rooms.price_per_night trong cùng transaction.
Database tự tính số đêm, subtotal, tax, discount và total.
Customer không có quyền insert/update trực tiếp bảng bookings.
Payment và lifecycle status chỉ được thay đổi qua RPC admin có transition rules.
Cách kiểm thử
Chỉnh request gửi giá 0/1 hoặc payment_status='paid': database phải bỏ qua hoặc từ chối.
Thay giá phòng giữa lúc mở trang và submit: booking phải dùng giá authoritative tại transaction.
Kiểm tra các công thức tiền bằng test boundary và rounding.
9. Chưa có chống đặt trùng phòng
Mức độ: Critical
Liên quan: bảng bookings, [functions-triggers.sql (line 152)](C:/Users/pnvto/cnpm-group-project/docs/database/functions-triggers.sql:152), [schema.sql (line 50)](C:/Users/pnvto/cnpm-group-project/docs/database/schema.sql:50)
Nguyên nhân
Không có:
Exclusion constraint trên khoảng ngày.
Function kiểm tra overlap.
Lock hoặc serializable booking transaction.
RPC tạo booking nguyên tử.
rooms.status='available' chỉ là trạng thái vận hành, không biểu diễn lịch trống theo ngày.
Cách lỗi xảy ra
Hai khách đặt cùng room_id với các khoảng ngày giao nhau; cả hai insert đều thành công.
Quy tắc overlap đúng cho khoảng [check_in, check_out) là:
existing.check_in < requested.check_out
AND existing.check_out > requested.check_in
Cách sửa đề xuất
Ưu tiên constraint ở database, ví dụ exclusion constraint dùng daterange(check_in_date, check_out_date, '[)') cho cùng room_id, áp dụng với các trạng thái đang giữ phòng. Nếu điều kiện trạng thái làm thiết kế constraint phức tạp, dùng bảng inventory/room stays riêng hoặc RPC có khóa phù hợp, nhưng vẫn nên có invariant ở database.
Cách kiểm thử
Hai booking cùng phòng, cùng ngày: chỉ một thành công.
Khoảng bao chứa, nằm trong và giao một phần đều bị chặn.
Booking có check-in đúng ngày checkout của booking trước phải được phép.
Booking cancelled/completed được xử lý đúng theo quy tắc đã chốt.
10. Có race condition khi hai khách đặt đồng thời
Mức độ: Critical
Liên quan: [booking.js (line 15)](C:/Users/pnvto/cnpm-group-project/frontend/js/booking.js:15), bảng bookings
Nguyên nhân
Frontend đọc phòng và insert booking thành hai bước độc lập. Không có transaction, lock hoặc constraint chống overlap.
Một thao tác “kiểm tra phòng còn trống rồi insert” đơn thuần cũng không đủ: hai transaction có thể cùng thấy phòng trống trước khi một transaction commit.
Cách lỗi xảy ra
Request A và B cùng kiểm tra availability, đều nhận “trống”, rồi cùng insert.
Cách sửa đề xuất
Tạo một RPC transaction duy nhất để kiểm tra, tính giá và insert.
Dùng exclusion constraint làm hàng rào cuối cùng.
Bắt mã lỗi conflict và trả thông báo “phòng vừa được người khác đặt”.
Không dùng frontend check làm cơ chế bảo đảm.
Cách kiểm thử
Chạy 10–50 request đồng thời cho cùng phòng và khoảng ngày:
Chính xác một request thành công.
Các request còn lại nhận lỗi conflict có kiểm soát.
Không có hai row active bị overlap sau test.
11. RLS của các bảng catalog đang vô hiệu hoặc thiếu policy
Mức độ: High
Liên quan: [rls-policies.sql (line 11)](C:/Users/pnvto/cnpm-group-project/docs/database/rls-policies.sql:11)
Bảng	Trạng thái hiện tại	Hệ quả
branches	RLS disabled, có public-select policy	Policy chưa có tác dụng
room_types	RLS disabled, có public-select policy	Policy chưa có tác dụng
rooms	RLS disabled, có public-select policy	Policy chưa có tác dụng
profiles	RLS disabled, không có policy	Không có row isolation
bookings	RLS disabled, không có policy	Không có owner isolation
amenities và bảng phụ	RLS enabled nhưng chưa ghi nhận policy	Frontend có thể bị chặn hoàn toàn
promotions và bảng phụ	RLS enabled nhưng chưa ghi nhận policy	Có thể không đọc được dữ liệu cần thiết

Cách lỗi xảy ra
Với ba bảng catalog tắt RLS, nếu anon/authenticated có write privilege, người ngoài có thể tạo, đổi giá, chuyển trạng thái hoặc xóa phòng/chi nhánh/loại phòng.
Các script admin đang CRUD trực tiếp các bảng này bằng publishable client.
Cách sửa đề xuất
Bật RLS cho toàn bộ bảng public.
Public chỉ select record active/available cần hiển thị.
Chỉ admin thật được insert/update/delete catalog.
Bảng phụ cần policy public-read/admin-write phù hợp.
Rà soát thêm GRANT/REVOKE, không chỉ policy.
Cách kiểm thử
Anon đọc được đúng catalog công khai.
Anon/customer không insert/update/delete catalog.
Không thể xem room inactive/maintenance nếu không được phép.
Admin CRUD thành công.
12. Thiếu các constraint và invariant database quan trọng
Mức độ: High
Liên quan: [schema.sql (line 1)](C:/Users/pnvto/cnpm-group-project/docs/database/schema.sql:1), các bảng rooms, bookings, promotions, room_images
Thiếu hoặc chưa đủ
rooms
Unique (branch_id, room_number).
Có thể cần unique/canonical identifier ổn định cho frontend.
Quy tắc giá authoritative giữa rooms.price_per_night và room_types.base_price chưa rõ.
bookings
check_out_date > check_in_date.
user_id NOT NULL nếu Giai đoạn 1 không hỗ trợ guest booking.
number_of_nights = check_out_date - check_in_date.
number_of_guests <= room_types.capacity.
Các invariant tiền:subtotal tương ứng giá × số đêm.
tax amount tương ứng tax rate.
discount không vượt subtotal + tax theo quy tắc.
total tương ứng công thức.

Chống overlap.
Booking code generation an toàn tại database; mã dùng 4 chữ số cuối của timestamp có khả năng collision.
Quy tắc nhất quán giữa cancelled_at và booking_status.
Quy tắc chuyển trạng thái hợp lệ.
guest_email/phone chỉ mới varchar, chưa có kiểm tra hợp lý.
promotions
end_at > start_at.
Percentage discount không vượt 100%.
used_count <= usage_limit.
Cập nhật usage và booking phải cùng transaction.
room_images
Mỗi phòng tối đa một is_primary=true.
Cách lỗi xảy ra
Dữ liệu có thể hợp lệ theo từng cột nhưng mâu thuẫn ở cấp nghiệp vụ: ngày âm, sai số đêm, vượt sức chứa, total không khớp, promotion quá 100%, nhiều ảnh chính.
Cách sửa đề xuất
Bổ sung constraint cho invariant đơn bảng; invariant qua nhiều bảng hoặc cần transaction đưa vào RPC/trigger có kiểm soát. Không dựa vào HTML min, required hoặc JavaScript validation.
Cách kiểm thử
Mỗi constraint cần test:
Một case hợp lệ.
Boundary case.
Dữ liệu âm/zero.
Dữ liệu mâu thuẫn.
Insert/update trực tiếp bỏ qua frontend.
13. Luồng tạo profile qua frontend không an toàn và không nguyên tử
Mức độ: High
Liên quan: [admin-profiles.js (line 9)](C:/Users/pnvto/cnpm-group-project/frontend/js/admin-profiles.js:9), [functions-triggers.sql (line 152)](C:/Users/pnvto/cnpm-group-project/docs/database/functions-triggers.sql:152)
Nguyên nhân
Admin page dùng một Supabase client khác để gọi public signUp.
Gửi role trong user metadata.
Sau đó update hoặc insert profiles trong một request riêng.
Tài liệu database cho biết chưa tìm thấy trigger tạo profile.
Tạo Auth user và profile không nằm trong một transaction.
Cách lỗi xảy ra
Auth user được tạo nhưng profile thất bại.
Email confirmation có thể khiến workflow không hoạt động như mong muốn.
Nếu metadata role được trigger tin tưởng trong tương lai, người đăng ký có thể tự tạo admin.
Xóa profile không xóa Auth user, tạo tài khoản mồ côi.
Cách sửa đề xuất
Trigger auth.users chỉ tạo profile customer với các trường allowlist.
Không tạo admin bằng public sign-up.
Quản lý user đặc quyền cần server-side/Admin API riêng ở giai đoạn phù hợp; không dùng publishable client.
Giai đoạn 1 có thể giới hạn admin user được tạo thủ công qua quy trình vận hành an toàn.
Cách kiểm thử
Sign-up luôn tạo đúng một profile customer.
Lỗi tạo profile làm workflow được phát hiện và phục hồi rõ ràng.
Metadata role/status tùy ý không ảnh hưởng profile.
Không tạo duplicate hoặc orphan profile.
14. Secret và thông tin nhạy cảm trong repository
Mức độ: High đối với mật khẩu mẫu; Low đối với Supabase publishable key
Liên quan: [supabase-client.js (line 2)](C:/Users/pnvto/cnpm-group-project/frontend/js/supabase-client.js:2), [auth.js (line 84)](C:/Users/pnvto/cnpm-group-project/frontend/js/auth.js:84)
Kết quả rà soát
Có commit project URL và Supabase publishable key.
Không tìm thấy service_role, database password, private key, connection string hoặc JWT bí mật trong các file text được track.
Có mật khẩu admin mẫu admin123.
Publishable/anon key được thiết kế để nằm trong frontend và không phải bí mật. Tuy nhiên key này chỉ an toàn khi RLS và grants đúng; hiện chúng chưa đúng.
Cách lỗi xảy ra
Mật khẩu mẫu có thể được thử trên môi trường thật hoặc tái sử dụng. Publishable key kết hợp với bảng tắt RLS có thể trở thành cổng truy cập dữ liệu.
Cách sửa đề xuất
Xóa credential mẫu khỏi source và thay/khóa tài khoản thật nếu từng dùng mật khẩu đó.
Kiểm tra lịch sử Git và secret scanner trước release.
Không đưa service_role, database URL có password hoặc private key vào frontend/repository.
Quản lý cấu hình deploy bằng environment configuration, nhưng không coi publishable key là secret.
Cách kiểm thử
Secret scanner trên working tree và toàn bộ Git history.
Kiểm tra Supabase logs cho hoạt động bất thường.
Xác nhận service-role key không xuất hiện trong browser bundle/network.
Thử publishable key trực tiếp: mọi thao tác trái phép phải bị RLS từ chối.
Trả lời trực tiếp 12 câu hỏi
Còn đăng nhập giả/localStorage: Có, toàn bộ customer/admin auth hiện là giả.  
Supabase Auth đã dùng đúng: Chưa. Chỉ admin-profiles.js gọi signUp, và luồng đó cũng chưa an toàn.  
Role admin lấy từ đâu: Từ object hard-code/localStorage, không phải profiles cho authorization.  
User tự đổi thành admin: Có thể ngay ở frontend; và nếu table grants cho phép thì có thể update profiles.role.  
RLS năm bảng: profiles, branches, room_types, rooms, bookings đều đang disabled; ba bảng catalog có policy nhưng policy vô hiệu.  
Customer xem/sửa dữ liệu người khác: Có rủi ro trực tiếp và rất cao; bookings/profiles không có row isolation.  
Booking gắn auth.uid(): Không; user_id để NULL, frontend không gắn owner.  
Frontend gửi/sửa giá: Có, gửi toàn bộ price/subtotal/tax/total và status.  
Database chống đặt trùng: Chưa.  
Race condition: Có.  
Constraint thiếu: Nhiều, đặc biệt dates, overlap, ownership, capacity, pricing invariants và unique room number.  
Secret/API key: Không thấy service-role/database password; có publishable key hợp lệ cho frontend nhưng RLS chưa bảo vệ; có mật khẩu admin mẫu bị commit.
Thứ tự triển khai Giai đoạn 1
Task 1 — Chốt mô hình quyền và invariant
Chốt role: customer, admin.
Chốt Giai đoạn 1 bắt buộc đăng nhập khi booking.
Chốt trạng thái nào giữ phòng: thường pending, confirmed, checked_in.
Chốt quy tắc customer cancellation.
Chốt nguồn giá authoritative và công thức thuế.
Chốt handling cho blocked/inactive profile.
Task 2 — Auth và profile foundation
Trigger tạo profiles từ auth.users.
Profile mới luôn là customer.
Bảo đảm một-to-một giữa Auth user và profile.
Thiết lập user_id NOT NULL cho booking sau khi xử lý dữ liệu cũ.
Tạo helper kiểm tra admin an toàn, tránh recursion trong RLS.
Task 3 — Bật RLS và bảo vệ profiles
Enable RLS.
Owner select/update trường allowlist.
Không cho customer update role/status.
Admin policy cho quản lý profile.
Rà soát grants.
Task 4 — Bật RLS cho catalog
branches, room_types, rooms: public read có điều kiện.
Admin-only write.
Policy cho amenities, room images và junction tables.
Kiểm thử anon/customer/admin bằng REST client độc lập.
Task 5 — Thiết lập database invariants booking
Constraint ngày hợp lệ.
Unique room number trong branch.
Capacity validation.
Exclusion constraint hoặc invariant tương đương chống overlap.
Quy tắc booking code và lifecycle.
Constraint/invariant tiền.
Task 6 — RPC tạo booking nguyên tử
RPC cần thực hiện trong một transaction:
Xác thực auth.uid().
Kiểm tra profile active.
Khóa/kiểm tra phòng và khoảng ngày.
Đọc giá thật.
Kiểm tra capacity.
Tính số đêm, thuế và tổng tiền.
Gán user_id = auth.uid().
Insert booking.
Trả kết quả tối thiểu cần thiết.
Chuyển conflict thành lỗi nghiệp vụ rõ ràng.
Task 7 — RLS và RPC quản lý booking
Owner chỉ select booking của mình.
Customer hủy qua RPC hạn chế.
Admin đọc/cập nhật theo role thật.
Không cấp insert/update trực tiếp cho customer.
Tạo trigger status history và quy tắc transition.
Task 8 — Thay frontend Auth giả
Login/register/logout bằng Supabase Auth.
Xóa gostayCurrentUser và gostayUsers.
Header lấy Supabase session/profile.
Guard admin dựa trên session/profile, chỉ dùng cho UX.
Bảo đảm mọi trang admin dùng chung bootstrap.
Task 9 — Thay frontend booking
Frontend chỉ gửi input nghiệp vụ tối thiểu vào RPC.
Không gửi giá, tổng tiền, user_id, payment status hay confirmed status.
History query theo owner/RLS, không theo email.
Success page không tin booking ID từ localStorage nếu row không thuộc caller.
Hiển thị lỗi conflict khi phòng vừa bị đặt.
Task 10 — Security và concurrency test suite
Ma trận anon/customer A/customer B/admin.
Test tự nâng role.
Test IDOR booking/profile.
Test sửa giá/payment status.
Test request đồng thời.
Test overlap boundaries.
Test blocked account.
Secret scan working tree và Git history.
Task 11 — Triển khai có kiểm soát
Backup và kiểm kê dữ liệu hiện hữu.
Xử lý booking có user_id NULL trước constraint.
Áp dụng thay đổi theo migration được review ở giai đoạn triển khai sau.
Smoke test bằng từng role.
Chỉ sau đó mới bật frontend mới.
Không nên bắt đầu bằng việc sửa UI. Thứ tự an toàn là: database invariants → RLS/RPC → Supabase Auth frontend → concurrency/security tests.

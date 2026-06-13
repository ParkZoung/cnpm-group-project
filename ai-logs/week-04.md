# AI Log — Tuần 04

## 1. Công cụ AI đã dùng
- GitHub Copilot AI

## 2. Mục tiêu sử dụng AI trong tuần 4
- Phân tích cấu trúc repo và xác định file/dữ liệu hiện có.
- Tạo nội dung tài liệu yêu cầu `REQUIREMENTS.md` cho tuần 4.
- Chuyển các user story trong `REQUIREMENTS.md` thành nội dung GitHub Issues.
- Ghi lại các prompt quan trọng và bài học rút ra trong tuần.

## 3. Các prompt chính đã dùng
- Prompt phân tích repo: yêu cầu xác định loại dự án, cấu trúc thư mục và file quan trọng.
- Prompt tạo REQUIREMENTS.md: yêu cầu xây dựng Product Overview, Customer/Admin roles, MVP scope, out-of-scope, và user stories, bao gồm story AI gợi ý phòng phù hợp.
- Prompt tạo GitHub Issues: chuyển user stories thành mỗi issue với Title, User Story, Acceptance Criteria theo Given-When-Then, Task checklist, Notes for AI Agent, Priority, Difficulty.
- Prompt review acceptance criteria: kiểm tra tính rõ ràng và chuẩn hóa định dạng Given-When-Then.

## 4. Kết quả AI tạo ra
- `REQUIREMENTS.md` chứa Product Overview, roles, MVP scope, out-of-scope và 11 user stories.
- Nội dung cho 11 GitHub Issues tương ứng với mỗi user story, có title, acceptance criteria, checklist, notes, priority và difficulty.
- `PROMPTS.md` ghi lại các prompt chính nhóm đã sử dụng trong tuần 4.

## 5. Những phần nhóm tự kiểm tra và chỉnh sửa
- Kiểm tra lại nội dung `REQUIREMENTS.md` để đảm bảo tiếng Việt chuẩn và không có lỗi encoding.
- Xác nhận rằng user story AI gợi ý phòng phù hợp đã được đưa vào và rõ ràng.
- Đảm bảo nội dung GitHub Issues phù hợp với yêu cầu: mỗi issue có đủ phần title, user story, acceptance criteria, task checklist, notes, priority, difficulty.
- Loại bỏ các file tạm nếu cần và giữ workspace gọn gàng.

## 6. Lỗi hoặc hạn chế của AI
- Có khả năng nội dung bị lỗi encoding khi ghi file trực tiếp, cần kiểm tra lại bằng UTF-8.
- AI chỉ tạo nội dung văn bản; các phần hành động thực tế cần do nhóm kiểm tra để đảm bảo phù hợp với kế hoạch và syntax GitHub.
- AI không tự động phân biệt chi tiết kỹ thuật backend/frontend có thể cần chỉnh sửa thêm.

## 7. Bài học rút ra
- Luôn đọc lại và xác thực nội dung AI tạo ra, đặc biệt với ngôn ngữ tiếng Việt và encoding file.
- Tạo prompt rõ ràng, cụ thể giúp AI sinh ra kết quả đúng định dạng mong muốn.
- Lưu lại prompt sử dụng để dễ tái sử dụng và đảm bảo tính nhất quán giữa các thành viên nhóm.
- Phần review của nhóm là cần thiết để phát hiện và khắc phục sai sót do AI tạo ra.

// Thông tin kết nối dự án Supabase
const SUPABASE_URL = "https://wpecaxsuadawaxadxqhj.supabase.co";
const SUPABASE_PUBLISHABLE_KEY =
    "sb_publishable_RZw0kA0la2a-ioYiM0C2aQ_G0ac8Y4f";

// Kiểm tra thư viện Supabase đã được tải chưa
if (!window.supabase || !window.supabase.createClient) {
    throw new Error("Thư viện Supabase chưa được tải.");
}

// Tạo Supabase Client dùng chung cho toàn bộ Frontend
window.gostaySupabase = window.supabase.createClient(
    SUPABASE_URL,
    SUPABASE_PUBLISHABLE_KEY
);

console.log("Đã khởi tạo Supabase Client.");
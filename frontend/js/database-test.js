async function testDatabaseConnection() {
    const statusElement = document.getElementById("connection-status");
    const resultElement = document.getElementById("database-result");

    statusElement.textContent = "Đang kết nối với Supabase...";

    try {
        const { data, error } = await window.gostaySupabase
            .from("rooms")
            .select(`
                id,
                room_number,
                name,
                price_per_night,
                status
            `)
            .order("id", { ascending: true });

        if (error) {
            throw error;
        }

        statusElement.textContent =
            `Kết nối thành công. Tìm thấy ${data.length} phòng.`;

        resultElement.textContent = JSON.stringify(data, null, 2);

        console.log("Dữ liệu phòng:", data);
    } catch (error) {
        console.error("Lỗi Supabase:", error);

        statusElement.textContent = "Kết nối thất bại.";
        resultElement.textContent = error.message;
    }
}

document.addEventListener(
    "DOMContentLoaded",
    testDatabaseConnection
);
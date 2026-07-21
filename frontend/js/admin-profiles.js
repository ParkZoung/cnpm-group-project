document.addEventListener("DOMContentLoaded", () => {
  const db = window.gostaySupabase;
  const $ = (id) => document.getElementById(id);
  const tableBody = $("profilesTableBody");
  const modal = $("profileModal");
  const form = $("profileForm");
  const saveButton = $("btnSaveProfile");
  const message = $("pageMessage");
  // Dùng duy nhất một client tách biệt để tạo Auth user mà không đổi phiên admin.
  const signupClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
      storageKey: "gostay-admin-signup"
    }
  });
  let profiles = [];

  const escapeHtml = (value = "") => String(value).replace(/[&<>'"]/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;"
  })[char]);

  function notify(text, type = "error") {
    message.textContent = text;
    message.className = `users-message${type === "success" ? " success" : ""}`;
    message.hidden = false;
    window.clearTimeout(notify.timer);
    notify.timer = window.setTimeout(() => { message.hidden = true; }, 4500);
  }

  function statusLabel(status) {
    return { active: "Hoạt động", inactive: "Ngưng hoạt động", blocked: "Đã khóa" }[status] || status;
  }

  function render(rows) {
    $("totalProfiles").textContent = profiles.length;
    $("activeProfiles").textContent = profiles.filter((item) => item.status === "active").length;
    $("blockedProfiles").textContent = profiles.filter((item) => item.status === "blocked").length;

    if (!rows.length) {
      tableBody.innerHTML = '<tr><td colspan="6" class="users-empty">Không tìm thấy hồ sơ phù hợp.</td></tr>';
      return;
    }

    tableBody.innerHTML = rows.map((profile) => {
      const name = profile.full_name || "Chưa cập nhật";
      const initial = name.trim().charAt(0).toUpperCase() || "?";
      const date = profile.created_at ? new Date(profile.created_at).toLocaleDateString("vi-VN") : "—";
      return `<tr>
        <td><div class="users-person"><span class="users-avatar">${escapeHtml(initial)}</span><div><strong>${escapeHtml(name)}</strong><small>#${escapeHtml(profile.id.slice(0, 8))}</small></div></div></td>
        <td>${escapeHtml(profile.phone || "—")}</td>
        <td><span class="users-pill role-${escapeHtml(profile.role)}">${profile.role === "admin" ? "Quản trị viên" : "Khách hàng"}</span></td>
        <td><span class="users-pill status-${escapeHtml(profile.status)}">${escapeHtml(statusLabel(profile.status))}</span></td>
        <td>${date}</td>
        <td><div class="users-actions"><button class="users-action" data-action="edit" data-id="${escapeHtml(profile.id)}">Sửa</button><button class="users-action delete" data-action="delete" data-id="${escapeHtml(profile.id)}">Xóa</button></div></td>
      </tr>`;
    }).join("");
  }

  function applyFilters() {
    const term = $("inputSearch").value.trim().toLocaleLowerCase("vi");
    const role = $("selectRoleFilter").value;
    const status = $("selectStatusFilter").value;
    render(profiles.filter((profile) => {
      const matchesText = !term || `${profile.full_name || ""} ${profile.phone || ""}`.toLocaleLowerCase("vi").includes(term);
      return matchesText && (!role || profile.role === role) && (!status || profile.status === status);
    }));
  }

  async function loadProfiles() {
    tableBody.innerHTML = '<tr><td colspan="6" class="users-empty">Đang tải dữ liệu...</td></tr>';
    const { data, error } = await db.from("profiles").select("id, full_name, phone, role, status, created_at").order("created_at", { ascending: false });
    if (error) {
      tableBody.innerHTML = `<tr><td colspan="6" class="users-empty">Không thể tải dữ liệu: ${escapeHtml(error.message)}</td></tr>`;
      return notify(`Lỗi Supabase: ${error.message}`);
    }
    profiles = data || [];
    applyFilters();
  }

  function openModal(profile = null) {
    form.reset();
    $("profileId").value = profile?.id || "";
    $("modalTitle").textContent = profile ? "Chỉnh sửa hồ sơ" : "Thêm khách hàng";
    $("accountFields").hidden = Boolean(profile);
    $("accountHint").hidden = Boolean(profile);
    $("profileEmail").required = !profile;
    $("profilePassword").required = !profile;
    if (profile) {
      $("profileFullName").value = profile.full_name || "";
      $("profilePhone").value = profile.phone || "";
      $("profileRole").value = profile.role || "customer";
      $("profileStatus").value = profile.status || "active";
    }
    modal.hidden = false;
    document.body.style.overflow = "hidden";
    window.setTimeout(() => $("profileFullName").focus(), 0);
  }

  function closeModal() {
    modal.hidden = true;
    document.body.style.overflow = "";
  }

  async function createProfile(payload) {
    const { data: authData, error: authError } = await signupClient.auth.signUp({
      email: $("profileEmail").value.trim(),
      password: $("profilePassword").value,
      options: { data: { full_name: payload.full_name, role: payload.role } }
    });
    if (authError) throw authError;
    if (!authData.user) throw new Error("Supabase Auth không trả về người dùng mới.");
    if (Array.isArray(authData.user.identities) && authData.user.identities.length === 0) {
      throw new Error("Email này đã có tài khoản. Hãy dùng email khác hoặc sửa hồ sơ hiện có.");
    }

    // Trigger của database có thể đã tự tạo profiles sau signUp, nên cập nhật trước.
    const { data: updatedRows, error: updateError } = await db
      .from("profiles")
      .update(payload)
      .eq("id", authData.user.id)
      .select("id");
    if (updateError) throw new Error(`Đã tạo Auth nhưng chưa cập nhật được hồ sơ: ${updateError.message}`);

    if (!updatedRows || updatedRows.length === 0) {
      const { error: insertError } = await db.from("profiles").insert({ id: authData.user.id, ...payload });
      if (insertError) {
        const detail = insertError.code === "23505"
          ? "Hồ sơ đã tồn tại nhưng tài khoản hiện tại không có quyền cập nhật. Kiểm tra RLS policy của bảng profiles."
          : insertError.message;
        throw new Error(`Đã tạo Auth nhưng chưa lưu được hồ sơ: ${detail}`);
      }
    }
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const id = $("profileId").value;
    const payload = {
      full_name: $("profileFullName").value.trim(),
      phone: $("profilePhone").value.trim() || null,
      role: $("profileRole").value,
      status: $("profileStatus").value
    };
    saveButton.disabled = true;
    saveButton.textContent = "Đang lưu...";
    try {
      if (id) {
        const { error } = await db.from("profiles").update(payload).eq("id", id);
        if (error) throw error;
      } else {
        await createProfile(payload);
      }
      closeModal();
      notify(id ? "Đã cập nhật hồ sơ." : "Đã tạo tài khoản và hồ sơ khách hàng.", "success");
      await loadProfiles();
    } catch (error) {
      notify(error.message);
    } finally {
      saveButton.disabled = false;
      saveButton.textContent = "Lưu hồ sơ";
    }
  });

  tableBody.addEventListener("click", async (event) => {
    const button = event.target.closest("[data-action]");
    if (!button) return;
    const profile = profiles.find((item) => item.id === button.dataset.id);
    if (!profile) return;
    if (button.dataset.action === "edit") return openModal(profile);
    if (!window.confirm(`Xóa hồ sơ của “${profile.full_name || "khách hàng này"}”? Tài khoản Auth sẽ không bị xóa.`)) return;
    button.disabled = true;
    const { error } = await db.from("profiles").delete().eq("id", profile.id);
    if (error) {
      button.disabled = false;
      return notify(`Không thể xóa hồ sơ: ${error.message}`);
    }
    notify("Đã xóa hồ sơ. Tài khoản Supabase Auth vẫn được giữ lại.", "success");
    await loadProfiles();
  });

  $("btnOpenAddModal").addEventListener("click", () => openModal());
  $("btnCloseModal").addEventListener("click", closeModal);
  modal.querySelectorAll("[data-close-modal]").forEach((node) => node.addEventListener("click", closeModal));
  $("btnFilter").addEventListener("click", applyFilters);
  $("inputSearch").addEventListener("input", applyFilters);
  $("topbarCustomerSearch").addEventListener("input", (event) => {
    $("inputSearch").value = event.target.value;
    applyFilters();
  });
  $("selectRoleFilter").addEventListener("change", applyFilters);
  $("selectStatusFilter").addEventListener("change", applyFilters);
  document.addEventListener("keydown", (event) => { if (event.key === "Escape" && !modal.hidden) closeModal(); });

  loadProfiles();
});

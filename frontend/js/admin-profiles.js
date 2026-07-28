document.addEventListener("DOMContentLoaded", async () => {
  const adminContext = await window.gostayAdminReady;
  if (!adminContext) return;

  const db = window.gostaySupabase;
  const $ = (id) => document.getElementById(id);
  const tableBody = $("profilesTableBody");
  const modal = $("profileModal");
  const form = $("profileForm");
  const saveButton = $("btnSaveProfile");
  const message = $("pageMessage");
  const state = {
    profiles: [],
    isUpdating: false,
    isRedirecting: false
  };

  const escapeHtml = (value = "") => String(value).replace(/[&<>'"]/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;"
  })[char]);

  function notify(text, type = "error") {
    message.textContent = text;
    message.className = `users-message${type === "success" ? " success" : ""}`;
    message.hidden = false;
    window.clearTimeout(notify.timer);
    notify.timer = window.setTimeout(() => { message.hidden = true; }, 6000);
  }

  function logSupabaseError(label, error) {
    console.error(label, {
      code: error?.code,
      message: error?.message,
      details: error?.details,
      hint: error?.hint
    });
  }

  function statusLabel(status) {
    return {
      active: "Hoạt động",
      inactive: "Ngưng hoạt động",
      blocked: "Đã khóa"
    }[status] || status;
  }

  function setMutationLock(isUpdating) {
    state.isUpdating = isUpdating;
    saveButton.disabled = isUpdating;
    saveButton.textContent = isUpdating ? "Đang lưu..." : "Lưu hồ sơ";
    $("profileRole").disabled = isUpdating;
    $("profileStatus").disabled = isUpdating;
    $("btnCloseModal").disabled = isUpdating;
    modal.querySelectorAll("[data-close-modal]").forEach((node) => {
      node.disabled = isUpdating;
    });
    tableBody.querySelectorAll("[data-action]").forEach((node) => {
      node.disabled = isUpdating;
    });
  }

  function render(rows) {
    $("totalProfiles").textContent = state.profiles.length;
    $("activeProfiles").textContent = state.profiles.filter((item) => item.status === "active").length;
    $("blockedProfiles").textContent = state.profiles.filter((item) => item.status === "blocked").length;

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
        <td><div class="users-actions"><button class="users-action" type="button" data-action="edit" data-id="${escapeHtml(profile.id)}"${state.isUpdating ? " disabled" : ""}>Sửa quyền</button></div></td>
      </tr>`;
    }).join("");
  }

  function applyFilters() {
    const term = $("inputSearch").value.trim().toLocaleLowerCase("vi");
    const role = $("selectRoleFilter").value;
    const status = $("selectStatusFilter").value;
    render(state.profiles.filter((profile) => {
      const matchesText = !term || `${profile.full_name || ""} ${profile.phone || ""}`.toLocaleLowerCase("vi").includes(term);
      return matchesText && (!role || profile.role === role) && (!status || profile.status === status);
    }));
  }

  async function loadProfiles() {
    tableBody.innerHTML = '<tr><td colspan="6" class="users-empty">Đang tải dữ liệu...</td></tr>';
    const { data, error } = await db
      .from("profiles")
      .select("id, full_name, phone, role, status, created_at")
      .order("created_at", { ascending: false });

    if (error) {
      tableBody.innerHTML = '<tr><td colspan="6" class="users-empty">Không thể tải danh sách hồ sơ.</td></tr>';
      throw error;
    }

    state.profiles = data || [];
    applyFilters();
  }

  function openModal(profile) {
    if (state.isUpdating) {
      notify("Vui lòng chờ thao tác cập nhật hiện tại hoàn tất.");
      return;
    }
    if (!profile) return;

    form.reset();
    $("profileId").value = profile.id;
    $("modalTitle").textContent = "Cập nhật quyền hồ sơ";
    $("profileEmail").value = "Không khả dụng từ public.profiles";
    $("profileFullName").value = profile.full_name || "";
    $("profilePhone").value = profile.phone || "";
    $("profileRole").value = profile.role || "customer";
    $("profileStatus").value = profile.status || "active";
    modal.hidden = false;
    document.body.style.overflow = "hidden";
    window.setTimeout(() => $("profileRole").focus(), 0);
  }

  function closeModal() {
    if (state.isUpdating) {
      notify("Không thể đóng cửa sổ khi hồ sơ đang được cập nhật.");
      return;
    }
    modal.hidden = true;
    document.body.style.overflow = "";
  }

  function forceCloseModal() {
    modal.hidden = true;
    document.body.style.overflow = "";
  }

  function friendlyMutationError(error) {
    const rawMessage = String(error?.message || "").toLowerCase();
    if (error?.code === "23514" || rawMessage.includes("last active admin")) {
      return "Không thể hạ quyền, khóa hoặc ngưng hoạt động quản trị viên đang hoạt động cuối cùng.";
    }
    if (error?.code === "42501") {
      return "Phiên hiện tại không còn quyền quản trị. Vui lòng đăng nhập lại.";
    }
    if (error?.code === "P0002") {
      return "Hồ sơ không còn tồn tại. Danh sách sẽ được tải lại.";
    }
    if (error?.code === "22023") {
      return "Vai trò hoặc trạng thái được chọn không hợp lệ.";
    }
    return "Không thể cập nhật quyền hồ sơ. Vui lòng thử lại.";
  }

  async function reloadAfterMutation() {
    try {
      await loadProfiles();
      return true;
    } catch (error) {
      logSupabaseError("Admin profiles reload failed", error);
      return false;
    }
  }

  async function signOutAndRedirect() {
    state.isRedirecting = true;
    forceCloseModal();
    setMutationLock(true);

    try {
      const { error } = await db.auth.signOut();
      if (error) logSupabaseError("Admin profiles sign out failed", error);
    } catch (error) {
      logSupabaseError("Admin profiles sign out failed", error);
    } finally {
      window.location.replace("login.html");
    }
  }

  async function verifyCallerStillActiveAdmin() {
    let callerProfile;
    try {
      const { data, error } = await db
        .from("profiles")
        .select("role, status")
        .eq("id", adminContext.user.id)
        .maybeSingle();
      if (error) throw error;
      callerProfile = data;
    } catch (error) {
      logSupabaseError("Admin profiles authorization recheck failed", error);
      await signOutAndRedirect();
      return false;
    }

    if (callerProfile?.role === "admin" && callerProfile.status === "active") {
      return true;
    }

    await signOutAndRedirect();
    return false;
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (state.isUpdating) return;

    const id = $("profileId").value;
    const profile = state.profiles.find((item) => item.id === id);
    if (!profile) {
      notify("Không tìm thấy hồ sơ cần cập nhật. Danh sách sẽ được tải lại.");
      await reloadAfterMutation();
      return;
    }

    const newRole = $("profileRole").value;
    const newStatus = $("profileStatus").value;
    const roleChanged = newRole !== profile.role;
    const statusChanged = newStatus !== profile.status;
    const isSelfUpdate = id === adminContext.user.id;

    if (!roleChanged && !statusChanged) {
      forceCloseModal();
      notify("Không có thay đổi cần lưu.");
      return;
    }

    if (isSelfUpdate && roleChanged && statusChanged) {
      notify("Bạn chỉ có thể thay đổi một trong hai: vai trò hoặc trạng thái của chính mình trong mỗi lần cập nhật.");
      return;
    }

    setMutationLock(true);
    const completedChanges = [];
    let mutationError = null;

    try {
      try {
        if (roleChanged) {
          const { error } = await db.rpc("admin_set_profile_role", {
            target_user_id: id,
            new_role: newRole
          });
          if (error) throw error;
          completedChanges.push("vai trò");
        }

        if (statusChanged) {
          const { error } = await db.rpc("admin_set_profile_status", {
            target_user_id: id,
            new_status: newStatus
          });
          if (error) throw error;
          completedChanges.push("trạng thái");
        }
      } catch (error) {
        mutationError = error;
        logSupabaseError("Admin profile mutation failed", error);
      }

      const reloadSucceeded = await reloadAfterMutation();
      const callerStillAuthorized = await verifyCallerStillActiveAdmin();
      if (!callerStillAuthorized) return;

      if (mutationError) {
        forceCloseModal();
        const baseMessage = friendlyMutationError(mutationError);
        if (completedChanges.length) {
          notify(`Hồ sơ đã được cập nhật một phần (${completedChanges.join(", ")}). ${baseMessage}`);
        } else {
          notify(baseMessage);
        }
        if (!reloadSucceeded) {
          notify(`${message.textContent} Chưa thể tải lại danh sách; vui lòng tải lại trang.`);
        }
      } else {
        forceCloseModal();
        if (reloadSucceeded) {
          notify("Đã cập nhật quyền hồ sơ.", "success");
        } else {
          notify("Đã cập nhật thành công, nhưng chưa thể tải lại danh sách. Vui lòng tải lại trang.");
        }
      }
    } finally {
      if (!state.isRedirecting) setMutationLock(false);
    }
  });

  tableBody.addEventListener("click", (event) => {
    const button = event.target.closest('[data-action="edit"]');
    if (!button || state.isUpdating) return;
    const profile = state.profiles.find((item) => item.id === button.dataset.id);
    if (profile) openModal(profile);
  });

  $("btnCloseModal").addEventListener("click", closeModal);
  modal.querySelectorAll("[data-close-modal]").forEach((node) => {
    node.addEventListener("click", closeModal);
  });
  $("btnFilter").addEventListener("click", applyFilters);
  $("inputSearch").addEventListener("input", applyFilters);
  $("topbarCustomerSearch").addEventListener("input", (event) => {
    $("inputSearch").value = event.target.value;
    applyFilters();
  });
  $("selectRoleFilter").addEventListener("change", applyFilters);
  $("selectStatusFilter").addEventListener("change", applyFilters);

  try {
    await loadProfiles();
  } catch (error) {
    logSupabaseError("Admin profiles load failed", error);
    notify("Không thể tải danh sách hồ sơ. Vui lòng tải lại trang.");
  }
});

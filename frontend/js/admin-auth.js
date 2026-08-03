(function () {
  'use strict';

  window.gostayAdminReady = verifyActiveAdmin().catch(function () {
    return null;
  });

  async function verifyActiveAdmin() {
    try {
      if (!window.gostaySupabase) {
        throw new Error('Supabase chưa được khởi tạo.');
      }

      const { data: sessionData, error: sessionError } =
        await window.gostaySupabase.auth.getSession();

      if (sessionError) throw sessionError;

      const session = sessionData.session;
      if (!session || !session.user || !session.user.id) {
        throw new Error('Bạn chưa đăng nhập.');
      }

      const { data: profile, error: profileError } = await window.gostaySupabase
        .from('profiles')
        .select('id, full_name, role, status')
        .eq('id', session.user.id)
        .maybeSingle();

      if (profileError) throw profileError;
      if (!profile) throw new Error('Không tìm thấy hồ sơ tài khoản.');
      if (profile.role !== 'admin' || profile.status !== 'active') {
        throw new Error('Tài khoản không có quyền quản trị đang hoạt động.');
      }

      bindAdminLogout();
      showAuthenticatedAdmin(session.user, profile);
      return { session: session, user: session.user, profile: profile };
    } catch (error) {
      await signOutAndRedirect();
      throw error;
    }
  }

  function bindAdminLogout() {
    const bind = function () {
      const logoutLink = document.querySelector('.logout-item');
      if (!logoutLink || logoutLink.dataset.authBound === 'true') return;

      logoutLink.dataset.authBound = 'true';
      logoutLink.addEventListener('click', async function (event) {
        event.preventDefault();
        logoutLink.setAttribute('aria-disabled', 'true');

        try {
          await signOutSafely();
        } finally {
          window.location.replace('login.html');
        }
      });
    };

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', bind, { once: true });
    } else {
      bind();
    }
  }

  function showAuthenticatedAdmin(user, profile) {
    const label = String(profile.full_name || user.email || 'Admin').trim() || 'Admin';
    document.querySelectorAll('.user-name').forEach(function (element) {
      element.textContent = label;
    });
  }

  async function signOutAndRedirect() {
    try {
      await signOutSafely();
    } finally {
      window.location.replace('login.html');
    }
  }

  async function signOutSafely() {
    if (!window.gostaySupabase) return;

    try {
      const { error } = await window.gostaySupabase.auth.signOut();
      if (!error) return;
      console.error('Không thể hoàn tất đăng xuất:', error.message);
    } catch (error) {
      console.error('Không thể hoàn tất đăng xuất:', error);
    }

    try {
      const { error } = await window.gostaySupabase.auth.signOut({ scope: 'local' });
      if (error) console.error('Không thể xóa phiên đăng nhập cục bộ:', error.message);
    } catch (error) {
      console.error('Không thể xóa phiên đăng nhập cục bộ:', error);
    }
  }
}());

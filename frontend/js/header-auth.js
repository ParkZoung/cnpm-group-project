(function () {
  'use strict';

  if (window.gostayHeaderAuthInitialized) return;
  window.gostayHeaderAuthInitialized = true;

  document.addEventListener('DOMContentLoaded', function () {
    updateActiveHeaderNav();
    initializeHeaderAuth();
  }, { once: true });

  function updateActiveHeaderNav() {
    const navLinks = document.querySelectorAll('.main-nav a');
    const currentPage = window.location.pathname.split('/').pop() || 'index.html';
    const bookingPages = ['booking.html', 'bookingsuccess.html'];
    const activePage = bookingPages.includes(currentPage) ? 'search.html' : currentPage;

    navLinks.forEach(function (link) {
      const isActive = link.getAttribute('href') === activePage;
      link.classList.toggle('active-nav', isActive);
      if (isActive) link.setAttribute('aria-current', 'page');
      else link.removeAttribute('aria-current');
    });
  }

  async function initializeHeaderAuth() {
    const authArea = document.querySelector('.auth');
    if (!authArea) return;

    if (!window.gostaySupabase) {
      renderSignedOut(authArea);
      return;
    }

    try {
      const { data, error } = await window.gostaySupabase.auth.getSession();
      if (error) throw error;
      await renderSession(authArea, data.session);
    } catch (error) {
      try {
        await signOutSafely();
      } finally {
        renderSignedOut(authArea);
      }
    }

    window.gostaySupabase.auth.onAuthStateChange(function (_event, session) {
      window.setTimeout(function () {
        renderSession(authArea, session).catch(async function () {
          try {
            await signOutSafely();
          } finally {
            renderSignedOut(authArea);
          }
        });
      }, 0);
    });
  }

  async function renderSession(authArea, session) {
    if (!session || !session.user || !session.user.id) {
      renderSignedOut(authArea);
      return;
    }

    const { data: profile, error } = await window.gostaySupabase
      .from('profiles')
      .select('id, full_name, role, status')
      .eq('id', session.user.id)
      .maybeSingle();

    if (error || !profile || profile.status !== 'active' ||
        (profile.role !== 'admin' && profile.role !== 'customer')) {
      throw error || new Error('Hồ sơ tài khoản không hợp lệ.');
    }

    renderSignedIn(authArea, session.user, profile);
  }

  function renderSignedIn(authArea, user, profile) {
    const displayName = profile.full_name || user.email || 'Người dùng';
    authArea.innerHTML = '';

    const userArea = document.createElement('div');
    userArea.className = 'user-area';

    const userPill = document.createElement('span');
    userPill.className = 'user-pill';
    userPill.textContent = 'Xin chào, ' + displayName;

    const logoutLink = document.createElement('a');
    logoutLink.className = 'logout-link';
    logoutLink.href = '#';
    logoutLink.textContent = 'Đăng xuất';
    logoutLink.addEventListener('click', async function (event) {
      event.preventDefault();
      if (logoutLink.dataset.submitting === 'true') return;

      logoutLink.dataset.submitting = 'true';
      logoutLink.setAttribute('aria-disabled', 'true');
      logoutLink.textContent = 'Đang đăng xuất...';

      try {
        await signOutSafely();
      } finally {
        renderSignedOut(authArea);
        window.location.assign('login.html');
      }
    });

    userArea.appendChild(userPill);
    userArea.appendChild(logoutLink);
    authArea.appendChild(userArea);
  }

  function renderSignedOut(authArea) {
    authArea.innerHTML = '';
    const loginLink = document.createElement('a');
    loginLink.href = 'login.html';
    loginLink.textContent = 'Đăng nhập';
    authArea.appendChild(loginLink);
  }

  async function signOutSafely() {
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

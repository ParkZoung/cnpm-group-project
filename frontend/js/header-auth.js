(function () {
  'use strict';

  if (window.gostayHeaderAuthInitialized) {
    return;
  }

  window.gostayHeaderAuthInitialized = true;

  document.addEventListener('DOMContentLoaded', function () {
    updateActiveHeaderNav();
    initializeHeaderAuth();
  }, { once: true });
}());

function updateActiveHeaderNav() {
  const navLinks = document.querySelectorAll('.main-nav a');
  const currentPage = window.location.pathname.split('/').pop() || 'index.html';
  const bookingPages = ['booking.html', 'bookingsuccess.html'];
  const activePage = bookingPages.includes(currentPage) ? 'cart.html' : currentPage;

  navLinks.forEach(function (link) {
    const linkPage = link.getAttribute('href');
    const isActive = linkPage === activePage;

    link.classList.toggle('active-nav', isActive);

    if (isActive) {
      link.setAttribute('aria-current', 'page');
    } else {
      link.removeAttribute('aria-current');
    }
  });
}

async function initializeHeaderAuth() {
  const authArea = document.querySelector('.auth');

  if (!authArea) {
    return;
  }

  if (!window.gostaySupabase) {
    renderSignedOutHeader(authArea);
    return;
  }

  try {
    const { data, error } = await window.gostaySupabase.auth.getSession();

    if (error) {
      throw error;
    }

    renderHeaderSession(authArea, data.session);
  } catch (error) {
    renderSignedOutHeader(authArea);
    showHeaderAuthError(authArea, 'Không thể kiểm tra phiên đăng nhập.');
  }

  window.gostaySupabase.auth.onAuthStateChange(function (_event, session) {
    renderHeaderSession(authArea, session);
  });
}

function renderHeaderSession(authArea, session) {
  if (session && session.user) {
    renderSignedInHeader(authArea, session.user);
  } else {
    renderSignedOutHeader(authArea);
  }
}

function renderSignedInHeader(authArea, user) {
  const metadata = user.user_metadata || {};
  const displayName = metadata.full_name || metadata.name || user.email || 'Người dùng';

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

    if (logoutLink.dataset.submitting === 'true') {
      return;
    }

    logoutLink.dataset.submitting = 'true';
    logoutLink.setAttribute('aria-disabled', 'true');
    logoutLink.textContent = 'Đang đăng xuất...';

    const { error } = await window.gostaySupabase.auth.signOut();

    if (error) {
      logoutLink.dataset.submitting = 'false';
      logoutLink.removeAttribute('aria-disabled');
      logoutLink.textContent = 'Đăng xuất';
      showHeaderAuthError(authArea, 'Không thể đăng xuất. Vui lòng thử lại.');
      return;
    }

    window.location.assign('login.html');
  });

  userArea.appendChild(userPill);
  userArea.appendChild(logoutLink);
  authArea.appendChild(userArea);
}

function renderSignedOutHeader(authArea) {
  authArea.innerHTML = '';

  const loginLink = document.createElement('a');
  loginLink.href = 'login.html';
  loginLink.textContent = 'Đăng nhập';
  authArea.appendChild(loginLink);
}

function showHeaderAuthError(authArea, message) {
  const errorElement = document.createElement('span');
  errorElement.className = 'auth-error';
  errorElement.setAttribute('role', 'alert');
  errorElement.textContent = message;
  authArea.appendChild(errorElement);
}

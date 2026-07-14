document.addEventListener('DOMContentLoaded', function () {
  updateHeaderLoginState();
});

function updateHeaderLoginState() {
  const authArea = document.querySelector('.auth');
  const currentUser = getHeaderCurrentUser();

  if (!authArea || !currentUser) {
    return;
  }

  const displayName = currentUser.name || currentUser.email;

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

  logoutLink.addEventListener('click', function (event) {
    event.preventDefault();
    localStorage.removeItem('gostayCurrentUser');
    alert('Đã đăng xuất');
    window.location.href = 'index.html';
  });

  userArea.appendChild(userPill);
  userArea.appendChild(logoutLink);
  authArea.appendChild(userArea);
}

function getHeaderCurrentUser() {
  const savedUser = localStorage.getItem('gostayCurrentUser');

  if (!savedUser) {
    return null;
  }

  try {
    return JSON.parse(savedUser);
  } catch (error) {
    localStorage.removeItem('gostayCurrentUser');
    return null;
  }
}

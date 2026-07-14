document.addEventListener('DOMContentLoaded', function () {
  const savedUser = localStorage.getItem('gostayCurrentUser');
  const currentUser = savedUser ? JSON.parse(savedUser) : null;

  // Frontend demo only. Real admin protection must be handled by a backend later.
  if (!currentUser || currentUser.role !== 'admin') {
    alert('Bạn cần đăng nhập bằng tài khoản admin để vào trang quản trị.');
    window.location.href = 'login.html';
    return;
  }

  const logoutLink = document.querySelector('.logout-item');

  if (logoutLink) {
    logoutLink.addEventListener('click', function () {
      localStorage.removeItem('gostayCurrentUser');
      alert('Logged out successfully');
    });
  }
});

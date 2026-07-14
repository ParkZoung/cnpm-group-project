document.addEventListener('DOMContentLoaded', function () {
  showCurrentUser();
  setupLogout();
  setupRegisterForm();
  setupLoginForm();
});

function getCurrentUser() {
  const savedUser = localStorage.getItem('gostayCurrentUser');

  if (!savedUser) {
    return null;
  }

  return JSON.parse(savedUser);
}

function showCurrentUser() {
  const authArea = document.querySelector('.auth');
  const currentUser = getCurrentUser();

  if (!authArea || !currentUser) {
    return;
  }

  const displayName = currentUser.name || currentUser.email;

  authArea.innerHTML = '';

  const userArea = document.createElement('div');
  userArea.className = 'user-area';

  const userPill = document.createElement('span');
  userPill.className = 'user-pill';
  userPill.textContent = 'Xin chao, ' + displayName;

  const logoutLink = document.createElement('a');
  logoutLink.className = 'logout-link';
  logoutLink.href = '#';
  logoutLink.id = 'logout-link';
  logoutLink.textContent = 'Dang xuat';

  userArea.appendChild(userPill);
  userArea.appendChild(logoutLink);
  authArea.appendChild(userArea);
}

function setupLogout() {
  const logoutLink = document.getElementById('logout-link');

  if (!logoutLink) {
    return;
  }

  logoutLink.addEventListener('click', function (event) {
    event.preventDefault();
    localStorage.removeItem('gostayCurrentUser');
    alert('Logged out successfully');
    window.location.href = 'index.html';
  });
}

function setupLoginForm() {
  const loginForm = document.querySelector('.auth-form');

  if (!loginForm || document.getElementById('fullname')) {
    return;
  }

  loginForm.addEventListener('submit', function (event) {
    event.preventDefault();

    const emailInput = loginForm.querySelector('input[type="text"]');
    const passwordInput = loginForm.querySelector('input[type="password"]');
    const email = emailInput.value.trim();
    const password = passwordInput.value.trim();

    // Check that the user entered both fields before demo login.
    if (email === '' || password === '') {
      alert('Please enter both email and password.');
      return;
    }

    // Demo only: real admin login must be checked by a backend later.
    if (email.toLowerCase() === 'admin@gostay.vn' && password === 'admin123') {
      const adminUser = {
        name: 'Admin GoStay',
        email: 'admin@gostay.vn',
        role: 'admin',
        loginTime: new Date().toISOString()
      };

      localStorage.setItem('gostayCurrentUser', JSON.stringify(adminUser));

      alert('Đăng nhập admin thành công');
      window.location.href = 'admin-dashboard.html';
      return;
    }

    const currentUser = {
      email: email,
      name: email,
      role: 'customer',
      loginTime: new Date().toISOString()
    };

    localStorage.setItem('gostayCurrentUser', JSON.stringify(currentUser));

    alert('Đăng nhập thành công');
    window.location.href = 'index.html';
  });
}

function setupRegisterForm() {
  const registerForm = document.querySelector('.auth-form');
  const fullnameInput = document.getElementById('fullname');
  const emailInput = document.getElementById('email');
  const phoneInput = document.getElementById('phone');
  const usernameInput = document.getElementById('username');
  const passwordInput = document.getElementById('password');
  const agreeInput = document.querySelector('input[name="agree"]');

  if (!registerForm || !fullnameInput || !emailInput || !usernameInput || !passwordInput) {
    return;
  }

  registerForm.addEventListener('submit', function (event) {
    event.preventDefault();

    const fullname = fullnameInput.value.trim();
    const email = emailInput.value.trim();
    const phone = phoneInput.value.trim();
    const username = usernameInput.value.trim();
    const password = passwordInput.value.trim();

    // This is a simple demo validation for students learning JavaScript.
    if (fullname === '' || email === '' || phone === '' || username === '' || password === '') {
      alert('Please fill in all fields.');
      return;
    }

    if (!email.includes('@')) {
      alert('Please enter a valid email address.');
      return;
    }

    if (password.length < 6) {
      alert('Password must be at least 6 characters.');
      return;
    }

    if (agreeInput && !agreeInput.checked) {
      alert('Please agree to the terms before registering.');
      return;
    }

    const newUser = {
      fullname: fullname,
      email: email,
      phone: phone,
      username: username,
      registeredAt: new Date().toISOString()
    };

    const savedUsers = localStorage.getItem('gostayUsers');
    const users = savedUsers ? JSON.parse(savedUsers) : [];

    users.push(newUser);
    localStorage.setItem('gostayUsers', JSON.stringify(users));

    alert('Register successful! Please login.');
    window.location.href = 'login.html';
  });
}

document.addEventListener('DOMContentLoaded', function () {
  setupRegisterForm();
  setupSupabaseLogin();
}, { once: true });

async function setupSupabaseLogin() {
  const loginForm = document.getElementById('login-form');
  const emailInput = document.getElementById('login-email');
  const passwordInput = document.getElementById('login-password');
  const submitButton = document.getElementById('login-submit');
  const statusElement = document.getElementById('login-status');

  if (!loginForm || !emailInput || !passwordInput || !submitButton || !statusElement) {
    return;
  }

  if (loginForm.dataset.authBound === 'true') {
    return;
  }

  loginForm.dataset.authBound = 'true';

  if (!window.gostaySupabase) {
    setLoginStatus(statusElement, 'Không thể khởi tạo dịch vụ đăng nhập. Vui lòng tải lại trang.', 'error');
    submitButton.disabled = true;
    return;
  }

  setLoginLoading(submitButton, statusElement, true, 'Đang kiểm tra phiên đăng nhập...');

  try {
    const { data, error } = await window.gostaySupabase.auth.getSession();

    if (error) {
      throw error;
    }

    if (data.session) {
      window.location.replace('search.html');
      return;
    }
  } catch (error) {
    setLoginStatus(statusElement, getFriendlyAuthError(error, 'Không thể kiểm tra phiên đăng nhập.'), 'error');
  } finally {
    setLoginLoading(submitButton, statusElement, false);
  }

  loginForm.addEventListener('submit', async function (event) {
    event.preventDefault();

    const email = emailInput.value.trim();
    const password = passwordInput.value;

    if (!email || !emailInput.validity.valid) {
      setLoginStatus(statusElement, 'Vui lòng nhập địa chỉ email hợp lệ.', 'error');
      emailInput.focus();
      return;
    }

    if (!password) {
      setLoginStatus(statusElement, 'Vui lòng nhập mật khẩu.', 'error');
      passwordInput.focus();
      return;
    }

    setLoginLoading(submitButton, statusElement, true, 'Đang đăng nhập...');

    try {
      const { data, error } = await window.gostaySupabase.auth.signInWithPassword({
        email: email,
        password: password
      });

      if (error) {
        throw error;
      }

      if (!data.session || !data.user) {
        throw new Error('Supabase không trả về phiên đăng nhập hợp lệ.');
      }

      setLoginStatus(statusElement, 'Đăng nhập thành công. Đang chuyển trang...', 'success');
      window.location.assign('search.html');
    } catch (error) {
      setLoginStatus(statusElement, getFriendlyAuthError(error, 'Không thể đăng nhập. Vui lòng thử lại.'), 'error');
      setLoginLoading(submitButton, statusElement, false);
    }
  });
}

function setLoginLoading(button, statusElement, isLoading, message) {
  button.disabled = isLoading;
  button.textContent = isLoading ? 'Đang xử lý...' : 'Đăng Nhập';

  if (message) {
    setLoginStatus(statusElement, message, 'loading');
  }
}

function setLoginStatus(statusElement, message, type) {
  statusElement.hidden = !message;
  statusElement.textContent = message || '';
  statusElement.dataset.status = type || '';
}

function getFriendlyAuthError(error, fallbackMessage) {
  const message = String(error && error.message ? error.message : '').toLowerCase();

  if (message.includes('invalid login credentials')) {
    return 'Email hoặc mật khẩu không đúng.';
  }

  if (message.includes('email not confirmed')) {
    return 'Email chưa được xác nhận. Vui lòng kiểm tra hộp thư của bạn.';
  }

  if (message.includes('failed to fetch') || message.includes('network')) {
    return 'Không thể kết nối dịch vụ đăng nhập. Vui lòng kiểm tra mạng và thử lại.';
  }

  return fallbackMessage;
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

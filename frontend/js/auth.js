(function () {
  'use strict';

  document.addEventListener('DOMContentLoaded', function () {
    setupLoginForm();
    setupGoogleLogin();
    setupRegisterForm();
  }, { once: true });

  function setupGoogleLogin() {
    const button = document.getElementById('google-login');
    const statusElement = document.getElementById('login-status');
    if (!button || !statusElement) return;

    button.addEventListener('click', async function () {
      if (!window.gostaySupabase || button.disabled) return;
      button.disabled = true;
      setStatus(statusElement, 'Đang chuyển đến Google...', 'loading');

      try {
        const { error } = await window.gostaySupabase.auth.signInWithOAuth({
          provider: 'google',
          options: { redirectTo: window.location.origin + window.location.pathname }
        });
        if (error) throw error;
      } catch (error) {
        setStatus(statusElement, friendlyError(error, 'Không thể đăng nhập bằng Google.'), 'error');
        button.disabled = false;
      }
    });
  }

  async function getActiveProfile(userId) {
    const { data, error } = await window.gostaySupabase
      .from('profiles')
      .select('id, full_name, role, status')
      .eq('id', userId)
      .maybeSingle();

    if (error) {
      throw new Error('Không thể kiểm tra hồ sơ tài khoản.');
    }

    if (!data) {
      throw new Error('Tài khoản chưa có hồ sơ hợp lệ.');
    }

    if (data.status !== 'active') {
      throw new Error(data.status === 'blocked'
        ? 'Tài khoản đã bị khóa.'
        : 'Tài khoản hiện không hoạt động.');
    }

    if (!['admin', 'staff', 'customer'].includes(data.role)) {
      throw new Error('Tài khoản có vai trò không hợp lệ.');
    }

    return data;
  }

  async function signOutInvalidSession() {
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

  function redirectForProfile(profile, replace) {
    const destination = profile.role === 'admin'
      ? 'admin-dashboard.html'
      : profile.role === 'staff' ? 'staff-dashboard.html' : 'index.html';

    window.location[replace ? 'replace' : 'assign'](destination);
  }

  async function validateSessionAndRedirect(session, replace) {
    if (!session || !session.user || !session.user.id) {
      return false;
    }

    try {
      const profile = await getActiveProfile(session.user.id);
      redirectForProfile(profile, replace);
      return true;
    } catch (error) {
      await signOutInvalidSession();
      throw error;
    }
  }

  async function setupLoginForm() {
    const form = document.getElementById('login-form');
    const emailInput = document.getElementById('login-email');
    const passwordInput = document.getElementById('login-password');
    const submitButton = document.getElementById('login-submit');
    const statusElement = document.getElementById('login-status');

    if (!form || !emailInput || !passwordInput || !submitButton || !statusElement) {
      return;
    }

    if (!window.gostaySupabase) {
      setStatus(statusElement, 'Không thể khởi tạo dịch vụ đăng nhập.', 'error');
      submitButton.disabled = true;
      return;
    }

    if (new URLSearchParams(window.location.search).get('password_reset') === 'success') {
      setStatus(statusElement, 'Mật khẩu đã được cập nhật. Vui lòng đăng nhập lại.', 'success');
      window.history.replaceState({}, document.title, window.location.pathname);
    }

    submitButton.disabled = true;

    try {
      const { data, error } = await window.gostaySupabase.auth.getSession();
      if (error) throw error;
      if (await validateSessionAndRedirect(data.session, true)) return;
    } catch (error) {
      setStatus(statusElement, friendlyError(error, 'Không thể kiểm tra phiên đăng nhập.'), 'error');
    } finally {
      submitButton.disabled = false;
    }

    form.addEventListener('submit', async function (event) {
      event.preventDefault();
      const email = emailInput.value.trim();
      const password = passwordInput.value;

      if (!email || !emailInput.validity.valid) {
        setStatus(statusElement, 'Vui lòng nhập địa chỉ email hợp lệ.', 'error');
        emailInput.focus();
        return;
      }

      if (!password) {
        setStatus(statusElement, 'Vui lòng nhập mật khẩu.', 'error');
        passwordInput.focus();
        return;
      }

      setLoading(submitButton, statusElement, true, 'Đang đăng nhập...', 'Đăng Nhập');

      try {
        const { data, error } = await window.gostaySupabase.auth.signInWithPassword({
          email: email,
          password: password
        });

        if (error) throw error;
        if (!data.session || !data.user) {
          throw new Error('Supabase không trả về phiên đăng nhập hợp lệ.');
        }

        const profile = await getActiveProfile(data.user.id);
        setStatus(statusElement, 'Đăng nhập thành công. Đang chuyển trang...', 'success');
        redirectForProfile(profile, false);
      } catch (error) {
        try {
          await signOutInvalidSession();
        } finally {
          setStatus(statusElement, friendlyError(error, 'Không thể đăng nhập. Vui lòng thử lại.'), 'error');
          setLoading(submitButton, statusElement, false, '', 'Đăng Nhập');
        }
      }
    });
  }

  function setupRegisterForm() {
    const form = document.getElementById('register-form');
    const fullnameInput = document.getElementById('fullname');
    const emailInput = document.getElementById('email');
    const phoneInput = document.getElementById('phone');
    const passwordInput = document.getElementById('password');
    const agreeInput = document.querySelector('input[name="agree"]');
    const submitButton = document.getElementById('register-submit');
    const statusElement = document.getElementById('register-status');

    if (!form || !fullnameInput || !emailInput || !phoneInput ||
        !passwordInput || !submitButton || !statusElement) {
      return;
    }

    if (!window.gostaySupabase) {
      setStatus(statusElement, 'Không thể khởi tạo dịch vụ đăng ký.', 'error');
      submitButton.disabled = true;
      return;
    }

    form.addEventListener('submit', async function (event) {
      event.preventDefault();

      const fullname = fullnameInput.value.trim();
      const email = emailInput.value.trim();
      const phone = phoneInput.value.trim();
      const password = passwordInput.value;

      if (!fullname || !email || !phone || !password) {
        setStatus(statusElement, 'Vui lòng điền đầy đủ thông tin.', 'error');
        return;
      }

      if (!emailInput.validity.valid) {
        setStatus(statusElement, 'Vui lòng nhập địa chỉ email hợp lệ.', 'error');
        emailInput.focus();
        return;
      }

      if (password.length < 6) {
        setStatus(statusElement, 'Mật khẩu phải có ít nhất 6 ký tự.', 'error');
        passwordInput.focus();
        return;
      }

      if (agreeInput && !agreeInput.checked) {
        setStatus(statusElement, 'Vui lòng đồng ý với Điều khoản và Chính sách.', 'error');
        return;
      }

      setLoading(submitButton, statusElement, true, 'Đang đăng ký...', 'Đăng Ký');

      try {
        const { data, error } = await window.gostaySupabase.auth.signUp({
          email: email,
          password: password,
          options: {
            emailRedirectTo: new URL('login.html', window.location.href).href,
            data: {
              full_name: fullname,
              phone: phone
            }
          }
        });

        if (error) throw error;
        if (!data.user) throw new Error('Supabase không trả về tài khoản vừa tạo.');

        if (!data.session) {
          setStatus(statusElement, 'Đăng ký thành công. Vui lòng kiểm tra email để xác nhận tài khoản.', 'success');
          form.reset();
          submitButton.disabled = true;
          return;
        }

        const profile = await getActiveProfile(data.user.id);
        setStatus(statusElement, 'Đăng ký thành công. Đang chuyển trang...', 'success');
        redirectForProfile(profile, false);
      } catch (error) {
        try {
          await signOutInvalidSession();
        } finally {
          setStatus(statusElement, friendlyError(error, 'Không thể đăng ký. Vui lòng thử lại.'), 'error');
          setLoading(submitButton, statusElement, false, '', 'Đăng Ký');
        }
      }
    });
  }

  function setLoading(button, statusElement, loading, message, idleText) {
    button.disabled = loading;
    button.textContent = loading ? 'Đang xử lý...' : idleText;
    if (message) setStatus(statusElement, message, 'loading');
  }

  function setStatus(element, message, type) {
    element.hidden = !message;
    element.textContent = message || '';
    element.dataset.status = type || '';
  }

  function friendlyError(error, fallback) {
    const message = String(error && error.message ? error.message : '');
    const code = String(error && error.code ? error.code : '').toLowerCase();
    const normalized = message.toLowerCase();

    if (normalized.includes('invalid login credentials')) return 'Email hoặc mật khẩu không đúng.';
    if (normalized.includes('email not confirmed')) return 'Email chưa được xác nhận. Vui lòng kiểm tra hộp thư.';
    if (normalized.includes('user already registered')) return 'Email này đã được đăng ký.';
    if (code === 'over_email_send_rate_limit' || normalized.includes('email rate limit exceeded')) {
      return 'Hệ thống đang gửi quá nhiều email xác nhận. Vui lòng chờ một lúc rồi thử lại.';
    }
    if (normalized.includes('email address') && normalized.includes('is invalid')) {
      return 'Địa chỉ email không được hệ thống chấp nhận. Vui lòng sử dụng email khác.';
    }
    if (normalized.includes('failed to fetch') || normalized.includes('network')) {
      return 'Không thể kết nối dịch vụ xác thực. Vui lòng kiểm tra mạng.';
    }

    return fallback;
  }
}());

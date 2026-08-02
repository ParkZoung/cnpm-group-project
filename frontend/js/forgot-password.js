(function () {
  'use strict';

  const RESEND_SECONDS = 60;
  let recoveryEmail = '';
  let countdownId = null;

  document.addEventListener('DOMContentLoaded', function () {
    const emailForm = document.getElementById('forgot-email-form');
    const otpForm = document.getElementById('otp-form');
    const passwordForm = document.getElementById('new-password-form');
    const resendButton = document.getElementById('resend-otp');
    const otpInputs = Array.from(document.querySelectorAll('.otp-box'));

    if (!emailForm || !otpForm || !passwordForm || !resendButton || otpInputs.length !== 6) return;

    emailForm.addEventListener('submit', handleInitialSend);
    otpForm.addEventListener('submit', handleVerifyOtp);
    passwordForm.addEventListener('submit', handlePasswordUpdate);
    resendButton.addEventListener('click', handleResend);
    setupOtpInputs(otpInputs);
  }, { once: true });

  async function handleInitialSend(event) {
    event.preventDefault();
    const emailInput = document.getElementById('forgot-email');
    const status = document.getElementById('forgot-email-status');
    const button = document.getElementById('send-otp-submit');
    const email = emailInput.value.trim();

    if (!email || !emailInput.validity.valid) {
      setStatus(status, 'Vui lòng nhập địa chỉ email hợp lệ.', 'error');
      emailInput.focus();
      return;
    }

    if (!window.gostaySupabase) {
      setStatus(status, 'Không thể khởi tạo dịch vụ khôi phục mật khẩu.', 'error');
      return;
    }

    setLoading(button, true, 'Đang gửi...', 'Gửi mã OTP');
    setStatus(status, 'Đang gửi mã OTP...', 'loading');

    try {
      const { error } = await window.gostaySupabase.auth.resetPasswordForEmail(email, {
        redirectTo: window.location.href.split('#')[0].split('?')[0]
      });
      if (error) throw error;

      recoveryEmail = email;
      showStep('step-otp');
      document.getElementById('form-title').textContent = 'Xác Minh OTP';
      document.getElementById('form-subtitle').textContent =
        'Nếu email tồn tại, mã OTP 6 số đã được gửi đến ' + maskEmail(email) + '. Vui lòng kiểm tra cả thư rác.';
      clearOtpInputs();
      startResendCountdown();
      document.getElementById('otp1').focus();
    } catch (error) {
      setStatus(status, friendlyError(error, 'Không thể gửi mã OTP. Vui lòng thử lại.'), 'error');
    } finally {
      setLoading(button, false, 'Đang gửi...', 'Gửi mã OTP');
    }
  }

  async function handleResend() {
    const status = document.getElementById('otp-status');
    const button = document.getElementById('resend-otp');
    if (!recoveryEmail || button.disabled) return;

    button.disabled = true;
    setStatus(status, 'Đang gửi lại mã OTP...', 'loading');

    try {
      const { error } = await window.gostaySupabase.auth.resetPasswordForEmail(recoveryEmail, {
        redirectTo: window.location.href.split('#')[0].split('?')[0]
      });
      if (error) throw error;
      clearOtpInputs();
      setStatus(status, 'Mã OTP mới đã được gửi. Mã cũ có thể không còn hiệu lực.', 'success');
      startResendCountdown();
      document.getElementById('otp1').focus();
    } catch (error) {
      setStatus(status, friendlyError(error, 'Không thể gửi lại mã OTP.'), 'error');
      button.disabled = false;
    }
  }

  async function handleVerifyOtp(event) {
    event.preventDefault();
    const status = document.getElementById('otp-status');
    const button = document.getElementById('verify-otp-submit');
    const token = getOtp();

    if (!/^\d{6}$/.test(token)) {
      setStatus(status, 'Vui lòng nhập đủ mã OTP gồm 6 số.', 'error');
      return;
    }

    setLoading(button, true, 'Đang xác thực...', 'Xác thực mã OTP');
    setStatus(status, 'Đang xác thực mã OTP...', 'loading');

    try {
      const { data, error } = await window.gostaySupabase.auth.verifyOtp({
        email: recoveryEmail,
        token: token,
        type: 'recovery'
      });
      if (error) throw error;
      if (!data || !data.session) throw new Error('Missing recovery session');

      window.clearInterval(countdownId);
      showStep('step-new-password');
      document.getElementById('form-title').textContent = 'Đổi Mật Khẩu';
      document.getElementById('form-subtitle').textContent =
        'Xác thực thành công. Hãy tạo mật khẩu mới có ít nhất 8 ký tự.';
      document.getElementById('new-password').focus();
    } catch (error) {
      setStatus(status, friendlyError(error, 'Mã OTP không đúng hoặc đã hết hạn.'), 'error');
      clearOtpInputs();
      document.getElementById('otp1').focus();
    } finally {
      setLoading(button, false, 'Đang xác thực...', 'Xác thực mã OTP');
    }
  }

  async function handlePasswordUpdate(event) {
    event.preventDefault();
    const password = document.getElementById('new-password');
    const confirmation = document.getElementById('confirm-password');
    const status = document.getElementById('password-status');
    const button = document.getElementById('update-password-submit');

    if (password.value.length < 8) {
      setStatus(status, 'Mật khẩu mới phải có ít nhất 8 ký tự.', 'error');
      password.focus();
      return;
    }
    if (password.value !== confirmation.value) {
      setStatus(status, 'Hai mật khẩu không trùng khớp.', 'error');
      confirmation.focus();
      return;
    }

    setLoading(button, true, 'Đang cập nhật...', 'Lưu mật khẩu mới');
    setStatus(status, 'Đang cập nhật mật khẩu...', 'loading');

    try {
      const { error } = await window.gostaySupabase.auth.updateUser({ password: password.value });
      if (error) throw error;

      setStatus(status, 'Đổi mật khẩu thành công. Đang chuyển đến trang đăng nhập...', 'success');
      await window.gostaySupabase.auth.signOut();
      window.setTimeout(function () {
        window.location.replace('login.html?password_reset=success');
      }, 900);
    } catch (error) {
      setStatus(status, friendlyError(error, 'Không thể cập nhật mật khẩu. Vui lòng yêu cầu mã OTP mới.'), 'error');
      setLoading(button, false, 'Đang cập nhật...', 'Lưu mật khẩu mới');
    }
  }

  function setupOtpInputs(inputs) {
    inputs.forEach(function (input, index) {
      input.addEventListener('input', function () {
        input.value = input.value.replace(/\D/g, '').slice(-1);
        if (input.value && inputs[index + 1]) inputs[index + 1].focus();
      });

      input.addEventListener('keydown', function (event) {
        if (event.key === 'Backspace' && !input.value && inputs[index - 1]) {
          inputs[index - 1].focus();
        }
      });

      input.addEventListener('paste', function (event) {
        const digits = event.clipboardData.getData('text').replace(/\D/g, '').slice(0, 6);
        if (!digits) return;
        event.preventDefault();
        inputs.forEach(function (item, itemIndex) { item.value = digits[itemIndex] || ''; });
        inputs[Math.min(digits.length, 6) - 1].focus();
      });
    });
  }

  function startResendCountdown() {
    const button = document.getElementById('resend-otp');
    const countdown = document.getElementById('resend-countdown');
    const timer = document.getElementById('timer');
    let remaining = RESEND_SECONDS;

    window.clearInterval(countdownId);
    button.disabled = true;
    countdown.hidden = false;
    timer.textContent = String(remaining);

    countdownId = window.setInterval(function () {
      remaining -= 1;
      timer.textContent = String(Math.max(remaining, 0));
      if (remaining <= 0) {
        window.clearInterval(countdownId);
        countdown.hidden = true;
        button.disabled = false;
      }
    }, 1000);
  }

  function showStep(stepId) {
    ['step-email', 'step-otp', 'step-new-password'].forEach(function (id) {
      document.getElementById(id).hidden = id !== stepId;
    });
  }

  function clearOtpInputs() {
    document.querySelectorAll('.otp-box').forEach(function (input) { input.value = ''; });
  }

  function getOtp() {
    return Array.from(document.querySelectorAll('.otp-box')).map(function (input) {
      return input.value;
    }).join('');
  }

  function maskEmail(email) {
    const parts = email.split('@');
    const name = parts[0];
    const visible = name.slice(0, Math.min(2, name.length));
    return visible + '*'.repeat(Math.max(3, name.length - visible.length)) + '@' + parts[1];
  }

  function setLoading(button, loading, loadingText, idleText) {
    button.disabled = loading;
    button.textContent = loading ? loadingText : idleText;
  }

  function setStatus(element, message, type) {
    element.hidden = !message;
    element.textContent = message || '';
    element.dataset.status = type || '';
  }

  function friendlyError(error, fallback) {
    const message = String(error && error.message ? error.message : '').toLowerCase();
    const code = String(error && error.code ? error.code : '').toLowerCase();
    if (message.includes('rate limit') || code.includes('rate_limit')) {
      return 'Bạn đã yêu cầu quá nhiều mã. Vui lòng chờ một lúc rồi thử lại.';
    }
    if (message.includes('expired') || message.includes('invalid') || code === 'otp_expired') {
      return 'Mã OTP không đúng hoặc đã hết hạn.';
    }
    if (message.includes('same password')) return 'Mật khẩu mới phải khác mật khẩu hiện tại.';
    if (message.includes('network') || message.includes('failed to fetch')) {
      return 'Không thể kết nối dịch vụ xác thực. Vui lòng kiểm tra mạng.';
    }
    return fallback;
  }
}());

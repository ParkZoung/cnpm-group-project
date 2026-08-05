(function () {
  'use strict';

  const eyeIcon = '<svg aria-hidden="true" viewBox="0 0 24 24"><path d="M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6S2.5 12 2.5 12Z"/><circle cx="12" cy="12" r="2.75"/></svg>';
  const eyeOffIcon = '<svg aria-hidden="true" viewBox="0 0 24 24"><path d="m3 3 18 18M10.6 6.1A9.8 9.8 0 0 1 12 6c6 0 9.5 6 9.5 6a15.5 15.5 0 0 1-2.1 2.8M6.2 6.2C3.8 8 2.5 12 2.5 12s3.5 6 9.5 6a9 9 0 0 0 3.2-.6M9.9 9.9a3 3 0 0 0 4.2 4.2"/></svg>';

  document.addEventListener('DOMContentLoaded', function () {
    document.querySelectorAll('.auth-form input[type="password"]').forEach(function (input) {
      const wrapper = document.createElement('div');
      wrapper.className = 'password-field';
      input.parentNode.insertBefore(wrapper, input);
      wrapper.appendChild(input);

      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'password-toggle';
      button.setAttribute('aria-label', 'Hiện mật khẩu');
      button.setAttribute('aria-pressed', 'false');
      button.innerHTML = eyeIcon;
      wrapper.appendChild(button);

      button.addEventListener('click', function () {
        const isVisible = input.type === 'text';
        input.type = isVisible ? 'password' : 'text';
        button.setAttribute('aria-label', isVisible ? 'Hiện mật khẩu' : 'Ẩn mật khẩu');
        button.setAttribute('aria-pressed', String(!isVisible));
        button.innerHTML = isVisible ? eyeIcon : eyeOffIcon;
        input.focus({ preventScroll: true });
        input.setSelectionRange(input.value.length, input.value.length);
      });
    });
  }, { once: true });
}());

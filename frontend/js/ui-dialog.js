(function () {
  'use strict';

  let activeResolve = null;

  function ensureDialog() {
    let overlay = document.getElementById('gostay-dialog-overlay');
    if (overlay) return overlay;

    const style = document.createElement('style');
    style.textContent = `
      @keyframes gostayFadeIn{from{opacity:0}to{opacity:1}}
      @keyframes gostayPopIn{from{opacity:0;transform:translateY(14px) scale(.97)}to{opacity:1;transform:translateY(0) scale(1)}}
      .gostay-dialog-overlay{position:fixed;inset:0;z-index:10000;display:grid;place-items:center;padding:20px;background:rgba(2,18,32,.62);backdrop-filter:blur(9px);animation:gostayFadeIn .18s ease-out}
      .gostay-dialog-overlay[hidden]{display:none}
      .gostay-dialog{position:relative;width:min(580px,100%);max-height:min(82vh,740px);overflow:auto;background:linear-gradient(155deg,#fff 0%,#f8fbfc 100%);border-radius:24px;box-shadow:0 32px 90px rgba(0,18,34,.38),0 2px 10px rgba(0,18,34,.12);border:1px solid rgba(255,255,255,.78);animation:gostayPopIn .24s cubic-bezier(.22,.8,.3,1)}
      .gostay-dialog::before{content:"";position:absolute;inset:0 0 auto;height:5px;background:linear-gradient(90deg,#0b3558,#10a4b3,#69d2c7)}
      .gostay-dialog-head{display:grid;grid-template-columns:48px 1fr auto;align-items:center;gap:14px;padding:28px 28px 18px}
      .gostay-dialog-icon{display:grid;place-items:center;width:48px;height:48px;border-radius:15px;background:linear-gradient(145deg,#0b3558,#10a4b3);color:#fff;font-size:21px;font-weight:850;box-shadow:0 10px 24px rgba(16,164,179,.24)}
      .gostay-dialog-heading{display:grid;gap:3px}
      .gostay-dialog-kicker{color:#0f9ead;font:800 11px/1.2 inherit;letter-spacing:.12em;text-transform:uppercase}
      .gostay-dialog-title{margin:0;color:#102a43;font:780 21px/1.3 inherit;letter-spacing:-.02em}
      .gostay-dialog-close{display:grid;place-items:center;width:36px;height:36px;border:0;border-radius:11px;background:#eef4f6;color:#64748b;font-size:20px;cursor:pointer;transition:.18s ease}
      .gostay-dialog-close:hover{background:#dfecef;color:#0b3558;transform:rotate(3deg)}
      .gostay-dialog-message{margin:0 28px;padding:18px 20px;color:#334e68;font:500 15px/1.72 inherit;white-space:pre-wrap;overflow-wrap:anywhere;background:rgba(238,246,248,.75);border:1px solid #dbe9ec;border-radius:15px}
      .gostay-dialog-actions{display:flex;justify-content:flex-end;gap:11px;padding:22px 28px 28px}
      .gostay-dialog-btn{min-width:104px;padding:11px 19px;border-radius:12px;border:1px solid #cfdee3;background:#fff;color:#415a6b;font:750 14px inherit;cursor:pointer;transition:transform .16s ease,box-shadow .16s ease,background .16s ease}
      .gostay-dialog-btn:hover{background:#f5f9fa;transform:translateY(-1px)}
      .gostay-dialog-btn.primary{border-color:transparent;background:linear-gradient(135deg,#0b7f8c,#11a6b5);color:#fff;box-shadow:0 10px 22px rgba(15,158,173,.22)}
      .gostay-dialog-btn.primary:hover{background:linear-gradient(135deg,#086d78,#0d929f);box-shadow:0 13px 26px rgba(15,158,173,.28)}
      .gostay-dialog.preview{width:min(1180px,96vw);height:min(88vh,900px);display:grid;grid-template-rows:auto 1fr auto;overflow:hidden}
      .gostay-dialog.preview .gostay-dialog-head{padding:22px 26px 16px}
      .gostay-dialog.preview .gostay-dialog-message{display:none}
      .gostay-dialog-frame{width:calc(100% - 32px);height:100%;min-height:0;margin:0 16px;border:1px solid #dbe9ec;border-radius:16px;background:#fff}
      .gostay-dialog-frame[hidden]{display:none}
      .gostay-dialog.preview .gostay-dialog-actions{padding:16px 26px 22px}
      @media(max-width:540px){.gostay-dialog{border-radius:20px}.gostay-dialog-head{padding:24px 20px 16px}.gostay-dialog-message{margin:0 20px}.gostay-dialog-actions{padding:18px 20px 22px}.gostay-dialog-btn{flex:1}.gostay-dialog-actions{justify-content:stretch}}
    `;
    document.head.appendChild(style);

    overlay = document.createElement('div');
    overlay.id = 'gostay-dialog-overlay';
    overlay.className = 'gostay-dialog-overlay';
    overlay.hidden = true;
    overlay.innerHTML = `
      <section class="gostay-dialog" role="dialog" aria-modal="true" aria-labelledby="gostay-dialog-title">
        <div class="gostay-dialog-head"><span class="gostay-dialog-icon">G</span><div class="gostay-dialog-heading"><span class="gostay-dialog-kicker">GoStay Admin</span><h2 id="gostay-dialog-title" class="gostay-dialog-title"></h2></div><button type="button" class="gostay-dialog-close" aria-label="Đóng">×</button></div>
        <p class="gostay-dialog-message"></p>
        <iframe class="gostay-dialog-frame" title="Xem trước trang khách" hidden></iframe>
        <div class="gostay-dialog-actions"><button type="button" class="gostay-dialog-btn cancel">Hủy</button><button type="button" class="gostay-dialog-btn primary">Đồng ý</button></div>
      </section>`;
    document.body.appendChild(overlay);
    overlay.querySelector('.cancel').addEventListener('click', function () { close(false); });
    overlay.querySelector('.primary').addEventListener('click', function () { close(true); });
    overlay.querySelector('.gostay-dialog-close').addEventListener('click', function () { close(false); });
    overlay.addEventListener('click', function (event) {
      if (event.target === overlay) close(false);
    });
    document.addEventListener('keydown', function (event) {
      if (!overlay.hidden && event.key === 'Escape') close(false);
    });
    return overlay;
  }

  function close(result) {
    const overlay = ensureDialog();
    overlay.hidden = true;
    const frame = overlay.querySelector('.gostay-dialog-frame');
    frame.src = 'about:blank';
    frame.hidden = true;
    overlay.querySelector('.gostay-dialog').classList.remove('preview');
    document.body.style.overflow = '';
    if (activeResolve) {
      const resolve = activeResolve;
      activeResolve = null;
      resolve(result);
    }
  }

  function open(options) {
    const overlay = ensureDialog();
    if (activeResolve) activeResolve(false);
    overlay.querySelector('.gostay-dialog-title').textContent = options.title || 'GoStay thông báo';
    overlay.querySelector('.gostay-dialog-message').textContent = String(options.message || '');
    const dialog = overlay.querySelector('.gostay-dialog');
    const frame = overlay.querySelector('.gostay-dialog-frame');
    const isPreview = Boolean(options.previewUrl);
    dialog.classList.toggle('preview', isPreview);
    frame.hidden = !isPreview;
    if (isPreview) frame.src = options.previewUrl;
    overlay.querySelector('.cancel').hidden = !options.confirm;
    overlay.querySelector('.primary').textContent = isPreview ? 'Đóng xem trước' : (options.confirm ? 'Xác nhận' : 'Đã hiểu');
    overlay.hidden = false;
    document.body.style.overflow = 'hidden';
    window.setTimeout(function () { overlay.querySelector('.primary').focus(); }, 0);
    return new Promise(function (resolve) { activeResolve = resolve; });
  }

  window.GoStayDialog = Object.freeze({
    alert: function (message, title) { return open({ message: message, title: title, confirm: false }); },
    confirm: function (message, title) { return open({ message: message, title: title || 'Xác nhận thao tác', confirm: true }); },
    preview: function (url, title) { return open({ previewUrl: url, title: title || 'Xem trước trang khách', confirm: false }); }
  });
}());

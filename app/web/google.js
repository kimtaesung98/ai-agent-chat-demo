// Google 로그인 (SPEC.md F-026 상세 동작 3) — Google Identity Services 버튼을 띄우고 ID 토큰을 받는다.
// lib/ui/google_sign_in_web.dart가 window.chatGoogle.signIn(clientId)를 부른다. 토큰은 서버(/api/auth/google)로만 보낸다.
// 클라이언트 ID는 비밀값이 아니다 — 서버가 /api/auth/options로 알려 준다. 스크립트는 처음 누를 때만 받는다.
(function () {
  var loading = null;

  function load() {
    if (window.google && google.accounts && google.accounts.id) return Promise.resolve();
    if (!loading) {
      loading = new Promise(function (resolve, reject) {
        var s = document.createElement('script');
        s.src = 'https://accounts.google.com/gsi/client';
        s.async = true;
        s.onload = function () { resolve(); };
        s.onerror = function () { loading = null; reject(new Error('Google 스크립트를 받지 못함')); };
        document.head.appendChild(s);
      });
    }
    return loading;
  }

  // 화면 가운데에 Google 버튼과 "닫기"를 띄운다. 로그인하면 ID 토큰, 닫으면 빈 문자열.
  function signIn(clientId) {
    return load().then(function () {
      return new Promise(function (resolve) {
        var overlay = document.createElement('div');
        overlay.setAttribute('role', 'dialog');
        overlay.style.cssText = 'position:fixed;inset:0;z-index:10000;background:rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center;padding:16px';
        var box = document.createElement('div');
        box.style.cssText = 'background:#fff;border-radius:16px;padding:24px;max-width:360px;width:100%;text-align:center;font:18px system-ui,sans-serif;color:#222';
        box.innerHTML = '<p style="margin:0 0 16px">연결된 Google 계정으로 들어가요</p>';
        var slot = document.createElement('div');
        slot.style.cssText = 'display:flex;justify-content:center;min-height:44px';
        var close = document.createElement('button');
        close.textContent = '닫기';
        close.style.cssText = 'margin-top:16px;font-size:17px;padding:10px 24px;border-radius:10px;border:1px solid #ccc;background:#fff';
        box.appendChild(slot);
        box.appendChild(close);
        overlay.appendChild(box);
        document.body.appendChild(overlay);
        var done = false;
        function finish(token) {
          if (done) return;
          done = true;
          overlay.remove();
          resolve(token || '');
        }
        close.onclick = function () { finish(''); };
        google.accounts.id.initialize({
          client_id: clientId,
          callback: function (r) { finish(r && r.credential); },
          auto_select: false,
          cancel_on_tap_outside: true,
        });
        google.accounts.id.renderButton(slot, { theme: 'outline', size: 'large', text: 'continue_with', locale: 'ko', width: 280 });
      });
    });
  }

  window.chatGoogle = { signIn: signIn };
})();

// 웹앱(PWA) 설치·서비스 워커 (SPEC.md F-025, ARCHITECTURE.md ADR-027).
// Dart(lib/ui/installer_web.dart)가 dart:js_interop으로 window.aiPwa를 부른다.
(function () {
  'use strict';
  const DISMISS_KEY = 'aiPwa.hintDismissed';
  let deferred = null; // Android Chrome 설치 창
  const listeners = [];
  const changed = function () { listeners.forEach(function (f) { try { f(); } catch (_) {} }); };

  if ('serviceWorker' in navigator) {
    window.addEventListener('load', function () {
      navigator.serviceWorker.register('sw.js').catch(function () {});
    });
  }
  window.addEventListener('beforeinstallprompt', function (e) {
    e.preventDefault(); // 브라우저 기본 배너 대신 앱 안의 안내에서 띄운다
    deferred = e;
    changed();
  });
  window.addEventListener('appinstalled', function () { deferred = null; changed(); });

  function standalone() {
    return (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) || navigator.standalone === true;
  }
  function ios() {
    const ua = navigator.userAgent || '';
    return /iPhone|iPad|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  }

  window.aiPwa = {
    // installed · prompt(Android 등 설치 창 가능) · ios(공유 → 홈 화면에 추가) · unsupported
    mode: function () {
      if (standalone()) return 'installed';
      if (deferred) return 'prompt';
      if (ios()) return 'ios';
      return 'unsupported';
    },
    install: async function () {
      const e = deferred;
      if (!e) return false;
      deferred = null;
      e.prompt();
      const choice = await e.userChoice;
      changed();
      return !!choice && choice.outcome === 'accepted';
    },
    dismissed: function () {
      try { return localStorage.getItem(DISMISS_KEY) === '1'; } catch (_) { return false; }
    },
    dismiss: function () {
      try { localStorage.setItem(DISMISS_KEY, '1'); } catch (_) {}
    },
    onChange: function (f) { listeners.push(f); },
    wakeLockSupported: function () { return !!(navigator.wakeLock && navigator.wakeLock.request); },
  };
})();

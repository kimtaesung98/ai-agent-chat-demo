// AI 말벗 서비스 워커 (SPEC.md F-025, ARCHITECTURE.md ADR-027).
// 화면 파일만 캐시한다: 늘 네트워크를 먼저 쓰고(새 빌드가 바로 보임), 끊겼을 때만 캐시로 연다.
// /api/*(대화·기억·임시 키)와 다른 출처(OpenAI 음성 연결·글꼴)는 손대지 않는다.
const CACHE = 'ai-malbeot-shell-v1';

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      for (const key of await caches.keys()) {
        if (key !== CACHE) await caches.delete(key);
      }
      await self.clients.claim();
    })(),
  );
});

function cacheable(request) {
  if (request.method !== 'GET') return false;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return false;
  return !url.pathname.startsWith('/api/') && !url.pathname.startsWith('/v1/');
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (!cacheable(request)) return;
  event.respondWith(
    (async () => {
      try {
        const response = await fetch(request);
        if (response.ok) {
          const copy = response.clone();
          event.waitUntil(caches.open(CACHE).then((c) => c.put(request, copy)));
        }
        return response;
      } catch (err) {
        const cached = await caches.match(request);
        if (cached) return cached;
        throw err;
      }
    })(),
  );
});

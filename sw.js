// Служебный скрипт «установки приложения» (PWA). Ничего не кеширует:
// все запросы идут напрямую в сеть, поэтому обновления игры приходят сразу.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', (e) => {
  e.respondWith(fetch(e.request).catch(() => new Response('Нет сети', { status: 503 })));
});

// Автообновление: сайт (GitHub Pages) выкладывает новую версию через 1–3 мин
// после пуша. Игра раз в 15 с (и при возврате во вкладку) спрашивает у сайта
// дату публикации index.html (без кэша); если она сменилась — показывает
// надпись и сама перезагружается. Жать «обновить» вручную не нужно.
(function () {
  let seen = null;
  let busy = false;
  async function check() {
    if (busy || location.protocol === 'file:') return;
    busy = true;
    try {
      const r = await fetch('index.html?t=' + Date.now(), { method: 'HEAD', cache: 'no-store' });
      const tag = r.ok && (r.headers.get('last-modified') || r.headers.get('etag'));
      if (tag) {
        if (seen === null) seen = tag;
        else if (tag !== seen) {
          const d = document.createElement('div');
          d.textContent = 'Вышло обновление — перезагружаю…';
          d.style.cssText = 'position:fixed;left:50%;top:40%;transform:translateX(-50%);z-index:9999;' +
            'background:rgba(0,0,0,.8);color:#fff;padding:12px 18px;border-radius:10px;font:16px sans-serif';
          document.body.appendChild(d);
          setTimeout(() => location.reload(), 1200);
          return;
        }
      }
    } catch (e) { /* нет сети — проверим позже */ }
    busy = false;
  }
  check();
  setInterval(check, 15000);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) check(); });
})();

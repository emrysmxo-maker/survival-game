// Счётчик скорости в углу рядом с версией: «v3.2 · 58 fps». Нужен, чтобы
// видеть реальную скорость игры на телефоне (в тестовом браузере без
// видеокарты цифры не показательны). Свой отдельный цикл, игру не трогает.
(function () {
  const el = document.getElementById('version-tag');
  if (!el) return;
  let n = 0, t0 = performance.now();
  function tick(t) {
    n++;
    if (t - t0 >= 500) {
      const fps = Math.round(n * 1000 / (t - t0));
      el.textContent = 'v' + GAME_VERSION + ' · ' + fps + ' fps';
      n = 0; t0 = t;
    }
    requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
})();

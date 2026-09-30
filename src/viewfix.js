// Страховка размера холста (отдельный файл, основной код не трогает).
// В приложении на весь экран и при повороте Android присылает размер окна
// несколькими шагами, и холст мог остаться со старым размером — картинка
// растягивалась. Здесь размер сверяется при любых событиях и раз в полсекунды.
(function () {
  function fix() {
    if (typeof resize !== 'function' || typeof canvas === 'undefined') return;
    const w = window.innerWidth, h = window.innerHeight;
    const dpr = Math.min(window.devicePixelRatio || 1, MAX_DPR);
    const bad = canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr) ||
                canvas.style.width !== w + 'px' || canvas.style.height !== h + 'px';
    if (bad) { view.w = 0; resize(); }          // принудительно: пересчитать холст
  }
  window.addEventListener('orientationchange', () => { fix(); setTimeout(fix, 300); setTimeout(fix, 900); });
  document.addEventListener('fullscreenchange', () => { fix(); setTimeout(fix, 300); setTimeout(fix, 900); });
  if (window.visualViewport) window.visualViewport.addEventListener('resize', fix);
  setInterval(fix, 500);

  // Шаг 3: Переделываем тени ям/склонов на легкий алгоритм (чтобы можно было вернуть рельеф без мерцания)
  // Убираем тяжелый ctx.clip() с полигоном и soft-light composite, которые сбрасывали буфер GPU на телефоне
  if (typeof window !== 'undefined') {
    window.drawGroundLight = function (chunk, x, y, gw, gh) {
      const L = chunk.groundLight;
      if (!L || (typeof DBG !== 'undefined' && DBG.noSlopeLight)) return;
      const sun = typeof sunLight === 'function' ? sunLight() : { dx: -0.7071, dy: -0.7071, k: 0.9 };
      if (sun.k < 0.02) return;
      const wx = -sun.dx * sun.k, wy = -sun.dy * sun.k;
      ctx.save();
      ctx.globalAlpha = Math.min(0.24, 0.16 * sun.k);
      const imgX = wx > 0 ? L[0] : L[1];
      const imgY = wy > 0 ? L[2] : L[3];
      if (imgX) ctx.drawImage(imgX, x, y, gw, gh);
      if (imgY) ctx.drawImage(imgY, x, y, gw, gh);
      ctx.restore();
    };
  }
})();
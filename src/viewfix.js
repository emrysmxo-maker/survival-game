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

  // Убираем серый слой наложения склонов (устраняет эффект тумана по всей карте,
  // земля и ямы остаются четкими, контрастными и естественными)
  if (typeof window !== 'undefined') {
    window.drawGroundLight = function () { /* без серого тумана */ };
  }
})();
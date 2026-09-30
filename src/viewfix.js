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

  // Контроль стрельбы: боец сначала поворачивается в сторону прицела, и только потом стреляет
  if (typeof updateWeapon === 'function') {
    const origUpdateWeapon = updateWeapon;
    updateWeapon = function (dt) {
      if (typeof weapon !== 'undefined') {
        if (weapon.touchGrace && weapon.touchGrace > 0) {
          weapon.touchGrace = Math.max(0, weapon.touchGrace - dt);
        }
        // Если прицел активен, проверяем направление ствола
        if (weapon.firing && typeof charAimWorld !== 'undefined' && charAimWorld !== null && typeof weapon.aimAngle === 'number') {
          const wantYaw = Math.atan2(Math.cos(weapon.aimAngle), Math.sin(weapon.aimAngle));
          let diff = charAimWorld - wantYaw;
          while (diff < -Math.PI) diff += Math.PI * 2;
          while (diff > Math.PI) diff -= Math.PI * 2;

          // Быстрый доворот к цели
          if (Math.abs(diff) > 0.6) {
            const step = Math.sign(diff) * Math.min(Math.abs(diff), 9.0 * dt);
            charAimWorld -= step;
          }

          const waitingForTurn = Math.abs(diff) > 0.42; // > 24° — ствол ещё поворачивается к цели
          const waitingForTouch = (weapon.touchGrace && weapon.touchGrace > 0);
          if (waitingForTurn || waitingForTouch) {
            const saved = weapon.firing;
            weapon.firing = false;
            origUpdateWeapon(dt);
            weapon.firing = saved;
            return;
          }
        }
      }
      origUpdateWeapon(dt);
    };
  }

  const fireBtn = document.getElementById('fire-btn');
  if (fireBtn) {
    fireBtn.addEventListener('touchstart', () => {
      if (typeof weapon !== 'undefined') {
        weapon.touchGrace = 0.08; // 80 мс форы для пальца при нажатии стика
      }
    }, { passive: true });
    window.addEventListener('touchmove', (e) => {
      if (typeof weapon !== 'undefined' && weapon.touchGrace > 0) {
        for (let i = 0; i < e.changedTouches.length; i++) {
          const t = e.changedTouches[i];
          if (typeof fireTouchId !== 'undefined' && t.identifier === fireTouchId) {
            weapon.touchGrace = 0;
          }
        }
      }
    }, { passive: true });
  }
})();
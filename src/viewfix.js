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

  // --- Исправление стрельбы при беге: сначала разворот назад, потом огонь назад ---
  function wrapA(a) {
    while (a < -Math.PI) a += Math.PI * 2;
    while (a > Math.PI) a -= Math.PI * 2;
    return a;
  }

  // Переопределяем updateWeapon напрямую в глобальной области
  window.updateWeapon = function (dt) {
    if (typeof weapon === 'undefined') return;
    weapon.cooldown -= dt;
    if (weapon._turnTimer > 0) weapon._turnTimer -= dt;
    if (weapon._touchGrace > 0) weapon._touchGrace -= dt;

    const aimA = (typeof weapon.aimAngle === 'number') ? weapon.aimAngle : (typeof player !== 'undefined' ? player.angle : 0);
    const moveA = (typeof joystick !== 'undefined' && joystick.active && (joystick.dx || joystick.dy))
      ? Math.atan2(joystick.dy, joystick.dx)
      : (typeof player !== 'undefined' ? player.angle : aimA);

    const diff = Math.abs(wrapA(aimA - moveA));
    const isAimingBack = diff > 0.85; // целимся назад или сильно вбок относительно бега

    if (isAimingBack) {
      if (weapon._lastAim !== aimA) {
        weapon._turnTimer = 0.18; // пауза 180 мс: даем бойцу развернуться назад перед выстрелами
        weapon._lastAim = aimA;
      }
    } else {
      weapon._turnTimer = 0;
      weapon._lastAim = aimA;
    }

    const waitingTurn = isAimingBack && weapon._turnTimer > 0;
    const waitingTouch = (weapon._touchGrace && weapon._touchGrace > 0);
    const ready = typeof charAimBlend === 'undefined' || charAimBlend > 0.65;

    // Стреляем ТОЛЬКО когда боец развернулся в сторону прицела
    if (weapon.firing && ready && !waitingTurn && !waitingTouch && weapon.cooldown <= 0) {
      if (typeof player !== 'undefined') {
        // Направление пули строго в сторону прицела (aimA):
        const wx = Math.cos(aimA) + Math.sin(aimA);
        const wy = Math.sin(aimA) - Math.cos(aimA);
        const l = Math.hypot(wx, wy) || 1;
        const d = { x: wx / l, y: wy / l };

        const spread = (Math.random() - 0.5) * 0.05;
        const c = Math.cos(spread), s = Math.sin(spread);
        const dx = d.x * c - d.y * s, dy = d.x * s + d.y * c;
        const mx = player.x + dx * 0.45;
        const my = player.y + dy * 0.45;
        const lift = 30;
        const z0 = (player.h || 0) + lift / 32;
        const aimSlope = (typeof terrainHeight === 'function')
          ? Math.max(-0.45, Math.min(0.45, (terrainHeight(mx + dx * 5, my + dy * 5) - terrainHeight(mx, my)) / 5))
          : 0;

        weapon.bullets.push({ x: mx, y: my, sx: mx, sy: my, dx, dy, lift, age: 0, z: z0, z0, vzT: aimSlope });
        if (typeof characterShotFired === 'function') characterShotFired();
        if (typeof playShotSound === 'function') playShotSound();
        weapon.cooldown = (typeof FIRE_INTERVAL !== 'undefined') ? FIRE_INTERVAL : 0.11;
      }
    }

    // Обновление пуль в полете
    const bullets = weapon.bullets || [];
    for (let i = bullets.length - 1; i >= 0; i--) {
      const b = bullets[i];
      b.age += dt;
      b.px = b.x; b.py = b.y;
      b.x += b.dx * 30 * dt;
      b.y += b.dy * 30 * dt;
      b.z += (b.vzT || 0) * 30 * dt;
      const gz = (typeof terrainHeight === 'function') ? terrainHeight(b.x, b.y) : 0;
      if (b.z < gz + 0.12) {
        b.z = gz;
        if (typeof spawnImpact === 'function') { spawnImpact(b.x, b.y, 0, false); spawnImpact(b.x, b.y, 0, false); }
        bullets.splice(i, 1);
        continue;
      }
      if (typeof bulletHitsZombie === 'function' && bulletHitsZombie(b)) {
        bullets.splice(i, 1);
      } else if (typeof bulletHitsTree === 'function' && bulletHitsTree(b)) {
        if (typeof spawnImpact === 'function') spawnImpact(b.x, b.y, b.lift, true);
        bullets.splice(i, 1);
      } else if (b.age > 0.5) {
        bullets.splice(i, 1);
      }
    }
  };

  // Перехват касания кнопки огня: небольшая фора на жест оттягивания назад
  const fireBtn = document.getElementById('fire-btn');
  if (fireBtn) {
    fireBtn.addEventListener('touchstart', () => {
      if (typeof weapon !== 'undefined') {
        weapon._touchGrace = 0.08;
      }
    }, { passive: true });
    window.addEventListener('touchmove', (e) => {
      if (typeof weapon !== 'undefined' && weapon._touchGrace > 0) {
        for (let i = 0; i < e.changedTouches.length; i++) {
          const t = e.changedTouches[i];
          if (typeof fireTouchId !== 'undefined' && t.identifier === fireTouchId) {
            weapon._touchGrace = 0;
          }
        }
      }
    }, { passive: true });
  }
})();
// Страховка размера холста и новое управление огнем (v5.5).
// 1. Палец на стике огня: боец переходит в режим готовности (вскидывает ствол, целится, ходит).
// 2. Внутри круга (радиус < 30px): только прицеливание, выстрелов нет.
// 3. Выход за круг (радиус >= 30px): открывается огонь строго по направлению стика.
// 4. Бег вперед + стик назад: боец разворачивается назад, после чего сразу открывает огонь назад.
(function () {
  function fix() {
    if (typeof resize !== 'function' || typeof canvas === 'undefined') return;
    const w = window.innerWidth, h = window.innerHeight;
    const dpr = Math.min(window.devicePixelRatio || 1, MAX_DPR);
    const bad = canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr) ||
                canvas.style.width !== w + 'px' || canvas.style.height !== h + 'px';
    if (bad) { view.w = 0; resize(); }
  }
  window.addEventListener('orientationchange', () => { fix(); setTimeout(fix, 300); setTimeout(fix, 900); });
  document.addEventListener('fullscreenchange', () => { fix(); setTimeout(fix, 300); setTimeout(fix, 900); });
  if (window.visualViewport) window.visualViewport.addEventListener('resize', fix);
  setInterval(fix, 500);

  // Убираем серый слой наложения склонов (устраняет эффект тумана по всей карте)
  if (typeof window !== 'undefined') {
    window.drawGroundLight = function () { /* без серого тумана */ };
  }

  function wrapA(a) {
    while (a < -Math.PI) a += Math.PI * 2;
    while (a > Math.PI) a -= Math.PI * 2;
    return a;
  }

  // --- Переопределяем логику оружия: разделение зон «прицел» и «огонь» ---
  const FIRE_ZONE_RADIUS = 30; // px: внутри этого радиуса — только прицел и стойка, за ним — стрельба

  window.updateWeapon = function (dt) {
    if (typeof weapon === 'undefined') return;
    weapon.cooldown -= dt;
    if (weapon._turnTimer > 0) weapon._turnTimer -= dt;

    const aimA = (typeof weapon.aimAngle === 'number') ? weapon.aimAngle : (typeof player !== 'undefined' ? player.angle : 0);
    const moveA = (typeof joystick !== 'undefined' && joystick.active && (joystick.dx || joystick.dy))
      ? Math.atan2(joystick.dy, joystick.dx)
      : (typeof player !== 'undefined' ? player.angle : aimA);

    const diff = Math.abs(wrapA(aimA - moveA));
    const isAimingBack = diff > 0.85; // угол больше ~49° (целимся назад или сильно вбок относительно бега)

    if (isAimingBack) {
      if (weapon._lastAim !== aimA) {
        weapon._turnTimer = 0.16; // 160 мс на разворот корпуса/модели назад перед выстрелами
        weapon._lastAim = aimA;
      }
    } else {
      weapon._turnTimer = 0;
      weapon._lastAim = aimA;
    }

    const waitingTurn = isAimingBack && weapon._turnTimer > 0;
    const ready = typeof charAimBlend === 'undefined' || charAimBlend > 0.6;

    // Стреляем ТОЛЬКО если:
    // 1. Палец на кнопке (weapon.firing)
    // 2. Палец вытянут ЗА пределы круга (weapon._outsideCircle)
    // 3. Боец завершил разворот назад (не waitingTurn)
    // 4. Оружие готово к выстрелу
    if (weapon.firing && weapon._outsideCircle && ready && !waitingTurn && weapon.cooldown <= 0) {
      if (typeof player !== 'undefined') {
        const wx = Math.cos(aimA) + Math.sin(aimA);
        const wy = Math.sin(aimA) - Math.cos(aimA);
        const l = Math.hypot(wx, wy) || 1;
        const d = { x: wx / l, y: wy / l };

        const spread = (Math.random() - 0.5) * 0.04;
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

  // --- Перехватываем сенсорное управление стиком огня ---
  const fireBtn = document.getElementById('fire-btn');
  const fireKnob = document.getElementById('fire-knob');
  let fTouchId = null;
  let fCX = 0, fCY = 0;

  if (fireBtn) {
    // Стили индикации зон
    const styleEl = document.createElement('style');
    styleEl.textContent = `
      #fire-btn.aim-ready {
        border-color: rgba(255, 215, 0, 0.9) !important;
        box-shadow: 0 0 14px rgba(255, 215, 0, 0.4);
      }
      #fire-btn.fire-active {
        border-color: #ff3333 !important;
        background: rgba(255, 40, 40, 0.35) !important;
        box-shadow: 0 0 20px rgba(255, 50, 50, 0.7);
      }
    `;
    document.head.appendChild(styleEl);

    function onTouchStart(e) {
      for (let i = 0; i < e.changedTouches.length; i++) {
        const t = e.changedTouches[i];
        if (fireBtn.contains(t.target)) {
          fTouchId = t.identifier;
          const r = fireBtn.getBoundingClientRect();
          fCX = r.left + r.width / 2;
          fCY = r.top + r.height / 2;

          if (typeof weapon !== 'undefined') {
            weapon.firing = true; // включает режим готовности в character.js
            weapon._outsideCircle = false; // внутри круга: НЕ стрелять!
            weapon.aimAngle = (typeof player !== 'undefined') ? player.angle : 0;
          }
          fireBtn.classList.add('aim-ready');
          fireBtn.classList.remove('fire-active');
          updateKnob(t.clientX, t.clientY);
        }
      }
    }

    function onTouchMove(e) {
      if (fTouchId === null) return;
      for (let i = 0; i < e.changedTouches.length; i++) {
        const t = e.changedTouches[i];
        if (t.identifier === fTouchId) {
          updateKnob(t.clientX, t.clientY);
        }
      }
    }

    function updateKnob(x, y) {
      const dx = x - fCX, dy = y - fCY;
      const d = Math.hypot(dx, dy);

      if (typeof weapon !== 'undefined') {
        if (d > 6) {
          weapon.aimAngle = Math.atan2(dy, dx);
        }
        // Проверяем выход за круг:
        if (d >= FIRE_ZONE_RADIUS) {
          weapon._outsideCircle = true; // за кругом: СТРЕЛЬБА!
          fireBtn.classList.add('fire-active');
        } else {
          weapon._outsideCircle = false; // внутри круга: ТОЛЬКО ПРИЦЕЛ!
          fireBtn.classList.remove('fire-active');
        }
      }

      if (fireKnob) {
        const maxR = 44;
        const k = Math.min(d, maxR) / (d || 1);
        fireKnob.style.transform = 'translate(' + (dx * k) + 'px, ' + (dy * k) + 'px)';
      }
    }

    function onTouchEnd(e) {
      if (fTouchId === null) return;
      for (let i = 0; i < e.changedTouches.length; i++) {
        if (e.changedTouches[i].identifier === fTouchId) {
          fTouchId = null;
          if (typeof weapon !== 'undefined') {
            weapon.firing = false;
            weapon._outsideCircle = false;
          }
          fireBtn.classList.remove('aim-ready', 'fire-active');
          if (fireKnob) fireKnob.style.transform = '';
        }
      }
    }

    window.addEventListener('touchstart', onTouchStart, { capture: true, passive: false });
    window.addEventListener('touchmove', onTouchMove, { capture: true, passive: false });
    window.addEventListener('touchend', onTouchEnd, { capture: true, passive: false });
    window.addEventListener('touchcancel', onTouchEnd, { capture: true, passive: false });
  }
})();
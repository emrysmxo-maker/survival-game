// Плавающий джойстик огня (v5.7):
// 1. Кнопка огня по умолчанию полностью СКРЫТА (нет статической кнопки в углу).
// 2. Появляется ровно под пальцем при касании правой половины экрана. Исчезает при отпускании.
// 3. Не мешает джойстику ходьбы (нет перехвата чужих touch-событий — ходьба без лагов).
// 4. Пули не вылетают из спины: если боец бежит вперед, а прицел направлен назад,
//    боец сначала разворачивается лицом к цели, и только после разворота открывает огонь.
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

  const CAMERA_ELEV = 55 * Math.PI / 180;
  function toYaw(a) {
    return Math.atan2(Math.cos(a), Math.sin(a) / Math.sin(CAMERA_ELEV));
  }

  // --- Настройки джойстика огня ---
  const fireBtn = document.getElementById('fire-btn');
  const fireKnob = document.getElementById('fire-knob');
  const R_FIRE_THRESHOLD = 26; // px: внутри этого радиуса — только прицел, снаружи — огонь
  const R_MAX_KNOB = 44;       // px: максимальный ход шляпки

  const fireJoy = {
    active: false,
    touchId: null,
    baseX: 0,
    baseY: 0,
    dist: 0
  };

  // Стили: джойстик скрыт до касания, центрируется по пальцу
  const styleEl = document.createElement('style');
  styleEl.textContent = `
    #fire-btn {
      display: none !important;
      position: fixed !important;
      width: 90px !important;
      height: 90px !important;
      border-radius: 50% !important;
      margin: 0 !important;
      right: auto !important;
      bottom: auto !important;
      pointer-events: none !important;
      transform: translate(-50%, -50%) !important;
      z-index: 1000 !important;
      touch-action: none;
      user-select: none;
      -webkit-user-select: none;
      border: 2px solid rgba(255, 255, 255, 0.4) !important;
      background: rgba(0, 0, 0, 0.25) !important;
    }
    #fire-btn.active {
      display: block !important;
    }
    #fire-btn.floating-aim {
      border-color: rgba(255, 215, 0, 0.95) !important;
      box-shadow: 0 0 16px rgba(255, 215, 0, 0.5);
    }
    #fire-btn.floating-shoot {
      border-color: #ff3333 !important;
      background: rgba(255, 40, 40, 0.35) !important;
      box-shadow: 0 0 24px rgba(255, 50, 50, 0.85);
    }
    #fire-knob {
      pointer-events: none;
    }
  `;
  document.head.appendChild(styleEl);

  // Ускорение разворота бойца к цели
  const origUpdateCharacter = window.updateCharacter;
  if (typeof origUpdateCharacter === 'function') {
    window.updateCharacter = function (dt, isMoving, angle, speed) {
      origUpdateCharacter(dt, isMoving, angle, speed);
      if (typeof weapon !== 'undefined' && weapon.firing && typeof soldierRoot !== 'undefined' && soldierRoot) {
        const aimA = (typeof weapon.aimAngle === 'number') ? weapon.aimAngle : angle;
        const wantYaw = toYaw(aimA);
        const curYaw = soldierRoot.rotation.y;
        const diff = wrapA(wantYaw - curYaw);
        if (Math.abs(diff) > 0.05) {
          // Быстрый и плавный разворот (14 рад/с ≈ 0.2с на полный оборот 180°)
          soldierRoot.rotation.y = wrapA(curYaw + Math.sign(diff) * Math.min(Math.abs(diff), 14.0 * dt));
        }
      }
    };
  }

  // Обновление оружия каждый кадр
  window.updateWeapon = function (dt) {
    if (typeof weapon === 'undefined') return;
    weapon.cooldown -= dt;

    const aimA = (typeof weapon.aimAngle === 'number') ? weapon.aimAngle : (typeof player !== 'undefined' ? player.angle : 0);
    const wantYaw = toYaw(aimA);
    const curFacingYaw = (typeof soldierRoot !== 'undefined' && soldierRoot)
      ? soldierRoot.rotation.y
      : (typeof charYaw !== 'undefined' ? charYaw : wantYaw);

    const yawDiff = Math.abs(wrapA(curFacingYaw - wantYaw));
    // Боец готов стрелять, только если развернулся лицом к цели (отклонение < 22°)
    const isFacingTarget = yawDiff <= 0.38;

    // Стрельба ведется, если палец за пределами круга И боец уже повернулся к цели
    if (weapon.firing && weapon.shootAllowed && isFacingTarget && weapon.cooldown <= 0) {
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

  // Проверка: касается ли палец интерфейсных кнопок
  function isUI(target) {
    if (!target || !target.closest) return false;
    return !!(
      target.closest('#minimap') ||
      target.closest('#bigmap') ||
      target.closest('#style-bar') ||
      target.closest('.style-btn') ||
      target.closest('#rot-btn') ||
      target.closest('#daynight') ||
      target.closest('#dbg') ||
      target.closest('#zombie-btn') ||
      target.closest('#auto-btn')
    );
  }

  // Обработка касаний: НЕ вызываем stopPropagation, чтобы джойстик ходьбы на левой половине работал без малейших задержек!
  window.addEventListener('touchstart', (e) => {
    for (let i = 0; i < e.changedTouches.length; i++) {
      const t = e.changedTouches[i];
      if (isUI(t.target)) continue;

      // Если касание в правой половине экрана и джойстик огня свободен
      if (!fireJoy.active && t.clientX > window.innerWidth * 0.48) {
        fireJoy.active = true;
        fireJoy.touchId = t.identifier;
        fireJoy.baseX = t.clientX;
        fireJoy.baseY = t.clientY;
        fireJoy.dist = 0;

        if (typeof weapon !== 'undefined') {
          weapon.firing = true;
          weapon.shootAllowed = false;
          weapon.aimAngle = (typeof player !== 'undefined') ? player.angle : 0;
        }

        if (fireBtn) {
          fireBtn.style.left = t.clientX + 'px';
          fireBtn.style.top = t.clientY + 'px';
          fireBtn.classList.remove('floating-shoot');
          fireBtn.classList.add('active', 'floating-aim');
        }
        if (fireKnob) fireKnob.style.transform = '';
      }
    }
  }, { passive: true });

  window.addEventListener('touchmove', (e) => {
    if (!fireJoy.active) return;
    for (let i = 0; i < e.changedTouches.length; i++) {
      const t = e.changedTouches[i];
      if (t.identifier === fireJoy.touchId) {
        const dx = t.clientX - fireJoy.baseX;
        const dy = t.clientY - fireJoy.baseY;
        const dist = Math.hypot(dx, dy);
        fireJoy.dist = dist;

        if (typeof weapon !== 'undefined') {
          if (dist > 6) {
            weapon.aimAngle = Math.atan2(dy, dx);
          }
          if (dist >= R_FIRE_THRESHOLD) {
            weapon.shootAllowed = true;
            if (fireBtn) {
              fireBtn.classList.remove('floating-aim');
              fireBtn.classList.add('floating-shoot');
            }
          } else {
            weapon.shootAllowed = false;
            if (fireBtn) {
              fireBtn.classList.remove('floating-shoot');
              fireBtn.classList.add('floating-aim');
            }
          }
        }

        if (fireKnob) {
          const k = Math.min(dist, R_MAX_KNOB) / (dist || 1);
          fireKnob.style.transform = 'translate(' + (dx * k) + 'px, ' + (dy * k) + 'px)';
        }
      }
    }
  }, { passive: true });

  function endFireJoy(e) {
    if (!fireJoy.active) return;
    for (let i = 0; i < e.changedTouches.length; i++) {
      const t = e.changedTouches[i];
      if (t.identifier === fireJoy.touchId) {
        fireJoy.active = false;
        fireJoy.touchId = null;
        fireJoy.dist = 0;

        if (typeof weapon !== 'undefined') {
          weapon.firing = false;
          weapon.shootAllowed = false;
        }

        if (fireBtn) {
          fireBtn.classList.remove('active', 'floating-aim', 'floating-shoot');
          if (fireKnob) fireKnob.style.transform = '';
        }
      }
    }
  }

  window.addEventListener('touchend', endFireJoy, { passive: true });
  window.addEventListener('touchcancel', endFireJoy, { passive: true });
})();
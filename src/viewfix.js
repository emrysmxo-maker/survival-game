// Плавающий джойстик огня и прицеливания (v5.6).
// Касание в любой точке правой половины экрана -> джойстик появляется прямо под пальцем.
// Внутри круга (дистанция < 26px) -> боец вскидывает оружие и целится (без выстрелов).
// За пределами круга (дистанция >= 26px) -> открывается непрерывная стрельба ровно по направлению пальца.
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

  // --- Плавающий джойстик огня ---
  const fireBtn = document.getElementById('fire-btn');
  const fireKnob = document.getElementById('fire-knob');
  const R_FIRE_THRESHOLD = 26; // px: внутри этого радиуса — только прицел, снаружи — непрерывный огонь
  const R_MAX_KNOB = 44;       // px: максимальный ход шляпки

  const fireJoy = {
    active: false,
    touchId: null,
    baseX: 0,
    baseY: 0,
    dist: 0
  };

  // Стили для плавающего джойстика
  const styleEl = document.createElement('style');
  styleEl.textContent = `
    #fire-btn {
      transition: opacity 0.15s ease;
      touch-action: none;
      user-select: none;
      -webkit-user-select: none;
    }
    #fire-btn.floating-idle {
      opacity: 0.35 !important;
    }
    #fire-btn.floating-aim {
      opacity: 0.95 !important;
      border-color: rgba(255, 215, 0, 0.9) !important;
      box-shadow: 0 0 16px rgba(255, 215, 0, 0.45);
    }
    #fire-btn.floating-shoot {
      opacity: 1 !important;
      border-color: #ff3333 !important;
      background: rgba(255, 40, 40, 0.35) !important;
      box-shadow: 0 0 24px rgba(255, 50, 50, 0.8);
    }
    #fire-knob {
      pointer-events: none;
    }
  `;
  document.head.appendChild(styleEl);

  if (fireBtn) {
    fireBtn.classList.add('floating-idle');
  }

  // Обновление оружия каждый кадр
  window.updateWeapon = function (dt) {
    if (typeof weapon === 'undefined') return;
    weapon.cooldown -= dt;

    const aimA = (typeof weapon.aimAngle === 'number') ? weapon.aimAngle : (typeof player !== 'undefined' ? player.angle : 0);

    // Стрельба ведется непрерывно, пока палец за пределами круга
    if (weapon.firing && weapon.shootAllowed && weapon.cooldown <= 0) {
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

  // Проверка: касается ли палец UI элементов (чтобы не блокировать кнопки)
  function isUIElement(target) {
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

  function handleTouchStart(e) {
    for (let i = 0; i < e.changedTouches.length; i++) {
      const t = e.changedTouches[i];
      if (isUIElement(t.target)) continue;

      // Если касание в правой половине экрана и плавающий джойстик еще не активен
      if (!fireJoy.active && t.clientX > window.innerWidth * 0.48) {
        fireJoy.active = true;
        fireJoy.touchId = t.identifier;
        fireJoy.baseX = t.clientX;
        fireJoy.baseY = t.clientY;
        fireJoy.dist = 0;

        if (typeof weapon !== 'undefined') {
          weapon.firing = true; // в character.js включает стойку боевой готовности и прицел
          weapon.shootAllowed = false; // внутри круга — НЕ стрелять!
          weapon.aimAngle = (typeof player !== 'undefined') ? player.angle : 0;
        }

        // Перемещаем джойстик ровно в место касания пальца
        if (fireBtn) {
          const btnR = 45; // половина ширины 90px
          fireBtn.style.left = (t.clientX - btnR) + 'px';
          fireBtn.style.top = (t.clientY - btnR) + 'px';
          fireBtn.style.right = 'auto';
          fireBtn.style.bottom = 'auto';
          fireBtn.classList.remove('floating-idle', 'floating-shoot');
          fireBtn.classList.add('floating-aim');
        }
        if (fireKnob) fireKnob.style.transform = '';

        e.stopPropagation();
        e.preventDefault();
        break;
      }
    }
  }

  function handleTouchMove(e) {
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
            weapon.shootAllowed = true; // ВЫШЕЛ ЗА КРУГ: СТРЕЛЬБА!
            if (fireBtn) {
              fireBtn.classList.remove('floating-aim');
              fireBtn.classList.add('floating-shoot');
            }
          } else {
            weapon.shootAllowed = false; // ВНУТРИ КРУГА: ТОЛЬКО ПРИЦЕЛ!
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

        e.stopPropagation();
        e.preventDefault();
        break;
      }
    }
  }

  function handleTouchEnd(e) {
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
          fireBtn.classList.remove('floating-aim', 'floating-shoot');
          fireBtn.classList.add('floating-idle');
          fireKnob.style.transform = '';
        }

        e.stopPropagation();
        e.preventDefault();
        break;
      }
    }
  }

  // Перехват событий в фазе capture для мгновенного и надежного отклика
  window.addEventListener('touchstart', handleTouchStart, { capture: true, passive: false });
  window.addEventListener('touchmove', handleTouchMove, { capture: true, passive: false });
  window.addEventListener('touchend', handleTouchEnd, { capture: true, passive: false });
  window.addEventListener('touchcancel', handleTouchEnd, { capture: true, passive: false });
})();
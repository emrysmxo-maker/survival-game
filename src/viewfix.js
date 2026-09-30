// Страховка размера холста и синхронизация прицела со стволом (v5.8).
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

  // Стили для плавающего джойстика огня: по умолчанию скрыт, центрируется по пальцу
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
      border: 2px solid rgba(255, 215, 0, 0.85) !important;
      background: rgba(0, 0, 0, 0.25) !important;
      box-shadow: 0 0 14px rgba(255, 215, 0, 0.35);
    }
    #fire-btn.active {
      display: block !important;
    }
    #fire-btn.pressed {
      border-color: #ff3333 !important;
      background: rgba(255, 40, 40, 0.35) !important;
      box-shadow: 0 0 22px rgba(255, 50, 50, 0.85) !important;
    }
    #fire-knob {
      pointer-events: none;
    }
  `;
  document.head.appendChild(styleEl);

  // Обертка updateCharacter: стойка боевой готовности при прицеливании и быстрый доворот к цели
  const origUpdateCharacter = window.updateCharacter;
  if (typeof origUpdateCharacter === 'function') {
    window.updateCharacter = function (dt, isMoving, angle, speed) {
      if (typeof weapon === 'undefined') {
        origUpdateCharacter(dt, isMoving, angle, speed);
        return;
      }
      const realFiring = weapon.firing;
      if (weapon.aiming) weapon.firing = true; // боец вскидывает ствол в стойку готовности
      origUpdateCharacter(dt, isMoving, angle, speed);
      weapon.firing = realFiring;

      // Быстрый и плавный разворот 3D-модели к направлению прицела
      if ((weapon.firing || weapon.aiming) && typeof soldierRoot !== 'undefined' && soldierRoot) {
        const aimA = (typeof weapon.aimAngle === 'number') ? weapon.aimAngle : angle;
        const wantYaw = toYaw(aimA);
        const curYaw = soldierRoot.rotation.y;
        const diff = wrapA(wantYaw - curYaw);
        if (Math.abs(diff) > 0.04) {
          soldierRoot.rotation.y = wrapA(curYaw + Math.sign(diff) * Math.min(Math.abs(diff), 14.0 * dt));
        }
      }
    };
  }

  // Обертка updateWeapon: пули вылетают СТРОГО из дула 3D-автомата и только когда ствол направлен в цель!
  const origUpdateWeapon = window.updateWeapon;
  if (typeof origUpdateWeapon === 'function') {
    window.updateWeapon = function (dt) {
      if (typeof weapon === 'undefined') return;

      let gunAligned = true;
      if (weapon.firing && typeof charMuzzle !== 'undefined' && charMuzzle.ok && typeof weapon.aimAngle === 'number') {
        const a = weapon.aimAngle;
        const wx = Math.cos(a) + Math.sin(a);
        const wy = Math.sin(a) - Math.cos(a);
        const l = Math.hypot(wx, wy) || 1;
        const dot = charMuzzle.dirX * (wx / l) + charMuzzle.dirY * (wy / l);
        // Ствол должен быть направлен в сторону цели (разница < 49°, dot > 0.65)
        if (dot < 0.65) gunAligned = false;
      }

      const realFiring = weapon.firing;
      // Если ствол еще не развернулся к цели — блокируем выстрел (никаких пуль из спины!)
      if (!gunAligned) weapon.firing = false;
      origUpdateWeapon(dt);
      weapon.firing = realFiring;
    };
  }
})();
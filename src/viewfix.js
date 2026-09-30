// Страховка холста и синхронизация стрельбы с поворотом бойца (v6.0).
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

  // Стили для плавающего джойстика огня (по умолчанию полностью скрыт, появляется по нажатию)
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
      border: 2px solid rgba(255, 60, 60, 0.8) !important;
      background: rgba(255, 40, 40, 0.25) !important;
      box-shadow: 0 0 16px rgba(255, 50, 50, 0.6) !important;
    }
    #fire-btn.active {
      display: flex !important;
      align-items: center;
      justify-content: center;
    }
    #fire-knob {
      pointer-events: none;
    }
  `;
  document.head.appendChild(styleEl);

  // Быстрый доворот 3D-модели к направлению прицела (24 рад/с ≈ 0.13с на полный разворот 180°)
  const origUpdateCharacter = window.updateCharacter;
  if (typeof origUpdateCharacter === 'function') {
    window.updateCharacter = function (dt, isMoving, angle, speed) {
      origUpdateCharacter(dt, isMoving, angle, speed);
      if (typeof weapon !== 'undefined' && weapon.firing && typeof soldierRoot !== 'undefined' && soldierRoot) {
        const aimA = (typeof weapon.aimAngle === 'number') ? weapon.aimAngle : angle;
        const wantYaw = toYaw(aimA);
        const curYaw = soldierRoot.rotation.y;
        const diff = wrapA(wantYaw - curYaw);
        if (Math.abs(diff) > 0.04) {
          soldierRoot.rotation.y = wrapA(curYaw + Math.sign(diff) * Math.min(Math.abs(diff), 24.0 * dt));
        }
      }
    };
  }

  // Обертка updateWeapon: пули вылетают из дула автомата, при резком развороте выстрел удерживается ~0.1с до поворота к цели
  const origUpdateWeapon = window.updateWeapon;
  if (typeof origUpdateWeapon === 'function') {
    window.updateWeapon = function (dt) {
      if (typeof weapon === 'undefined') return;

      let facingOk = true;
      if (weapon.firing && typeof soldierRoot !== 'undefined' && soldierRoot && typeof weapon.aimAngle === 'number') {
        const wantYaw = toYaw(weapon.aimAngle);
        const curYaw = soldierRoot.rotation.y;
        const diff = Math.abs(wrapA(wantYaw - curYaw));
        // Если боец развернут в противоположную сторону (разница > 65°) — ждем 2-3 кадра пока повернется
        if (diff > 1.15) facingOk = false;
      }

      if (facingOk) {
        origUpdateWeapon(dt);
      } else {
        weapon.cooldown -= dt;
      }
    };
  }
})();
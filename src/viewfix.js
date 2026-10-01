// Страховка холста и синхронизация стрельбы с поворотом бойца (v6.5).
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

  function wrapA(a) {
    while (a < -Math.PI) a += Math.PI * 2;
    while (a > Math.PI) a -= Math.PI * 2;
    return a;
  }

  const CAMERA_ELEV = 55 * Math.PI / 180;
  function toYaw(a) {
    return Math.atan2(Math.cos(a), Math.sin(a) / Math.sin(CAMERA_ELEV));
  }

  // Быстрый доворот 3D-модели к направлению прицела (32 рад/с ≈ 0.1с на разворот 180°)
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
          soldierRoot.rotation.y = wrapA(curYaw + Math.sign(diff) * Math.min(Math.abs(diff), 32.0 * dt));
        }
      }
    };
  }

  // Обертка updateWeapon: пули вылетают строго в направлении прицела, при резком развороте выстрел удерживается 1-2 кадра до поворота к цели
  const origUpdateWeapon = window.updateWeapon;
  if (typeof origUpdateWeapon === 'function') {
    window.updateWeapon = function (dt) {
      if (typeof weapon === 'undefined') return;

      let facingOk = true;
      if (weapon.firing && typeof soldierRoot !== 'undefined' && soldierRoot && typeof weapon.aimAngle === 'number') {
        const wantYaw = toYaw(weapon.aimAngle);
        const curYaw = soldierRoot.rotation.y;
        const diff = Math.abs(wrapA(wantYaw - curYaw));
        // Если боец развернут в противоположную сторону (разница > 45°) — ждем 1-2 кадра пока повернется
        if (diff > 0.8) facingOk = false;
      }

      if (facingOk) {
        origUpdateWeapon(dt);
      } else {
        weapon.cooldown -= dt;
      }
    };
  }
})();

// Страховка размера холста и синхронизация прицела со стволом (v5.9).
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

  // Обертка updateCharacter:
  // 1. Когда палец на стике (weapon.aiming), боец вскидывает оружие к плечу
  // 2. Быстро поворачиваем модель к направлению прицела (22 рад/с), чтобы боец мгновенно разворачивался лицом к цели
  const origUpdateCharacter = window.updateCharacter;
  if (typeof origUpdateCharacter === 'function') {
    window.updateCharacter = function (dt, isMoving, angle, speed) {
      if (typeof weapon === 'undefined') {
        origUpdateCharacter(dt, isMoving, angle, speed);
        return;
      }
      const realFiring = weapon.firing;
      if (weapon.aiming) weapon.firing = true;
      origUpdateCharacter(dt, isMoving, angle, speed);
      weapon.firing = realFiring;

      // Быстрый доворот модели к прицелу
      if ((weapon.firing || weapon.aiming) && typeof soldierRoot !== 'undefined' && soldierRoot) {
        const aimA = (typeof weapon.aimAngle === 'number') ? weapon.aimAngle : angle;
        const wantYaw = toYaw(aimA);
        const curYaw = soldierRoot.rotation.y;
        const diff = wrapA(wantYaw - curYaw);
        if (Math.abs(diff) > 0.04) {
          soldierRoot.rotation.y = wrapA(curYaw + Math.sign(diff) * Math.min(Math.abs(diff), 22.0 * dt));
        }
      }
    };
  }
})();
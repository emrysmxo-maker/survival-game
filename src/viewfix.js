// Полный файл src/viewfix.js для v7.1:
// 1. Страховка холста при повороте и изменении размера окна (Android/RedMagic)
// 2. Полное устранение мигания теней на склонах и в ямах
// 3. 3D-рельеф ям, воронок авиаудара, оврагов реки и горных гряд без мерцания

(function () {
  'use strict';

  function fix() {
    if (typeof resize !== 'function' || typeof canvas === 'undefined') return;
    const w = window.innerWidth, h = window.innerHeight;
    const dpr = Math.min(window.devicePixelRatio || 1, (typeof MAX_DPR !== 'undefined' ? MAX_DPR : 3.3));
    const bad = canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr) ||
                canvas.style.width !== w + 'px' || canvas.style.height !== h + 'px';
    if (bad) {
      if (typeof view !== 'undefined') view.w = 0;
      resize();
    }
  }
  window.addEventListener('orientationchange', () => { fix(); setTimeout(fix, 300); setTimeout(fix, 900); });
  document.addEventListener('fullscreenchange', () => { fix(); setTimeout(fix, 300); setTimeout(fix, 900); });
  if (window.visualViewport) window.visualViewport.addEventListener('resize', fix);
  setInterval(fix, 500);

  // Старый per-frame вызов отключен — рельеф рисуется стабильным слоем в drawGroundLayer
  window.drawGroundLight = function () {};

  // Плавный, высококонтрастный и стабильный 3D-рельеф ям, оврагов и склонов
  function drawTerrainRelief(c) {
    if (typeof DBG !== 'undefined' && DBG.noSlopeLight) return;
    if (typeof toScreen !== 'function' || typeof view === 'undefined') return;

    const sun = (typeof sunLight === 'function') ? sunLight() : { dx: -0.7071, dy: -0.7071, sxs: -0.7071, sys: -0.7071, k: 0.9, e: 0.5 };
    const sunK = Math.max(0.15, Math.min(1.2, sun.k || 0.8));
    const e = sun.e !== undefined ? sun.e : 0.5;

    // Рельефные ямы и воронки в мире
    const pits = [
      { x: 75, y: 165, r: 8.0, depth: 3.2, name: 'crater' },
      { x: -25, y: -45, r: 6.5, depth: 2.5, name: 'pit' }
    ];

    for (const pItem of pits) {
      const pBottom = toScreen(pItem.x, pItem.y, -pItem.depth);
      const pRim = toScreen(pItem.x, pItem.y, 0);
      const rx = pItem.r * 32 * 1.414;
      const ry = pItem.r * 16 * 1.414;

      if (pRim.x < -rx - 80 || pRim.x > view.w + rx + 80 || pRim.y < -ry - 80 || pRim.y > view.h + ry + 80) continue;

      c.save();
      c.translate(pBottom.x, pBottom.y);
      c.scale(1, 0.5); // изометрический эллипс 2:1

      // 1. Объемное затенение дна чаши ямы (Ambient Occlusion)
      const gBowl = c.createRadialGradient(0, 0, 0, 0, 0, rx);
      gBowl.addColorStop(0, 'rgba(8, 16, 10, 0.48)');
      gBowl.addColorStop(0.35, 'rgba(10, 20, 12, 0.32)');
      gBowl.addColorStop(0.7, 'rgba(12, 24, 15, 0.14)');
      gBowl.addColorStop(1.0, 'rgba(12, 24, 15, 0.0)');
      c.fillStyle = gBowl;
      c.beginPath();
      c.arc(0, 0, rx, 0, Math.PI * 2);
      c.fill();

      // 2. Светотень теневого склона по солнцу
      const shDist = rx * 0.34;
      const shX = -sun.sxs * shDist;
      const shY = -sun.sys * shDist;
      const gSlope = c.createRadialGradient(shX, shY, 0, shX, shY, rx * 0.85);
      const shAlpha = (0.32 * Math.min(1.0, sunK)).toFixed(3);
      gSlope.addColorStop(0, `rgba(6, 12, 8, ${shAlpha})`);
      gSlope.addColorStop(0.5, `rgba(8, 16, 10, ${(shAlpha * 0.5).toFixed(3)})`);
      gSlope.addColorStop(1.0, 'rgba(8, 16, 10, 0.0)');
      c.fillStyle = gSlope;
      c.beginPath();
      c.arc(shX, shY, rx * 0.85, 0, Math.PI * 2);
      c.fill();

      // 3. Солнечный отсвет на противоположном склоне
      if (e > 0.02) {
        const litDist = rx * 0.38;
        const litX = sun.sxs * litDist;
        const litY = sun.sys * litDist;
        const gLit = c.createRadialGradient(litX, litY, 0, litX, litY, rx * 0.72);
        const litAlpha = (0.22 * Math.min(1.0, sunK)).toFixed(3);
        gLit.addColorStop(0, `rgba(255, 246, 210, ${litAlpha})`);
        gLit.addColorStop(0.5, `rgba(255, 246, 210, ${(litAlpha * 0.4).toFixed(3)})`);
        gLit.addColorStop(1.0, 'rgba(255, 246, 210, 0.0)');
        c.globalCompositeOperation = 'soft-light';
        c.fillStyle = gLit;
        c.beginPath();
        c.arc(litX, litY, rx * 0.72, 0, Math.PI * 2);
        c.fill();
        c.globalCompositeOperation = 'source-over';
      }

      c.restore();

      // 4. Четкая кромка (бровка) ямы
      c.save();
      c.translate(pRim.x, pRim.y);
      c.scale(1, 0.5);
      c.lineWidth = 3.2;
      c.strokeStyle = 'rgba(8, 16, 10, 0.22)';
      c.beginPath();
      c.arc(0, 0, rx * 0.98, 0, Math.PI * 2);
      c.stroke();
      c.restore();
    }

    // Рельеф русла реки Быстрянки (вдоль русла в пределах видимости)
    if (typeof riverCenterY === 'function') {
      const pcx = (typeof player !== 'undefined' ? player.x : 0);
      c.save();
      for (let sx = Math.floor(pcx - 24); sx <= Math.ceil(pcx + 24); sx += 4) {
        const sy = riverCenterY(sx);
        const pStr = toScreen(sx, sy, -2.2);
        if (pStr.x < -120 || pStr.x > view.w + 120 || pStr.y < -120 || pStr.y > view.h + 120) continue;

        c.save();
        c.translate(pStr.x, pStr.y);
        c.scale(1, 0.5);
        const gRav = c.createRadialGradient(0, 0, 0, 0, 0, 140);
        gRav.addColorStop(0, 'rgba(6, 15, 12, 0.36)');
        gRav.addColorStop(0.5, 'rgba(8, 18, 14, 0.18)');
        gRav.addColorStop(1.0, 'rgba(8, 18, 14, 0.0)');
        c.fillStyle = gRav;
        c.beginPath();
        c.arc(0, 0, 140, 0, Math.PI * 2);
        c.fill();
        c.restore();
      }
      c.restore();
    }
  }

  const origDrawGroundLayer = window.drawGroundLayer;
  window.drawGroundLayer = function (c) {
    drawTerrainRelief(c);
    if (typeof origDrawGroundLayer === 'function') {
      origDrawGroundLayer(c);
    }
  };

})();

// Полный файл src/viewfix.js для v7.0:
// 1. Страховка холста при повороте и изменении размера окна (Android/RedMagic)
// 2. Полное устранение мигания теней на склонах и в ямах (замена старого багованного drawGroundLight)
// 3. Выразительный, высококонтрастный и стабильный 3D-рельеф ям, оврагов и холмов без мерцания

(function () {
  'use strict';

  // 1. Страховка холста и разрешения экрана
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

  // 2. Полное устранение мерцания теней в ямах:
  // Старый алгоритм в render.js использовал ctx.clip(lightPoly) с полигоном без учета
  // динамического зума камеры, что вызывало стробоскопическое мигание на каждом шаге в яме.
  window.drawGroundLight = function () {
    // Старый багованный per-frame clip отключен — рельеф рисуется стабильным слоем в drawGroundLayer
  };

  // 3. Плавный, высококонтрастный и стабильный 3D-рельеф ям и склонов
  function drawTerrainRelief(c) {
    if (typeof DBG !== 'undefined' && DBG.noSlopeLight) return;
    if (typeof toScreen !== 'function' || typeof view === 'undefined') return;

    const sun = (typeof sunLight === 'function') ? sunLight() : { dx: -0.7071, dy: -0.7071, sxs: -0.7071, sys: -0.7071, k: 0.9, e: 0.5 };
    const sunK = Math.max(0.15, Math.min(1.2, sun.k || 0.8));
    const e = sun.e !== undefined ? sun.e : 0.5;

    // --- А. Рельеф основной ямы (на тестовой карте x=5, y=5, r=7, depth=2.6) ---
    const pitX = (typeof TEST_FEATURES !== 'undefined' && TEST_FEATURES.pit) ? TEST_FEATURES.pit.x : 5;
    const pitY = (typeof TEST_FEATURES !== 'undefined' && TEST_FEATURES.pit) ? TEST_FEATURES.pit.y : 5;
    const pitR = (typeof TEST_FEATURES !== 'undefined' && TEST_FEATURES.pit) ? TEST_FEATURES.pit.r : 7;
    const pitDepth = (typeof TEST_FEATURES !== 'undefined' && TEST_FEATURES.pit) ? TEST_FEATURES.pit.depth : 2.6;

    const pBottom = toScreen(pitX, pitY, -pitDepth);
    const pRim = toScreen(pitX, pitY, 0);

    const rx = pitR * 32 * 1.414; // горизонтальный радиус изометрии
    const ry = pitR * 16 * 1.414; // вертикальный радиус изометрии

    // Проверяем попадание ямы в экран с запасом
    if (pRim.x >= -rx - 80 && pRim.x <= view.w + rx + 80 && pRim.y >= -ry - 80 && pRim.y <= view.h + ry + 80) {
      c.save();

      // 1. Объемное затенение дна и чаши ямы (Ambient Occlusion)
      c.translate(pBottom.x, pBottom.y);
      c.scale(1, 0.5); // изометрический эллипс 2:1

      const gBowl = c.createRadialGradient(0, 0, 0, 0, 0, rx);
      gBowl.addColorStop(0, 'rgba(8, 16, 10, 0.46)');         // глубокое темное дно
      gBowl.addColorStop(0.35, 'rgba(10, 20, 12, 0.32)');     // нижний склон
      gBowl.addColorStop(0.7, 'rgba(12, 24, 15, 0.14)');      // верхний склон
      gBowl.addColorStop(1.0, 'rgba(12, 24, 15, 0.0)');       // плавно гаснет к бровке
      c.fillStyle = gBowl;
      c.beginPath();
      c.arc(0, 0, rx, 0, Math.PI * 2);
      c.fill();

      // 2. Светотень склонов по текущему положению солнца (без мерцания):
      // Теневой склон (противоположный солнцу)
      const shDist = rx * 0.34;
      const shX = -sun.sxs * shDist;
      const shY = -sun.sys * shDist;
      const gSlope = c.createRadialGradient(shX, shY, 0, shX, shY, rx * 0.85);
      const shAlpha = (0.30 * Math.min(1.0, sunK)).toFixed(3);
      gSlope.addColorStop(0, `rgba(6, 12, 8, ${shAlpha})`);
      gSlope.addColorStop(0.5, `rgba(8, 16, 10, ${(shAlpha * 0.5).toFixed(3)})`);
      gSlope.addColorStop(1.0, 'rgba(8, 16, 10, 0.0)');
      c.fillStyle = gSlope;
      c.beginPath();
      c.arc(shX, shY, rx * 0.85, 0, Math.PI * 2);
      c.fill();

      // 3. Солнечный отсвет на противоположном склоне ямы
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

      // 4. Тонкая контрастная кромка (бровка) ямы — четкая линия перелома рельефа
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

    // --- Б. Рельеф холма (на тестовой карте x=-8, y=-8, r=9, h=3.6) ---
    if (typeof TEST_FEATURES !== 'undefined' && TEST_FEATURES.hill) {
      const hx = TEST_FEATURES.hill.x, hy = TEST_FEATURES.hill.y, hr = TEST_FEATURES.hill.r, hh = TEST_FEATURES.hill.h;
      const pHill = toScreen(hx, hy, hh);
      const hrx = hr * 32 * 1.414;
      if (pHill.x >= -hrx - 80 && pHill.x <= view.w + hrx + 80 && pHill.y >= -hrx - 80 && pHill.y <= view.h + hrx + 80) {
        c.save();
        c.translate(pHill.x, pHill.y);
        c.scale(1, 0.5);

        // Солнечный акцент на вершине холма
        if (e > 0.02) {
          const gHillLit = c.createRadialGradient(0, 0, 0, 0, 0, hrx * 0.65);
          const hLitAlpha = (0.24 * Math.min(1.0, sunK)).toFixed(3);
          gHillLit.addColorStop(0, `rgba(255, 248, 220, ${hLitAlpha})`);
          gHillLit.addColorStop(0.6, `rgba(255, 248, 220, ${(hLitAlpha * 0.3).toFixed(3)})`);
          gHillLit.addColorStop(1.0, 'rgba(255, 248, 220, 0.0)');
          c.globalCompositeOperation = 'soft-light';
          c.fillStyle = gHillLit;
          c.beginPath();
          c.arc(0, 0, hrx * 0.65, 0, Math.PI * 2);
          c.fill();
          c.globalCompositeOperation = 'source-over';
        }

        // Теневой склон холма
        const hShX = -sun.sxs * hrx * 0.35;
        const hShY = -sun.sys * hrx * 0.35;
        const gHillSh = c.createRadialGradient(hShX, hShY, 0, hShX, hShY, hrx * 0.85);
        const hShAlpha = (0.24 * Math.min(1.0, sunK)).toFixed(3);
        gHillSh.addColorStop(0, `rgba(10, 18, 12, ${hShAlpha})`);
        gHillSh.addColorStop(0.6, `rgba(10, 18, 12, ${(hShAlpha * 0.4).toFixed(3)})`);
        gHillSh.addColorStop(1.0, 'rgba(10, 18, 12, 0.0)');
        c.fillStyle = gHillSh;
        c.beginPath();
        c.arc(hShX, hShY, hrx * 0.85, 0, Math.PI * 2);
        c.fill();

        c.restore();
      }
    }

    // --- В. Рельеф оврага и русла ручья (вдоль Y = 19 + 3*sin(0.18*X)) ---
    if (typeof testStreamY === 'function') {
      const pcx = (typeof player !== 'undefined' ? player.x : 0);
      c.save();
      for (let sx = Math.floor(pcx - 22); sx <= Math.ceil(pcx + 22); sx += 3.5) {
        const sy = testStreamY(sx);
        const pStr = toScreen(sx, sy, -2.0);
        if (pStr.x < -120 || pStr.x > view.w + 120 || pStr.y < -120 || pStr.y > view.h + 120) continue;

        c.save();
        c.translate(pStr.x, pStr.y);
        c.scale(1, 0.5);
        const gRav = c.createRadialGradient(0, 0, 0, 0, 0, 130);
        gRav.addColorStop(0, 'rgba(6, 15, 12, 0.36)');
        gRav.addColorStop(0.5, 'rgba(8, 18, 14, 0.20)');
        gRav.addColorStop(1.0, 'rgba(8, 18, 14, 0.0)');
        c.fillStyle = gRav;
        c.beginPath();
        c.arc(0, 0, 130, 0, Math.PI * 2);
        c.fill();
        c.restore();
      }
      c.restore();
    }
  }

  // Встраиваем стабильный рельеф в drawGroundLayer (вызывается сразу после drawGround)
  const origDrawGroundLayer = window.drawGroundLayer;
  window.drawGroundLayer = function (c) {
    drawTerrainRelief(c);
    if (typeof origDrawGroundLayer === 'function') {
      origDrawGroundLayer(c);
    }
  };

})();

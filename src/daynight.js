// День и ночь (отдельный файл, игру не трогает): время суток идёт само
// (сутки = DAY_REAL_MIN минут), ползунок внизу по центру — проверить любое время.
// Рисуется поверх мира, под джойстиком и кнопками:
//  • общий свет: ночью темно-синий, на рассвете/закате тёплый оранжевый;
//  • лучи солнца — мягкие косые полосы света от солнца (утром слева, вечером
//    справа), ярче всего в «золотой час», медленно колышутся;
//  • ночью — слабый свет вокруг бойца, чтобы было видно, куда идти.

const DAY_REAL_MIN = 12;          // сколько реальных минут длятся игровые сутки
const dayNight = { t: 10, auto: true };   // t — часы (0..24)

(function initDayNightUI() {
  const wrap = document.createElement('div');
  wrap.id = 'daynight';
  wrap.innerHTML = '<span id="dn-label">10:00</span><input id="dn-slider" type="range" min="0" max="24" step="0.05" value="10"><span id="dn-auto">⏸</span>';
  // стили прямо здесь: style.css у телефона мог остаться старым в кэше —
  // тогда ползунок уезжал наверх под панель
  wrap.style.cssText = 'position:fixed;left:50%;bottom:8px;transform:translateX(-50%);display:flex;align-items:center;gap:8px;' +
    'padding:4px 12px;background:rgba(10,16,10,0.78);border:1px solid rgba(255,255,255,0.22);border-radius:16px;' +
    'pointer-events:auto;z-index:30;font:13px sans-serif;color:#e8e2c8;touch-action:auto;';
  document.body.appendChild(wrap);
  const slider = wrap.querySelector('#dn-slider');
  slider.style.cssText = 'width:190px;accent-color:#e0a040;touch-action:auto;';
  wrap.querySelector('#dn-auto').style.cssText = 'font-size:16px;padding:0 4px;cursor:pointer;';
  const auto = wrap.querySelector('#dn-auto');
  slider.addEventListener('input', () => { dayNight.t = Number(slider.value); });
  auto.addEventListener('click', () => { dayNight.auto = !dayNight.auto; auto.textContent = dayNight.auto ? '⏸' : '▶'; });
  auto.addEventListener('touchend', (e) => { e.preventDefault(); auto.click(); });
})();

function updateDayNight(dt) {
  if (dayNight.auto) dayNight.t = (dayNight.t + dt * 24 / (DAY_REAL_MIN * 60)) % 24;
  const slider = document.getElementById('dn-slider');
  if (slider && document.activeElement !== slider) slider.value = dayNight.t.toFixed(2);
  const lab = document.getElementById('dn-label');
  if (lab) {
    const h = Math.floor(dayNight.t), m = Math.floor((dayNight.t - h) * 60);
    const txt = (h < 10 ? '0' : '') + h + ':' + (m < 10 ? '0' : '') + m;
    if (lab.textContent !== txt) lab.textContent = txt;
  }
}

// Высота солнца: 1 в полдень, 0 на рассвете (6:00) и закате (18:00), < 0 ночью.
function sunElevation(t) { return Math.sin(Math.PI * (t - 6) / 12); }

function lerp(a, b, k) { return a + (b - a) * k; }
function mixRGB(a, b, k) { return [lerp(a[0], b[0], k), lerp(a[1], b[1], k), lerp(a[2], b[2], k)]; }

const DN_DAY = [255, 255, 255];
const DN_GOLD = [255, 196, 140];
const DN_NIGHT = [72, 90, 142];

function drawDayNight(c) {
  const W = view.w, H = view.h, t = dayNight.t;
  const e = sunElevation(t);
  // общий свет: ночь → сумерки → золотой час → день
  let col;
  if (e <= -0.2) col = DN_NIGHT;
  else if (e < 0.05) col = mixRGB(DN_NIGHT, DN_GOLD, (e + 0.2) / 0.25);
  else if (e < 0.45) col = mixRGB(DN_GOLD, DN_DAY, (e - 0.05) / 0.4);
  else col = DN_DAY;

  c.save();
  c.setTransform(view.dpr, 0, 0, view.dpr, 0, 0);
  if (col !== DN_DAY) {
    c.globalCompositeOperation = 'multiply';
    c.fillStyle = `rgb(${col[0] | 0},${col[1] | 0},${col[2] | 0})`;
    c.fillRect(0, 0, W, H);
  }

  // лучи солнца
  if (e > -0.05) {
    const gold = e < 0.5 ? 1 - Math.max(0, e) / 0.5 : 0;       // низкое солнце — лучи сильнее и теплее
    const strength = Math.min(1, (e + 0.05) / 0.2) * (0.35 + 0.65 * gold);
    const morning = t < 12;
    // солнце за краем экрана: утром слева-сверху, вечером справа-сверху, в полдень сверху
    const sx = W * (0.5 + (morning ? -1 : 1) * (0.25 + 0.75 * (1 - Math.max(0, e)))), sy = -H * (0.35 + 0.4 * Math.max(0, e));
    const now = performance.now() / 1000;
    const rc = mixRGB([255, 250, 225], [255, 190, 110], gold);
    c.globalCompositeOperation = 'screen';
    const len = Math.hypot(W, H) * 1.6;
    const BEAMS = [[-0.34, 70, 0.9], [-0.2, 40, 0.6], [-0.08, 95, 1], [0.05, 55, 0.7], [0.17, 80, 0.85], [0.3, 45, 0.55]];
    const base = Math.atan2(H * 0.6 - sy, W * 0.5 - sx);
    for (let i = 0; i < BEAMS.length; i++) {
      const [da, wid, k] = BEAMS[i];
      const a = base + da + Math.sin(now * 0.07 + i * 1.9) * 0.015;
      const flick = 0.75 + 0.25 * Math.sin(now * 0.23 + i * 2.7);
      const alpha = 0.085 * strength * k * flick;
      c.save();
      c.translate(sx, sy);
      c.rotate(a);
      const g = c.createLinearGradient(0, -wid, 0, wid);
      g.addColorStop(0, `rgba(${rc[0] | 0},${rc[1] | 0},${rc[2] | 0},0)`);
      g.addColorStop(0.5, `rgba(${rc[0] | 0},${rc[1] | 0},${rc[2] | 0},${alpha.toFixed(3)})`);
      g.addColorStop(1, `rgba(${rc[0] | 0},${rc[1] | 0},${rc[2] | 0},0)`);
      c.fillStyle = g;
      c.beginPath();
      c.moveTo(0, -wid * 0.25); c.lineTo(len, -wid); c.lineTo(len, wid); c.lineTo(0, wid * 0.25);
      c.fill();
      c.restore();
    }
    // тёплое свечение со стороны солнца
    const glow = c.createRadialGradient(sx, sy, 0, sx, sy, Math.hypot(W, H) * 0.9);
    glow.addColorStop(0, `rgba(${rc[0] | 0},${rc[1] | 0},${rc[2] | 0},${(0.22 * strength).toFixed(3)})`);
    glow.addColorStop(1, `rgba(${rc[0] | 0},${rc[1] | 0},${rc[2] | 0},0)`);
    c.fillStyle = glow;
    c.fillRect(0, 0, W, H);
  }

  // ночью — слабый тёплый свет вокруг бойца
  const dark = e < 0.05 ? Math.min(1, (0.05 - e) / 0.25) : 0;
  if (dark > 0 && typeof player !== 'undefined') {
    const p = toScreen(player.x, player.y, player.h);
    const z = camera.zoom || 1;
    const px = (p.x - W / 2) * z + W / 2, py = (p.y - 30 - H / 2) * z + H / 2;
    const r = 170 * z;
    c.globalCompositeOperation = 'lighter';
    const g = c.createRadialGradient(px, py, 0, px, py, r);
    g.addColorStop(0, `rgba(120,100,70,${(0.5 * dark).toFixed(3)})`);
    g.addColorStop(1, 'rgba(120,100,70,0)');
    c.fillStyle = g;
    c.fillRect(px - r, py - r, r * 2, r * 2);
  }
  c.restore();
}

// Солнце для освещения земли (render.js, drawGroundLight): направление К солнцу
// по земле (мир) и сила светотени. Утром солнце слева экрана, в полдень сверху,
// вечером справа; низкое солнце — светотень сильнее (длинные тени), полдень —
// мягче, ночью — едва (луна).
function sunLight() {
  const t = dayNight.t, e = sunElevation(t);
  const th = Math.max(0, Math.min(Math.PI, Math.PI * (t - 6) / 12));
  const sxs = -Math.cos(th), sys = -Math.sin(th);            // на экране
  let dx = (sxs + sys) / 2, dy = (sys - sxs) / 2;             // в мир
  const l = Math.hypot(dx, dy) || 1; dx /= l; dy /= l;
  let k;
  if (e > 0) k = 0.55 + 0.75 * (1 - e);                       // 0.55 в полдень … 1.3 у горизонта
  else k = Math.max(0.12, 1.3 * (1 + e / 0.15));              // сумерки гаснут до лунных 0.12
  return { dx, dy, k: Math.max(0, k), sxs, sys, e };
}

// Единственные тени в игре — от солнца: деревья и боец/зомби. Направление —
// от солнца, длина — по его высоте (утром/вечером длинные), ночью их нет.
// Картинки теней деревьев отрендерены с солнцем слева (тень вправо) под ~48°,
// поэтому их поворачиваем и вытягиваем.
// Картинки теней обрезаны по краю холста рендера (у ствола) — при повороте
// тени этот срез становился резкой прямой линией. Края плавно гасим.
const _feather = {};
function featheredShadow(key) {
  if (_feather[key]) return _feather[key];
  const img = spriteImage(key, 'treeShadow');
  if (!img.complete || !img.naturalWidth) return null;
  const w = img.naturalWidth, h = img.naturalHeight;
  const cv = document.createElement('canvas'); cv.width = w; cv.height = h;
  const g = cv.getContext('2d');
  g.drawImage(img, 0, 0);
  g.globalCompositeOperation = 'destination-in';
  const f = Math.max(6, Math.round(Math.min(w, h) * 0.18));
  const mk = (x0, y0, x1, y1) => { const gr = g.createLinearGradient(x0, y0, x1, y1); gr.addColorStop(0, 'rgba(0,0,0,0)'); gr.addColorStop(1, 'rgba(0,0,0,1)'); return gr; };
  g.fillStyle = mk(0, 0, f, 0); g.fillRect(0, 0, w, h);
  g.fillStyle = mk(w, 0, w - f, 0); g.fillRect(0, 0, w, h);
  g.fillStyle = mk(0, 0, 0, f); g.fillRect(0, 0, w, h);
  g.fillStyle = mk(0, h, 0, h - f); g.fillRect(0, 0, w, h);
  _feather[key] = cv;
  return cv;
}

function drawSunShadows(c) {
  if (DBG.noSunShadow) return;
  const t = dayNight.t, e = sunElevation(t);
  if (e <= 0.02) return;
  const sun = sunLight();
  const alpha = 0.32 * Math.min(1, e / 0.15);
  const ang = Math.atan2(-sun.sys, -sun.sxs);                 // куда падает тень на экране
  const elev = Math.asin(Math.min(1, e)) || 0.02;
  const len = Math.max(0.6, Math.min(2.6, Math.tan(0.84) / Math.tan(Math.max(0.2, elev))));
  c.save();
  c.globalAlpha = alpha;
  for (const chunk of loadedChunks.values()) {
    for (const tr of chunk.trees) {
      const key = TREE_FILES[tr.type].replace('.png', '');
      const d = SPRITE_DATA.treeShadow[key];
      if (!d) continue;
      const p = toScreen(tr.x, tr.y, heightOf(tr));
      const R = (d.w + d.h) * len * (tr.scale || 1);
      if (p.x < -R || p.x > view.w + R || p.y < -R || p.y > view.h + R) continue;
      const img = featheredShadow(key);
      if (!img) continue;
      const sc = tr.scale || 1;
      c.save();
      c.translate(p.x, p.y);
      c.scale(1, TILE_H / TILE_W);            // поворот в плоскости земли (изометрия)
      c.rotate(ang);
      c.scale(len, 1);
      c.scale(1, TILE_W / TILE_H);
      c.drawImage(img, -d.ax * sc, -d.ay * sc, d.w * sc, d.h * sc);
      c.restore();
    }
  }
  c.globalAlpha = 1;
  const who = [[player.x, player.y, player.h, 1]];
  if (typeof zombies !== 'undefined') for (const z of zombies) who.push([z.x, z.y, undefined, z.state === 'walk' ? 1 : 1.4]);
  for (const [x, y, h, k] of who) {
    const p = toScreen(x, y, h);
    if (p.x < -80 || p.x > view.w + 80 || p.y < -80 || p.y > view.h + 80) continue;
    c.save();
    c.translate(p.x, p.y);
    c.scale(1, TILE_H / TILE_W);
    c.rotate(ang);
    const L = 26 * k * len;
    c.translate(L * 0.5, 0);
    c.scale(L / 12, 0.9 * k);
    const g = c.createRadialGradient(0, 0, 0, 0, 0, 12);
    g.addColorStop(0, `rgba(0,0,0,${(alpha * 1.3).toFixed(3)})`);
    g.addColorStop(1, 'rgba(0,0,0,0)');
    c.fillStyle = g;
    c.beginPath(); c.arc(0, 0, 12, 0, Math.PI * 2); c.fill();
    c.restore();
  }
  c.restore();
}

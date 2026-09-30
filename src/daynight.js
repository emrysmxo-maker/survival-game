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
  (document.getElementById('ui-overlay') || document.body).appendChild(wrap);
  const slider = wrap.querySelector('#dn-slider');
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

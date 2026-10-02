// Карта местности: круглая мини-карта справа вверху и большая карта по
// нажатию на неё. Рисуется из тех же функций рельефа, что и земля
// (terrainAt, pathDistAt в ground.js), поэтому показывает ручьи, болота,
// поляны, каменистые места и холмы (светотень) ещё до того, как туда
// дойдёшь. Ориентирована как экран (изометрия), боец в центре.

const MINIMAP_RADIUS = 42;     // тайлов от бойца до края мини-карты
const BIGMAP_RADIUS = 360;     // тайлов — вся карта 1.12 км²
const MINIMAP_RES = 72;        // точек по стороне
const BIGMAP_RES = 240;

const miniCanvas = document.getElementById('minimap-canvas');
const bigWrap = document.getElementById('bigmap');
const bigCanvas = document.getElementById('bigmap-canvas');
let miniAt = { x: 1e9, y: 1e9 }, miniT = 0;
let bigOpen = false;

// Цвет точки карты по местности
const _mt = {};
function mapColor(wx, wy) {
  const t = terrainAt(wx, wy, _mt);
  let r = 46, g = 74, b = 36;                                  // лес
  const mix = (k, rr, gg, bb) => { r += (rr - r) * k; g += (gg - g) * k; b += (bb - b) * k; };
  mix(t.clearing, 135, 170, 85);                                // поляна под постройки
  mix(t.rocky * 0.85, 125, 128, 120);                           // скалы и камни
  mix(t.swamp, 52, 66, 40);                                     // болото
  mix(t.path, 185, 150, 95);                                    // грунтовые дороги и тропы
  mix(t.ravine * 0.35, 36, 50, 30);                             // овраг русла
  mix(t.water, 55, 120, 175);                                   // река Быстрянка
  // светотень холмов и низин
  const hx = terrainHeight(wx + 1.2, wy) - t.h, hy = terrainHeight(wx, wy + 1.2) - t.h;
  const sh = Math.max(-0.35, Math.min(0.35, -(hx + hy) * 0.35));
  const k = 1 + sh;
  return [Math.round(r * k), Math.round(g * k), Math.round(b * k)];
}

// Рисует кусок карты вокруг (cx, cy) в холст (квадрат, изометрия экрана).
function drawTerrainMap(canvas, cx, cy, radius, res) {
  const g = canvas.getContext('2d');
  const img = g.createImageData(res, res);
  const span = radius * 2;
  for (let j = 0; j < res; j++) {
    for (let i = 0; i < res; i++) {
      const sx = (i / res - 0.5) * span * (TILE_W / 2);
      const sy = (j / res - 0.5) * span * (TILE_W / 2);
      const a = sx / (TILE_W / 2), bb = sy / (TILE_H / 2);
      const wx = cx + (a + bb) / 2, wy = cy + (bb - a) / 2;
      const c = mapColor(wx, wy);
      const o = (j * res + i) * 4;
      img.data[o] = c[0]; img.data[o + 1] = c[1]; img.data[o + 2] = c[2]; img.data[o + 3] = 255;
    }
  }
  const tmp = document.createElement('canvas');
  tmp.width = tmp.height = res;
  tmp.getContext('2d').putImageData(img, 0, 0);
  g.imageSmoothingEnabled = true;
  g.drawImage(tmp, 0, 0, canvas.width, canvas.height);
}

// Точка мира -> пиксель карты.
function mapPoint(canvas, cx, cy, radius, wx, wy) {
  const dx = wx - cx, dy = wy - cy;
  const sx = (dx - dy) * (TILE_W / 2), sy = (dx + dy) * (TILE_H / 2);
  const span = radius * 2 * (TILE_W / 2);
  return { x: (sx / span + 0.5) * canvas.width, y: (sy / span + 0.5) * canvas.height };
}

const MAP_LANDMARKS = [
  { name: '🏕️ Заимка', x: 0, y: -6 },
  { name: '🎖️ Блокпост', x: 42, y: -190 },
  { name: '🌉 Брод', x: 45, y: 62 },
  { name: '🏚️ Хутор', x: 60, y: 190 },
  { name: '🚪 Бункер', x: -175, y: 145 },
  { name: '💥 Воронка', x: 75, y: 165 }
];

function drawMarkers(canvas, cx, cy, radius, scale, isBig) {
  const g = canvas.getContext('2d');
  if (typeof zombies !== 'undefined') {
    for (const z of zombies) {
      if (z.state === 'dead') continue;
      const p = mapPoint(canvas, cx, cy, radius, z.x, z.y);
      g.fillStyle = '#e04030';
      g.beginPath(); g.arc(p.x, p.y, 3.5 * scale, 0, Math.PI * 2); g.fill();
    }
  }

  // Метки локаций на большой карте
  if (isBig) {
    g.font = 'bold 11px sans-serif';
    g.textAlign = 'center';
    g.textBaseline = 'bottom';
    for (const lm of MAP_LANDMARKS) {
      const p = mapPoint(canvas, cx, cy, radius, lm.x, lm.y);
      if (p.x < 10 || p.x > canvas.width - 10 || p.y < 10 || p.y > canvas.height - 10) continue;
      // Кружок
      g.fillStyle = '#f1c40f';
      g.beginPath(); g.arc(p.x, p.y, 4, 0, Math.PI * 2); g.fill();
      g.strokeStyle = '#000'; g.lineWidth = 1.5; g.stroke();
      // Подпись с фоновой плашкой
      g.fillStyle = 'rgba(0, 0, 0, 0.75)';
      const textW = g.measureText(lm.name).width;
      g.fillRect(p.x - textW / 2 - 3, p.y - 18, textW + 6, 14);
      g.fillStyle = '#fff';
      g.fillText(lm.name, p.x, p.y - 6);
    }
  }

  // Боец — стрелка по направлению взгляда
  const p = mapPoint(canvas, cx, cy, radius, player.x, player.y);
  g.save();
  g.translate(p.x, p.y);
  g.rotate(player.angle + Math.PI / 2);
  g.fillStyle = '#ffffff';
  g.strokeStyle = '#000000';
  g.lineWidth = 1.5 * scale;
  g.beginPath();
  g.moveTo(0, -7 * scale); g.lineTo(5 * scale, 6 * scale); g.lineTo(0, 3 * scale); g.lineTo(-5 * scale, 6 * scale);
  g.closePath(); g.fill(); g.stroke();
  g.restore();
}

let miniBase = null;
function updateMinimap(dt) {
  miniT -= dt;
  const moved = Math.hypot(player.x - miniAt.x, player.y - miniAt.y);
  if (!miniBase || (moved > 2 && miniT <= 0)) {
    miniAt = { x: player.x, y: player.y };
    miniT = 0.4;
    if (!miniBase) { miniBase = document.createElement('canvas'); miniBase.width = miniBase.height = miniCanvas.width; }
    drawTerrainMap(miniBase, miniAt.x, miniAt.y, MINIMAP_RADIUS, MINIMAP_RES);
  }
  const g = miniCanvas.getContext('2d');
  const off = mapPoint(miniCanvas, miniAt.x, miniAt.y, MINIMAP_RADIUS, player.x, player.y);
  g.clearRect(0, 0, miniCanvas.width, miniCanvas.height);
  g.drawImage(miniBase, miniCanvas.width / 2 - off.x, miniCanvas.height / 2 - off.y);
  drawMarkers(miniCanvas, player.x, player.y, MINIMAP_RADIUS, 1.3, false);
  if (bigOpen) drawBigMap();
}

let bigBase = null, bigAt = null;
function drawBigMap() {
  const size = 600;
  if (bigCanvas.width !== size) { bigCanvas.width = bigCanvas.height = size; }
  // Вся карта 1.12 км² центрирована в (0,0)
  if (!bigBase) {
    bigAt = { x: 0, y: 0 };
    bigBase = document.createElement('canvas');
    bigBase.width = bigBase.height = size;
    drawTerrainMap(bigBase, 0, 0, BIGMAP_RADIUS, BIGMAP_RES);
  }
  const g = bigCanvas.getContext('2d');
  g.drawImage(bigBase, 0, 0);
  drawMarkers(bigCanvas, 0, 0, BIGMAP_RADIUS, 1.8, true);
}

function toggleBigMap(open) {
  bigOpen = open === undefined ? !bigOpen : open;
  bigWrap.classList.toggle('open', bigOpen);
  if (bigOpen) drawBigMap();
}

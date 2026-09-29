// Карта местности: круглая мини-карта справа вверху и большая карта по
// нажатию на неё. Рисуется из тех же функций рельефа, что и земля
// (terrainAt, pathDistAt в ground.js), поэтому показывает ручьи, болота,
// поляны, каменистые места и холмы (светотень) ещё до того, как туда
// дойдёшь. Ориентирована как экран (изометрия), боец в центре.

const MINIMAP_RADIUS = 36;     // тайлов от бойца до края мини-карты
const BIGMAP_RADIUS = 140;     // тайлов — большая карта
const MINIMAP_RES = 72;        // точек по стороне
const BIGMAP_RES = 200;

const miniCanvas = document.getElementById('minimap-canvas');
const bigWrap = document.getElementById('bigmap');
const bigCanvas = document.getElementById('bigmap-canvas');
let miniAt = { x: 1e9, y: 1e9 }, miniT = 0;
let bigOpen = false;

// Цвет точки карты по местности.
const _mt = {};
function mapColor(wx, wy) {
  const t = terrainAt(wx, wy, _mt);
  let r = 52, g = 78, b = 40;                                  // лес
  const mix = (k, rr, gg, bb) => { r += (rr - r) * k; g += (gg - g) * k; b += (bb - b) * k; };
  mix(t.clearing, 150, 165, 95);                                // поляна
  mix(t.rocky * 0.8, 130, 130, 120);                            // камни
  mix(t.swamp, 70, 84, 48);                                     // болото
  mix(Math.max(0, Math.min(1, (1.9 - pathDistAt(wx, wy)) / 1.2)), 190, 160, 105); // тропа
  mix(t.ravine * 0.35, 40, 52, 34);                             // овраг темнее
  mix(t.water, 70, 118, 140);                                   // ручей
  // светотень холмов
  const hx = terrainHeight(wx + 1, wy) - t.h, hy = terrainHeight(wx, wy + 1) - t.h;
  const sh = Math.max(-0.35, Math.min(0.35, -(hx + hy) * 0.35));
  const k = 1 + sh;
  return [r * k, g * k, b * k];
}

// Рисует кусок карты вокруг (cx, cy) в холст (квадрат, изометрия экрана).
function drawTerrainMap(canvas, cx, cy, radius, res) {
  const g = canvas.getContext('2d');
  const img = g.createImageData(res, res);
  // точка карты -> экранное смещение -> мир (обратная toScreen)
  const span = radius * 2;
  for (let j = 0; j < res; j++) {
    for (let i = 0; i < res; i++) {
      // экран: по x ширина тайла TILE_W, по y — TILE_H; нормируем так,
      // чтобы radius тайлов по горизонтали = половине карты
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

function drawMarkers(canvas, cx, cy, radius, scale) {
  const g = canvas.getContext('2d');
  if (typeof zombies !== 'undefined') {
    for (const z of zombies) {
      if (z.state === 'dead') continue;
      const p = mapPoint(canvas, cx, cy, radius, z.x, z.y);
      g.fillStyle = '#e04030';
      g.beginPath(); g.arc(p.x, p.y, 3.5 * scale, 0, Math.PI * 2); g.fill();
    }
  }
  // боец — стрелка по направлению взгляда
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
  // сдвиг подложки, пока не перерисовали (карта «едет» плавно)
  const off = mapPoint(miniCanvas, miniAt.x, miniAt.y, MINIMAP_RADIUS, player.x, player.y);
  g.clearRect(0, 0, miniCanvas.width, miniCanvas.height);
  g.drawImage(miniBase, miniCanvas.width / 2 - off.x, miniCanvas.height / 2 - off.y);
  drawMarkers(miniCanvas, player.x, player.y, MINIMAP_RADIUS, 1.3);
  if (bigOpen) drawBigMap();
}

let bigBase = null, bigAt = null;
function drawBigMap() {
  const size = 600;
  if (bigCanvas.width !== size) { bigCanvas.width = bigCanvas.height = size; }
  if (!bigBase || Math.hypot(player.x - bigAt.x, player.y - bigAt.y) > 8) {
    bigAt = { x: player.x, y: player.y };
    if (!bigBase) { bigBase = document.createElement('canvas'); bigBase.width = bigBase.height = size; }
    drawTerrainMap(bigBase, bigAt.x, bigAt.y, BIGMAP_RADIUS, BIGMAP_RES);
  }
  const g = bigCanvas.getContext('2d');
  g.drawImage(bigBase, 0, 0);
  drawMarkers(bigCanvas, bigAt.x, bigAt.y, BIGMAP_RADIUS, 2);
}

function toggleBigMap(open) {
  bigOpen = open === undefined ? !bigOpen : open;
  bigWrap.classList.toggle('open', bigOpen);
  if (bigOpen) drawBigMap();
}

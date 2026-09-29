// Игрок и камера: положение в мире и перевод мировых координат в экранные.

const player = {
  x: 0,
  y: 0,
  vx: 0,
  vy: 0,
  // Скорость по каждой оси мира (тайлов/с) при полном джойстике. Реальная
  // скорость — √2 × это = ~3 тайла/с. Тайл ≈ 1.4 м (по размерам бойца),
  // то есть ~4.1 м/с — бодрый бег трусцой, предел, который анимация бойца
  // отрабатывает без скольжения ног. Раньше было 6.8 (≈13 м/с — быстрее
  // спринтера), и анимация шагов выглядела как катание на коньках.
  speed: 2.4,
  angle: 0,
  radius: 9,
  isMoving: false
};

const camera = { x: 0, y: 0 };

// Камера для отрисовки кадра: выровнена по реальным точкам экрана
// (1/dpr CSS-пикселя). Так картинка сдвигается ровными шагами в одну точку
// экрана, без пересчёта «между пикселями», и земля (drawGround) с объектами
// (toScreen) используют одно и то же значение — друг относительно друга
// не ездят. Обновляется в начале каждого кадра (render.js).
const renderCam = { x: 0, y: 0 };
function syncRenderCamera() {
  renderCam.x = Math.round(camera.x * view.dpr) / view.dpr;
  renderCam.y = Math.round(camera.y * view.dpr) / view.dpr;
}

// Мир -> экран (изометрическая проекция, TILE_W/TILE_H — из ground.js),
// в CSS-пикселях.
function toScreen(gx, gy) {
  return {
    x: (gx - gy) * (TILE_W / 2) - renderCam.x + view.w / 2,
    y: (gx + gy) * (TILE_H / 2) - renderCam.y + view.h / 2
  };
}

// Выталкивает игрока из стволов деревьев и сломанных стволов рядом.
// Смещение идёт по нормали к препятствию, поэтому вдоль него игрок скользит.
function collidePlayer() {
  const pcx = Math.floor(player.x / CHUNK_SIZE);
  const pcy = Math.floor(player.y / CHUNK_SIZE);
  for (let cx = pcx - 1; cx <= pcx + 1; cx++) {
    for (let cy = pcy - 1; cy <= pcy + 1; cy++) {
      const chunk = loadedChunks.get(`${cx},${cy}`);
      if (!chunk) continue;
      pushOut(chunk.trees, (t) => TREE_COLLIDE_R * Math.min(1.15, t.scale || 1));
      pushOut(chunk.clutter, () => CLUTTER_COLLIDE_R);
    }
  }
}

function pushOut(list, radiusOf) {
  for (const o of list) {
    const dx = player.x - o.x, dy = player.y - o.y;
    const r = radiusOf(o);
    if (Math.abs(dx) > r || Math.abs(dy) > r) continue;
    const d2 = dx * dx + dy * dy;
    if (d2 >= r * r) continue;
    const d = Math.sqrt(d2) || 0.0001;
    player.x = o.x + dx / d * r;
    player.y = o.y + dy / d * r;
  }
}

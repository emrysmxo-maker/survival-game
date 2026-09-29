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
// Между двумя близкими стволами круги перекрываются и выталкивание одного
// толкает в другой — тогда возвращаем игрока на прошлую позицию (prevX/prevY),
// чтобы он не протискивался в щель, где ему физически нет места.
function collidePlayer(prevX, prevY) {
  for (let pass = 0; pass < 3; pass++) {
    forNearbyObstacles(pushOut);
  }
  let stuck = false;
  forNearbyObstacles((list, radiusOf) => {
    for (const o of list) {
      const r = radiusOf(o) - 0.02;
      if (Math.hypot(player.x - o.x, player.y - o.y) < r) stuck = true;
    }
  });
  if (stuck) {
    player.x = prevX;
    player.y = prevY;
  }
}

function forNearbyObstacles(fn) {
  const pcx = Math.floor(player.x / CHUNK_SIZE);
  const pcy = Math.floor(player.y / CHUNK_SIZE);
  for (let cx = pcx - 1; cx <= pcx + 1; cx++) {
    for (let cy = pcy - 1; cy <= pcy + 1; cy++) {
      const chunk = loadedChunks.get(`${cx},${cy}`);
      if (!chunk) continue;
      fn(chunk.trees, treeCollideRadius);
      fn(chunk.clutter, (c) => CLUTTER_COLLIDE_R * Math.min(1.05, c.scale || 1));
      if (chunk.rocks) fn(chunk.rocks, rockCollideRadius);
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

// Радиус упора дерева (тайлы): полуширина основания ствола на экране,
// переведённая в тайлы (полуось окружности тайла по горизонтали ≈ 45 px),
// плюс запас на тело бойца.
function treeCollideRadius(t) {
  const halfPx = (TREE_TRUNK_W[t.type] || 0.1) * TREE_DRAW_W * (t.scale || 1) / 2;
  return Math.max(TREE_COLLIDE_MIN, halfPx * 1.15 / (TILE_W * 0.7) + TREE_COLLIDE_BODY);
}

// Радиус упора валуна (тайлы): полуширина камня на экране -> тайлы + тело.
function rockCollideRadius(o) {
  const halfPx = ROCK_TYPES[o.type].w * ROCK_DRAW * (o.scale || 1) / 2;
  return halfPx / (TILE_W * 0.7) + 0.22;
}

// Множитель скорости от местности: вода, болото, подъём/спуск.
// (mx, my) — направление движения в тайлах (не обязательно единичное).
const _ts = {};
function terrainSpeed(x, y, mx, my) {
  const t = terrainAt(x, y, _ts);
  let k = 1 - (1 - SPEED_WATER) * t.water;
  k *= 1 - (1 - SPEED_SWAMP) * t.swamp;
  const l = Math.hypot(mx, my);
  if (l > 1e-6) {
    // уклон по ходу движения (м на тайл): вверх — медленнее, вниз — чуть быстрее
    const e = 0.5, ux = mx / l, uy = my / l;
    const slope = (terrainHeight(x + ux * e, y + uy * e) - terrainHeight(x - ux * e, y - uy * e)) / (2 * e);
    k *= slope > 0 ? Math.max(0.55, 1 - slope * 0.55) : Math.min(1.12, 1 - slope * 0.15);
  }
  return k;
}

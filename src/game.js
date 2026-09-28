// Survival Game: Natural Forest Ecology
// Игровая логика. Деревья и подлесок — готовые PNG-спрайты из assets/trees/,
// а не нарисованный кодом узор: код только ставит картинку на карту.

// Версия ассетов: увеличивать при каждом обновлении PNG-спрайтов, чтобы
// браузер (в т.ч. кэш GitHub Pages и мобильный Chrome) не показывал старые
// картинки из кэша по тому же URL.
const ASSET_VERSION = 9;

const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');

function resize() {
  canvas.width = window.innerWidth;
  canvas.height = window.innerHeight;
}
window.addEventListener('resize', resize);
resize();

const TILE_W = 64;
const TILE_H = 32;

const player = {
  x: 0,
  y: 0,
  speed: 6.8,
  angle: 0,
  radius: 9,
  isMoving: false
};

const camera = { x: 0, y: 0 };

function toScreen(gx, gy) {
  return {
    x: (gx - gy) * (TILE_W / 2) - camera.x + canvas.width / 2,
    y: (gx + gy) * (TILE_H / 2) - camera.y + canvas.height / 2
  };
}

function pseudoRand(s) {
  const x = Math.sin(s) * 10000;
  return x - Math.floor(x);
}

// 12 видов деревьев: готовые картинки вместо процедурного рисования.
// 0: Сосна, 1: Дуб, 2: Берёза, 3: Клён, 4: Сухостой, 5: Голубая ель, 6: Ива, 7: Осина, 8: Рябина,
// 9: Сибирский кедр, 10: Лиственница, 11: Липа
const TREE_FILES = [
  '00_pine.png', '01_oak.png', '02_birch.png', '03_maple.png', '04_deadwood.png',
  '05_bluespruce.png', '06_willow.png', '07_aspen.png', '08_rowan.png',
  '09_cedar.png', '10_larch.png', '11_linden.png'
];
const treeSprites = TREE_FILES.map((file) => {
  const img = new Image();
  img.src = `assets/trees/${file}?v=${ASSET_VERSION}`;
  return img;
});

// Земля: настоящие бесшовные фототекстуры (Poly Haven, CC0), но НЕ нарезаны
// по одной картинке на клетку — так в изометрической ромбовидной сетке
// всегда виден шов (у каждого ромба 4 соседа по диагоналям, а не 4 ровных
// стороны). Вместо этого текстура рисуется как canvas-паттерн, растянутый
// матрицей той же изометрической проекции, что и toScreen() — получается
// один и тот же бесконечно повторяющийся кусок текстуры под всей картой,
// поэтому шва нет в принципе: соседние клетки — окна в одну и ту же плоскость.
// 0 трава, 1 светлая, 2 тропа, 3 тёмная, 4 пепел.
const GROUND_TEXTURE_FILES = ['grass.jpg', 'light.jpg', 'path.jpg', 'dark.jpg', 'ash.jpg'];
const GROUND_TILES_PER_TEXTURE = 3.2; // сколько игровых клеток занимает одно повторение текстуры
const groundImages = GROUND_TEXTURE_FILES.map((file) => {
  const img = new Image();
  img.src = `assets/ground/${file}?v=${ASSET_VERSION}`;
  return img;
});
const groundPatterns = groundImages.map(() => null);

// Лесной мусор: поваленные и сломанные деревья, пни, камни, ямы, мох.
// w/h — базовый размер отрисовки, anchor — какая доля высоты картинки выше точки (x,y).
const CLUTTER_TYPES = {
  fallen_log:   { file: 'fallen_log.png',   w: 130, h: 87,  anchor: 0.55 },
  broken_trunk: { file: 'broken_trunk.png', w: 70,  h: 121, anchor: 0.9 },
  stump:        { file: 'stump.png',        w: 75,  h: 89,  anchor: 0.85 },
  rocks:        { file: 'rocks.png',        w: 90,  h: 83,  anchor: 0.6 },
  pit:          { file: 'pit.png',          w: 120, h: 86,  anchor: 0.5 },
  moss_patch:   { file: 'moss_patch.png',   w: 120, h: 86,  anchor: 0.6 }
};
const clutterSprites = {};
for (const kind in CLUTTER_TYPES) {
  const img = new Image();
  img.src = `assets/clutter/${CLUTTER_TYPES[kind].file}?v=${ASSET_VERSION}`;
  clutterSprites[kind] = img;
}

// 2. РЕАЛИСТИЧНАЯ ЭКОЛОГИЧЕСКАЯ ГЕНЕРАЦИЯ (Многоярусность и дистанции)
// В реальном лесу есть:
// - Верхний ярус (Великаны: Сосны, Дубы, Кедры, Лиственницы) — растут просторно (дистанция 3.5 - 6 клеток).
// - Средний ярус (Березы, Осины, Липы, Рябины) — группируются между великанами.
// - Подлесок (Молодые деревца 12, Папоротники 13) — растут пятнами у подножия.
const CHUNK_SIZE = 12;
const CHUNK_RADIUS = 2;
const loadedChunks = new Map();

function getEcosystemAt(cx, cy) {
  const n = Math.sin(cx * 0.3) + Math.cos(cy * 0.3);
  if (n > 0.8) return {
    name: '🌲 Кедрово-сосновый бор',
    canopy: [0, 9, 5],      // Сосна, Кедр, Голубая ель
    subcanopy: [2, 7],      // Береза, Осина
  };
  if (n > 0.2) return {
    name: '🌳 Смешанный вековой лес',
    canopy: [1, 10, 0],     // Дуб, Лиственница, Сосна
    subcanopy: [11, 8, 3, 6], // Липа, Рябина, Клен, Ива
  };
  if (n > -0.4) return {
    name: '🪵 Берёзово-осиновая роща',
    canopy: [2, 7],         // Березы, Осины
    subcanopy: [8, 11, 6],  // Рябина, Липа, Ива
  };
  if (n > -0.9) return {
    name: '🍁 Осенняя дубрава',
    canopy: [1, 3],         // Дуб, Клен
    subcanopy: [8, 2],      // Рябина, Береза
  };
  return {
    name: '⚡ Выгоревшая гарь',
    canopy: [4, 4, 0],      // Сухостой
    subcanopy: [4, 0],
    ground: [4, 4, 2, 4],  // Пепел вместо травы, тропа остаётся тропой
  };
}

function generateChunk(cx, cy) {
  const key = `${cx},${cy}`;
  if (loadedChunks.has(key)) return loadedChunks.get(key);

  const eco = getEcosystemAt(cx, cy);
  const chunk = {
    cx, cy,
    biomeName: eco.name,
    tiles: [],
    trees: [],
    clutter: []
  };

  const startX = cx * CHUNK_SIZE;
  const startY = cy * CHUNK_SIZE;
  let seed = Math.abs(cx * 73856093 ^ cy * 19349663);

  // Земля. eco.ground переопределяет, какая текстура соответствует каждому
  // базовому типу почвы (0 трава, 1 светлая, 2 тропа, 3 тёмная) — например,
  // в выгоревшей гари трава и тёмная земля заменяются на пепел.
  // Биом для земли берётся не по чанку целиком (иначе на границе чанка
  // получается резкая прямая линия), а по мировым координатам каждой
  // клетки — тот же плавный шум, что определяет чанковый биом, просто
  // посчитанный в масштабе одной клетки, так что переход растянут на
  // много клеток и выглядит как естественная опушка, а не стена.
  for (let x = 0; x < CHUNK_SIZE; x++) {
    chunk.tiles[x] = [];
    for (let y = 0; y < CHUNK_SIZE; y++) {
      const wx = startX + x;
      const wy = startY + y;
      const tileEco = getEcosystemAt(wx / CHUNK_SIZE, wy / CHUNK_SIZE);
      const groundMap = tileEco.ground || [0, 1, 2, 3];
      const pathDist = Math.abs(wy - Math.sin(wx * 0.15) * 8);

      let tileType = 0;
      if (pathDist < 1.2) tileType = 2; // Тропа
      else {
        // sin(x)*cos(y) даёт математически «клетчатый» узор с прямыми
        // границами (перемножение двух волн) — вместо этого складываем
        // несколько волн под разными углами и частотами (как и для шума
        // экосистемы выше): границы получаются органичными, а не
        // нарисованными по линейке, и пятна — крупные, в духе настоящих
        // полян/просек, а не мелкая мозаика через каждые 15 клеток.
        const n = (
          Math.sin(wx * 0.06 + wy * 0.035) +
          Math.sin(wx * 0.035 - wy * 0.07) * 1.3 +
          Math.sin(wx * 0.12 + wy * 0.09) * 0.5
        ) / 2.8;
        if (n > 0.32) tileType = 1;
        else if (n < -0.28) tileType = 3;
      }
      const groundType = groundMap[tileType];
      chunk.tiles[x][y] = { t: groundType, isPath: tileType === 2 };
    }
  }

  // 1. ВЕРХНИЙ ЯРУС (Великаны) — спавнятся с дистанцией отталкивания > 3.0 клеток
  const giantCount = 2 + Math.floor(pseudoRand(seed++) * 3);
  for (let g = 0; g < giantCount; g++) {
    const gx = startX + 1.5 + pseudoRand(seed++) * (CHUNK_SIZE - 3);
    const gy = startY + 1.5 + pseudoRand(seed++) * (CHUNK_SIZE - 3);

    const localX = Math.floor(gx - startX);
    const localY = Math.floor(gy - startY);
    if (chunk.tiles[localX] && chunk.tiles[localX][localY].isPath) continue; // Не на тропе

    let tooClose = false;
    for (const t of chunk.trees) {
      if (Math.hypot(t.x - gx, t.y - gy) < 3.2) { tooClose = true; break; }
    }

    if (!tooClose) {
      const type = eco.canopy[Math.floor(pseudoRand(seed++) * eco.canopy.length)];
      chunk.trees.push({
        x: gx, y: gy,
        type: type,
        scale: 1.0 + pseudoRand(seed++) * 0.25,
        isGiant: true
      });

      // 2. СРЕДНИЙ ЯРУС ВОКРУГ ВЕЛИКАНА (Кластеры в радиусе 1.8 - 2.8)
      const satelliteCount = 1 + Math.floor(pseudoRand(seed++) * 3);
      for (let sIdx = 0; sIdx < satelliteCount; sIdx++) {
        const ang = pseudoRand(seed++) * Math.PI * 2;
        const dist = 1.8 + pseudoRand(seed++) * 1.6;
        const sx = gx + Math.cos(ang) * dist;
        const sy = gy + Math.sin(ang) * dist;
        const subType = eco.subcanopy[Math.floor(pseudoRand(seed++) * eco.subcanopy.length)];
        chunk.trees.push({ x: sx, y: sy, type: subType, scale: 0.75 + pseudoRand(seed++) * 0.2 });
      }
    }
  }

  // 1.5. РЕДКИЕ СУХОСТОИ: одиночное мёртвое/сломанное дерево может реалистично
  // встретиться в любом биоме, не только в выгоревшей гари — но нечасто.
  if (pseudoRand(seed++) < 0.22) {
    const dx = startX + 1.5 + pseudoRand(seed++) * (CHUNK_SIZE - 3);
    const dy = startY + 1.5 + pseudoRand(seed++) * (CHUNK_SIZE - 3);
    const localX = Math.floor(dx - startX);
    const localY = Math.floor(dy - startY);
    const onPath = chunk.tiles[localX] && chunk.tiles[localX][localY].isPath;
    let tooClose = false;
    for (const t of chunk.trees) {
      if (Math.hypot(t.x - dx, t.y - dy) < 3.0) { tooClose = true; break; }
    }
    if (!onPath && !tooClose) {
      chunk.trees.push({ x: dx, y: dy, type: 4, scale: 0.9 + pseudoRand(seed++) * 0.3, isGiant: true });
    }
  }

  // 3. ЛЕСНОЙ МУСОР: то, что обычно встречается под ногами в реальном лесу —
  // поваленные и сломанные деревья, пни, валуны, ямы, пятна мха. Редко и не на тропе.
  const CLUTTER_KINDS = ['moss_patch', 'rocks', 'fallen_log', 'stump', 'broken_trunk', 'pit'];
  const CLUTTER_WEIGHTS = [0.30, 0.25, 0.17, 0.14, 0.09, 0.05];
  for (let x = 0; x < CHUNK_SIZE; x++) {
    for (let y = 0; y < CHUNK_SIZE; y++) {
      if (chunk.tiles[x][y].isPath) continue; // Не на тропе
      if (pseudoRand(seed++) > 0.07) continue; // ~7% клеток

      const wx = startX + x + 0.5 + (pseudoRand(seed++) - 0.5) * 0.7;
      const wy = startY + y + 0.5 + (pseudoRand(seed++) - 0.5) * 0.7;

      let tooCloseToGiant = false;
      for (const t of chunk.trees) {
        if (t.isGiant && Math.hypot(t.x - wx, t.y - wy) < 1.3) { tooCloseToGiant = true; break; }
      }
      if (tooCloseToGiant) continue;

      let roll = pseudoRand(seed++);
      let kind = CLUTTER_KINDS[CLUTTER_KINDS.length - 1];
      for (let i = 0; i < CLUTTER_WEIGHTS.length; i++) {
        if (roll < CLUTTER_WEIGHTS[i]) { kind = CLUTTER_KINDS[i]; break; }
        roll -= CLUTTER_WEIGHTS[i];
      }

      chunk.clutter.push({
        x: wx, y: wy, kind,
        scale: 0.85 + pseudoRand(seed++) * 0.3,
        flip: pseudoRand(seed++) > 0.5
      });
    }
  }

  loadedChunks.set(key, chunk);
  return chunk;
}

function updateWorldChunks() {
  const pChunkX = Math.floor(player.x / CHUNK_SIZE);
  const pChunkY = Math.floor(player.y / CHUNK_SIZE);

  for (let dx = -CHUNK_RADIUS; dx <= CHUNK_RADIUS; dx++) {
    for (let dy = -CHUNK_RADIUS; dy <= CHUNK_RADIUS; dy++) {
      generateChunk(pChunkX + dx, pChunkY + dy);
    }
  }

  for (const [key, chunk] of loadedChunks.entries()) {
    if (Math.abs(chunk.cx - pChunkX) > 4 || Math.abs(chunk.cy - pChunkY) > 4) {
      loadedChunks.delete(key);
    }
  }

  const curEco = getEcosystemAt(pChunkX, pChunkY);
  document.getElementById('info-biome').textContent = curEco.name;
  document.getElementById('info-coords').textContent = `X: ${Math.round(player.x)}, Y: ${Math.round(player.y)}`;

  let totalTrees = 0;
  loadedChunks.forEach(c => {
    totalTrees += c.trees.length;
  });
  document.getElementById('info-trees').textContent = totalTrees;
}

// 3. СЕНСОРНОЕ УПРАВЛЕНИЕ ТОЧКОЙ
const joystick = {
  active: false, touchId: null,
  startX: 0, startY: 0,
  currX: 0, currY: 0,
  maxDist: 50, dx: 0, dy: 0
};

window.addEventListener('touchstart', (e) => {
  e.preventDefault();
  for (let i = 0; i < e.changedTouches.length; i++) {
    const t = e.changedTouches[i];
    if (!joystick.active) {
      joystick.active = true;
      joystick.touchId = t.identifier;
      joystick.startX = t.clientX; joystick.startY = t.clientY;
      joystick.currX = t.clientX; joystick.currY = t.clientY;
      joystick.dx = 0; joystick.dy = 0;
      document.getElementById('joystick-hint').style.display = 'none';
    }
  }
}, { passive: false });

window.addEventListener('touchmove', (e) => {
  e.preventDefault();
  for (let i = 0; i < e.changedTouches.length; i++) {
    const t = e.changedTouches[i];
    if (t.identifier === joystick.touchId) {
      const diffX = t.clientX - joystick.startX;
      const diffY = t.clientY - joystick.startY;
      const dist = Math.hypot(diffX, diffY);

      if (dist > joystick.maxDist) {
        joystick.currX = joystick.startX + (diffX / dist) * joystick.maxDist;
        joystick.currY = joystick.startY + (diffY / dist) * joystick.maxDist;
      } else {
        joystick.currX = t.clientX;
        joystick.currY = t.clientY;
      }

      joystick.dx = (joystick.currX - joystick.startX) / joystick.maxDist;
      joystick.dy = (joystick.currY - joystick.startY) / joystick.maxDist;
    }
  }
}, { passive: false });

function stopJoy(id) {
  if (joystick.touchId === id) {
    joystick.active = false; joystick.touchId = null;
    joystick.dx = 0; joystick.dy = 0;
  }
}
window.addEventListener('touchend', (e) => { for (const t of e.changedTouches) stopJoy(t.identifier); });
window.addEventListener('touchcancel', (e) => { for (const t of e.changedTouches) stopJoy(t.identifier); });

// 4. ИГРОВОЙ ЦИКЛ
let lastTime = performance.now();
function update(dt) {
  if (joystick.active && (Math.abs(joystick.dx) > 0.05 || Math.abs(joystick.dy) > 0.05)) {
    player.isMoving = true;
    const moveX = joystick.dx + joystick.dy;
    const moveY = joystick.dy - joystick.dx;

    player.x += moveX * player.speed * dt;
    player.y += moveY * player.speed * dt;
    player.angle = Math.atan2(joystick.dy, joystick.dx);
  } else {
    player.isMoving = false;
  }

  const targetCamX = (player.x - player.y) * (TILE_W / 2);
  const targetCamY = (player.x + player.y) * (TILE_H / 2);
  camera.x += (targetCamX - camera.x) * 0.12;
  camera.y += (targetCamY - camera.y) * 0.12;

  updateWorldChunks();
}

// 5. ОТРИСОВКА
// Земля рисуется сплошной заливкой (0 трава, 1 светлая, 2 тропа, 3 тёмная,
// 4 пепел) с лёгким шумом яркости на клетку — никаких повторяющихся
// картинок-плиток, поэтому в изометрической ромбовидной сетке в принципе
// неоткуда взяться видимым швам или «шахматному» узору.
const GROUND_TEX_PX = 192; // ассеты assets/ground/*.jpg приведены к этому размеру
const GROUND_OVERSCAN = 1.2; // нахлёст между соседними ромбами, см. комментарий в render()
const tileFallbackColors = ['#3a5428', '#60843a', '#7c603e', '#2a3620', '#3a3836'];

// Обновляет матрицу паттерна так, чтобы он был «приклеен» к миру (двигался
// вместе с камерой), а не к экрану — иначе при ходьбе земля будет скользить
// под ногами игрока, а не оставаться на месте под деревьями.
function updateGroundPatternTransform(pattern) {
  const k = GROUND_TEX_PX / GROUND_TILES_PER_TEXTURE;
  const a = TILE_W / (2 * k);
  const b = TILE_H / (2 * k);
  const offsetX = -camera.x + canvas.width / 2;
  const offsetY = -camera.y + canvas.height / 2;
  pattern.setTransform(new DOMMatrix([a, b, -a, b, offsetX, offsetY]));
}

function render() {
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';

  const halfW = TILE_W / 2;
  const halfH = TILE_H / 2;
  const renderQueue = [];

  // Паттерны создаются лениво, как только картинка загрузилась, и каждый
  // кадр переориентируются под текущее положение камеры.
  for (let i = 0; i < groundImages.length; i++) {
    if (!groundPatterns[i] && groundImages[i].complete && groundImages[i].naturalWidth) {
      groundPatterns[i] = ctx.createPattern(groundImages[i], 'repeat');
    }
    if (groundPatterns[i]) updateGroundPatternTransform(groundPatterns[i]);
  }

  for (const [, chunk] of loadedChunks.entries()) {
    const startX = chunk.cx * CHUNK_SIZE;
    const startY = chunk.cy * CHUNK_SIZE;

    for (let x = 0; x < CHUNK_SIZE; x++) {
      for (let y = 0; y < CHUNK_SIZE; y++) {
        const wx = startX + x;
        const wy = startY + y;
        const pt = toScreen(wx, wy);

        if (pt.x < -TILE_W || pt.x > canvas.width + TILE_W || pt.y < -TILE_H || pt.y > canvas.height + TILE_H) continue;

        const tile = chunk.tiles[x][y];
        // Каждый ромб красится отдельным ctx.fill(), и Canvas сглаживает
        // (антиалиасит) края КАЖДОГО из них независимо — на стыке двух
        // соседних ромбов это даёт тонкую паразитную линию, даже если
        // текстура под ними абсолютно одна и та же. Лечится небольшим
        // нахлёстом: полигон рисуется на пару пикселей больше клетки,
        // соседи перекрывают друг друга и линия пропадает.
        const cy = pt.y + halfH;
        ctx.beginPath();
        ctx.moveTo(pt.x, cy - halfH - GROUND_OVERSCAN);
        ctx.lineTo(pt.x + halfW + GROUND_OVERSCAN, cy);
        ctx.lineTo(pt.x, cy + halfH + GROUND_OVERSCAN);
        ctx.lineTo(pt.x - halfW - GROUND_OVERSCAN, cy);
        ctx.closePath();
        ctx.fillStyle = groundPatterns[tile.t] || tileFallbackColors[tile.t];
        ctx.fill();
      }
    }

    // Лесной мусор (пни, поваленные стволы, камни, ямы, мох)
    for (const c of chunk.clutter) {
      renderQueue.push({ isPlayer: false, isClutter: true, obj: c, depth: c.x + c.y });
    }

    // Деревья
    for (const t of chunk.trees) {
      renderQueue.push({ isPlayer: false, isClutter: false, obj: t, depth: t.x + t.y });
    }
  }

  renderQueue.push({ isPlayer: true, obj: player, depth: player.x + player.y });
  renderQueue.sort((a, b) => a.depth - b.depth);

  renderQueue.forEach(item => {
    if (item.isPlayer) {
      const pos = toScreen(player.x, player.y);
      ctx.beginPath();
      ctx.ellipse(pos.x, pos.y + 4, 10, 5, 0, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(0,0,0,0.5)';
      ctx.fill();

      ctx.beginPath();
      ctx.arc(pos.x, pos.y - 8, player.radius, 0, Math.PI * 2);
      ctx.fillStyle = '#2ecc71';
      ctx.fill();
      ctx.strokeStyle = '#ffffff';
      ctx.lineWidth = 2.5;
      ctx.stroke();

      ctx.strokeStyle = '#ffffff';
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.moveTo(pos.x, pos.y - 8);
      ctx.lineTo(pos.x + Math.cos(player.angle) * 16, pos.y - 8 + Math.sin(player.angle) * 16);
      ctx.stroke();

    } else if (item.isClutter) {
      const obj = item.obj;
      const pos = toScreen(obj.x, obj.y);
      if (pos.x < -100 || pos.x > canvas.width + 100 || pos.y < -120 || pos.y > canvas.height + 100) return;

      const def = CLUTTER_TYPES[obj.kind];
      const sprite = clutterSprites[obj.kind];
      const scale = obj.scale || 1.0;
      const dw = def.w * scale;
      const dh = def.h * scale;

      if (sprite.complete) {
        if (obj.flip) {
          ctx.save();
          ctx.translate(pos.x, 0);
          ctx.scale(-1, 1);
          ctx.drawImage(sprite, -dw / 2, pos.y - dh * def.anchor, dw, dh);
          ctx.restore();
        } else {
          ctx.drawImage(sprite, pos.x - dw / 2, pos.y - dh * def.anchor, dw, dh);
        }
      }

    } else {
      const obj = item.obj;
      const pos = toScreen(obj.x, obj.y);
      if (pos.x < -120 || pos.x > canvas.width + 120 || pos.y < -220 || pos.y > canvas.height + 100) return;

      const sprite = treeSprites[obj.type];
      const scale = obj.scale || 1.0;
      const dw = 110 * scale;
      const dh = 150 * scale;

      ctx.beginPath();
      ctx.ellipse(pos.x + 3, pos.y + 3, 26 * scale, 13 * scale, 0, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(0, 0, 0, 0.45)';
      ctx.fill();

      if (sprite.complete) {
        ctx.drawImage(sprite, pos.x - dw / 2, pos.y - dh * 0.92, dw, dh);
      }
    }
  });

  // Сенсорный джойстик
  if (joystick.active) {
    ctx.beginPath();
    ctx.arc(joystick.startX, joystick.startY, joystick.maxDist, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(255, 255, 255, 0.08)';
    ctx.fill();
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.25)';
    ctx.lineWidth = 2;
    ctx.stroke();

    ctx.beginPath();
    ctx.arc(joystick.currX, joystick.currY, 22, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(46, 204, 113, 0.7)';
    ctx.fill();
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 1.5;
    ctx.stroke();
  }

  // Виньетка
  const vignette = ctx.createRadialGradient(
    canvas.width / 2, canvas.height / 2, Math.min(canvas.width, canvas.height) * 0.35,
    canvas.width / 2, canvas.height / 2, Math.max(canvas.width, canvas.height) * 0.75
  );
  vignette.addColorStop(0, 'rgba(0, 0, 0, 0)');
  vignette.addColorStop(1, 'rgba(4, 7, 4, 0.55)');
  ctx.fillStyle = vignette;
  ctx.fillRect(0, 0, canvas.width, canvas.height);
}

function gameLoop(time) {
  const dt = Math.min((time - lastTime) / 1000, 0.1);
  lastTime = time;
  update(dt);
  render();
  requestAnimationFrame(gameLoop);
}
requestAnimationFrame(gameLoop);

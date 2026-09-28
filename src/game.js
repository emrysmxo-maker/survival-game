// Survival Game: Natural Forest Ecology
// Игровая логика. Деревья и подлесок — готовые PNG-спрайты из assets/trees/,
// а не нарисованный кодом узор: код только ставит картинку на карту.

// Версия ассетов: увеличивать при каждом обновлении PNG-спрайтов, чтобы
// браузер (в т.ч. кэш GitHub Pages и мобильный Chrome) не показывал старые
// картинки из кэша по тому же URL.
const ASSET_VERSION = 15;

const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');

function resize() {
  canvas.width = window.innerWidth;
  canvas.height = window.innerHeight;
}
window.addEventListener('resize', resize);
resize();


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
    x: (gx - gy) * (TILE_W / 2) - Math.round(camera.x) + canvas.width / 2,
    y: (gx + gy) * (TILE_H / 2) - Math.round(camera.y) + canvas.height / 2
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
// Размер дерева на экране при масштабе 1 (около 5–6 ростов человека).
const TREE_DRAW_W = 165;
const TREE_DRAW_H = 225;
const TREE_BASE_FRAC = 0.95;
const treeSprites = TREE_FILES.map((file) => {
  const img = new Image();
  img.src = `assets/trees/${file}?v=${ASSET_VERSION}`;
  return img;
});
// Сломанные ветром версии тех же пород (обломанный ствол с рваным изломом),
// нарезаны в той же сетке 360x500 с тем же основанием ствола. У сухостоя (4)
// сломанной версии нет — он и так мёртвый.
const BROKEN_TREE_CHANCE = 0.03;
const brokenTreeSprites = TREE_FILES.map((file, i) => {
  if (i === 4) return null;
  const img = new Image();
  img.src = `assets/trees/broken/${file}?v=${ASSET_VERSION}`;
  return img;
});
function isBrokenRoll(type, r) {
  return type !== 4 && r < BROKEN_TREE_CHANCE;
}

// Земля: настоящие бесшовные фототекстуры (Poly Haven, CC0), но НЕ нарезаны
// по одной картинке на клетку — так в изометрической ромбовидной сетке
// всегда виден шов (у каждого ромба 4 соседа по диагоналям, а не 4 ровных
// стороны). Вместо этого текстура рисуется как canvas-паттерн, растянутый
// матрицей той же изометрической проекции, что и toScreen() — получается
// один и тот же бесконечно повторяющийся кусок текстуры под всей картой,
// поэтому шва нет в принципе: соседние клетки — окна в одну и ту же плоскость.
// 0 трава, 1 светлая, 2 тропа, 3 тёмная, 4 пепел.
const GROUND_TEXTURE_FILES = ['grass.jpg', 'light.jpg', 'path.jpg', 'dark.jpg', 'ash.jpg'];
const groundImages = GROUND_TEXTURE_FILES.map((file) => {
  const img = new Image();
  img.src = `assets/ground/${file}?v=${ASSET_VERSION}`;
  return img;
});

// Лесной мусор: сломанные стволы, пни, камни.
// w/h — базовый размер отрисовки, anchor — какая доля высоты картинки выше точки (x,y).
// Размеры — в пикселях при масштабе 1, в пропорции к дереву (~225px) и
// будущему человеку (~40px): пень ниже колена, сломанный ствол в пару
// ростов человека и заметно ниже живого дерева. Задаётся либо высота
// (стоячие объекты), либо ширина (лежачие) — вторая сторона берётся из
// пропорций картинки. Картинки обрезаны по краю объекта, поэтому нижняя
// кромка картинки = точка касания земли.
// tilt — максимальный случайный наклон (рад), scale — разброс размера.
const CLUTTER_TYPES = {
  broken_trunk: { files: ['broken_trunk.png', 'broken_trunk_b.png', 'broken_trunk_c.png'], h: 92, tilt: 0.14, scale: [0.7, 1.1] },
  stump:        { files: ['stump.png'], h: 50, scale: [0.8, 1.15] },
  rocks:        { files: ['rocks.png'], w: 76, scale: [0.75, 1.2] }
};
const clutterSprites = {};
for (const kind in CLUTTER_TYPES) {
  clutterSprites[kind] = CLUTTER_TYPES[kind].files.map((file) => {
    const img = new Image();
    img.src = `assets/clutter/${file}?v=${ASSET_VERSION}`;
    return img;
  });
}

// 2. РЕАЛИСТИЧНАЯ ЭКОЛОГИЧЕСКАЯ ГЕНЕРАЦИЯ (Многоярусность и дистанции)
// В реальном лесу есть:
// - Верхний ярус (Великаны: Сосны, Дубы, Кедры, Лиственницы) — растут просторно (дистанция 3.5 - 6 клеток).
// - Средний ярус (Березы, Осины, Липы, Рябины) — группируются между великанами.
// - Подлесок (Молодые деревца 12, Папоротники 13) — растут пятнами у подножия.
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

  // Тип земли больше не хранится по клеткам — земля рисуется плавными
  // масками прямо по пикселям (см. drawGround). По клеткам нужно только
  // знать, где тропа, чтобы не ставить на неё деревья и мусор.
  for (let x = 0; x < CHUNK_SIZE; x++) {
    chunk.tiles[x] = [];
    for (let y = 0; y < CHUNK_SIZE; y++) {
      const wx = startX + x;
      const wy = startY + y;
      chunk.tiles[x][y] = { isPath: pathDistAt(wx, wy) < 1.2 };
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
        scale: 1.0 + pseudoRand(seed++) * 0.12,
        broken: isBrokenRoll(type, pseudoRand(seed++)),
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
        chunk.trees.push({
          x: sx, y: sy, type: subType,
          scale: 0.88 + pseudoRand(seed++) * 0.1,
          broken: isBrokenRoll(subType, pseudoRand(seed++))
        });
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
      chunk.trees.push({ x: dx, y: dy, type: 4, scale: 0.95 + pseudoRand(seed++) * 0.1, isGiant: true });
    }
  }

  // 3. ЛЕСНОЙ МУСОР: то, что обычно встречается под ногами в реальном лесу —
  // сломанные стволы, пни, валуны. Редко и не на тропе.
  const CLUTTER_KINDS = ['rocks', 'stump', 'broken_trunk'];
  const CLUTTER_WEIGHTS = [0.5, 0.3, 0.2];
  for (let x = 0; x < CHUNK_SIZE; x++) {
    for (let y = 0; y < CHUNK_SIZE; y++) {
      if (chunk.tiles[x][y].isPath) continue; // Не на тропе
      if (pseudoRand(seed++) > 0.05) continue; // ~5% клеток

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

      const def = CLUTTER_TYPES[kind];
      chunk.clutter.push({
        x: wx, y: wy, kind,
        variant: Math.floor(pseudoRand(seed++) * def.files.length),
        scale: def.scale[0] + pseudoRand(seed++) * (def.scale[1] - def.scale[0]),
        flip: pseudoRand(seed++) > 0.5,
        tilt: (pseudoRand(seed++) - 0.5) * 2 * (def.tilt || 0)
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

  // Панель обновляем только когда значения меняются — запись в DOM
  // каждый кадр на телефоне тоже стоит заметно.
  const curEco = getEcosystemAt(pChunkX, pChunkY);
  let totalTrees = 0;
  loadedChunks.forEach(c => {
    totalTrees += c.trees.length;
  });
  setInfo('info-biome', curEco.name);
  setInfo('info-coords', `X: ${Math.round(player.x)}, Y: ${Math.round(player.y)}`);
  setInfo('info-trees', String(totalTrees));
}

const infoCache = {};
function setInfo(id, text) {
  if (infoCache[id] === text) return;
  infoCache[id] = text;
  document.getElementById(id).textContent = text;
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
  // Камера и земля, и объекты сдвигаются на одно и то же целое число
  // пикселей (см. toScreen/drawGround): раньше земля округлялась, а деревья
  // нет — пока камера «доплывала» к игроку после остановки, объекты на пол-
  // пикселя ездили относительно земли и всё будто тряслось. Плюс хвост
  // плавного догона обрезается, чтобы камера не ползла ещё пару секунд.
  camera.x += (targetCamX - camera.x) * 0.12;
  camera.y += (targetCamY - camera.y) * 0.12;
  if (Math.abs(targetCamX - camera.x) < 0.5) camera.x = targetCamX;
  if (Math.abs(targetCamY - camera.y) < 0.5) camera.y = targetCamY;

  updateWorldChunks();
}

// 5. ОТРИСОВКА
// Земля каждого чанка «запекается» в картинку один раз (код — src/ground.js)
// и потом просто рисуется drawImage. Запекание идёт в фоновом потоке
// (src/ground-worker.js): на телефоне один чанк готовится до ~0.2 с, и в
// основном потоке это было заметным рывком при переходе в новый участок.
// Если браузер не умеет OffscreenCanvas в потоке — запекаем по одному чанку
// за кадр прямо в игре, как раньше.
const GROUND_BASE_COLOR = '#5a6a3a';
const GROUND_BAKE_KEEP_RADIUS = 3;
const GROUND_MAX_IN_FLIGHT = 2;

function groundTexturesReady() {
  return groundImages.every((img) => img.complete && img.naturalWidth);
}

const groundBake = { started: false, worker: null, ready: false, inFlight: new Set(), local: null };

function startGroundBaking() {
  groundBake.started = true;
  if (window.Worker && window.OffscreenCanvas && window.createImageBitmap) {
    try {
      const w = new Worker(`src/ground-worker.js?v=${ASSET_VERSION}`);
      w.onmessage = (e) => {
        const { key, bitmap } = e.data;
        groundBake.inFlight.delete(key);
        const chunk = loadedChunks.get(key);
        if (!chunk || chunk.ground) { bitmap.close(); return; }
        chunk.ground = bitmap;
        chunk.groundOrigin = chunkPixelOrigin(chunk.cx, chunk.cy);
      };
      w.onerror = () => { groundBake.worker = null; groundBake.ready = false; groundBake.inFlight.clear(); };
      groundBake.worker = w;
      Promise.all(groundImages.map((img) => createImageBitmap(img))).then((textures) => {
        w.postMessage({ type: 'init', textures }, textures);
        groundBake.ready = true;
      }).catch(() => { groundBake.worker = null; });
      return;
    } catch (e) {
      groundBake.worker = null;
    }
  }
}

function localBake(chunk) {
  if (!groundBake.local) {
    groundBake.local = createGroundBaker((w, h) => {
      const c = document.createElement('canvas');
      c.width = w;
      c.height = h;
      return c;
    }, groundImages);
  }
  chunk.ground = groundBake.local(chunk.cx, chunk.cy);
  chunk.groundOrigin = chunkPixelOrigin(chunk.cx, chunk.cy);
}

function drawGround() {
  const W = canvas.width, H = canvas.height;
  const camX = Math.round(camera.x) - W / 2;
  const camY = Math.round(camera.y) - H / 2;
  const pcx = Math.floor(player.x / CHUNK_SIZE);
  const pcy = Math.floor(player.y / CHUNK_SIZE);

  ctx.fillStyle = GROUND_BASE_COLOR;
  ctx.fillRect(0, 0, W, H);

  if (groundTexturesReady()) {
    if (!groundBake.started) startGroundBaking();
    const pending = [];
    for (const [key, chunk] of loadedChunks.entries()) {
      const d = Math.max(Math.abs(chunk.cx - pcx), Math.abs(chunk.cy - pcy));
      if (d > GROUND_BAKE_KEEP_RADIUS) {
        if (chunk.ground && chunk.ground.close) chunk.ground.close();
        chunk.ground = null;
        continue;
      }
      if (!chunk.ground && !groundBake.inFlight.has(key)) pending.push([d, key, chunk]);
    }
    pending.sort((p, q) => p[0] - q[0]);
    if (groundBake.worker) {
      if (groundBake.ready) {
        for (const [, key, chunk] of pending) {
          if (groundBake.inFlight.size >= GROUND_MAX_IN_FLIGHT) break;
          groundBake.inFlight.add(key);
          groundBake.worker.postMessage({ type: 'bake', key, cx: chunk.cx, cy: chunk.cy });
        }
      }
    } else if (pending.length) {
      localBake(pending[0][2]);
    }
  }

  for (const chunk of loadedChunks.values()) {
    if (!chunk.ground) continue;
    const x = chunk.groundOrigin.x - camX;
    const y = chunk.groundOrigin.y - camY;
    if (x > W || y > H || x + chunk.ground.width < 0 || y + chunk.ground.height < 0) continue;
    ctx.drawImage(chunk.ground, x, y);
  }
}

function render() {
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  const renderQueue = [];
  drawGround();

  for (const [, chunk] of loadedChunks.entries()) {
    // Лесной мусор (пни, сломанные стволы, камни)
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
      const sprite = clutterSprites[obj.kind][obj.variant || 0];
      if (!sprite.complete || !sprite.naturalWidth) return;
      const scale = obj.scale || 1.0;
      const ratio = sprite.naturalHeight / sprite.naturalWidth;
      const dw = def.h ? (def.h * scale) / ratio : def.w * scale;
      const dh = dw * ratio;

      // Рисуем относительно точки касания земли (низ картинки): поворот
      // (наклон сломанного ствола) и отражение идут вокруг неё, так что
      // объект не отрывается от земли.
      ctx.save();
      ctx.translate(pos.x, pos.y);
      if (obj.tilt) ctx.rotate(obj.tilt);
      if (obj.flip) ctx.scale(-1, 1);
      ctx.drawImage(sprite, -dw / 2, -dh, dw, dh);
      ctx.restore();

    } else {
      const obj = item.obj;
      const pos = toScreen(obj.x, obj.y);
      const scale = obj.scale || 1.0;
      const dw = TREE_DRAW_W * scale;
      const dh = TREE_DRAW_H * scale;
      if (pos.x < -dw || pos.x > canvas.width + dw || pos.y < -20 || pos.y - dh > canvas.height) return;

      const sprite = obj.broken ? brokenTreeSprites[obj.type] : treeSprites[obj.type];
      const shadow = obj.broken ? 0.45 : 1; // без кроны тень маленькая

      // Тень — вокруг основания ствола, чуть вправо-вниз (свет сверху-слева).
      ctx.beginPath();
      ctx.ellipse(pos.x + 6 * scale * shadow, pos.y + 2, 34 * scale * shadow, 13 * scale * shadow, 0, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(0, 0, 0, 0.32)';
      ctx.fill();

      // В картинке дерева основание ствола стоит ровно по центру на 95% высоты
      // (так нарезаны assets/trees) — ставим эту точку в точку дерева на карте.
      if (sprite.complete) {
        ctx.drawImage(sprite, pos.x - dw / 2, pos.y - dh * TREE_BASE_FRAC, dw, dh);
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

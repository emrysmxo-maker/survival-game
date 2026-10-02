// Генерация мира: 5 логичных связанных экосистем на площади 1.12 км² (±360 тайлов).
//
// 12 пород деревьев распределены по их естественным местам обитания:
// 1. 🎖️ Северный Скалистый Бор (y < -70): Кедры (9), Лиственницы (10), Сосны (0), Голубые ели (5)
// 2. 🌲 Центральная Лесная Заимка (y: -70..+30): Сосны (0), Берёзы (2), Липы (11), Рябины (8), Осины (7)
// 3. 🌊 Долина Реки Быстрянки (вдоль реки): Плакучие ивы (6), Клёны (3), Осины (7), Липы (11)
// 4. 🌫️ Гиблые Мшистые Топи (x < -60, y: 30..220): Чахлые берёзы (2), Болотные сосны (0), Сухостой (4)
// 5. 🌾 Заброшенный Дубовый Хутор (y > 110, x > -70): Вековые дубы (1), Клёны (3), Липы (11), Рябины (8)

function pseudoRand(s) {
  const x = Math.sin(s) * 10000;
  return x - Math.floor(x);
}

const loadedChunks = new Map();

function getEcosystemAt(cx, cy) {
  const wx = cx * CHUNK_SIZE, wy = cy * CHUNK_SIZE;
  if (wy < -70) {
    return {
      name: '🎖️ Северный Скалистый Бор',
      canopy: [9, 10, 0, 5],      // Кедр, Лиственница, Сосна, Голубая ель
      subcanopy: [8, 2, 4, 7]      // Рябина, Береза, Сухостой, Осина
    };
  }
  if (wy > 110 && wx > -70) {
    return {
      name: '🌾 Заброшенный Дубовый Хутор',
      canopy: [1, 3, 11, 8],      // Дуб, Клен, Липа, Рябина
      subcanopy: [8, 2, 6, 7]      // Рябина, Береза, Ива, Осина
    };
  }
  // Долина реки
  const ry = 62.0 + 18.0 * Math.sin(wx * 0.018 + 0.4) + 6.0 * Math.sin(wx * 0.045);
  if (Math.abs(wy - ry) < 26) {
    return {
      name: '🌊 Долина Реки Быстрянки',
      canopy: [6, 3, 7, 11],      // Ива, Клен, Осина, Липа
      subcanopy: [6, 2, 11]        // Ива, Береза, Липа
    };
  }
  if (wx < -60 && wy >= 30 && wy <= 220) {
    return {
      name: '🌫️ Гиблые Мшистые Топи',
      canopy: [2, 0, 4],          // Береза, Болотная сосна, Сухостой
      subcanopy: [2, 4, 7]         // Береза, Сухостой, Осина
    };
  }
  return {
    name: '🌲 Центральная Лесная Заимка',
    canopy: [0, 2, 11, 8],        // Сосна, Береза, Липа, Рябина
    subcanopy: [2, 7, 3, 8]        // Береза, Осина, Клен, Рябина
  };
}

// Проверка места для дерева: не в воде, не на дне оврага, не на дороге, не на поляне застройки
const _tp = {};
function treeSpot(wx, wy, r) {
  const t = terrainAt(wx, wy, _tp);
  if (t.water > 0.05 || t.ravine > 0.8) return null;
  if (t.path > 0.35) return null;      // дороги и тропы чистые
  if (t.clearing > 0.35) return null;  // поляны под будущие дома чистые
  if (t.swamp > 0.5 && r > 0.45) return null;
  if (t.rocky > 0.65 && r > 0.6) return null;
  return t;
}

const SWAMP_TREES = [2, 0, 4];

function inWorldMap(x, y, m) {
  const r = (typeof MAP_RADIUS !== 'undefined') ? MAP_RADIUS : 360;
  return Math.abs(x) < r - (m || 0) && Math.abs(y) < r - (m || 0);
}

function isBrokenRoll(type, roll) {
  if (typeof BROKEN_TREE_CHANCE === 'number' && roll < BROKEN_TREE_CHANCE) return true;
  return false;
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
    clutter: [],
    rocks: []
  };

  const startX = cx * CHUNK_SIZE;
  const startY = cy * CHUNK_SIZE;
  let seed = Math.abs(cx * 73856093 ^ cy * 19349663);

  // 1. ВЕРХНИЙ ЯРУС (Великаны)
  const giantCount = 2 + Math.floor(pseudoRand(seed++) * 3);
  for (let g = 0; g < giantCount; g++) {
    const gx = startX + 1.5 + pseudoRand(seed++) * (CHUNK_SIZE - 3);
    const gy = startY + 1.5 + pseudoRand(seed++) * (CHUNK_SIZE - 3);
    if (!inWorldMap(gx, gy, 1)) continue;

    let tooClose = false;
    for (const t of chunk.trees) {
      if (Math.hypot(t.x - gx, t.y - gy) < 3.2) { tooClose = true; break; }
    }

    const spot = treeSpot(gx, gy, pseudoRand(seed++));
    if (!tooClose && spot) {
      const pool = spot.swamp > 0.5 ? SWAMP_TREES : eco.canopy;
      const type = pool[Math.floor(pseudoRand(seed++) * pool.length)];
      chunk.trees.push({
        x: gx, y: gy,
        type: type,
        scale: 1.0 + pseudoRand(seed++) * 0.12,
        broken: isBrokenRoll(type, pseudoRand(seed++)),
        isGiant: true
      });

      // 2. СРЕДНИЙ ЯРУС ВОКРУГ ВЕЛИКАНА
      const satelliteCount = 1 + Math.floor(pseudoRand(seed++) * 3);
      for (let sIdx = 0; sIdx < satelliteCount; sIdx++) {
        const ang = pseudoRand(seed++) * Math.PI * 2;
        const dist = 1.8 + pseudoRand(seed++) * 1.6;
        const sx = gx + Math.cos(ang) * dist;
        const sy = gy + Math.sin(ang) * dist;
        if (!inWorldMap(sx, sy, 1)) continue;
        const sSpot = treeSpot(sx, sy, pseudoRand(seed++));
        if (!sSpot) continue;
        const sPool = sSpot.swamp > 0.5 ? SWAMP_TREES : eco.subcanopy;
        const subType = sPool[Math.floor(pseudoRand(seed++) * sPool.length)];
        chunk.trees.push({
          x: sx, y: sy, type: subType,
          scale: 0.88 + pseudoRand(seed++) * 0.1,
          broken: isBrokenRoll(subType, pseudoRand(seed++))
        });
      }
    }
  }

  // Редкий сухостой
  if (pseudoRand(seed++) < 0.22) {
    const dx = startX + 1.5 + pseudoRand(seed++) * (CHUNK_SIZE - 3);
    const dy = startY + 1.5 + pseudoRand(seed++) * (CHUNK_SIZE - 3);
    if (inWorldMap(dx, dy, 1)) {
      const spot = treeSpot(dx, dy, pseudoRand(seed++));
      if (spot) {
        let tooClose = false;
        for (const t of chunk.trees) {
          if (Math.hypot(t.x - dx, t.y - dy) < 3.0) { tooClose = true; break; }
        }
        if (!tooClose) {
          chunk.trees.push({ x: dx, y: dy, type: 4, scale: 0.95 + pseudoRand(seed++) * 0.1, isGiant: true });
        }
      }
    }
  }

  // Валуны на каменистых участках
  const rockRoll = pseudoRand(seed++);
  if (rockRoll < 0.35 && typeof ROCK_TYPES !== 'undefined') {
    const rx = startX + 2 + pseudoRand(seed++) * (CHUNK_SIZE - 4);
    const ry = startY + 2 + pseudoRand(seed++) * (CHUNK_SIZE - 4);
    const t = terrainAt(rx, ry, _tp);
    if (t.rocky > 0.3 && t.water < 0.05 && t.path < 0.35 && inWorldMap(rx, ry, 1)) {
      chunk.rocks.push({
        x: rx, y: ry,
        type: Math.floor(pseudoRand(seed++) * ROCK_TYPES.length),
        scale: 0.85 + pseudoRand(seed++) * 0.3,
        flip: pseudoRand(seed++) > 0.5
      });
    }
  }

  if (typeof generateCover === 'function') {
    generateCover(chunk, startX, startY, seed + 7777);
  }

  loadedChunks.set(key, chunk);
  return chunk;
}

const infoCache = {};
function setInfo(id, text) {
  if (infoCache[id] === text) return;
  infoCache[id] = text;
  const el = document.getElementById(id);
  if (el) el.textContent = text;
}

function updateWorldChunks() {
  const pChunkX = Math.floor(player.x / CHUNK_SIZE);
  const pChunkY = Math.floor(player.y / CHUNK_SIZE);

  const R = (typeof CHUNK_RADIUS !== 'undefined') ? CHUNK_RADIUS : 2;
  for (let dx = -R; dx <= R; dx++) {
    for (let dy = -R; dy <= R; dy++) {
      generateChunk(pChunkX + dx, pChunkY + dy);
    }
  }

  for (const [key, chunk] of loadedChunks.entries()) {
    if (Math.abs(chunk.cx - pChunkX) > 4 || Math.abs(chunk.cy - pChunkY) > 4) {
      loadedChunks.delete(key);
    }
  }

  const curEco = getEcosystemAt(pChunkX, pChunkY);
  let totalTrees = 0;
  loadedChunks.forEach(c => {
    totalTrees += c.trees.length;
  });
  setInfo('info-biome', curEco.name);
  setInfo('info-coords', `X: ${Math.round(player.x)}, Y: ${Math.round(player.y)}`);
  setInfo('info-trees', String(totalTrees));
}

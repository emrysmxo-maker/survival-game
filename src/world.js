// Генерация мира: биомы, чанки, деревья и лесной мусор.
//
// Реалистичная экологическая генерация (многоярусность и дистанции) —
// в реальном лесу есть:
// - Верхний ярус (Великаны: Сосны, Дубы, Кедры, Лиственницы) — растут
//   просторно (дистанция 3.5 - 6 клеток).
// - Средний ярус (Березы, Осины, Липы, Рябины) — группируются между
//   великанами.
// - Лесной мусор — то, что встречается под ногами: сломанные стволы,
//   пни, валуны. Редко и не на тропе.

function pseudoRand(s) {
  const x = Math.sin(s) * 10000;
  return x - Math.floor(x);
}

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

// Можно ли тут стоять дереву (рельеф): не в воде и не на дне оврага,
// не на поляне; в болоте — реже. Возвращает null (нельзя) или признаки места.
const _tp = {};
function treeSpot(wx, wy, r) {
  const t = terrainAt(wx, wy, _tp);
  if (t.water > 0.05 || t.ravine > 0.8) return null;
  if (t.clearing > 0.45) return null;
  if (t.swamp > 0.5 && r > 0.45) return null;
  if (t.rocky > 0.6 && r > 0.6) return null;
  return t;
}
// В болоте растут в основном берёзы и чахлые сосны.
const SWAMP_TREES = [2, 2, 0, 7];

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

  // Тип земли больше не хранится по клеткам — земля рисуется плавными
  // масками прямо по пикселям (см. render.js/drawGround). По клеткам нужно
  // только знать, где тропа, чтобы не ставить на неё деревья и мусор.
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

      // 2. СРЕДНИЙ ЯРУС ВОКРУГ ВЕЛИКАНА (Кластеры в радиусе 1.8 - 2.8)
      const satelliteCount = 1 + Math.floor(pseudoRand(seed++) * 3);
      for (let sIdx = 0; sIdx < satelliteCount; sIdx++) {
        const ang = pseudoRand(seed++) * Math.PI * 2;
        const dist = 1.8 + pseudoRand(seed++) * 1.6;
        const sx = gx + Math.cos(ang) * dist;
        const sy = gy + Math.sin(ang) * dist;
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
    if (!onPath && !tooClose && treeSpot(dx, dy, 0)) {
      chunk.trees.push({ x: dx, y: dy, type: 4, scale: 0.95 + pseudoRand(seed++) * 0.1, isGiant: true });
    }
  }

  // 3. ЛЕСНОЙ МУСОР: сломанные стволы под ногами. Редко и не на тропе.
  const CLUTTER_KINDS = ['broken_trunk'];
  const CLUTTER_WEIGHTS = [1];
  for (let x = 0; x < CHUNK_SIZE; x++) {
    for (let y = 0; y < CHUNK_SIZE; y++) {
      if (chunk.tiles[x][y].isPath) continue; // Не на тропе
      if (pseudoRand(seed++) > CLUTTER_CHANCE) continue; // доля клеток (часть отсеется у деревьев)

      const wx = startX + x + 0.5 + (pseudoRand(seed++) - 0.5) * 0.7;
      const wy = startY + y + 0.5 + (pseudoRand(seed++) - 0.5) * 0.7;

      // Не у края чанка — туда могут дотягиваться деревья соседнего чанка,
      // которых отсюда не видно.
      if (x < 2 || y < 2 || x >= CHUNK_SIZE - 2 || y >= CHUNK_SIZE - 2) continue;

      // Держимся подальше от ВСЕХ деревьев (и крупных, и подлеска): иначе
      // сломанный ствол с наклоном вставал вплотную и будто лежал на
      // соседнем дереве.
      let tooCloseToTree = false;
      for (const t of chunk.trees) {
        if (Math.hypot(t.x - wx, t.y - wy) < 2.0) { tooCloseToTree = true; break; }
      }
      if (tooCloseToTree) continue;

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

  // 4. ВАЛУНЫ: на каменистых местах часто, в остальном лесу — изредка;
  // не в воде, не на тропе, не вплотную к деревьям.
  const rockTries = 6;
  for (let r = 0; r < rockTries; r++) {
    const rx = startX + 1 + pseudoRand(seed++) * (CHUNK_SIZE - 2);
    const ry = startY + 1 + pseudoRand(seed++) * (CHUNK_SIZE - 2);
    const t = terrainAt(rx, ry, _tp);
    const chance = t.rocky > 0.4 ? 0.55 : 0.04;
    if (pseudoRand(seed++) > chance) continue;
    if (t.water > 0.05 || t.swamp > 0.4 || pathDistAt(rx, ry) < 1.6) continue;
    if (chunk.trees.some((tr) => Math.hypot(tr.x - rx, tr.y - ry) < 1.6)) continue;
    if (chunk.rocks.some((o) => Math.hypot(o.x - rx, o.y - ry) < 1.8)) continue;
    chunk.rocks.push({
      x: rx, y: ry,
      type: Math.floor(pseudoRand(seed++) * ROCK_TYPES.length),
      scale: 0.75 + pseudoRand(seed++) * 0.5,
      flip: pseudoRand(seed++) > 0.5
    });
  }

  loadedChunks.set(key, chunk);
  return chunk;
}

// Панель с биомом/координатами обновляем только когда значения меняются —
// запись в DOM каждый кадр на телефоне тоже стоит заметно.
const infoCache = {};
function setInfo(id, text) {
  if (infoCache[id] === text) return;
  infoCache[id] = text;
  document.getElementById(id).textContent = text;
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
  let totalTrees = 0;
  loadedChunks.forEach(c => {
    totalTrees += c.trees.length;
  });
  setInfo('info-biome', curEco.name);
  setInfo('info-coords', `X: ${Math.round(player.x)}, Y: ${Math.round(player.y)}`);
  setInfo('info-trees', String(totalTrees));
}

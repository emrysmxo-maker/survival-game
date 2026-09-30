// Подлесок и тени: трава, папоротники, крапива, кусты, молодые ёлочки,
// ветки, упавшие стволы, корни (рендеры 3D-моделей Poly Haven, CC0, под угол
// камеры, с тенью в самой картинке); тени деревьев на земле; мягкая тень
// под ногами бойца и зомби. Размеры и точки земли — SPRITE_DATA
// (src/sprites-data.js, собирает tools/treegen/export_sprites.py).

// Солнце светит слева (чуть сзади): все тени — вправо. Так же отрендерены
// тени в картинках подлеска, камней и деревьев.
const TREE_SHADOW_ALPHA = 0.34;

const spriteImages = {};
function spriteImage(key, group) {
  const id = group + ':' + key;
  if (!spriteImages[id]) {
    const d = SPRITE_DATA[group][key];
    const img = new Image();
    img.src = `${d.file}?v=${ASSET_VERSION}`;
    spriteImages[id] = img;
  }
  return spriteImages[id];
}

// Виды подлеска: какие картинки, где растёт, лежит ли плоско (рисуется под
// всеми) или стоит (рисуется по глубине и качается от ветра).
const COVER_KINDS = {
  grass:   { keys: ['grass_0', 'grass_1', 'grass_2', 'grass_3'], flat: false, sway: 1.0 },
  fern:    { keys: ['fern_0', 'fern_1', 'fern_2', 'fern_3'], flat: false, sway: 0.6 },
  nettle:  { keys: ['nettle_0', 'nettle_1'], flat: false, sway: 0.8 },
  bush:    { keys: ['bush_0', 'bush_1', 'bush_2'], flat: false, sway: 0.7 },
  sapling: { keys: ['sapling_0', 'sapling_1', 'sapling_2', 'sapling_3', 'sapling_4', 'sapling_5'], flat: false, sway: 0.5 },
  branch:  { keys: ['branch_0', 'branch_1', 'branch_2'], flat: true },
  log:     { keys: ['log_0', 'log_1'], flat: true },
  roots:   { keys: ['roots_0', 'roots_1'], flat: true }
};

// Расстановка подлеска в чанке. Плотность зависит от местности: на
// полянах — трава и крапива, в лесу — папоротники, кусты, ёлочки, ветки;
// у больших деревьев — корни; в воде и на тропе ничего.
const _ct = {};
function generateCover(chunk, startX, startY, seedStart) {
  let seed = seedStart;
  const rnd = () => pseudoRand(seed++);
  const cover = [];
  const tries = 70;
  for (let i = 0; i < tries; i++) {
    const x = startX + rnd() * CHUNK_SIZE, y = startY + rnd() * CHUNK_SIZE;
    const t = terrainAt(x, y, _ct);
    if (t.water > 0.02 || pathDistAt(x, y) < 1.3) { rnd(); rnd(); continue; }
    const r = rnd();
    // вероятность каждого вида в этом месте
    const w = {
      grass: 0.30 + t.clearing * 1.2 + t.swamp * 0.5,
      fern: (0.32 + t.ravine * 0.5) * (1 - t.clearing) * (1 - t.rocky * 0.6),
      nettle: 0.06 + t.clearing * 0.25,
      bush: 0.10 * (1 - t.swamp),
      sapling: 0.07 * (1 - t.clearing * 0.5),
      branch: 0.12 * (1 - t.clearing),
      log: 0.018 * (1 - t.swamp)
    };
    let sum = 0;
    for (const k in w) sum += w[k];
    if (r > Math.min(0.9, sum * 0.62)) { rnd(); continue; }
    let pick = rnd() * sum, kind = 'grass';
    for (const k in w) { if (pick < w[k]) { kind = k; break; } pick -= w[k]; }
    if (kind !== 'grass' && kind !== 'fern' && chunk.trees.some((tr) => Math.hypot(tr.x - x, tr.y - y) < 0.9)) continue;
    const def = COVER_KINDS[kind];
    cover.push({ x, y, kind, key: def.keys[Math.floor(rnd() * def.keys.length)], flip: rnd() > 0.5, scale: 0.85 + rnd() * 0.3 });
  }
  // кромки склонов (берега оврагов, края котловин): гуще трава, папоротник
  // и корни, торчащие из обрыва — видно, где земля обрывается
  for (let i = 0; i < 60; i++) {
    const x = startX + rnd() * CHUNK_SIZE, y = startY + rnd() * CHUNK_SIZE;
    const r1 = rnd(), r2 = rnd(), r3 = rnd();
    const t = terrainAt(x, y, _ct);
    if (t.water > 0.02 || pathDistAt(x, y) < 1.3) continue;
    const h = t.h;
    const slope = Math.hypot(terrainAt(x + 0.5, y, _ct).h - h, terrainAt(x, y + 0.5, _ct).h - h) / 0.5;
    if (slope < 0.45 || r1 > Math.min(0.9, (slope - 0.45) * 1.6)) continue;
    const kind = r2 < 0.22 ? 'roots' : r2 < 0.62 ? 'grass' : 'fern';
    const def = COVER_KINDS[kind];
    cover.push({ x, y, kind, key: def.keys[Math.floor(r3 * def.keys.length)], flip: r3 > 0.5, scale: kind === 'roots' ? 0.7 + r1 * 0.3 : 0.8 + r1 * 0.35 });
  }
  // корни у основания больших деревьев
  for (const tr of chunk.trees) {
    if (!tr.isGiant || rnd() > 0.5) continue;
    const a = rnd() * Math.PI * 2;
    cover.push({ x: tr.x + Math.cos(a) * 0.25, y: tr.y + Math.sin(a) * 0.25, kind: 'roots', key: COVER_KINDS.roots.keys[Math.floor(rnd() * 2)], flip: rnd() > 0.5, scale: 0.9 });
  }
  chunk.cover = cover;
}

// Рисует спрайт по SPRITE_DATA: точка земли — в (x, y).
function drawDataSprite(c, group, key, x, y, scale, flip, skew, squash) {
  const d = SPRITE_DATA[group][key];
  const img = spriteImage(key, group);
  if (!img.complete || !img.naturalWidth) return;
  const w = d.w * scale, h = d.h * scale;
  c.save();
  c.translate(x, y);
  if (skew) c.transform(1, 0, skew, 1, 0, 0);       // наклон верхушки от ветра
  if (squash) c.scale(1, 1 - squash);               // примят сверху
  if (flip) c.scale(-1, 1);
  c.drawImage(img, -d.ax * scale, -d.ay * scale, w, h);
  c.restore();
}

function onScreen(p, m) {
  return p.x > -m && p.x < view.w + m && p.y > -m && p.y < view.h + m * 1.5;
}

// Слой на земле (под всем): плоский подлесок, тени деревьев, тени под ногами.
function drawGroundLayer(c) {
  coverFrame();
  for (const chunk of loadedChunks.values()) {
    for (const o of chunk.cover || []) {
      if (!COVER_KINDS[o.kind].flat) continue;
      const p = toScreen(o.x, o.y, heightOf(o));
      if (!onScreen(p, 120)) continue;
      drawDataSprite(c, 'cover', o.key, p.x, p.y, o.scale, o.flip);
    }
  }
  // тени деревьев
  c.save();
  c.globalAlpha = TREE_SHADOW_ALPHA;
  for (const chunk of loadedChunks.values()) {
    for (const t of chunk.trees) {
      const key = TREE_FILES[t.type].replace('.png', '');
      const d = SPRITE_DATA.treeShadow[key];
      if (!d) continue;
      const p = toScreen(t.x, t.y, heightOf(t));
      if (p.x + (d.w - d.ax) < -10 || p.x - d.ax > view.w + 10 || p.y + d.h < -10 || p.y - d.ay > view.h + 10) continue;
      drawDataSprite(c, 'treeShadow', key, p.x, p.y, t.scale || 1, false);
    }
  }
  c.restore();
  // мягкие тени под ногами (рисуются кодом — это только тень)
  footShadow(c, player.x, player.y, player.h, 1);
  if (typeof zombies !== 'undefined') {
    for (const z of zombies) footShadow(c, z.x, z.y, undefined, z.state === 'walk' ? 1 : 1.5);
  }
}

// Тень под ногами: тёмное пятно у ног + вытянутая вправо (от солнца).
function footShadow(c, x, y, h, k) {
  const p = toScreen(x, y, h);
  if (!onScreen(p, 60)) return;
  c.save();
  c.translate(p.x, p.y);
  let g = c.createRadialGradient(0, 0, 0, 0, 0, 16 * k);
  g.addColorStop(0, 'rgba(0,0,0,0.45)');
  g.addColorStop(1, 'rgba(0,0,0,0)');
  c.fillStyle = g;
  c.scale(1, 0.45);
  c.beginPath(); c.arc(0, 0, 16 * k, 0, Math.PI * 2); c.fill();
  c.restore();
  c.save();
  c.translate(p.x + 22 * k, p.y + 2);
  c.scale(2.3 * k, 0.5 * k);
  g = c.createRadialGradient(0, 0, 0, 0, 0, 12);
  g.addColorStop(0, 'rgba(0,0,0,0.22)');
  g.addColorStop(1, 'rgba(0,0,0,0)');
  c.fillStyle = g;
  c.beginPath(); c.arc(0, 0, 12, 0, Math.PI * 2); c.fill();
  c.restore();
}

// Стоящий подлесок (трава, папоротник, крапива, куст, ёлочка) — в общей
// очереди по глубине.
// • Издалека: одна картинка, качается от ветра (полоски сверху вниз, низ стоит).
// • Когда рядом боец или зомби: растение рисуется из 6 частей-секторов
//   (заранее разрезано в 3D, SPRITE_DATA.coverParts). Каждая часть — твёрдая:
//   она поворачивается вокруг корня, отклоняясь от идущего (своя пружина),
//   ничего не растягивается. Части позади ног рисуются до бойца, впереди — после.
const COVER_PUSH_R = { grass: 0.75, fern: 0.95, nettle: 0.8, bush: 1.0, sapling: 0.7 };
const COVER_PUSH_K = { grass: 1.0, fern: 0.8, nettle: 0.85, bush: 0.55, sapling: 0.3 };
const COVER_PART_SHADOW = 0.42;
const COVER_SLICES = 6;
let _frameT = 0, _frameDt = 0.016;
const _pacc = { s: 0, wx: 0, wy: 0 };

function coverFrame() {
  const t = performance.now() / 1000;
  _frameDt = Math.min(0.05, Math.max(0.001, t - _frameT));
  _frameT = t;
}

// Вклад одного идущего: вес (ближе — сильнее) и его положение на экране
// относительно корня растения.
function coverPush(o, e, R, acc) {
  const dx = e.x - o.x, dy = e.y - o.y;
  const d = Math.hypot(dx, dy);
  if (d >= R) return;
  const k = 1 - d / R;
  const w = k * k * (3 - 2 * k);
  acc.s += w;
  acc.wx += (dx - dy) * TILE_W / 2 * w;
  acc.wy += (dx + dy) * TILE_H / 2 * w;
}

// Целая картинка, качается от ветра: полоски сверху вниз, низ у земли стоит.
function drawWindSprite(c, o, x, y, tip) {
  const d = SPRITE_DATA.cover[o.key];
  const img = spriteImage(o.key, 'cover');
  if (!img.complete || !img.naturalWidth) return;
  const sc = o.scale, w = d.w * sc, h = d.h * sc, ay = d.ay * sc, ax = d.ax * sc;
  const nw = img.naturalWidth, nh = img.naturalHeight;
  const srcG = nh * (d.ay / d.h), band = srcG / COVER_SLICES, dstBand = ay / COVER_SLICES;
  const dpr = view.dpr || 1;
  c.save();
  c.translate(Math.round(x * dpr) / dpr, Math.round(y * dpr) / dpr);
  if (o.flip) c.scale(-1, 1);
  // границы полосок — по целым пикселям экрана и без перекрытия: иначе шов
  // либо светится, либо удваивает полупрозрачную тень из картинки
  let y0 = Math.round(-ay * dpr) / dpr;
  for (let i = 0; i < COVER_SLICES; i++) {
    const hn = 1 - (i + 0.5) / COVER_SLICES;
    const y1 = i === COVER_SLICES - 1 ? 0 : Math.round((-ay + (i + 1) * dstBand) * dpr) / dpr;
    if (y1 > y0) c.drawImage(img, 0, i * band, nw, band, -ax + tip * hn * hn, y0, w, y1 - y0);
    y0 = y1;
  }
  if (h > ay + 0.5) c.drawImage(img, 0, srcG, nw, nh - srcG, -ax, 0, w, h - ay);
  c.restore();
}

function partImage(file) {
  let img = spriteImages[file];
  if (!img) { img = new Image(); img.src = `${file}?v=${ASSET_VERSION}`; spriteImages[file] = img; }
  return img;
}

// Раз в кадр на растение: кто рядом, пружины частей.
function updateCoverPhysics(o) {
  if (o._frame === _frameT) return;
  o._frame = _frameT;
  const R = (COVER_PUSH_R[o.kind] || 0.7) * o.scale;
  const A = _pacc;
  A.s = A.wx = A.wy = 0;
  coverPush(o, player, R, A);
  if (typeof zombies !== 'undefined') for (const z of zombies) coverPush(o, z, R, A);
  const cp = SPRITE_DATA.coverParts && SPRITE_DATA.coverParts[o.key];
  if (!cp) { o._act = 0; return; }
  const infl = Math.min(1, A.s * 1.5);
  if (o._ang === undefined) { o._ang = new Float32Array(cp.parts.length); o._vel = new Float32Array(cp.parts.length); o._act = 0; o._wx = 0; o._wy = 0; }
  if (A.s > 0.001) {                                     // где идущий (в системе картинки)
    const wx = (A.wx / A.s) * (o.flip ? -1 : 1), wy = A.wy / A.s;
    if (o._act < 0.01) { o._wx = wx; o._wy = wy; }
    const f = Math.min(1, 20 * _frameDt);
    o._wx += (wx - o._wx) * f; o._wy += (wy - o._wy) * f;
  }
  const H = SPRITE_DATA.cover[o.key].ay * o.scale;
  const K = (COVER_PUSH_K[o.kind] || 0.6) * infl;
  let act = infl;
  for (let j = 0; j < cp.parts.length; j++) {
    const pt = cp.parts[j];
    const rx = pt.cx * o.scale, ry = pt.cy * o.scale;
    let target = 0;
    if (K > 0) {
      // часть уходит от идущего: сдвиг её центра вдоль (центр − идущий),
      // переведённый в поворот вокруг корня
      const axv = rx - o._wx, ayv = ry - o._wy;
      const dist = Math.hypot(axv, ayv) + 1;
      const m = K * H * 0.9 * Math.exp(-dist / (H * 1.2 + 10));
      target = m * (axv * -ry + ayv * rx) / dist / (rx * rx + ry * ry + 80);
      target = Math.max(-0.9, Math.min(0.9, target));
    }
    // пружина: быстро отклоняется, возвращаясь слегка покачивается
    o._vel[j] += ((target - o._ang[j]) * 140 - o._vel[j] * 12) * _frameDt;
    o._ang[j] += o._vel[j] * _frameDt;
    act = Math.max(act, Math.abs(o._ang[j]) * 20);
  }
  o._act = act;
}

function drawCoverItem(c, o, half) {
  const p = toScreen(o.x, o.y, heightOf(o));
  if (!onScreen(p, 120)) return;
  updateCoverPhysics(o);
  const def = COVER_KINDS[o.kind];
  const ph = o.x * 0.55 + o.y * 0.35;
  const cp = SPRITE_DATA.coverParts && SPRITE_DATA.coverParts[o.key];
  if (!cp || o._act < 0.02) {
    if (half) return;                                    // целая картинка — один раз
    const H = SPRITE_DATA.cover[o.key].ay * o.scale;
    const wind = def.sway * 0.07 * H * (Math.sin(_frameT * 2 * Math.PI * WIND_FREQ + ph) * 0.7 + Math.sin(_frameT * 3.1 + ph * 2.3) * 0.3);
    drawWindSprite(c, o, p.x, p.y, wind);
    return;
  }
  const dpr = view.dpr || 1;
  c.save();
  c.translate(Math.round(p.x * dpr) / dpr, Math.round(p.y * dpr) / dpr);
  if (o.flip) c.scale(-1, 1);
  const sc = o.scale;
  if (!half && cp.shadow) {
    const sh = cp.shadow, img = partImage(sh.file);
    if (img.complete && img.naturalWidth) {
      c.globalAlpha = COVER_PART_SHADOW;
      c.drawImage(img, -sh.ax * sc, -sh.ay * sc, sh.w * sc, sh.h * sc);
      c.globalAlpha = 1;
    }
  }
  for (let j = 0; j < cp.parts.length; j++) {
    const pt = cp.parts[j];
    const front = pt.cy * sc > o._wy;                    // часть ближе к камере, чем ноги
    if (front !== !!half) continue;
    const img = partImage(pt.file);
    if (!img.complete || !img.naturalWidth) continue;
    const wind = def.sway * 0.05 * Math.sin(_frameT * 2 * Math.PI * WIND_FREQ + ph + j * 1.3);
    c.save();
    c.rotate(o._ang[j] + wind);
    c.drawImage(img, -pt.ax * sc, -pt.ay * sc, pt.w * sc, pt.h * sc);
    c.restore();
  }
  c.restore();
}

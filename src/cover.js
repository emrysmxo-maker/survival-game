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
  // на склоне у дерева с нижней стороны оголяются корни (земля осыпалась)
  for (const tr of chunk.trees) {
    groundGrad(tr);
    const g = Math.hypot(tr._gx, tr._gy) / 1.39;           // уклон, м/м
    if (g < 0.3) continue;
    const ux = -tr._gx / (g * 1.39), uy = -tr._gy / (g * 1.39);  // вниз по склону
    const sx = (ux - uy);                                  // куда это на экране (знак x)
    cover.push({ x: tr.x + ux * 0.28, y: tr.y + uy * 0.28, kind: 'roots',
      key: COVER_KINDS.roots.keys[Math.floor(rnd() * 2)], flip: sx < 0,
      scale: Math.min(1.15, 0.7 + g * 0.6) * (tr.scale || 1) });
  }
  // корни у основания больших деревьев
  for (const tr of chunk.trees) {
    if (!tr.isGiant || rnd() > 0.5) continue;
    const a = rnd() * Math.PI * 2;
    cover.push({ x: tr.x + Math.cos(a) * 0.25, y: tr.y + Math.sin(a) * 0.25, kind: 'roots', key: COVER_KINDS.roots.keys[Math.floor(rnd() * 2)], flip: rnd() > 0.5, scale: 0.9 });
  }
  chunk.cover = cover;
}

// Наклон земли в точке (м на тайл по осям мира), кешируется в объекте.
function groundGrad(o) {
  if (o._gx === undefined) {
    o._gx = (terrainHeight(o.x + 0.5, o.y) - terrainHeight(o.x - 0.5, o.y));
    o._gy = (terrainHeight(o.x, o.y + 0.5) - terrainHeight(o.x, o.y - 0.5));
  }
  return o;
}
// Лежащий предмет (ветка, бревно, корни) «ложится» на склон: точка картинки,
// смещённая на (dx, dy) px от якоря, опускается/поднимается на высоту земли
// под ней. Для плоскости это аффинное преобразование y' = y + kx·dx + ky·dy.
function slopeTransform(c, o) {
  groundGrad(o);
  const kx = -RELIEF_PX_PER_M * (o._gx - o._gy) / TILE_W;
  const ky = -RELIEF_PX_PER_M * (o._gx + o._gy) / TILE_H;
  c.transform(1, kx, 0, Math.max(0.35, 1 + ky), 0, 0);
}

// Рисует спрайт по SPRITE_DATA: точка земли — в (x, y).
function drawDataSprite(c, group, key, x, y, scale, flip, skew, squash, lieOn) {
  const d = SPRITE_DATA[group][key];
  const img = spriteImage(key, group);
  if (!img.complete || !img.naturalWidth) return;
  const w = d.w * scale, h = d.h * scale;
  c.save();
  c.translate(x, y);
  if (lieOn) slopeTransform(c, lieOn);
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
      drawDataSprite(c, 'cover', o.key, p.x, p.y, o.scale, o.flip, 0, 0, o);
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
// • Издалека: одна картинка, качается от ветра (полоски сверху вниз).
// • Когда рядом боец или зомби: растение рассыпается на ~12 пучков листьев
//   (заранее разрезано в 3D, SPRITE_DATA.coverPieces, атлас на растение). У каждого
//   пучка своя точка корня, жёсткость и пружина: пучки, которых касается тело,
//   отгибаются от него и увлекаются по ходу движения, остальные почти стоят;
//   потом с разбросом по времени качаются и успокаиваются — как шелестит куст.
//   Пучки позади ног рисуются до бойца, впереди (ближе к камере) — после.
const COVER_PUSH_K = { grass: 1.0, fern: 0.9, nettle: 0.9, bush: 0.75, sapling: 0.3 };
const COVER_ACT_R = 1.3;              // радиус включения режима пучков, тайлов
const COVER_TOUCH_PX = 30;            // радиус касания тела, px экрана
const COVER_BODY_H = 44;              // высота тела над землёй, px экрана
const COVER_PART_SHADOW = 0.42;
const COVER_SLICES = 6;
let _frameT = 0, _frameDt = 0.016;

function coverFrame() {
  const t = performance.now() / 1000;
  _frameDt = Math.min(0.05, Math.max(0.001, t - _frameT));
  _frameT = t;
}

// Целая картинка, качается от ветра: полоски сверху вниз, низ у земли стоит.
function drawWindSprite(c, o, x, y, tip) {
  // Один вызов отрисовки на растение (раньше — 7 полосками: сотни вызовов за
  // кадр тормозили телефон). Качание от ветра — лёгкий наклон верха (shear):
  // размах всего несколько пикселей, растяжения не видно.
  const d = SPRITE_DATA.cover[o.key];
  const img = spriteImage(o.key, 'cover');
  if (!img.complete || !img.naturalWidth) return;
  const sc = o.scale, w = d.w * sc, h = d.h * sc, ay = d.ay * sc, ax = d.ax * sc;
  const dpr = view.dpr || 1;
  c.save();
  c.translate(Math.round(x * dpr) / dpr, Math.round(y * dpr) / dpr);
  if (o.flip) c.scale(-1, 1);
  if (tip) c.transform(1, 0, tip / Math.max(ay, 1), 1, 0, 0);
  c.drawImage(img, -ax, -ay, w, h);
  c.restore();
}

function partImage(file) {
  let img = spriteImages[file];
  if (!img) { img = new Image(); img.src = `${file}?v=${ASSET_VERSION}`; spriteImages[file] = img; }
  return img;
}

// Раз в кадр на растение: кто рядом, пружины пучков.
const _pushers = [];
function updateCoverPhysics(o) {
  if (o._frame === _frameT) return;
  o._frame = _frameT;
  const cp = SPRITE_DATA.coverPieces && SPRITE_DATA.coverPieces[o.key];
  if (!cp) { o._act = 0; return; }
  const P = cp.pieces, n = P.length;
  if (!cp._sorted) { P.sort((u, v) => u.pvy - v.pvy); cp._sorted = true; }     // дальние — первыми
  if (o._ang === undefined) {
    o._ang = new Float32Array(n); o._vel = new Float32Array(n);
    o._k = new Float32Array(n);                                        // жёсткость каждого пучка
    let sd = Math.floor((o.x * 7.3 + o.y * 3.1) * 1000) & 0xffff;
    for (let j = 0; j < n; j++) { sd = (sd * 1103515245 + 12345) & 0x7fffffff; o._k[j] = 0.75 + (sd % 1000) / 1000 * 0.6; }
    o._act = 0;
  }
  // кто рядом (положение ног относительно корня, px экрана, в системе картинки)
  const sc = o.scale, fl = o.flip ? -1 : 1;
  const R = COVER_ACT_R * sc;
  _pushers.length = 0;
  const add = (e, vx, vy) => {
    const dx = e.x - o.x, dy = e.y - o.y;
    if (Math.hypot(dx, dy) > R) return;
    _pushers.push({ x: (dx - dy) * TILE_W / 2 * fl, y: (dx + dy) * TILE_H / 2,
      vx: ((vx - vy) * TILE_W / 2) * fl, vy: (vx + vy) * TILE_H / 2 });
  };
  add(player, player.vx, player.vy);
  if (typeof zombies !== 'undefined') for (const z of zombies) add(z, z.vx || 0, z.vy || 0);
  const kind = (COVER_PUSH_K[o.kind] || 0.6);
  let act = _pushers.length ? 1 : 0;
  for (let j = 0; j < n; j++) {
    const pc = P[j];
    const pvx = pc.pvx * sc, pvy = pc.pvy * sc, cx = pc.cx * sc, cy = pc.cy * sc;
    const vx0 = cx - pvx, vy0 = cy - pvy;
    const len2 = vx0 * vx0 + vy0 * vy0 + 25;
    let target = 0;
    for (const q of _pushers) {
      // расстояние от центра пучка до тела (вертикальный отрезок от ног вверх)
      const t = Math.max(0, Math.min(1, (q.y - cy) / COVER_BODY_H));
      const bx = q.x, by = q.y - t * COVER_BODY_H;
      let ux = cx - bx, uy = (cy - by) * 1.3;
      const d = Math.hypot(ux, uy) + 0.01;
      const infl = Math.max(0, 1 - d / (COVER_TOUCH_PX * sc)); 
      if (infl <= 0) continue;
      const w = infl * infl * (3 - 2 * infl);
      ux /= d; uy /= d;
      // смещение центра пучка: от тела + вслед движению
      const sp = Math.hypot(q.vx, q.vy);
      const fx = sp > 1 ? q.vx / sp * Math.min(1, sp / 80) : 0, fy = sp > 1 ? q.vy / sp * Math.min(1, sp / 80) : 0;
      const Dx = (ux + fx * 0.6) * w * 15 * sc * kind, Dy = (uy + fy * 0.6) * w * 15 * sc * kind;
      target += (vx0 * Dy - vy0 * Dx) / len2;                       // поворот вокруг корня пучка
    }
    // длинный пучок: кончик уходит далеко и быстро даже при малом угле — поэтому
    // чем он длиннее, тем мягче пружина (медленнее), меньше предельный угол
    // (кончик смещается не больше ~16 px) и меньше предельная скорость кончика
    const L = Math.max(pc.h, pc.w) * sc + 1;
    const kL = Math.min(1, Math.pow(28 / L, 1.4));
    const maxA = Math.min(0.9, 16 * sc * kind / L);
    target = Math.max(-maxA, Math.min(maxA, target));
    const kk = o._k[j];
    // пружина: отклоняется не мгновенно, потом с разбросом покачивается
    o._vel[j] += ((target - o._ang[j]) * 24 * kk * kL - o._vel[j] * 5.2 * Math.sqrt(kL)) * _frameDt;
    const vmax = Math.min(2.2, 60 / L);                 // кончик не быстрее ~60 px/с
    o._vel[j] = Math.max(-vmax, Math.min(vmax, o._vel[j]));
    o._ang[j] += o._vel[j] * _frameDt;
    act = Math.max(act, Math.abs(o._ang[j]) * 30 + Math.abs(o._vel[j]) * 4);
  }
  o._act = act;
  o._wy = _pushers.length ? _pushers[0].y : 1e9;
}

function drawCoverItem(c, o, half) {
  const p = toScreen(o.x, o.y, heightOf(o));
  if (!onScreen(p, 120)) return;
  updateCoverPhysics(o);
  const def = COVER_KINDS[o.kind];
  const ph = o.x * 0.55 + o.y * 0.35;
  const cp = SPRITE_DATA.coverPieces && SPRITE_DATA.coverPieces[o.key];
  if (!cp || o._act < 0.05) {
    if (half) return;                                    // целая картинка — один раз
    const H = SPRITE_DATA.cover[o.key].ay * o.scale;
    const wind = def.sway * 0.07 * H * (Math.sin(_frameT * 2 * Math.PI * WIND_FREQ + ph) * 0.7 + Math.sin(_frameT * 3.1 + ph * 2.3) * 0.3);
    drawWindSprite(c, o, p.x, p.y, wind);
    return;
  }
  const atlas = partImage(cp.file);
  if (!atlas.complete || !atlas.naturalWidth) { if (!half) drawWindSprite(c, o, p.x, p.y, 0); return; }
  const dpr = view.dpr || 1, sc = o.scale;
  c.save();
  c.translate(Math.round(p.x * dpr) / dpr, Math.round(p.y * dpr) / dpr);
  if (o.flip) c.scale(-1, 1);
  if (!half && cp.shadow) {
    const sh = cp.shadow, img = partImage(sh.file);
    if (img.complete && img.naturalWidth) {
      c.globalAlpha = COVER_PART_SHADOW;
      c.drawImage(img, -sh.ax * sc, -sh.ay * sc, sh.w * sc, sh.h * sc);
      c.globalAlpha = 1;
    }
  }
  const P = cp.pieces;
  for (let j = 0; j < P.length; j++) {
    const pc = P[j];
    const front = pc.pvy * sc > o._wy;                   // корень пучка ближе к камере, чем ноги
    if (front !== !!half) continue;
    const wind = def.sway * 0.03 * Math.sin(_frameT * 2 * Math.PI * WIND_FREQ + ph + j * 1.7);
    c.save();
    c.translate(pc.pvx * sc, pc.pvy * sc);
    c.rotate(o._ang[j] + wind);
    c.drawImage(atlas, pc.sx, pc.sy, pc.sw, pc.sh, (-pc.ax - pc.pvx) * sc, (-pc.ay - pc.pvy) * sc, pc.w * sc, pc.h * sc);
    c.restore();
  }
  c.restore();
}

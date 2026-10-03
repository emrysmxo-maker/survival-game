// Общий код земли: используется и игрой (render.js), и фоновым потоком
// (ground-worker.js), который «запекает» землю чанков в фоновом потоке.
// v7.1: Полноценная карта 1.12 км² (±360 тайлов) с 5 связанными локациями.

const TILE_W = 64;
const TILE_H = 32;
const CHUNK_SIZE = 12;

const GROUND_TILES_PER_TEXTURE = 3.2; // сколько игровых клеток занимает одно повторение текстуры
const GROUND_BAKE_SCALE = 2.6;
const GROUND_LO_SCALE = 1.3;
const GROUND_LIGHT_SCALE = 0.35;
const GROUND_MARGIN_LO = 1100;
const GROUND_MARGIN_HI = 380;
const GROUND_MARGIN_HI_KEEP = 640;
const GROUND_TEX_PX = 512;
const GROUND_MASK_STEP = 8;
const GROUND_LAYER_ORDER = [1, 3, 4, 7, 5, 2, 6]; // светлая, тёмная, листья, камни, болото, тропа, дно ручья
const GROUND_BAKE_MARGIN = 2;
const CHUNK_PX_W = CHUNK_SIZE * TILE_W;
const CHUNK_PX_H = CHUNK_SIZE * TILE_H;
const GROUND_WARP_CELLS = 4;
const RELIEF_PX_PER_M = 32;
const RELIEF_MARGIN = 176;

// ---------------- Полноценный Лесной Мир (1-2 км², 5 связанных локаций) ----------------
const MAP_RADIUS = 360; // ±360 тайлов ≈ 1000м x 1000м (1.0 км² - 1.2 км²)
const TEST_MAP = false;  // переключено с временной тестовой коробки на полный открытый мир

// 5 ключевых локаций и площадок под постройки
const WORLD_FEATURES = {
  cabin:    { x: 0,    y: -6,   r: 10.0, name: 'Стартовая Заимка' },
  post:     { x: 42,   y: -190, r: 14.0, name: 'Военный Блокпост «Север»' },
  ford:     { x: 45,   y: 62,   r: 12.0, name: 'Переправа «Вороний Брод»' },
  ruins:    { x: 60,   y: 190,  r: 15.0, name: 'Заброшенный Кордон «Дубки»' },
  bunker:   { x: -175, y: 145,  r: 11.0, name: 'Секретный Бункер «Топи»' },
  crater:   { x: 75,   y: 165,  r: 8.0,  depth: 3.2, name: 'Воронка авиаудара' },
  pit:      { x: -25,  y: -45,  r: 6.5,  depth: 2.5, name: 'Лесная карстовая яма' }
};

// Извилистая река Быстрянка (протекает через весь мир с запада на восток в полосе Y: +40..+80)
function riverCenterY(wx) {
  return 62.0 + 18.0 * Math.sin(wx * 0.018 + 0.4) + 6.0 * Math.sin(wx * 0.045);
}

function riverDist(wx, wy) {
  const ry = riverCenterY(wx);
  const dy = wy - ry;
  const k = 18.0 * 0.018 * Math.cos(wx * 0.018 + 0.4) + 6.0 * 0.045 * Math.cos(wx * 0.045);
  return Math.abs(dy) / Math.sqrt(1 + k * k);
}

// Брод (переправа) возле X: 45, Y: 62: река становится мелкой и проходимой вброд
function fordFactor(wx, wy) {
  return smoothstep(18.0, 5.0, Math.hypot(wx - 45.0, wy - 62.0));
}

// Дорожная сеть: Главный тракт (Север-Юг), Болотная гать и Тропа на восточную гряду
function mainRoadX(wy) {
  return 20.0 + 32.0 * Math.sin(wy * 0.014 - 0.3) + 10.0 * Math.sin(wy * 0.038);
}

function pathDistAt(wx, wy) {
  // 1. Главный тракт (Северный блокпост -> Заимка -> Брод -> Хутор)
  const rx = mainRoadX(wy);
  const dx = wx - rx;
  const k = 32.0 * 0.014 * Math.cos(wy * 0.014 - 0.3) + 10.0 * 0.038 * Math.cos(wy * 0.038);
  let d = Math.abs(dx) / Math.sqrt(1 + k * k);

  // 2. Западная тропа на болото (от развилки у заимки к бункеру)
  if (wx <= 25 && wx >= -220 && wy >= 10 && wy <= 180) {
    const t = Math.max(0, Math.min(1, (18.0 - wx) / 195.0));
    const targetY = 18.0 + 127.0 * t + 14.0 * Math.sin(t * Math.PI * 2.0);
    const ds = Math.hypot(wx - (18.0 - t * 195.0), wy - targetY);
    if (ds < d) d = ds;
  }

  // 3. Восточная тропа на горную гряду
  if (wx >= 20 && wx <= 170 && wy >= -160 && wy <= -50) {
    const t = Math.max(0, Math.min(1, (wx - 28.0) / 112.0));
    const targetY = -60.0 - 60.0 * t + 10.0 * Math.sin(t * Math.PI);
    const dr = Math.hypot(wx - (28.0 + t * 112.0), wy - targetY);
    if (dr < d) d = dr;
  }

  return d;
}

// Органичные пятна светлой травы / тёмной земли
function soilNoise(wx, wy) {
  return (
    Math.sin(wx * 0.03 + wy * 0.017) +
    Math.sin(wx * 0.017 - wy * 0.035) * 1.3 +
    Math.sin(wx * 0.06 + wy * 0.045) * 0.5
  ) / 2.8;
}

function smoothstep(e0, e1, x) {
  const t = Math.min(1, Math.max(0, (x - e0) / (e1 - e0)));
  return t * t * (3 - 2 * t);
}

function radial(x, y, cx, cy, r) {
  const d = Math.hypot(x - cx, y - cy);
  return smoothstep(r, r * 0.25, d);
}

// Полный рельеф мира
function terrainAt(wx, wy, out) {
  const rd = riverDist(wx, wy);
  const ford = fordFactor(wx, wy);

  // Река и овраг русла
  const waterWidth = 1.25 * (1.0 - 0.75 * ford);
  const water = smoothstep(waterWidth, waterWidth * 0.6, rd) * (1.0 - 0.85 * ford);
  const ravine = smoothstep(8.5, 1.8, rd);

  // Болото на западе (впадина между X: -60 и -220, Y: +30 и +220)
  const swampArea = smoothstep(-60, -130, wx) * smoothstep(30, 80, wy) * smoothstep(240, 190, wy);
  const swamp = swampArea * (1.0 - ravine * 0.8);

  // Северная горная гряда (скалы, сосны, высота до +5..+6м)
  const northElev = smoothstep(-40, -180, wy) * (4.2 + 1.6 * Math.sin(wx * 0.035 + 1.2));
  // Южные холмы (дубравы, хутор, высота до +2.5..+3.5м)
  const southElev = smoothstep(90, 220, wy) * (2.2 + 1.0 * Math.sin(wx * 0.03 - wy * 0.02));

  // Локальные элементы:
  // 1. Воронка авиаудара на южном хуторе (x=75, y=165, глубина 3.2м)
  const crater = radial(wx, wy, WORLD_FEATURES.crater.x, WORLD_FEATURES.crater.y, WORLD_FEATURES.crater.r);
  // 2. Лесная карстовая яма (x=-25, y=-45, глубина 2.5м)
  const forestPit = radial(wx, wy, WORLD_FEATURES.pit.x, WORLD_FEATURES.pit.y, WORLD_FEATURES.pit.r);

  // Естественные микро-бугры почвы
  const bumps = 0.32 * Math.sin(wx * 0.28 + wy * 0.14) * Math.sin(wy * 0.25 - wx * 0.12) * (1.0 - ravine) * (1.0 - swamp);
  // Глубина оврага (у брода дно мелкое ~ -0.3м)
  const ravineDepth = 2.8 * (1.0 - 0.85 * ford);

  const h = northElev + southElev + bumps - ravine * ravineDepth - swamp * 1.2 - crater * WORLD_FEATURES.crater.depth - forestPit * WORLD_FEATURES.pit.depth;

  // Поляны под постройки (Заимка, Блокпост, Хутор, Бункер)
  const c_cabin = radial(wx, wy, WORLD_FEATURES.cabin.x, WORLD_FEATURES.cabin.y, WORLD_FEATURES.cabin.r);
  const c_post = radial(wx, wy, WORLD_FEATURES.post.x, WORLD_FEATURES.post.y, WORLD_FEATURES.post.r);
  const c_ruins = radial(wx, wy, WORLD_FEATURES.ruins.x, WORLD_FEATURES.ruins.y, WORLD_FEATURES.ruins.r);
  const c_bunker = radial(wx, wy, WORLD_FEATURES.bunker.x, WORLD_FEATURES.bunker.y, WORLD_FEATURES.bunker.r);
  const clearing = Math.max(c_cabin, c_post, c_ruins, c_bunker);

  // Скалистые осыпи на высоте и выброс породы у воронки
  const rocky = smoothstep(3.2, 5.2, northElev) * 0.85 + (crater > 0.1 ? smoothstep(0.2, 0.6, crater) * 0.7 : 0);

  out.h = h;
  out.water = water;
  out.ravine = ravine;
  out.swamp = swamp;
  out.clearing = clearing;
  out.rocky = rocky;
  out.path = smoothstep(2.0, 0.8, pathDistAt(wx, wy));
  out.crater = crater;
  out.forestPit = forestPit;
  out.bowl = Math.max(crater, forestPit);
  return out;
}

const _terr = {};
function terrainHeight(wx, wy) { return terrainAt(wx, wy, _terr).h; }
function streamDist(wx, wy) { return riverDist(wx, wy); }

const _gt = {};
function groundWeights(wx, wy, out) {
  const n = soilNoise(wx, wy);
  const t = terrainAt(wx, wy, _gt);
  out[1] = Math.max(smoothstep(0.18, 0.46, n), t.clearing * 0.9);   // поляны — светлая сочная трава
  out[3] = smoothstep(-0.14, -0.42, n) * (1 - t.clearing);           // тёмная лесная земля
  out[4] = smoothstep(-0.55, -1.1, Math.sin(wx * 0.02) + Math.cos(wy * 0.02)) * (1 - t.swamp); // лесной опад
  out[2] = t.path * (1 - t.water);                                   // наезженная грунтовая дорога
  out[5] = t.swamp;                                                  // болото и сырая торфяная грязь
  out[6] = smoothstep(2.2, 0.9, riverDist(wx, wy));                 // галечно-песчаное дно русла
  out[7] = t.rocky * 0.85;                                           // горные скалы и осыпи
  out.t = t;
}

function chunkPixelOrigin(cx, cy) {
  return {
    x: (cx - cy) * (CHUNK_SIZE * TILE_W / 2) - GROUND_BAKE_MARGIN,
    y: (cx + cy) * (CHUNK_SIZE * TILE_H / 2) - GROUND_BAKE_MARGIN
  };
}

function chunkHBase(cx, cy) {
  return Math.round(terrainHeight(cx * CHUNK_SIZE + CHUNK_SIZE / 2, cy * CHUNK_SIZE + CHUNK_SIZE / 2));
}

function chunkBakeOrigin(cx, cy) {
  const o = chunkPixelOrigin(cx, cy);
  return { x: o.x, y: o.y - RELIEF_MARGIN - chunkHBase(cx, cy) * RELIEF_PX_PER_M };
}

function createGroundBaker(makeCanvas, textures, scale) {
  const W = CHUNK_PX_W + GROUND_BAKE_MARGIN * 2;
  const H = CHUNK_PX_H + GROUND_BAKE_MARGIN * 2;
  const mw = Math.ceil(CHUNK_PX_W / GROUND_MASK_STEP) + 1;
  const mh = Math.ceil(CHUNK_PX_H / GROUND_MASK_STEP) + 1;
  const mask = makeCanvas(mw, mh);
  const mctx = mask.getContext('2d');
  const maskData = {};
  for (const t of GROUND_LAYER_ORDER) maskData[t] = mctx.createImageData(mw, mh);
  for (const t of ['water', 'puddle']) maskData[t] = mctx.createImageData(mw, mh);
  const GRAD = ['gx', 'gy'];
  for (const t of GRAD) maskData[t] = mctx.createImageData(mw, mh);
  const S = scale || GROUND_BAKE_SCALE;
  const Ws = Math.ceil(W * S), Hs = Math.ceil(H * S);
  const layer = makeCanvas(Ws, Hs);
  const lctx = layer.getContext('2d');
  const patterns = textures.map((tex) => lctx.createPattern(tex, 'repeat'));
  const weights = [0, 0, 0, 0, 0, 0, 0, 0];
  const k = GROUND_TEX_PX / GROUND_TILES_PER_TEXTURE;
  const pa = TILE_W / (2 * k);
  const pb = TILE_H / (2 * k);

  return function bake(cx, cy) {
    const o = chunkPixelOrigin(cx, cy);
    for (const p of patterns) p.setTransform(new DOMMatrix([pa * S, pb * S, -pa * S, pb * S, -o.x * S, -o.y * S]));

    const maxA = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0, water: 0, puddle: 0, gx: 0, gy: 0 };
    const tt = {};
    for (let j = 0; j < mh; j++) {
      const sum = ((j + 0.5) * GROUND_MASK_STEP + o.y) / (TILE_H / 2);
      for (let i = 0; i < mw; i++) {
        const diff = ((i + 0.5) * GROUND_MASK_STEP + o.x) / (TILE_W / 2);
        const wx = (sum + diff) / 2, wy = (sum - diff) / 2;
        groundWeights(wx, wy, weights);
        const idx = (j * mw + i) * 4 + 3;
        for (const t of GROUND_LAYER_ORDER) {
          const a = Math.round(weights[t] * 255);
          maskData[t].data[idx] = a;
          if (a > maxA[t]) maxA[t] = a;
        }
        const h = weights.t.h;
        const hx = terrainAt(wx + 0.6, wy, tt).h - h;
        const hy = terrainAt(wx, wy + 0.6, tt).h - h;
        const gxm = hx / 0.6 / 1.39 * 1.6, gym = hy / 0.6 / 1.39 * 1.6;
        const extra = {
          water: weights.t.water * 0.82,
          gx: 0.5 + 0.5 * Math.max(-1, Math.min(1, gxm)),
          gy: 0.5 + 0.5 * Math.max(-1, Math.min(1, gym)),
          puddle: weights.t.swamp * smoothstep(0.35, 0.75, Math.sin(wx * 0.7 + Math.sin(wy * 0.5) * 2) * Math.sin(wy * 0.63 + 1.3 + Math.sin(wx * 0.41) * 2)) * 0.8
        };
        for (const t in extra) {
          const a = Math.round(extra[t] * 255);
          maskData[t].data[idx] = a;
          if (a > maxA[t]) maxA[t] = a;
        }
      }
    }

    const out = makeCanvas(Ws, Hs);
    const octx = out.getContext('2d');
    octx.imageSmoothingEnabled = true;

    octx.fillStyle = patterns[0];
    octx.fillRect(0, 0, Ws, Hs);

    for (const t of GROUND_LAYER_ORDER) {
      if (maxA[t] === 0) continue;
      mctx.putImageData(maskData[t], 0, 0);
      lctx.globalCompositeOperation = 'source-over';
      lctx.clearRect(0, 0, Ws, Hs);
      lctx.fillStyle = patterns[t];
      lctx.fillRect(0, 0, Ws, Hs);
      lctx.globalCompositeOperation = 'destination-in';
      lctx.drawImage(mask, 0, 0, Ws, Hs);
      octx.drawImage(layer, 0, 0);
    }

    const overlay = (t, color, op) => {
      if (maxA[t] === 0) return;
      mctx.putImageData(maskData[t], 0, 0);
      lctx.globalCompositeOperation = 'source-over';
      lctx.clearRect(0, 0, Ws, Hs);
      lctx.fillStyle = color;
      lctx.fillRect(0, 0, Ws, Hs);
      lctx.globalCompositeOperation = 'destination-in';
      lctx.drawImage(mask, 0, 0, Ws, Hs);
      octx.globalCompositeOperation = op || 'source-over';
      octx.drawImage(layer, 0, 0);
      octx.globalCompositeOperation = 'source-over';
    };
    overlay('puddle', 'rgb(38, 46, 36)');
    overlay('water', 'rgb(46, 66, 64)');

    const G = GROUND_WARP_CELLS, cs = CHUNK_SIZE / G;
    const startX = cx * CHUNK_SIZE, startY = cy * CHUNK_SIZE;
    const vx = new Float32Array((G + 1) * (G + 1)), vy = new Float32Array((G + 1) * (G + 1));
    const vh = new Float32Array((G + 1) * (G + 1));
    const hBase = chunkHBase(cx, cy);
    let minDy = 1e9, maxDy = -1e9;
    for (let j = 0; j <= G; j++) {
      for (let i = 0; i <= G; i++) {
        const wx = startX + i * cs, wy = startY + j * cs, k = j * (G + 1) + i;
        vx[k] = (wx - wy) * (TILE_W / 2) - o.x;
        vy[k] = (wx + wy) * (TILE_H / 2) - o.y;
        vh[k] = (terrainHeight(wx, wy) - hBase) * RELIEF_PX_PER_M;
        const dy = vy[k] - vh[k] + RELIEF_MARGIN;
        if (dy < minDy) minDy = dy;
        if (dy > maxDy) maxDy = dy;
      }
    }
    const cropTop = Math.max(0, Math.floor(minDy) - 6);
    const cropBot = Math.min(H + RELIEF_MARGIN * 2, Math.ceil(maxDy) + 6);
    const res = makeCanvas(Ws, Math.ceil((cropBot - cropTop) * S));
    res.cropTop = cropTop;
    const rctx = res.getContext('2d');
    const tri = (a, b, c, src, srcK, ctx2, D, gr = 0.8) => {
      const sx0 = vx[a], sy0 = vy[a], sx1 = vx[b], sy1 = vy[b], sx2 = vx[c], sy2 = vy[c];
      const dx0 = sx0, dy0 = sy0 - vh[a] + RELIEF_MARGIN - cropTop;
      const dx1 = sx1, dy1 = sy1 - vh[b] + RELIEF_MARGIN - cropTop;
      const dx2 = sx2, dy2 = sy2 - vh[c] + RELIEF_MARGIN - cropTop;
      const den = (sx0 - sx2) * (sy1 - sy2) - (sx1 - sx2) * (sy0 - sy2);
      if (Math.abs(den) < 1e-4) return;
      const m11 = ((dx0 - dx2) * (sy1 - sy2) - (dx1 - dx2) * (sy0 - sy2)) / den;
      const m12 = ((dy0 - dy2) * (sy1 - sy2) - (dy1 - dy2) * (sy0 - sy2)) / den;
      const m21 = ((dx1 - dx2) * (sx0 - sx2) - (dx0 - dx2) * (sx1 - sx2)) / den;
      const m22 = ((dy1 - dy2) * (sx0 - sx2) - (dy0 - dy2) * (sx1 - sx2)) / den;
      const e = dx0 - m11 * sx0 - m21 * sy0, f = dy0 - m12 * sx0 - m22 * sy0;
      const mx = (dx0 + dx1 + dx2) / 3, my = (dy0 + dy1 + dy2) / 3;
      const grow = (x, y) => { const l = Math.hypot(x - mx, y - my) || 1; return [x + (x - mx) / l * gr, y + (y - my) / l * gr]; };
      const p0 = grow(dx0, dy0), p1 = grow(dx1, dy1), p2 = grow(dx2, dy2);
      ctx2.save();
      ctx2.beginPath();
      ctx2.moveTo(p0[0] * D, p0[1] * D); ctx2.lineTo(p1[0] * D, p1[1] * D); ctx2.lineTo(p2[0] * D, p2[1] * D);
      ctx2.closePath();
      ctx2.clip();
      ctx2.setTransform(m11 * D, m12 * D, m21 * D, m22 * D, e * D, f * D);
      const mg = Math.ceil(gr / Math.min(1, Math.abs(m11) + 0.3)) + 1;
      const bx0 = Math.floor(Math.min(sx0, sx1, sx2)) - mg, by0 = Math.floor(Math.min(sy0, sy1, sy2)) - mg;
      const bw = Math.ceil(Math.max(sx0, sx1, sx2)) - bx0 + 2 * mg, bh = Math.ceil(Math.max(sy0, sy1, sy2)) - by0 + 2 * mg;
      ctx2.drawImage(src, bx0 * srcK, by0 * srcK, bw * srcK, bh * srcK, bx0, by0, bw, bh);
      ctx2.restore();
    };
    for (let sum = 0; sum <= 2 * G - 2; sum++) {
      for (let i = Math.max(0, sum - G + 1); i <= Math.min(G - 1, sum); i++) {
        const j = sum - i;
        const a = j * (G + 1) + i, b = a + 1, c = a + G + 1, d = c + 1;
        tri(a, b, d, out, S, rctx, S);
        tri(a, d, c, out, S, rctx, S);
      }
    }
    const LK = GROUND_LIGHT_SCALE;
    res.light = [];
    for (const t of GRAD) {
      const src = maskData[t].data;
      for (const inv of [false, true]) {
        const flat = makeCanvas(mw, mh);
        const fc = flat.getContext('2d');
        const im = fc.createImageData(mw, mh);
        for (let q = 0; q < mw * mh; q++) {
          const v = inv ? 255 - src[q * 4 + 3] : src[q * 4 + 3];
          im.data[q * 4] = v; im.data[q * 4 + 1] = v; im.data[q * 4 + 2] = v; im.data[q * 4 + 3] = 255;
        }
        fc.putImageData(im, 0, 0);
        const warped = makeCanvas(Math.ceil(Ws / S * LK), Math.ceil(res.height / S * LK));
        const wc = warped.getContext('2d');
        wc.imageSmoothingEnabled = true;
        for (let sum = 0; sum <= 2 * G - 2; sum++) {
          for (let i = Math.max(0, sum - G + 1); i <= Math.min(G - 1, sum); i++) {
            const j = sum - i;
            const a = j * (G + 1) + i, b = a + 1, c = a + G + 1, d = c + 1;
            tri(a, b, d, flat, 1 / GROUND_MASK_STEP, wc, LK, 3);
            tri(a, d, c, flat, 1 / GROUND_MASK_STEP, wc, LK, 3);
          }
        }
        res.light.push(warped);
      }
    }
    return res;
  };
}

// Скорость перемещения бойца по рельефу (вода замедляет на 50%, болото на 35%, подъём в гору)
const _ts = {};
function terrainSpeed(x, y, mx, my) {
  if (typeof terrainAt !== 'function') return 1;
  const t = terrainAt(x, y, _ts);
  let k = 1 - 0.5 * (t.water || 0);
  k *= 1 - 0.35 * (t.swamp || 0);
  const l = Math.hypot(mx || 0, my || 0);
  if (l > 1e-6 && typeof terrainHeight === 'function') {
    const e = 0.5, ux = (mx || 0) / l, uy = (my || 0) / l;
    const slope = (terrainHeight(x + ux * e, y + uy * e) - terrainHeight(x - ux * e, y - uy * e)) / (2 * e);
    k *= slope > 0 ? Math.max(0.55, 1 - slope * 0.55) : Math.min(1.12, 1 - slope * 0.15);
  }
  return Math.max(0.35, Math.min(1.2, k));
}
window.terrainSpeed = terrainSpeed;

// Безопасная обработка коллизий с деревьями и препятствиями
function collidePlayer(prevX, prevY) {
  if (typeof forNearbyObstacles === 'function') {
    forNearbyObstacles((list, radiusFn) => {
      if (!list) return;
      for (const obj of list) {
        const r = typeof radiusFn === 'function' ? radiusFn(obj) : (obj.radius || 0.6);
        const dx = player.x - obj.x, dy = player.y - obj.y;
        const d = Math.hypot(dx, dy);
        const minDist = r + (player.radius || 0.45);
        if (d < minDist && d > 1e-4) {
          player.x = obj.x + (dx / d) * minDist;
          player.y = obj.y + (dy / d) * minDist;
        }
      }
    });
  }
}
window.collidePlayer = collidePlayer;

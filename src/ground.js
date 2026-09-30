// Общий код земли: используется и игрой (src/game.js), и фоновым потоком
// (src/ground-worker.js), который «запекает» землю чанков, чтобы подготовка
// нового участка не останавливала игру.

const TILE_W = 74; // ширина тайла на экране (px); тайл ≈ 1.39 м → масштаб ~37.5 px/м (кадр ~11 м по ширине телефона)
// Наклон камеры задаётся отношением TILE_H/TILE_W: угол камеры над землёй
// = asin(TILE_H / TILE_W). 32/64 — 30° (почти вид сбоку), 48/64 — ~49°
// (заметно «сверху»: боец виден со стороны плеч и головы, а не только сбоку).
// Всё остальное (камера 3D-бойца в character.js, проекция toScreen,
// запекание земли) считается от этих двух чисел.
const TILE_H = 54; // наклон камеры = asin(54/74) ≈ 47° — выбран владельцем в camera-test.html
const CHUNK_SIZE = 12;
const CAMERA_ELEV = Math.asin(TILE_H / TILE_W); // угол камеры над землёй, рад

// Земля: основа — трава, поверх — светлая трава, тёмная земля, пепел и
// тропа, каждая через свою маску прозрачности. Маска считается по точкам
// (шаг GROUND_MASK_STEP px) из плавных функций мировых координат и
// растягивается со сглаживанием — переходы получаются мягким градиентом,
// без ромбов, зубцов и «молний». Текстуры — бесшовные фото (Poly Haven,
// CC0), рисуются canvas-паттерном в изометрической проекции.
// 0 трава, 1 светлая, 2 тропа, 3 тёмная, 4 пепел, 5 болото, 6 дно ручья, 7 камни.
const GROUND_TILES_PER_TEXTURE = 3.2; // сколько игровых клеток занимает одно повторение текстуры
const GROUND_TEX_PX = 384; // ассеты assets/ground/*.jpg приведены к этому размеру (фото + свет из карты нормалей, tools/treegen/bake_ground.py)
const GROUND_MASK_STEP = 8;
const GROUND_LAYER_ORDER = [1, 3, 4, 7, 5, 2, 6]; // …камни, болото, тропа, дно ручья (сверху)
const GROUND_BAKE_MARGIN = 2;
// Рельеф: 1 м высоты сдвигает точку на экране вверх на RELIEF_PX_PER_M px
// (метр на экране по вертикали ≈ 37.7 px/м × cos(наклона камеры)).
// Запечённая земля чанка «морщится» по сетке WARP_CELLS × WARP_CELLS, и в
// холсте оставлен запас RELIEF_MARGIN сверху и снизу под перепад высот внутри чанка.
const RELIEF_PX_PER_M = 48;
const RELIEF_MARGIN = 260;
const GROUND_WARP_CELLS = 16;
const CHUNK_PX_W = CHUNK_SIZE * TILE_W;
const CHUNK_PX_H = CHUNK_SIZE * TILE_H;

function pathDistAt(wx, wy) {
  return Math.abs(wy - Math.sin(wx * 0.15) * 8);
}

// Крупные органичные пятна светлой травы / тёмной земли.
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

// ---------------- Рельеф ----------------
// Всё считается из плавных функций мировых координат (тайлы), поэтому
// одинаково в игре и в фоновом потоке, без хранения карты.
// Холмы: сумма «искривлённых» синусов, перепад ~±2.5 м (после ×0.5 в
// terrainAt), между вершинами 40–90 тайлов (60–120 м).
function hillHeight(wx, wy) {
  return (
    2.2 * Math.sin(wx * 0.041 + 1.3 * Math.sin(wy * 0.027)) +
    1.7 * Math.sin(wy * 0.049 - 0.9 * Math.sin(wx * 0.033)) +
    0.9 * Math.sin((wx + wy) * 0.083 + 2.1) +
    0.4 * Math.sin((wx - wy) * 0.17)
  );
}

// Бугры и впадины «под ногами»: волны 10–30 тайлов, перепад до ~±2 м на
// 10–15 тайлов (уклон 10–20%) — их чувствуешь при ходьбе (в гору медленнее,
// земля и деревья поднимаются на экране); крупные холмы этого не дают.
function bumpHeight(wx, wy) {
  return (
    0.9 * Math.sin(wx * 0.23 + wy * 0.11 + 1.2 * Math.sin(wy * 0.09)) +
    0.85 * Math.sin(wx * 0.13 - wy * 0.27 + 0.8 * Math.sin(wx * 0.11) + 2) +
    0.55 * Math.sin(wx * 0.31 - wy * 0.19 + 4) +
    0.3 * Math.sin(wx * 0.47 + wy * 0.41 + 1)
  );
}

// Уступы (террасы): ступени высотой ~2 м — ровные площадки и крутые откосы
// (5–6 тайлов шириной, уклон ~30%) вдоль линий уровня плавного поля. Откос
// даёт яркую кромку сверху и тёмную стенку — рельеф виден сразу. Есть не везде
// (маска terraceMask ~половина мира), в овраге/у воды/на болоте нет.
function terraceField(wx, wy) {
  return (
    Math.sin(wx * 0.021 + 0.6 * Math.sin(wy * 0.017)) +
    0.8 * Math.sin(wy * 0.024 - 0.5 * Math.sin(wx * 0.02) + 1.9) +
    0.5 * Math.sin((wx + wy) * 0.035 + 0.4)
  ) * 0.75;
}
function terraceHeight(wx, wy) {
  const L = terraceField(wx, wy);
  const k = Math.floor(L), f = L - k;
  return 2.0 * (k + smoothstep(0.78, 0.95, f));
}
function terraceMask(wx, wy) {
  return smoothstep(-0.25, 0.35, Math.sin(wx * 0.017 - wy * 0.013 + 2.2) + 0.6 * Math.sin(wx * 0.03 + wy * 0.041));
}

// Ручьи: линии, где плавное поле F = 0. Расстояние до ручья ≈ |F| / |∇F|.
function streamField(wx, wy) {
  return (
    Math.sin(wx * 0.019 + 1.6 * Math.sin(wy * 0.012 + 0.7)) +
    0.75 * Math.sin(wy * 0.016 - 1.2 * Math.sin(wx * 0.021)) +
    0.28
  );
}
function streamDist(wx, wy) {
  if (TEST_MAP) return testStreamDist(wx, wy);
  const f = streamField(wx, wy);
  const e = 0.5;
  const gx = (streamField(wx + e, wy) - streamField(wx - e, wy)) / (2 * e);
  const gy = (streamField(wx, wy + e) - streamField(wx, wy - e)) / (2 * e);
  return Math.abs(f) / (Math.hypot(gx, gy) + 1e-4);
}

// Сырость: большие пятна; в низинах и сырых местах — болото.
function wetNoise(wx, wy) {
  return (Math.sin(wx * 0.023 + wy * 0.011 + 1.1) + Math.sin(wx * 0.013 - wy * 0.027 + 2.3) * 0.9) / 1.9;
}
// Поляны (без деревьев) и каменистые места.
function clearingNoise(wx, wy) {
  return (Math.sin(wx * 0.052 + 0.8 * Math.sin(wy * 0.04)) + Math.sin(wy * 0.061 - 0.7 * Math.sin(wx * 0.045) + 1.7)) / 2;
}
function rockNoise(wx, wy) {
  return (Math.sin(wx * 0.037 - wy * 0.029 + 4.2) + Math.sin(wx * 0.071 + wy * 0.053 + 0.6) * 0.6) / 1.6;
}

// Котловины: округлые углубления 15–30 тайлов в поперечнике, до 3 м глубиной.
function bowlNoise(wx, wy) {
  return (Math.sin(wx * 0.045 + 1.1 * Math.sin(wy * 0.03 + 1)) + Math.sin(wy * 0.05 - 0.9 * Math.sin(wx * 0.04) + 2.5)) / 2;
}

// ---------------- Тестовая карта ----------------
// TEST_MAP = true: вместо бесконечного мира — квадрат ±TEST_MAP_R тайлов, где
// собрано всё для проверки: яма, холм, овраг с ручьём, болото, поляна,
// каменистое место, уступ, тропа, рощи всех пород (world.js). Выключить —
// поставить false: снова бесконечная генерация, ничего больше менять не нужно.
const TEST_MAP = true;
const TEST_MAP_R = 30;
const TEST_FEATURES = {
  pit:      { x: 5, y: 5, r: 5.5, depth: 3.0 },    // яма (впереди-внизу от старта)
  hill:     { x: -8, y: -8, r: 7.5, h: 4.0 },      // холм (сверху от старта)
  swamp:    { x: -17, y: 6, r: 7 },                // болото (слева)
  clearing: { x: 15, y: -11, r: 6 },               // поляна (справа)
  rocky:    { x: -3, y: -21, r: 5.5 },             // каменистое место (вверху)
  cliffX: 20, cliffH: 2.5                           // уступ вдоль x = 20 (правее — выше)
};
function testStreamY(wx) { return 19 + 3 * Math.sin(wx * 0.18); }
function testStreamDist(wx, wy) {
  const d = wy - testStreamY(wx), k = 3 * 0.18 * Math.cos(wx * 0.18);
  return Math.abs(d) / Math.sqrt(1 + k * k);
}
function radial(x, y, c, r) { return smoothstep(r, r * 0.25, Math.hypot(x - c.x, y - c.y)); }
function terrainAtTest(wx, wy, out) {
  const F = TEST_FEATURES;
  const d = testStreamDist(wx, wy);
  const water = smoothstep(1.15, 0.7, d);
  const ravine = smoothstep(5.5, 0.9, d);
  const pit = radial(wx, wy, F.pit, F.pit.r);
  const hill = radial(wx, wy, F.hill, F.hill.r);
  const swamp = radial(wx, wy, F.swamp, F.swamp.r) * (1 - ravine);
  const cliff = smoothstep(F.cliffX - 0.8, F.cliffX + 0.8, wx) * smoothstep(12, 8, wy) * smoothstep(-26, -22, wy);
  const bump = 0.25 * Math.sin(wx * 0.45 + wy * 0.2) * Math.sin(wy * 0.37 - wx * 0.15) * (1 - ravine) * (1 - swamp);
  out.h = hill * F.hill.h - pit * F.pit.depth - swamp * 0.8 - ravine * 3.4 + cliff * F.cliffH + bump;
  out.bowl = pit;
  out.water = water;
  out.ravine = ravine;
  out.swamp = swamp;
  out.clearing = radial(wx, wy, F.clearing, F.clearing.r) * (1 - swamp);
  out.rocky = Math.max(radial(wx, wy, F.rocky, F.rocky.r), smoothstep(0.6, 0, Math.abs(wx - F.cliffX)) * smoothstep(12, 8, wy) * smoothstep(-26, -22, wy)) * (1 - water);
  return out;
}

// Всё о месте (wx, wy): высота (м), вода/болото/камни/поляна (0..1).
// water — вода ручья; ravine — склон оврага вокруг ручья.
function terrainAt(wx, wy, out) {
  if (TEST_MAP) return terrainAtTest(wx, wy, out);
  const d = streamDist(wx, wy);
  const water = smoothstep(1.15, 0.7, d);
  const ravine = smoothstep(5.5, 0.9, d);
  const hill = hillHeight(wx, wy);
  const wet = wetNoise(wx, wy);
  // болото — в сырых местах, чаще в низинах, не на ручье
  const swamp = smoothstep(0.5, 0.72, wet - hill * 0.16) * (1 - ravine);
  // болото плоское и низкое, овраг — глубокий
  const bowl = smoothstep(0.5, 0.85, bowlNoise(wx, wy)) * (1 - ravine);
  // бугры не в овраге и у воды; на болоте — вполовину слабее (плоское, но не ровное)
  const bump = bumpHeight(wx, wy) * 0.5 * (1 - ravine) * (1 - water) * (1 - 0.5 * swamp);
  const terr = terraceHeight(wx, wy) * terraceMask(wx, wy) * (1 - ravine) * (1 - water) * (1 - swamp) * (1 - bowl);
  const h = hill * 0.5 * (1 - 0.8 * swamp) + bump + terr - swamp * 0.8 - ravine * 3.4 - bowl * 3.0;
  out.h = h;
  out.bowl = bowl;
  out.water = water;
  out.ravine = ravine;
  out.swamp = swamp;
  out.clearing = smoothstep(0.62, 0.8, clearingNoise(wx, wy)) * (1 - swamp) * (1 - ravine);
  out.rocky = smoothstep(0.62, 0.82, rockNoise(wx, wy)) * (1 - swamp) * (1 - water);
  return out;
}
const _terr = {};
function terrainHeight(wx, wy) { return terrainAt(wx, wy, _terr).h; }

// Вес (0..1) каждого слоя земли в точке мира. Пепел — там же, где биом
// «Выгоревшая гарь» (тот же шум, что в getEcosystemAt), но с широкой
// плавной кромкой вместо жёсткого порога.
const _gt = {};
function groundWeights(wx, wy, out) {
  const n = soilNoise(wx, wy);
  const eco = Math.sin(wx / CHUNK_SIZE * 0.3) + Math.cos(wy / CHUNK_SIZE * 0.3);
  const t = terrainAt(wx, wy, _gt);
  out[1] = Math.max(smoothstep(0.18, 0.46, n), t.clearing * 0.85);   // поляны — светлая трава
  out[3] = smoothstep(-0.14, -0.42, n) * (1 - t.clearing);
  out[4] = smoothstep(-0.55, -1.1, eco) * (1 - t.swamp);
  out[2] = smoothstep(1.9, 0.7, pathDistAt(wx, wy)) * (1 - t.swamp * 0.7);
  out[5] = t.swamp;
  out[6] = smoothstep(1.7, 0.95, streamDist(wx, wy));                  // дно чуть шире воды
  out[7] = t.rocky * 0.6;
  out.t = t;
}

// Положение левого верхнего угла картинки чанка в «мировых пикселях»
// (экранные координаты без учёта камеры).
// Где рисовать запечённую (с рельефом) землю чанка: та же точка, но на
// RELIEF_MARGIN выше — сверху запас под холмы.
// Высоты в картинке чанка считаются от chunkHBase (целых метров в его центре),
// а не от нуля: запас RELIEF_MARGIN нужен только под перепад внутри чанка, и
// высокие/низкие места мира не вылезают за холст.
function chunkHBase(cx, cy) {
  return Math.round(terrainHeight(cx * CHUNK_SIZE + CHUNK_SIZE / 2, cy * CHUNK_SIZE + CHUNK_SIZE / 2));
}
function chunkBakeOrigin(cx, cy) {
  const o = chunkPixelOrigin(cx, cy);
  return { x: o.x, y: o.y - RELIEF_MARGIN - chunkHBase(cx, cy) * RELIEF_PX_PER_M };
}

function chunkPixelOrigin(cx, cy) {
  const sx = cx * CHUNK_SIZE, sy = cy * CHUNK_SIZE;
  return {
    x: (sx - sy - CHUNK_SIZE) * (TILE_W / 2) - GROUND_BAKE_MARGIN,
    y: (sx + sy) * (TILE_H / 2) - GROUND_BAKE_MARGIN
  };
}

// makeCanvas(w, h) — обычный <canvas> в игре или OffscreenCanvas в потоке;
// textures — картинки/ImageBitmap в порядке 0..4. Возвращает bake(cx, cy),
// который рисует землю чанка в новый холст и возвращает его.
function createGroundBaker(makeCanvas, textures) {
  const W = CHUNK_PX_W + GROUND_BAKE_MARGIN * 2;
  const H = CHUNK_PX_H + GROUND_BAKE_MARGIN * 2;
  const mw = Math.ceil(CHUNK_PX_W / GROUND_MASK_STEP) + 1;
  const mh = Math.ceil(CHUNK_PX_H / GROUND_MASK_STEP) + 1;
  const mask = makeCanvas(mw, mh);
  const mctx = mask.getContext('2d');
  const maskData = {};
  for (const t of GROUND_LAYER_ORDER) maskData[t] = mctx.createImageData(mw, mh);
  // Вода (поверх дна), светотень рельефа (свет/тень) и лужи болота.
  for (const t of ['water', 'lit', 'shade', 'puddle', 'low', 'hi']) maskData[t] = mctx.createImageData(mw, mh);
  const layer = makeCanvas(W, H);
  const lctx = layer.getContext('2d');
  const patterns = textures.map((tex) => lctx.createPattern(tex, 'repeat'));
  const weights = [0, 0, 0, 0, 0, 0, 0, 0];
  const k = GROUND_TEX_PX / GROUND_TILES_PER_TEXTURE;
  const pa = TILE_W / (2 * k);
  const pb = TILE_H / (2 * k);

  return function bake(cx, cy) {
    const o = chunkPixelOrigin(cx, cy);
    for (const p of patterns) p.setTransform(new DOMMatrix([pa, pb, -pa, pb, -o.x, -o.y]));

    // Маски: точка маски -> «мировой пиксель» -> координаты мира -> веса.
    const maxA = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0, water: 0, lit: 0, shade: 0, puddle: 0 };
    const tt = {};
    for (let j = 0; j < mh; j++) {
      const sum = ((j + 0.5) * GROUND_MASK_STEP + o.y) / (TILE_H / 2);
      for (let i = 0; i < mw; i++) {
        const diff = ((i + 0.5) * GROUND_MASK_STEP + o.x) / (TILE_W / 2);
        const wx = (sum + diff) / 2, wy = (sum - diff) / 2;
        groundWeights(wx, wy, weights);
        const idx = (j * mw + i) * 4 + 3;
        // Рельеф места: наклон, вогнутость — для светотени и для материала откоса
        const h = weights.t.h;
        const hx = terrainAt(wx + 0.6, wy, tt).h - h;
        const hy = terrainAt(wx, wy + 0.6, tt).h - h;
        const lap = (terrainAt(wx + 1.5, wy, tt).h + terrainAt(wx - 1.5, wy, tt).h +
                     terrainAt(wx, wy + 1.5, tt).h + terrainAt(wx, wy - 1.5, tt).h) / 4 - h;
        const slope = Math.hypot(hx, hy) / 0.6 / 1.39;          // уклон, доли (0.3 = 30%)
        // крутой откос — голая земля и камень вместо травы (материал виден с любого
        // направления, в отличие от светотени)
        const steep = smoothstep(0.16, 0.42, slope) * (1 - weights.t.swamp) * (1 - weights.t.water);
        weights[3] = Math.max(weights[3], steep * 0.35);
        weights[7] = Math.max(weights[7], steep * 0.7);
        for (const t of GROUND_LAYER_ORDER) {
          const a = Math.round(weights[t] * 255);
          maskData[t].data[idx] = a;
          if (a > maxA[t]) maxA[t] = a;
        }
        // Светотень: главный свет — сверху-слева экрана (мир (-1,-1)); второй,
        // слабее, — слева-снизу (мир (-1,+1)): иначе откос вдоль главного луча
        // остаётся без светотени. Плюс затемнение по крутизне и по вогнутости
        // (впадина темнее, бугор светлее).
        // Освещение склона по закону Ламберта: нормаль земли из уклона (высоты
        // слегка преувеличены ×1.5, как и на экране), солнце сверху-слева экрана
        // (мир (-1,-1)) под 35° над горизонтом. Ровная земля — без изменений;
        // склон от солнца темнеет (до 70%), к солнцу — светлеет. Плюс слабый
        // боковой свет (мир (-1,+1)) и затемнение во впадинах.
        const gx = hx / 0.6 / 1.39 * 1.5, gy = hy / 0.6 / 1.39 * 1.5;
        const nl = 1 / Math.sqrt(gx * gx + gy * gy + 1);
        const SE = 0.574, CE = 0.819 / Math.SQRT2;        // sin, cos(35°)/√2
        const L = (gx * CE + gy * CE + SE) * nl;         // n·l, n = (-gx,-gy,1)
        const L2 = (gx * CE - gy * CE + SE) * nl;        // боковой свет
        const lightK = (L - SE) * 1.6 + (L2 - SE) * 0.5 - lap * 0.5;
        const extra = {
          water: weights.t.water * 0.82,
          // высота места: низины темнее и холоднее (сыро, тень), возвышенности светлее
          low: smoothstep(0.2, -2.6, h) * 0.38 + smoothstep(1.5, 4.5, h) * 0,
          hi: smoothstep(1.2, 4.2, h) * 0.5,
          lit: Math.min(0.5, Math.max(0, lightK)),
          shade: Math.min(0.72, Math.max(0, -lightK)),
          puddle: weights.t.swamp * smoothstep(0.35, 0.75, Math.sin(wx * 0.7 + Math.sin(wy * 0.5) * 2) * Math.sin(wy * 0.63 + 1.3 + Math.sin(wx * 0.41) * 2)) * 0.8
        };
        for (const t in extra) {
          const a = Math.round(extra[t] * 255);
          maskData[t].data[idx] = a;
          if (a > maxA[t]) maxA[t] = a;
        }
      }
    }

    const out = makeCanvas(W, H);
    const octx = out.getContext('2d');
    octx.imageSmoothingEnabled = true;
    octx.imageSmoothingQuality = 'high';
    octx.fillStyle = patterns[0];
    octx.fillRect(0, 0, W, H);
    for (const t of GROUND_LAYER_ORDER) {
      if (maxA[t] === 0) continue;
      mctx.putImageData(maskData[t], 0, 0);
      lctx.globalCompositeOperation = 'source-over';
      lctx.clearRect(0, 0, W, H);
      lctx.fillStyle = patterns[t];
      lctx.fillRect(0, 0, W, H);
      lctx.globalCompositeOperation = 'destination-in';
      lctx.imageSmoothingEnabled = true;
      lctx.drawImage(mask, 0, 0, mw * GROUND_MASK_STEP, mh * GROUND_MASK_STEP);
      lctx.globalCompositeOperation = 'source-over';
      octx.drawImage(layer, 0, 0);
    }

    // Вода, лужи и светотень — заливка цветом через маску.
    const overlay = (t, color, op) => {
      if (maxA[t] === 0) return;
      mctx.putImageData(maskData[t], 0, 0);
      lctx.globalCompositeOperation = 'source-over';
      lctx.clearRect(0, 0, W, H);
      lctx.fillStyle = color;
      lctx.fillRect(0, 0, W, H);
      lctx.globalCompositeOperation = 'destination-in';
      lctx.drawImage(mask, 0, 0, mw * GROUND_MASK_STEP, mh * GROUND_MASK_STEP);
      lctx.globalCompositeOperation = 'source-over';
      octx.globalCompositeOperation = op || 'source-over';
      octx.drawImage(layer, 0, 0);
      octx.globalCompositeOperation = 'source-over';
    };
    overlay('puddle', 'rgb(38, 46, 36)');
    overlay('water', 'rgb(46, 66, 64)');
    overlay('shade', 'rgb(20, 24, 16)');
    overlay('low', 'rgb(10, 24, 30)');
    overlay('lit', 'rgb(255, 244, 205)', 'soft-light');
    overlay('hi', 'rgb(255, 244, 205)', 'soft-light');

    // Рельеф: плоская картинка `out` режется на сетку клеток мира, каждая
    // клетка (два треугольника) сдвигается по вертикали на высоту своих
    // углов. Рисуем от дальних к ближним — ближний склон закрывает дальний.
    const HH = H + RELIEF_MARGIN * 2;
    const res = makeCanvas(W, HH);
    const rctx = res.getContext('2d');
    const G = GROUND_WARP_CELLS, cs = CHUNK_SIZE / G;
    const startX = cx * CHUNK_SIZE, startY = cy * CHUNK_SIZE;
    const vx = new Float32Array((G + 1) * (G + 1)), vy = new Float32Array((G + 1) * (G + 1));
    const vh = new Float32Array((G + 1) * (G + 1));
    const hBase = chunkHBase(cx, cy);
    for (let j = 0; j <= G; j++) {
      for (let i = 0; i <= G; i++) {
        const wx = startX + i * cs, wy = startY + j * cs, k = j * (G + 1) + i;
        vx[k] = (wx - wy) * (TILE_W / 2) - o.x;
        vy[k] = (wx + wy) * (TILE_H / 2) - o.y;
        vh[k] = (terrainHeight(wx, wy) - hBase) * RELIEF_PX_PER_M;
      }
    }
    const tri = (a, b, c) => {
      // источник (плоская картинка) -> приёмник (со сдвигом по y)
      const sx0 = vx[a], sy0 = vy[a], sx1 = vx[b], sy1 = vy[b], sx2 = vx[c], sy2 = vy[c];
      const dx0 = sx0, dy0 = sy0 - vh[a] + RELIEF_MARGIN;
      const dx1 = sx1, dy1 = sy1 - vh[b] + RELIEF_MARGIN;
      const dx2 = sx2, dy2 = sy2 - vh[c] + RELIEF_MARGIN;
      const ax = sx1 - sx0, ay = sy1 - sy0, bx = sx2 - sx0, by = sy2 - sy0;
      const det = ax * by - ay * bx;
      if (Math.abs(det) < 1e-6) return;
      const cx1 = dx1 - dx0, cy1 = dy1 - dy0, cx2 = dx2 - dx0, cy2 = dy2 - dy0;
      const m11 = (cx1 * by - cx2 * ay) / det, m12 = (cy1 * by - cy2 * ay) / det;
      const m21 = (cx2 * ax - cx1 * bx) / det, m22 = (cy2 * ax - cy1 * bx) / det;
      const e = dx0 - m11 * sx0 - m21 * sy0, f = dy0 - m12 * sx0 - m22 * sy0;
      // клип — приёмный треугольник, чуть раздутый (без щелей между клетками)
      const mx = (dx0 + dx1 + dx2) / 3, my = (dy0 + dy1 + dy2) / 3;
      const grow = (x, y) => { const l = Math.hypot(x - mx, y - my) || 1; return [x + (x - mx) / l * 0.8, y + (y - my) / l * 0.8]; };
      const p0 = grow(dx0, dy0), p1 = grow(dx1, dy1), p2 = grow(dx2, dy2);
      rctx.save();
      rctx.beginPath();
      rctx.moveTo(p0[0], p0[1]); rctx.lineTo(p1[0], p1[1]); rctx.lineTo(p2[0], p2[1]);
      rctx.closePath();
      rctx.clip();
      rctx.setTransform(m11, m12, m21, m22, e, f);
      const bx0 = Math.floor(Math.min(sx0, sx1, sx2)) - 1, by0 = Math.floor(Math.min(sy0, sy1, sy2)) - 1;
      const bw = Math.ceil(Math.max(sx0, sx1, sx2)) - bx0 + 2, bh = Math.ceil(Math.max(sy0, sy1, sy2)) - by0 + 2;
      rctx.drawImage(out, bx0, by0, bw, bh, bx0, by0, bw, bh);
      rctx.restore();
    };
    for (let sum = 0; sum <= 2 * G - 2; sum++) {
      for (let i = Math.max(0, sum - G + 1); i <= Math.min(G - 1, sum); i++) {
        const j = sum - i;
        const a = j * (G + 1) + i, b = a + 1, c = a + G + 1, d = c + 1;
        tri(a, b, d);
        tri(a, d, c);
      }
    }
    return res;
  };
}

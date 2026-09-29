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
const GROUND_TEX_PX = 192; // ассеты assets/ground/*.jpg приведены к этому размеру
const GROUND_MASK_STEP = 8;
const GROUND_LAYER_ORDER = [1, 3, 4, 7, 5, 2, 6]; // …камни, болото, тропа, дно ручья (сверху)
const GROUND_BAKE_MARGIN = 2;
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
// Холмы: сумма «искривлённых» синусов, перепад ~±4 м, между вершинами
// 40–90 тайлов (60–120 м).
function hillHeight(wx, wy) {
  return (
    2.2 * Math.sin(wx * 0.041 + 1.3 * Math.sin(wy * 0.027)) +
    1.7 * Math.sin(wy * 0.049 - 0.9 * Math.sin(wx * 0.033)) +
    0.9 * Math.sin((wx + wy) * 0.083 + 2.1) +
    0.4 * Math.sin((wx - wy) * 0.17)
  );
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

// Всё о месте (wx, wy): высота (м), вода/болото/камни/поляна (0..1).
// water — вода ручья; ravine — склон оврага вокруг ручья.
function terrainAt(wx, wy, out) {
  const d = streamDist(wx, wy);
  const water = smoothstep(1.15, 0.7, d);
  const ravine = smoothstep(5.5, 0.9, d);
  const hill = hillHeight(wx, wy);
  const wet = wetNoise(wx, wy);
  // болото — в сырых местах, чаще в низинах, не на ручье
  const swamp = smoothstep(0.5, 0.72, wet - hill * 0.16) * (1 - ravine);
  // болото плоское и низкое, овраг — глубокий
  const h = hill * (1 - 0.8 * swamp) - swamp * 1.2 - ravine * 2.6;
  out.h = h;
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
  for (const t of ['water', 'lit', 'shade', 'puddle']) maskData[t] = mctx.createImageData(mw, mh);
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
        for (const t of GROUND_LAYER_ORDER) {
          const a = Math.round(weights[t] * 255);
          maskData[t].data[idx] = a;
          if (a > maxA[t]) maxA[t] = a;
        }
        // Светотень: наклон земли к свету (свет — сверху-слева экрана,
        // это направление мира (-1,-1)). Шаг 0.6 тайла.
        const h = weights.t.h;
        const hx = terrainAt(wx + 0.6, wy, tt).h - h;
        const hy = terrainAt(wx, wy + 0.6, tt).h - h;
        const lightK = -(hx + hy) * 1.9;
        const extra = {
          water: weights.t.water * 0.82,
          lit: Math.min(0.32, Math.max(0, lightK)),
          shade: Math.min(0.5, Math.max(0, -lightK)),
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
    overlay('lit', 'rgb(255, 244, 205)', 'soft-light');

    // Оставляем только ромб чанка (с нахлёстом в пару пикселей — соседние
    // чанки перекрываются одинаковой картинкой, стык не виден).
    const m = GROUND_BAKE_MARGIN, ov = 1.5;
    octx.globalCompositeOperation = 'destination-in';
    octx.beginPath();
    octx.moveTo(m + CHUNK_PX_W / 2, m - ov);
    octx.lineTo(m + CHUNK_PX_W + ov, m + CHUNK_PX_H / 2);
    octx.lineTo(m + CHUNK_PX_W / 2, m + CHUNK_PX_H + ov);
    octx.lineTo(m - ov, m + CHUNK_PX_H / 2);
    octx.closePath();
    octx.fillStyle = '#000';
    octx.fill();
    octx.globalCompositeOperation = 'source-over';
    return out;
  };
}

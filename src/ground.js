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
// 0 трава, 1 светлая, 2 тропа, 3 тёмная, 4 пепел.
const GROUND_TILES_PER_TEXTURE = 3.2; // сколько игровых клеток занимает одно повторение текстуры
const GROUND_TEX_PX = 192; // ассеты assets/ground/*.jpg приведены к этому размеру
const GROUND_MASK_STEP = 8;
const GROUND_LAYER_ORDER = [1, 3, 4, 2]; // светлая, тёмная, пепел, тропа (сверху)
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

// Вес (0..1) каждого слоя земли в точке мира. Пепел — там же, где биом
// «Выгоревшая гарь» (тот же шум, что в getEcosystemAt), но с широкой
// плавной кромкой вместо жёсткого порога.
function groundWeights(wx, wy, out) {
  const n = soilNoise(wx, wy);
  const eco = Math.sin(wx / CHUNK_SIZE * 0.3) + Math.cos(wy / CHUNK_SIZE * 0.3);
  out[1] = smoothstep(0.18, 0.46, n);
  out[3] = smoothstep(-0.14, -0.42, n);
  out[4] = smoothstep(-0.55, -1.1, eco);
  out[2] = smoothstep(1.9, 0.7, pathDistAt(wx, wy));
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
  const layer = makeCanvas(W, H);
  const lctx = layer.getContext('2d');
  const patterns = textures.map((tex) => lctx.createPattern(tex, 'repeat'));
  const weights = [0, 0, 0, 0, 0];
  const k = GROUND_TEX_PX / GROUND_TILES_PER_TEXTURE;
  const pa = TILE_W / (2 * k);
  const pb = TILE_H / (2 * k);

  return function bake(cx, cy) {
    const o = chunkPixelOrigin(cx, cy);
    for (const p of patterns) p.setTransform(new DOMMatrix([pa, pb, -pa, pb, -o.x, -o.y]));

    // Маски: точка маски -> «мировой пиксель» -> координаты мира -> веса.
    const maxA = { 1: 0, 2: 0, 3: 0, 4: 0 };
    for (let j = 0; j < mh; j++) {
      const sum = ((j + 0.5) * GROUND_MASK_STEP + o.y) / (TILE_H / 2);
      for (let i = 0; i < mw; i++) {
        const diff = ((i + 0.5) * GROUND_MASK_STEP + o.x) / (TILE_W / 2);
        groundWeights((sum + diff) / 2, (sum - diff) / 2, weights);
        const idx = (j * mw + i) * 4 + 3;
        for (const t of GROUND_LAYER_ORDER) {
          const a = Math.round(weights[t] * 255);
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

// Фоновый поток: запекает землю чанков, чтобы основная игра не ждала.
importScripts('ground.js' + self.location.search);

let bake = null, bakeLo = null;
self.onmessage = (e) => {
  const m = e.data;
  if (m.type === 'init') {
    bake = createGroundBaker((w, h) => new OffscreenCanvas(w, h), m.textures, GROUND_BAKE_SCALE);
    bakeLo = createGroundBaker((w, h) => new OffscreenCanvas(w, h), m.textures, GROUND_LO_SCALE);
  } else if (m.type === 'bake' && bake) {
    const cv = (m.hi ? bake : bakeLo)(m.cx, m.cy);
    const bitmap = cv.transferToImageBitmap();
    self.postMessage({ key: m.key, hi: !!m.hi, bitmap, cropTop: cv.cropTop || 0 }, [bitmap]);
  }
};

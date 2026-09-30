// Фоновый поток: запекает землю чанков, чтобы основная игра не ждала.
importScripts('ground.js' + self.location.search);

let bake = null;
self.onmessage = (e) => {
  const m = e.data;
  if (m.type === 'init') {
    bake = createGroundBaker((w, h) => new OffscreenCanvas(w, h), m.textures);
  } else if (m.type === 'bake' && bake) {
    const cv = bake(m.cx, m.cy);
    const bitmap = cv.transferToImageBitmap();
    self.postMessage({ key: m.key, bitmap, cropTop: cv.cropTop || 0 }, [bitmap]);
  }
};

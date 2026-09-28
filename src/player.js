// Игрок и камера: положение в мире и перевод мировых координат в экранные.

const player = {
  x: 0,
  y: 0,
  vx: 0,
  vy: 0,
  speed: 6.8,
  angle: 0,
  radius: 9,
  isMoving: false
};

const camera = { x: 0, y: 0 };

// Камера для отрисовки кадра: выровнена по реальным точкам экрана
// (1/dpr CSS-пикселя). Так картинка сдвигается ровными шагами в одну точку
// экрана, без пересчёта «между пикселями», и земля (drawGround) с объектами
// (toScreen) используют одно и то же значение — друг относительно друга
// не ездят. Обновляется в начале каждого кадра (render.js).
const renderCam = { x: 0, y: 0 };
function syncRenderCamera() {
  renderCam.x = Math.round(camera.x * view.dpr) / view.dpr;
  renderCam.y = Math.round(camera.y * view.dpr) / view.dpr;
}

// Мир -> экран (изометрическая проекция, TILE_W/TILE_H — из ground.js),
// в CSS-пикселях.
function toScreen(gx, gy) {
  return {
    x: (gx - gy) * (TILE_W / 2) - renderCam.x + view.w / 2,
    y: (gx + gy) * (TILE_H / 2) - renderCam.y + view.h / 2
  };
}

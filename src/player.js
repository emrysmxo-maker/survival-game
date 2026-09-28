// Игрок и камера: положение в мире и перевод мировых координат в экранные.

const player = {
  x: 0,
  y: 0,
  speed: 6.8,
  angle: 0,
  radius: 9,
  isMoving: false
};

const camera = { x: 0, y: 0 };

// Мир -> экран (изометрическая проекция, TILE_W/TILE_H — из ground.js).
// Камера округляется до целого пикселя — так же, как земля в drawGround()
// (render.js), иначе объекты и земля на доли пикселя «ездят» друг
// относительно друга и картинка дрожит.
function toScreen(gx, gy) {
  return {
    x: (gx - gy) * (TILE_W / 2) - Math.round(camera.x) + canvas.width / 2,
    y: (gx + gy) * (TILE_H / 2) - Math.round(camera.y) + canvas.height / 2
  };
}

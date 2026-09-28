// Запуск игры: канвас и игровой цикл (движение, камера, кадр).

const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');

function resize() {
  canvas.width = window.innerWidth;
  canvas.height = window.innerHeight;
}
window.addEventListener('resize', resize);
resize();

let lastTime = performance.now();
function update(dt) {
  if (joystick.active && (Math.abs(joystick.dx) > 0.05 || Math.abs(joystick.dy) > 0.05)) {
    player.isMoving = true;
    const moveX = joystick.dx + joystick.dy;
    const moveY = joystick.dy - joystick.dx;

    player.x += moveX * player.speed * dt;
    player.y += moveY * player.speed * dt;
    player.angle = Math.atan2(joystick.dy, joystick.dx);
  } else {
    player.isMoving = false;
  }

  const targetCamX = (player.x - player.y) * (TILE_W / 2);
  const targetCamY = (player.x + player.y) * (TILE_H / 2);
  // Камера и земля, и объекты сдвигаются на одно и то же целое число
  // пикселей (см. toScreen/drawGround): раньше земля округлялась, а деревья
  // нет — пока камера «доплывала» к игроку после остановки, объекты на пол-
  // пикселя ездили относительно земли и всё будто тряслось. Плюс хвост
  // плавного догона обрезается, чтобы камера не ползла ещё пару секунд.
  camera.x += (targetCamX - camera.x) * 0.12;
  camera.y += (targetCamY - camera.y) * 0.12;
  if (Math.abs(targetCamX - camera.x) < 0.5) camera.x = targetCamX;
  if (Math.abs(targetCamY - camera.y) < 0.5) camera.y = targetCamY;

  updateWorldChunks();
}

function gameLoop(time) {
  const dt = Math.min((time - lastTime) / 1000, 0.1);
  lastTime = time;
  update(dt);
  render();
  requestAnimationFrame(gameLoop);
}
requestAnimationFrame(gameLoop);

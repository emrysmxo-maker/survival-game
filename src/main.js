// Игровой цикл и размер экрана.

const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');

// Логический размер экрана (CSS-пиксели) и плотность пикселей телефона.
// Холст рисуется в реальном разрешении экрана (до x2), а не в CSS-пикселях:
// иначе браузер растягивает весь кадр в ~2.6 раза, и когда в конце
// торможения карта сдвигается на доли пикселя, растянутая картинка
// каждый кадр пересчитывается по-разному — вся карта мелко «дрожит».
// Все координаты в игре остаются в CSS-пикселях (view.w/view.h).
const view = { w: 0, h: 0, dpr: 1 };
const MAX_DPR = 2;

function resize() {
  const dpr = Math.min(window.devicePixelRatio || 1, MAX_DPR);
  const w = window.innerWidth, h = window.innerHeight;
  if (w === view.w && h === view.h && dpr === view.dpr) return;
  view.w = w;
  view.h = h;
  view.dpr = dpr;
  canvas.width = Math.round(w * dpr);
  canvas.height = Math.round(h * dpr);
  canvas.style.width = w + 'px';
  canvas.style.height = h + 'px';
}
window.addEventListener('resize', resize);
resize();

let lastTime = performance.now();

function update(dt) {
  let wantX = 0, wantY = 0;
  if (joystick.active && (joystick.dx !== 0 || joystick.dy !== 0)) {
    wantX = (joystick.dx + joystick.dy) * player.speed;
    wantY = (joystick.dy - joystick.dx) * player.speed;
    player.angle = Math.atan2(joystick.dy, joystick.dx);
    player.isMoving = true;
    player.vx = wantX;
    player.vy = wantY;
  } else {
    // Мгновенная остановка: убираем скольжение «на коньках»
    player.isMoving = false;
    player.vx = 0;
    player.vy = 0;
  }

  player.x += player.vx * dt;
  player.y += player.vy * dt;

  if (typeof updateCharacter === 'function') {
    updateCharacter(dt, player.isMoving, player.angle, Math.hypot(player.vx, player.vy));
  }

  // Камера жёстко привязана к игроку
  camera.x = (player.x - player.y) * (TILE_W / 2);
  camera.y = (player.x + player.y) * (TILE_H / 2);

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

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
// Резкость разгона при старте (1/с): 14 — около 0.1 с до полной скорости.
const PLAYER_START_ACCEL = 14;

function update(dt) {
  let wantX = 0, wantY = 0;
  if (joystick.active && (joystick.dx !== 0 || joystick.dy !== 0)) {
    // При стрельбе скорость задаёт выбранный стиль (charMoveFactor, character.js).
    const mf = typeof charMoveFactor !== 'undefined' ? charMoveFactor : WEAPON_WALK_FACTOR;
    const spd = player.speed * (weapon.firing ? mf : 1);
    wantX = (joystick.dx + joystick.dy) * spd;
    wantY = (joystick.dy - joystick.dx) * spd;
    // местность: вода, болото, склон
    const tk = terrainSpeed(player.x, player.y, wantX, wantY);
    wantX *= tk;
    wantY *= tk;
    player.angle = Math.atan2(joystick.dy, joystick.dx);
    player.isMoving = spd > 0.01;
    // Короткий разгон (~0.1 с): человек не стартует сразу на полной скорости.
    // Остановка, наоборот, мгновенная — никакого скольжения после отпускания.
    const k = 1 - Math.exp(-PLAYER_START_ACCEL * dt);
    player.vx += (wantX - player.vx) * k;
    player.vy += (wantY - player.vy) * k;
  } else {
    player.isMoving = false;
    player.vx = 0;
    player.vy = 0;
  }

  const prevX = player.x, prevY = player.y;
  player.x += player.vx * dt;
  player.y += player.vy * dt;
  collidePlayer(prevX, prevY);
  // Реальная скорость после столкновений: у дерева боец не «бежит на месте».
  const realSpeed = dt > 0 ? Math.hypot(player.x - prevX, player.y - prevY) / dt : 0;

  if (typeof updateCharacter === 'function') {
    updateCharacter(dt, player.isMoving, player.angle, realSpeed);
  }

  // Камера жёстко привязана к игроку
  camera.x = (player.x - player.y) * (TILE_W / 2);
  camera.y = (player.x + player.y) * (TILE_H / 2);

  updateWeapon(dt);
  if (typeof updateZombies === 'function') updateZombies(dt);
  if (typeof updateMinimap === 'function') updateMinimap(dt);
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

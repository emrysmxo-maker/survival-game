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
const MAX_DPR = 3.3;   // полная плотность экрана телефона (было 2 — картинка растягивалась и «мылила»)

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
// Зум камеры в низинах: +ZOOM_PER_M на метр глубины, не больше ZOOM_MAX; скорость 1/с.
const CAMERA_ZOOM_PER_M = 0.12, CAMERA_ZOOM_MAX = 1.22, CAMERA_ZOOM_RATE = 1.4;

function update(dt) {
  let wantX = 0, wantY = 0;
  if (joystick.active && (joystick.dx !== 0 || joystick.dy !== 0)) {
    // При стрельбе скорость задаёт выбранный стиль (charMoveFactor, character.js).
    const mf = typeof charMoveFactor !== 'undefined' ? charMoveFactor : WEAPON_WALK_FACTOR;
    const spd = player.speed * (weapon.firing ? mf : 1);
    wantX = (joystick.dx + joystick.dy) * spd;
    wantY = (joystick.dy - joystick.dx) * spd;
    // местность: вода, болото, склон
    // Скорость от местности меняется не мгновенно: разгон под горку и его
    // инерция (выбежал из ямы — первые шаги вверх ещё бодрые), усталость в
    // гору нарастает за ~0.5 с.
    const tkT = terrainSpeed(player.x, player.y, wantX, wantY);
    player.tk = player.tk || 1;
    player.tk += (tkT - player.tk) * Math.min(1, (tkT > player.tk ? 1.6 : 2.2) * dt);
    const tk = player.tk;
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
  if (TEST_MAP) {                              // край тестовой карты
    const lim = TEST_MAP_R - 1;
    player.x = Math.max(-lim, Math.min(lim, player.x));
    player.y = Math.max(-lim, Math.min(lim, player.y));
  }
  // Реальная скорость после столкновений: у дерева боец не «бежит на месте».
  const realSpeed = dt > 0 ? Math.hypot(player.x - prevX, player.y - prevY) / dt : 0;

  if (typeof updateCharacter === 'function') {
    // уклон по ходу движения (м на м): вверх +, вниз −; персонаж от него наклоняется
    let slopeAlong = 0;
    const vsp = Math.hypot(player.vx, player.vy);
    if (vsp > 0.05) {
      const ux = player.vx / vsp, uy = player.vy / vsp, e = 0.6;
      slopeAlong = (terrainHeight(player.x + ux * e, player.y + uy * e) - terrainHeight(player.x - ux * e, player.y - uy * e)) / (2 * e * METERS_PER_TILE);
    }
    updateCharacter(dt, player.isMoving, player.angle, realSpeed, slopeAlong);
  }

  // Камера жёстко привязана к игроку
  // Высота под бойцом; камера догоняет её плавно (~0.4 с), поэтому при спуске
  // в овраг боец заметно опускается на экране, а земля вокруг поднимается.
  player.h = terrainHeight(player.x, player.y);
  if (camera.h === null) camera.h = player.h;
  camera.h += (player.h - camera.h) * Math.min(1, 2.6 * dt);
  // Камера сближается, когда боец в низине, и плавно возвращается на место при
  // выходе (глубина места = насколько боец ниже средней высоты окрестности
  // в радиусе 6 тайлов). На бугре и ровном месте зума нет — только приближение.
  let ring = 0;
  for (let i = 0; i < 8; i++) {
    const a = i * Math.PI / 4;
    ring += terrainHeight(player.x + Math.cos(a) * 6, player.y + Math.sin(a) * 6);
  }
  const depth = Math.max(0, ring / 8 - player.h);
  const zoomTarget = DBG.noZoom ? 1 : 1 + Math.min(CAMERA_ZOOM_MAX - 1, depth * CAMERA_ZOOM_PER_M);
  camera.zoom = camera.zoom || 1;
  camera.zoom += (zoomTarget - camera.zoom) * Math.min(1, CAMERA_ZOOM_RATE * dt);
  camera.x = (player.x - player.y) * (TILE_W / 2);
  camera.y = (player.x + player.y) * (TILE_H / 2);

  updateWeapon(dt);
  if (typeof updateZombies === 'function') updateZombies(dt);
  updateEffects(dt);
  if (typeof updateDayNight === 'function') updateDayNight(dt);
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

// Номер версии в углу экрана (src/version.js)
(function () { const el = document.getElementById('version-tag'); if (el) el.textContent = 'v' + GAME_VERSION; })();

// Инициализация, управление экраном и главный цикл игры (v7.1).

let canvas, ctx;
const view = { w: 0, h: 0, dpr: 1 };

function resize() {
  canvas = document.getElementById('gameCanvas');
  ctx = canvas.getContext('2d');
  view.w = window.innerWidth;
  view.h = window.innerHeight;
  view.dpr = Math.min(window.devicePixelRatio || 1, MAX_DPR);
  canvas.width = Math.round(view.w * view.dpr);
  canvas.height = Math.round(view.h * view.dpr);
  canvas.style.width = `${view.w}px`;
  canvas.style.height = `${view.h}px`;
  const vt = document.getElementById('version-tag');
  if (vt) vt.textContent = `v${GAME_VERSION}`;
}

window.addEventListener('resize', resize);
window.addEventListener('orientationchange', () => setTimeout(resize, 200));
resize();

let lastTime = performance.now();
const PLAYER_START_ACCEL = 14;
const CAMERA_ZOOM_PER_M = 0.12, CAMERA_ZOOM_MAX = 1.22, CAMERA_ZOOM_RATE = 1.4;

function update(dt) {
  let wantX = 0, wantY = 0;
  if (joystick.active) {
    const mf = Math.hypot(joystick.dx, joystick.dy) < 0.28 ? 0.45 : 0.72;
    const spd = player.speed * (weapon.firing ? mf : 1);
    wantX = (joystick.dx + joystick.dy) * spd;
    wantY = (joystick.dy - joystick.dx) * spd;
    const tk = terrainSpeed(player.x, player.y, wantX, wantY);
    wantX *= tk;
    wantY *= tk;
    player.angle = Math.atan2(joystick.dy, joystick.dx);
    player.isMoving = spd > 0.01;
    player.vx += (wantX - player.vx) * Math.min(1, PLAYER_START_ACCEL * dt);
    player.vy += (wantY - player.vy) * Math.min(1, PLAYER_START_ACCEL * dt);
  } else {
    player.vx *= Math.max(0, 1 - 18 * dt);
    player.vy *= Math.max(0, 1 - 18 * dt);
    if (Math.hypot(player.vx, player.vy) < 0.05) { player.vx = 0; player.vy = 0; }
    player.isMoving = false;
  }

  const prevX = player.x, prevY = player.y;
  player.x += player.vx * dt;
  player.y += player.vy * dt;
  collidePlayer(prevX, prevY);

  // Свободное перемещение по всей карте 1.12 км² (±360 тайлов)
  const mapLim = (typeof MAP_RADIUS !== 'undefined' ? MAP_RADIUS : 360) - 5;
  player.x = Math.max(-mapLim, Math.min(mapLim, player.x));
  player.y = Math.max(-mapLim, Math.min(mapLim, player.y));

  const realSpeed = dt > 0 ? Math.hypot(player.x - prevX, player.y - prevY) / dt : 0;
  if (typeof updateCharacter === 'function') {
    updateCharacter(dt, player.isMoving, player.angle, realSpeed);
  }

  player.h = terrainHeight(player.x, player.y);
  if (camera.h === null) camera.h = player.h;
  camera.h += (player.h - camera.h) * Math.min(1, 2.6 * dt);

  let ring = 0;
  for (let i = 0; i < 8; i++) {
    const a = i * Math.PI / 4;
    ring += terrainHeight(player.x + Math.cos(a) * 6, player.y + Math.sin(a) * 6);
  }
  const depth = Math.max(0, ring / 8 - player.h);
  const zoomTarget = (typeof DBG !== 'undefined' && DBG.noZoom) ? 1 : 1 + Math.min(CAMERA_ZOOM_MAX - 1, depth * CAMERA_ZOOM_PER_M);
  camera.zoom = camera.zoom || 1;
  camera.zoom += (zoomTarget - camera.zoom) * Math.min(1, CAMERA_ZOOM_RATE * dt);

  camera.x = (player.x - player.y) * (TILE_W / 2);
  camera.y = (player.x + player.y) * (TILE_H / 2);

  updateWeapon(dt);
  if (typeof updateZombies === 'function') updateZombies(dt);
  if (typeof updateMinimap === 'function') updateMinimap(dt);
  if (typeof updateDayNight === 'function') updateDayNight(dt);
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

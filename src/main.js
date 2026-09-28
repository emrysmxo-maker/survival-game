// Запуск игры: канвас и игровой цикл (движение, камера, кадр).

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
// Резкость разгона/торможения игрока (1/с): чем больше, тем быстрее
// скорость доходит до нужной; 18 — примерно 0.1 с.
const PLAYER_ACCEL = 18;

function update(dt) {
  let wantX = 0, wantY = 0;
  if (joystick.active && (joystick.dx !== 0 || joystick.dy !== 0)) {
    wantX = (joystick.dx + joystick.dy) * player.speed;
    wantY = (joystick.dy - joystick.dx) * player.speed;
    player.angle = Math.atan2(joystick.dy, joystick.dx);
  }
  // Плавно подводим скорость к желаемой (разгон и торможение за ~0.1–0.2 с),
  // независимо от частоты кадров экрана (60/120/144 Гц).
  const k = 1 - Math.exp(-PLAYER_ACCEL * dt);
  player.vx += (wantX - player.vx) * k;
  player.vy += (wantY - player.vy) * k;
  // Хвост торможения обрезаем: на очень малой скорости игрок сдвигался бы
  // на пиксель раз в несколько кадров — это читается как подёргивание.
  if (wantX === 0 && wantY === 0 && Math.hypot(player.vx, player.vy) < 0.8) {
    player.vx = 0;
    player.vy = 0;
  }
  player.x += player.vx * dt;
  player.y += player.vy * dt;
  player.isMoving = player.vx !== 0 || player.vy !== 0;

  // Камера жёстко привязана к игроку. Раньше она догоняла его с
  // запаздыванием и после остановки ещё около секунды «доплывала»
  // мелкими скачками по пикселю — это и выглядело как рывок всей карты.
  // Плавность теперь даёт разгон/торможение самого игрока выше.
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

// Главный скрипт: инициализация холста, управление камерой и рендер
window.addEventListener('DOMContentLoaded', () => {
  const canvas = document.getElementById('gameCanvas');
  const ctx = canvas.getContext('2d');

  function resize() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
  }
  window.addEventListener('resize', resize);
  resize();

  // Инициализируем мир и камеру
  const world = new World(40, 40);
  const camera = new Camera();

  // Начальная позиция камеры — центр лесной поляны
  const startTarget = world.toScreen(20, 20, { x: 0, y: 0 }, 0, 0);
  camera.x = startTarget.x;
  camera.y = startTarget.y;
  camera.targetX = startTarget.x;
  camera.targetY = startTarget.y;

  // Интерактивное перемещение по карте ландшафта (drag пальцем по экрану)
  let isDragging = false;
  let lastTouchX = 0;
  let lastTouchY = 0;

  window.addEventListener('touchstart', (e) => {
    if (e.touches.length === 1) {
      isDragging = true;
      lastTouchX = e.touches[0].clientX;
      lastTouchY = e.touches[0].clientY;
    }
  }, { passive: false });

  window.addEventListener('touchmove', (e) => {
    if (isDragging && e.touches.length === 1) {
      e.preventDefault();
      const currentX = e.touches[0].clientX;
      const currentY = e.touches[0].clientY;
      const dx = currentX - lastTouchX;
      const dy = currentY - lastTouchY;

      // Сдвиг камеры пальцем
      camera.targetX -= dx;
      camera.targetY -= dy;

      lastTouchX = currentX;
      lastTouchY = currentY;
    }
  }, { passive: false });

  window.addEventListener('touchend', () => { isDragging = false; });
  window.addEventListener('touchcancel', () => { isDragging = false; });

  // Мышь для тестирования на компьютере
  window.addEventListener('mousedown', (e) => {
    isDragging = true;
    lastTouchX = e.clientX;
    lastTouchY = e.clientY;
  });
  window.addEventListener('mousemove', (e) => {
    if (isDragging) {
      camera.targetX -= (e.clientX - lastTouchX);
      camera.targetY -= (e.clientY - lastTouchY);
      lastTouchX = e.clientX;
      lastTouchY = e.clientY;
    }
  });
  window.addEventListener('mouseup', () => { isDragging = false; });

  // Игровой цикл
  function loop() {
    camera.update();

    ctx.clearRect(0, 0, canvas.width, canvas.height);
    world.render(ctx, camera, canvas.width, canvas.height);

    requestAnimationFrame(loop);
  }

  requestAnimationFrame(loop);
});

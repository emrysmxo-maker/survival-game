window.addEventListener('DOMContentLoaded', () => {
  const canvas = document.getElementById('gameCanvas');
  const ctx = canvas.getContext('2d');

  function resize() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
  }
  window.addEventListener('resize', resize);
  resize();

  const world = new World(40, 40);
  const camera = new Camera();

  // Начальная точка в центре
  const startTarget = world.toScreen(20, 20, { x: 0, y: 0 }, 0, 0);
  camera.x = startTarget.x;
  camera.y = startTarget.y;
  camera.targetX = startTarget.x;
  camera.targetY = startTarget.y;

  // Интерактивные кнопки переключения стилей
  const buttons = document.querySelectorAll('.biome-btn');
  buttons.forEach((btn) => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      buttons.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const biomeId = parseInt(btn.dataset.biome);
      world.setBiome(biomeId);
    });
  });

  // Управление камерой пальцем (свайп)
  let isDragging = false;
  let lastX = 0;
  let lastY = 0;

  window.addEventListener('touchstart', (e) => {
    if (e.target.closest('#biome-bar')) return;
    if (e.touches.length === 1) {
      isDragging = true;
      lastX = e.touches[0].clientX;
      lastY = e.touches[0].clientY;
    }
  }, { passive: false });

  window.addEventListener('touchmove', (e) => {
    if (isDragging && e.touches.length === 1) {
      e.preventDefault();
      const curX = e.touches[0].clientX;
      const curY = e.touches[0].clientY;
      camera.targetX -= (curX - lastX);
      camera.targetY -= (curY - lastY);
      lastX = curX;
      lastY = curY;
    }
  }, { passive: false });

  window.addEventListener('touchend', () => { isDragging = false; });
  window.addEventListener('touchcancel', () => { isDragging = false; });

  function loop() {
    camera.update();
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    world.render(ctx, camera, canvas.width, canvas.height);
    requestAnimationFrame(loop);
  }

  requestAnimationFrame(loop);
});

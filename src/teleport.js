// Телепорт по локациям для проверки карты (отдельный файл, игру не трогает).
// Кнопка 📍 под ⚙: список меток из MAP_LANDMARKS (minimap.js).
(function () {
  if (typeof MAP_LANDMARKS === 'undefined') return;
  const box = document.createElement('div');
  box.style.cssText = 'position:fixed;left:8px;top:142px;z-index:40;font:13px sans-serif;color:#eee;';
  const btn = document.createElement('div');
  btn.textContent = '📍';
  btn.style.cssText = 'width:38px;height:38px;line-height:38px;text-align:center;font-size:20px;background:rgba(10,16,10,0.78);border:1px solid rgba(255,255,255,0.25);border-radius:10px;cursor:pointer;';
  const panel = document.createElement('div');
  panel.style.cssText = 'display:none;margin-top:6px;padding:6px;background:rgba(10,16,10,0.9);border:1px solid rgba(255,255,255,0.25);border-radius:10px;max-height:calc(100vh - 200px);overflow-y:auto;';
  for (const lm of MAP_LANDMARKS) {
    const b = document.createElement('div');
    b.textContent = lm.name;
    b.style.cssText = 'padding:8px 10px;cursor:pointer;white-space:nowrap;';
    b.addEventListener('click', () => {
      player.x = lm.x + 4; player.y = lm.y + 4; player.vx = 0; player.vy = 0;
      panel.style.display = 'none';
    });
    panel.appendChild(b);
  }
  btn.addEventListener('click', () => { panel.style.display = panel.style.display === 'none' ? 'block' : 'none'; });
  box.appendChild(btn); box.appendChild(panel);
  document.body.appendChild(box);
})();

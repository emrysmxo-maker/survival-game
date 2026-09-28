// Сенсорное управление: виртуальный джойстик в левой нижней зоне экрана.
// render.js рисует его по этим же полям (joystick.startX/currX/...).

const joystick = {
  active: false, touchId: null,
  startX: 0, startY: 0,
  currX: 0, currY: 0,
  maxDist: 50, dx: 0, dy: 0
};

window.addEventListener('touchstart', (e) => {
  e.preventDefault();
  for (let i = 0; i < e.changedTouches.length; i++) {
    const t = e.changedTouches[i];
    if (!joystick.active) {
      joystick.active = true;
      joystick.touchId = t.identifier;
      joystick.startX = t.clientX; joystick.startY = t.clientY;
      joystick.currX = t.clientX; joystick.currY = t.clientY;
      joystick.dx = 0; joystick.dy = 0;
      document.getElementById('joystick-hint').style.display = 'none';
    }
  }
}, { passive: false });

window.addEventListener('touchmove', (e) => {
  e.preventDefault();
  for (let i = 0; i < e.changedTouches.length; i++) {
    const t = e.changedTouches[i];
    if (t.identifier === joystick.touchId) {
      const diffX = t.clientX - joystick.startX;
      const diffY = t.clientY - joystick.startY;
      const dist = Math.hypot(diffX, diffY);

      if (dist > joystick.maxDist) {
        joystick.currX = joystick.startX + (diffX / dist) * joystick.maxDist;
        joystick.currY = joystick.startY + (diffY / dist) * joystick.maxDist;
      } else {
        joystick.currX = t.clientX;
        joystick.currY = t.clientY;
      }

      joystick.dx = (joystick.currX - joystick.startX) / joystick.maxDist;
      joystick.dy = (joystick.currY - joystick.startY) / joystick.maxDist;
    }
  }
}, { passive: false });

function stopJoy(id) {
  if (joystick.touchId === id) {
    joystick.active = false; joystick.touchId = null;
    joystick.dx = 0; joystick.dy = 0;
  }
}
window.addEventListener('touchend', (e) => { for (const t of e.changedTouches) stopJoy(t.identifier); });
window.addEventListener('touchcancel', (e) => { for (const t of e.changedTouches) stopJoy(t.identifier); });

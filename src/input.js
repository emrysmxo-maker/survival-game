// Сенсорное управление: виртуальный джойстик в левой нижней зоне экрана.
// render.js рисует его по этим же полям (joystick.startX/currX/...).

// Доля радиуса джойстика у центра, где движение не засчитывается (~10px).
const JOYSTICK_DEAD_ZONE = 0.2;

const joystick = {
  active: false, touchId: null,
  startX: 0, startY: 0,
  currX: 0, currY: 0,
  maxDist: 50, dx: 0, dy: 0
};

// Кнопка огня: отдельное касание, джойстик его не занимает. Можно
// бежать одним пальцем и стрелять другим.
const fireBtn = document.getElementById('fire-btn');
let fireTouchId = null;
function setFire(on) {
  weapon.firing = on;
  fireBtn.classList.toggle('pressed', on);
}
window.addEventListener('keydown', (e) => { if (e.code === 'Space') setFire(true); });
window.addEventListener('keyup', (e) => { if (e.code === 'Space') setFire(false); });

window.addEventListener('touchstart', (e) => {
  e.preventDefault();
  for (let i = 0; i < e.changedTouches.length; i++) {
    const t = e.changedTouches[i];
    if (fireBtn.contains(t.target)) {
      fireTouchId = t.identifier;
      setFire(true);
      continue;
    }
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

      // Мёртвая зона у центра: палец на экране всегда чуть дрожит, и
      // без неё при остановке игрок мелко ходил туда-сюда — камера
      // привязана к нему, поэтому тряслась вся карта. Вне зоны скорость
      // растёт плавно от нуля, без скачка на её границе.
      const rx = (joystick.currX - joystick.startX) / joystick.maxDist;
      const ry = (joystick.currY - joystick.startY) / joystick.maxDist;
      const m = Math.hypot(rx, ry);
      if (m < JOYSTICK_DEAD_ZONE) {
        joystick.dx = 0;
        joystick.dy = 0;
      } else {
        const s = (m - JOYSTICK_DEAD_ZONE) / (1 - JOYSTICK_DEAD_ZONE) / m;
        joystick.dx = rx * s;
        joystick.dy = ry * s;
      }
    }
  }
}, { passive: false });

function stopJoy(id) {
  if (fireTouchId === id) { fireTouchId = null; setFire(false); }
  if (joystick.touchId === id) {
    joystick.active = false; joystick.touchId = null;
    joystick.dx = 0; joystick.dy = 0;
  }
}
window.addEventListener('touchend', (e) => { for (const t of e.changedTouches) stopJoy(t.identifier); });
window.addEventListener('touchcancel', (e) => { for (const t of e.changedTouches) stopJoy(t.identifier); });

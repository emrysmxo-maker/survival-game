// Управление для Android сенсорных экранов (v6.4):
// Левая половина экрана — джойстик ходьбы.
// Правая половина экрана — плавающий джойстик огня (появляется под пальцем, стреляет сразу туда, куда направлен).

const joystick = {
  active: false,
  touchId: null,
  startX: 0,
  startY: 0,
  currentX: 0,
  currentY: 0,
  maxDist: 50,
  dx: 0,
  dy: 0
};

const fireJoy = {
  active: false,
  touchId: null,
  startX: 0,
  startY: 0
};

const fireBtn = document.getElementById('fire-btn');
const fireKnob = document.getElementById('fire-knob');
const FIRE_AIM_RADIUS = 44; // px — максимальный ход шляпки

function selectFireStyle(n) {
  fireStyle = n;
  try { localStorage.setItem('fireStyle', String(n)); } catch (e) {}
  document.querySelectorAll('.style-btn').forEach((b) => b.classList.toggle('active', Number(b.dataset.style) === n));
  const el = document.getElementById('style-name');
  if (el) el.textContent = FIRE_STYLE_NAMES[n];
}
selectFireStyle(fireStyle);

const zb = document.getElementById('zombie-btn');
if (zb) zb.addEventListener('click', () => spawnZombie());

let autoFire = false;
function toggleAutoFire() {
  autoFire = !autoFire;
  const b = document.getElementById('auto-btn');
  if (b) {
    b.classList.toggle('active', autoFire);
    b.classList.toggle('on', autoFire);
  }
  if (typeof weapon !== 'undefined') {
    weapon.auto = autoFire;
    if (!weapon.manualFire) {
      weapon.firing = autoFire;
    }
  }
}
const ab = document.getElementById('auto-btn');
if (ab) ab.addEventListener('click', () => toggleAutoFire());

const mm = document.getElementById('minimap');
if (mm) mm.addEventListener('click', () => toggleBigMap(true));

const bm = document.getElementById('bigmap');
if (bm) bm.addEventListener('click', () => toggleBigMap(false));

document.querySelectorAll('.style-btn').forEach((b) => b.addEventListener('click', () => selectFireStyle(Number(b.dataset.style))));

// Клавиатура (для тестов): пробел — огонь
window.addEventListener('keydown', (e) => {
  if (e.code === 'Space' && typeof weapon !== 'undefined') {
    weapon.manualFire = true;
    weapon.firing = true;
    weapon.aimAngle = player.angle;
  }
});
window.addEventListener('keyup', (e) => {
  if (e.code === 'Space' && typeof weapon !== 'undefined') {
    weapon.manualFire = false;
    weapon.firing = typeof weapon.auto !== 'undefined' ? !!weapon.auto : false;
  }
});

function isUI(target) {
  if (!target || !target.closest) return false;
  return !!(
    target.closest('#rot-btn') ||
    target.closest('#zombie-btn') ||
    target.closest('#auto-btn') ||
    target.closest('#minimap') ||
    target.closest('#bigmap') ||
    target.closest('.style-btn') ||
    target.closest('#daynight') ||
    target.closest('#dbg')
  );
}

// Сенсорные касания на экране телефона
window.addEventListener('touchstart', (e) => {
  if (e.target.closest && (e.target.closest('#daynight') || e.target.closest('#dbg'))) return;
  e.preventDefault();
  for (let i = 0; i < e.changedTouches.length; i++) {
    const t = e.changedTouches[i];
    if (isUI(t.target)) {
      if (t.target.closest('#rot-btn')) goLandscape();
      else if (t.target.closest('#zombie-btn')) spawnZombie();
      else if (t.target.closest('#auto-btn')) toggleAutoFire();
      else if (t.target.closest('#minimap')) toggleBigMap(true);
      else if (t.target.closest('#bigmap')) toggleBigMap(false);
      continue;
    }

    // ЛЕВАЯ ПОЛОВИНА: Движение игрока
    if (t.clientX < window.innerWidth * 0.5) {
      if (!joystick.active) {
        joystick.active = true;
        joystick.touchId = t.identifier;
        joystick.startX = t.clientX;
        joystick.startY = t.clientY;
        joystick.currentX = t.clientX;
        joystick.currentY = t.clientY;
        joystick.dx = 0;
        joystick.dy = 0;
      }
      continue;
    }

    // ПРАВАЯ ПОЛОВИНА: Плавающий огонь и прицел
    if (!fireJoy.active) {
      fireJoy.active = true;
      fireJoy.touchId = t.identifier;
      fireJoy.startX = t.clientX;
      fireJoy.startY = t.clientY;

      if (typeof weapon !== 'undefined') {
        weapon.manualFire = true;
        weapon.firing = true; // Сразу открывает огонь!
        weapon.aimAngle = (typeof player !== 'undefined') ? player.angle : 0;
      }

      if (fireBtn) {
        fireBtn.style.left = t.clientX + 'px';
        fireBtn.style.top = t.clientY + 'px';
        fireBtn.classList.add('active', 'pressed');
      }
      if (fireKnob) fireKnob.style.transform = '';
    }
  }
}, { passive: false });

window.addEventListener('touchmove', (e) => {
  if (e.target.closest && (e.target.closest('#daynight') || e.target.closest('#dbg'))) return;
  e.preventDefault();
  for (let i = 0; i < e.changedTouches.length; i++) {
    const t = e.changedTouches[i];

    // Левый стик (ходьба)
    if (joystick.active && t.identifier === joystick.touchId) {
      const diffX = t.clientX - joystick.startX;
      const diffY = t.clientY - joystick.startY;
      const dist = Math.hypot(diffX, diffY);
      const angle = Math.atan2(diffY, diffX);
      const clampedDist = Math.min(dist, joystick.maxDist);
      joystick.currentX = joystick.startX + Math.cos(angle) * clampedDist;
      joystick.currentY = joystick.startY + Math.sin(angle) * clampedDist;
      const DEAD_ZONE = 10;
      if (dist < DEAD_ZONE) {
        joystick.dx = 0;
        joystick.dy = 0;
      } else {
        const factor = (clampedDist - DEAD_ZONE) / (joystick.maxDist - DEAD_ZONE);
        joystick.dx = Math.cos(angle) * factor;
        joystick.dy = Math.sin(angle) * factor;
      }
      continue;
    }

    // Правый стик (направление стрельбы)
    if (fireJoy.active && t.identifier === fireJoy.touchId) {
      const dx = t.clientX - fireJoy.startX;
      const dy = t.clientY - fireJoy.startY;
      const dist = Math.hypot(dx, dy);

      if (typeof weapon !== 'undefined') {
        weapon.manualFire = true;
        weapon.firing = true;
        if (dist > 6) {
          weapon.aimAngle = Math.atan2(dy, dx);
        }
      }

      if (fireKnob) {
        const k = Math.min(dist, FIRE_AIM_RADIUS) / (dist || 1);
        fireKnob.style.transform = `translate(${dx * k}px, ${dy * k}px)`;
      }
    }
  }
}, { passive: false });

function stopJoy(id) {
  if (fireJoy.active && fireJoy.touchId === id) {
    fireJoy.active = false;
    fireJoy.touchId = null;
    if (typeof weapon !== 'undefined') {
      weapon.manualFire = false;
      weapon.firing = typeof weapon.auto !== 'undefined' ? !!weapon.auto : false;
    }
    if (fireBtn) {
      fireBtn.classList.remove('active', 'pressed');
      if (fireKnob) fireKnob.style.transform = '';
    }
  }
  if (joystick.active && joystick.touchId === id) {
    joystick.active = false;
    joystick.touchId = null;
    joystick.dx = 0;
    joystick.dy = 0;
  }
}

window.addEventListener('touchend', (e) => {
  for (let i = 0; i < e.changedTouches.length; i++) stopJoy(e.changedTouches[i].identifier);
});
window.addEventListener('touchcancel', (e) => {
  for (let i = 0; i < e.changedTouches.length; i++) stopJoy(e.changedTouches[i].identifier);
});

function goLandscape() {
  const el = document.documentElement;
  const req = el.requestFullscreen || el.webkitRequestFullscreen;
  Promise.resolve(req ? req.call(el) : null)
    .then(() => screen.orientation && screen.orientation.lock && screen.orientation.lock('landscape'))
    .catch(() => {});
}

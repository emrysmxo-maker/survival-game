// Оружие: стрельба, пули, гильзы, дымок, звук выстрела. Поза и анимация
// автомата в руках бойца — в character.js (там 3D-модель); здесь только
// игровая логика и эффекты. Кнопка «огонь» — в input.js (weapon.firing).
//
// Пули и гильзы вылетают из настоящих точек автомата: character.js каждый
// кадр пересчитывает, где на экране дульный срез и окно выброса
// (charMuzzle / charPort), а тут пуля стартует ровно оттуда.

const FIRE_INTERVAL = 0.11;   // с между выстрелами (~540 выстр/мин, как у штурмового карабина)
const BULLET_SPEED = 30;      // тайлов/с (настоящая пуля быстрее, но так глаз успевает увидеть трассер)
const BULLET_LIFE = 0.55;     // с полёта (~16 тайлов)
const BULLET_SPREAD = 0.02;   // рад, разброс
const TRACER_LEN_PX = 34;     // длина светящегося следа пули на экране
const BULLET_HIT_R = 0.28;    // тайлов: пуля, попавшая в ствол дерева, гасится
const WEAPON_WALK_FACTOR = 0.6; // при стрельбе боец идёт медленнее (шагом)

// Гильзы: вылетают вправо-вверх, падают, раз-другой отскакивают и лежат.
const CASING_GRAVITY = 700;   // px/с² (высота над землёй считается в экранных px)
const CASING_LIE_TIME = 6;    // с лежат на земле, потом тают
const CASING_MAX = 80;

const weapon = {
  firing: false,
  aimAngle: 0,   // экранный угол прицела (кнопка огня как стик)
  cooldown: 0,
  bullets: [],
  casings: [],
  puffs: []     // дымок у дула и пыль/щепки в месте попадания
};

const casingSprite = new Image();
casingSprite.src = `assets/fx/casing.png?v=${ASSET_VERSION}`;

// Направление взгляда бойца в мировых координатах (запасной вариант, если
// 3D-автомат ещё не загрузился): то же соответствие, что у джойстика.
function playerAimDir() {
  const a = player.angle;
  const wx = Math.cos(a) + Math.sin(a);
  const wy = Math.sin(a) - Math.cos(a);
  const l = Math.hypot(wx, wy) || 1;
  return { x: wx / l, y: wy / l };
}

function updateWeapon(dt) {
  weapon.cooldown -= dt;
  // Стреляем, когда автомат поднят к плечу (см. charAimBlend в character.js).
  const ready = typeof charAimBlend === 'undefined' || charAimBlend > 0.75;
  if (weapon.firing && ready && weapon.cooldown <= 0) {
    shootBullet();
    weapon.cooldown = FIRE_INTERVAL;
  }

  const bullets = weapon.bullets;
  for (let i = bullets.length - 1; i >= 0; i--) {
    const b = bullets[i];
    b.age += dt;
    b.x += b.dx * BULLET_SPEED * dt;
    b.y += b.dy * BULLET_SPEED * dt;
    if (bulletHitsTree(b)) {
      spawnImpact(b.x, b.y, b.lift, true);
      bullets.splice(i, 1);
    } else if (b.age > BULLET_LIFE) {
      spawnImpact(b.x, b.y, 0, false); // пуля ушла в землю — облачко пыли
      bullets.splice(i, 1);
    }
  }

  const casings = weapon.casings;
  for (let i = casings.length - 1; i >= 0; i--) {
    const c = casings[i];
    if (c.resting) {
      c.age += dt;
      if (c.age > CASING_LIE_TIME + 1) casings.splice(i, 1);
      continue;
    }
    c.x += c.vx * dt;
    c.y += c.vy * dt;
    c.vz -= CASING_GRAVITY * dt;
    c.z += c.vz * dt;
    c.rot += c.spin * dt;
    if (c.z <= 0) {
      c.z = 0;
      if (c.bounces < 2 && Math.abs(c.vz) > 60) {
        // Удар о землю: подскок, гасит скорость, меняет вращение.
        c.vz = -c.vz * 0.32;
        c.vx *= 0.45; c.vy *= 0.45;
        c.spin = (Math.random() - 0.5) * 30;
        c.bounces++;
      } else {
        c.resting = true;
        c.age = 0;
      }
    }
  }

  const puffs = weapon.puffs;
  for (let i = puffs.length - 1; i >= 0; i--) {
    const p = puffs[i];
    p.age += dt;
    p.x += p.vx * dt;
    p.y += p.vy * dt;
    p.z += p.vz * dt;
    if (p.grav) p.vz -= p.grav * dt;
    if (p.age > p.life) puffs.splice(i, 1);
  }
}

function shootBullet() {
  const hasGun = typeof charMuzzle !== 'undefined' && charMuzzle.ok;
  const d = hasGun ? { x: charMuzzle.dirX, y: charMuzzle.dirY } : playerAimDir();
  // Разброс: прицельно с плеча — маленький, на ходу — больше, стрельба назад
  // на бегу от бедра одной рукой — очень большой (как в жизни).
  const back = typeof charBackFire !== 'undefined' ? charBackFire : 0;
  const cone = BULLET_SPREAD * (player.isMoving ? 1.8 : 1) + 0.12 * back;
  const spread = (Math.random() - 0.5) * 2 * cone;
  const c = Math.cos(spread), s = Math.sin(spread);
  const dx = d.x * c - d.y * s, dy = d.x * s + d.y * c;
  const mx = player.x + (hasGun ? charMuzzle.gx : dx * 0.4);
  const my = player.y + (hasGun ? charMuzzle.gy : dy * 0.4);
  const lift = hasGun ? charMuzzle.lift : 30;
  weapon.bullets.push({ x: mx, y: my, sx: mx, sy: my, dx, dy, lift, age: 0 });

  // Дымок у дула: пара серых клубочков, медленно расходятся и поднимаются.
  for (let k = 0; k < 2; k++) {
    weapon.puffs.push({
      kind: 'smoke', x: mx + dx * 0.1, y: my + dy * 0.1, z: lift,
      vx: dx * (0.4 + Math.random() * 0.4) + (Math.random() - 0.5) * 0.3,
      vy: dy * (0.4 + Math.random() * 0.4) + (Math.random() - 0.5) * 0.3,
      vz: 6 + Math.random() * 6, age: 0, life: 0.7 + Math.random() * 0.4,
      size: 2.5 + Math.random() * 1.5
    });
  }

  if (hasGun && typeof charPort !== 'undefined' && charPort.ok) {
    const sp = 1.1 + Math.random() * 0.6;       // тайлов/с вбок (падают в 1–2 м справа)
    const back = 0.15 + Math.random() * 0.25;   // чуть назад
    weapon.casings.push({
      x: player.x + charPort.gx, y: player.y + charPort.gy, z: charPort.lift,
      vx: charPort.sideX * sp - dx * back, vy: charPort.sideY * sp - dy * back,
      vz: 90 + Math.random() * 50,
      rot: Math.random() * Math.PI, spin: 25 + Math.random() * 20,
      bounces: 0, resting: false, age: 0
    });
    if (weapon.casings.length > CASING_MAX) weapon.casings.shift();
  }

  if (typeof characterShotFired === 'function') characterShotFired();
  playShotSound();
}

// Попадание: в дерево — щепки и древесная пыль, в землю — облачко пыли.
function spawnImpact(x, y, z, wood) {
  const n = wood ? 7 : 4;
  for (let k = 0; k < n; k++) {
    const a = Math.random() * Math.PI * 2;
    const sp = 0.5 + Math.random() * 1.2;
    weapon.puffs.push({
      kind: wood ? 'chip' : 'dust', x, y, z: z + (wood ? 0 : 1),
      vx: Math.cos(a) * sp, vy: Math.sin(a) * sp,
      vz: wood ? 40 + Math.random() * 60 : 10 + Math.random() * 15,
      grav: wood ? 400 : 0,
      age: 0, life: wood ? 0.45 : 0.6 + Math.random() * 0.3,
      size: wood ? 1 + Math.random() : 2 + Math.random() * 2
    });
  }
}

function bulletHitsTree(b) {
  const cx = Math.floor(b.x / CHUNK_SIZE), cy = Math.floor(b.y / CHUNK_SIZE);
  const chunk = loadedChunks.get(`${cx},${cy}`);
  if (!chunk) return false;
  for (const t of chunk.trees) {
    if (Math.abs(t.x - b.x) > BULLET_HIT_R || Math.abs(t.y - b.y) > BULLET_HIT_R) continue;
    if (Math.hypot(t.x - b.x, t.y - b.y) < BULLET_HIT_R) return true;
  }
  return false;
}

// Гильзы рисуются сразу после земли (они лежат на ней, под деревьями и бойцом).
function drawCasings(ctx) {
  if (!casingSprite.complete || !casingSprite.naturalWidth) return;
  for (const c of weapon.casings) {
    const p = toScreen(c.x, c.y);
    if (p.x < -20 || p.x > view.w + 20 || p.y < -60 || p.y > view.h + 20) continue;
    const fade = c.resting ? Math.min(1, CASING_LIE_TIME + 1 - c.age) : 1;
    if (fade <= 0) continue;
    ctx.save();
    ctx.globalAlpha = fade;
    ctx.translate(p.x, p.y - c.z);
    ctx.rotate(c.rot);
    ctx.drawImage(casingSprite, -2, -0.7, 4, 1.4);
    ctx.restore();
  }
}

// Трассеры, дым, щепки и пыль рисуются В ОБЩЕЙ ОЧЕРЕДИ с деревьями и бойцом
// (render.js кладёт их в renderQueue по глубине x+y): пуля перед деревом
// видна поверх него, а пуля за деревом скрыта кроной — как в жизни. Раньше
// они рисовались поверх всего, и пуля «летела над деревом».
//
// Трассер как в реальной съёмке: тонкая светлая полоска, короткая, без
// «лазеров».
function drawBullet(ctx, b) {
  // Длина следа берётся в ЭКРАННЫХ пикселях, а не в тайлах: по вертикали
  // экрана тайл вдвое короче, и при стрельбе вниз/вверх след раньше
  // сжимался в едва заметную точку.
  const head = toScreen(b.x, b.y);
  const flown = toScreen(b.sx, b.sy);
  const hx = head.x - flown.x, hy = head.y - flown.y;
  const flownPx = Math.hypot(hx, hy);
  if (flownPx < 1) return;
  const ux = hx / flownPx, uy = hy / flownPx;
  const len = Math.min(TRACER_LEN_PX, flownPx);
  const tx = head.x - ux * len, ty = head.y - uy * len;
  const y0 = b.lift;
  const g = ctx.createLinearGradient(tx, ty - y0, head.x, head.y - y0);
  g.addColorStop(0, 'rgba(255, 210, 120, 0)');
  g.addColorStop(0.7, 'rgba(255, 225, 150, 0.55)');
  g.addColorStop(1, 'rgba(255, 250, 225, 0.95)');
  ctx.save();
  ctx.lineCap = 'round';
  ctx.strokeStyle = g;
  ctx.lineWidth = 1.6;
  ctx.beginPath();
  ctx.moveTo(tx, ty - y0);
  ctx.lineTo(head.x, head.y - y0);
  ctx.stroke();
  ctx.restore();
}

// Дымок у дула, щепки при попадании в дерево, пыль от пули в землю.
function drawPuff(ctx, p) {
  const s = toScreen(p.x, p.y);
  const t = p.age / p.life;
  ctx.save();
  if (p.kind === 'chip') {
    ctx.globalAlpha = 1 - t;
    ctx.fillStyle = '#6b5236';
    ctx.fillRect(s.x - p.size / 2, s.y - p.z - p.size / 2, p.size, p.size);
  } else {
    const r = p.size * (1 + t * 2.5);
    const a = (p.kind === 'smoke' ? 0.22 : 0.3) * (1 - t);
    const col = p.kind === 'smoke' ? '200, 200, 195' : '150, 130, 100';
    const grad = ctx.createRadialGradient(s.x, s.y - p.z, 0, s.x, s.y - p.z, r);
    grad.addColorStop(0, `rgba(${col}, ${a})`);
    grad.addColorStop(1, `rgba(${col}, 0)`);
    ctx.fillStyle = grad;
    ctx.fillRect(s.x - r, s.y - p.z - r, r * 2, r * 2);
  }
  ctx.restore();
}

// Звук выстрела: синтезируется (шумовой «хлопок» + низкий удар), файлов нет.
let audioCtx = null;
let noiseBuf = null;
function playShotSound() {
  try {
    if (!audioCtx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return;
      audioCtx = new AC();
      noiseBuf = audioCtx.createBuffer(1, Math.floor(audioCtx.sampleRate * 0.25), audioCtx.sampleRate);
      const data = noiseBuf.getChannelData(0);
      for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
    }
    if (audioCtx.state === 'suspended') audioCtx.resume();
    const t = audioCtx.currentTime;

    const noise = audioCtx.createBufferSource();
    noise.buffer = noiseBuf;
    const lp = audioCtx.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.setValueAtTime(5000, t);
    lp.frequency.exponentialRampToValueAtTime(600, t + 0.12);
    const ng = audioCtx.createGain();
    ng.gain.setValueAtTime(0.5, t);
    ng.gain.exponentialRampToValueAtTime(0.001, t + 0.14);
    noise.connect(lp); lp.connect(ng); ng.connect(audioCtx.destination);
    noise.start(t); noise.stop(t + 0.16);

    const osc = audioCtx.createOscillator();
    osc.frequency.setValueAtTime(140, t);
    osc.frequency.exponentialRampToValueAtTime(45, t + 0.09);
    const og = audioCtx.createGain();
    og.gain.setValueAtTime(0.5, t);
    og.gain.exponentialRampToValueAtTime(0.001, t + 0.1);
    osc.connect(og); og.connect(audioCtx.destination);
    osc.start(t); osc.stop(t + 0.11);
  } catch (e) { /* звук — не критично */ }
}

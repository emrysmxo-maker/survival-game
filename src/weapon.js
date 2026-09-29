// Оружие: стрельба, пули, звук выстрела. Поза и анимация автомата в руках
// бойца — в character.js (там 3D-модель); здесь только игровая логика.
// Кнопка «огонь» обрабатывается в input.js (weapon.firing).

const FIRE_INTERVAL = 0.11;   // с между выстрелами (~540 выстр/мин, как у штурмового карабина)
const BULLET_SPEED = 30;      // тайлов/с
const BULLET_LIFE = 0.5;      // с полёта (~15 тайлов ≈ 20 м)
const BULLET_SPREAD = 0.025;  // рад, разброс
const BULLET_HEIGHT_PX = 30;  // высота дульного среза над землёй на экране
const BULLET_HIT_R = 0.28;    // тайлов: пуля, попавшая в ствол дерева, гасится
const WEAPON_WALK_FACTOR = 0.6; // при стрельбе боец идёт медленнее (шагом)

const weapon = {
  firing: false,
  cooldown: 0,
  bullets: []
};

// Направление взгляда бойца в мировых координатах: то же соответствие,
// что у джойстика в main.js (экранный угол -> ось x/y мира).
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
    if (b.age > BULLET_LIFE || bulletHitsTree(b)) bullets.splice(i, 1);
  }
}

function shootBullet() {
  const d = playerAimDir();
  const spread = (Math.random() - 0.5) * 2 * BULLET_SPREAD;
  const c = Math.cos(spread), s = Math.sin(spread);
  const dx = d.x * c - d.y * s, dy = d.x * s + d.y * c;
  weapon.bullets.push({
    x: player.x + dx * 0.55, y: player.y + dy * 0.55,
    dx, dy, age: 0
  });
  if (typeof characterShotFired === 'function') characterShotFired();
  playShotSound();
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

// Трассеры пуль: короткая светящаяся линия вдоль полёта.
function drawBullets(ctx) {
  ctx.save();
  ctx.lineCap = 'round';
  for (const b of weapon.bullets) {
    const head = toScreen(b.x, b.y);
    const tail = toScreen(b.x - b.dx * 1.1, b.y - b.dy * 1.1);
    const fade = Math.min(1, (BULLET_LIFE - b.age) / 0.15);
    ctx.globalAlpha = Math.max(0, fade);
    ctx.strokeStyle = 'rgba(255, 224, 140, 0.95)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(tail.x, tail.y - BULLET_HEIGHT_PX);
    ctx.lineTo(head.x, head.y - BULLET_HEIGHT_PX);
    ctx.stroke();
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

// Следы под ногами: отпечатки на мягкой земле (грязь, тропа, пепел),
// пыль из-под ног на сухой земле при беге, брызги и круги на воде.
// Это эффекты (как кровь и дым выстрела) — рисуются кодом, картинок нет.

const FX_STEP = 0.5;            // длина шага, тайлы (~0.7 м)
const FOOTPRINT_LIFE = 25;      // с
const FOOTPRINT_MAX = 180;
const fx = { prints: [], dust: [], ripples: [], drops: [] };
const _fw = [];

// Вызывается каждый кадр для бойца и каждого зомби.
function stepEffects(ent, x, y, dt, heavy) {
  if (ent._fxX === undefined) { ent._fxX = x; ent._fxY = y; ent._fxAcc = 0; ent._fxSide = 1; return; }
  const dx = x - ent._fxX, dy = y - ent._fxY;
  ent._fxX = x; ent._fxY = y;
  const d = Math.hypot(dx, dy);
  if (d < 1e-5 || d > 1) return;
  ent._fxAcc += d;
  if (ent._fxAcc < FX_STEP) return;
  ent._fxAcc -= FX_STEP;
  ent._fxSide = -ent._fxSide;
  const speed = dt > 0 ? d / dt : 0;
  const nx = dx / d, ny = dy / d;
  // ступня — чуть в сторону от линии движения
  const fxw = x - ny * 0.07 * ent._fxSide, fyw = y + nx * 0.07 * ent._fxSide;
  groundWeights(fxw, fyw, _fw);
  const t = _fw.t, h = t.h;
  if (t.water > 0.15) {
    fx.ripples.push({ x: fxw, y: fyw, h, age: 0, life: 1.3 });
    const n = heavy ? 3 : 5;
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2, v = 12 + Math.random() * 22;
      fx.drops.push({ x: fxw, y: fyw, h, ox: 0, oy: 0, vx: Math.cos(a) * v, vy: Math.sin(a) * v * 0.5, vz: 40 + Math.random() * 50, z: 0, age: 0 });
    }
    return;
  }
  const soft = Math.max(t.swamp, _fw[2] || 0, (_fw[4] || 0) * 0.8, (_fw[3] || 0) * 0.6);
  if (soft > 0.3) {
    fx.prints.push({ x: fxw, y: fyw, h, ang: Math.atan2((nx + ny) * TILE_H / 2, (nx - ny) * TILE_W / 2), mud: t.swamp > 0.3, age: 0, k: heavy ? 1.2 : 1 });
    if (fx.prints.length > FOOTPRINT_MAX) fx.prints.shift();
  }
  const dry = ((_fw[2] || 0) + (_fw[4] || 0) + (_fw[7] || 0) * 0.6) * (1 - t.swamp);
  if (dry > 0.35 && speed > 1.2) {
    const ash = (_fw[4] || 0) > 0.4;
    for (let i = 0; i < 2; i++) {
      fx.dust.push({ x: fxw, y: fyw, h, ox: (Math.random() - 0.5) * 6 - nx * 4, oy: (Math.random() - 0.5) * 3, age: 0, life: 0.8 + Math.random() * 0.5, ash });
    }
  }
}

function updateEffects(dt) {
  stepEffects(player, player.x, player.y, dt, false);
  if (typeof zombies !== 'undefined') {
    for (const z of zombies) if (z.state !== 'dead') stepEffects(z, z.x, z.y, dt, true);
  }
  for (const p of fx.prints) p.age += dt;
  while (fx.prints.length && fx.prints[0].age > FOOTPRINT_LIFE) fx.prints.shift();
  fx.dust = fx.dust.filter((p) => (p.age += dt) < p.life);
  fx.ripples = fx.ripples.filter((p) => (p.age += dt) < p.life);
  fx.drops = fx.drops.filter((p) => {
    p.age += dt;
    p.ox += p.vx * dt; p.oy += p.vy * dt;
    p.vz -= 260 * dt; p.z += p.vz * dt;
    return p.z > 0 || p.age < 0.05;
  });
}

// Всё рисуется на земле, под бойцом и деревьями.
function drawEffects(c) {
  c.save();
  for (const p of fx.prints) {
    const s = toScreen(p.x, p.y, p.h);
    if (!onScreen(s, 20)) continue;
    const a = (p.mud ? 0.5 : 0.32) * Math.min(1, (FOOTPRINT_LIFE - p.age) / 6);
    c.fillStyle = p.mud ? `rgba(22,16,8,${a})` : `rgba(40,30,18,${a})`;
    c.beginPath();
    c.ellipse(s.x, s.y, 5.2 * p.k, 2.3 * p.k, p.ang, 0, Math.PI * 2);
    c.fill();
  }
  for (const p of fx.ripples) {
    const s = toScreen(p.x, p.y, p.h);
    if (!onScreen(s, 40)) continue;
    const k = p.age / p.life, r = 4 + k * 22;
    c.strokeStyle = `rgba(210,225,230,${0.32 * (1 - k)})`;
    c.lineWidth = 1.2;
    c.beginPath();
    c.ellipse(s.x, s.y, r, r * 0.45, 0, 0, Math.PI * 2);
    c.stroke();
  }
  for (const p of fx.dust) {
    const s = toScreen(p.x, p.y, p.h);
    if (!onScreen(s, 40)) continue;
    const k = p.age / p.life, r = 4 + k * 13;
    const g = c.createRadialGradient(s.x + p.ox, s.y + p.oy - k * 8, 0, s.x + p.ox, s.y + p.oy - k * 8, r);
    const col = p.ash ? '120,115,110' : '150,128,96';
    g.addColorStop(0, `rgba(${col},${0.3 * (1 - k)})`);
    g.addColorStop(1, `rgba(${col},0)`);
    c.fillStyle = g;
    c.beginPath(); c.arc(s.x + p.ox, s.y + p.oy - k * 8, r, 0, Math.PI * 2); c.fill();
  }
  c.fillStyle = 'rgba(215,230,235,0.75)';
  for (const p of fx.drops) {
    const s = toScreen(p.x, p.y, p.h);
    c.fillRect(s.x + p.ox - 1, s.y + p.oy - p.z - 1, 2, 2);
  }
  c.restore();
}

// Зомби (для теста — вызывается кнопкой «ЗОМБИ»).
// Модель: «Mobile Ready Zombie» (OpenGameArt, CC0), привязана в Blender к
// скелету Mixamo бойца — поэтому у зомби те же клипы Walk/Idle/Run
// (assets/character/Zombie.glb, как собрано — tools/zombie/README.md).
//
// Здоровье и конечности: пуля попадает в случайную часть тела (голова,
// корпус, руки, ноги). Голова — много урона. Рука, набравшая урон, может
// оторваться (кость руки сжимается в ноль — рука исчезает, летит кровь).
// Нога, набравшая урон, ломается или отрывается: зомби падает и ползёт.
// Здоровье 0 — падает и лежит, потом исчезает.
//
// Рисуется так же, как боец: своя 3D-сцена в закадровый холст, холст —
// в общую очередь отрисовки по глубине.

const ZOMBIE_HP = 250;
const ZOMBIE_WALK_TPS = 0.55;     // тайлов/с — медленный шаг (~0.8 м/с)
const ZOMBIE_CRAWL_TPS = 0.22;    // ползком
const ZOMBIE_HIT_R = 0.38;        // тайлов — радиус попадания
const ZOMBIE_REACH = 0.75;        // тайлов — дистанция «удара»
const ZOMBIE_FRUSTUM = 3.2;       // кадр 3D-камеры (шире, чем у бойца: лежачий зомби длиннее)
const ZOMBIE_DRAW = CHARACTER_DRAW_W * ZOMBIE_FRUSTUM / 2.4;
const ZOMBIE_BASE_FRAC = 0.5 + 0.85 * Math.cos(CAMERA_ELEV) / ZOMBIE_FRUSTUM + 0.0197 * 2.4 / ZOMBIE_FRUSTUM;
const ZOMBIE_MAX = 6;
// Части тела: вероятность попадания, урон, прочность конечности.
const ZOMBIE_PARTS = [
  { part: 'head', p: 0.12, dmg: 55 },
  { part: 'torso', p: 0.43, dmg: 16 },
  { part: 'armL', p: 0.11, dmg: 10, hp: 28 },
  { part: 'armR', p: 0.11, dmg: 10, hp: 28 },
  { part: 'legL', p: 0.115, dmg: 12, hp: 30 },
  { part: 'legR', p: 0.115, dmg: 12, hp: 30 }
];

const zombies = [];
const bloodDecals = [];
let zombieGltf = null;
let zombieLoading = false;
let zRenderer = null, zCamera = null;

function initZombieRenderer() {
  if (zRenderer || typeof THREE === 'undefined') return !!zRenderer;
  const c = document.createElement('canvas');
  c.width = c.height = 320;
  zRenderer = new THREE.WebGLRenderer({ canvas: c, alpha: true, antialias: true, preserveDrawingBuffer: true });
  zRenderer.setSize(320, 320);
  zRenderer.setClearColor(0x000000, 0);
  const f = ZOMBIE_FRUSTUM;
  zCamera = new THREE.OrthographicCamera(-f / 2, f / 2, f / 2, -f / 2, 0.1, 50);
  zCamera.position.set(0, 5.6 * Math.sin(CAMERA_ELEV), 5.6 * Math.cos(CAMERA_ELEV));
  zCamera.lookAt(0, 0.85, 0);
  return true;
}

function loadZombieModel(cb) {
  if (zombieGltf) { cb(); return; }
  if (zombieLoading || typeof THREE === 'undefined' || !THREE.GLTFLoader) return;
  zombieLoading = true;
  new THREE.GLTFLoader().load(`assets/character/Zombie.glb?v=${ASSET_VERSION}`, (g) => {
    zombieGltf = g;
    zombieLoading = false;
    cb();
  }, undefined, () => { zombieLoading = false; });
}

// Кнопка «ЗОМБИ»: появляется в ~7 тайлах от бойца в случайной стороне.
function spawnZombie() {
  if (!initZombieRenderer()) return;
  loadZombieModel(() => {
    if (zombies.length >= ZOMBIE_MAX) zombies.shift();
    const a = Math.random() * Math.PI * 2;
    const z = createZombie(player.x + Math.cos(a) * 7, player.y + Math.sin(a) * 7);
    zombies.push(z);
  });
}

function createZombie(x, y) {
  const scene = new THREE.Scene();
  scene.add(new THREE.AmbientLight(0xffffff, 1.1));
  const d = new THREE.DirectionalLight(0xfff2e0, 1.6); d.position.set(-4, 7, 3); scene.add(d);
  const fill = new THREE.DirectionalLight(0x8090a0, 0.35); fill.position.set(3, 2, -2); scene.add(fill);

  const model = THREE.SkeletonUtils ? THREE.SkeletonUtils.clone(zombieGltf.scene) : cloneSkinned(zombieGltf.scene);
  model.traverse((n) => { if (n.isMesh) { n.frustumCulled = false; n.material = n.material.clone(); } });
  model.scale.setScalar(0.9);          // как боец: ~1.65 в единицах сцены
  model.rotation.y = Math.PI;           // модель смотрит в -Z, как Soldier.glb
  // root — поворот к цели; tilt — наклон всего тела (ползёт / упал).
  const root = new THREE.Group();
  const tilt = new THREE.Group();
  tilt.add(model);
  root.add(tilt);
  scene.add(root);

  const bones = {};
  model.traverse((n) => { if (n.isBone) bones[n.name.replace('mixamorig', '').replace(':', '')] = n; });
  // Поза покоя ног (ноги прямые) — ползком ноги волочатся прямо.
  const legRest = {};
  ['LeftUpLeg', 'LeftLeg', 'RightUpLeg', 'RightLeg', 'LeftFoot', 'RightFoot'].forEach((n) => {
    if (bones[n]) legRest[n] = bones[n].quaternion.clone();
  });
  // Пальцы ног держим в покое: иначе при автопривязке ступня «хлопает».
  const toeRest = {};
  ['LeftToeBase', 'RightToeBase'].forEach((n) => { if (bones[n]) toeRest[n] = bones[n].quaternion.clone(); });
  const mixer = new THREE.AnimationMixer(model);
  const actions = {};
  zombieGltf.animations.forEach((clip) => { actions[clip.name] = mixer.clipAction(clip); });
  const walk = actions.Walk;
  walk.play();
  walk.time = Math.random() * walk.getClip().duration;

  return {
    x, y, hp: ZOMBIE_HP, state: 'walk', t: 0, yaw: 0,
    scene, root, tilt, model, bones, legRest, toeRest, mixer, actions, crawlK: 0,
    limbs: { armL: 28, armR: 28, legL: 30, legR: 30 },
    lost: {}, broken: {}, labels: [],
    fall: 0, deadT: 0, attackT: 0, hitFlash: 0,
    phase: Math.random() * 10
  };
}

// Запасной клон скелетной модели (если SkeletonUtils не подключён).
function cloneSkinned(src) {
  const clone = src.clone(true);
  const srcBones = {}, dstBones = {};
  src.traverse((n) => { if (n.isBone) srcBones[n.name] = n; });
  clone.traverse((n) => { if (n.isBone) dstBones[n.name] = n; });
  const srcMeshes = [], dstMeshes = [];
  src.traverse((n) => { if (n.isSkinnedMesh) srcMeshes.push(n); });
  clone.traverse((n) => { if (n.isSkinnedMesh) dstMeshes.push(n); });
  dstMeshes.forEach((m, i) => {
    const sk = srcMeshes[i].skeleton;
    const bones = sk.bones.map((b) => dstBones[b.name]);
    m.bind(new THREE.Skeleton(bones, sk.boneInverses), srcMeshes[i].bindMatrix);
  });
  return clone;
}

function updateZombies(dt) {
  for (let i = zombies.length - 1; i >= 0; i--) {
    const z = zombies[i];
    z.t += dt;
    z.hitFlash = Math.max(0, z.hitFlash - dt);
    for (let k = z.labels.length - 1; k >= 0; k--) {
      z.labels[k].age += dt;
      if (z.labels[k].age > z.labels[k].life) z.labels.splice(k, 1);
    }
    const dx = player.x - z.x, dy = player.y - z.y;
    const dist = Math.hypot(dx, dy);

    if (z.state === 'dead') {
      z.deadT += dt;
      z.fall = Math.min(1, z.fall + dt * 2.2);
      if (z.deadT > 12) { zombies.splice(i, 1); continue; }
    } else {
      // Направление на бойца в экранных координатах -> угол поворота модели.
      const sa = Math.atan2((dx + dy) * TILE_H / 2, (dx - dy) * TILE_W / 2);
      const targetYaw = screenAngleToYaw(sa);
      let d = targetYaw - z.yaw;
      while (d < -Math.PI) d += Math.PI * 2;
      while (d > Math.PI) d -= Math.PI * 2;
      z.yaw += Math.max(-1.6 * dt, Math.min(1.6 * dt, d)); // медленно разворачивается

      const crawl = z.state === 'crawl';
      const speed = crawl ? ZOMBIE_CRAWL_TPS : ZOMBIE_WALK_TPS * (z.broken.legL || z.broken.legR ? 0.6 : 1);
      if (dist > ZOMBIE_REACH) {
        // Идёт к бойцу; пока не развернулся к нему — медленнее (не скользит боком).
        const facing = Math.max(0.15, Math.cos(d)) * terrainSpeed(z.x, z.y, dx, dy);
        z.x += dx / dist * speed * facing * dt;
        z.y += dy / dist * speed * facing * dt;
        collideZombie(z);
        z.attackT = 0;
      } else {
        z.attackT += dt;
      }
    }
    animateZombie(z, dt);
  }
  for (let i = bloodDecals.length - 1; i >= 0; i--) {
    bloodDecals[i].age += dt;
    if (bloodDecals[i].age > 14) bloodDecals.splice(i, 1);
  }
}

function collideZombie(z) {
  const cx = Math.floor(z.x / CHUNK_SIZE), cy = Math.floor(z.y / CHUNK_SIZE);
  for (let ix = cx - 1; ix <= cx + 1; ix++) {
    for (let iy = cy - 1; iy <= cy + 1; iy++) {
      const chunk = loadedChunks.get(`${ix},${iy}`);
      if (!chunk) continue;
      for (const t of chunk.rocks || []) {
        const r = rockCollideRadius(t);
        const ddx = z.x - t.x, ddy = z.y - t.y, dd = Math.hypot(ddx, ddy);
        if (dd < r && dd > 1e-4) { z.x = t.x + ddx / dd * r; z.y = t.y + ddy / dd * r; }
      }
      for (const t of chunk.trees) {
        const r = treeCollideRadius(t) * 0.8;
        const ddx = z.x - t.x, ddy = z.y - t.y, dd = Math.hypot(ddx, ddy);
        if (dd < r && dd > 1e-4) { z.x = t.x + ddx / dd * r; z.y = t.y + ddy / dd * r; }
      }
    }
  }
}

// Анимация: клип Walk + поверх «зомби-поза»: руки тянутся вперёд (IK рук,
// та же функция, что у бойца), сутулость, голова набок. Ползёт — всё тело
// ложится лицом вниз, руки по очереди тянутся вперёд к земле и подтягивают.
// Мёртв — заваливается на спину. Оторванные конечности — кость в ноль.
const _zv = new THREE.Vector3(), _zf = new THREE.Vector3(), _zu = new THREE.Vector3();
function animateZombie(z, dt) {
  const B = z.bones;
  const moving = z.state !== 'dead' && z.attackT === 0;
  const walk = z.actions.Walk;
  // мёртвый — поза замирает (иначе ноги продолжали «шагать» лёжа)
  if (walk) walk.setEffectiveTimeScale(z.state === 'dead' ? 0 : z.state === 'crawl' ? 0.05 : (moving ? 0.55 : 0.15));
  z.mixer.update(dt);
  for (const [n, q] of Object.entries(z.toeRest)) B[n].quaternion.copy(q);

  // наклон всего тела
  z.crawlK += ((z.state === 'crawl' ? 1 : 0) - z.crawlK) * Math.min(1, 4 * dt);
  const f = z.state === 'dead' ? Math.min(1, z.fall * z.fall) : 0;
  const ck = z.crawlK;
  // ползком: лицом вниз (+90° вперёд), тело вытянуто по земле за точкой;
  // мёртвый: на спину (-90°)
  z.tilt.rotation.x = ck * 1.45 - f * 1.5;
  z.tilt.position.set(0, ck * 0.18 + f * 0.12, -ck * 0.75 + f * 0.7);

  if (z.state !== 'crawl') {
    if (B.Spine) B.Spine.rotateX(0.28 * (1 - f));
    if (B.Neck) B.Neck.rotateZ((0.35 + Math.sin(z.t * 1.3 + z.phase) * 0.08) * (1 - f));
    if (B.Head) B.Head.rotateX(0.15);
  } else {
    if (B.Head) B.Head.rotateX(-0.7);     // голову поднимает, смотрит вперёд
    // ноги прямые, волочатся; чуть раздвинуты и подрагивают
    for (const [n, q] of Object.entries(z.legRest)) {
      B[n].quaternion.slerp(q, z.crawlK);
    }
    if (B.LeftUpLeg) B.LeftUpLeg.rotateZ(0.12 + Math.sin(z.t * 2.4) * 0.05);
    if (B.RightUpLeg) B.RightUpLeg.rotateZ(-0.12 - Math.sin(z.t * 2.4 + 1) * 0.05);
  }

  if (z.state !== 'dead') {
    z.root.updateMatrixWorld(true);
    const fwd = _zf.set(0, 0, 1).applyQuaternion(z.root.quaternion);   // куда смотрит
    const up = _zu.set(0, 1, 0);
    ['Left', 'Right'].forEach((side, i) => {
      if (z.lost['arm' + side[0]] || !B[side + 'Arm'] || !B[side + 'Hand']) return;
      const sh = B[side + 'Arm'].getWorldPosition(new THREE.Vector3());
      const sideV = new THREE.Vector3().crossVectors(up, fwd).multiplyScalar(side === 'Left' ? 1 : -1);
      let target, pole;
      if (z.state === 'crawl') {
        // тянется вперёд к земле по очереди
        const k = Math.sin(z.t * 2.4 + i * Math.PI);
        target = sh.clone().addScaledVector(fwd, 0.45 + 0.2 * k).addScaledVector(up, -0.22 + 0.08 * Math.max(0, k)).addScaledVector(sideV, 0.12);
        pole = sh.clone().addScaledVector(up, 0.6).addScaledVector(sideV, 0.4);
      } else {
        // руки вперёд, чуть вниз; при атаке — взмахи
        const swipe = z.attackT > 0 ? Math.sin(z.attackT * 7 + i * Math.PI) : 0;
        target = sh.clone().addScaledVector(fwd, 0.5 + 0.1 * swipe).addScaledVector(up, -0.12 + 0.12 * swipe + Math.sin(z.t * 1.8 + i + z.phase) * 0.03).addScaledVector(sideV, 0.05);
        pole = sh.clone().addScaledVector(up, -0.8).addScaledVector(sideV, 0.4);
      }
      if (z.broken['arm' + side[0]]) target.addScaledVector(up, -0.45).addScaledVector(fwd, -0.3); // сломанная — висит
      solveArmIK(B[side + 'Arm'], B[side + 'ForeArm'], B[side + 'Hand'], target, pole);
    });
  }

  const cut = (name) => { const b = B[name]; if (b) b.scale.setScalar(0.0001); };
  if (z.lost.armL) cut('LeftArm');
  if (z.lost.armR) cut('RightArm');
  if (z.lost.legL) cut('LeftUpLeg');
  if (z.lost.legR) cut('RightUpLeg');

  z.root.rotation.y = z.yaw;
  z.model.traverse((n) => {
    if (n.isMesh && n.material.emissive) n.material.emissive.setRGB(z.hitFlash * 2.5, 0, 0);
  });
}

// Проверка попаданий (вызывается из weapon.js для каждой пули).
function bulletHitsZombie(b) {
  for (const z of zombies) {
    if (z.state === 'dead') continue;
    const r = z.state === 'crawl' ? ZOMBIE_HIT_R * 1.2 : ZOMBIE_HIT_R;
    // пуля за кадр пролетает до ~1.5 тайла — проверяем весь отрезок полёта
    const ax = b.px ?? b.x, ay = b.py ?? b.y;
    const sx = b.x - ax, sy = b.y - ay, sl = sx * sx + sy * sy || 1e-9;
    const t = Math.max(0, Math.min(1, ((z.x - ax) * sx + (z.y - ay) * sy) / sl));
    if (Math.hypot(ax + sx * t - z.x, ay + sy * t - z.y) > r) continue;
    damageZombie(z, b);
    return true;
  }
  return false;
}

function damageZombie(z, b) {
  // какая часть тела (лежачему в ноги почти не попасть — они дальше)
  let roll = Math.random(), hit = ZOMBIE_PARTS[1];
  for (const p of ZOMBIE_PARTS) { if (roll < p.p) { hit = p; break; } roll -= p.p; }
  if (z.lost[hit.part]) hit = ZOMBIE_PARTS[1];      // оторванная — пуля в корпус
  z.hp -= hit.dmg;
  z.hitFlash = 0.12;
  spawnBlood(z.x, z.y, b.dx, b.dy, hit.part === 'head' ? 4 : 2);
  const PART_RU = { head: 'ГОЛОВА', torso: 'КОРПУС', armL: 'РУКА', armR: 'РУКА', legL: 'НОГА', legR: 'НОГА' };
  let label = PART_RU[hit.part];

  if (hit.hp) {
    z.limbs[hit.part] -= hit.dmg + 8;
    if (z.limbs[hit.part] <= 0 && !z.lost[hit.part] && !z.broken[hit.part]) {
      const isLeg = hit.part.startsWith('leg');
      // рука: 55% отрывается, иначе повисает; нога: 40% отрывается, иначе ломается
      if (Math.random() < (isLeg ? 0.4 : 0.55)) {
        z.lost[hit.part] = true;
        spawnBlood(z.x, z.y, b.dx, b.dy, 6);
        addBloodDecal(z.x, z.y, 1.0);
        label = isLeg ? 'НОГА ОТОРВАНА' : 'РУКА ОТОРВАНА';
      } else {
        z.broken[hit.part] = true;
        label = isLeg ? 'НОГА СЛОМАНА' : 'РУКА СЛОМАНА';
      }
      if (isLeg && z.state === 'walk') z.state = 'crawl';
    }
  }
  if (z.hp <= 0 && z.state !== 'dead') {
    z.state = 'dead';
    addBloodDecal(z.x, z.y, 1.2);
    label = 'УБИТ';
  }
  // Подпись над зомби: куда попали (важные — крупнее и дольше).
  const big = label.includes(' ') || label === 'УБИТ';
  if (big || !z.labels.some((l) => l.age < 0.35)) {
    z.labels.push({ text: label, age: 0, life: big ? 1.6 : 0.6, big });
    if (z.labels.length > 4) z.labels.shift();
  }
}

// Кровь: брызги (частицы) по направлению пули + пятно на земле.
function spawnBlood(x, y, dx, dy, n) {
  for (let k = 0; k < n; k++) {
    const a = Math.atan2(dy, dx) + (Math.random() - 0.5) * 1.6;
    const sp = 0.6 + Math.random() * 1.8;
    weapon.puffs.push({
      kind: 'blood', x, y, z: 28 + Math.random() * 20,
      vx: Math.cos(a) * sp, vy: Math.sin(a) * sp,
      vz: 20 + Math.random() * 60, grav: 380,
      age: 0, life: 0.5 + Math.random() * 0.3, size: 1.2 + Math.random() * 1.6
    });
  }
  if (Math.random() < 0.25) addBloodDecal(x + dx * 0.3, y + dy * 0.3, 0.35 + Math.random() * 0.3);
}

function addBloodDecal(x, y, s) {
  bloodDecals.push({ x: x + (Math.random() - 0.5) * 0.3, y: y + (Math.random() - 0.5) * 0.3, s, rot: Math.random() * 6, age: 0 });
  if (bloodDecals.length > 25) bloodDecals.shift();
}

// Лужи крови — рисуются после земли, под всем остальным.
function drawBloodDecals(ctx) {
  for (const d of bloodDecals) {
    const p = toScreen(d.x, d.y);
    if (p.x < -40 || p.x > view.w + 40 || p.y < -40 || p.y > view.h + 40) continue;
    const a = Math.min(0.55, 0.55 * (14 - d.age) / 4);
    const r = 9 * d.s;
    ctx.save();
    ctx.translate(p.x, p.y);
    ctx.scale(1, TILE_H / TILE_W);
    ctx.rotate(d.rot);
    const g = ctx.createRadialGradient(0, 0, 0, 0, 0, r);
    g.addColorStop(0, `rgba(90, 8, 8, ${a})`);
    g.addColorStop(0.7, `rgba(70, 5, 5, ${a * 0.8})`);
    g.addColorStop(1, 'rgba(60, 0, 0, 0)');
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.ellipse(0, 0, r, r * 0.8, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }
}

function drawZombie(ctx, z) {
  const p = toScreen(z.x, z.y);
  if (p.x < -ZOMBIE_DRAW || p.x > view.w + ZOMBIE_DRAW || p.y < -ZOMBIE_DRAW || p.y > view.h + ZOMBIE_DRAW) return;
  zRenderer.render(z.scene, zCamera);
  const alpha = z.state === 'dead' && z.deadT > 9 ? Math.max(0, (12 - z.deadT) / 3) : 1;
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.drawImage(zRenderer.domElement, p.x - ZOMBIE_DRAW / 2, p.y - ZOMBIE_DRAW * ZOMBIE_BASE_FRAC, ZOMBIE_DRAW, ZOMBIE_DRAW);
  ctx.restore();

  // Полоска здоровья над головой (пока жив и уже ранен).
  const top = p.y - (z.state === 'walk' ? 78 : 34);
  if (z.state !== 'dead' && z.hp < ZOMBIE_HP) {
    const w = 34, k = Math.max(0, z.hp / ZOMBIE_HP);
    ctx.fillStyle = 'rgba(0,0,0,0.55)';
    ctx.fillRect(p.x - w / 2 - 1, top - 1, w + 2, 6);
    ctx.fillStyle = k > 0.5 ? '#6fcf4a' : k > 0.25 ? '#e0b030' : '#d04030';
    ctx.fillRect(p.x - w / 2, top, w * k, 4);
  }
  // Подписи попаданий: всплывают и тают.
  ctx.save();
  ctx.textAlign = 'center';
  z.labels.forEach((l, i) => {
    const t = l.age / l.life;
    ctx.globalAlpha = Math.max(0, 1 - t);
    ctx.font = `bold ${l.big ? 12 : 9}px sans-serif`;
    ctx.lineWidth = 3;
    ctx.strokeStyle = 'rgba(0,0,0,0.7)';
    ctx.fillStyle = l.big ? '#ffd24a' : '#ffffff';
    const y = top - 6 - t * 14 - (z.labels.length - 1 - i) * 13;  // новые снизу, не налезают
    ctx.strokeText(l.text, p.x, y);
    ctx.fillText(l.text, p.x, y);
  });
  ctx.restore();
}

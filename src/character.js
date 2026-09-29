// Survival Game: Character System (3D WebGL / Three.js + Procedural Soldier + GLTF Soldier.glb)
// Реалистичный персонаж в военной форме (камуфляж, шлем, берцы, разгрузочный жилет).
// Поворачивается на 360° во все стороны вслед за джойстиком, анимирует бег/ходьбу.
// Размер: ~78px (отлично видна экипировка, пропорционален деревьям ~250px).

// Тайл мира ≈ 1.4 м: так считаем реальную скорость бойца в м/с, чтобы шаги
// попадали в такт с землёй, уходящей из-под ног (иначе «катание на коньках»).
const METERS_PER_TILE = 1.39;
// Скорость, с которой стопа идёт назад по земле при обычном темпе клипов
// Soldier.glb (в клипах нет движения вперёд — они играют «на месте»).
// ИЗМЕРЕНО на модели (стопа в фазе опоры): ходьба ≈ 1.32 м/с, бег ≈ 2.83 м/с
// (клип бега — скорее трусца). Скорость игры подгоняется через timeScale.
const WALK_CLIP_MPS = 1.32;
const RUN_CLIP_MPS = 2.83;
// Порог переключения ходьба/бег с гистерезисом, чтобы не дёргалось на границе.
const GAIT_TEMPO = 0.7;
const RUN_ENTER_MPS = 2.4;
const RUN_EXIT_MPS = 2.0;
let charIsRunning = false;

const CHARACTER_DRAW_W = 90;
const CHARACTER_DRAW_H = 90;
// Доля высоты до подошв берцев в 3D (ортографическая камера, frustum 2.4, y=0)
// Точка земли под ногами в холсте бойца: центр кадра — точка (0, 0.85 м, 0),
// земля на 0.85·cos(наклона) ниже, в кадре высотой 2.4 м (+0.02 — подошвы).
const CHARACTER_BASE_FRAC = 0.5 + 0.85 * Math.cos(CAMERA_ELEV) / 2.4 + 0.0197;

let charCanvas = null;
let charRenderer = null;
let charScene = null;
let charCamera = null;
let soldierRoot = null;
let proceduralSoldier = null;
let gltfSoldier = null;
let charMixer = null;
let charActions = {};
let currentActionName = 'Idle';
let charYaw = 0;
let charRunPhase = 0;
let is3DInitialized = false;

// Оружие в руках (модель CC0: OpenGameArt «Flat Guns West» — Rifle_Assault).
// charAimBlend: 0 — автомат в положении «наготове» (у груди, стволом вниз-вперёд),
// 1 — приклад в плече, ствол горизонтально (стрельба).
let rifleRig = null;
let muzzleFlash = null;
let charAimBlend = 0;
let charRecoil = 0;
let charFlashT = 0;
// Прицел относительно ног (рад, + = против часовой, если смотреть сверху):
// корпус доворачивается до ±57°, дальше — руки выносят автомат вбок/назад.
// charBackFire: 0 — обычная стрельба, 1 — стрельба назад от бедра на бегу.
let charAimLocal = 0;
let charBackFire = 0;

// Инициализация Three.js и персонажа
function init3DCharacter() {
  if (typeof THREE === 'undefined') return false;

  try {
    charCanvas = document.createElement('canvas');
    charCanvas.width = 384;
    charCanvas.height = 384;

    charRenderer = new THREE.WebGLRenderer({
      canvas: charCanvas,
      alpha: true,
      antialias: true,
      preserveDrawingBuffer: true
    });
    charRenderer.setSize(384, 384);
    charRenderer.setClearColor(0x000000, 0);

    charScene = new THREE.Scene();

    // Изометрическая ортографическая камера под углом 2:1 (~26.56° к горизонту)
    const frustum = 2.4;
    charCamera = new THREE.OrthographicCamera(
      -frustum / 2, frustum / 2,
      frustum / 2, -frustum / 2,
      0.1, 50
    );
    // Камера смотрит под тем же углом, что и земля (CAMERA_ELEV из ground.js).
    charCamera.position.set(0, 5.6 * Math.sin(CAMERA_ELEV), 5.6 * Math.cos(CAMERA_ELEV));
    charCamera.lookAt(0, 0.85, 0);

    // Освещение: свет сверху-слева (согласован с деревьями и тенями мира)
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.75);
    charScene.add(ambientLight);

    const dirLight = new THREE.DirectionalLight(0xfffaed, 1.35);
    dirLight.position.set(-4, 7, 3);
    charScene.add(dirLight);

    const fillLight = new THREE.DirectionalLight(0x7a8b9e, 0.4);
    fillLight.position.set(3, 2, -2);
    charScene.add(fillLight);

    soldierRoot = new THREE.Group();
    charScene.add(soldierRoot);

    // 1. Сразу создаём процедурного 3D-бойца в военной форме (готов мгновенно)
    proceduralSoldier = createProceduralSoldier();
    soldierRoot.add(proceduralSoldier.group);

    // 2. Фоново подгружаем высокодетализированную модель Soldier.glb (Mixamo/Three.js)
    loadGLTFSoldier();

    is3DInitialized = true;
    return true;
  } catch (err) {
    console.warn('Three.js character init failed, using 2D fallback:', err);
    return false;
  }
}

// Процедурный 3D-боец в реалистичной военной экипировке
function createProceduralSoldier() {
  const group = new THREE.Group();

  // Материалы военной формы (олива, камуфляж, хаки, чёрная кожа)
  const matJacket = new THREE.MeshLambertMaterial({ color: 0x475535 }); // Оливково-зелёный китель
  const matVest = new THREE.MeshLambertMaterial({ color: 0x2e3922 });   // Тёмный бронежилет / разгрузка
  const matPants = new THREE.MeshLambertMaterial({ color: 0x3d472c });  // Камуфляжные штаны
  const matBoots = new THREE.MeshLambertMaterial({ color: 0x181816 });  // Чёрные армейские берцы
  const matSkin = new THREE.MeshLambertMaterial({ color: 0xdda885 });   // Кожа
  const matHelmet = new THREE.MeshLambertMaterial({ color: 0x3b4629 }); // Военный шлем
  const matGoggles = new THREE.MeshLambertMaterial({ color: 0x1f221e });// Резинка / очки на шлеме
  const matPack = new THREE.MeshLambertMaterial({ color: 0x333d25 });   // Тактический рюкзак
  const matRifle = new THREE.MeshLambertMaterial({ color: 0x222426 });  // Оружие / автомат

  // Торс и разгрузочный жилет
  const torso = new THREE.Mesh(new THREE.BoxGeometry(0.38, 0.52, 0.24), matJacket);
  torso.position.y = 0.95;
  group.add(torso);

  const vest = new THREE.Mesh(new THREE.BoxGeometry(0.40, 0.38, 0.28), matVest);
  vest.position.set(0, 0.98, 0);
  group.add(vest);

  // Тактический рюкзак за спиной (-Z)
  const backpack = new THREE.Mesh(new THREE.BoxGeometry(0.30, 0.36, 0.16), matPack);
  backpack.position.set(0, 1.0, -0.19);
  group.add(backpack);

  // Голова и военный шлем
  const head = new THREE.Mesh(new THREE.BoxGeometry(0.20, 0.20, 0.20), matSkin);
  head.position.y = 1.34;
  group.add(head);

  const helmet = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.14, 0.25), matHelmet);
  helmet.position.set(0, 1.41, 0);
  group.add(helmet);

  const goggles = new THREE.Mesh(new THREE.BoxGeometry(0.25, 0.05, 0.26), matGoggles);
  goggles.position.set(0, 1.39, 0.02);
  group.add(goggles);

  // Ноги (с суставами для ходьбы и бега, подошва на уровне земли Y = 0.00)
  const leftLeg = new THREE.Group();
  leftLeg.position.set(-0.10, 0.70, 0);
  const leftPants = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.50, 0.16), matPants);
  leftPants.position.y = -0.25;
  leftLeg.add(leftPants);
  const leftBoot = new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.18, 0.22), matBoots);
  leftBoot.position.set(0, -0.61, 0.03); // подошва на уровне земли Y = 0.00
  leftLeg.add(leftBoot);
  group.add(leftLeg);

  const rightLeg = new THREE.Group();
  rightLeg.position.set(0.10, 0.70, 0);
  const rightPants = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.50, 0.16), matPants);
  rightPants.position.y = -0.25;
  rightLeg.add(rightPants);
  const rightBoot = new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.18, 0.22), matBoots);
  rightBoot.position.set(0, -0.61, 0.03); // подошва на уровне земли Y = 0.00
  rightLeg.add(rightBoot);
  group.add(rightLeg);

  // Руки (с автоматом в положении готовности)
  const leftArm = new THREE.Group();
  leftArm.position.set(-0.25, 1.15, 0);
  const leftSleeve = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.44, 0.13), matJacket);
  leftSleeve.position.set(0, -0.22, 0.05);
  leftArm.add(leftSleeve);
  group.add(leftArm);

  const rightArm = new THREE.Group();
  rightArm.position.set(0.25, 1.15, 0);
  const rightSleeve = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.44, 0.13), matJacket);
  rightSleeve.position.set(0, -0.22, 0.05);
  rightArm.add(rightSleeve);
  group.add(rightArm);

  // Автомат на груди / в руках (+Z, смотрит вперёд)
  const rifle = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.12, 0.55), matRifle);
  rifle.position.set(0.08, 0.95, 0.22);
  rifle.rotation.x = -0.3;
  rifle.rotation.y = -0.2;
  group.add(rifle);

  return {
    group,
    leftLeg, rightLeg,
    leftArm, rightArm,
    rifle
  };
}

// Фоновая загрузка 3D-модели бойца (Soldier.glb из Three.js / Mixamo)
function loadGLTFSoldier() {
  if (typeof THREE.GLTFLoader === 'undefined') return;

  const loader = new THREE.GLTFLoader();
  const modelUrls = [
    'assets/character/Soldier.glb',
    'https://cdn.jsdelivr.net/gh/mrdoob/three.js@r128/examples/models/gltf/Soldier.glb',
    'https://raw.githubusercontent.com/mrdoob/three.js/r128/examples/models/gltf/Soldier.glb',
    'https://threejs.org/examples/models/gltf/Soldier.glb'
  ];

  function tryLoad(urlIndex) {
    if (urlIndex >= modelUrls.length) return;
    loader.load(
      modelUrls[urlIndex],
      (gltf) => {
        gltfSoldier = gltf.scene;

        // В Mixamo Soldier смотрит по умолчанию на -Z.
        // Поворачиваем на PI, чтобы смотрел на +Z (лицом к камере/вниз),
        // согласуя с процедурным бойцом.
        gltfSoldier.rotation.y = Math.PI;

        // Настройка размера и материалов под сцену
        const box = new THREE.Box3().setFromObject(gltfSoldier);
        const size = box.getSize(new THREE.Vector3());
        const targetH = 1.65;
        const scale = targetH / (size.y || 1.8);
        gltfSoldier.scale.set(scale, scale, scale);

        // Поправка базовой точки на уровень ног
        box.setFromObject(gltfSoldier);
        gltfSoldier.position.y = -box.min.y;

        gltfSoldier.traverse((child) => {
          if (child.isMesh) {
            child.castShadow = false;
            child.receiveShadow = false;
            if (child.material) {
              child.material.roughness = 0.8;
            }
          }
        });

        // Анимации: Idle, Walk, Run
        if (gltf.animations && gltf.animations.length) {
          charMixer = new THREE.AnimationMixer(gltfSoldier);
          charActions = {};
          gltf.animations.forEach((clip) => {
            const action = charMixer.clipAction(clip);
            charActions[clip.name] = action;
          });
          if (charActions['Idle']) {
            activeAction = charActions['Idle'];
            activeAction.play();
            currentActionName = 'Idle';
          }
        }

        // Заменяем процедурную модель на высокополигональную
        if (proceduralSoldier && proceduralSoldier.group) {
          soldierRoot.remove(proceduralSoldier.group);
        }
        soldierRoot.add(gltfSoldier);
        recolorSoldier(gltfSoldier);
        loadRifle();
      },
      undefined,
      () => {
        tryLoad(urlIndex + 1);
      }
    );
  }

  tryLoad(0);
}

// Плавный переход между анимациями
function fadeToAction(name, duration = 0.15) {
  if (!charActions || !charActions[name] || currentActionName === name) return;
  const prevAction = activeAction;
  activeAction = charActions[name];
  if (prevAction) {
    prevAction.fadeOut(duration);
  }
  activeAction.reset().fadeIn(duration).play();
  currentActionName = name;
}

// Обновление состояния персонажа каждый кадр (поворот на 360°, анимация бега)
function updateCharacter(dt, isMoving, angle, speed) {
  if (!is3DInitialized) {
    if (!init3DCharacter()) return;
  }

  // 1. Поворот на 360 градусов вслед за направлением джойстика
  // В изометрической камере (вид сверху 3/4):
  // angle: -PI/2 (вверх), PI/2 (вниз), 0 (вправо), PI (влево)
  // Модель смотрит на +Z (вниз экрана) при rotation.y = 0.
  // При движении вверх (angle = -PI/2): atan2(cos, sin) = atan2(0, -1) = PI (смотрит вверх).
  // При движении вниз (angle = PI/2): atan2(cos, sin) = atan2(0, 1) = 0 (смотрит вниз).
  const targetYaw = Math.atan2(Math.cos(angle), Math.sin(angle));
  // Прицел: угол между ногами (куда бежим) и направлением стрельбы.
  const firingNow = typeof weapon !== 'undefined' && weapon.firing;
  if (firingNow) {
    const aimYaw = Math.atan2(Math.cos(weapon.aimAngle), Math.sin(weapon.aimAngle));
    let rel = aimYaw - charYaw;
    while (rel < -Math.PI) rel += Math.PI * 2;
    while (rel > Math.PI) rel -= Math.PI * 2;
    // Строго назад: не перескакивать между «через левое» и «через правое» плечо.
    if (Math.abs(rel) > 2.9 && Math.abs(charAimLocal) > 1.5 && Math.sign(rel) !== Math.sign(charAimLocal)) {
      rel = Math.sign(charAimLocal) * Math.PI * 0.98;
    }
    charAimLocal += (rel - charAimLocal) * Math.min(1, 14 * dt);
  } else {
    charAimLocal += (0 - charAimLocal) * Math.min(1, 10 * dt);
  }
  const a = Math.abs(charAimLocal);
  charBackFire = Math.max(0, Math.min(1, (a - 1.55) / 0.55)); // от ~90° до ~120°
  let diff = targetYaw - charYaw;
  while (diff < -Math.PI) diff += Math.PI * 2;
  while (diff > Math.PI) diff -= Math.PI * 2;
  charYaw += diff * Math.min(1, 24 * dt);
  if (soldierRoot) {
    soldierRoot.rotation.y = charYaw;
  }

  // 2. Анимация бега и ходьбы
  if (isMoving) {
    // Реальная скорость по земле, м/с. Темп шагов считается из неё:
    // подошва, стоящая на земле, должна уходить назад ровно с той же
    // скоростью, с какой земля уходит из-под бойца.
    const mps = speed * METERS_PER_TILE;
    if (charIsRunning) { if (mps < RUN_EXIT_MPS) charIsRunning = false; }
    else if (mps > RUN_ENTER_MPS) charIsRunning = true;

    // Длина полного цикла шага (обе ноги), м: ходьба ~1.45, бег ~3.4,
    // между ними — плавно.
    const cycleLen = Math.min(3.4, Math.max(1.45, 1.45 + (mps - 1.4) * (3.4 - 1.45) / (4.8 - 1.4)));
    charRunPhase += (mps * dt / cycleLen) * Math.PI * 2;

    if (charMixer) {
      const clip = charIsRunning ? 'Run' : 'Walk';
      fadeToAction(clip, 0.12);
      const act = charActions[clip];
      if (act) {
        // GAIT_TEMPO < 1: руки и ноги двигаются спокойнее, чем «по физике»,
        // иначе выглядит как бег на тренажёре (немного скользит, но естественнее).
        const ts = GAIT_TEMPO * mps / (charIsRunning ? RUN_CLIP_MPS : WALK_CLIP_MPS);
        act.setEffectiveTimeScale(Math.min(1.3, Math.max(0.5, ts)));
      }
      charMixer.update(dt);
      applyRiflePose(dt, weapon.firing);
    } else if (proceduralSoldier) {
      // Размах ноги из условия «стопа стоит на земле»: в середине опоры
      // скорость стопы назад = скорости бега (A = длина цикла / (2π · длина ноги)).
      const amp = Math.min(0.9, cycleLen / (2 * Math.PI * 0.68));
      const swing = Math.sin(charRunPhase) * amp;
      proceduralSoldier.leftLeg.rotation.x = swing;
      proceduralSoldier.rightLeg.rotation.x = -swing;
      proceduralSoldier.leftArm.rotation.x = -swing * 0.7;
      proceduralSoldier.rightArm.rotation.x = swing * 0.7;
      proceduralSoldier.group.position.y = Math.abs(Math.sin(charRunPhase * 2)) * 0.04;
    }
  } else {
    charIsRunning = false;
    // В покое (Idle): ноги мгновенно упираются в землю, никакого скольжения
    charRunPhase = 0;
    if (charMixer) {
      fadeToAction('Idle', 0.15);
      charMixer.update(dt);
      applyRiflePose(dt, weapon.firing);
    } else if (proceduralSoldier) {
      proceduralSoldier.leftLeg.rotation.x = 0;
      proceduralSoldier.rightLeg.rotation.x = 0;
      proceduralSoldier.leftArm.rotation.x = 0;
      proceduralSoldier.rightArm.rotation.x = 0;
      proceduralSoldier.group.position.y = 0; // ноги стоят ровно на земле, без подпрыгиваний
    }
  }

  // Рендер 3D-персонажа в закадровый холст
  if (charRenderer && charScene && charCamera) {
    charRenderer.render(charScene, charCamera);
    updateMuzzleScreen();
  }
}

// Отрисовка персонажа на игровом холсте по координатам (screenX, screenY)
function drawCharacter(ctx, screenX, screenY) {
  const dw = CHARACTER_DRAW_W;
  const dh = CHARACTER_DRAW_H;

  if (is3DInitialized && charCanvas) {
    // Подошвы берцев 3D-бойца точно привязаны к уровню земли (screenY)
    ctx.drawImage(charCanvas, screenX - dw / 2, screenY - Math.round(dh * CHARACTER_BASE_FRAC), dw, dh);
  } else {
    // Запасной 2D-рендер бойца в военной форме, если Three.js ещё не загрузился
    drawFallback2DSoldier(ctx, screenX, screenY, player.angle, player.isMoving);
  }
}

// Запасной 2D-солдат в военной форме (камуфляж, шлем, берцы, поворот всего тела)
function drawFallback2DSoldier(ctx, screenX, screenY, angle, isMoving) {
  ctx.save();
  ctx.translate(screenX, screenY - 18); // подошвы берцев (6+12=18) касаются screenY
  // Вращаем всего бойца в сторону движения
  // По умолчанию фигура нарисована смотрящей вниз (angle = PI/2)
  ctx.rotate(angle - Math.PI / 2);

  // Анимация ног при беге
  const step = isMoving ? Math.sin(charRunPhase) * 6 : 0;

  // Берцы (ноги)
  ctx.fillStyle = '#1c1c1c';
  ctx.fillRect(-8, 6 + step, 6, 12);
  ctx.fillRect(2, 6 - step, 6, 12);

  // Камуфляжные штаны
  ctx.fillStyle = '#3e4a2e';
  ctx.fillRect(-9, -2, 7, 10);
  ctx.fillRect(2, -2, 7, 10);

  // Тактический рюкзак сзади (-Y)
  ctx.fillStyle = '#2c361e';
  ctx.fillRect(-7, -18, 14, 6);

  // Камуфляжный китель и бронежилет
  ctx.fillStyle = '#485735';
  ctx.fillRect(-12, -14, 24, 18);
  ctx.fillStyle = '#2d3822';
  ctx.fillRect(-9, -12, 18, 14);

  // Руки и автомат
  ctx.fillStyle = '#485735';
  ctx.beginPath();
  ctx.arc(-13, -4, 4.5, 0, Math.PI * 2);
  ctx.arc(13, -4, 4.5, 0, Math.PI * 2);
  ctx.fill();

  // Автомат в руках (направлен вперёд +Y)
  ctx.fillStyle = '#1e2022';
  ctx.fillRect(4, -8, 5, 20);

  // Голова и военный шлем
  ctx.fillStyle = '#3c482a';
  ctx.beginPath();
  ctx.arc(0, -2, 9, 0, Math.PI * 2);
  ctx.fill();
  ctx.strokeStyle = '#222a18';
  ctx.lineWidth = 1.5;
  ctx.stroke();

  // Очки / козырёк шлема спереди (+Y)
  ctx.fillStyle = '#1a1f14';
  ctx.fillRect(-5, 4, 10, 3);

  ctx.restore();
}


// Мixamo Vanguard приходит в ярко-оранжевой «скафандровой» текстуре. Сдвигаем
// оттенок в оливково-хаки, чтобы был похож на военную форму.
function recolorSoldier(root) {
  root.traverse((child) => {
    if (!child.isMesh || !child.material || !child.material.map) return;
    const img = child.material.map.image;
    if (!img || !img.width) return;
    try {
      const c = document.createElement('canvas');
      c.width = img.width; c.height = img.height;
      const g = c.getContext('2d');
      g.filter = 'hue-rotate(58deg) saturate(0.55) brightness(0.8)';
      g.drawImage(img, 0, 0);
      const tex = new THREE.CanvasTexture(c);
      tex.flipY = child.material.map.flipY;
      tex.encoding = child.material.map.encoding;
      tex.anisotropy = child.material.map.anisotropy;
      child.material.map = tex;
      child.material.needsUpdate = true;
    } catch (e) { /* остаётся исходная текстура */ }
  });
}

// ---------- Автомат в руках ----------
// Система координат «rifleRig»: +Z — куда смотрит боец, ствол вдоль +Z,
// начало — центр автомата. Размеры (м) измерены по модели:
const RIFLE_GRIP = new THREE.Vector3(0, -0.10, -0.125);   // пистолетная рукоятка
const RIFLE_HANDGUARD = new THREE.Vector3(0, -0.035, 0.15); // цевьё
const RIFLE_MUZZLE = new THREE.Vector3(0, 0.02, 0.37);

function loadRifle() {
  if (typeof THREE.GLTFLoader === 'undefined' || !soldierRoot) return;
  new THREE.GLTFLoader().load('assets/character/Rifle_Assault.glb', (gltf) => {
    rifleRig = new THREE.Group();
    const model = gltf.scene;
    model.rotation.y = Math.PI; // в файле ствол смотрит в -Z
    model.traverse((n) => {
      if (n.isMesh && n.material) {
        // Материалы модели почти чёрные («плоские» цвета) — чуть светлим,
        // иначе автомат сливается в пятно.
        n.material.color.offsetHSL(0, 0, 0.09);
      }
    });
    rifleRig.add(model);

    // Вспышка выстрела: короткий вытянутый вперёд язычок пламени с рваными
    // лучами (как на замедленной съёмке), а не круглый шар. Две плоскости
    // вдоль ствола (горизонтальная и вертикальная) + маленькая «звезда»
    // поперёк ствола. Каждый выстрел — случайный поворот и размер.
    const mk = (canvas) => new THREE.MeshBasicMaterial({
      map: new THREE.CanvasTexture(canvas), transparent: true,
      blending: THREE.AdditiveBlending, depthWrite: false, depthTest: false,
      side: THREE.DoubleSide
    });
    const sideMat = mk(makeFlashSideCanvas());
    const starMat = mk(makeFlashStarCanvas());
    muzzleFlash = new THREE.Group();
    const sideGeo = new THREE.PlaneGeometry(0.42, 0.16);
    sideGeo.translate(0.21, 0, 0); // начало язычка — у дульного среза
    const flatH = new THREE.Mesh(sideGeo, sideMat);
    flatH.rotation.set(-Math.PI / 2, 0, -Math.PI / 2); // лежит вдоль +Z
    const flatV = new THREE.Mesh(sideGeo, sideMat);
    flatV.rotation.set(0, -Math.PI / 2, 0);             // стоит вдоль +Z
    const star = new THREE.Mesh(new THREE.PlaneGeometry(0.17, 0.17), starMat);
    muzzleFlash.add(flatH, flatV, star);
    muzzleFlash.userData.star = star;
    muzzleFlash.position.copy(RIFLE_MUZZLE);
    muzzleFlash.visible = false;
    rifleRig.add(muzzleFlash);

    soldierRoot.add(rifleRig);
  }, undefined, () => { /* без автомата бойцу просто нечего держать */ });
}

// Вызывается из weapon.js при каждом выстреле: отдача и вспышка.
function characterShotFired() {
  charRecoil = 1;
  charFlashT = 0.035; // 1–2 кадра, как у настоящей вспышки
  if (muzzleFlash) {
    const k = 0.75 + Math.random() * 0.5;
    muzzleFlash.scale.set(k, k, 0.7 + Math.random() * 0.6);
    muzzleFlash.rotation.z = Math.random() * Math.PI;
    muzzleFlash.userData.star.rotation.z = Math.random() * Math.PI;
  }
}

// Текстура язычка пламени сбоку: яркое ядро у дула, дальше рваные лучи.
function makeFlashSideCanvas() {
  const c = document.createElement('canvas');
  c.width = 128;
  c.height = 48;
  const g = c.getContext('2d');
  const core = g.createRadialGradient(10, 24, 1, 10, 24, 22);
  core.addColorStop(0, 'rgba(255,255,235,1)');
  core.addColorStop(0.4, 'rgba(255,215,120,0.8)');
  core.addColorStop(1, 'rgba(255,140,40,0)');
  g.fillStyle = core;
  g.fillRect(0, 0, 40, 48);
  for (let i = 0; i < 7; i++) {
    const len = 50 + Math.random() * 70;
    const off = (Math.random() - 0.5) * 16;
    const w = 2 + Math.random() * 4;
    const lg = g.createLinearGradient(8, 0, 8 + len, 0);
    lg.addColorStop(0, 'rgba(255,245,200,0.9)');
    lg.addColorStop(0.5, 'rgba(255,170,60,0.55)');
    lg.addColorStop(1, 'rgba(255,110,20,0)');
    g.fillStyle = lg;
    g.beginPath();
    g.moveTo(8, 24 - w);
    g.lineTo(8 + len, 24 + off);
    g.lineTo(8, 24 + w);
    g.closePath();
    g.fill();
  }
  return c;
}

// Текстура вспышки поперёк ствола: маленькая пятилучевая звезда.
function makeFlashStarCanvas() {
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d');
  g.translate(32, 32);
  for (let i = 0; i < 5; i++) {
    g.rotate(Math.PI * 2 / 5 + (Math.random() - 0.5) * 0.4);
    const len = 18 + Math.random() * 12;
    const lg = g.createLinearGradient(0, 0, len, 0);
    lg.addColorStop(0, 'rgba(255,245,210,1)');
    lg.addColorStop(1, 'rgba(255,140,40,0)');
    g.fillStyle = lg;
    g.beginPath();
    g.moveTo(0, -3);
    g.lineTo(len, 0);
    g.lineTo(0, 3);
    g.fill();
  }
  const core = g.createRadialGradient(0, 0, 0, 0, 0, 8);
  core.addColorStop(0, 'rgba(255,255,240,1)');
  core.addColorStop(1, 'rgba(255,200,100,0)');
  g.fillStyle = core;
  g.fillRect(-8, -8, 16, 16);
  return c;
}

// Где на экране дульный срез и окно выброса гильз — считаем по настоящей
// 3D-модели после отрисовки кадра, чтобы пули и гильзы вылетали из
// автомата, а не из тела. Значения — смещения от точки игрока на земле:
// gx/gy — в тайлах мира (проекция точки на землю), lift — высота над
// землёй в экранных пикселях, dirX/dirY — куда смотрит ствол по земле,
// sideX/sideY — куда вылетают гильзы (вправо от ствола).
const RIFLE_PORT = new THREE.Vector3(0.02, 0.03, -0.02);
const charMuzzle = { ok: false, gx: 0, gy: 0, lift: 30, dirX: 1, dirY: 0 };
const charPort = { ok: false, gx: 0, gy: 0, lift: 30, sideX: 0, sideY: 1 };

function screenOffsetOf(v3) {
  const p = v3.clone().project(charCamera);
  return {
    x: (p.x + 1) / 2 * CHARACTER_DRAW_W - CHARACTER_DRAW_W / 2,
    y: (1 - p.y) / 2 * CHARACTER_DRAW_H - CHARACTER_DRAW_H * CHARACTER_BASE_FRAC
  };
}

// Экранное смещение (px) -> смещение по земле мира (тайлы): обратная
// изометрическая проекция toScreen().
function screenToWorldDelta(sx, sy) {
  const a = sx / (TILE_W / 2), b = sy / (TILE_H / 2);
  return { x: (a + b) / 2, y: (b - a) / 2 };
}

// Точка автомата -> положение на земле (тайлы) и высота над ней (px).
function locateOnScreen(localPoint, out) {
  const w = rifleRig.localToWorld(localPoint.clone());
  const top = screenOffsetOf(w);
  const ground = screenOffsetOf(new THREE.Vector3(w.x, 0, w.z));
  const d = screenToWorldDelta(ground.x, ground.y);
  out.gx = d.x;
  out.gy = d.y;
  out.lift = ground.y - top.y;
  return w;
}

// Направление по земле мира от точки автомата вдоль локального вектора.
function groundDirOf(localPoint, localDir) {
  const a = rifleRig.localToWorld(localPoint.clone());
  const b = rifleRig.localToWorld(localPoint.clone().add(localDir));
  const s0 = screenOffsetOf(new THREE.Vector3(a.x, 0, a.z));
  const s1 = screenOffsetOf(new THREE.Vector3(b.x, 0, b.z));
  const d = screenToWorldDelta(s1.x - s0.x, s1.y - s0.y);
  const l = Math.hypot(d.x, d.y);
  return l > 1e-4 ? { x: d.x / l, y: d.y / l } : null;
}

function updateMuzzleScreen() {
  if (!rifleRig || !charCamera) { charMuzzle.ok = charPort.ok = false; return; }
  rifleRig.updateMatrixWorld(true);
  locateOnScreen(RIFLE_MUZZLE, charMuzzle);
  const fwd = groundDirOf(RIFLE_MUZZLE, new THREE.Vector3(0, 0, 1));
  if (fwd) { charMuzzle.dirX = fwd.x; charMuzzle.dirY = fwd.y; }
  charMuzzle.ok = true;

  locateOnScreen(RIFLE_PORT, charPort);
  // Окно выброса у этой (AR-подобной) винтовки справа: в модели,
  // повёрнутой на 180°, «право» — это локальный -X.
  const side = groundDirOf(RIFLE_PORT, new THREE.Vector3(-1, 0, 0));
  if (side) { charPort.sideX = side.x; charPort.sideY = side.y; }
  charPort.ok = true;
}

const _v1 = new THREE.Vector3(), _v2 = new THREE.Vector3(), _v3 = new THREE.Vector3();
const _q1 = new THREE.Quaternion(), _q2 = new THREE.Quaternion(), _q3 = new THREE.Quaternion();

// Двухсуставный IK руки: плечо -> локоть -> кисть дотягивается до target
// (мировые координаты), локоть уходит в сторону pole. Кости Mixamo смотрят
// вдоль своей оси Y, поэтому достаточно довернуть кость на кратчайший угол.
function solveArmIK(upper, fore, hand, target, pole) {
  upper.updateWorldMatrix(true, true);
  const a = upper.getWorldPosition(new THREE.Vector3());
  const e0 = fore.getWorldPosition(new THREE.Vector3());
  const h0 = hand.getWorldPosition(new THREE.Vector3());
  const l1 = a.distanceTo(e0), l2 = e0.distanceTo(h0);

  const toT = target.clone().sub(a);
  const dist = Math.min(Math.max(toT.length(), 0.05), l1 + l2 - 1e-4);
  const dir = toT.normalize();
  const cosA = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist);
  const sinA = Math.sqrt(Math.max(0, 1 - cosA * cosA));
  const pv = pole.clone().sub(a);
  pv.addScaledVector(dir, -pv.dot(dir));
  if (pv.lengthSq() < 1e-8) pv.set(0, -1, 0);
  pv.normalize();
  const elbow = a.clone().addScaledVector(dir, l1 * cosA).addScaledVector(pv, l1 * sinA);
  const handPos = a.clone().addScaledVector(dir, dist);

  const rotateBoneTo = (bone, from, toDir) => {
    bone.updateWorldMatrix(true, false);
    const curDir = fromDirOfBone(bone, from);
    const wq = bone.getWorldQuaternion(new THREE.Quaternion());
    const delta = new THREE.Quaternion().setFromUnitVectors(curDir, toDir);
    wq.premultiply(delta);
    const pq = bone.parent.getWorldQuaternion(new THREE.Quaternion());
    bone.quaternion.copy(pq.invert().multiply(wq));
    bone.updateWorldMatrix(false, true);
  };
  const fromDirOfBone = (bone, childBone) =>
    childBone.getWorldPosition(new THREE.Vector3()).sub(bone.getWorldPosition(new THREE.Vector3())).normalize();

  rotateBoneTo(upper, fore, elbow.clone().sub(a).normalize());
  rotateBoneTo(fore, hand, handPos.clone().sub(fore.getWorldPosition(new THREE.Vector3())).normalize());
}

let _bones = null;
function findBones() {
  if (_bones || !gltfSoldier) return _bones;
  const b = {};
  gltfSoldier.traverse((n) => { if (n.isBone) b[n.name.replace('mixamorig', '')] = n; });
  _bones = b;
  return b;
}

// Кладёт автомат в позу и тянет к нему обе руки. Вызывается после
// charMixer.update(): анимация ног/корпуса остаётся от клипа, руки — IK.
function applyRiflePose(dt, wantAim) {
  if (!rifleRig || !gltfSoldier) return;
  const B = findBones();
  if (!B.Spine2 || !B.RightArm || !B.LeftArm) return;

  charAimBlend += ((wantAim ? 1 : 0) - charAimBlend) * Math.min(1, 9 * dt);
  charRecoil = Math.max(0, charRecoil - dt * 14);
  charFlashT = Math.max(0, charFlashT - dt);
  if (muzzleFlash) muzzleFlash.visible = charFlashT > 0;

  soldierRoot.updateMatrixWorld(true);
  const chest = soldierRoot.worldToLocal(B.Spine2.getWorldPosition(_v1.clone()));
  const sideR = Math.sign(soldierRoot.worldToLocal(B.RightArm.getWorldPosition(_v2.clone())).x) || 1;

  // Поворот корпуса к цели: три позвонка делят доворот до ±57°.
  const twist = Math.max(-1.0, Math.min(1.0, charAimLocal));
  B.Spine.rotateY(twist * 0.3);
  if (B.Spine1) B.Spine1.rotateY(twist * 0.35);
  B.Spine2.rotateY(twist * 0.35);
  soldierRoot.updateMatrixWorld(true);
  const chest2 = soldierRoot.worldToLocal(B.Spine2.getWorldPosition(new THREE.Vector3()));

  // Позы (в системе бойца, относительно груди): готовность и стрельба.
  // Всё поворачиваем на угол прицела вокруг груди. Стрельба назад (bf):
  // автомат ниже, у бедра, вынесен вбок, чуть стволом вниз — так человек
  // на бегу отстреливается назад через плечо.
  const k = charAimBlend;
  const bf = charBackFire;
  const cx = sideR * (0.05 + 0.04 * k) * (1 - bf);
  const cy = -0.21 + 0.31 * k - 0.2 * bf;
  const cz = (0.26 + 0.07 * k - 0.035 * charRecoil) * (1 - 0.35 * bf);
  const ay = charAimLocal;
  const lateral = Math.sign(Math.sin(ay) || ay || 1) * 0.24 * bf;
  const px = cx * Math.cos(ay) + cz * Math.sin(ay) + lateral * Math.cos(ay);
  const pz = -cx * Math.sin(ay) + cz * Math.cos(ay) - lateral * Math.sin(ay);
  rifleRig.position.set(chest2.x + px, chest2.y + cy, chest2.z + pz);
  const pitch = 0.42 * (1 - k) - 0.03 * charRecoil * (1 + 2 * bf) + 0.12 * bf; // + = ствол вниз
  const yaw = -sideR * 0.22 * (1 - k) * (1 - bf) + ay;
  rifleRig.rotation.set(pitch, yaw, 0, 'YXZ');
  rifleRig.updateMatrixWorld(true);

  const gripW = rifleRig.localToWorld(RIFLE_GRIP.clone());
  const guardW = rifleRig.localToWorld(RIFLE_HANDGUARD.clone());
  const down = new THREE.Vector3(0, -1, 0);
  const poleR = B.RightArm.getWorldPosition(new THREE.Vector3())
    .add(soldierRoot.localToWorld(new THREE.Vector3(sideR * 0.5, -1, -0.5)).sub(soldierRoot.localToWorld(new THREE.Vector3())));
  const poleL = B.LeftArm.getWorldPosition(new THREE.Vector3())
    .add(soldierRoot.localToWorld(new THREE.Vector3(-sideR * 0.5, -1, -0.3)).sub(soldierRoot.localToWorld(new THREE.Vector3())));

  solveArmIK(B.RightArm, B.RightForeArm, B.RightHand, gripW, poleR);
  // Назад одной рукой: левая рука не тянется к цевью (не достанет) —
  // остаётся как в анимации бега.
  if (bf < 0.5) solveArmIK(B.LeftArm, B.LeftForeArm, B.LeftHand, guardW, poleL);
}

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

const CHARACTER_DRAW_W = 78;
const CHARACTER_DRAW_H = 78;
// Доля высоты до подошв берцев в 3D (ортографическая камера, frustum 2.4, y=0)
const CHARACTER_BASE_FRAC = 0.8363;

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
    charCamera.position.set(0, 2.5, 5.0);
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

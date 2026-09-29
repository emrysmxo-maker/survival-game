// Тестовая 3D-сцена для подбора угла камеры (camera-test.html).
// Деревья — те же модели Polyy.AI (CC0), что отрисованы в спрайты игры,
// но сжатые (assets/test3d/*.glb). Боец — Soldier.glb с автоматом.
// Камера вращается вокруг бойца: наклон (над землёй), поворот (вокруг),
// расстояние и угол обзора (0 = ортографическая, как в игре).

const TREE_MODELS = [
  { file: 'tree_16_ponderosa_pine.glb', h: 14 },
  { file: 'tree_06_norway_spruce.glb', h: 14 },
  { file: 'tree_28_grand_fir.glb', h: 13 },
  { file: 'tree_12_oak_green.glb', h: 11 },
  { file: 'tree_07_birch_cluster.glb', h: 12 },
  { file: 'tree_09_round_green.glb', h: 10.5 }
];
const TREE_COUNT = 55;
const FOREST_RADIUS = 30;      // м
const CLEARING_RADIUS = 2.2;   // м — поляна вокруг бойца
// «Как в игре»: наклон ~49° (asin(48/64)), поворот 45° (изометрия),
// ортографическая камера, в кадре по ширине ~12.7 м (как на телефоне).
const GAME_VIEW = { pitch: 49, yaw: 45, dist: 13, fov: 0 };

const cam = Object.assign({}, GAME_VIEW);
const clock = new THREE.Clock();
let fog, renderer, scene, persp, ortho, sun, soldier, mixer, actions = {}, rifle;
let walking = false, walkAngle = 0;
const target = new THREE.Vector3(0, 1.0, 0);

function init() {
  renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.outputEncoding = THREE.sRGBEncoding;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  document.body.appendChild(renderer.domElement);

  scene = new THREE.Scene();
  scene.background = new THREE.Color(0xa9c4d8);
  fog = new THREE.Fog(0xa9c4d8, 45, 110);
  scene.fog = fog;

  persp = new THREE.PerspectiveCamera(40, 1, 0.1, 400);
  ortho = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 400);

  scene.add(new THREE.HemisphereLight(0xdfe9ff, 0x4a4030, 0.85));
  sun = new THREE.DirectionalLight(0xfff2d8, 1.5);
  sun.castShadow = true;
  sun.shadow.mapSize.set(1024, 1024);
  Object.assign(sun.shadow.camera, { left: -30, right: 30, top: 30, bottom: -30, near: 1, far: 120 });
  sun.shadow.bias = -0.0005;
  scene.add(sun, sun.target);

  // Земля: та же фототекстура травы, что в игре.
  const tex = new THREE.TextureLoader().load('assets/ground/grass.jpg');
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.repeat.set(200 / 4.4, 200 / 4.4);
  tex.encoding = THREE.sRGBEncoding;
  tex.anisotropy = renderer.capabilities.getMaxAnisotropy();
  const ground = new THREE.Mesh(new THREE.PlaneGeometry(200, 200), new THREE.MeshLambertMaterial({ map: tex }));
  ground.rotation.x = -Math.PI / 2;
  ground.receiveShadow = true;
  scene.add(ground);

  loadAll().then(() => {
    document.getElementById('loading').style.display = 'none';
  });

  setupUI();
  setupTouch();
  window.addEventListener('resize', onResize);
  onResize();
  renderer.setAnimationLoop(frame);
}

function loadGlb(url) {
  return new Promise((res, rej) => new THREE.GLTFLoader().load(url, res, undefined, rej));
}

// Простая детерминированная «случайность», чтобы лес был одинаковым.
let seed = 12345;
function rnd() { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; }

async function loadAll() {
  const models = await Promise.all(TREE_MODELS.map((m) => loadGlb('assets/test3d/' + m.file)));
  const protos = models.map((g, i) => {
    const root = g.scene;
    root.traverse((n) => {
      if (n.isMesh) { n.castShadow = true; n.receiveShadow = true; if (n.material) n.material.side = THREE.DoubleSide; }
    });
    const bb = new THREE.Box3().setFromObject(root);
    const size = bb.getSize(new THREE.Vector3()), c = bb.getCenter(new THREE.Vector3());
    const s = TREE_MODELS[i].h / size.y;
    const holder = new THREE.Group();
    root.scale.setScalar(s);
    root.position.set(-c.x * s, -bb.min.y * s, -c.z * s);
    holder.add(root);
    return holder;
  });
  const placed = [];
  let tries = 0;
  while (placed.length < TREE_COUNT && tries++ < 4000) {
    const a = rnd() * Math.PI * 2, r = CLEARING_RADIUS + Math.sqrt(rnd()) * FOREST_RADIUS;
    const x = Math.cos(a) * r, z = Math.sin(a) * r;
    if (placed.some((p) => Math.hypot(p.x - x, p.z - z) < 3.2)) continue;
    const t = protos[Math.floor(rnd() * protos.length)].clone(true);
    t.position.set(x, 0, z);
    t.rotation.y = rnd() * Math.PI * 2;
    t.scale.setScalar(0.85 + rnd() * 0.3);
    scene.add(t);
    placed.push({ x, z });
  }

  // Боец
  const sg = await loadGlb('assets/character/Soldier.glb');
  soldier = sg.scene;
  soldier.traverse((n) => { if (n.isMesh) { n.castShadow = true; n.receiveShadow = true; } });
  const bb = new THREE.Box3().setFromObject(soldier);
  soldier.scale.setScalar(1.8 / bb.getSize(new THREE.Vector3()).y);
  soldier.rotation.y = Math.PI;
  const holder = new THREE.Group();
  holder.add(soldier);
  scene.add(holder);
  soldier = holder;
  mixer = new THREE.AnimationMixer(sg.scene);
  sg.animations.forEach((clip) => { actions[clip.name] = mixer.clipAction(clip); });
  if (actions.Idle) actions.Idle.play();
  recolor(sg.scene);

  // Автомат: держим у груди стволом вперёд-вниз (как «наготове» в игре).
  try {
    const rg = await loadGlb('assets/character/Rifle_Assault.glb');
    rifle = rg.scene;
    rifle.traverse((n) => { if (n.isMesh) { n.castShadow = true; n.material.color.offsetHSL(0, 0, 0.09); } });
    const bbR = new THREE.Box3().setFromObject(rifle);
    rifle.scale.setScalar(0.8 / bbR.getSize(new THREE.Vector3()).z);
    rifle.rotation.set(0.35, Math.PI, 0);
    rifle.position.set(0.1, 1.12, 0.3);
    soldier.add(rifle);
  } catch (e) { /* без автомата — не страшно для теста */ }
}

// Та же перекраска формы в хаки, что в игре (character.js).
function recolor(root) {
  root.traverse((child) => {
    if (!child.isMesh || !child.material || !child.material.map) return;
    const img = child.material.map.image;
    if (!img || !img.width) return;
    const c = document.createElement('canvas');
    c.width = img.width; c.height = img.height;
    const g = c.getContext('2d');
    g.filter = 'hue-rotate(58deg) saturate(0.55) brightness(0.8)';
    g.drawImage(img, 0, 0);
    const tex = new THREE.CanvasTexture(c);
    tex.flipY = child.material.map.flipY;
    tex.encoding = child.material.map.encoding;
    child.material.map = tex;
    child.material.needsUpdate = true;
  });
}

function setAction(name) {
  if (!actions[name]) return;
  Object.entries(actions).forEach(([n, a]) => { if (n !== name) a.fadeOut(0.2); });
  actions[name].reset().fadeIn(0.2).play();
}

// ---------- Камера ----------
function updateCamera() {
  const p = THREE.MathUtils.degToRad(cam.pitch), y = THREE.MathUtils.degToRad(cam.yaw);
  const dir = new THREE.Vector3(Math.cos(p) * Math.sin(y), Math.sin(p), Math.cos(p) * Math.cos(y));
  const aspect = window.innerWidth / window.innerHeight;
  let camera;
  if (cam.fov <= 0) {
    // Ортографическая: dist = ширина кадра в метрах.
    const hw = cam.dist / 2, hh = hw / aspect;
    Object.assign(ortho, { left: -hw, right: hw, top: hh, bottom: -hh });
    ortho.updateProjectionMatrix();
    ortho.position.copy(target).addScaledVector(dir, 80);
    scene.fog = null; // туман считается от камеры — в орто она далеко
    camera = ortho;
  } else {
    persp.fov = cam.fov;
    persp.aspect = aspect;
    persp.updateProjectionMatrix();
    persp.position.copy(target).addScaledVector(dir, cam.dist);
    scene.fog = fog;
    camera = persp;
  }
  camera.up.set(0, 1, 0);
  if (cam.pitch >= 89.5) camera.up.set(-Math.sin(y), 0, -Math.cos(y)); // строго сверху
  camera.lookAt(target);

  sun.position.copy(target).add(new THREE.Vector3(-18, 30, 12));
  sun.target.position.copy(target);

  const mode = cam.fov <= 0 ? 'орто (как в игре)' : `перспектива ${cam.fov}°`;
  document.getElementById('angle-text').textContent =
    `Наклон ${cam.pitch}° · Поворот ${cam.yaw}° · ${cam.fov <= 0 ? 'Кадр' : 'Расст.'} ${cam.dist} м · ${mode}`;
  syncSliders();
  return camera;
}

function frame() {
  const dt = Math.min(clock.getDelta(), 0.1);
  if (soldier && walking) {
    walkAngle += dt * 1.4 / 4;                  // 1.4 м/с по кругу радиусом 4 м
    soldier.position.set(Math.cos(walkAngle) * 4, 0, Math.sin(walkAngle) * 4);
    soldier.rotation.y = -walkAngle;            // лицом по ходу движения
  }
  if (soldier) target.set(soldier.position.x, 1.0, soldier.position.z);
  if (mixer) mixer.update(dt);
  renderer.render(scene, updateCamera());
}

function onResize() {
  renderer.setSize(window.innerWidth, window.innerHeight);
}

// ---------- Управление ----------
const ids = ['pitch', 'yaw', 'dist', 'fov'];
function syncSliders() {
  ids.forEach((k) => {
    const el = document.getElementById(k);
    if (document.activeElement !== el) el.value = cam[k];
    document.getElementById('v-' + k).textContent =
      k === 'fov' ? (cam.fov <= 0 ? 'орто' : cam.fov + '°') : k === 'dist' ? cam.dist + ' м' : cam[k] + '°';
  });
}

function setupUI() {
  ids.forEach((k) => {
    document.getElementById(k).addEventListener('input', (e) => { cam[k] = Number(e.target.value); });
  });
  document.getElementById('btn-game').onclick = () => Object.assign(cam, GAME_VIEW);
  const walkBtn = document.getElementById('btn-walk');
  walkBtn.onclick = () => {
    walking = !walking;
    walkBtn.textContent = walking ? 'Боец: идёт' : 'Боец: стоит';
    setAction(walking ? 'Walk' : 'Idle');
  };
  const panel = document.getElementById('panel'), show = document.getElementById('btn-show');
  document.getElementById('btn-panel').onclick = () => { panel.style.display = 'none'; show.style.display = 'block'; };
  show.onclick = () => { panel.style.display = 'block'; show.style.display = 'none'; };
}

function setupTouch() {
  const el = renderer.domElement;
  let last = null, pinch = null;
  const clampPitch = (v) => Math.max(5, Math.min(90, v));
  el.addEventListener('touchstart', (e) => {
    e.preventDefault();
    if (e.touches.length === 1) last = { x: e.touches[0].clientX, y: e.touches[0].clientY };
    if (e.touches.length === 2) {
      pinch = Math.hypot(e.touches[0].clientX - e.touches[1].clientX, e.touches[0].clientY - e.touches[1].clientY);
      last = null;
    }
  }, { passive: false });
  el.addEventListener('touchmove', (e) => {
    e.preventDefault();
    if (e.touches.length === 1 && last) {
      const t = e.touches[0];
      cam.yaw = Math.round(((cam.yaw - (t.clientX - last.x) * 0.4) % 360 + 360) % 360);
      cam.pitch = Math.round(clampPitch(cam.pitch + (t.clientY - last.y) * 0.3));
      last = { x: t.clientX, y: t.clientY };
    } else if (e.touches.length === 2 && pinch) {
      const d = Math.hypot(e.touches[0].clientX - e.touches[1].clientX, e.touches[0].clientY - e.touches[1].clientY);
      cam.dist = Math.round(Math.max(4, Math.min(60, cam.dist * pinch / d)));
      pinch = d;
    }
  }, { passive: false });
  el.addEventListener('touchend', () => { last = null; pinch = null; });

  // Мышь (для ПК): перетаскивание — вращение, колесо — расстояние.
  let drag = null;
  el.addEventListener('mousedown', (e) => { drag = { x: e.clientX, y: e.clientY }; });
  window.addEventListener('mouseup', () => { drag = null; });
  window.addEventListener('mousemove', (e) => {
    if (!drag) return;
    cam.yaw = Math.round(((cam.yaw - (e.clientX - drag.x) * 0.4) % 360 + 360) % 360);
    cam.pitch = Math.round(clampPitch(cam.pitch + (e.clientY - drag.y) * 0.3));
    drag = { x: e.clientX, y: e.clientY };
  });
  el.addEventListener('wheel', (e) => {
    cam.dist = Math.round(Math.max(4, Math.min(60, cam.dist * (e.deltaY > 0 ? 1.1 : 0.9))));
  });
}

init();

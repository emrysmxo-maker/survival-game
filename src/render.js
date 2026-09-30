// Вся отрисовка: земля, деревья, лесной мусор, персонаж, джойстик и виньетка.
// Опирается на данные из world.js (чанки), player.js (координаты), input.js
// (джойстик) и assets.js (картинки).

// Земля каждого чанка «запекается» в картинку один раз (код — src/ground.js)
// и потом просто рисуется drawImage. Запекание идёт в фоновом потоке
// (src/ground-worker.js): на телефоне один чанк готовится до ~0.2 с, и в
// основном потоке это было заметным рывком при переходе в новый участок.
// Если браузер не умеет OffscreenCanvas в потоке — запекаем по одному чанку
// за кадр прямо в игре, как раньше.

function groundTexturesReady() {
  return groundImages.every((img) => img.complete && img.naturalWidth);
}

const groundBake = { started: false, worker: null, ready: false, inFlight: new Set(), local: null };

function startGroundBaking() {
  groundBake.started = true;
  if (window.Worker && window.OffscreenCanvas && window.createImageBitmap) {
    try {
      const w = new Worker(`src/ground-worker.js?v=${ASSET_VERSION}`);
      w.onmessage = (e) => {
        const { key, bitmap, cropTop, hi, light } = e.data;
        groundBake.inFlight.delete(key + (hi ? ':H' : ':L'));
        const chunk = loadedChunks.get(key);
        if (!chunk) { bitmap.close(); return; }
        if (chunk.groundPrev && chunk.groundPrev.close) chunk.groundPrev.close();
        chunk.groundPrev = null;
        if (chunk.ground && hi) {
          // грубая земля остаётся снизу, чёткая проявляется поверх за ~0.45 с —
          // без «щелчка» (был заметен как «что-то меняется под ногами»)
          chunk.groundPrev = chunk.ground; chunk.groundPrevScale = chunk.groundScale;
          chunk.groundPrevOrigin = chunk.groundOrigin; chunk.groundFadeT0 = performance.now();
        } else if (chunk.ground && chunk.ground.close) {
          chunk.ground.close();
        }
        if (chunk.groundLight) chunk.groundLight.forEach((b) => b && b.close && b.close());
        chunk.groundLight = light;
        chunk.ground = bitmap;
        chunk.groundScale = hi ? GROUND_BAKE_SCALE : GROUND_LO_SCALE;
        chunk.groundOrigin = chunkBakeOrigin(chunk.cx, chunk.cy);
        chunk.groundOrigin.y += cropTop || 0;
      };
      w.onerror = () => { groundBake.worker = null; groundBake.ready = false; groundBake.inFlight.clear(); };
      groundBake.worker = w;
      Promise.all(groundImages.map((img) => createImageBitmap(img))).then((textures) => {
        w.postMessage({ type: 'init', textures }, textures);
        groundBake.ready = true;
      }).catch(() => { groundBake.worker = null; });
      return;
    } catch (e) {
      groundBake.worker = null;
    }
  }
}

function localBake(chunk, hi) {
  groundBake.localBakers = groundBake.localBakers || {};
  const S = hi ? GROUND_BAKE_SCALE : GROUND_LO_SCALE;
  if (!groundBake.localBakers[S]) {
    groundBake.localBakers[S] = createGroundBaker((w, h) => {
      const c = document.createElement('canvas');
      c.width = w;
      c.height = h;
      return c;
    }, groundImages, S);
  }
  chunk.ground = groundBake.localBakers[S](chunk.cx, chunk.cy);
  chunk.groundLight = chunk.ground.light;
  chunk.groundScale = S;
  chunk.groundOrigin = chunkBakeOrigin(chunk.cx, chunk.cy);
  chunk.groundOrigin.y += chunk.ground.cropTop || 0;
}

function drawGround() {
  const W = view.w, H = view.h;
  // Та же камера, что в toScreen() — см. комментарий в player.js.
  const camX = renderCam.x - W / 2;
  const camY = renderCam.y - H / 2;
  const pcx = Math.floor(player.x / CHUNK_SIZE);
  const pcy = Math.floor(player.y / CHUNK_SIZE);

  ctx.fillStyle = GROUND_BASE_COLOR;
  ctx.fillRect(0, 0, W, H);

  if (groundTexturesReady()) {
    if (!groundBake.started) startGroundBaking();
    // Два уровня земли: грубая (быстро, заранее, далеко от экрана) и чёткая
    // (только вблизи экрана). Так на экран никогда не выезжает незапечённый
    // кусок (плоское зелёное пятно), а память не раздувается.
    const pending = [];
    const distToScreen = (chunk) => {
      const go = chunkBakeOrigin(chunk.cx, chunk.cy);
      const gx = go.x - camX, gy = go.y - camY;
      const dx = Math.max(-GROUND_CHUNK_CSS_W - gx, gx - W, 0), dy = Math.max(-GROUND_CHUNK_CSS_H - gy, gy - H, 0);
      return Math.max(dx, dy);
    };
    for (const [key, chunk] of loadedChunks.entries()) {
      const d = Math.max(Math.abs(chunk.cx - pcx), Math.abs(chunk.cy - pcy));
      const ds = distToScreen(chunk);
      if (d > GROUND_BAKE_KEEP_RADIUS || ds > GROUND_MARGIN_LO) {
        if (chunk.ground && chunk.ground.close) chunk.ground.close();
        if (chunk.groundPrev && chunk.groundPrev.close) chunk.groundPrev.close();
        if (chunk.groundLight) chunk.groundLight.forEach((b) => b && b.close && b.close());
        chunk.ground = null; chunk.groundPrev = null; chunk.groundLight = null;
        continue;
      }
      if (!chunk.ground) {
        if (!groundBake.inFlight.has(key + ':L')) pending.push([0, ds, key, chunk, false]);
      } else if (chunk.groundScale !== GROUND_BAKE_SCALE && ds < GROUND_MARGIN_HI) {
        if (!groundBake.inFlight.has(key + ':H')) pending.push([1, ds, key, chunk, true]);
      } else if (chunk.groundScale === GROUND_BAKE_SCALE && ds > GROUND_MARGIN_HI_KEEP) {
        if (!groundBake.inFlight.has(key + ':L')) pending.push([2, ds, key, chunk, false]);
      }
    }
    pending.sort((p, q) => (p[0] - q[0]) || (p[1] - q[1]));
    if (groundBake.worker) {
      if (groundBake.ready) {
        for (const [, , key, chunk, hi] of pending) {
          if (groundBake.inFlight.size >= GROUND_MAX_IN_FLIGHT) break;
          groundBake.inFlight.add(key + (hi ? ':H' : ':L'));
          groundBake.worker.postMessage({ type: 'bake', key, cx: chunk.cx, cy: chunk.cy, hi });
        }
      }
    } else if (pending.length) {
      localBake(pending[0][3], pending[0][4]);
    }
  }

  // От дальних чанков к ближним: сдвинутая рельефом земля ближнего перекрывает дальний.
  const drawList = [];
  for (const chunk of loadedChunks.values()) if (chunk.ground) drawList.push(chunk);
  drawList.sort((p, q) => (p.cx + p.cy) - (q.cx + q.cy));
  for (const chunk of drawList) {
    const x = chunk.groundOrigin.x - camX;
    const y = chunk.groundOrigin.y - camY;
    const gs = chunk.groundScale || GROUND_BAKE_SCALE;
    const gw = chunk.ground.width / gs, gh = chunk.ground.height / gs;
    if (x > W || y > H || x + gw < 0 || y + gh < 0) continue;
    if (chunk.groundPrev) {
      const a = (performance.now() - chunk.groundFadeT0) / 450;
      const ps = chunk.groundPrevScale || 1, po = chunk.groundPrevOrigin;
      ctx.drawImage(chunk.groundPrev, po.x - camX, po.y - camY, chunk.groundPrev.width / ps, chunk.groundPrev.height / ps);
      if (a >= 1) {
        if (chunk.groundPrev.close) chunk.groundPrev.close();
        chunk.groundPrev = null;
        ctx.drawImage(chunk.ground, x, y, gw, gh);
      } else {
        ctx.globalAlpha = a < 0 ? 0 : a;
        ctx.drawImage(chunk.ground, x, y, gw, gh);
        ctx.globalAlpha = 1;
      }
      drawGroundLight(chunk, x, y, gw, gh);
      continue;
    }
    ctx.drawImage(chunk.ground, x, y, gw, gh);
    drawGroundLight(chunk, x, y, gw, gh);
  }
}

// Освещение склонов от солнца: 4 карты наклона (+x, −x, +y, −y) складываются
// с весами по направлению и высоте солнца (sunLight() в daynight.js). Склон к
// солнцу светлее, от солнца — темнее; утром и вечером сильнее, ночью почти нет.
const _sunDefault = { dx: -0.7071, dy: -0.7071, k: 0.9 };
const GROUND_LIGHT_GAIN = 1.6;   // сила светотени склонов
function drawGroundLight(chunk, x, y, gw, gh) {
  const L = chunk.groundLight;
  if (!L) return;
  const sun = typeof sunLight === 'function' ? sunLight() : _sunDefault;
  if (sun.k < 0.01) return;
  // освещение = −(gx·dx + gy·dy)·k; карты: [gx, 255−gx, gy, 255−gy]
  const wx = -sun.dx * sun.k, wy = -sun.dy * sun.k;
  // только внутри контура своего чанка (с рельефом): иначе на стыках чанков
  // полупрозрачные карты ложатся дважды или оставляют щель — видны линии
  if (!chunk.lightPoly) {
    const G = GROUND_WARP_CELLS, cs = CHUNK_SIZE / G, sx = chunk.cx * CHUNK_SIZE, sy = chunk.cy * CHUNK_SIZE;
    const pts = [];
    const add = (i, j) => { const wx = sx + i * cs, wy = sy + j * cs; pts.push((wx - wy) * TILE_W / 2, (wx + wy) * TILE_H / 2 - terrainHeight(wx, wy) * RELIEF_PX_PER_M); };
    for (let i = 0; i < G; i++) add(i, 0);
    for (let j = 0; j < G; j++) add(G, j);
    for (let i = G; i > 0; i--) add(i, G);
    for (let j = G; j > 0; j--) add(0, j);
    // раздуть на ~1.2 px, как раздута сама земля при запекании: её полоска на
    // стыке перекрывает соседний кусок — туда же должен лечь и свет этого куска
    let cx = 0, cy = 0;
    for (let k = 0; k < pts.length; k += 2) { cx += pts[k]; cy += pts[k + 1]; }
    cx /= pts.length / 2; cy /= pts.length / 2;
    for (let k = 0; k < pts.length; k += 2) {
      const dx = pts[k] - cx, dy = pts[k + 1] - cy, l = Math.hypot(dx, dy) || 1;
      pts[k] += dx / l * 0.7; pts[k + 1] += dy / l * 0.7;
    }
    chunk.lightPoly = pts;
  }
  const P = chunk.lightPoly, ox = x - chunk.groundOrigin.x, oy = y - chunk.groundOrigin.y;
  ctx.save();
  ctx.beginPath();
  ctx.moveTo(P[0] + ox, P[1] + oy);
  for (let k = 2; k < P.length; k += 2) ctx.lineTo(P[k] + ox, P[k + 1] + oy);
  ctx.closePath();
  ctx.clip();
  ctx.globalCompositeOperation = 'soft-light';
  for (const [wgt, a, b] of [[wx, L[0], L[1]], [wy, L[2], L[3]]]) {
    if (Math.abs(wgt) < 0.02) continue;
    const img = wgt > 0 ? a : b;
    if (!img) continue;
    let rem = Math.abs(wgt) * GROUND_LIGHT_GAIN;        // >1 — кладём дважды (soft-light мягкий)
    while (rem > 0.01) {
      ctx.globalAlpha = Math.min(1, rem);
      ctx.drawImage(img, x, y, gw, gh);
      rem -= 1;
    }
  }
  ctx.globalAlpha = 1;
  ctx.globalCompositeOperation = 'source-over';
  ctx.restore();
}

function render() {
  // Рисуем в CSS-пикселях, холст — в пикселях экрана (см. main.js/resize).
  ctx.setTransform(view.dpr, 0, 0, view.dpr, 0, 0);
  syncRenderCamera();
  ctx.clearRect(0, 0, view.w, view.h);
  // зум камеры (в низинах приближение): масштаб вокруг центра экрана
  const zoom = camera.zoom || 1;
  if (zoom > 1.001) {
    ctx.setTransform(view.dpr * zoom, 0, 0, view.dpr * zoom,
      view.dpr * view.w / 2 * (1 - zoom), view.dpr * view.h / 2 * (1 - zoom));
  }
  const renderQueue = [];
  drawGround();
  drawGroundLayer(ctx);
  if (typeof drawSunShadows === 'function') drawSunShadows(ctx);   // единственные тени — от солнца
  drawEffects(ctx);
  drawBloodDecals(ctx);
  drawCasings(ctx);

  for (const [, chunk] of loadedChunks.entries()) {
    // Лесной мусор (пни, сломанные стволы, камни)
    for (const c of chunk.clutter) {
      renderQueue.push({ isPlayer: false, isClutter: true, obj: c, depth: c.x + c.y });
    }

    // Подлесок, который стоит (трава, папоротники, кусты, ёлочки)
    for (const o of chunk.cover || []) {
      // две записи: части позади ног (до бойца) и впереди (после)
      if (!COVER_KINDS[o.kind].flat) {
        // Глубина растения одна и та же в режиме «целое» и «пучки» — иначе при подходе
        // соседи вплотную (в лесу их полно) внезапно меняются местами. Передняя
        // половина пучков поднимается выше бойца только когда он рядом.
        const dd = o.x + o.y;
        renderQueue.push({ isCover: true, half: 0, obj: o, depth: dd });
        if (o._act > 0.05) {
          renderQueue.push({ isCover: true, half: 1, obj: o, depth: Math.max(dd + 0.02, player.x + player.y + 0.01) });
        }
      }
    }

    // Валуны
    for (const r of chunk.rocks || []) {
      renderQueue.push({ isRock: true, obj: r, depth: r.x + r.y });
    }

    // Деревья
    for (const t of chunk.trees) {
      renderQueue.push({ isPlayer: false, isClutter: false, obj: t, depth: t.x + t.y });
    }
  }

  // Пули и дым — в той же очереди по глубине: перед деревом видны, за ним скрыты.
  for (const b of weapon.bullets) renderQueue.push({ isBullet: true, obj: b, depth: b.x + b.y });
  for (const p of weapon.puffs) renderQueue.push({ isPuff: true, obj: p, depth: p.x + p.y });

  for (const z of zombies) renderQueue.push({ isZombie: true, obj: z, depth: z.x + z.y });
  renderQueue.push({ isPlayer: true, obj: player, depth: player.x + player.y });
  renderQueue.sort((a, b) => a.depth - b.depth);

  renderQueue.forEach(item => {
    if (item.isCover) {
      drawCoverItem(ctx, item.obj, item.half);
    } else if (item.isRock) {
      const o = item.obj;
      const pos = toScreen(o.x, o.y, heightOf(o));
      if (!onScreen(pos, 140)) return;
      drawDataSprite(ctx, 'rock', ROCK_TYPES[o.type].key, pos.x, pos.y, o.scale || 1, o.flip);
    } else if (item.isZombie) {
      drawZombie(ctx, item.obj);
    } else if (item.isBullet) {
      drawBullet(ctx, item.obj);
    } else if (item.isPuff) {
      drawPuff(ctx, item.obj);
    } else if (item.isPlayer) {
      const pos = toScreen(player.x, player.y, player.h);
      drawCharacter(ctx, pos.x, pos.y);
    } else if (item.isClutter) {
      const obj = item.obj;
      const pos = toScreen(obj.x, obj.y, heightOf(obj));
      if (pos.x < -100 || pos.x > view.w + 100 || pos.y < -120 || pos.y > view.h + 100) return;

      const def = CLUTTER_TYPES[obj.kind];
      const sprite = clutterSprites[obj.kind][obj.variant || 0];
      if (!sprite.complete || !sprite.naturalWidth) return;
      const scale = obj.scale || 1.0;
      const ratio = sprite.naturalHeight / sprite.naturalWidth;
      const dw = def.h ? (def.h * scale) / ratio : def.w * scale;
      const dh = dw * ratio;

      // Рисуем относительно точки касания земли (низ картинки): поворот
      // (наклон сломанного ствола) и отражение идут вокруг неё, так что
      // объект не отрывается от земли.
      ctx.save();
      ctx.translate(pos.x, pos.y);
      if (obj.tilt) ctx.rotate(obj.tilt);
      if (obj.flip) ctx.scale(-1, 1);
      ctx.drawImage(sprite, -dw / 2, -dh, dw, dh);
      ctx.restore();

    } else {
      const obj = item.obj;
      const pos = toScreen(obj.x, obj.y, heightOf(obj));
      const scale = obj.scale || 1.0;
      const dw = TREE_DRAW_W * scale;
      const dh = TREE_DRAW_H * scale;
      if (pos.x < -dw || pos.x > view.w + dw || pos.y < -20 || pos.y - dh > view.h) return;

      const sprite = obj.broken ? brokenTreeSprites[obj.type] : treeSprites[obj.type];

      // В картинке дерева основание ствола стоит ровно по центру на 95% высоты
      // (так нарезаны assets/trees) — ставим эту точку в точку дерева на карте.
      if (sprite.complete) {
        const left = pos.x - dw / 2, top = pos.y - dh * TREE_BASE_FRAC;
        // Дерево ближе к камере, чем боец, и его крона накрывает бойца на
        // экране — «прозрачное окошко» вокруг бойца, чтобы его форма и
        // оружие оставались видны (как в играх с таким видом сверху).
        const pp = toScreen(player.x, player.y, player.h);
        const covers = (obj.x + obj.y) > (player.x + player.y) + 0.05 &&
          pp.x > left + dw * 0.12 && pp.x < left + dw * 0.88 &&
          pp.y - 35 > top && pp.y < pos.y + 6;
        obj.fade = (obj.fade || 0) + ((covers ? 1 : 0) - (obj.fade || 0)) * 0.2;
        if (obj.fade > 0.02) {
          treeHoleObj = obj;
          drawTreeWithHole(sprite, left, top, dw, dh, pp.x - left, pp.y - 48 - top, obj.fade);
        } else {
          drawSwaying(ctx, sprite, left, top, dw, dh, obj);
        }
      }
    }
  });

  // День и ночь, лучи солнца (src/daynight.js) — поверх мира, под джойстиком
  if (typeof drawDayNight === 'function') drawDayNight(ctx);

  // Сенсорный джойстик
  if (joystick.active) {
    ctx.beginPath();
    ctx.arc(joystick.startX, joystick.startY, joystick.maxDist, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(255, 255, 255, 0.08)';
    ctx.fill();
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.25)';
    ctx.lineWidth = 2;
    ctx.stroke();

    ctx.beginPath();
    ctx.arc(joystick.currX, joystick.currY, 22, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(46, 204, 113, 0.7)';
    ctx.fill();
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 1.5;
    ctx.stroke();
  }

  // Виньетка
  const vignette = ctx.createRadialGradient(
    view.w / 2, view.h / 2, Math.min(view.w, view.h) * 0.35,
    view.w / 2, view.h / 2, Math.max(view.w, view.h) * 0.75
  );
  vignette.addColorStop(0, 'rgba(0, 0, 0, 0)');
  vignette.addColorStop(1, 'rgba(4, 7, 4, 0.55)');
  ctx.fillStyle = vignette;
  ctx.fillRect(0, 0, view.w, view.h);
}

// Дерево с мягким «окошком» вокруг бойца: рисуем спрайт во временный
// холст, вырезаем эллиптическую дыру с плавным краем и кладём на кадр.
// Обычно окошко нужно 1–3 деревьям за раз, поэтому это дёшево.
let treeHoleCanvas = null;
function drawTreeWithHole(sprite, left, top, dw, dh, hx, hy, strength) {
  const dpr = view.dpr;
  const w = Math.ceil(dw * dpr), h = Math.ceil(dh * dpr);
  if (!treeHoleCanvas) treeHoleCanvas = document.createElement('canvas');
  if (treeHoleCanvas.width < w || treeHoleCanvas.height < h) {
    treeHoleCanvas.width = Math.max(treeHoleCanvas.width, w);
    treeHoleCanvas.height = Math.max(treeHoleCanvas.height, h);
  }
  const tc = treeHoleCanvas.getContext('2d');
  tc.setTransform(1, 0, 0, 1, 0, 0);
  tc.globalCompositeOperation = 'source-over';
  tc.clearRect(0, 0, treeHoleCanvas.width, treeHoleCanvas.height);
  tc.setTransform(dpr, 0, 0, dpr, 0, 0);
  drawSwaying(tc, sprite, 0, 0, dw, dh, treeHoleObj);
  tc.globalCompositeOperation = 'destination-out';
  tc.save();
  tc.translate(hx, hy);
  tc.scale(0.75, 1);              // окошко вытянуто по вертикали: боец высокий
  const r = 72;
  const g = tc.createRadialGradient(0, 0, r * 0.45, 0, 0, r);
  g.addColorStop(0, `rgba(0,0,0,${0.97 * strength})`);
  g.addColorStop(1, 'rgba(0,0,0,0)');
  tc.fillStyle = g;
  tc.fillRect(-r, -r, r * 2, r * 2);
  tc.restore();
  ctx.drawImage(treeHoleCanvas, 0, 0, w, h, left, top, dw, dh);
}

// Ветер. Картинка дерева режется на горизонтальные полоски, и каждая
// сдвигается вбок тем сильнее, чем выше она над землёй (∝ высота^1.6):
// ствол у корней стоит на месте, крона гнётся. Покачивание — сумма двух
// синусов (медленная волна + порыв), фаза зависит от места дерева, поэтому
// по лесу идёт «волна» ветра, а не качаются все деревья в такт. Плюс мелкая
// дрожь листвы в верхней части.
let treeHoleObj = null;
function windOffset(obj, hn, t) {
  const ph = obj.x * 0.55 + obj.y * 0.35;
  const w = 2 * Math.PI * WIND_FREQ;
  const gust = 0.65 + 0.35 * Math.sin(t * 0.21 + ph * 0.15);
  const sway = Math.sin(w * t + ph) * 0.7 + Math.sin(w * 2.3 * t + ph * 1.7) * 0.3;
  const flutter = Math.sin(t * 9.0 + ph * 3.1) * 0.12 + Math.sin(t * 13.0 + ph * 5.3) * 0.08;
  const k = obj.type === 4 ? 0.45 : 1; // сухостой без листвы качается меньше
  return WIND_AMPLITUDE * (obj.scale || 1) * k * (Math.pow(hn, 1.6) * sway * gust + hn * flutter);
}

function drawSwaying(c, sprite, left, top, dw, dh, obj) {
  if (!obj) { c.drawImage(sprite, left, top, dw, dh); return; }
  const t = performance.now() / 1000;
  const sw = sprite.naturalWidth || sprite.width, sh = sprite.naturalHeight || sprite.height;
  const baseY = TREE_BASE_FRAC;           // доля высоты картинки, где земля
  const n = WIND_SLICES;
  const bandSrc = (sh * baseY) / n;       // полоски от верха до земли
  const bandDst = (dh * baseY) / n;
  for (let i = 0; i < n; i++) {
    const hn = 1 - (i + 0.5) / n;         // 1 у верхушки, 0 у земли
    const dx = windOffset(obj, hn, t);
    // +0.6 px перекрытия, чтобы между полосками не было щелей
    c.drawImage(sprite, 0, i * bandSrc, sw, bandSrc + 1, left + dx, top + i * bandDst, dw, bandDst + 0.6);
  }
  // низ картинки ниже земли (корни, свисающие ветви) — без сдвига
  c.drawImage(sprite, 0, sh * baseY, sw, sh * (1 - baseY), left, top + dh * baseY, dw, dh * (1 - baseY));
}

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
        const { key, bitmap } = e.data;
        groundBake.inFlight.delete(key);
        const chunk = loadedChunks.get(key);
        if (!chunk || chunk.ground) { bitmap.close(); return; }
        chunk.ground = bitmap;
        chunk.groundOrigin = chunkPixelOrigin(chunk.cx, chunk.cy);
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

function localBake(chunk) {
  if (!groundBake.local) {
    groundBake.local = createGroundBaker((w, h) => {
      const c = document.createElement('canvas');
      c.width = w;
      c.height = h;
      return c;
    }, groundImages);
  }
  chunk.ground = groundBake.local(chunk.cx, chunk.cy);
  chunk.groundOrigin = chunkPixelOrigin(chunk.cx, chunk.cy);
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
    const pending = [];
    for (const [key, chunk] of loadedChunks.entries()) {
      const d = Math.max(Math.abs(chunk.cx - pcx), Math.abs(chunk.cy - pcy));
      if (d > GROUND_BAKE_KEEP_RADIUS) {
        if (chunk.ground && chunk.ground.close) chunk.ground.close();
        chunk.ground = null;
        continue;
      }
      if (!chunk.ground && !groundBake.inFlight.has(key)) pending.push([d, key, chunk]);
    }
    pending.sort((p, q) => p[0] - q[0]);
    if (groundBake.worker) {
      if (groundBake.ready) {
        for (const [, key, chunk] of pending) {
          if (groundBake.inFlight.size >= GROUND_MAX_IN_FLIGHT) break;
          groundBake.inFlight.add(key);
          groundBake.worker.postMessage({ type: 'bake', key, cx: chunk.cx, cy: chunk.cy });
        }
      }
    } else if (pending.length) {
      localBake(pending[0][2]);
    }
  }

  for (const chunk of loadedChunks.values()) {
    if (!chunk.ground) continue;
    const x = chunk.groundOrigin.x - camX;
    const y = chunk.groundOrigin.y - camY;
    if (x > W || y > H || x + chunk.ground.width < 0 || y + chunk.ground.height < 0) continue;
    ctx.drawImage(chunk.ground, x, y);
  }
}

function render() {
  // Рисуем в CSS-пикселях, холст — в пикселях экрана (см. main.js/resize).
  ctx.setTransform(view.dpr, 0, 0, view.dpr, 0, 0);
  syncRenderCamera();
  ctx.clearRect(0, 0, view.w, view.h);
  const renderQueue = [];
  drawGround();
  drawCasings(ctx);

  for (const [, chunk] of loadedChunks.entries()) {
    // Лесной мусор (пни, сломанные стволы, камни)
    for (const c of chunk.clutter) {
      renderQueue.push({ isPlayer: false, isClutter: true, obj: c, depth: c.x + c.y });
    }

    // Деревья
    for (const t of chunk.trees) {
      renderQueue.push({ isPlayer: false, isClutter: false, obj: t, depth: t.x + t.y });
    }
  }

  // Пули и дым — в той же очереди по глубине: перед деревом видны, за ним скрыты.
  for (const b of weapon.bullets) renderQueue.push({ isBullet: true, obj: b, depth: b.x + b.y });
  for (const p of weapon.puffs) renderQueue.push({ isPuff: true, obj: p, depth: p.x + p.y });

  renderQueue.push({ isPlayer: true, obj: player, depth: player.x + player.y });
  renderQueue.sort((a, b) => a.depth - b.depth);

  renderQueue.forEach(item => {
    if (item.isBullet) {
      drawBullet(ctx, item.obj);
    } else if (item.isPuff) {
      drawPuff(ctx, item.obj);
    } else if (item.isPlayer) {
      const pos = toScreen(player.x, player.y);
      drawCharacter(ctx, pos.x, pos.y);
    } else if (item.isClutter) {
      const obj = item.obj;
      const pos = toScreen(obj.x, obj.y);
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
      const pos = toScreen(obj.x, obj.y);
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
        const pp = toScreen(player.x, player.y);
        const covers = (obj.x + obj.y) > (player.x + player.y) + 0.05 &&
          pp.x > left + dw * 0.12 && pp.x < left + dw * 0.88 &&
          pp.y - 30 > top && pp.y < pos.y + 6;
        obj.fade = (obj.fade || 0) + ((covers ? 1 : 0) - (obj.fade || 0)) * 0.2;
        if (obj.fade > 0.02) {
          drawTreeWithHole(sprite, left, top, dw, dh, pp.x - left, pp.y - 42 - top, obj.fade);
        } else {
          ctx.drawImage(sprite, left, top, dw, dh);
        }
      }
    }
  });

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
  tc.drawImage(sprite, 0, 0, dw, dh);
  tc.globalCompositeOperation = 'destination-out';
  tc.save();
  tc.translate(hx, hy);
  tc.scale(0.75, 1);              // окошко вытянуто по вертикали: боец высокий
  const r = 62;
  const g = tc.createRadialGradient(0, 0, r * 0.45, 0, 0, r);
  g.addColorStop(0, `rgba(0,0,0,${0.97 * strength})`);
  g.addColorStop(1, 'rgba(0,0,0,0)');
  tc.fillStyle = g;
  tc.fillRect(-r, -r, r * 2, r * 2);
  tc.restore();
  ctx.drawImage(treeHoleCanvas, 0, 0, w, h, left, top, dw, dh);
}

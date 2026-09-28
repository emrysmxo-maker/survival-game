// Модуль реалистичного ландшафта и живых деревьев (без аниме, реалистичная текстура)
class World {
  constructor(cols = 40, rows = 40) {
    this.cols = cols;
    this.rows = rows;
    this.tileW = 64;
    this.tileH = 32;

    this.currentTreeStyle = 0; // 0: Сосна, 1: Дуб, 2: Берёза, 3: Клён, 4: Сухостой

    this.styles = [
      { name: '🌲 1. Сосна', bg: '#090d09' },
      { name: '🌳 2. Дуб', bg: '#0b100b' },
      { name: '🪵 3. Берёза', bg: '#0a0e0a' },
      { name: '🍁 4. Клён', bg: '#100c08' },
      { name: '⚡ 5. Сухостой', bg: '#080808' }
    ];

    this.treeTextures = [];
    this.initRealisticTreeSprites();

    this.grid = [];
    this.trees = [];
    this.generateTerrain();
  }

  setTreeStyle(index) {
    this.currentTreeStyle = index;
    document.body.style.backgroundColor = this.styles[index].bg;
  }

  // Генерация высокодетализированных реалистичных текстур деревьев в памяти
  initRealisticTreeSprites() {
    for (let s = 0; s < 5; s++) {
      const c = document.createElement('canvas');
      c.width = 180;
      c.height = 250;
      const ctx = c.getContext('2d');
      this.drawRealisticTreeTexture(ctx, s);
      this.treeTextures[s] = c;
    }
  }

  // Псевдослучайный генератор с фиксированным сидом для повторяемости
  seededRandom(s) {
    const x = Math.sin(s++) * 10000;
    return x - Math.floor(x);
  }

  drawRealisticTreeTexture(ctx, styleId) {
    const cx = 90;
    const baseY = 230;

    if (styleId === 0) {
      // 1. РЕАЛИСТИЧНАЯ СИБИРСКАЯ СОСНА
      // Корни и ствол с шероховатой корой
      ctx.fillStyle = '#22160d';
      ctx.beginPath();
      ctx.moveTo(cx - 9, baseY);
      ctx.quadraticCurveTo(cx - 5, baseY - 50, cx - 2.5, baseY - 140);
      ctx.lineTo(cx + 2.5, baseY - 140);
      ctx.quadraticCurveTo(cx + 5, baseY - 50, cx + 9, baseY);
      ctx.closePath();
      ctx.fill();

      // Борозды и трещины коры
      ctx.strokeStyle = '#140c06';
      ctx.lineWidth = 1.2;
      for (let y = baseY; y > baseY - 120; y -= 8) {
        ctx.beginPath();
        ctx.moveTo(cx - 4 + Math.sin(y)*2, y);
        ctx.lineTo(cx + 3 + Math.cos(y)*2, y - 6);
        ctx.stroke();
      }

      // Тонкие сосновые сучья
      ctx.strokeStyle = '#1e130b';
      ctx.lineWidth = 2.5;
      const branchTiers = [
        { y: baseY - 40, len: 45 },
        { y: baseY - 65, len: 40 },
        { y: baseY - 90, len: 32 },
        { y: baseY - 115, len: 24 },
        { y: baseY - 135, len: 16 }
      ];
      branchTiers.forEach(b => {
        ctx.beginPath();
        ctx.moveTo(cx, b.y);
        ctx.quadraticCurveTo(cx - b.len * 0.5, b.y + 4, cx - b.len, b.y - 2);
        ctx.moveTo(cx, b.y - 2);
        ctx.quadraticCurveTo(cx + b.len * 0.5, b.y + 4, cx + b.len, b.y - 2);
        ctx.stroke();
      });

      // Сотни мелких реалистичных пучков хвои (не круги, а органическая хвоя)
      let seed = 42;
      for (let i = 0; i < 420; i++) {
        const t = this.seededRandom(seed++);
        const tierY = baseY - 35 - t * 145;
        const maxSpread = (1 - t * 0.75) * 52;
        const offsetX = (this.seededRandom(seed++) - 0.5) * 2 * maxSpread;
        const offsetY = (this.seededRandom(seed++) - 0.5) * 14;

        const posX = cx + offsetX;
        const posY = tierY + offsetY;

        // Естественные цвета хвои (глубокая тень -> свет)
        const depth = (posX - (cx - maxSpread)) / (maxSpread * 2);
        let col = '#0d2112'; // Глубокая тень
        if (depth > 0.55) col = '#1b4023';
        if (depth > 0.75) col = '#285834';

        ctx.fillStyle = col;
        ctx.fillRect(posX, posY, 2.5, 4.5);

        // Тонкие игольчатые штрихи
        ctx.strokeStyle = col;
        ctx.lineWidth = 0.8;
        ctx.beginPath();
        ctx.moveTo(posX, posY);
        ctx.lineTo(posX + (offsetX > 0 ? 3 : -3), posY + 2);
        ctx.stroke();
      }

    } else if (styleId === 1) {
      // 2. ВЕКОВОЙ ДУБ (Мощный узловатый ствол, раскидистая листва)
      ctx.fillStyle = '#261b13';
      ctx.beginPath();
      ctx.moveTo(cx - 14, baseY);
      ctx.quadraticCurveTo(cx - 8, baseY - 30, cx - 12, baseY - 60);
      ctx.lineTo(cx - 24, baseY - 100); // Левый сук
      ctx.lineTo(cx - 18, baseY - 103);
      ctx.lineTo(cx - 6, baseY - 70);
      ctx.lineTo(cx + 6, baseY - 70);
      ctx.lineTo(cx + 22, baseY - 95); // Правый сук
      ctx.lineTo(cx + 26, baseY - 92);
      ctx.quadraticCurveTo(cx + 10, baseY - 40, cx + 15, baseY);
      ctx.closePath();
      ctx.fill();

      // Текстура дубовой коры
      ctx.strokeStyle = '#150e09';
      ctx.lineWidth = 1.5;
      for (let y = baseY; y > baseY - 60; y -= 6) {
        ctx.beginPath();
        ctx.moveTo(cx - 7, y); ctx.lineTo(cx - 5, y - 5);
        ctx.moveTo(cx + 3, y - 2); ctx.lineTo(cx + 5, y - 8);
        ctx.stroke();
      }

      // Густая органическая листва дуба (сотни органических мазков)
      let seed = 101;
      for (let i = 0; i < 650; i++) {
        const u = this.seededRandom(seed++);
        const v = this.seededRandom(seed++);
        const angle = u * Math.PI * 2;
        const radX = Math.sqrt(v) * 58;
        const radY = Math.sqrt(v) * 44;

        const lx = cx + Math.cos(angle) * radX;
        const ly = (baseY - 110) + Math.sin(angle) * radY;

        // Расчёт света (справа сверху)
        const isSunlit = (lx > cx - 10) && (ly < baseY - 110);
        const isDeepShadow = (ly > baseY - 90) || (lx < cx - 25);

        let leafColor = '#1e3818';
        if (isDeepShadow) leafColor = '#0f200c';
        else if (isSunlit) leafColor = '#36612b';
        if (isSunlit && this.seededRandom(seed++) > 0.6) leafColor = '#4a7d3c';

        ctx.fillStyle = leafColor;
        ctx.beginPath();
        ctx.ellipse(lx, ly, 3.5, 2.5, angle, 0, Math.PI * 2);
        ctx.fill();
      }

    } else if (styleId === 2) {
      // 3. РУССКАЯ БЕРЁЗА (Белый ствол с чёрными полосами, ажурная листва)
      ctx.fillStyle = '#eaeae6';
      ctx.beginPath();
      ctx.moveTo(cx - 5, baseY);
      ctx.quadraticCurveTo(cx - 1, baseY - 70, cx + 2, baseY - 150);
      ctx.lineTo(cx + 5, baseY - 150);
      ctx.quadraticCurveTo(cx + 2, baseY - 70, cx - 1, baseY);
      ctx.closePath();
      ctx.fill();

      // Черные полосы на белой коре березы (чечевички)
      ctx.fillStyle = '#1e1e1e';
      const birchMarks = [5, 15, 28, 42, 58, 75, 92, 110, 130];
      birchMarks.forEach(my => {
        ctx.fillRect(cx - 2, baseY - my, 4, 2);
        ctx.fillRect(cx, baseY - my - 4, 3.5, 1.5);
      });

      // Тонкие изящные свисающие ветви
      ctx.strokeStyle = '#2b261f';
      ctx.lineWidth = 1;
      for (let b = 0; b < 12; b++) {
        const by = baseY - 80 - b * 5;
        const dir = b % 2 === 0 ? 1 : -1;
        ctx.beginPath();
        ctx.moveTo(cx + 2, by);
        ctx.quadraticCurveTo(cx + dir * 20, by + 10, cx + dir * 32, by + 30);
        ctx.stroke();
      }

      // Нежная мелкая листва березы
      let seed = 303;
      for (let i = 0; i < 480; i++) {
        const t = this.seededRandom(seed++);
        const angle = this.seededRandom(seed++) * Math.PI * 2;
        const rx = this.seededRandom(seed++) * 38;
        const ry = this.seededRandom(seed++) * 55;

        const lx = cx + Math.cos(angle) * rx;
        const ly = (baseY - 110) + Math.sin(angle) * ry;

        const col = lx > cx ? '#4a7536' : '#2b4d1d';
        ctx.fillStyle = col;
        ctx.fillRect(lx, ly, 2.5, 2.5);
      }

    } else if (styleId === 3) {
      // 4. ЛЕСНОЙ КЛЁН (Реалистичная багряно-золотая листва)
      ctx.fillStyle = '#2b1c14';
      ctx.beginPath();
      ctx.moveTo(cx - 8, baseY);
      ctx.quadraticCurveTo(cx - 4, baseY - 40, cx - 7, baseY - 80);
      ctx.lineTo(cx + 7, baseY - 80);
      ctx.quadraticCurveTo(cx + 4, baseY - 40, cx + 8, baseY);
      ctx.closePath();
      ctx.fill();

      // Живописные осенние листья (охра, багрянец, медь, золото)
      let seed = 505;
      for (let i = 0; i < 680; i++) {
        const u = this.seededRandom(seed++);
        const v = this.seededRandom(seed++);
        const angle = u * Math.PI * 2;
        const radX = Math.sqrt(v) * 54;
        const radY = Math.sqrt(v) * 46;

        const lx = cx + Math.cos(angle) * radX;
        const ly = (baseY - 115) + Math.sin(angle) * radY;

        const pal = ['#7c2214', '#9e321b', '#b84918', '#cb6819', '#d98b1b', '#e8ae23'];
        const colorIdx = Math.floor(this.seededRandom(seed++) * pal.length);

        ctx.fillStyle = pal[colorIdx];
        ctx.beginPath();
        ctx.ellipse(lx, ly, 3.2, 2.2, angle, 0, Math.PI * 2);
        ctx.fill();
      }

    } else if (styleId === 4) {
      // 5. МЁРТВЫЙ СУХОСТОЙ (Выветренный серый треснувший ствол без листьев)
      ctx.fillStyle = '#3a3d3c';
      ctx.beginPath();
      ctx.moveTo(cx - 10, baseY);
      ctx.lineTo(cx - 5, baseY - 50);
      ctx.lineTo(cx - 18, baseY - 90); // Сломанная сухая ветвь
      ctx.lineTo(cx - 15, baseY - 92);
      ctx.lineTo(cx - 3, baseY - 65);
      ctx.lineTo(cx - 1, baseY - 130); // Расколотый пик
      ctx.lineTo(cx + 3, baseY - 128);
      ctx.lineTo(cx + 4, baseY - 75);
      ctx.lineTo(cx + 20, baseY - 105); // Правый острый сук
      ctx.lineTo(cx + 22, baseY - 102);
      ctx.lineTo(cx + 7, baseY - 55);
      ctx.lineTo(cx + 10, baseY);
      ctx.closePath();
      ctx.fill();

      // Продольные глубокие трещины древесины
      ctx.strokeStyle = '#1b1d1c';
      ctx.lineWidth = 1.8;
      ctx.beginPath();
      ctx.moveTo(cx - 3, baseY); ctx.lineTo(cx - 2, baseY - 80);
      ctx.moveTo(cx + 2, baseY - 20); ctx.lineTo(cx + 1, baseY - 100);
      ctx.stroke();

      // Мелкие сухие острые ветки
      ctx.lineWidth = 1.2;
      ctx.beginPath();
      ctx.moveTo(cx - 15, baseY - 90); ctx.lineTo(cx - 28, baseY - 105);
      ctx.moveTo(cx + 18, baseY - 100); ctx.lineTo(cx + 30, baseY - 118);
      ctx.moveTo(cx, baseY - 110); ctx.lineTo(cx - 12, baseY - 135);
      ctx.stroke();
    }
  }

  generateTerrain() {
    this.trees = [];

    for (let x = 0; x < this.cols; x++) {
      this.grid[x] = [];
      for (let y = 0; y < this.rows; y++) {
        const isBorder = (x < 3 || x >= this.cols - 3 || y < 3 || y >= this.rows - 3);
        const pathDist = Math.abs(y - (Math.sin(x * 0.25) * 4 + this.rows / 2));

        if (isBorder) {
          this.grid[x][y] = 4; // Стена леса
          this.trees.push({ x: x + 0.5, y: y + 0.5, scale: 1.1 });
        } else if (pathDist < 1.3) {
          this.grid[x][y] = 2; // Тропа
        } else {
          const noise = Math.sin(x * 0.4) * Math.cos(y * 0.4);
          if (noise > 0.35) {
            this.grid[x][y] = 1; // Поляна
          } else if (noise < -0.3) {
            this.grid[x][y] = 3; // Мох
          } else {
            this.grid[x][y] = 0; // Трава
          }

          if (noise > 0.42 && Math.random() < 0.65) {
            this.trees.push({ x: x + 0.3 + Math.random() * 0.4, y: y + 0.3 + Math.random() * 0.4, scale: 0.85 + Math.random() * 0.3 });
          }
        }
      }
    }
  }

  toScreen(gridX, gridY, camera, screenW, screenH) {
    return {
      x: (gridX - gridY) * (this.tileW / 2) - camera.x + screenW / 2,
      y: (gridX + gridY) * (this.tileH / 2) - camera.y + screenH / 2
    };
  }

  render(ctx, camera, screenW, screenH) {
    const halfW = this.tileW / 2;
    const halfH = this.tileH / 2;

    // Палитра земли
    const tileColors = ['#1a2417', '#22321e', '#33271c', '#151e13', '#0a0f08'];

    // 1. Земля
    for (let x = 0; x < this.cols; x++) {
      for (let y = 0; y < this.rows; y++) {
        const pt = this.toScreen(x, y, camera, screenW, screenH);
        if (pt.x < -this.tileW || pt.x > screenW + this.tileW || pt.y < -this.tileH || pt.y > screenH + this.tileH) continue;

        const type = this.grid[x][y];
        ctx.beginPath();
        ctx.moveTo(pt.x, pt.y);
        ctx.lineTo(pt.x + halfW, pt.y + halfH);
        ctx.lineTo(pt.x, pt.y + this.tileH);
        ctx.lineTo(pt.x - halfW, pt.y + halfH);
        ctx.closePath();

        ctx.fillStyle = tileColors[type];
        ctx.fill();
        ctx.strokeStyle = 'rgba(0,0,0,0.12)';
        ctx.lineWidth = 0.5;
        ctx.stroke();
      }
    }

    // 2. Деревья с Y-сортировкой
    this.trees.sort((a, b) => (a.x + a.y) - (b.x + b.y));

    const sprite = this.treeTextures[this.currentTreeStyle];
    for (let i = 0; i < this.trees.length; i++) {
      const t = this.trees[i];
      const pos = this.toScreen(t.x, t.y, camera, screenW, screenH);
      if (pos.x < -120 || pos.x > screenW + 120 || pos.y < -180 || pos.y > screenH + 100) continue;

      const scale = t.scale || 1.0;
      const dw = 110 * scale;
      const dh = 150 * scale;

      // Тень дерева на земле
      ctx.beginPath();
      ctx.ellipse(pos.x + 4, pos.y + 3, 26 * scale, 13 * scale, 0, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(0, 0, 0, 0.45)';
      ctx.fill();

      // Отрисовка высококачественной текстуры
      ctx.drawImage(sprite, pos.x - dw / 2, pos.y - dh * 0.92, dw, dh);
    }

    // 3. Мягкая виньетка
    const vignette = ctx.createRadialGradient(
      screenW / 2, screenH / 2, Math.min(screenW, screenH) * 0.35,
      screenW / 2, screenH / 2, Math.max(screenW, screenH) * 0.75
    );
    vignette.addColorStop(0, 'rgba(0, 0, 0, 0)');
    vignette.addColorStop(1, 'rgba(4, 7, 4, 0.55)');
    ctx.fillStyle = vignette;
    ctx.fillRect(0, 0, screenW, screenH);
  }
}

window.World = World;

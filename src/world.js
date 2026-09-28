// Модуль ландшафта и окружения (фон, почва, тропинки, текстурные детали)
class World {
  constructor(cols = 40, rows = 40) {
    this.cols = cols;
    this.rows = rows;
    this.tileW = 64;
    this.tileH = 32;

    // Палитра ландшафта тайги в стиле выживания (LDoE)
    this.tileTypes = {
      FOREST_GRASS: 0, // Глубокая тёмная лесная трава
      CLEARING_GRASS: 1, // Освещённая поляна
      DIRT_PATH: 2, // Земляная лесная тропинка
      MOSSY_SOIL: 3, // Влажная земля и мох
      BORDER: 4 // Тёмная граница леса
    };

    this.palette = {
      0: { fill: '#1b2617', stroke: '#131c10' }, // Трава тайги
      1: { fill: '#24331f', stroke: '#1a2617' }, // Поляна
      2: { fill: '#33291c', stroke: '#261e14' }, // Тропинка
      3: { fill: '#182115', stroke: '#10170e' }, // Мох
      4: { fill: '#0a0f08', stroke: '#060a05' }  // Край
    };

    this.grid = [];
    this.groundDetails = [];
    this.generateTerrain();
  }

  // Генерация карты ландшафта с извилистой тропинкой и деталями почвы
  generateTerrain() {
    for (let x = 0; x < this.cols; x++) {
      this.grid[x] = [];
      for (let y = 0; y < this.rows; y++) {
        // 1. Граница карты
        if (x < 3 || x >= this.cols - 3 || y < 3 || y >= this.rows - 3) {
          this.grid[x][y] = this.tileTypes.BORDER;
          continue;
        }

        // 2. Извилистая тропинка через центр локации
        const pathDist = Math.abs(y - (Math.sin(x * 0.25) * 4 + this.rows / 2));
        if (pathDist < 1.3) {
          this.grid[x][y] = this.tileTypes.DIRT_PATH;
          continue;
        }

        // 3. Пятна полян и мха
        const noise = Math.sin(x * 0.4) * Math.cos(y * 0.4);
        if (noise > 0.35) {
          this.grid[x][y] = this.tileTypes.CLEARING_GRASS;
        } else if (noise < -0.3) {
          this.grid[x][y] = this.tileTypes.MOSSY_SOIL;
        } else {
          this.grid[x][y] = this.tileTypes.FOREST_GRASS;
        }

        // 4. Мелкие детали ландшафта (травинки, камешки, опавшая хвоя)
        const rand = Math.random();
        if (rand < 0.22) {
          this.groundDetails.push({
            x: x + 0.2 + Math.random() * 0.6,
            y: y + 0.2 + Math.random() * 0.6,
            type: rand < 0.14 ? 'tuft' : (rand < 0.19 ? 'pebble' : 'leaves'),
            color: rand < 0.14 ? '#3d5434' : (rand < 0.19 ? '#4b5548' : '#453523'),
            size: 2 + Math.random() * 3
          });
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

  // Отрисовка фона и ландшафта
  render(ctx, camera, screenW, screenH) {
    const halfW = this.tileW / 2;
    const halfH = this.tileH / 2;

    // 1. Отрисовка изометрической сетки земли
    for (let x = 0; x < this.cols; x++) {
      for (let y = 0; y < this.rows; y++) {
        const pt = this.toScreen(x, y, camera, screenW, screenH);

        // Отсечение невидимых тайлов
        if (pt.x < -this.tileW || pt.x > screenW + this.tileW || pt.y < -this.tileH || pt.y > screenH + this.tileH) {
          continue;
        }

        const tileType = this.grid[x][y];
        const style = this.palette[tileType];

        ctx.beginPath();
        ctx.moveTo(pt.x, pt.y);
        ctx.lineTo(pt.x + halfW, pt.y + halfH);
        ctx.lineTo(pt.x, pt.y + this.tileH);
        ctx.lineTo(pt.x - halfW, pt.y + halfH);
        ctx.closePath();

        ctx.fillStyle = style.fill;
        ctx.fill();
        ctx.strokeStyle = style.stroke;
        ctx.lineWidth = 0.5;
        ctx.stroke();
      }
    }

    // 2. Мелкие органические детали почвы (трава, камешки, листья)
    for (let i = 0; i < this.groundDetails.length; i++) {
      const d = this.groundDetails[i];
      const pos = this.toScreen(d.x, d.y, camera, screenW, screenH);

      if (pos.x < -20 || pos.x > screenW + 20 || pos.y < -20 || pos.y > screenH + 20) continue;

      if (d.type === 'tuft') {
        // Пучок дикой травы
        ctx.strokeStyle = d.color;
        ctx.lineWidth = 1.2;
        ctx.beginPath();
        ctx.moveTo(pos.x, pos.y);
        ctx.lineTo(pos.x - 2, pos.y - d.size);
        ctx.moveTo(pos.x, pos.y);
        ctx.lineTo(pos.x + 2, pos.y - d.size * 1.1);
        ctx.stroke();
      } else if (d.type === 'pebble') {
        // Камушек в земле
        ctx.fillStyle = 'rgba(0,0,0,0.3)';
        ctx.beginPath();
        ctx.ellipse(pos.x, pos.y + 1, d.size, d.size * 0.5, 0, 0, Math.PI * 2);
        ctx.fill();

        ctx.fillStyle = d.color;
        ctx.beginPath();
        ctx.ellipse(pos.x, pos.y, d.size * 0.9, d.size * 0.45, 0, 0, Math.PI * 2);
        ctx.fill();
      } else if (d.type === 'leaves') {
        // Опавшая хвоя/листья
        ctx.fillStyle = d.color;
        ctx.fillRect(pos.x, pos.y, d.size, 1.5);
      }
    }

    // 3. Атмосферная виньетка (затемнение по краям экрана для кинематографичности)
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

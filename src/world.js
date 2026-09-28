// Модуль генерации и переключения 5 стилей леса
class World {
  constructor(cols = 40, rows = 40) {
    this.cols = cols;
    this.rows = rows;
    this.tileW = 64;
    this.tileH = 32;

    this.currentBiome = 0; // 0: Тайга, 1: Гибли, 2: Осень, 3: Сакура, 4: Выжженный

    this.biomes = [
      {
        id: 0,
        name: '🌲 1. Тёмная тайга',
        bg: '#080c08',
        tiles: {
          grass: '#172214',
          clearing: '#1f2e1a',
          path: '#2e2518',
          moss: '#121a0f',
          border: '#080d07'
        },
        treeType: 'taiga_pine',
        vignette: 'rgba(3, 7, 3, 0.6)'
      },
      {
        id: 1,
        name: '🍃 2. Лес Миядзаки (Ghibli)',
        bg: '#0c160c',
        tiles: {
          grass: '#22421d',
          clearing: '#2d5727',
          path: '#4a3b25',
          moss: '#1b3617',
          border: '#0d1c0e'
        },
        treeType: 'ghibli_oak',
        vignette: 'rgba(5, 15, 5, 0.4)'
      },
      {
        id: 2,
        name: '🍂 3. Туманная осень',
        bg: '#140f09',
        tiles: {
          grass: '#3b2816',
          clearing: '#4f351c',
          path: '#3d2516',
          moss: '#2e1e10',
          border: '#120b05'
        },
        treeType: 'autumn_maple',
        vignette: 'rgba(20, 12, 6, 0.55)'
      },
      {
        id: 3,
        name: '🌸 4. Сакура и бамбук',
        bg: '#111413',
        tiles: {
          grass: '#1d3328',
          clearing: '#254435',
          path: '#3a332a',
          moss: '#172920',
          border: '#0a1410'
        },
        treeType: 'sakura_tree',
        vignette: 'rgba(15, 10, 15, 0.45)'
      },
      {
        id: 4,
        name: '🔥 5. Выжженный лес',
        bg: '#0a0808',
        tiles: {
          grass: '#1a1717',
          clearing: '#262222',
          path: '#211915',
          moss: '#141212',
          border: '#050404'
        },
        treeType: 'burnt_tree',
        vignette: 'rgba(10, 5, 5, 0.7)'
      }
    ];

    this.grid = [];
    this.trees = [];
    this.groundDetails = [];

    this.generateMap();
  }

  setBiome(index) {
    this.currentBiome = index;
    document.body.style.backgroundColor = this.biomes[index].bg;
  }

  generateMap() {
    this.trees = [];
    this.groundDetails = [];

    for (let x = 0; x < this.cols; x++) {
      this.grid[x] = [];
      for (let y = 0; y < this.rows; y++) {
        const isBorder = (x < 3 || x >= this.cols - 3 || y < 3 || y >= this.rows - 3);
        const pathDist = Math.abs(y - (Math.sin(x * 0.25) * 4 + this.rows / 2));

        if (isBorder) {
          this.grid[x][y] = 'border';
          this.trees.push({ x: x + 0.5, y: y + 0.5, scale: 1.15 });
        } else if (pathDist < 1.3) {
          this.grid[x][y] = 'path';
        } else {
          const noise = Math.sin(x * 0.4) * Math.cos(y * 0.4);
          if (noise > 0.35) {
            this.grid[x][y] = 'clearing';
          } else if (noise < -0.3) {
            this.grid[x][y] = 'moss';
          } else {
            this.grid[x][y] = 'grass';
          }

          // Деревья на полянах
          if (noise > 0.42 && Math.random() < 0.65) {
            this.trees.push({ x: x + 0.3 + Math.random() * 0.4, y: y + 0.3 + Math.random() * 0.4, scale: 0.85 + Math.random() * 0.35 });
          } else if (Math.random() < 0.2) {
            this.groundDetails.push({ x: x + 0.5, y: y + 0.5, rand: Math.random() });
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

  // Отрисовка дерева в зависимости от выбранного биома
  drawTree(ctx, pos, tree, biomeId) {
    const scale = tree.scale || 1.0;

    // Тень под деревом
    ctx.beginPath();
    ctx.ellipse(pos.x + 4, pos.y + 4, 28 * scale, 14 * scale, 0, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(0, 0, 0, 0.45)';
    ctx.fill();

    if (biomeId === 0) {
      // 1. ТЁМНАЯ ТАЁЖНАЯ СОСНА
      ctx.fillStyle = '#22140a';
      ctx.fillRect(pos.x - 3 * scale, pos.y - 18 * scale, 6 * scale, 20 * scale);

      const tiers = [
        { y: 16, w: 42, h: 32, dark: '#0e2412', mid: '#193d1f', light: '#26592e' },
        { y: 38, w: 34, h: 30, dark: '#102915', mid: '#1c4523', light: '#2c6635' },
        { y: 58, w: 24, h: 26, dark: '#123018', mid: '#21522a', light: '#33773d' },
        { y: 76, w: 14, h: 22, dark: '#15361b', mid: '#265c2f', light: '#3a8746' }
      ];
      tiers.forEach(t => {
        const topY = pos.y - (t.y + t.h) * scale;
        const botY = pos.y - t.y * scale;
        const w = t.w * scale;

        ctx.beginPath();
        ctx.moveTo(pos.x, topY);
        ctx.lineTo(pos.x + w, botY);
        ctx.lineTo(pos.x - w, botY);
        ctx.closePath();
        ctx.fillStyle = t.dark;
        ctx.fill();

        ctx.beginPath();
        ctx.moveTo(pos.x, topY);
        ctx.lineTo(pos.x + w * 0.85, botY);
        ctx.lineTo(pos.x, botY);
        ctx.closePath();
        ctx.fillStyle = t.light;
        ctx.fill();
      });

    } else if (biomeId === 1) {
      // 2. ЛЕС МИЯДЗАКИ (Пышный аниме-дуб с круглыми облаками листвы)
      ctx.fillStyle = '#3a2312';
      ctx.beginPath();
      ctx.moveTo(pos.x - 5 * scale, pos.y);
      ctx.quadraticCurveTo(pos.x - 2, pos.y - 35 * scale, pos.x - 4, pos.y - 50 * scale);
      ctx.lineTo(pos.x + 4, pos.y - 50 * scale);
      ctx.quadraticCurveTo(pos.x + 2, pos.y - 35 * scale, pos.x + 5 * scale, pos.y);
      ctx.closePath();
      ctx.fill();

      // Круглые облака изумрудной листвы
      const puffs = [
        { x: -16, y: -58, r: 24, c: '#236e2f' },
        { x: 16, y: -56, r: 22, c: '#2c8538' },
        { x: 0, y: -74, r: 26, c: '#369e44' },
        { x: -8, y: -88, r: 18, c: '#48b857' }
      ];
      puffs.forEach(p => {
        ctx.beginPath();
        ctx.arc(pos.x + p.x * scale, pos.y + p.y * scale, p.r * scale, 0, Math.PI * 2);
        ctx.fillStyle = p.c;
        ctx.fill();
      });

    } else if (biomeId === 2) {
      // 3. ОСЕННИЙ БОР (Золотые и багряные кроны)
      ctx.fillStyle = '#2c1e14';
      ctx.fillRect(pos.x - 4 * scale, pos.y - 30 * scale, 8 * scale, 32 * scale);

      const autumnLeaves = [
        { x: -14, y: -48, r: 20, c: '#b33927' }, // Багряный
        { x: 14, y: -46, r: 18, c: '#cf6a17' },  // Оранжевый
        { x: 0, y: -64, r: 22, c: '#e59819' },   // Золотой
        { x: 4, y: -78, r: 15, c: '#f3b625' }    // Светло-желтый
      ];
      autumnLeaves.forEach(p => {
        ctx.beginPath();
        ctx.arc(pos.x + p.x * scale, pos.y + p.y * scale, p.r * scale, 0, Math.PI * 2);
        ctx.fillStyle = p.c;
        ctx.fill();
      });

    } else if (biomeId === 3) {
      // 4. САКУРА (Цветущие нежно-розовые кроны)
      ctx.fillStyle = '#2b211e';
      ctx.beginPath();
      ctx.moveTo(pos.x - 4 * scale, pos.y);
      ctx.quadraticCurveTo(pos.x + 6, pos.y - 25 * scale, pos.x + 3, pos.y - 48 * scale);
      ctx.lineTo(pos.x - 2, pos.y - 48 * scale);
      ctx.quadraticCurveTo(pos.x, pos.y - 25 * scale, pos.x + 3 * scale, pos.y);
      ctx.closePath();
      ctx.fill();

      const sakuraPuffs = [
        { x: -15, y: -52, r: 20, c: '#d9658b' },
        { x: 15, y: -50, r: 19, c: '#e87ea1' },
        { x: 0, y: -68, r: 22, c: '#f59bb7' },
        { x: -6, y: -80, r: 16, c: '#fcc5d5' }
      ];
      sakuraPuffs.forEach(p => {
        ctx.beginPath();
        ctx.arc(pos.x + p.x * scale, pos.y + p.y * scale, p.r * scale, 0, Math.PI * 2);
        ctx.fillStyle = p.c;
        ctx.fill();
      });

    } else if (biomeId === 4) {
      // 5. ВЫЖЖЕННЫЙ ЛЕС (Обугленные мертвые стволы и ветви)
      ctx.fillStyle = '#141414';
      ctx.beginPath();
      ctx.moveTo(pos.x - 4 * scale, pos.y);
      ctx.lineTo(pos.x - 1, pos.y - 65 * scale);
      ctx.lineTo(pos.x + 1, pos.y - 65 * scale);
      ctx.lineTo(pos.x + 4 * scale, pos.y);
      ctx.closePath();
      ctx.fill();

      // Острые сухие ветви
      ctx.strokeStyle = '#181818';
      ctx.lineWidth = 2.5 * scale;
      ctx.beginPath();
      ctx.moveTo(pos.x, pos.y - 40 * scale); ctx.lineTo(pos.x - 18 * scale, pos.y - 52 * scale);
      ctx.moveTo(pos.x, pos.y - 30 * scale); ctx.lineTo(pos.x + 16 * scale, pos.y - 42 * scale);
      ctx.moveTo(pos.x, pos.y - 52 * scale); ctx.lineTo(pos.x + 12 * scale, pos.y - 66 * scale);
      ctx.stroke();
    }
  }

  render(ctx, camera, screenW, screenH) {
    const biome = this.biomes[this.currentBiome];
    const halfW = this.tileW / 2;
    const halfH = this.tileH / 2;

    // 1. Отрисовка земли
    for (let x = 0; x < this.cols; x++) {
      for (let y = 0; y < this.rows; y++) {
        const pt = this.toScreen(x, y, camera, screenW, screenH);
        if (pt.x < -this.tileW || pt.x > screenW + this.tileW || pt.y < -this.tileH || pt.y > screenH + this.tileH) continue;

        const type = this.grid[x][y];
        const color = biome.tiles[type] || biome.tiles.grass;

        ctx.beginPath();
        ctx.moveTo(pt.x, pt.y);
        ctx.lineTo(pt.x + halfW, pt.y + halfH);
        ctx.lineTo(pt.x, pt.y + this.tileH);
        ctx.lineTo(pt.x - halfW, pt.y + halfH);
        ctx.closePath();

        ctx.fillStyle = color;
        ctx.fill();
        ctx.strokeStyle = 'rgba(0,0,0,0.15)';
        ctx.lineWidth = 0.5;
        ctx.stroke();
      }
    }

    // 2. Отрисовка деревьев с Y-сортировкой
    this.trees.sort((a, b) => (a.x + a.y) - (b.x + b.y));

    for (let i = 0; i < this.trees.length; i++) {
      const t = this.trees[i];
      const pos = this.toScreen(t.x, t.y, camera, screenW, screenH);
      if (pos.x < -100 || pos.x > screenW + 100 || pos.y < -150 || pos.y > screenH + 100) continue;

      this.drawTree(ctx, pos, t, this.currentBiome);
    }

    // 3. Виньетка
    ctx.fillStyle = biome.vignette;
    ctx.fillRect(0, 0, screenW, screenH);
  }
}

window.World = World;

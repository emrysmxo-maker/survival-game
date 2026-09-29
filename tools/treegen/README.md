# Генератор деревьев (3D → PNG-спрайты)

Все 12 пород деревьев в `assets/trees/` (и сломанные версии в `assets/trees/broken/`)
получены рендером 3D-деревьев под ТОТ ЖЕ угол камеры, что и игра
(наклон ~49°, `TILE_H/TILE_W = 48/64`). Так деревья и боец видны в одном ракурсе.

Генератор деревьев: **EZ-Tree** (@dgreenheck/ez-tree, лицензия MIT, https://github.com/dgreenheck/ez-tree).

## Как пересобрать
```bash
cd tools/treegen
npm init -y && npm i three@0.186 @dgreenheck/ez-tree --legacy-peer-deps
python3 -m http.server 8791 &          # рендер-страница render.html
python3 rt.py s4.json                  # живые деревья  -> out/*.png (720x1000)
python3 rt.py s5.json                  # сломанные      -> out/b_*.png
python3 export.py                      # цветокоррекция, 360x500, в assets/trees
```
Нужны `playwright` (Chromium) и `Pillow`. В `export.py` поправь путь `OUT`.

- `s4.json` / `s5.json` — параметры пород (сгенерированы `mkspecs.py`): пресет EZ-Tree, высота (м), ширина, оттенки.
- Картинка 360x720, основание ствола в 90% высоты (`TREE_BASE_FRAC = 0.9`, `TREE_DRAW_H = 370` в `src/config.js`), по центру.
- Если поменяешь наклон камеры (`TILE_H` в `src/ground.js`), деревья нужно перерендерить с тем же `elev` (см. `render.html`).
- Ширины оснований для радиуса упора — `TREE_TRUNK_W` в `src/config.js`.

# Генератор деревьев (3D → PNG-спрайты)

Все 12 пород деревьев в `assets/trees/` (и сломанные версии в `assets/trees/broken/`)
получены рендером 3D-деревьев под ТОТ ЖЕ угол камеры, что и игра
(наклон ~49°, `TILE_H/TILE_W = 48/64`). Так деревья и боец видны в одном ракурсе.

Модели деревьев (11 пород): **Polyy.AI 3D Deciduous Trees Pack** и **3D Coniferous Trees Pack**
(itch.io, лицензия **CC0**, https://polyyai.itch.io/3d-deciduous-trees-pack и
https://polyyai.itch.io/3d-coniferous-trees-pack). Сухостой (`04_deadwood`) — генератор
**EZ-Tree** (@dgreenheck/ez-tree, MIT). Какая модель какой породе — `s10.json`.

Скачать наборы: `python3 download_itch_packs.py 3d-deciduous-trees-pack` и
`... 3d-coniferous-trees-pack`, распаковать в папку `models/` рядом с render.html
(в репозиторий модели не кладём — 400 МБ).

## Как пересобрать
```bash
cd tools/treegen
npm init -y && npm i three@0.186 @dgreenheck/ez-tree --legacy-peer-deps
python3 -m http.server 8791 &          # рендер-страница render.html
python3 rt.py s10.json                 # все породы -> out/*.png (720x1440)
python3 export.py                      # цветокоррекция, 360x500, в assets/trees
```
Нужны `playwright` (Chromium) и `Pillow`. В `export.py` поправь путь `OUT`.

- `s10.json` — порода → модель (glb) или пресет EZ-Tree, высота (м), ширина.
- Ветер (покачивание крон) — в игре, `drawSwaying` в `src/render.js`, настройки `WIND_*` в `src/config.js`.
- Картинка 360x720, основание ствола в 90% высоты (`TREE_BASE_FRAC = 0.9`, `TREE_DRAW_H = 370` в `src/config.js`), по центру.
- Если поменяешь наклон камеры (`TILE_H` в `src/ground.js`), деревья нужно перерендерить с тем же `elev` (см. `render.html`).
- Ширины оснований для радиуса упора — `TREE_TRUNK_W` в `src/config.js`.

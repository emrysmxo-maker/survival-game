// Загрузка картинок. Ни одна фигура тут не рисуется кодом — только
// подготовка готовых PNG/JPG-спрайтов (assets/...), которые расставляют
// world.js (где) и render.js (как).

const treeSprites = TREE_FILES.map((file) => {
  const img = new Image();
  img.src = `assets/trees/${file}?v=${ASSET_VERSION}`;
  return img;
});

// Сломанные ветром версии тех же пород (обломанный ствол с рваным изломом),
// нарезаны в той же сетке 360x500 с тем же основанием ствола. У сухостоя (4)
// сломанной версии нет — он и так мёртвый.
const brokenTreeSprites = TREE_FILES.map((file, i) => {
  if (i === 4) return null;
  const img = new Image();
  img.src = `assets/trees/broken/${file}?v=${ASSET_VERSION}`;
  return img;
});
function isBrokenRoll(type, r) {
  return type !== 4 && r < BROKEN_TREE_CHANCE;
}

const groundImages = GROUND_TEXTURE_FILES.map((file) => {
  const img = new Image();
  img.src = `assets/ground/${file}?v=${ASSET_VERSION}`;
  return img;
});

const clutterSprites = {};
for (const kind in CLUTTER_TYPES) {
  clutterSprites[kind] = CLUTTER_TYPES[kind].files.map((file) => {
    const img = new Image();
    img.src = `assets/clutter/${file}?v=${ASSET_VERSION}`;
    return img;
  });
}

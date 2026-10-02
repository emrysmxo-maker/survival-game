const DBG = { noPieces: false, noWind: false, noSunShadow: false, noSlopeLight: false, loOnly: false, noHole: false, noZoom: false, noPlants: false };
const DBG_LABELS = {
  noPieces: 'Без отклонения кустов (стоят неподвижно)',
  noWind: 'Без ветра (кусты и деревья не качаются)',
  noSunShadow: 'Без теней от солнца (деревья, боец, кусты)',
  noSlopeLight: 'Без светотени склонов и ям',
  loOnly: 'Земля только в одном качестве',
  noHole: 'Без окошка в кроне над бойцом',
  noZoom: 'Без зума камеры в ямах',
  noPlants: 'Убрать подлесок совсем'
};
(function () {
  try {
    const saved = JSON.parse(localStorage.getItem('dbg') || '{}');
    Object.assign(DBG, saved);
    if (!saved._v70_relief) {
      DBG.noSlopeLight = false;
      saved._v70_relief = true;
      saved.noSlopeLight = false;
      localStorage.setItem('dbg', JSON.stringify(saved));
    }
    if (saved.noPieces === undefined) DBG.noPieces = false;
  } catch (e) { /* нет хранилища */ }
  const save = () => { try { localStorage.setItem('dbg', JSON.stringify(DBG)); } catch (e) { /* ignore */ } };
  const box = document.createElement('div');
  box.id = 'dbg';
  box.style.cssText = 'position:fixed;left:8px;top:96px;z-index:40;font:13px sans-serif;color:#eee;touch-action:auto;';
  const btn = document.createElement('div');
  btn.textContent = '⚙';
  btn.style.cssText = 'width:38px;height:38px;line-height:38px;text-align:center;font-size:22px;background:rgba(10,16,10,0.78);border:1px solid rgba(255,255,255,0.25);border-radius:10px;cursor:pointer;';
  const panel = document.createElement('div');
  panel.style.cssText = 'display:none;margin-top:6px;padding:8px 10px;background:rgba(10,16,10,0.9);border:1px solid rgba(255,255,255,0.25);border-radius:10px;max-width:330px;max-height:calc(100vh - 160px);overflow-y:auto;-webkit-overflow-scrolling:touch;';
  for (const k in DBG_LABELS) {
    const row = document.createElement('label');
    row.style.cssText = 'display:flex;align-items:center;gap:8px;padding:4px 0;';
    const cb = document.createElement('input');
    cb.type = 'checkbox'; cb.checked = !!DBG[k];
    cb.style.cssText = 'width:22px;height:22px;accent-color:#e0a040;';
    cb.addEventListener('change', () => { DBG[k] = cb.checked; save(); });
    row.appendChild(cb); row.appendChild(document.createTextNode(DBG_LABELS[k]));
    panel.appendChild(row);
  }
  btn.addEventListener('click', () => { panel.style.display = panel.style.display === 'none' ? 'block' : 'none'; });
  box.appendChild(btn); box.appendChild(panel);
  document.addEventListener('DOMContentLoaded', () => document.body.appendChild(box));
  if (document.body) document.body.appendChild(box);
})();

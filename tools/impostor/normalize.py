# Выравнивание цвета импосторов: у моделей разная экспозиция (сосны почти чёрные,
# берёза/осина желтоватые). Средняя яркость листвы приводится к одной цели по виду.
# python3 normalize.py <папка с *_albedo.png и meta.json>
import sys, json, numpy as np
from PIL import Image
d = sys.argv[1]
m = json.load(open(f'{d}/meta.json'))
TARGET = {'tree': 0.34, 'sapling': 0.33, 'shrub': 0.33, 'fern': 0.34, 'nettle': 0.33, 'grass': 0.36, 'flower': 0.38, 'dead': 0.30}
for k, v in m.items():
    cat = v['spec']['cat']
    if cat not in TARGET:
        continue
    p = f'{d}/{k}_albedo.png'
    a = np.asarray(Image.open(p).convert('RGBA')).astype(np.float32) / 255
    rgb = a[..., :3]
    if k.startswith(('birch', 'aspen')):
        # жёлтая листва EZ-Tree -> зелёная; белая кора ствола не трогаем
        yel = np.clip((rgb[..., 0] - rgb[..., 2]) * 4.0, 0, 1)[..., None]
        rgb = rgb * (1 - yel) + (rgb * np.array([0.72, 1.0, 1.45])) * yel
    if k == 'dead2_0':
        rgb = rgb * np.array([0.62, 0.52, 0.42])         # голая белая кора -> серо-коричневая
    msk = a[..., 3] > 0.5
    L = float((rgb[msk] @ np.array([0.2126, 0.7152, 0.0722])).mean())
    k_gain = TARGET[cat] / max(L, 1e-3)
    k_gain = float(np.clip(k_gain, 0.6, 2.4))
    rgb = np.clip(rgb * k_gain, 0, 1)
    out = np.concatenate([rgb, a[..., 3:4]], -1)
    Image.fromarray((out * 255 + 0.5).astype(np.uint8), 'RGBA').save(p, optimize=True)
    v['norm_gain'] = round(k_gain, 3)
json.dump(m, open(f'{d}/meta.json', 'w'), indent=1)
print('ok', len(m))

# Маска непрозрачности (сетка 24×48, строка «0/1») — для проверки в игре,
# закрывает ли крона бойца (world.gd → occluded)
MW, MH = 24, 48
for k, v in m.items():
    a = Image.open(f'{d}/{k}_albedo.png').convert('RGBA').split()[3].resize((MW, MH), Image.BILINEAR)
    arr = np.asarray(a) > 100
    v['mask'] = ''.join('1' if b else '0' for b in arr.flatten())
    v['mask_w'] = MW
    v['mask_h'] = MH
json.dump(m, open(f'{d}/meta.json', 'w'), indent=1)
print('masks ok')

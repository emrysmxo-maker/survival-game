# Предпросмотр импосторов: цвет × свет (по нормали) × AO, на фоне земли
import sys, glob, numpy as np
from PIL import Image, ImageDraw
names = sys.argv[2:]
H = 420
tiles = []
L = np.array([-0.5, 0.6, 0.62]); L /= np.linalg.norm(L)
for n in names:
    a = np.asarray(Image.open(f'{n}_albedo.png').convert('RGBA')).astype(np.float32) / 255
    d = np.asarray(Image.open(f'{n}_ndt.png').convert('RGBA')).astype(np.float32) / 255
    nx, ny = d[..., 0] * 2 - 1, d[..., 1] * 2 - 1
    nz = np.sqrt(np.clip(1 - nx * nx - ny * ny, 0, 1))
    ndl = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0, 1)
    lit = a[..., :3] * (0.35 * d[..., 3:4] + 0.9 * ndl[..., None] * (0.4 + 0.6 * d[..., 3:4]))
    bg = np.ones_like(lit) * np.array([0.33, 0.36, 0.25])
    img = bg * (1 - a[..., 3:4]) + lit * a[..., 3:4]
    im = Image.fromarray((img.clip(0, 1) * 255).astype(np.uint8))
    im = im.resize((max(1, int(im.width * H / im.height)), H))
    tiles.append((n, im))
W = sum(t[1].width for t in tiles) + 8 * len(tiles)
s = Image.new('RGB', (W, H + 16), (40, 40, 40)); dr = ImageDraw.Draw(s); x = 0
for n, im in tiles:
    s.paste(im, (x, 16)); dr.text((x + 2, 2), n, fill='white'); x += im.width + 8
s.save(sys.argv[1], quality=85)

# Текстуры заброшенных построек и машин (процедурные, без внешних файлов): python3 tex.py <папка>
import sys, numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter
OUT = sys.argv[1]
rng = np.random.default_rng(7)

def noise(n, sig, seed=None, aniso=(1, 1)):
    r = np.random.default_rng(seed) if seed is not None else rng
    a = r.normal(size=(n, n))
    a = gaussian_filter(a, (sig * aniso[0], sig * aniso[1]), mode='wrap')
    a -= a.min(); a /= max(a.max(), 1e-6)
    return a

def fbm(n, sig, seed, octs=4):
    t = np.zeros((n, n)); amp = 1.0; tot = 0
    for o in range(octs):
        t += amp * noise(n, max(0.7, sig / (2 ** o)), seed + o); tot += amp; amp *= 0.5
    t /= tot
    return (t - t.min()) / (t.max() - t.min())

def sm(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

def mix(a, b, m):
    return a * (1 - m[..., None]) + b * m[..., None]

def col(n, c):
    return np.ones((n, n, 3)) * np.array(c, float)

def save(name, img, q=88):
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(f'{OUT}/{name}.jpg', quality=q)

N = 512
Y, X = np.mgrid[0:N, 0:N] / N

# --- бревенчатая стена: 5 брёвен на тайл (1 м), серо-бурое, обветренное, мох ---
def logs():
    rows = 5
    v = (Y * rows) % 1.0
    ri = (Y * rows).astype(int)
    cyl = np.sqrt(np.clip(1 - (2 * v - 1) ** 2, 0, 1))
    grain = noise(N, 2, 11, (0.4, 22)) * 0.6 + noise(N, 1, 12, (0.3, 10)) * 0.4
    tint = np.array([rng.uniform(0.85, 1.12) for _ in range(rows + 1)])[ri]
    base = col(N, (118, 98, 76)) * (0.55 + 0.45 * cyl)[..., None] * tint[..., None]
    gray = col(N, (128, 124, 116)) * (0.6 + 0.4 * cyl)[..., None]
    base = mix(base, gray, sm(fbm(N, 14, 21), 0.45, 0.8) * 0.75)       # вылинявшее серебро
    base *= (0.78 + 0.34 * grain)[..., None]
    crack = sm(noise(N, 1.2, 31, (0.2, 40)), 0.8, 0.9)
    base *= (1 - 0.5 * crack)[..., None]
    base = mix(base, col(N, (62, 78, 38)), sm(fbm(N, 10, 41), 0.62, 0.78) * 0.55 * (1 - cyl * 0.4))   # мох
    gap = sm(np.abs(2 * v - 1), 0.9, 1.0)
    base *= (1 - 0.7 * gap)[..., None]
    return base

# --- вертикальные доски (сарай, забор), параметр — остатки краски ---
def boards(paint=None, seed=51):
    nb = 8
    u = (X * nb) % 1.0
    bi = (X * nb).astype(int)
    tint = np.array([rng.uniform(0.8, 1.15) for _ in range(nb + 1)])[bi]
    grain = noise(N, 2, seed, (22, 0.4)) * 0.6 + noise(N, 1, seed + 1, (10, 0.3)) * 0.4
    wood = col(N, (112, 100, 86)) * tint[..., None]
    wood = mix(wood, col(N, (140, 136, 128)), sm(fbm(N, 14, seed + 2), 0.4, 0.75) * 0.7)
    wood *= (0.76 + 0.4 * grain)[..., None]
    if paint is not None:
        m = sm(fbm(N, 26, seed + 3, 3), 0.36, 0.5) * (1 - sm(noise(N, 1.5, seed + 4, (30, 0.5)), 0.75, 0.9))
        wood = mix(wood, col(N, paint) * (0.85 + 0.25 * grain)[..., None], m)
    wood = mix(wood, col(N, (60, 76, 38)), sm(fbm(N, 10, seed + 5), 0.66, 0.8) * 0.5)
    gap = sm(np.abs(2 * u - 1), 0.92, 1.0)
    wood *= (1 - 0.75 * gap)[..., None]
    wood *= (1 - 0.45 * sm(noise(N, 1.0, seed + 6, (40, 0.3)), 0.82, 0.92))[..., None]
    return wood

# --- кирпич с остатками штукатурки ---
def brick():
    rows, per = 14, 4
    v = (Y * rows) % 1.0
    ri = (Y * rows).astype(int)
    xs = (X * per + (ri % 2) * 0.5) % 1.0
    bid = ((X * per + (ri % 2) * 0.5).astype(int) + ri * 7) % 23
    tint = (0.75 + 0.5 * np.random.default_rng(5).random(23))[bid]
    br = col(N, (140, 62, 44)) * tint[..., None] * (0.8 + 0.3 * noise(N, 1.2, 61))[..., None]
    mort = (v < 0.1) | (v > 0.93) | (xs < 0.04) | (xs > 0.97)
    out = np.where(mort[..., None], col(N, (150, 146, 138)), br)
    pl = sm(fbm(N, 38, 62, 3), 0.56, 0.68)                                       # штукатурка
    pc = mix(col(N, (196, 186, 164)), col(N, (170, 160, 140)), noise(N, 2, 63))
    out = mix(out, pc, pl * 0.95)
    out = mix(out, col(N, (60, 76, 40)), sm(fbm(N, 24, 64, 3), 0.7, 0.82) * 0.4)
    out *= (1 - 0.45 * sm(noise(N, 1.0, 65, (30, 0.4)), 0.7, 0.95))[..., None]  # потёки
    return out

# --- шифер (серый волнистый), лишайник, потёки ---
def slate():
    wave = 0.5 + 0.5 * np.sin(X * 2 * np.pi * 8)
    base = col(N, (122, 122, 116)) * (0.72 + 0.34 * wave)[..., None]
    base *= (0.85 + 0.3 * fbm(N, 6, 71))[..., None]
    base = mix(base, col(N, (134, 140, 80)), sm(fbm(N, 9, 72), 0.6, 0.78) * 0.6)    # лишайник
    base = mix(base, col(N, (60, 72, 40)), sm(fbm(N, 11, 73), 0.72, 0.86) * 0.55)    # мох
    base *= (1 - 0.5 * sm(noise(N, 1.0, 74, (40, 0.4)), 0.75, 0.93))[..., None]
    seam = sm(np.abs(((Y * 3) % 1.0) - 0.5), 0.46, 0.5)
    base *= (1 - 0.3 * (1 - seam))[..., None] if False else 1
    return base

# --- ржавое железо (гофра): зелёная краска слезла до ржавчины ---
def roofmetal():
    wave = 0.5 + 0.5 * np.sin(X * 2 * np.pi * 10)
    rust = mix(col(N, (122, 62, 28)), col(N, (86, 44, 24)), fbm(N, 6, 81))
    rust = mix(rust, col(N, (160, 90, 40)), sm(fbm(N, 3, 82), 0.62, 0.85) * 0.6)
    paint = col(N, (84, 106, 78)) * (0.85 + 0.3 * noise(N, 2, 83))[..., None]
    m = sm(fbm(N, 14, 84), 0.5, 0.64)
    out = mix(rust, paint, m * 0.85)
    out *= (0.66 + 0.5 * wave)[..., None]
    out *= (1 - 0.4 * sm(noise(N, 1.0, 85, (40, 0.4)), 0.75, 0.93))[..., None]
    return out

def concrete():
    base = col(N, (138, 136, 130)) * (0.8 + 0.4 * fbm(N, 5, 91))[..., None]
    base = mix(base, col(N, (70, 82, 46)), sm(fbm(N, 10, 92), 0.64, 0.8) * 0.5)
    base *= (1 - 0.4 * sm(noise(N, 1.2, 93, (20, 0.5)), 0.78, 0.92))[..., None]
    return base

def floorwood():
    return boards(None, 95) * 0.55

def rustmetal():
    base = mix(col(N, (96, 52, 30)), col(N, (60, 38, 28)), fbm(N, 5, 101))
    base = mix(base, col(N, (140, 78, 36)), sm(fbm(N, 3, 102), 0.6, 0.85) * 0.6)
    return base * (0.85 + 0.3 * noise(N, 1.0, 103))[..., None]

# --- краска автомобиля: выгоревшая, грязная, мелкая ржавчина; без ярких пятен ---
def car(name, rgb, seed):
    n = 512
    global N, Y, X
    N0 = N
    N = n; Y, X = np.mgrid[0:N, 0:N] / N
    rgb = np.array(rgb, float)
    base = col(N, rgb) * (0.88 + 0.16 * fbm(N, 20, seed, 4))[..., None]
    fade = sm(fbm(N, 28, seed + 1, 3), 0.4, 0.75)
    base = mix(base, np.clip(rgb * 1.18 + 14, 0, 255) * np.ones((N, N, 3)), fade * 0.35)       # выгорание
    base = mix(base, col(N, (92, 84, 70)), sm(fbm(N, 16, seed + 4, 4), 0.55, 0.85) * 0.38)      # пыль и грязь
    # ржавчина: мелкие очаги, крупные редкие + царапины
    fine = sm(fbm(N, 3.5, seed + 2, 4), 0.62, 0.78)
    big = sm(fbm(N, 22, seed + 3, 3), 0.68, 0.8)
    rustc = mix(col(N, (110, 56, 30)), col(N, (66, 40, 28)), fbm(N, 4, seed + 5))
    base = mix(base, rustc, np.clip(fine * big * 1.4 + fine * 0.35, 0, 1) * 0.92)
    sc = sm(noise(N, 0.8, seed + 6, (14, 0.5)), 0.86, 0.94)
    base = mix(base, np.clip(rgb * 0.5, 0, 255) * np.ones((N, N, 3)), sc * 0.5)
    base *= (1 - 0.4 * sm(noise(N, 1.0, seed + 7, (40, 0.35)), 0.8, 0.94))[..., None]            # потёки
    save(name, base, 90)
    N = N0; Y, X = np.mgrid[0:N, 0:N] / N

def tire():
    base = col(N, (34, 33, 32)) * (0.8 + 0.4 * noise(N, 1.2, 301))[..., None]
    base = mix(base, col(N, (92, 86, 76)), sm(fbm(N, 14, 302), 0.55, 0.8) * 0.4)
    stripes = (np.sin(Y * 2 * np.pi * 14) > 0.4)
    return base * (0.85 + 0.15 * stripes)[..., None]

def glass():
    base = col(N, (24, 32, 34)) * (0.8 + 0.5 * fbm(N, 20, 311))[..., None]
    streak = sm(noise(N, 1.0, 312, (30, 0.4)), 0.7, 0.95)
    return mix(base, col(N, (96, 106, 104)), streak * 0.35)

def sheet(rgb, seed):         # крашеная жесть (бочки, баки, кабины)
    return car_tex(rgb, seed)

def car_tex(rgb, seed):
    global N, Y, X
    N0 = N; N = 512; Y, X = np.mgrid[0:N, 0:N] / N
    rgb = np.array(rgb, float)
    base = col(N, rgb) * (0.88 + 0.16 * fbm(N, 20, seed, 4))[..., None]
    base = mix(base, col(N, (92, 84, 70)), sm(fbm(N, 16, seed + 4, 4), 0.55, 0.85) * 0.38)
    fine = sm(fbm(N, 3.5, seed + 2, 4), 0.6, 0.78)
    base = mix(base, mix(col(N, (110, 56, 30)), col(N, (66, 40, 28)), fbm(N, 4, seed + 5)), fine * 0.9)
    out = base; N = N0; Y, X = np.mgrid[0:N, 0:N] / N
    return out


# --- кора (полосы вдоль U), торец спила, солома, брезент, земля грядок, жесть ---
def bark():
    streak = noise(N, 1.5, 401, (0.25, 18)) * 0.6 + noise(N, 1.0, 402, (0.2, 8)) * 0.4
    base = mix(col(N, (62, 50, 40)), col(N, (110, 96, 80)), sm(streak, 0.3, 0.85))
    base = mix(base, col(N, (70, 82, 44)), sm(fbm(N, 12, 403), 0.7, 0.85) * 0.45)
    return base * (0.7 + 0.5 * noise(N, 1.0, 404))[..., None]

def endgrain():
    cx, cy = 0.5, 0.5
    r = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2)
    rings = 0.5 + 0.5 * np.sin(r * 2 * np.pi * 22 + 3 * noise(N, 6, 411))
    base = mix(col(N, (170, 138, 92)), col(N, (128, 96, 60)), rings)
    base = mix(base, col(N, (92, 70, 48)), sm(r, 0.44, 0.5))
    return base * (0.9 + 0.2 * noise(N, 1.0, 412))[..., None]

def hay():
    s1 = noise(N, 0.8, 421, (0.3, 6)) * 0.5 + noise(N, 0.6, 422, (6, 0.3)) * 0.5
    base = mix(col(N, (150, 124, 62)), col(N, (206, 178, 98)), s1)
    base = mix(base, col(N, (96, 90, 50)), sm(fbm(N, 14, 423), 0.6, 0.85) * 0.5)
    return base

def canvas(rgb, seed):
    weave = 0.9 + 0.1 * np.sin(X * 2 * np.pi * 90) * np.sin(Y * 2 * np.pi * 90)
    base = col(N, rgb) * (0.85 + 0.25 * fbm(N, 14, seed, 4))[..., None] * weave[..., None]
    base = mix(base, col(N, (70, 66, 52)), sm(fbm(N, 10, seed + 1), 0.55, 0.85) * 0.5)
    base = mix(base, col(N, (60, 78, 40)), sm(fbm(N, 12, seed + 2), 0.7, 0.85) * 0.4)
    return base * (1 - 0.35 * sm(noise(N, 1.0, seed + 3, (30, 0.4)), 0.78, 0.94))[..., None]

def soil():
    furrow = 0.5 + 0.5 * np.sin(X * 2 * np.pi * 6)
    base = mix(col(N, (58, 42, 30)), col(N, (92, 68, 46)), furrow * 0.6 + 0.4 * fbm(N, 3, 431))
    base = mix(base, col(N, (74, 92, 44)), sm(fbm(N, 6, 432), 0.62, 0.8) * 0.55)       # сорняки
    return base

def earth():
    base = mix(col(N, (84, 66, 44)), col(N, (108, 88, 58)), fbm(N, 6, 451))
    base = mix(base, col(N, (74, 96, 48)), sm(fbm(N, 14, 452), 0.45, 0.7) * 0.85)
    base = mix(base, col(N, (120, 112, 90)), sm(noise(N, 1.2, 453), 0.8, 0.9) * 0.5)
    return base * (0.85 + 0.3 * noise(N, 0.8, 454))[..., None]

def tin(rgb, seed):
    wave = 0.5 + 0.5 * np.sin(Y * 2 * np.pi * 10)
    base = col(N, rgb) * (0.7 + 0.5 * wave)[..., None] * (0.85 + 0.2 * fbm(N, 10, seed))[..., None]
    rust = mix(col(N, (120, 62, 30)), col(N, (80, 46, 28)), fbm(N, 4, seed + 1))
    base = mix(base, rust, sm(fbm(N, 7, seed + 2), 0.55, 0.75) * 0.8)
    return base * (1 - 0.4 * sm(noise(N, 1.0, seed + 3, (40, 0.4)), 0.78, 0.93))[..., None]

def asphalt():
    base = col(N, (70, 70, 68)) * (0.8 + 0.4 * noise(N, 0.8, 441))[..., None]
    base = mix(base, col(N, (96, 94, 86)), sm(fbm(N, 12, 442), 0.6, 0.8) * 0.5)
    cr = sm(noise(N, 0.7, 443, (0.2, 30)), 0.88, 0.95)
    return base * (1 - 0.6 * cr)[..., None]

save('earth', earth()); save('bark', bark()); save('endgrain', endgrain()); save('hay', hay()); save('soil', soil()); save('asphalt', asphalt())
save('canvas_olive', canvas((92, 98, 66), 451)); save('canvas_tan', canvas((150, 134, 98), 461)); save('tarp_blue', canvas((58, 94, 132), 471))
save('tin_gray', tin((146, 148, 144), 481)); save('tin_green', tin((86, 108, 84), 491)); save('tin_blue', tin((70, 100, 130), 501)); save('tin_red', tin((130, 56, 44), 511))
save('logs', logs()); save('boards_gray', boards(None, 51))
save('boards_green', boards((74, 112, 92), 52)); save('boards_blue', boards((70, 100, 140), 53)); save('boards_red', boards((130, 52, 40), 54))
save('brick', brick()); save('slate', slate()); save('roofmetal', roofmetal())
save('concrete', concrete()); save('floorwood', floorwood()); save('rustmetal', rustmetal())
car('car_red', (122, 44, 38), 200); car('car_blue', (66, 92, 122), 210); car('car_white', (196, 194, 184), 220)
car('car_green', (70, 92, 66), 230); car('car_olive', (92, 94, 62), 240); car('car_yellow', (176, 150, 62), 250); car('car_brown', (110, 80, 54), 260)
car('car_gray', (120, 124, 124), 270); car('car_orange', (170, 96, 40), 280); car('car_teal', (60, 104, 100), 290)
save('tire', tire()); save('glass', glass())
from PIL import ImageDraw
_im = Image.new('RGBA', (256, 256), (0, 0, 0, 0)); _d = ImageDraw.Draw(_im)
for _i in range(-256, 512, 24):
    _d.line([(_i, 0), (_i + 256, 256)], fill=(120, 122, 120, 255), width=3); _d.line([(_i, 256), (_i + 256, 0)], fill=(120, 122, 120, 255), width=3)
_im.save(f'{OUT}/chain.png')
_im2 = Image.new('RGBA', (256, 256), (0, 0, 0, 0)); _d2 = ImageDraw.Draw(_im2)
for _i in range(-256, 512, 32):
    _d2.line([(_i, 0), (_i + 256, 256)], fill=(34, 52, 36, 255), width=3); _d2.line([(_i, 256), (_i + 256, 0)], fill=(34, 52, 36, 255), width=3)
_im2.save(f'{OUT}/net.png')
print('ok')

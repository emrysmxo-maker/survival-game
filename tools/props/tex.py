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
    pl = sm(fbm(N, 38, 62, 3), 0.42, 0.56)                                       # штукатурка
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

# --- краска автомобиля (с ржавчиной и грязью) ---
def car(name, rgb, seed):
    n = 256
    global N, Y, X
    N0 = N
    N = n; Y, X = np.mgrid[0:N, 0:N] / N
    paint = col(N, rgb) * (0.85 + 0.25 * noise(N, 3, seed))[..., None]
    fade = sm(fbm(N, 9, seed + 1), 0.45, 0.7)
    paint = mix(paint, col(N, rgb) * 1.25 + 25, fade * 0.35)            # выгорание
    rust = mix(col(N, (112, 56, 28)), col(N, (74, 42, 26)), fbm(N, 4, seed + 2))
    rm = sm(fbm(N, 12, seed + 3, 3), 0.58, 0.72) * 0.85
    out = mix(paint, rust, rm)
    out = mix(out, col(N, (88, 80, 64)), sm(fbm(N, 12, seed + 4), 0.55, 0.8) * 0.4)   # пыль
    out *= (1 - 0.4 * sm(noise(N, 1.0, seed + 5, (30, 0.4)), 0.78, 0.94))[..., None]
    save(name, out, 90)
    N = N0; Y, X = np.mgrid[0:N, 0:N] / N

save('logs', logs()); save('boards_gray', boards(None, 51))
save('boards_green', boards((74, 112, 92), 52)); save('boards_blue', boards((70, 100, 140), 53)); save('boards_red', boards((130, 52, 40), 54))
save('brick', brick()); save('slate', slate()); save('roofmetal', roofmetal())
save('concrete', concrete()); save('floorwood', floorwood()); save('rustmetal', rustmetal())
car('car_red', (150, 40, 34), 200); car('car_blue', (58, 92, 140), 210); car('car_white', (205, 204, 196), 220)
car('car_green', (74, 104, 70), 230); car('car_olive', (96, 100, 60), 240); car('car_yellow', (200, 168, 52), 250)
print('ok')

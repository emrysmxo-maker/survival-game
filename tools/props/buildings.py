# Дома и хозпостройки (расширенный набор): избушка/баня, дача, магазин, дом культуры, часовня, теплица, навес. python -I buildings.py <выход> [превью]; ONLY=...
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *
from rural import PM
import houses
from houses import wall, roof, debris, planks_on_ground

OUT = sys.argv[1]
PRE = sys.argv[2] if len(sys.argv) > 2 else None

def hole_set(rnd, nx, ns, k=2, rad=(1.0, 2.0)):
    """дыры в крыше: k округлых провалов случайного размера; возвращает множество (i, j)"""
    cells = set()
    for _ in range(k):
        ci = rnd.uniform(1, nx - 2); cj = rnd.uniform(1, ns - 1.5); r = rnd.uniform(*rad)
        for i in range(nx):
            for j in range(ns):
                if (i - ci) ** 2 + ((j - cj) * 1.2) ** 2 < r * r: cells.add((i, j))
    return cells

def gable_house(name, seed, L, D, wh, th, wallm, roofm, front, back, left, right, chimney=0.0, porch=None, holes=2, cell=0.62, eave=0.45, gable='wood', frame='wood', tilt=0.0, ridge_k=0.58, cond=1.0):
    rnd = random.Random(seed); M = PM(); a = Acc()
    zf = 0.32
    a.box(M['conc'], (0, 0, zf / 2), (L + 0.3, D + 0.3, zf))
    ys, xs = D / 2 - th / 2, L / 2 - th / 2
    mw = M[wallm]; fm = M[frame]
    wall(a, mw, (-L / 2, -ys), (L / 2, -ys), th, wh, front, zf, fm, M['dark'], M['glass'], rnd)
    wall(a, mw, (-L / 2, ys), (L / 2, ys), th, wh, back, zf, fm, M['dark'], M['glass'], rnd)
    wall(a, mw, (-xs, -ys), (-xs, ys), th, wh, left, zf, fm, M['dark'], M['glass'], rnd)
    wall(a, mw, (xs, -ys), (xs, ys), th, wh, right, zf, fm, M['dark'], M['glass'], rnd)
    rise = (D / 2 + eave) * ridge_k * 0.62
    for sx in (-1, 1):
        a.poly(M[gable], [(sx * xs - th / 2, -ys - 0.1, zf + wh), (sx * xs - th / 2, ys + 0.1, zf + wh), (sx * xs - th / 2, 0, zf + wh + rise * 0.98)], (th, 0, 0))
    ze = zf + wh - 0.05; rz = zf + wh + rise
    nx = max(1, round((L + 2 * eave) / cell)); ns = max(1, round(math.hypot(D / 2 + eave, rise) / cell))
    hs = {-1: hole_set(rnd, nx, ns, holes), 1: hole_set(rnd, nx, ns, max(0, holes - 1))}
    def skip(i, j, side, nx_, ns_):
        return (i, j) in hs[side] or rnd.random() < 0.05 * cond
    roof(a, M[roofm], M['wood'], -L / 2 - eave, L / 2 + eave, -(D / 2 + eave), D / 2 + eave, ze, rz, 0, skip, rnd, cell=cell)
    a.box(M['floor'], (0, 0, zf + wh - 0.06), (L - 0.5, D - 0.5, 0.08)); a.box(M['floor'], (0, 0, zf + 0.04), (L - 0.5, D - 0.5, 0.06))
    debris(a, M[roofm], rnd, rnd.uniform(-1, 1), rnd.uniform(-0.8, 0.8), zf + wh - 0.02, 0.9, 8)
    if chimney > 0:
        a.box(M['brick'], (L * 0.1, 0.0, zf + wh + rise * 0.6 + chimney / 2), (0.55, 0.55, chimney * 0.95 + rise * 0.5)); a.box(M['brick'], (L * 0.1, 0, zf + wh + rise * 0.6 + chimney + 0.1), (0.68, 0.68, 0.1))
    if porch:
        px, pw = porch
        a.box(M['floor'], (px, -ys - 0.8, zf * 0.7), (pw, 1.2, 0.16))
        for sx in (px - pw / 2 + 0.1, px + pw / 2 - 0.1): a.box(M['wood'], (sx, -ys - 1.3, 1.1), (0.13, 0.13, 2.0))
        a.box(M['wood'], (px, -ys - 1.3, 2.1), (pw, 0.15, 0.15))
        for i in range(3):
            if i != 1: a.box(M[roofm], (px - pw / 2 + (i + 0.5) * pw / 3, -ys - 0.9, 2.25), (pw / 3, 1.5, 0.06), rot=(-0.25, 0, 0))
    planks_on_ground(a, M['wood'], rnd, 0, -ys - 1.6, 3.2, 6)
    o = a.build(name)
    return o

def cabin(name, seed): return gable_house(name, seed, 4.9, 3.9, 2.1, 0.22, 'logs', 'tin', [(-1.0, 0.9, 0.0, 1.85, False), (1.1, 0.8, 0.9, 0.9)], [(0.0, 0.8, 0.9, 0.9)], [], [(0.0, 0.8, 0.9, 0.9)], chimney=1.3, porch=(-1.0, 1.6), holes=1, cell=0.55)
def banya(name, seed): return gable_house(name, seed, 4.0, 3.2, 2.0, 0.22, 'logs', 'slate', [(-0.8, 0.8, 0.0, 1.7, False)], [(0.6, 0.5, 1.1, 0.5)], [], [], chimney=1.6, holes=1, cell=0.55)
def dacha_a(name, seed): return gable_house(name, seed, 5.6, 4.4, 2.3, 0.16, 'green', 'tin_green', [(-1.3, 0.9, 0.0, 1.9, False), (0.7, 1.0, 0.9, 1.1), (2.0, 0.9, 0.9, 1.1)], [(-1.5, 0.9, 0.9, 1.0), (1.2, 0.9, 0.9, 1.0)], [(0, 0.9, 0.9, 1.0)], [(0, 0.9, 0.9, 1.0)], chimney=0.9, porch=(-1.3, 2.0), holes=1, gable='green')
def dacha_b(name, seed): return gable_house(name, seed, 6.0, 4.6, 2.3, 0.16, 'blue', 'tin_red', [(-1.5, 0.9, 0.0, 1.9, False), (0.8, 1.2, 0.9, 1.1), (2.3, 0.9, 0.9, 1.1)], [(-1.6, 0.9, 0.9, 1.0), (0.4, 0.9, 0.9, 1.0), (2.2, 0.9, 0.9, 1.0)], [(0.2, 0.9, 0.9, 1.0)], [(0.2, 0.9, 0.9, 1.0)], chimney=1.0, porch=(-1.5, 2.2), holes=2, gable='blue')
def dacha_c(name, seed): return gable_house(name, seed, 5.2, 4.2, 2.3, 0.16, 'red', 'metal', [(-1.2, 0.9, 0.0, 1.9, False), (0.9, 1.0, 0.9, 1.1)], [(0, 1.0, 0.9, 1.0)], [(0.0, 0.9, 0.9, 1.0)], [(0.0, 0.9, 0.9, 1.0)], chimney=0.9, holes=2, gable='red')
def dacha_d(name, seed): return gable_house(name, seed, 5.4, 4.2, 2.3, 0.2, 'wood', 'slate', [(1.3, 0.9, 0.0, 1.9, False), (-0.9, 1.0, 0.9, 1.1)], [(0, 1.0, 0.9, 1.0), (1.8, 0.9, 0.9, 1.0)], [(0.0, 0.9, 0.9, 1.0)], [], chimney=0.9, porch=(1.3, 1.8), holes=2, gable='wood')
def izba_c(name, seed): return gable_house(name, seed, 6.6, 4.8, 2.3, 0.24, 'logs', 'slate', [(-1.5, 0.95, 0.0, 1.95, False), (0.7, 1.0, 0.9, 1.1), (2.3, 1.0, 0.9, 1.1)], [(-2.0, 0.9, 0.9, 1.0), (0.2, 0.9, 0.9, 1.0), (2.2, 0.9, 0.9, 1.0)], [(0.0, 0.9, 0.9, 1.0)], [(0.0, 0.9, 0.9, 1.0)], chimney=1.3, porch=(-1.5, 2.0), holes=2)
def house_brick_small(name, seed): return gable_house(name, seed, 7.4, 5.4, 2.7, 0.4, 'brick', 'slate', [(1.2, 1.0, 0.0, 2.1, False), (-1.8, 1.1, 0.95, 1.3), (-0.2, 1.1, 0.95, 1.3), (3.0, 1.1, 0.95, 1.3)], [(-2.2, 1.1, 0.95, 1.3), (0.2, 1.1, 0.95, 1.3), (2.6, 1.1, 0.95, 1.3)], [(0, 1.1, 0.95, 1.3)], [(0, 1.1, 0.95, 1.3)], chimney=1.4, holes=2, eave=0.5, gable='brick')

# ---------- магазин (сельпо): кирпичный, плоская крыша, витрина ----------
def shop(name, seed):
    rnd = random.Random(seed); M = PM(); a = Acc()
    L, D, wh, th = 9.0, 5.6, 3.1, 0.4; zf = 0.3
    a.box(M['conc'], (0, 0, zf / 2), (L + 0.2, D + 0.2, zf))
    ys, xs = D / 2 - th / 2, L / 2 - th / 2
    wall(a, M['brick'], (-L / 2, -ys), (L / 2, -ys), th, wh, [(-2.4, 2.0, 0.8, 1.7), (0.2, 1.2, 0.0, 2.2, False), (2.6, 2.0, 0.8, 1.7)], zf, M['wood'], M['dark'], M['glass'], rnd)
    wall(a, M['brick'], (-L / 2, ys), (L / 2, ys), th, wh, [(-2.0, 1.0, 1.4, 0.8), (2.0, 1.0, 1.4, 0.8), (0.0, 1.2, 0.0, 2.0, False)], zf, M['wood'], M['dark'], M['glass'], rnd)
    wall(a, M['brick'], (-xs, -ys), (-xs, ys), th, wh, [], zf); wall(a, M['brick'], (xs, -ys), (xs, ys), th, wh, [(0.5, 3.0, 1.0, 2.2, False)], zf)
    # плоская крыша из плит, провал
    for i in range(9):
        for j in range(6):
            if (i - 6) ** 2 + (j - 2) ** 2 < 3.2 or rnd.random() < 0.05: continue
            a.box(M['tin'], (-L / 2 + 0.5 + i * 1.0, -D / 2 + 0.5 + j * 0.95, zf + wh + 0.05 + rnd.uniform(-0.03, 0.03)), (1.0, 0.95, 0.1), rot=(0, rnd.uniform(-0.03, 0.03), rnd.uniform(-0.02, 0.02)))
    for sx in (-1, 1): a.box(M['brick'], (sx * (L / 2 - 0.1), 0, zf + wh + 0.4), (0.25, D, 0.5))
    a.box(M['brick'], (0, -D / 2 + 0.1, zf + wh + 0.4), (L, 0.25, 0.5))
    a.box(M['red'], (0, -D / 2 - 0.12, zf + wh - 0.3), (4.4, 0.1, 0.7))                                    # вывеска
    a.box(M['floor'], (0.2, -D / 2 - 0.9, zf * 0.7), (2.6, 1.4, 0.16))
    a.cyl(M['rust'], (3.5, 0.5, zf + wh + 0.9), 0.1, 1.4, 'Z', 8)
    planks_on_ground(a, M['wood'], rnd, 0, -D / 2 - 2.0, 3, 5)
    debris(a, M['brick'], rnd, 3.0, ys + 0.6, 0.1, 1.0, 10, (0.3, 0.15, 0.12))
    return a.build(name)

# ---------- клуб / дом культуры: колонны, большие окна ----------
def club(name, seed):
    rnd = random.Random(seed); M = PM(); a = Acc()
    L, D, wh, th = 14.0, 8.4, 4.2, 0.45; zf = 0.5
    a.box(M['conc'], (0, 0, zf / 2), (L + 0.3, D + 0.3, zf))
    ys, xs = D / 2 - th / 2, L / 2 - th / 2
    win = lambda x: (x, 1.3, 1.2, 2.2)
    wall(a, M['brick'], (-L / 2, -ys), (L / 2, -ys), th, wh, [win(-4.5), win(-2.3), (0, 1.8, 0.0, 2.8, False), win(2.3), win(4.5)], zf, M['wood'], M['dark'], M['glass'], rnd)
    wall(a, M['brick'], (-L / 2, ys), (L / 2, ys), th, wh, [win(-4.5), win(-1.5), win(1.5), (5.0, 3.0, 0.8, 3.0, False)], zf, M['wood'], M['dark'], M['glass'], rnd)
    wall(a, M['brick'], (-xs, -ys), (-xs, ys), th, wh, [win(-1.5), win(1.5)], zf, M['wood'], M['dark'], M['glass'], rnd)
    wall(a, M['brick'], (xs, -ys), (xs, ys), th, wh, [win(0)], zf, M['wood'], M['dark'], M['glass'], rnd)
    for sx in (-1, 1):
        a.poly(M['brick'], [(sx * xs - th / 2, -ys - 0.05, zf + wh), (sx * xs - th / 2, ys + 0.05, zf + wh), (sx * xs - th / 2, 0, zf + wh + 2.2)], (th, 0, 0))
    ze = zf + wh - 0.05; rz = zf + wh + 2.3
    hs = {-1: hole_set(rnd, 24, 8, 3, (1.2, 2.4)), 1: hole_set(rnd, 24, 8, 3, (1.2, 2.6))}
    roof(a, M['slate'], M['wood'], -L / 2 - 0.5, L / 2 + 0.5, -(D / 2 + 0.55), D / 2 + 0.55, ze, rz, 0, lambda i, j, sd, nx, ns: (i, j) in hs[sd] or rnd.random() < 0.05, rnd, cell=0.66)
    # портик с колоннами
    a.box(M['conc'], (0, -D / 2 - 1.2, 0.3), (7.0, 2.2, 0.6))
    for k in range(4):
        x = -2.7 + k * 1.8
        if k == 2: a.cyl(M['conc'], (x, -D / 2 - 1.9, 2.6), 0.28, 3.4, 'Z', 12); a.box(M['conc'], (x, -D / 2 - 1.9, 0.9), (0.4, 0.4, 0.5), rot=(0, 0, 0.1)); continue
        a.cyl(M['conc'], (x, -D / 2 - 1.9, 2.6), 0.3, 4.0, 'Z', 12)
    a.box(M['conc'], (0, -D / 2 - 1.9, 4.45), (7.4, 0.9, 0.35))
    a.poly(M['conc'], [(-3.7, -D / 2 - 2.4, 4.6), (3.7, -D / 2 - 2.4, 4.6), (0, -D / 2 - 2.4, 5.8)], (0, 1.5, 0))
    a.box(M['floor'], (0, 0, zf + wh - 0.06), (L - 0.9, D - 0.9, 0.08)); a.box(M['floor'], (0, 0, zf + 0.04), (L - 0.9, D - 0.9, 0.06))
    debris(a, M['slate'], rnd, 2.0, 0.6, zf + wh - 0.02, 2.0, 12); debris(a, M['brick'], rnd, 5.0, ys + 1.0, 0.1, 1.4, 16, (0.3, 0.15, 0.12))
    planks_on_ground(a, M['wood'], rnd, 0, -D / 2 - 4.0, 4.0, 6)
    return a.build(name)

# ---------- часовня с луковкой ----------
def chapel(name, seed):
    rnd = random.Random(seed); M = PM(); a = Acc()
    L = D = 4.2; wh = 3.4; th = 0.5; zf = 0.4
    a.box(M['conc'], (0, 0, zf / 2), (L + 0.5, D + 0.5, zf))
    ys = D / 2 - th / 2
    wall(a, M['brick'], (-L / 2, -ys), (L / 2, -ys), th, wh, [(0, 1.3, 0.0, 2.4, False)], zf)
    wall(a, M['brick'], (-L / 2, ys), (L / 2, ys), th, wh, [(0, 0.8, 1.2, 1.5)], zf, M['wood'], M['dark'], M['glass'], rnd)
    wall(a, M['brick'], (-ys, -ys), (-ys, ys), th, wh, [(0, 0.8, 1.2, 1.5)], zf, M['wood'], M['dark'], M['glass'], rnd)
    wall(a, M['brick'], (ys, -ys), (ys, ys), th, wh - 0.6, [(0, 0.8, 1.2, 1.2)], zf, M['wood'], M['dark'], M['glass'], rnd)
    # шатёр: 4 ската
    zt = zf + wh
    for k in range(4):
        ang = k * math.pi / 2
        if k == 3 and rnd.random() < 2: pass
        c = (math.cos(ang) * 1.05, math.sin(ang) * 1.05, zt + 1.0)
        a.box(M['metal'], c, (2.9 if k % 2 == 0 else 2.9, 0.06, 2.3), rot=(0, 0, 0), pivot=None) if False else None
    for k in range(4):
        ang = k * math.pi / 2
        n = (math.cos(ang), math.sin(ang))
        if k == 1: continue                                                                          # одного ската нет
        cx, cy = n[0] * 1.15, n[1] * 1.15
        a.box(M['metal'], (cx, cy, zt + 0.95), (3.6 if k % 2 else 0.07, 0.07 if k % 2 else 3.6, 2.4), rot=(0, 0, 0))
    # проще: пирамида из лофта
    pyr = []
    for i in range(6):
        t = i / 5; r = 2.5 * (1 - t) + 0.12
        pyr.append([(r, r, zt + t * 2.4), (-r, r, zt + t * 2.4), (-r, -r, zt + t * 2.4), (r, -r, zt + t * 2.4)])
    a.loft(M['metal'], pyr)
    # луковка
    onion = []
    for i in range(10):
        t = i / 9
        r = 0.55 * math.sin(math.pi * min(1.0, t * 1.15)) ** 0.8 + 0.05
        onion.append([(r * math.cos(2 * math.pi * j / 10), r * math.sin(2 * math.pi * j / 10), zt + 2.35 + t * 1.2) for j in range(10)])
    a.loft(material('onion', 'roofmetal', rough=0.5, metal=0.4, tile=1.0, smooth=True), onion)
    a.cyl(M['rust'], (0, 0, zt + 4.1), 0.03, 0.9, 'Z', 6); a.box(M['rust'], (0, 0, zt + 4.15), (0.45, 0.03, 0.04)); a.box(M['rust'], (0, 0, zt + 4.35), (0.3, 0.03, 0.04), rot=(0, 0, 0))
    a.box(M['rust'], (0, 0, zt + 4.0), (0.4, 0.03, 0.04), rot=(0.0, 0.0, 0.3))
    debris(a, M['brick'], rnd, 0.0, ys + 0.8, 0.1, 1.0, 12, (0.3, 0.15, 0.12))
    return a.build(name)

# ---------- теплица ----------
def greenhouse(name, seed):
    rnd = random.Random(seed); M = PM(); a = Acc()
    L, W, H = 5.0, 2.6, 2.0
    film = material('film', color=(0.55, 0.6, 0.52, 1), rough=0.4)
    n = 7
    for i in range(n):
        x = -L / 2 + i * L / (n - 1)
        pts = [(x, -W / 2 * math.cos(t), H * math.sin(t) * 0.98) for t in [k * math.pi / 8 for k in range(9)]]
        for p, q in zip(pts, pts[1:]):
            mid = ((p[0] + q[0]) / 2, (p[1] + q[1]) / 2, (p[2] + q[2]) / 2)
            ln = math.hypot(q[1] - p[1], q[2] - p[2]); ang = math.atan2(q[2] - p[2], q[1] - p[1])
            a.box(M['wood'], mid, (0.05, ln + 0.02, 0.05), rot=(ang, 0, 0))
    a.box(M['wood'], (0, 0, H), (L, 0.05, 0.05))
    for yy in (-0.9, 0.9): a.box(M['wood'], (0, yy, 0.9), (L, 0.04, 0.04))
    for k in range(5):                                                                              # обрывки плёнки
        if rnd.random() < 0.6:
            x = rnd.uniform(-L / 2 + 0.4, L / 2 - 0.4); t = rnd.uniform(0.3, 1.2)
            a.box(film, (x, -W / 2 * math.cos(t) * 0.97, H * math.sin(t) * 0.97), (rnd.uniform(0.5, 0.9), 0.01, rnd.uniform(0.4, 0.8)), rot=(math.pi / 2 - t, 0, rnd.uniform(-0.1, 0.1)))
    a.box(M['soil'], (0, 0, 0.1), (L - 0.3, W - 0.6, 0.2))
    for i in range(18):
        x = rnd.uniform(-L / 2 + 0.3, L / 2 - 0.3); y = rnd.uniform(-0.9, 0.9)
        a.box(M['weed'], (x, y, 0.35), (0.3, 0.02, 0.5), rot=(0, 0, rnd.uniform(0, 3)))
    return a.build(name)

# ---------- навес (сенный/дровяной) ----------
def open_shed(name, seed):
    rnd = random.Random(seed); M = PM(); a = Acc()
    L, D, H = 6.0, 3.6, 2.8
    for x in (-L / 2, 0, L / 2):
        for y in (-D / 2, D / 2): a.box(M['wood'], (x, y, H / 2), (0.2, 0.2, H))
    a.box(M['wood'], (0, D / 2, 1.2), (L, 0.06, 2.0)); a.box(M['wood'], (-L / 2, 0, 1.2), (0.06, D, 2.0))
    for i in range(14):
        if rnd.random() < 0.25: continue
        j = i // 7
        a.box(M['tin'], (-L / 2 - 0.2 + (i % 7) * 0.88 + 0.44, -D / 2 - 0.2 + j * 2.0 + 1.0, H + 0.2 + j * 0.0 + rnd.uniform(-0.03, 0.03)), (0.9, 2.0, 0.05), rot=(0.17 if j == 0 else -0.17, 0, 0)) if False else None
    for i in range(8):
        for j in range(4):
            if rnd.random() < 0.18: continue
            a.box(M['tin'], (-L / 2 - 0.2 + (i + 0.5) * 0.82, -D / 2 - 0.15 + (j + 0.5) * 0.98, H + 0.2 - (j + 0.5) * 0.17 + rnd.uniform(-0.03, 0.03)), (0.83, 1.0, 0.05), rot=(-0.17, 0, rnd.uniform(-0.03, 0.03)))
    for k in range(6): a.box(M['hay'], (-1.5 + (k % 3) * 1.2, 0.5 - (k // 3) * 0.9, 0.35 + (0.5 if k == 4 else 0)), (1.1, 0.8, 0.5))
    return a.build(name)

JOBS = {
    'house_cabin': lambda: cabin('house_cabin', 31), 'house_banya': lambda: banya('house_banya', 32),
    'house_dacha_a': lambda: dacha_a('house_dacha_a', 33), 'house_dacha_b': lambda: dacha_b('house_dacha_b', 34), 'house_dacha_c': lambda: dacha_c('house_dacha_c', 35), 'house_dacha_d': lambda: dacha_d('house_dacha_d', 36),
    'house_izba_c': lambda: izba_c('house_izba_c', 37), 'house_brick_small': lambda: house_brick_small('house_brick_small', 38),
    'shop': lambda: shop('shop', 39), 'club': lambda: club('club', 40), 'chapel': lambda: chapel('chapel', 41), 'greenhouse': lambda: greenhouse('greenhouse', 42), 'open_shed': lambda: open_shed('open_shed', 43),
}

if __name__ == '__main__':
    from rural import run
    run(JOBS, os.environ.get('ONLY'))

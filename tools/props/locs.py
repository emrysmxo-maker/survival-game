# Постройки локаций (1): лагерь выживших, лесопилка, рыбацкая база. python -I locs.py <выход> [превью]; ONLY=...
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *
from rural import PM, run, barrel
import houses
from houses import wall, roof, debris, planks_on_ground
from buildings import gable_house, hole_set

OUT = sys.argv[1]
PRE = sys.argv[2] if len(sys.argv) > 2 else None

def PM2():
    M = PM()
    M['sawdust'] = material('sawdust', color=(0.09, 0.06, 0.035, 1), rough=1.0)
    M['sandbag'] = material('sandbag', 'canvas_tan', rough=1.0, tile=0.5, smooth=True)
    M['ash'] = material('ash', color=(0.05, 0.045, 0.04, 1), rough=1.0)
    M['fish'] = material('fish', color=(0.55, 0.58, 0.58, 1), rough=0.4, metal=0.5)
    M['net'] = material('net', 'net', rough=1.0, tile=0.7)
    M['red_c'] = material('cloth_red', color=(0.4, 0.1, 0.08, 1), rough=1.0)
    return M

# ===================== ЛАГЕРЬ =====================
def tent_army(name, seed, col='olive'):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    L, W, H = 3.6, 2.6, 1.85
    a.poly(M[col], [(-L / 2, -W / 2, 0.04), (-L / 2, W / 2, 0.04), (-L / 2, 0, H)], (L, 0, 0))
    a.poly(M['dark'], [(-L / 2 - 0.006, -0.5, 0.05), (-L / 2 - 0.006, 0.5, 0.05), (-L / 2 - 0.006, 0, 1.35)], (-0.002, 0, 0))
    a.box(M['olive'], (-L / 2 - 0.02, -0.62, 0.7), (0.03, 0.7, 1.35), rot=(0.0, 0.0, 0.0)) if False else None
    for sx in (-1, 1):
        a.cyl(M['wood'], (sx * (L / 2 + 0.1), 0, H / 2), 0.04, H + 0.1, 'Z', 6)
        for sy in (-1, 1):
            a.beam(M['rust'], (sx * (L / 2 + 0.95), sy * 1.9, 0.0), (sx * (L / 2 + 0.85), sy * 1.9, 0.22), 0.04)
            a.beam(M['dark'], (sx * (L / 2 + 0.1), 0, H), (sx * (L / 2 + 0.9), sy * 1.9, 0.12), 0.012)
    a.box(M['sandbag'], (0.0, -W / 2 - 0.2, 0.12), (1.4, 0.25, 0.2))
    a.box(M['olive'], (0.2, 0.0, 0.03), (3.0, 2.2, 0.03))
    return a.build(name)

def tent_tan(name, seed):
    return tent_army(name, seed, 'tan')

def tent_dome_old(name, seed):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    rings = []
    for i in range(11):
        x = -1.75 + 3.5 * i / 10
        s = math.sqrt(max(0.0, 1 - (x / 1.78) ** 2)) + 0.03
        rings.append([(x, 1.25 * s * math.cos(math.pi * k / 12), 0.04 + 1.15 * s * math.sin(math.pi * k / 12)) for k in range(13)])
    a.loft(material('tent_tan', 'canvas_tan', rough=1.0, tile=1.0, smooth=True), rings)
    a.cyl(M['dark'], (-1.62, 0, 0.5), 0.45, 0.04, 'X', 10)
    for sx in (-1, 1): a.box(M['rust'], (sx * 2.1, 0, 0.04), (0.04, 0.04, 0.2), rot=(0, 0.4, 0))
    a.box(M['olive'], (0.3, 0.4, 0.2), (0.8, 0.5, 0.3), rot=(0, 0, 0.3))
    return a.build(name)

def tarp(name, seed):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    for (x, y, h) in ((-1.5, -1.2, 1.9), (-1.5, 1.2, 1.9), (1.5, -1.2, 1.1), (1.5, 1.2, 1.1)):
        a.cyl(M['bark'], (x, y, h / 2), 0.05, h, 'Z', 6)
    a.box(M['tarp'], (0, 0, 1.52), (3.5, 2.8, 0.025), rot=(0, 0.25, 0))
    a.box(M['tarp'], (0, 0, 0.03), (3.2, 2.5, 0.02))
    a.box(M['wood'], (-0.9, 0.5, 0.18), (0.9, 0.5, 0.36)); a.box(M['olive'], (0.6, -0.6, 0.12), (1.4, 0.6, 0.24), rot=(0, 0, 0.1))
    return a.build(name)

def campfire(name, seed):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    a.cyl(M['ash'], (0, 0, 0.012), 0.62, 0.025, 'Z', 14)
    for i in range(10):
        t = i * 2 * math.pi / 10
        a.box(M['stone'], (0.72 * math.cos(t), 0.72 * math.sin(t), 0.1), (0.3, 0.22, 0.2), rot=(0, 0, t + rnd.uniform(-0.3, 0.3)))
    for i in range(5):
        t = i * 2 * math.pi / 5 + 0.3
        a.cyl(M['bark'], (0.3 * math.cos(t), 0.3 * math.sin(t), 0.16), 0.06, 0.85, 'X', 7)

    for k in range(3):
        t = k * 2 * math.pi / 3
        a.beam(M['bark'], (1.15 * math.cos(t), 1.15 * math.sin(t), 0.03), (0.08 * math.cos(t), 0.08 * math.sin(t), 1.75), 0.08)
    a.box(M['rust'], (0, 0, 1.0), (0.015, 0.015, 0.7))
    a.cyl(M['rust'], (0, 0, 0.62), 0.2, 0.24, 'Z', 12); a.cyl(M['dark'], (0, 0, 0.745), 0.17, 0.01, 'Z', 12)
    return a.build(name)

def bench(name, seed):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    for sx in (-0.8, 0.8): a.cyl(M['bark'], (sx, 0, 0.22), 0.22, 0.44, 'Z', 8); a.cyl(M['endgrain'], (sx, 0, 0.445), 0.2, 0.01, 'Z', 8)
    a.box(M['wood'], (0, 0, 0.48), (2.3, 0.36, 0.07))
    return a.build(name)

def camp_table(name, seed):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    a.box(M['wood'], (0, 0, 0.8), (2.0, 0.9, 0.06))
    for sx in (-0.9, 0.9):
        for sy in (-0.38, 0.38): a.box(M['wood'], (sx, sy, 0.4), (0.07, 0.07, 0.8))
    a.box(M['wood'], (-0.5, 0.1, 1.0), (0.5, 0.4, 0.34)); a.box(M['olive'], (0.1, -0.1, 0.96), (0.4, 0.3, 0.26), rot=(0, 0, 0.2))
    a.box(M['tin_green'], (0.6, 0.15, 0.97), (0.38, 0.14, 0.28)); a.cyl(M['rust'], (-0.1, 0.3, 0.9), 0.07, 0.15, 'Z', 8)
    return a.build(name)

def barricade(name, seed):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    for i in range(11):
        x = -1.5 + i * 0.3
        a.cyl(M['bark'], (x, 0, 0.8), 0.06, 1.6, 'Z', 6, r2=0.02)
    for z in (0.5, 1.0): a.box(M['wood'], (0, 0.1, z), (3.3, 0.05, 0.14))
    for r in range(3):
        for i in range(6): a.box(M['sandbag'], (-1.4 + i * 0.55 + (r % 2) * 0.27, -0.3, 0.12 + r * 0.19), (0.52, 0.3, 0.18), rot=(0, 0, rnd.uniform(-0.04, 0.04)))
    for x in (-1.0, 0.0, 1.0): a.torus(M['rust'], (x, 0.0, 1.63), 0.22, 0.012, 'Y', 12, 4)
    return a.build(name)

def watch_tower(name, seed):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    H = 4.2
    for sx in (-1, 1):
        for sy in (-1, 1):
            a.beam(M['bark'], (sx * 1.1, sy * 1.1, 0.0), (sx * 0.75, sy * 0.75, H + 0.1), 0.15)
    for z in (0.9, 2.1, 3.2):
        w = 1.1 - 0.35 * z / H
        for sy in (-1, 1): a.box(M['wood'], (0, sy * w, z), (2 * w, 0.07, 0.1))
        for sx in (-1, 1): a.box(M['wood'], (sx * w, 0, z + 0.2), (0.07, 2 * w, 0.1))
    a.box(M['floor'], (0, 0, H), (1.9, 1.9, 0.1))
    for sx in (-1, 1):
        a.box(M['wood'], (sx * 0.9, 0, H + 0.55), (0.06, 1.8, 0.1)); a.box(M['wood'], (0, sx * 0.9, H + 0.55), (1.8, 0.06, 0.1))
    for sx in (-0.9, 0.9):
        for sy in (-0.9, 0.9): a.box(M['wood'], (sx, sy, H + 1.0), (0.09, 0.09, 2.0))
    a.box(M['tarp'], (0, 0, H + 2.05), (2.3, 2.3, 0.04), rot=(0, 0.1, 0))
    a.box(M['wood'], (0.2, 0.9, H / 2), (0.1, 0.1, H + 0.1), rot=(0, 0, 0)) if False else None
    for k in range(10): a.box(M['wood'], (1.18 - 0.0, 0.0 + (k - 4.5) * 0.0, 0.2 + k * 0.4), (0.04, 0.5, 0.04)) if False else None
    for s in (-0.2, 0.2): a.box(M['wood'], (1.12, s, 2.1), (0.05, 0.05, 4.4), rot=(0, 0.08, 0))
    for k in range(9): a.box(M['wood'], (1.1 - k * 0.0, 0, 0.3 + k * 0.45), (0.05, 0.4, 0.04), rot=(0, 0.08, 0))
    return a.build(name)

def clothesline(name, seed):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    for sx in (-1.6, 1.6): a.cyl(M['bark'], (sx, 0, 1.15), 0.05, 2.3, 'Z', 6)
    a.box(M['dark'], (0, 0, 2.2), (3.2, 0.012, 0.012))
    for i, c in enumerate(('olive', 'tan', 'red_c', 'olive')):
        a.box(M[c], (-1.2 + i * 0.75, 0, 1.85), (0.5, 0.01, 0.7), rot=(0, rnd.uniform(-0.1, 0.1), 0))
    return a.build(name)

def sandbags(name, seed):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    for r in range(4):
        n = 7 - (r // 2)
        for i in range(n):
            a.box(M['sandbag'], (-1.7 + i * 0.52 + (r % 2) * 0.26 + (r // 2) * 0.26, 0, 0.1 + r * 0.19), (0.5, 0.32, 0.18), rot=(0, 0, rnd.uniform(-0.05, 0.05)))
    return a.build(name)

# ===================== ЛЕСОПИЛКА =====================
def sawmill_hall(name, seed):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    L, D, H = 16.0, 7.0, 4.0
    a.box(M['conc'], (0, 0, 0.1), (L + 0.6, D + 0.6, 0.2))
    for x in (-7.5, -3.75, 0.0, 3.75, 7.5):
        for y in (-D / 2, D / 2): a.box(M['wood'], (x, y, H / 2 + 0.1), (0.28, 0.28, H))
    a.box(M['wood'], (0, D / 2, 1.5), (L, 0.07, 2.6)); a.box(M['wood'], (-L / 2, 0, 1.5), (0.07, D, 2.6))
    for i in range(12):
        if rnd.random() < 0.3: continue
        a.box(M['wood'], (-L / 2 + 0.7 + i * 1.3, -D / 2, 1.2 + rnd.uniform(0, 0.4)), (0.12, 0.05, 1.9)) if False else None
    rise = 1.6
    holes = {-1: hole_set(rnd, 28, 8, 3, (1.4, 2.6)), 1: hole_set(rnd, 28, 8, 2, (1.2, 2.0))}
    roof(a, M['tin'], M['wood'], -L / 2 - 0.6, L / 2 + 0.6, -(D / 2 + 0.6), D / 2 + 0.6, H + 0.1, H + 0.1 + rise, 0, lambda i, j, sd, nx, ns: (i, j) in holes[sd] or rnd.random() < 0.05, rnd, cell=0.62)
    # станок: рельсы, каретка, бревно, пила, мотор
    for y in (-0.8, 0.8): a.box(M['rust'], (-1.0, y, 0.35), (11.0, 0.18, 0.3))
    a.box(M['wood'], (-2.0, 0, 0.62), (3.6, 1.9, 0.18)); a.box(M['rust'], (-2.0, 0, 0.78), (3.8, 0.2, 0.2))
    a.cyl(M['bark'], (-2.1, 0, 1.15), 0.42, 5.8, 'X', 12); a.cyl(M['endgrain'], (0.8, 0, 1.15), 0.41, 0.012, 'X', 12); a.cyl(M['endgrain'], (-5.0, 0, 1.15), 0.41, 0.012, 'X', 12)
    a.box(M['rust'], (1.6, -1.15, 1.7), (0.22, 0.22, 3.2)); a.box(M['rust'], (1.6, 1.15, 1.7), (0.22, 0.22, 3.2)); a.box(M['rust'], (1.6, 0, 3.2), (0.3, 2.5, 0.3))
    a.cyl(M['chrome'], (1.6, 0, 1.55), 0.95, 0.025, 'Y', 28)
    a.box(M['rust'], (3.2, 1.8, 0.7), (1.4, 0.9, 1.0)); a.cyl(M['dark'], (2.6, 1.4, 1.2), 0.3, 0.2, 'Y', 12); a.box(M['dark'], (2.2, 1.0, 1.0), (1.2, 0.04, 0.2), rot=(0, 0, 0.5)) if False else None
    for i in range(7): a.box(M['wood'], (-5.5 + (i % 3) * 0.0, 2.6 + (i // 3) * 0.0, 0.1 + i * 0.07), (3.2, 0.9, 0.06)) if False else None
    for k in range(10): a.box(M['wood'], (-6.2, 2.5, 0.1 + k * 0.08), (3.0, 1.0, 0.06), rot=(0, 0, rnd.uniform(-0.03, 0.03)))
    a.cyl(M['sawdust'], (2.6, -1.8, 0.4), 1.4, 0.8, 'Z', 12, r2=0.05)
    return a.build(name)

def log_pile(name, seed):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    rows = [(6, 0.37, 0.4), (5, 0.35, 1.05), (4, 0.34, 1.65), (3, 0.33, 2.2)]
    for n, r, z in rows:
        sp = 0.74
        for i in range(n):
            y = (i - (n - 1) / 2) * sp
            L = 7.0 + rnd.uniform(-0.6, 0.3)
            x = rnd.uniform(-0.3, 0.3)
            a.cyl(M['bark'], (x, y, z), r * rnd.uniform(0.95, 1.05), L, 'X', 12)
            for sd in (-1, 1): a.cyl(M['endgrain'], (x + sd * (L / 2 + 0.004), y, z), r * 0.96, 0.012, 'X', 12)
    for sx in (-3.9, 3.9):
        for sy in (-2.2, 2.2): a.cyl(M['bark'], (sx, sy, 1.3), 0.09, 2.6, 'Z', 6)
    return a.build(name)

def lumber_stack(name, seed):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    for k in range(14):
        z = 0.2 + k * 0.1
        a.box(M['wood'], (rnd.uniform(-0.05, 0.05), rnd.uniform(-0.03, 0.03), z), (4.2, 1.1, 0.06))
        for x in (-1.8, 0.0, 1.8): a.box(M['wood'], (x, 0, z - 0.05), (0.06, 1.1, 0.04))
    for x in (-1.8, 0.0, 1.8): a.box(M['conc'], (x, 0, 0.1), (0.3, 1.2, 0.2))
    a.box(M['tin'], (0, 0, 1.78), (4.6, 1.5, 0.03), rot=(0.1, 0, 0))
    return a.build(name)

def sawdust(name, seed):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    rings = []
    for i in range(10):
        t = i / 9
        r = max(0.05, 2.4 * (1 - t) ** 0.8) * (1 + 0.08 * math.sin(t * 8))
        rings.append([(r * math.cos(2 * math.pi * j / 14) * rnd.uniform(0.94, 1.06), r * math.sin(2 * math.pi * j / 14) * rnd.uniform(0.94, 1.06), t * 2.0) for j in range(14)])
    a.loft(material('sawdust_s', color=(0.09, 0.06, 0.035, 1), rough=1.0, smooth=True), rings)
    return a.build(name)

def log_heap(name, seed):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    for i in range(9):
        a.cyl(M['bark'], (rnd.uniform(-0.8, 0.8), rnd.uniform(-0.8, 0.8), 0.3 + (i // 3) * 0.45), 0.3, rnd.uniform(3.0, 4.6), 'X', 10)
    return a.build(name)

# ===================== РЫБАЦКАЯ БАЗА =====================
def pier(name, seed):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    L, W = 12.0, 1.8
    for i in range(24):
        if rnd.random() < 0.14: continue
        a.box(M['floor'], (0.25 + i * 0.5, 0, 0.72 + rnd.uniform(-0.01, 0.015)), (0.46, W, 0.06), rot=(0, 0, rnd.uniform(-0.01, 0.01)))
    for y in (-0.7, 0, 0.7): a.box(M['wood'], (L / 2, y, 0.62), (L, 0.12, 0.14))
    for i in range(7):
        x = 0.5 + i * 1.9
        for y in (-0.8, 0.8): a.cyl(M['bark'], (x, y, -0.5), 0.12, 2.5, 'Z', 8)
        a.box(M['wood'], (x, 0, 0.5), (0.1, 1.9, 0.12))
    for x in (2.0, 5.6, 9.0):
        for y in (-0.88, 0.88): a.box(M['wood'], (x, y, 1.15), (0.1, 0.1, 0.9))
    for y in (-0.88, 0.88): a.box(M['wood'], (3.8, y, 1.45), (3.6, 0.05, 0.08)); a.box(M['wood'], (10.0, y, 1.45), (2.0, 0.05, 0.08), rot=(0, 0.25 * (1 if y > 0 else 0), 0))
    a.cyl(M['rust'], (11.6, 0.7, 0.9), 0.1, 0.35, 'Z', 8); a.torus(M['rust'], (11.8, -0.4, 0.78), 0.14, 0.02, 'Z', 10, 4)
    return a.build(name)

def boat(name, seed, kind='wood', up=False, motor=False):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    hm = {'wood': material('boat_wood', 'boards_gray', rough=0.9, tile=1.0, smooth=True), 'blue': material('boat_blue', 'boards_blue', rough=0.8, tile=1.0, smooth=True),
          'alu': material('boat_alu', 'tin_gray', rough=0.5, metal=0.4, tile=1.0, smooth=True), 'green': material('boat_green', 'boards_green', rough=0.8, tile=1.0, smooth=True)}[kind]
    Lh = 3.8 if not motor else 4.4; Wmax = 0.7 if not motor else 0.85
    xs = [-Lh / 2 + Lh * i / 14 for i in range(15)]
    rings = []; tops = []
    for x in xs:
        u = x / (Lh / 2)
        w = Wmax * max(0.04, (1 - abs(u) ** 2.3)) ** 0.55
        sheer = 0.55 + 0.12 * abs(u) ** 2
        rings.append([(x, -w, sheer), (x, -w * 0.93, 0.22), (x, -w * 0.5, 0.04), (x, 0, 0.0), (x, w * 0.5, 0.04), (x, w * 0.93, 0.22), (x, w, sheer)])
        tops.append((x, w, sheer))
    a.loft(hm, rings)
    L_, R_ = [(x, -w * 0.9, s - 0.015) for x, w, s in tops], [(x, w * 0.9, s - 0.015) for x, w, s in tops]
    a.face(M['dark'], L_ + R_[::-1])
    for x in (-0.8, 0.0, 0.8):
        w = Wmax * max(0.04, (1 - abs(x / (Lh / 2)) ** 2.3)) ** 0.55
        a.box(M['wood'], (x, 0, 0.36), (0.26, 2 * w * 0.93, 0.04))
    if motor:
        a.box(M['dark'], (-Lh / 2 - 0.12, 0, 0.7), (0.3, 0.28, 0.55)); a.cyl(M['rust'], (-Lh / 2 - 0.12, 0, 0.2), 0.04, 0.9, 'Z', 6); a.box(M['tin_red'], (-1.2, 0.3, 0.45), (0.3, 0.2, 0.3))
    else:
        for s in (-1, 1): a.cyl(M['bark'], (0.4, s * 0.45, 0.7), 0.025, 2.2, 'X', 6, ); a.box(M['wood'], (1.5, s * 0.45, 0.7), (0.4, 0.03, 0.14))
    o = a.build(name)
    if up:
        o.data.transform(Matrix.Rotation(math.pi, 4, 'X'))
        mn = min(v.co.z for v in o.data.vertices); o.data.transform(Matrix.Translation((0, 0, -mn)))
    return o

def fish_rack(name, seed):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    for sx in (-1.8, 1.8):
        for sy in (-0.5, 0.5): a.box(M['wood'], (sx, sy, 1.05), (0.11, 0.11, 2.1), rot=(0, 0, 0))
    for z in (1.0, 1.5, 2.0): a.box(M['wood'], (0, 0, z), (3.8, 0.07, 0.07)); a.box(M['wood'], (0, 0.45, z), (3.8, 0.07, 0.07)) if False else None
    for z in (1.0, 1.5, 2.0):
        for i in range(8):
            if rnd.random() < 0.3: continue
            a.box(M['fish'], (-1.5 + i * 0.43, rnd.uniform(-0.1, 0.1), z - 0.25), (0.1, 0.03, 0.4), rot=(0, rnd.uniform(-0.2, 0.2), 0))
    return a.build(name)

def nets(name, seed):
    rnd = random.Random(seed); M = PM2(); a = Acc()
    for sx in (-1.4, 1.4): a.cyl(M['bark'], (sx, 0, 1.0), 0.05, 2.0, 'Z', 6)
    a.cyl(M['bark'], (0, 0, 1.95), 0.04, 2.9, 'X', 6)
    a.box(M['net'], (0, 0.04, 1.35), (2.7, 0.05, 1.2), rot=(0.0, 0, 0)); a.box(M['net'], (0.3, 0.03, 0.75), (2.0, 0.04, 0.5), rot=(0.05, 0, 0))
    a.box(M['net'], (1.4, -1.0, 0.18), (1.3, 1.0, 0.3)); 
    for i in range(5): a.cyl(M['sawdust'], (-1.2 + i * 0.6, 0.06, 0.95), 0.06, 0.1, 'Y', 6)
    return a.build(name)

def boat_shed(name, seed):
    return gable_house(name, seed, 7.0, 4.6, 2.5, 0.14, 'wood', 'tin', [(0.0, 3.4, 0.0, 2.3, False)], [(-1.8, 0.9, 1.0, 0.9), (1.8, 0.9, 1.0, 0.9)], [], [(0, 0.9, 1.0, 0.9)], holes=3, eave=0.4, cell=0.7, ridge_k=0.5)

JOBS = {
    'tent_army': lambda: tent_army('tent_army', 1), 'tent_tan': lambda: tent_tan('tent_tan', 2), 'tarp_shelter': lambda: tarp('tarp_shelter', 3),
    'campfire': lambda: campfire('campfire', 4), 'bench_log': lambda: bench('bench_log', 5), 'camp_table': lambda: camp_table('camp_table', 6),
    'barricade': lambda: barricade('barricade', 7), 'watch_tower': lambda: watch_tower('watch_tower', 8), 'clothesline': lambda: clothesline('clothesline', 9), 'sandbags': lambda: sandbags('sandbags', 10),
    'sawmill_hall': lambda: sawmill_hall('sawmill_hall', 11), 'log_pile': lambda: log_pile('log_pile', 12), 'lumber_stack': lambda: lumber_stack('lumber_stack', 13),
    'sawdust': lambda: sawdust('sawdust', 14), 'log_heap': lambda: log_heap('log_heap', 15),
    'pier': lambda: pier('pier', 16), 'boat_row_wood': lambda: boat('boat_row_wood', 17, 'wood'), 'boat_row_blue': lambda: boat('boat_row_blue', 18, 'blue'),
    'boat_row_up': lambda: boat('boat_row_up', 19, 'green', up=True), 'boat_motor': lambda: boat('boat_motor', 20, 'alu', motor=True),
    'fish_rack': lambda: fish_rack('fish_rack', 21), 'nets': lambda: nets('nets', 22), 'boat_shed': lambda: boat_shed('boat_shed', 23),
}
if __name__ == '__main__':
    run(JOBS, os.environ.get('ONLY'))

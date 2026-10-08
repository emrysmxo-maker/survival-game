# Машины: гладкий кузов по сечениям (loft), остекление, детали. Блендер-скрипт: python -I vehicles.py <выход> [превью]; ONLY=имя,...
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *
from mathutils import Vector

OUT = sys.argv[1]
PRE = sys.argv[2] if len(sys.argv) > 2 else None

def interp(tab, x):
    if x <= tab[0][0]: return tab[0][1]
    for (x0, y0), (x1, y1) in zip(tab, tab[1:]):
        if x <= x1:
            t = (x - x0) / (x1 - x0); t = t * t * (3 - 2 * t) * 0.35 + t * 0.65
            return y0 + (y1 - y0) * t
    return tab[-1][1]

def mirror(half):
    return half + [(-y, z) for (y, z) in half[-2:0:-1]]

def ring(x, half):
    return [Vector((x, y, z)) for (y, z) in mirror(half)]

def mats(paint, burnt=False):
    return dict(
        paint=material('paint_' + paint, paint, rough=0.62, metal=0.18, tile=2.0, smooth=True),
        rubber=material('tire', 'tire', rough=0.95, tile=0.8),
        rim=material('rim', 'rustmetal', rough=0.85, metal=0.25, tile=0.5),
        rust=material('rustmetal', 'rustmetal', rough=0.9, metal=0.2, tile=1.0),
        glass=material('glass', 'glass', rough=0.12, metal=0.35, tile=1.0),
        dark=material('dark', color=(0.015, 0.015, 0.02, 1), rough=1.0),
        chrome=material('chrome', color=(0.36, 0.36, 0.34, 1), rough=0.45, metal=0.7),
        lamp=material('lamp', color=(0.5, 0.5, 0.42, 1), rough=0.3),
        tail=material('tail', color=(0.30, 0.05, 0.04, 1), rough=0.5),
        wood=material('boards_gray', 'boards_gray', tile=1.0),
        seat=material('seat', color=(0.06, 0.05, 0.045, 1), rough=1.0),
        plate=material('plate', color=(0.55, 0.55, 0.5, 1), rough=0.6))

def window_poly(a, M, rings_at, xa, xb, v0=0.08, v1=0.92, side=1, push=0.006, n=7):
    """боковое окно на гранях между сечениями: x от xa до xb; сечение даёт (низ окна, верх окна) в точках side"""
    xs = [xa + (xb - xa) * i / n for i in range(n + 1)]
    low, up = [], []
    for x in xs:
        p2, p3 = rings_at(x)
        p2 = Vector((p2[0], side * p2[1], p2[2])); p3 = Vector((p3[0], side * p3[1], p3[2]))
        d = p3 - p2
        low.append(p2 + d * v0 + Vector((0, side * push, 0.0)))
        up.append(p2 + d * v1 + Vector((0, side * push, 0.0)))
    pts = low + up[::-1]
    a.face(M['glass'], pts if side > 0 else pts[::-1])

def wheel(a, M, x, y, z, r=0.31, w=0.2, flat=False, rim_r=0.55, seg=22):
    if flat: r *= 0.84; z -= 0.035
    a.cyl(M['rubber'], (x, y, z), r, w, 'Y', seg)
    s = 1 if y > 0 else -1
    a.cyl(M['rim'], (x, y + s * (w / 2 - 0.012), z), r * rim_r, 0.03, 'Y', 14)
    a.cyl(M['chrome'], (x, y + s * (w / 2 + 0.004), z), r * 0.16, 0.03, 'Y', 8)

def lamp_disc(a, m, x, y, z, r, axis='X', depth=0.04):
    a.cyl(m, (x, y, z), r, depth, axis, 12)

# ======================= седан =======================
def sedan(name, paint, seed, burnt=False, hatch=False):
    rnd = random.Random(seed); M = mats(paint); a = Acc()
    HW = 0.81
    top = [(-2.08, 0.74), (-2.02, 0.88), (-1.85, 0.92), (-1.15, 0.94), (0.8, 0.95), (1.3, 0.93), (1.9, 0.85), (2.08, 0.70)]
    arches = [(-1.28, 0.375), (1.28, 0.375)]
    def zb(x):
        z = 0.24 + (0.12 * min(1.0, max(0.0, (abs(x) - 1.85) / 0.22)))
        for xc, r in arches:
            d = abs(x - xc)
            if d < r: z = max(z, 0.31 + math.sqrt(r * r - d * d) * 0.96)
        return z
    def wf(x):
        e = max(0.0, abs(x) - 1.78) / 0.30
        return 1.0 - 0.17 * e * e
    xs = sorted(set([round(-2.08 + i * 0.07, 3) for i in range(60)] + [2.08] + [round(c + k, 3) for c, r in arches for k in (-r, r, -r * 0.7, r * 0.7, 0.0, -r * 0.35, r * 0.35)]))
    xs = [x for x in xs if -2.08 <= x <= 2.08]
    rings = []
    for x in xs:
        zt = interp(top, x); z0 = zb(x); h = zt - z0; hw = HW * wf(x)
        half = [(0, z0), (hw * 0.78, z0), (hw * 0.97, z0 + h * 0.10), (hw * 1.0, z0 + h * 0.40), (hw * 0.985, z0 + h * 0.74), (hw * 0.90, zt - 0.015), (hw * 0.55, zt + 0.006), (0, zt + 0.012)]
        rings.append(ring(x, half))
    a.loft(M['paint'], rings)
    # салон (зелёнка)
    gtop = [(-1.20, 0.94), (-1.02, 1.17), (-0.82, 1.36), (-0.55, 1.415), (0.05, 1.425), (0.30, 1.40), (0.56, 1.26), (0.88, 0.955)]
    gx0, gx1 = gtop[0][0], gtop[-1][0]
    def gparams(x):
        zt = interp(gtop, x); z0 = interp(top, x) - 0.02
        k = min(1.0, (zt - z0) / 0.25)
        hwb = HW * 0.90; hwt = hwb - 0.15 * min(1.0, (zt - z0) / 0.48)
        return z0, zt, hwb, hwt
    def gring(x):
        z0, zt, hwb, hwt = gparams(x); h = max(zt - z0, 0.012)
        half = [(0, z0), (hwb, z0), (hwb * 0.99, z0 + 0.1 * h), (hwt, zt - 0.07 * h), (hwt * 0.9, zt - 0.004), (hwt * 0.5, zt + 0.008), (0, zt + 0.014)]
        return ring(x, half)
    gxs = [gx0 + (gx1 - gx0) * i / 34 for i in range(35)]
    a.loft(M['paint'], [gring(x) for x in gxs])
    def side_pts(x):
        z0, zt, hwb, hwt = gparams(x); h = zt - z0
        return (x, hwb * 0.99, z0 + 0.1 * h), (x, hwt, zt - 0.07 * h)
    if not burnt:
        for (xa, xb) in ((-1.05, -0.36), (-0.2, 0.52)):
            for sd in (-1, 1): window_poly(a, M, side_pts, xa, xb, 0.06, 0.88, sd, 0.005, 8)
        # лобовое и заднее — по реальной линии крыши салона
        def glass_strip(xa, xb, k=0.9, n=10, lift=0.02):
            L, R = [], []
            for i in range(n + 1):
                x = xa + (xb - xa) * i / n
                z0, zt, hwb, hwt = gparams(x)
                wv = hwt * k
                L.append((x, -wv, zt + lift)); R.append((x, wv, zt + lift))
            a.face(M['glass'], L + R[::-1])
        glass_strip(0.34, 0.80); glass_strip(-1.12, -0.86)
        # сиденья и руль видны сквозь стёкла
        for sx in (-0.3, 0.2): a.box(M['seat'], (sx, 0.0, 1.0), (0.3, 1.0, 0.3))
    # детали
    a.box(M['dark'], (2.07, 0, 0.5), (0.06, 0.78, 0.16))                              # решётка
    for s in (-1, 1):
        lamp_disc(a, M['lamp'], 2.07, s * 0.56, 0.62, 0.1)
        a.box(M['tail'], (-2.06, s * 0.62, 0.74), (0.05, 0.3, 0.1))
        a.box(M['dark'], (0.0, s * 0.835, 0.42), (2.4, 0.03, 0.06))                    # порог
        a.box(M['dark'], (-0.2, s * 0.84, 0.82), (0.9, 0.012, 0.02)); a.box(M['dark'], (0.3, s * 0.84, 0.72), (0.14, 0.02, 0.025))   # шов двери, ручка
        a.box(M['dark'], (0.45, s * 0.84, 1.0), (0.14, 0.12, 0.09), rot=(0, 0, s * -0.4))     # зеркало
    a.box(M['chrome'], (2.12, 0, 0.36), (0.1, 1.5, 0.11)); a.box(M['chrome'], (-2.12, 0, 0.38), (0.1, 1.5, 0.11))
    a.box(M['plate'], (2.115, 0, 0.5), (0.02, 0.5, 0.12)); a.box(M['plate'], (-2.11, 0, 0.55), (0.02, 0.5, 0.12))
    a.box(M['dark'], (0, 0, 0.27), (3.6, 1.2, 0.08))
    for xc, r in arches:
        a.box(M['dark'], (xc, 0, 0.5), (0.8, 1.3, 0.34))
    a.box(M['rust'], (-1.9, 0.4, 0.3), (0.5, 0.05, 0.05), rot=(0, 0, 0.1))              # выхлопная
    # колёса
    for i, (x, y) in enumerate(((1.28, 0.7), (1.28, -0.7), (-1.28, 0.7), (-1.28, -0.7))):
        if burnt and rnd.random() < 0.5: continue
        wheel(a, M, x, y, 0.31, flat=(i == 2))
    # дворники и капот/трещина
    a.box(M['dark'], (0.7, 0.2, 0.97), (0.04, 0.5, 0.012), rot=(0, 0, 0.3)); a.box(M['dark'], (0.7, -0.35, 0.97), (0.04, 0.5, 0.012), rot=(0, 0, 0.3))
    return a.build(name)


# ======================= общие куски для «ящичных» машин =======================
def boxy_half(hw, zb, zt):
    h = zt - zb
    return [(0, zb), (hw * 0.9, zb), (hw * 0.995, zb + 0.06 * h), (hw, zb + 0.5 * h), (hw, zt - 0.10 * h), (hw * 0.965, zt - 0.025 * h), (hw * 0.8, zt), (hw * 0.4, zt + 0.01), (0, zt + 0.012)]

def boxy_body(a, m, x0, x1, top, zb_fn, hw, end_round=(0.0, 0.0), step=0.08):
    n = max(8, int((x1 - x0) / step))
    xs = sorted(set([round(x0 + (x1 - x0) * i / n, 4) for i in range(n + 1)] + list(zb_fn.__dict__.get('extra', []))))
    rings = []
    for x in xs:
        zt = interp(top, x); z0 = zb_fn(x)
        f = 1.0
        if end_round[0] > 0 and x > x1 - end_round[0]: f = 1 - 0.18 * ((x - (x1 - end_round[0])) / end_round[0]) ** 2
        if end_round[1] > 0 and x < x0 + end_round[1]: f = 1 - 0.14 * (((x0 + end_round[1]) - x) / end_round[1]) ** 2
        rings.append(ring(x, boxy_half(hw * f, z0, max(zt, z0 + 0.04))))
    a.loft(m, rings)

def arch_bottom(base, arches, kind=0.96):
    def f(x):
        z = base(x) if callable(base) else base
        for xc, r, zc in arches:
            d = abs(x - xc)
            if d < r: z = max(z, zc + math.sqrt(r * r - d * d) * kind)
        return z
    f.extra = sorted(set([round(xc + k * r, 4) for xc, r, zc in arches for k in (-1, -0.7, -0.35, 0, 0.35, 0.7, 1)]))
    return f

def sidewin(a, M, hw, zlo, zhi_fn, xa, xb, sides=(-1, 1), n=8, lo_off=0.0):
    def pts(x):
        zh = zhi_fn(x)
        return (x, hw, zlo), (x, hw, max(zlo + 0.05, zh))
    for sd in sides: window_poly(a, M, pts, xa, xb, 0.0, 1.0, sd, 0.014, n)

def log(a, M, x, y, z, r, L):
    a.cyl(M['bark'], (x, y, z), r, L, 'X', 12)
    for sd in (-1, 1): a.cyl(M['endgrain'], (x + sd * (L / 2 + 0.004), y, z), r * 0.97, 0.012, 'X', 12)

def mats2(paint):
    M = mats(paint)
    M.update(bark=material('bark', 'bark', rough=1.0, tile=0.8), endgrain=material('endgrain', 'endgrain', rough=1.0, tile=0.5),
             tin=material('tin_gray', 'tin_gray', rough=0.6, metal=0.3, tile=1.0), hay=material('hay', 'hay', rough=1.0, tile=1.0))
    return M

# ======================= «буханка» (УАЗ-452) =======================
def uaz(name, paint, seed, wagon_roof=False):
    rnd = random.Random(seed); M = mats2(paint); a = Acc()
    top = [(-2.26, 1.88), (-2.2, 2.05), (-2.0, 2.09), (1.1, 2.09), (1.24, 1.95), (1.42, 1.17), (1.62, 1.08), (2.0, 1.05), (2.22, 0.98), (2.3, 0.84)]
    arches = [(-1.42, 0.43, 0.37), (1.42, 0.43, 0.37)]
    zb = arch_bottom(lambda x: 0.30 + (0.1 * min(1.0, max(0.0, (abs(x) - 2.1) / 0.18))), arches)
    boxy_body(a, M['paint'], -2.26, 2.3, top, zb, 0.97, (0.2, 0.15))
    hz = lambda x: min(1.84, interp(top, x) - 0.18)
    for (xa, xb) in ((0.55, 1.14), (-0.62, 0.38), (-1.78, -0.8)):
        sidewin(a, M, 0.97, 1.30, hz, xa, xb)
    a.face(M['glass'], [(1.43, -0.83, 1.22), (1.43, 0.83, 1.22), (1.285, 0.83, 1.86), (1.285, -0.83, 1.86)][::-1])
    a.face(M['glass'], [(-2.262, -0.7, 1.36), (-2.262, 0.7, 1.36), (-2.235, 0.7, 1.84), (-2.235, -0.7, 1.84)])
    a.box(M['dark'], (2.31, 0, 0.62), (0.05, 0.82, 0.3)); a.box(M['chrome'], (2.32, 0, 0.76), (0.03, 0.8, 0.04))
    for s in (-1, 1):
        lamp_disc(a, M['lamp'], 2.29, s * 0.66, 0.9, 0.11)
        a.box(M['tail'], (-2.265, s * 0.82, 0.95), (0.04, 0.12, 0.3))
        a.box(M['dark'], (-0.15, s * 0.975, 0.52), (3.7, 0.025, 0.06))
        for xd in (1.1, -0.62): a.box(M['dark'], (xd, s * 0.975, 0.9), (0.012, 0.02, 0.7))          # швы дверей
        a.box(M['dark'], (1.38, s * 1.05, 1.15), (0.1, 0.1, 0.14))                                      # зеркало
    a.box(M['chrome'], (2.36, 0, 0.46), (0.1, 1.96, 0.12)); a.box(M['chrome'], (-2.32, 0, 0.46), (0.1, 1.96, 0.12))
    a.cyl(M['rubber'], (-2.3, 0, 1.15), 0.34, 0.16, 'X', 20); a.cyl(M['rim'], (-2.385, 0, 1.15), 0.18, 0.02, 'X', 12)   # запаска
    a.box(M['dark'], (0, 0, 0.3), (4.2, 1.5, 0.1))
    for xc, r, zc in arches: a.box(M['dark'], (xc, 0, 0.62), (1.0, 1.5, 0.42))
    for i, (x, y) in enumerate(((1.42, 0.86), (1.42, -0.86), (-1.42, 0.86), (-1.42, -0.86))):
        wheel(a, M, x, y, 0.37, r=0.37, w=0.24, flat=(i == 3))
    return a.build(name)

# ======================= автобус (ПАЗ) =======================
def bus(name, paint, seed):
    rnd = random.Random(seed); M = mats2(paint); a = Acc()
    top = [(-3.62, 2.3), (-3.52, 2.78), (-3.3, 2.9), (2.1, 2.92), (2.28, 2.72), (2.42, 1.9), (2.55, 1.46), (3.2, 1.32), (3.58, 1.1), (3.64, 0.9)]
    arches = [(-1.9, 0.56, 0.5), (2.2, 0.56, 0.5)]
    zb = arch_bottom(lambda x: 0.4 + (0.1 * min(1.0, max(0.0, (abs(x) - 3.4) / 0.2))), arches)
    boxy_body(a, M['paint'], -3.62, 3.64, top, zb, 1.2, (0.3, 0.2))
    hz = lambda x: min(2.5, interp(top, x) - 0.22)
    for (xa, xb) in ((-3.3, -2.35), (-2.2, -1.2), (-1.05, -0.1), (0.05, 1.0), (1.15, 2.0)):
        sidewin(a, M, 1.2, 1.5, hz, xa, xb, n=3)
    a.face(M['glass'], [(2.43, -1.05, 1.5), (2.43, 1.05, 1.5), (2.3, 1.05, 2.55), (2.3, -1.05, 2.55)][::-1])
    a.face(M['glass'], [(-3.64, -0.9, 1.7), (-3.64, 0.9, 1.7), (-3.55, 0.9, 2.5), (-3.55, -0.9, 2.5)])
    for sd in (-1, 1): a.box(M['dark'], (0.6, sd * 1.205, 1.0), (1.0, 0.02, 1.3)) if sd > 0 else None       # дверь пассажирская
    a.box(M['dark'], (3.66, 0, 0.78), (0.06, 1.0, 0.4)); a.box(M['chrome'], (3.67, 0, 0.98), (0.03, 1.0, 0.05))
    for s in (-1, 1):
        lamp_disc(a, M['lamp'], 3.62, s * 0.85, 1.05, 0.13)
        a.box(M['tail'], (-3.64, s * 1.0, 0.9), (0.04, 0.14, 0.4))
        a.box(M['dark'], (0.0, s * 1.2, 0.62), (7.0, 0.03, 0.07))
        a.box(M['dark'], (2.4, s * 1.28, 2.1), (0.05, 0.05, 0.9), rot=(0, 0, 0))                          # зеркало-штанга
    a.box(M['chrome'], (3.7, 0, 0.52), (0.1, 2.4, 0.14)); a.box(M['chrome'], (-3.7, 0, 0.55), (0.1, 2.4, 0.14))
    a.box(M['tin'], (-1.0, 0, 2.95), (0.8, 0.7, 0.08))                                                   # люк
    a.box(M['dark'], (0, 0, 0.4), (7.4, 1.9, 0.1))
    for xc, r, zc in arches: a.box(M['dark'], (xc, 0, 0.8), (1.2, 2.0, 0.6))
    for x in (2.2, -1.9):
        for s in (-1, 1):
            wheel(a, M, x, s * 1.1, 0.5, r=0.5, w=0.3, flat=(x == -1.9 and s == 1))
            if x == -1.9: wheel(a, M, x, s * 1.44, 0.5, r=0.5, w=0.3)
    return a.build(name)

# ======================= грузовик с бортом (ГАЗ-53 / ЗИЛ) =======================
def truck(name, paint, seed, logs=False, dump=False):
    rnd = random.Random(seed); M = mats2(paint); a = Acc()
    # лонжероны, поперечины, мосты
    for s in (-1, 1): a.box(M['dark'], (-0.2, s * 0.5, 0.88), (6.8, 0.14, 0.22))
    for x in (-3.3, -1.5, 0.3, 2.0): a.box(M['dark'], (x, 0, 0.88), (0.12, 1.1, 0.14))
    a.box(M['rust'], (2.9, 0, 0.62), (0.2, 2.0, 0.14)); a.box(M['rust'], (-0.95, 0, 0.62), (0.2, 2.1, 0.16)); a.box(M['rust'], (-2.3, 0, 0.62), (0.2, 2.1, 0.16))
    # кабина
    topc = [(0.55, 1.5), (0.6, 2.36), (0.78, 2.52), (1.85, 2.55), (2.05, 2.4), (2.22, 1.66)]
    boxy_body(a, M['paint'], 0.55, 2.22, topc, lambda x: 1.0, 0.98, (0.0, 0.0))
    hzc = lambda x: min(2.3, interp(topc, x) - 0.12)
    sidewin(a, M, 0.98, 1.68, hzc, 0.75, 1.95, n=6)
    a.face(M['glass'], [(2.12, -0.8, 1.72), (2.12, 0.8, 1.72), (2.03, 0.8, 2.3), (2.03, -0.8, 2.3)][::-1])
    a.face(M['glass'], [(0.565, -0.7, 1.75), (0.565, 0.7, 1.75), (0.6, 0.7, 2.25), (0.6, -0.7, 2.25)])
    # капот, крылья, решётка
    toph = [(2.22, 1.62), (2.5, 1.62), (3.3, 1.56), (3.5, 1.44), (3.58, 1.2)]
    boxy_body(a, M['paint'], 2.22, 3.58, toph, lambda x: 1.0 + 0.1 * (1 if x > 3.4 else 0), 0.72, (0.1, 0.0))
    for s in (-1, 1):
        a.box(M['paint'], (2.9, s * 0.93, 1.12), (1.5, 0.36, 0.16), rot=(0, 0, 0))
        a.box(M['paint'], (2.9, s * 1.08, 0.95), (1.5, 0.08, 0.5))
        a.box(M['paint'], (2.9, s * 0.95, 1.38), (1.4, 0.3, 0.06), rot=(s * 0.25, 0, 0))
        lamp_disc(a, M['lamp'], 3.6, s * 0.78, 1.28, 0.12)
    a.box(M['dark'], (3.63, 0, 1.2), (0.06, 0.8, 0.5)); a.box(M['chrome'], (3.66, 0, 1.46), (0.03, 0.8, 0.05))
    a.box(M['chrome'], (3.74, 0, 0.78), (0.14, 2.1, 0.18))
    # платформа с бортами
    a.box(M['wood'], (-1.6, 0, 1.04), (4.5, 2.3, 0.14))
    for s in (-1, 1):
        a.box(M['wood'], (-1.6, s * 1.14, 1.4), (4.5, 0.08, 0.62))
        for xx in (-3.8, -2.7, -1.6, -0.5, 0.6): a.box(M['rust'], (xx, s * 1.185, 1.4), (0.09, 0.04, 0.66))
    a.box(M['wood'], (0.72, 0, 1.45), (0.08, 2.3, 0.72))
    if logs:
        for i, (y, z, r) in enumerate([(-0.75, 1.36, 0.32), (-0.25, 1.4, 0.34), (0.25, 1.36, 0.33), (0.75, 1.38, 0.31), (-0.5, 1.95, 0.3), (0.0, 2.0, 0.32), (0.5, 1.96, 0.3), (-0.25, 2.5, 0.28), (0.25, 2.5, 0.28)]):
            log(a, M, -1.6 + rnd.uniform(-0.3, 0.3), y, z, r, 4.9 + rnd.uniform(-0.3, 0.3))
        for xx in (-3.7, -0.4): a.box(M['rust'], (xx, 0, 1.7), (0.1, 0.06, 1.3)); a.box(M['rust'], (xx, 0.9, 1.7), (0.1, 0.06, 1.3))
    else:
        a.box(M['wood'], (-4.0, 0, 1.2), (0.08, 2.3, 0.62), rot=(0, 0.55, 0), pivot=(-3.85, 0, 1.05))       # откинутый задний борт
    # колёса
    for s in (-1, 1):
        wheel(a, M, 2.85, s * 1.02, 0.5, r=0.5, w=0.3, flat=False)
        for xx in (-0.95, -2.3):
            wheel(a, M, xx, s * 1.0, 0.5, r=0.5, w=0.3, flat=(xx == -2.3 and s == 1))
            wheel(a, M, xx, s * 1.34, 0.5, r=0.5, w=0.3)
    a.cyl(M['rust'], (0.1, -1.1, 0.85), 0.25, 0.9, 'X', 12)                                              # бак
    return a.build(name)

# ======================= трактор (МТЗ) и прицеп =======================
def tractor(name, paint, seed):
    rnd = random.Random(seed); M = mats2(paint); a = Acc()
    toph = [(0.3, 1.42), (0.4, 1.48), (1.5, 1.38), (1.78, 1.28), (1.86, 1.0)]
    boxy_body(a, M['paint'], 0.3, 1.86, toph, lambda x: 0.78, 0.5, (0.2, 0.0))
    topc = [(-0.95, 1.7), (-0.9, 2.55), (-0.75, 2.68), (0.2, 2.68), (0.34, 2.55), (0.4, 1.7)]
    boxy_body(a, M['paint'], -0.95, 0.4, topc, lambda x: 1.45, 0.66, (0.0, 0.0))
    for sd in (-1, 1):
        window_poly(a, M, lambda x: ((x, 0.66, 1.75), (x, 0.66, 2.5)), -0.8, 0.28, 0.0, 1.0, sd, 0.014, 3)
    a.face(M['glass'], [(0.405, -0.55, 1.78), (0.405, 0.55, 1.78), (0.375, 0.55, 2.5), (0.375, -0.55, 2.5)][::-1])
    a.face(M['glass'], [(-0.955, -0.55, 1.78), (-0.955, 0.55, 1.78), (-0.925, 0.55, 2.5), (-0.925, -0.55, 2.5)])
    a.box(M['seat'], (-0.4, 0, 1.75), (0.4, 0.5, 0.3))
    a.box(M['dark'], (1.87, 0, 1.0), (0.05, 0.6, 0.4)); a.box(M['chrome'], (1.9, 0, 1.2), (0.03, 0.6, 0.04))
    for s in (-1, 1): lamp_disc(a, M['lamp'], 1.86, s * 0.38, 1.28, 0.09)
    a.cyl(M['rust'], (1.1, 0.25, 1.75), 0.045, 0.8, 'Z', 8)                                               # выхлопная труба
    a.box(M['dark'], (0.6, 0, 0.82), (2.0, 0.7, 0.28)); a.box(M['rust'], (1.35, 0, 0.55), (0.1, 1.5, 0.12))
    a.box(M['rust'], (2.0, 0, 0.62), (0.28, 0.6, 0.3))                                                    # пригруз
    for s in (-1, 1):
        a.box(M['paint'], (-0.9, s * 0.92, 1.42), (1.5, 0.5, 0.05), rot=(s * 0.05, 0, 0))                # крыло
        wheel(a, M, -0.9, s * 0.95, 0.8, r=0.8, w=0.46, flat=(s == 1), rim_r=0.45)
        wheel(a, M, 1.35, s * 0.78, 0.46, r=0.46, w=0.22, rim_r=0.5)
    a.box(M['rust'], (-1.45, 0, 0.7), (0.3, 0.9, 0.12))
    return a.build(name)

def trailer(name, seed):
    rnd = random.Random(seed); M = mats2('car_green'); a = Acc()
    a.box(M['wood'], (0, 0, 1.0), (3.4, 1.9, 0.14))
    for s in (-1, 1): a.box(M['wood'], (0, s * 0.93, 1.38), (3.4, 0.07, 0.62)); a.box(M['dark'], (0, s * 0.7, 0.88), (3.4, 0.14, 0.14))
    a.box(M['wood'], (-1.67, 0, 1.38), (0.07, 1.9, 0.62), rot=(0, 0.5, 0), pivot=(-1.67, 0, 1.07)); a.box(M['wood'], (1.67, 0, 1.38), (0.07, 1.9, 0.62))
    for s in (-1, 1): a.box(M['rust'], (2.3, s * 0.3, 0.92), (1.4, 0.1, 0.1), rot=(0, 0, s * -0.22))      # дышло
    a.box(M['rust'], (0, 0, 0.62), (0.12, 2.2, 0.12))
    for s in (-1, 1): wheel(a, M, 0.0, s * 1.05, 0.6, r=0.6, w=0.28, flat=(s == -1), rim_r=0.5)
    hay = rnd.random() < 2
    if hay:
        for i in range(3): a.box(M['hay'], (-0.9 + i * 0.9, rnd.uniform(-0.2, 0.2), 1.45 + (0.55 if i == 1 else 0)), (0.85, 1.6, 0.55))
    return a.build(name)

JOBS = {'car_sedan_red': lambda: sedan('car_sedan_red', 'car_red', 11), 'car_sedan_blue': lambda: sedan('car_sedan_blue', 'car_blue', 12),
        'car_sedan_white': lambda: sedan('car_sedan_white', 'car_white', 13), 'car_sedan_burnt': lambda: sedan('car_sedan_burnt', 'car_brown', 14, True),
        'car_sedan_green': lambda: sedan('car_sedan_green', 'car_green', 15), 'car_sedan_yellow': lambda: sedan('car_sedan_yellow', 'car_yellow', 16),
        'car_van_olive': lambda: uaz('car_van_olive', 'car_olive', 21), 'car_van_white': lambda: uaz('car_van_white', 'car_white', 22), 'car_van_orange': lambda: uaz('car_van_orange', 'car_orange', 23),
        'car_bus_yellow': lambda: bus('car_bus_yellow', 'car_yellow', 41), 'car_bus_blue': lambda: bus('car_bus_blue', 'car_teal', 42),
        'car_truck_blue': lambda: truck('car_truck_blue', 'car_blue', 31), 'car_truck_green': lambda: truck('car_truck_green', 'car_green', 32),
        'car_truck_logs': lambda: truck('car_truck_logs', 'car_orange', 33, logs=True),
        'tractor_blue': lambda: tractor('tractor_blue', 'car_blue', 51), 'tractor_red': lambda: tractor('tractor_red', 'car_red', 52), 'trailer_cart': lambda: trailer('trailer_cart', 53)}

if __name__ == '__main__':
    only = os.environ.get('ONLY')
    for nm, fn in JOBS.items():
        if only and nm not in only.split(','): continue
        reset()
        o = fn()
        print(nm, 'вершин', len(o.data.vertices), 'размер', tuple(round(x, 2) for x in o.dimensions))
        export(o, f'{OUT}/{nm}.glb')
        if PRE: preview(o, f'{PRE}/{nm}', views=((1, -1.2, 0.7), (-1, 1.2, 0.7)), samples=16)

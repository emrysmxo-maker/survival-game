# Заброшенные дома, сарай и хозпостройка: Blender-скрипт. Запуск: python -I houses.py <папка выхода> [превью-папка]
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *
from mathutils import Vector

OUT = sys.argv[1]
PRE = sys.argv[2] if len(sys.argv) > 2 else None

def mats():
    return dict(
        logs=material('logs', 'logs', tile=1.0), gray=material('boards_gray', 'boards_gray', tile=1.0),
        green=material('boards_green', 'boards_green', tile=1.0), blue=material('boards_blue', 'boards_blue', tile=1.0),
        brick=material('brick', 'brick', tile=1.0), slate=material('slate', 'slate', tile=1.0),
        metal=material('roofmetal', 'roofmetal', tile=1.0), conc=material('concrete', 'concrete', tile=1.2),
        floor=material('floorwood', 'floorwood', tile=1.0), rust=material('rustmetal', 'rustmetal', tile=1.0),
        dark=material('dark', color=(0.015, 0.015, 0.02, 1), rough=1.0),
        hay=material('hay', color=(0.62, 0.52, 0.24, 1), rough=1.0),
        glass=material('glass', color=(0.05, 0.07, 0.08, 1), rough=0.2))

def wall(a, m, p0, p1, th, h, ops, z0=0.0, frame=None, dark=None, glass=None, rnd=None):
    """стена от p0 до p1 (по X или по Y) толщиной th; ops: [(центр вдоль стены, ширина, низ, высота, рама?)] — проёмы"""
    along_x = abs(p1[0] - p0[0]) >= abs(p1[1] - p0[1])
    t0, t1 = (p0[0], p1[0]) if along_x else (p0[1], p1[1])
    if t0 > t1: t0, t1 = t1, t0
    fix = p0[1] if along_x else p0[0]
    def put(ta, tb, za, zb, mm=m, thk=th, off=0.0):
        if tb - ta < 0.005 or zb - za < 0.005: return
        tc = (ta + tb) / 2; zc = (za + zb) / 2
        c = (tc, fix + off, zc) if along_x else (fix + off, tc, zc)
        s = (tb - ta, thk, zb - za) if along_x else (thk, tb - ta, zb - za)
        a.box(mm, c, s)
    cur = t0
    ops = sorted(ops, key=lambda o: o[0])
    for o in ops:
        xc, w, zb, hh = o[:4]
        put(cur, xc - w / 2, z0, z0 + h)
        put(xc - w / 2, xc + w / 2, z0, z0 + zb)                     # подоконник
        put(xc - w / 2, xc + w / 2, z0 + zb + hh, z0 + h)             # над окном
        cur = xc + w / 2
        fr = o[4] if len(o) > 4 else True
        if fr and frame is not None:
            ft = 0.07
            put(xc - w / 2, xc + w / 2, z0 + zb - 0.04, z0 + zb + 0.02, frame, th + 0.1)
            put(xc - w / 2 - 0.02, xc - w / 2 + ft, z0 + zb, z0 + zb + hh, frame, th + 0.08)
            put(xc + w / 2 - ft, xc + w / 2 + 0.02, z0 + zb, z0 + zb + hh, frame, th + 0.08)
            put(xc - w / 2, xc + w / 2, z0 + zb + hh - 0.03, z0 + zb + hh + 0.05, frame, th + 0.1)
            if dark is not None: put(xc - w / 2 + ft, xc + w / 2 - ft, z0 + zb + 0.02, z0 + zb + hh - 0.02, dark, 0.02, off=0.04)
            if glass is not None and rnd is not None and rnd.random() < 0.6:   # осколок в углу рамы
                gw = rnd.uniform(0.15, 0.3); gh = rnd.uniform(0.15, 0.4)
                put(xc - w / 2 + ft, xc - w / 2 + ft + gw, z0 + zb + 0.02, z0 + zb + 0.02 + gh, glass, 0.012, off=-0.03)
    put(cur, t1, z0, z0 + h)

def roof(a, m, beam, x0, x1, y_eave_a, y_eave_b, z_eave, ridge_z, ridge_y, skip, rnd, cell=0.62, th=0.07, scatter=0.04, jag=True):
    """двускатная крыша из плиток-клеток: skip(i,j,side) -> True: клетки нет (дыра). Конёк вдоль X на y=ridge_y"""
    for side, ye in ((-1, y_eave_a), (1, y_eave_b)):
        run = abs(ridge_y - ye); rise = ridge_z - z_eave
        s = math.hypot(run, rise); ang = math.atan2(rise, run)
        nx = max(1, round((x1 - x0) / cell)); ns = max(1, round(s / cell))
        cw = (x1 - x0) / nx; cs = s / ns
        for i in range(nx):
            for j in range(ns):
                if skip(i, j, side, nx, ns): continue
                t = (j + 0.5) * cs
                xc = x0 + (i + 0.5) * cw
                yc = ye + side * -1 * 0 + (run - 0) * 0
                yc = ye + (t * math.cos(ang)) * (1 if ye < ridge_y else -1)
                zc = z_eave + t * math.sin(ang)
                dz = rnd.uniform(-scatter, scatter) if jag else 0
                rx = (ang if ye < ridge_y else -ang) + (rnd.uniform(-0.05, 0.05) if jag else 0)
                a.box(m, (xc, yc, zc + dz), (cw + 0.01, cs + 0.01, th), rot=(rx, rnd.uniform(-0.02, 0.02) if jag else 0, 0))
        # стропила под крышей
        nr = max(2, round((x1 - x0) / 0.9))
        for i in range(nr + 1):
            xc = x0 + i * (x1 - x0) / nr
            t = s / 2
            yc = ye + t * math.cos(ang) * (1 if ye < ridge_y else -1)
            zc = z_eave + t * math.sin(ang) - 0.1
            a.box(beam, (xc, yc, zc), (0.1, s, 0.12), rot=(ang if ye < ridge_y else -ang, 0, 0))
    a.box(beam, ((x0 + x1) / 2, ridge_y, ridge_z - 0.08), (x1 - x0, 0.16, 0.16))

def debris(a, m, rnd, cx, cy, cz, r, n, sz=(0.5, 0.25, 0.06)):
    for _ in range(n):
        a.box(m, (cx + rnd.uniform(-r, r), cy + rnd.uniform(-r, r), cz + rnd.uniform(0, 0.08)),
              (rnd.uniform(0.6, 1.2) * sz[0], rnd.uniform(0.6, 1.2) * sz[1], sz[2]), rot=(rnd.uniform(-0.2, 0.2), rnd.uniform(-0.2, 0.2), rnd.uniform(0, 6.28)))

def planks_on_ground(a, m, rnd, cx, cy, r, n):
    for _ in range(n):
        L = rnd.uniform(0.8, 2.0)
        a.box(m, (cx + rnd.uniform(-r, r), cy + rnd.uniform(-r, r), 0.04 + rnd.uniform(0, 0.05)), (L, 0.16, 0.04), rot=(0, rnd.uniform(-0.1, 0.1), rnd.uniform(0, 6.28)))

# ===== деревенский сруб =====
def izba(name, seed, tilt=0.0):
    rnd = random.Random(seed); M = mats(); a = Acc()
    L, D, wh, th = 7.2, 5.2, 2.3, 0.24
    zf = 0.32
    a.box(M['conc'], (0, 0, zf / 2), (L + 0.3, D + 0.3, zf))
    ys, xs = D / 2 - th / 2, L / 2 - th / 2
    wall(a, M['logs'], (-L / 2, -ys), (L / 2, -ys), th, wh, [(-1.7, 0.95, 0.0, 1.95, False), (0.9, 1.0, 0.9, 1.1), (2.6, 1.0, 0.9, 1.1)], zf, M['gray'], M['dark'], M['glass'], rnd)
    wall(a, M['logs'], (-L / 2, ys), (L / 2, ys), th, wh, [(-2.2, 0.9, 0.9, 1.0), (0.2, 0.9, 0.9, 1.0), (2.4, 0.9, 0.9, 1.0)], zf, M['gray'], M['dark'], M['glass'], rnd)
    wall(a, M['logs'], (-xs, -ys), (-xs, ys), th, wh, [(0.2, 0.9, 0.9, 1.0)], zf, M['gray'], M['dark'], M['glass'], rnd)
    wall(a, M['logs'], (xs, -ys), (xs, ys), th, wh, [(-0.8, 0.9, 0.9, 1.0), (1.2, 2.0, 1.3, 1.0, False)], zf, M['gray'], M['dark'], M['glass'], rnd)   # пролом
    for sx in (-1, 1):                                                  # фронтоны
        a.poly(M['gray'], [(sx * xs - th / 2, -ys - 0.1, zf + wh), (sx * xs - th / 2, ys + 0.1, zf + wh), (sx * xs - th / 2, 0, zf + wh + 1.45)], (th, 0, 0))
    ze = zf + wh - 0.05; rz = zf + wh + 1.5
    holes = {(1, 3), (1, 4), (2, 3), (2, 4), (3, 3), (3, 4), (2, 2), (0, 4)}
    def skip(i, j, side, nx, ns):
        if side == -1 and (i - 5, j) in {(0, 2), (1, 2), (0, 3), (1, 3), (2, 3), (1, 4), (0, 4), (2, 2)}: return True
        if side == 1 and (i - 9, j) in {(0, 3), (1, 3), (1, 4), (0, 4)}: return True
        return rnd.random() < 0.05
    roof(a, M['slate'], M['gray'], -L / 2 - 0.45, L / 2 + 0.45, -(D / 2 + 0.45), D / 2 + 0.45, ze, rz, 0, skip, rnd)
    a.box(M['floor'], (0, 0, zf + wh - 0.06), (L - 0.5, D - 0.5, 0.08))             # потолок (виден через дыру)
    debris(a, M['slate'], rnd, -0.6, -1.4, zf + wh - 0.02, 1.0, 9)
    a.box(M['floor'], (0, 0, zf + 0.04), (L - 0.5, D - 0.5, 0.06))
    # печная труба
    a.box(M['brick'], (0.5, 0.0, zf + wh + 1.1), (0.6, 0.6, 3.0)); a.box(M['brick'], (0.5, 0.0, zf + wh + 2.65), (0.72, 0.72, 0.12))
    debris(a, M['brick'], rnd, 0.9, 0.3, zf + wh - 0.02, 0.4, 3, (0.25, 0.12, 0.08))
    # дверь (приоткрыта), ставень
    a.box(M['gray'], (-1.7 + 0.5, -ys - 0.55, zf + 0.97), (0.9, 0.05, 1.9), rot=(0, 0, 1.1), pivot=(-1.7 - 0.47, -ys - 0.05, 0))
    a.box(M['gray'], (0.9 - 0.62, -ys - 0.3, zf + 1.45), (0.5, 0.04, 1.0), rot=(0, 0.1, 0.5), pivot=(0.9 - 0.52, -ys - 0.1, 0))
    # крыльцо
    a.box(M['floor'], (-1.7, -ys - 0.9, zf * 0.7), (2.2, 1.3, 0.16))
    for px in (-2.6, -0.8):
        a.box(M['gray'], (px, -ys - 1.5, 1.1), (0.14, 0.14, 2.0), rot=(0.0, 0.0, 0.0))
    a.box(M['gray'], (-1.7, -ys - 1.5, 2.1), (2.2, 0.16, 0.16))
    for i in range(3):
        if i != 1: a.box(M['slate'], (-2.4 + i * 0.7, -ys - 1.0, 2.2), (0.7, 1.4, 0.06), rot=(-0.28, 0, 0))
    planks_on_ground(a, M['gray'], rnd, 0, -ys - 1.5, 3.5, 8)
    o = a.build(name)
    o.rotation_euler = (tilt, 0, 0)
    return o

# ===== кирпичный дом (одноэтажный, шиферная/ржавая крыша, обвалился угол) =====
def brickhouse(name, seed):
    rnd = random.Random(seed); M = mats(); a = Acc()
    L, D, wh, th = 9.0, 6.4, 2.9, 0.42
    zf = 0.35
    a.box(M['conc'], (0, 0, zf / 2), (L + 0.2, D + 0.2, zf))
    ys, xs = D / 2 - th / 2, L / 2 - th / 2
    win = lambda x: (x, 1.1, 0.95, 1.35)
    wall(a, M['brick'], (-L / 2, -ys), (L / 2, -ys), th, wh, [win(-3.2), win(-1.1), (1.2, 1.1, 0.0, 2.1, False), win(3.2)], zf, M['gray'], M['dark'], M['glass'], rnd)
    wall(a, M['brick'], (-L / 2, ys), (L / 2, ys), th, wh, [win(-3.2), win(-1.1), win(1.1), (3.1, 2.6, 1.0, 2.0, False)], zf, M['gray'], M['dark'], M['glass'], rnd)   # обвал
    wall(a, M['brick'], (-xs, -ys), (-xs, ys), th, wh, [win(-1.0), win(1.0)], zf, M['gray'], M['dark'], M['glass'], rnd)
    wall(a, M['brick'], (xs, -ys), (xs, ys), th, wh, [win(0.0)], zf, M['gray'], M['dark'], M['glass'], rnd)
    for sx in (-1, 1):
        a.poly(M['brick'], [(sx * xs - th / 2, -ys - 0.05, zf + wh), (sx * xs - th / 2, ys + 0.05, zf + wh), (sx * xs - th / 2, 0, zf + wh + 1.7)], (th, 0, 0))
    ze = zf + wh; rz = zf + wh + 1.75
    def skip(i, j, side, nx, ns):
        if side == 1 and i >= 10 and j >= 1 and j <= 4: return True
        if side == 1 and i in (9, 8) and j in (2, 3): return True
        if side == -1 and (i, j) in {(4, 3), (5, 3), (4, 4), (5, 4), (6, 4), (3, 4)}: return True
        return rnd.random() < 0.07
    roof(a, M['metal'], M['gray'], -L / 2 - 0.5, L / 2 + 0.5, -(D / 2 + 0.5), D / 2 + 0.5, ze, rz, 0, skip, rnd, cell=0.7)
    a.box(M['floor'], (0, 0, zf + wh - 0.06), (L - 0.8, D - 0.8, 0.08))
    a.box(M['floor'], (0, 0, zf + 0.04), (L - 0.8, D - 0.8, 0.06))
    a.box(M['brick'], (-2.0, 0.6, zf + wh + 1.15), (0.7, 0.7, 3.2)); a.box(M['brick'], (-2.0, 0.6, zf + wh + 2.78), (0.85, 0.85, 0.12))
    debris(a, M['brick'], rnd, 3.6, ys + 0.8, 0.12, 1.2, 14, (0.28, 0.14, 0.12))
    debris(a, M['metal'], rnd, 2.8, 0.8, zf + wh - 0.02, 1.0, 8, (0.7, 0.5, 0.05))
    a.box(M['gray'], (1.2 + 0.5, -ys - 0.6, zf + 1.0), (0.95, 0.05, 2.0), rot=(0, 0, -1.2), pivot=(1.2 + 0.47, -ys - 0.05, 0))
    # крыльцо-козырёк
    a.box(M['conc'], (1.2, -ys - 0.7, 0.18), (1.8, 1.2, 0.36))
    planks_on_ground(a, M['gray'], rnd, 0, -ys - 1.6, 4.0, 6)
    return a.build(name)

# ===== большой сарай (колхозный) =====
def barn(name, seed):
    rnd = random.Random(seed); M = mats(); a = Acc()
    L, D, wh, th = 14.0, 7.6, 4.0, 0.16
    zf = 0.25
    a.box(M['conc'], (0, 0, zf / 2), (L + 0.2, D + 0.2, zf))
    ys, xs = D / 2 - th / 2, L / 2 - th / 2
    wall(a, M['green'], (-L / 2, -ys), (L / 2, -ys), th, wh, [(-4.0, 0.8, 1.6, 0.7), (-1.0, 0.8, 1.6, 0.7), (3.0, 0.8, 1.6, 0.7), (5.5, 2.4, 0.0, 3.0, False)], zf, M['gray'], M['dark'], None, rnd)
    wall(a, M['green'], (-L / 2, ys), (L / 2, ys), th, wh, [(-3.0, 0.8, 1.6, 0.7), (2.0, 0.8, 1.6, 0.7)], zf, M['gray'], M['dark'], None, rnd)
    wall(a, M['green'], (-xs, -ys), (-xs, ys), th, wh, [(0, 3.6, 0.0, 3.3, False)], zf, M['gray'], None, None, rnd)       # большие ворота
    wall(a, M['green'], (xs, -ys), (xs, ys), th, wh, [(1.0, 1.0, 2.2, 1.0)], zf, M['gray'], M['dark'], None, rnd)
    for sx in (-1, 1):
        a.poly(M['gray'], [(sx * xs - th / 2, -ys - 0.05, zf + wh), (sx * xs - th / 2, ys + 0.05, zf + wh), (sx * xs - th / 2, 0, zf + wh + 2.3)], (th, 0, 0))
    ze = zf + wh - 0.05; rz = zf + wh + 2.4
    def skip(i, j, side, nx, ns):
        if i >= 13 and j >= 2: return True
        if side == 1 and 7 <= i <= 11 and j >= 1: return True
        if side == -1 and 3 <= i <= 6 and j >= 4: return True
        return rnd.random() < 0.06
    roof(a, M['metal'], M['gray'], -L / 2 - 0.5, L / 2 + 0.5, -(D / 2 + 0.55), D / 2 + 0.55, ze, rz, 0, skip, rnd, cell=0.8)
    # фермы внутри
    for i in range(-3, 4):
        x = i * 2.2
        a.box(M['gray'], (x, 0, zf + wh + 0.08), (0.14, D, 0.16))
    # ворота: створки (одна упала, другая висит)
    a.box(M['gray'], (-xs - 0.25, -1.8 - 0.6, zf + 1.55), (1.8, 0.07, 3.1), rot=(0, 0, 0.0), pivot=(-xs, -1.8, 0))
    a.box(M['gray'], (-xs - 1.8, 2.2, 0.35), (1.8, 0.07, 3.1), rot=(0, 1.2, 0.25), pivot=(-xs - 1.8, 2.2, 0.0))
    for k in range(5):                                                                   # тюки
        a.box(M['hay'], (-3.5 + (k % 3) * 1.1, 1.8 - (k // 3) * 1.0, zf + 0.25 + (0.4 if k == 4 else 0)), (1.0, 0.7, 0.5), rot=(0, 0, rnd.uniform(-0.2, 0.2)))
    debris(a, M['metal'], rnd, 6.0, 1.0, zf + 0.04, 2.0, 7, (0.9, 0.7, 0.05))
    planks_on_ground(a, M['gray'], rnd, -5.0, -ys - 1.0, 3.5, 7)
    return a.build(name)

# ===== хозпостройка / сарайчик =====
def shed(name, seed, paint='blue'):
    rnd = random.Random(seed); M = mats(); a = Acc()
    L, D, wh, th = 3.4, 2.6, 2.0, 0.12
    zf = 0.18
    a.box(M['conc'], (0, 0, zf / 2), (L + 0.1, D + 0.1, zf))
    ys, xs = D / 2 - th / 2, L / 2 - th / 2
    mm = M[paint]
    wall(a, mm, (-L / 2, -ys), (L / 2, -ys), th, wh, [(-0.7, 0.9, 0.0, 1.75, False)], zf, M['gray'], None, None, rnd)
    wall(a, mm, (-L / 2, ys), (L / 2, ys), th, wh - 0.5, [(0.8, 0.7, 0.9, 0.5)], zf, M['gray'], M['dark'], None, rnd)
    wall(a, mm, (-xs, -ys), (-xs, ys), th, wh - 0.25, [], zf, M['gray'], None, None, rnd)
    wall(a, mm, (xs, -ys), (xs, ys), th, wh - 0.25, [], zf, M['gray'], None, None, rnd)
    # односкатная крыша
    nx, ns = 6, 5
    ang = 0.2
    for i in range(nx):
        for j in range(ns):
            if (i, j) in {(2, 3), (3, 3), (2, 4), (3, 4), (4, 4)} or rnd.random() < 0.06: continue
            cw = (L + 0.6) / nx; cs = (D + 0.6) / ns / math.cos(ang)
            yc = -D / 2 - 0.3 + (j + 0.5) * cs * math.cos(ang)
            zc = zf + wh + 0.1 - (j + 0.5) * cs * math.sin(ang)
            a.box(M['metal'], (-L / 2 - 0.3 + (i + 0.5) * cw, yc, zc + rnd.uniform(-0.03, 0.03)), (cw + 0.01, cs + 0.01, 0.05), rot=(-ang, 0, 0))
    a.box(M['gray'], (0, -ys, zf + wh - 0.02), (L, 0.12, 0.12))
    a.box(M['gray'], (-0.7 + 0.5, -ys - 0.55, zf + 0.9), (0.85, 0.05, 1.75), rot=(0, 0, 1.0), pivot=(-0.7 - 0.45, -ys - 0.05, 0))
    planks_on_ground(a, M['gray'], rnd, 0, -ys - 1.0, 2.0, 4)
    return a.build(name)

if __name__ == '__main__':
    jobs = [('house_izba_a', lambda: izba('house_izba_a', 1)), ('house_izba_b', lambda: izba('house_izba_b', 2, 0.0)),
            ('house_brick', lambda: brickhouse('house_brick', 3)), ('barn', lambda: barn('barn', 4)),
            ('shed_blue', lambda: shed('shed_blue', 5, 'blue')), ('shed_green', lambda: shed('shed_green', 6, 'green'))]
    only = os.environ.get('ONLY')
    for nm, fn in jobs:
        if only and nm not in only.split(','): continue
        reset()
        o = fn()
        print(nm, 'вершин', len(o.data.vertices), 'размер', tuple(round(x, 1) for x in o.dimensions))
        export(o, f'{OUT}/{nm}.glb')
        if PRE: preview(o, f'{PRE}/{nm}')

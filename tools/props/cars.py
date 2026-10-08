# Брошенные машины (ржавые остовы): седан (типа «Жигули»), фургон («буханка»), грузовик с бортом (типа ГАЗ-53).
# Blender-скрипт. Запуск: python -I cars.py <папка выхода> [превью-папка]; ONLY=имя1,имя2 — собрать часть.
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *
from mathutils import Vector

OUT = sys.argv[1]
PRE = sys.argv[2] if len(sys.argv) > 2 else None

def base(paint_tex):
    return dict(
        paint=material('paint_' + paint_tex, paint_tex, rough=0.7, metal=0.15, tile=2.0),
        rubber=material('rubber', color=(0.035, 0.035, 0.04, 1), rough=0.95),
        rust=material('rustmetal', 'rustmetal', rough=0.9, metal=0.2, tile=1.0),
        glass=material('glass', color=(0.045, 0.06, 0.07, 1), rough=0.15, metal=0.3),
        dark=material('dark', color=(0.015, 0.015, 0.02, 1), rough=1.0),
        lamp=material('lamp', color=(0.55, 0.54, 0.46, 1), rough=0.3),
        tail=material('tail', color=(0.28, 0.05, 0.04, 1), rough=0.5),
        wood=material('boards_gray', 'boards_gray', tile=1.0))

def arch(cx, r, z0, n=8):
    """полуокружность колёсной арки: от (cx-r,z0) вверх и обратно к (cx+r,z0)"""
    return [(cx - r * math.cos(math.pi * i / n), z0 + r * math.sin(math.pi * i / n)) for i in range(n + 1)]

def wheel(a, M, x, y, z, r=0.31, w=0.2, flat=False):
    if flat: r *= 0.82; z -= 0.04
    a.cyl(M['rubber'], (x, y, z), r, w, 'Y', 16)
    a.cyl(M['rust'], (x, y + (0.01 if y > 0 else -0.01), z), r * 0.55, w + 0.02, 'Y', 12)

def side_glass(a, m, P, u0, u1, v0, v1, n, thick=0.012):
    """стекло на грани P=(BR,BF,TF,TR): прямоугольник (u0..u1, v0..v1) на грани, чуть наружу (по нормали n)"""
    BR, BF, TF, TR = [Vector(p) for p in P]
    def pt(u, v):
        b = BR.lerp(BF, u); t = TR.lerp(TF, u); return b.lerp(t, v)
    pts = [pt(u0, v0), pt(u1, v0), pt(u1, v1), pt(u0, v1)]
    a.poly(m, pts, Vector(n).normalized() * thick)

def sedan(name, paint, seed, burnt=False):
    rnd = random.Random(seed); M = base(paint if not burnt else 'car_red'); a = Acc()
    pm = M['rust'] if burnt else M['paint']
    W = 1.62; z0 = 0.2
    prof = [(-2.05, z0)]
    prof += arch(-1.28, 0.37, z0)[:]
    prof += arch(1.28, 0.37, z0)[:]
    prof += [(2.05, z0), (2.07, 0.5), (2.0, 0.7), (1.9, 0.82), (0.85, 0.9), (0.8, 0.93), (-1.1, 0.93), (-1.95, 0.9), (-2.05, 0.78), (-2.07, 0.5)]
    prof.sort(key=lambda p: 0)   # порядок задан вручную
    a.poly(pm, [(x, -W / 2, z) for x, z in prof], (0, W, 0))
    # салон
    wb = 0.75; wt = 0.66; zb = 0.93; zt = 1.42
    xs_b = (-1.15, 0.82); xs_t = (-0.78, 0.30)
    a.hexa(pm, [(xs_b[0], -wb, zb), (xs_b[1], -wb, zb), (xs_b[1], wb, zb), (xs_b[0], wb, zb), (xs_t[0], -wt, zt), (xs_t[1], -wt, zt), (xs_t[1], wt, zt), (xs_t[0], wt, zt)])
    if not burnt:
        for s in (-1, 1):
            P = [(xs_b[0], s * wb, zb), (xs_b[1], s * wb, zb), (xs_t[1], s * wt, zt), (xs_t[0], s * wt, zt)]
            n = (0, s, 0.12)
            for (u0, u1) in ((0.05, 0.47), (0.53, 0.95)):
                if rnd.random() < 0.15: continue          # выбито — видна ржавая обшивка
                side_glass(a, M['glass'], P, u0, u1, 0.14, 0.86, n)
        P = [(xs_b[1], -wb, zb), (xs_b[1], wb, zb), (xs_t[1], wt, zt), (xs_t[1], -wt, zt)]
        side_glass(a, M['glass'], P, 0.06, 0.94, 0.12, 0.88, (0.7, 0, 0.5))                          # лобовое
        P = [(xs_b[0], wb, zb), (xs_b[0], -wb, zb), (xs_t[0], -wt, zt), (xs_t[0], wt, zt)]
        side_glass(a, M['glass'], P, 0.06, 0.94, 0.14, 0.86, (-0.6, 0, 0.5))                          # заднее
    # фары, решётка, бамперы, днище
    a.box(M['dark'], (2.075, 0, 0.58), (0.04, 0.8, 0.14))
    for s in (-1, 1):
        a.cyl(M['lamp'], (2.08, s * 0.55, 0.62), 0.1, 0.05, 'X', 10)
        a.box(M['tail'], (-2.08, s * 0.6, 0.72), (0.04, 0.3, 0.1))
    a.box(M['rust'], (2.12, 0, 0.36), (0.1, 1.68, 0.1)); a.box(M['rust'], (-2.12, 0, 0.36), (0.1, 1.68, 0.1))
    a.box(M['dark'], (0, 0, 0.2), (3.7, 1.3, 0.1))
    # колёса (одно спущено, у сгоревшего — только диски)
    for i, (x, y) in enumerate(((1.28, 0.71), (1.28, -0.71), (-1.28, 0.71), (-1.28, -0.71))):
        if burnt and rnd.random() < 0.5: continue
        wheel(a, M, x, y, 0.31, flat=(i == 2))
    if not burnt:      # капот чуть приподнят
        pass
    o = a.build(name)
    return o

def van(name, paint, seed):
    rnd = random.Random(seed); M = base(paint); a = Acc()
    pm = M['paint']
    W = 1.94; z0 = 0.3; r = 0.43
    prof = [(-2.2, z0)] + arch(-1.42, r, z0 + 0.02)[:] + arch(1.42, r, z0 + 0.02)[:]
    prof += [(2.2, z0), (2.22, 0.78), (2.1, 0.98), (1.65, 1.06), (1.4, 1.1), (1.15, 2.0), (1.05, 2.1), (-2.15, 2.1), (-2.2, 2.0), (-2.22, 0.5)]
    a.poly(pm, [(x, -W / 2, z) for x, z in prof], (0, W, 0))
    # стёкла по бокам (3 окна), лобовое и заднее
    for s in (-1, 1):
        for (x0, x1) in ((0.45, 1.05), (-0.7, 0.3), (-1.8, -0.9)):
            if rnd.random() < 0.2: continue
            a.box(M['glass'], ((x0 + x1) / 2, s * (W / 2 + 0.006), 1.62), (x1 - x0, 0.014, 0.5))
    a.poly(M['glass'], [(1.37, -0.8, 1.2), (1.37, 0.8, 1.2), (1.18, 0.8, 1.92), (1.18, -0.8, 1.92)], (0.012, 0, 0.0))
    a.box(M['glass'], (-2.216, 0, 1.55), (0.014, 1.3, 0.5))
    a.box(M['dark'], (2.215, 0, 0.62), (0.04, 0.9, 0.2))
    for s in (-1, 1):
        a.cyl(M['lamp'], (2.215, s * 0.7, 0.8), 0.11, 0.05, 'X', 10)
        a.box(M['tail'], (-2.22, s * 0.8, 0.9), (0.04, 0.16, 0.3))
    a.box(M['rust'], (2.26, 0, 0.46), (0.1, 1.95, 0.12)); a.box(M['rust'], (-2.26, 0, 0.46), (0.1, 1.95, 0.12))
    a.box(M['dark'], (0, 0, 0.28), (4.2, 1.5, 0.12))
    for i, (x, y) in enumerate(((1.42, 0.85), (1.42, -0.85), (-1.42, 0.85), (-1.42, -0.85))):
        wheel(a, M, x, y, 0.37, r=0.37, w=0.24, flat=(i == 1))
    return a.build(name)

def truck(name, paint, seed):
    rnd = random.Random(seed); M = base(paint); a = Acc()
    pm = M['paint']
    a.box(M['dark'], (0, 0, 0.62), (6.0, 0.95, 0.24)); a.box(M['rust'], (0, 0, 0.8), (5.9, 1.0, 0.1))
    # кабина и капот
    a.box(pm, (1.55, 0, 1.75), (1.6, 2.1, 1.5))
    a.hexa(pm, [(0.75, -1.05, 2.5), (2.35, -1.05, 2.5), (2.35, 1.05, 2.5), (0.75, 1.05, 2.5), (0.8, -1.0, 2.62), (2.3, -1.0, 2.62), (2.3, 1.0, 2.62), (0.8, 1.0, 2.62)])
    a.box(pm, (2.95, 0, 1.45), (1.2, 1.7, 0.85)); a.box(M['dark'], (3.56, 0, 1.4), (0.04, 1.0, 0.5))
    for s in (-1, 1):
        a.cyl(M['lamp'], (3.57, s * 0.62, 1.55), 0.12, 0.05, 'X', 10)
        a.box(M['glass'], (1.7, s * 1.056, 2.1), (1.0, 0.014, 0.65))
        a.box(pm, (2.95, s * 0.95, 0.95), (1.3, 0.12, 0.18))
    a.box(M['glass'], (2.36, 0, 2.1), (0.014, 1.7, 0.6))
    a.box(M['glass'], (0.75, 0, 2.1), (0.014, 1.5, 0.5))
    a.box(M['rust'], (3.75, 0, 0.72), (0.14, 2.0, 0.16))
    # кузов-платформа: дно и борта из досок
    a.box(M['wood'], (-1.45, 0, 1.0), (3.9, 2.25, 0.12))
    for s in (-1, 1):
        a.box(M['wood'], (-1.45, s * 1.1, 1.3), (3.9, 0.07, 0.55), rot=(0, 0, 0))
    a.box(M['wood'], (-3.4, 0, 1.3), (0.07, 2.25, 0.55), rot=(0.0, 0.5, 0.0), pivot=(-3.4, 0, 1.0))      # задний борт откинут
    a.box(M['wood'], (0.5, 0, 1.55), (0.07, 2.25, 1.0))                                                    # передний борт
    # колёса
    for x, ys, dual in ((2.65, 1.05, False), (-1.0, 1.0, True), (-2.45, 1.0, True)):
        for s in (-1, 1):
            r = 0.5
            wheel(a, M, x, s * ys, r, r=r, w=0.3, flat=(x == -1.0 and s == 1))
            if dual: wheel(a, M, x, s * (ys + 0.32), r, r=r, w=0.3)
    return a.build(name)

if __name__ == '__main__':
    jobs = {
        'car_sedan_red': lambda: sedan('car_sedan_red', 'car_red', 11), 'car_sedan_blue': lambda: sedan('car_sedan_blue', 'car_blue', 12),
        'car_sedan_white': lambda: sedan('car_sedan_white', 'car_white', 13), 'car_sedan_burnt': lambda: sedan('car_sedan_burnt', 'car_red', 14, True),
        'car_van_olive': lambda: van('car_van_olive', 'car_olive', 21), 'car_van_white': lambda: van('car_van_white', 'car_white', 22),
        'car_truck_blue': lambda: truck('car_truck_blue', 'car_blue', 31), 'car_truck_green': lambda: truck('car_truck_green', 'car_green', 32)}
    only = os.environ.get('ONLY')
    for nm, fn in jobs.items():
        if only and nm not in only.split(','): continue
        reset()
        o = fn()
        print(nm, 'вершин', len(o.data.vertices), 'размер', tuple(round(x, 2) for x in o.dimensions))
        export(o, f'{OUT}/{nm}.glb')
        if PRE: preview(o, f'{PRE}/{nm}', views=((1, -1.2, 0.7), (-1, 1.2, 0.7)), samples=20)

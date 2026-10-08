# Постройки локаций (2): колхоз, военный бункер, радиовышка. python -I locs2.py <выход> [превью]; ONLY=...
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *
from rural import PM, run
import houses
from houses import wall, roof, debris, planks_on_ground
from buildings import gable_house, hole_set
from locs import PM2

OUT = sys.argv[1]
PRE = sys.argv[2] if len(sys.argv) > 2 else None

def PM3():
    M = PM2()
    M['chain'] = material('chain', 'chain', rough=0.6, metal=0.4, tile=0.6)
    M['conc_dark'] = material('conc_dark', color=(0.12, 0.12, 0.11, 1), rough=1.0)
    M['red_w'] = material('red_w', color=(0.35, 0.04, 0.03, 1), rough=0.6)
    M['white_p'] = material('white_p', color=(0.6, 0.6, 0.58, 1), rough=0.6)
    M['cont_g'] = material('cont_g', 'tin_green', rough=0.6, metal=0.3, tile=1.2)
    M['cont_b'] = material('cont_b', 'tin_blue', rough=0.6, metal=0.3, tile=1.2)
    M['cont_r'] = material('cont_r', 'tin_red', rough=0.6, metal=0.3, tile=1.2)
    return M

# ===================== КОЛХОЗ =====================
def barn_long(name, seed):
    ops_f = [(-8.0, 1.0, 1.5, 0.8), (-4.8, 1.0, 1.5, 0.8), (-1.6, 3.6, 0.0, 3.0, False), (2.4, 1.0, 1.5, 0.8), (5.6, 1.0, 1.5, 0.8), (8.8, 1.0, 1.5, 0.8)]
    ops_b = [(-8.0, 1.0, 1.5, 0.8), (-4.0, 1.0, 1.5, 0.8), (0.0, 1.0, 1.5, 0.8), (4.0, 1.0, 1.5, 0.8), (8.0, 1.0, 1.5, 0.8), (-1.6, 3.2, 0.0, 2.8, False)]
    return gable_house(name, seed, 24.0, 9.0, 3.6, 0.16, 'red', 'metal', ops_f, ops_b, [(0, 3.2, 0.0, 2.8, False)], [(0, 1.0, 1.6, 0.9)], holes=5, eave=0.5, cell=0.8, gable='red', ridge_k=0.62, cond=1.3)

def silo(name, seed, metal=False):
    rnd = random.Random(seed); M = PM3(); a = Acc()
    R, H = 2.1, 11.0
    body = M['tin'] if metal else M['conc']
    a.cyl(M['conc'], (0, 0, 0.25), R + 0.3, 0.5, 'Z', 24)
    a.cyl(body, (0, 0, H / 2 + 0.5), R, H, 'Z', 28)
    for k in range(1, 10): a.cyl(M['rust'], (0, 0, 0.5 + k * H / 10), R + 0.035, 0.1, 'Z', 28)
    dome = []
    for i in range(7):
        t = i / 6; ang = t * math.pi / 2
        r = max(0.06, R * math.cos(ang)); z = 0.5 + H + R * 0.55 * math.sin(ang)
        dome.append([(r * math.cos(2 * math.pi * j / 20), r * math.sin(2 * math.pi * j / 20), z) for j in range(20)])
    a.loft(material('dome_tin', 'tin_gray', rough=0.6, metal=0.3, tile=1.0, smooth=True), dome)
    a.cyl(M['rust'], (0, 0, H + 0.5 + R * 0.55 + 0.3), 0.3, 0.5, 'Z', 8)
    for s in (-0.18, 0.18): a.box(M['rust'], (R + 0.08, s, H / 2 + 0.5), (0.05, 0.05, H))
    for k in range(int(H / 0.4)): a.box(M['rust'], (R + 0.08, 0, 0.7 + k * 0.4), (0.05, 0.4, 0.04))
    a.box(M['dark'], (-0.4, -R - 0.02, 3.4), (0.8, 0.04, 0.5), rot=(0, 0, 0.3)) if False else None
    a.box(M['dark'], (0.1, -R - 0.012, 2.2), (0.04, 0.02, 2.6), rot=(0, 0.08, 0)); a.box(M['dark'], (-0.5, -R - 0.012, 6.0), (0.03, 0.02, 3.0), rot=(0, -0.12, 0))
    a.box(M['dark'], (0, -R - 0.02, 1.1), (1.0, 0.04, 1.4))                                         # проём внизу
    return a.build(name)

def water_tower(name, seed):
    rnd = random.Random(seed); M = PM3(); a = Acc()
    H = 7.5
    for k in range(6):
        t = k * math.pi / 3
        a.beam(M['rust'], (1.9 * math.cos(t), 1.9 * math.sin(t), 0), (1.6 * math.cos(t), 1.6 * math.sin(t), H), 0.2)
    for z in (1.8, 3.8, 5.8):
        r = 1.9 - 0.3 * z / H
        for k in range(6):
            t0 = k * math.pi / 3; t1 = (k + 1) * math.pi / 3
            a.beam(M['rust'], (r * math.cos(t0), r * math.sin(t0), z), (r * math.cos(t1), r * math.sin(t1), z), 0.1)
            a.beam(M['rust'], (r * math.cos(t0), r * math.sin(t0), z), (r * 1.05 * math.cos(t1), r * 1.05 * math.sin(t1), z + 2.0), 0.06)
    tank = material('tank_rust', 'rustmetal', rough=0.7, metal=0.4, tile=1.5)
    a.cyl(tank, (0, 0, H + 1.5), 1.7, 3.0, 'Z', 24)
    for k in (0.7, 1.5, 2.3): a.cyl(M['rust'], (0, 0, H + k), 1.74, 0.08, 'Z', 24)
    cone = []
    for i in range(5):
        t = i / 4; r = max(0.08, 1.8 * (1 - t))
        cone.append([(r * math.cos(2 * math.pi * j / 20), r * math.sin(2 * math.pi * j / 20), H + 3.0 + t * 1.1) for j in range(20)])
    a.loft(M['rust'], cone)
    a.cyl(M['rust'], (0, 0, H / 2), 0.14, H, 'Z', 8)
    for k in range(int(H / 0.4)): a.box(M['rust'], (1.95, 0, 0.5 + k * 0.4), (0.05, 0.4, 0.04))
    return a.build(name)

def machine_shed(name, seed):
    rnd = random.Random(seed); M = PM3(); a = Acc()
    L, D, H = 20.0, 7.0, 4.0
    a.box(M['conc'], (0, 0, 0.08), (L + 0.4, D + 0.4, 0.16))
    for x in [-L / 2 + i * L / 5 for i in range(6)]:
        a.box(M['wood'], (x, -D / 2, H / 2), (0.3, 0.3, H)); a.box(M['wood'], (x, D / 2, H / 2), (0.3, 0.3, H))
    for i in range(18):
        if rnd.random() < 0.2: continue
        a.box(M['wood'], (-L / 2 + 0.6 + i * 1.07, D / 2, 1.7 + rnd.uniform(-0.2, 0.2)), (0.14, 0.05, 3.3 + rnd.uniform(-0.3, 0.3)))
    holes = {-1: hole_set(rnd, 26, 8, 3, (1.3, 2.4)), 1: hole_set(rnd, 26, 8, 2, (1.3, 2.2))}
    roof(a, M['tin_green'], M['wood'], -L / 2 - 0.5, L / 2 + 0.5, -(D / 2 + 0.5), D / 2 + 0.5, H + 0.1, H + 1.4, 0, lambda i, j, sd, nx, ns: (i, j) in holes[sd] or rnd.random() < 0.05, rnd, cell=0.8)
    return a.build(name)

def fuel_tank(name, seed):
    rnd = random.Random(seed); M = PM3(); a = Acc()
    a.cyl(M['tin_green'], (0, 0, 1.55), 1.1, 5.4, 'X', 24)
    for x in (-1.8, 1.8): a.box(M['conc'], (x, 0, 0.35), (0.7, 2.4, 0.7)); a.cyl(M['rust'], (x, 0, 1.55), 1.14, 0.1, 'X', 24)
    for sd in (-1, 1): a.cyl(M['rust'], (sd * 2.72, 0, 1.55), 1.0, 0.06, 'X', 20)
    a.cyl(M['rust'], (0.5, 0, 2.75), 0.34, 0.3, 'Z', 10); a.cyl(M['dark'], (0.5, 0, 2.91), 0.28, 0.02, 'Z', 10)
    a.cyl(M['rust'], (-1.0, 0.0, 2.7), 0.06, 0.4, 'Z', 6)
    a.cyl(M['rust'], (0, -1.15, 0.8), 0.07, 0.8, 'Z', 6); a.box(M['red_w'], (0, -1.15, 0.45), (0.2, 0.2, 0.2))
    for k in range(6): a.box(M['rust'], (-2.4 + k * 0.0, 1.14, 0.7 + k * 0.4), (0.04, 0.4, 0.04)) if False else None
    return a.build(name)

# ===================== ВОЕННЫЙ БУНКЕР =====================
def bunker_entrance(name, seed):
    rnd = random.Random(seed); M = PM3(); a = Acc()
    # земляная насыпь и бетонный оголовок
    mound = []
    for i in range(7):
        t = i / 6
        rx = 6.2 * (1 - t ** 1.8) + 0.2; ry = 5.0 * (1 - t ** 1.8) + 0.2
        mound.append([(rx * math.cos(2 * math.pi * j / 16) - 1.0, ry * math.sin(2 * math.pi * j / 16), t * 2.3) for j in range(16)])
    a.loft(material('mound_e', 'earth', rough=1.0, tile=2.5, smooth=True), mound)
    a.box(M['conc'], (0, -3.6, 1.35), (7.4, 2.2, 2.7))
    a.box(M['conc'], (0, -4.7, 2.75), (7.8, 2.8, 0.3), rot=(0.06, 0, 0))                           # козырёк
    a.box(M['conc'], (0, -5.4, 0.8), (3.4, 1.6, 1.6))
    a.box(M['dark'], (0, -5.85, 1.1), (1.9, 0.5, 2.1)); a.box(M['rust'], (0.35, -5.75, 1.05), (1.7, 0.18, 2.0), rot=(0, 0, 0.35), pivot=(-0.4, -5.75, 0))
    for sx in (-1, 1):
        a.box(M['conc'], (sx * 2.6, -6.2, 0.7), (1.4, 3.0, 1.4)); a.box(M['conc'], (sx * 2.9, -7.9, 0.3), (1.2, 1.6, 0.6))
    for (x, y) in ((-1.6, 0.5), (1.4, 1.0), (0.2, -1.0)): a.cyl(M['tin'], (x, y, 2.9), 0.32, 1.0, 'Z', 10); a.cyl(M['rust'], (x, y, 3.45), 0.4, 0.1, 'Z', 10)
    a.cyl(M['rust'], (2.2, 0.3, 3.5), 0.05, 3.2, 'Z', 6)
    a.box(M['tin_green'], (-3.5, -1.2, 0.5), (1.6, 1.0, 1.0)); a.box(M['red_w'], (0, -5.85, 3.3), (1.8, 0.1, 0.6))
    return a.build(name)

def barracks(name, seed):
    win = [(x, 1.2, 1.0, 1.3) for x in (-8.0, -5.5, -3.0, -0.5, 2.0, 4.5, 7.0)]
    ops_f = win[:3] + [(-0.0 + 0.5, 1.2, 0.0, 2.1, False)] + win[4:]
    return gable_house(name, seed, 21.0, 6.8, 3.0, 0.4, 'brick', 'metal', win[:3] + [(1.3, 1.2, 0.0, 2.1, False)] + win[4:], win, [(0, 1.2, 1.0, 1.3)], [(0, 1.2, 1.0, 1.3)], chimney=1.4, holes=4, eave=0.55, cell=0.8, gable='brick', ridge_k=0.5)

def checkpoint(name, seed):
    rnd = random.Random(seed); M = PM3(); a = Acc()
    a.box(M['conc'], (0, 0, 0.1), (3.0, 2.6, 0.2))
    for sx in (-1.2, 1.2):
        for sy in (-1.0, 1.0): a.box(M['tin_green'], (sx, sy, 1.3), (0.12, 0.12, 2.2))
    for (x, y, w, h) in ((0, -1.0, 2.4, 0), (0, 1.0, 2.4, 0)): a.box(M['tin_green'], (x, y, 0.6), (w, 0.05, 0.8)); a.box(M['glass'], (x, y, 1.5), (w - 0.1, 0.03, 1.0))
    for sx in (-1.2, 1.2): a.box(M['tin_green'], (sx, 0, 0.6), (0.05, 2.0, 0.8)); a.box(M['glass'], (sx, 0, 1.5), (0.03, 1.9, 1.0))
    a.box(M['tin_green'], (0, 0, 2.5), (3.1, 2.8, 0.1), rot=(0.05, 0, 0))
    a.box(M['conc'], (3.6, 0, 0.5), (0.5, 0.5, 1.0)); a.box(M['conc'], (-5.4, 0, 0.5), (0.5, 0.5, 1.0))
    a.box(M['red_w'], (-0.9, 0, 1.15), (7.0, 0.12, 0.14), rot=(0, 0.35, 0), pivot=(3.6, 0, 1.15)); a.box(M['white_p'], (0.7, 0.0, 1.0), (0.5, 0.13, 0.15), rot=(0, 0.35, 0), pivot=(3.6, 0, 1.15))
    a.box(M['rust'], (3.6, 0, 1.2), (0.3, 0.3, 0.3))
    return a.build(name)

def mil_tower(name, seed):
    rnd = random.Random(seed); M = PM3(); a = Acc()
    H = 8.5
    for sx in (-1, 1):
        for sy in (-1, 1): a.beam(M['rust'], (sx * 1.4, sy * 1.4, 0), (sx * 0.95, sy * 0.95, H), 0.16)
    for z in (1.2, 2.8, 4.4, 6.0, 7.5):
        w = 1.4 - 0.45 * z / H
        for sy in (-1, 1): a.beam(M['rust'], (-w, sy * w, z), (w, sy * w, z), 0.07)
        for sx in (-1, 1): a.beam(M['rust'], (sx * w, -w, z), (sx * w, w, z), 0.07)
    for z0, z1 in ((0, 1.2), (1.2, 2.8), (2.8, 4.4), (4.4, 6.0), (6.0, 7.5)):
        w0 = 1.4 - 0.45 * z0 / H; w1 = 1.4 - 0.45 * z1 / H
        for sy in (-1, 1): a.beam(M['rust'], (-w0, sy * w0, z0), (w1, sy * w1, z1), 0.05)
    a.box(M['floor'], (0, 0, H), (3.3, 3.3, 0.12))
    for (x, y, w, h) in ((0, -1.5, 3.0, 0), (0, 1.5, 3.0, 0)): a.box(M['tin_green'], (x, y, H + 0.6), (w, 0.05, 1.0)); a.box(M['glass'], (x, y, H + 1.55), (w - 0.1, 0.04, 0.9))
    for sx in (-1.5, 1.5): a.box(M['tin_green'], (sx, 0, H + 0.6), (0.05, 3.0, 1.0)); a.box(M['glass'], (sx, 0, H + 1.55), (0.04, 2.9, 0.9))
    a.box(M['tin_green'], (0, 0, H + 2.2), (3.8, 3.8, 0.12), rot=(0.0, 0.05, 0))
    a.cyl(M['dark'], (1.6, -1.6, H + 2.0), 0.25, 0.4, 'Y', 10); a.cyl(M['rust'], (0, 0, H + 3.1), 0.03, 1.8, 'Z', 6)
    for k in range(int(H / 0.4)): a.box(M['rust'], (0, 1.5 - k * 0.0 + 0.2, 0.4 + k * 0.4), (0.5, 0.04, 0.04)) if False else None
    for k in range(int((H - 0.3) / 0.38)): a.box(M['rust'], (1.45 - 0.45 * (0.4 + k * 0.38) / H * 0, 1.55, 0.4 + k * 0.38), (0.5, 0.04, 0.04)) if False else None
    for s in (-0.25, 0.25): a.beam(M['rust'], (1.65, s, 0.0), (1.2, s, H), 0.05)
    for k in range(int((H - 0.3) / 0.38)):
        z = 0.4 + k * 0.38; x = 1.65 - 0.45 * z / H
        a.box(M['rust'], (x, 0, z), (0.04, 0.5, 0.04))
    return a.build(name)

def sandbag_nest(name, seed):
    rnd = random.Random(seed); M = PM3(); a = Acc()
    R = 2.3
    for r in range(5):
        n = 22
        for i in range(n):
            t = 2 * math.pi * i / n + (r % 2) * 0.07
            if 0.8 < t < 1.7 and r < 3: continue                                       # проём
            a.box(M['sandbag'], (R * math.cos(t), R * math.sin(t), 0.1 + r * 0.19), (0.52, 0.34, 0.19), rot=(0, 0, t + math.pi / 2 + rnd.uniform(-0.05, 0.05)))
    a.box(M['tin_green'], (0, 0, 0.9), (0.04, 0.04, 0.04)) if False else None
    a.box(M['tin_green'], (0.4, -0.2, 1.0), (0.5, 0.5, 0.3)); a.cyl(M['dark'], (0.4, 0.05, 1.18), 0.04, 1.1, 'Y', 6)
    return a.build(name)

def container(name, seed, color='cont_g'):
    rnd = random.Random(seed); M = PM3(); a = Acc()
    L, W, H = 6.0, 2.4, 2.6
    a.box(M[color], (0, 0, H / 2 + 0.15), (L, W, H))
    for x in (-L / 2, L / 2):
        a.box(M['rust'], (x, 0, H / 2 + 0.15), (0.14, W + 0.04, H + 0.04))
    for y in (-W / 2, W / 2):
        a.box(M['rust'], (0, y, 0.2), (L + 0.04, 0.12, 0.2)); a.box(M['rust'], (0, y, H + 0.1), (L + 0.04, 0.12, 0.2))
    for s in (-1, 1): a.box(M['dark'], (L / 2 + 0.075, s * 0.55, H / 2 + 0.15), (0.02, 0.04, H - 0.1))
    a.box(M['rust'], (L / 2 + 0.08, 0.55, 1.4), (0.04, 0.05, 1.5)) if False else None
    return a.build(name)

def jersey(name, seed):
    rnd = random.Random(seed); M = PM3(); a = Acc()
    prof = [(-0.35, 0), (-0.35, 0.18), (-0.22, 0.5), (-0.12, 0.85), (0.12, 0.85), (0.22, 0.5), (0.35, 0.18), (0.35, 0)]
    a.poly(M['conc'], [(-1.5, y, z) for y, z in prof], (3.0, 0, 0))
    return a.build(name)

def fence_chain(name, seed, broken=False):
    rnd = random.Random(seed); M = PM3(); a = Acc()
    for sx in (-1.5, 1.5): a.cyl(M['rust'], (sx, 0, 1.15), 0.04, 2.3, 'Z', 6)
    a.box(M['rust'], (0, 0, 2.2), (3.0, 0.04, 0.04))
    a.face(M['chain'], [(-1.5, 0, 0.15), (1.5, 0, 0.15), (1.5, 0, 2.2), (-1.5, 0, 2.2)] if not broken else [(-1.5, 0, 0.15), (0.2, 0, 0.15), (0.2, 0, 1.1), (1.5, 0, 1.5), (1.5, 0, 2.2), (-1.5, 0, 2.2)])
    for k in range(3): a.torus(M['rust'], (-1.2 + k * 1.2, 0.0, 2.3), 0.2, 0.015, 'Y', 10, 4)
    for sx in (-1.5, 1.5): a.beam(M['rust'], (sx, 0, 2.3), (sx + 0.4, 0, 2.55), 0.03)
    return a.build(name)

# ===================== РАДИОВЫШКА =====================
def radio_mast(name, seed):
    rnd = random.Random(seed); M = PM3(); a = Acc()
    H = 34.0
    W0, W1 = 3.4, 0.7
    legs = []
    for k in range(3):
        t = k * 2 * math.pi / 3 + math.pi / 2
        legs.append(t)
    def pt(k, z):
        t = legs[k]; w = (W0 + (W1 - W0) * z / H) / 1.732
        return (w * math.cos(t), w * math.sin(t), z)
    nseg = 17
    for s in range(nseg):
        z0 = H * s / nseg; z1 = H * (s + 1) / nseg
        mat = M['red_w'] if s % 2 == 0 else M['white_p']
        for k in range(3):
            a.beam(mat, pt(k, z0), pt(k, z1), 0.14)
            k2 = (k + 1) % 3
            a.beam(M['rust'], pt(k, z0), pt(k2, z1), 0.05); a.beam(M['rust'], pt(k2, z0), pt(k, z1), 0.05)
            a.beam(M['rust'], pt(k, z1), pt(k2, z1), 0.06)
    for k in range(3): a.beam(M['conc'], (pt(k, 0)[0] * 1.15, pt(k, 0)[1] * 1.15, 0.0), (pt(k, 0)[0] * 1.15, pt(k, 0)[1] * 1.15, 0.5), 0.5)
    a.cyl(M['white_p'], (0, 0, H + 1.5), 0.04, 3.0, 'Z', 6)
    for z in (H - 3, H - 6):
        for k in range(3): a.beam(M['rust'], pt(k, z), (pt(k, z)[0] * 2.4, pt(k, z)[1] * 2.4, z), 0.04); a.box(M['white_p'], (pt(k, z)[0] * 2.7, pt(k, z)[1] * 2.7, z), (0.5, 0.5, 0.04))
    for lvl in (14.0, 26.0):
        for k in range(3):
            ang = legs[k] + math.pi / 3 * 0
            w = (W0 + (W1 - W0) * lvl / H) / 1.732
            top = (w * math.cos(legs[k]), w * math.sin(legs[k]), lvl)
            a.beam(M['rust'], top, (22 * math.cos(legs[k] + 0.5), 22 * math.sin(legs[k] + 0.5), 0.0), 0.022)
            a.box(M['conc'], (22 * math.cos(legs[k] + 0.5), 22 * math.sin(legs[k] + 0.5), 0.3), (0.8, 0.8, 0.6))
    return a.build(name)

def transmitter(name, seed):
    rnd = random.Random(seed); M = PM3(); a = Acc()
    L, D, H = 8.0, 5.4, 3.4
    a.box(M['conc'], (0, 0, 0.15), (L + 0.4, D + 0.4, 0.3))
    ys, xs = D / 2 - 0.2, L / 2 - 0.2
    wall(a, M['conc'], (-L / 2, -ys), (L / 2, -ys), 0.4, H, [(-1.0, 1.2, 0.0, 2.1, False), (2.2, 0.9, 1.6, 0.7)], 0.3, M['rust'], M['dark'], M['glass'], rnd)
    wall(a, M['conc'], (-L / 2, ys), (L / 2, ys), 0.4, H, [(-1.5, 0.9, 1.6, 0.7), (1.5, 0.9, 1.6, 0.7)], 0.3, M['rust'], M['dark'], M['glass'], rnd)
    wall(a, M['conc'], (-xs, -ys), (-xs, ys), 0.4, H, [], 0.3); wall(a, M['conc'], (xs, -ys), (xs, ys), 0.4, H, [(0, 1.0, 1.6, 0.7)], 0.3, M['rust'], M['dark'], M['glass'], rnd)
    for i in range(8):
        for j in range(5):
            if rnd.random() < 0.12 or (i - 5) ** 2 + (j - 2) ** 2 < 2.2: continue
            a.box(M['conc'], (-L / 2 + 0.5 + i * 1.0, -D / 2 + 0.55 + j * 1.0, H + 0.4), (1.0, 1.0, 0.2), rot=(0, 0, 0))
    a.box(M['conc'], (0, -D / 2, H + 0.65), (L + 0.2, 0.3, 0.4))
    a.box(M['rust'], (-1.0 + 0.5, -ys - 0.55, 1.35), (0.95, 0.06, 2.1), rot=(0, 0, 1.1), pivot=(-1.0 - 0.5, -ys - 0.1, 0))
    for k in range(4): a.beam(M['dark'], (-3.8 + k * 0.0, ys + 0.3, 3.0 - k * 0.0), (-3.8 - 3.5 - k * 0.3, ys + 2 + k * 0.4, 0.3), 0.06) if False else None
    a.box(M['tin_gray' if False else 'tin'], (3.0, 0, H + 0.62), (0.6, 0.6, 0.6))
    a.beam(M['dark'], (-3.0, ys + 0.2, 3.0), (-6.5, ys + 0.2, 0.2), 0.08)
    planks_on_ground(a, M['wood'], rnd, 0, -D / 2 - 1.5, 2.5, 3)
    return a.build(name)

def generator_shed(name, seed):
    return gable_house(name, seed, 3.6, 2.8, 2.2, 0.12, 'tin_green', 'tin', [(-0.6, 1.0, 0.0, 1.8, False)], [], [], [(0, 0.8, 1.0, 0.6)], chimney=0.0, holes=1, eave=0.3, cell=0.6, gable='tin_green', ridge_k=0.4)

def dish(name, seed):
    rnd = random.Random(seed); M = PM3(); a = Acc()
    a.cyl(M['rust'], (0, 0, 1.2), 0.1, 2.4, 'Z', 8)
    rings = []
    for i in range(7):
        t = i / 6; r = 1.3 * t + 0.05; z = 0.5 * (r / 1.3) ** 2 * 1.3
        rings.append([(r * math.cos(2 * math.pi * j / 16), r * math.sin(2 * math.pi * j / 16), z) for j in range(16)])
    d = Acc()
    d.loft(M['white_p'], rings, cap=False)
    obj = d.build('dish_part')
    obj.rotation_euler = (math.radians(-55), 0, 0); obj.location = (0, 0.2, 2.5)
    bpy.context.view_layer.update()
    o2 = a.build(name)
    bpy.ops.object.select_all(action='DESELECT'); o2.select_set(True); obj.select_set(True); bpy.context.view_layer.objects.active = o2
    bpy.ops.object.join()
    return bpy.context.view_layer.objects.active

JOBS = {
    'barn_long': lambda: barn_long('barn_long', 1), 'silo_conc': lambda: silo('silo_conc', 2), 'silo_metal': lambda: silo('silo_metal', 3, True), 'water_tower': lambda: water_tower('water_tower', 4),
    'machine_shed': lambda: machine_shed('machine_shed', 5), 'fuel_tank': lambda: fuel_tank('fuel_tank', 6),
    'bunker_entrance': lambda: bunker_entrance('bunker_entrance', 7), 'barracks': lambda: barracks('barracks', 8), 'checkpoint': lambda: checkpoint('checkpoint', 9),
    'mil_tower': lambda: mil_tower('mil_tower', 10), 'sandbag_nest': lambda: sandbag_nest('sandbag_nest', 11),
    'container_g': lambda: container('container_g', 12, 'cont_g'), 'container_b': lambda: container('container_b', 13, 'cont_b'), 'container_r': lambda: container('container_r', 14, 'cont_r'),
    'jersey': lambda: jersey('jersey', 15), 'fence_chain_a': lambda: fence_chain('fence_chain_a', 16), 'fence_chain_b': lambda: fence_chain('fence_chain_b', 17, True),
    'radio_mast': lambda: radio_mast('radio_mast', 18), 'transmitter': lambda: transmitter('transmitter', 19), 'generator_shed': lambda: generator_shed('generator_shed', 20), 'dish': lambda: dish('dish', 21),
}
if __name__ == '__main__':
    run(JOBS, os.environ.get('ONLY'))

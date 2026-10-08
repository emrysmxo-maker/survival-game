# Перенос цикла 100STYLE (BVH, CC BY 4.0, Ian Mason) на скелет бойца (Mixamo, поза покоя из dump_rest.gd).
# Способ: мировой поворот кости цели = (мировой поворот источника) × (выравнивание направлений костей в покое) × (покой цели).
# Источник Т-поза (нули), смотрит в +Z, правая сторона −X; цель смотрит в −Z, правая +X → разворот на 180° вокруг Y.
import json, numpy as np
from scipy.spatial.transform import Rotation as R, Slerp

MAP = {  # кость цели: (сустав BVH, сустав-ребёнок BVH для направления, кость-ребёнок цели)
    'Hips': ('Hips', None, None),
    'Spine': ('Chest', 'Chest2', 'Spine1'), 'Spine1': ('Chest2', 'Chest4', 'Spine2'), 'Spine2': ('Chest4', 'Neck', 'Neck'),
    'Neck': ('Neck', 'Head', 'Head'), 'Head': ('Head', 'Head_End', 'HeadTop_End'),
    'LeftUpLeg': ('LeftHip', 'LeftKnee', 'LeftLeg'), 'LeftLeg': ('LeftKnee', 'LeftAnkle', 'LeftFoot'),
    'LeftFoot': ('LeftAnkle', 'LeftToe', 'LeftToeBase'), 'LeftToeBase': ('LeftToe', 'LeftToe_End', 'LeftToe_End'),
    'RightUpLeg': ('RightHip', 'RightKnee', 'RightLeg'), 'RightLeg': ('RightKnee', 'RightAnkle', 'RightFoot'),
    'RightFoot': ('RightAnkle', 'RightToe', 'RightToeBase'), 'RightToeBase': ('RightToe', 'RightToe_End', 'RightToe_End'),
}
C = R.from_euler('y', 180, degrees=True)

def minarc(a, b):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    v = np.cross(a, b); c = np.dot(a, b)
    if c < -0.9999: return R.from_rotvec(np.array([0, 1, 0]) * np.pi)
    q = np.array([v[0], v[1], v[2], 1 + c]); return R.from_quat(q / np.linalg.norm(q))

class Target:
    def __init__(self, path):
        d = json.load(open(path))
        self.b = {x['name'].replace('mixamorig_', ''): x for x in d['bones']}
        self.names = [x['name'].replace('mixamorig_', '') for x in d['bones']]
        self.parent = [x['parent'] for x in d['bones']]
    def rest_w(self, n): return R.from_quat(self.b[n]['rot'])
    def rest_p(self, n): return np.array(self.b[n]['pos'])
    def rest_l(self, n): return R.from_quat(self.b[n]['lrot'])

def retarget(bvh, tgt, f0, f1, out_fps=30, straighten=True):
    """кадры f0..f1 (последний = первый по фазе) → {кость: [xyzw]}, позиции таза, скорость (ед. скелета/с), направление хода"""
    fps = 1.0 / bvh.dt
    frames = np.arange(f0, f1 + 1)
    WR, WP = bvh.world(frames)
    I = bvh.idx
    # курс таза (куда смотрит) и путь
    side = WP[:, I['LeftHip']] - WP[:, I['RightHip']]
    fy = np.arctan2(-side[:, 2], side[:, 0])            # угол «вперёд» = L×up, через atan2(x, z)
    fwd = np.stack([-side[:, 2], np.zeros(len(side)), side[:, 0]], 1)
    fyaw = np.arctan2(fwd[:, 0], fwd[:, 2])
    yaw0 = np.angle(np.mean(np.exp(1j * fyaw)))
    n = len(frames)
    tt = np.linspace(0, 1, n)
    # выпрямление дуги: поворот кадра вокруг вертикали на −(отклонение курса от линейного), чтобы конец смотрел как начало
    turn = np.angle(np.exp(1j * (fyaw[-1] - fyaw[0]))) if straighten else 0.0
    corr = -(yaw0 + turn * (tt - 0.5))
    Rc = R.from_euler('y', corr[:, None])
    hips = WP[:, I['Hips']].copy()
    # путь таза после выпрямления: интегрируем скорость, повёрнутую на поправку
    v = np.gradient(hips, axis=0)
    v = Rc.apply(v)
    path = np.cumsum(v, axis=0); path -= path[0]
    path[:, 1] = hips[:, 1]
    drift = path[-1] - path[0]; drift[1] = 0
    dist = np.linalg.norm(drift)
    dur = (f1 - f0) / fps
    speed_src = dist / dur
    move_dir = np.degrees(np.arctan2(drift[0], drift[2]))   # относительно лица (+Z источника): 0 вперёд, ±90 вбок
    inplace = path - np.outer(tt, drift)
    # масштаб: длина ноги цели / источника
    src_leg = np.linalg.norm(bvh.offset[I['RightKnee']]) + np.linalg.norm(bvh.offset[I['RightAnkle']])
    tl = tgt.rest_p('RightUpLeg') - tgt.rest_p('RightFoot')
    k = np.linalg.norm(tl) / src_leg
    ank = np.minimum(WP[:, I['LeftAnkle'], 1], WP[:, I['RightAnkle'], 1])
    ground_src = np.percentile(ank, 5)
    hip_off_t = tgt.rest_p('Hips')[1] - tgt.rest_p('RightUpLeg')[1]
    hip_off_s = -bvh.offset[I['RightHip']][1]
    # ресэмпл на out_fps
    m = int(round(dur * out_fps))
    ts = np.linspace(0, n - 1, m + 1)
    out = {}
    # мировые повороты цели
    TW = {}
    for tn, (sj, sc, tc) in MAP.items():
        S = C * Rc * WR[I[sj]] * C.inv()
        if sc is None:
            A = R.identity()
        else:
            ds = C.apply(bvh.offset[I[sc]])
            dt_ = tgt.rest_p(tc) - tgt.rest_p(tn)
            A = minarc(dt_, ds)
        TW[tn] = S * A * tgt.rest_w(tn)
    # локальные: родитель — по цепочке цели (немаппированные кости — покой)
    def world_of(name, f, cache):
        if name in cache: return cache[name]
        if name in TW: w = TW[name][f]
        else:
            pi = tgt.parent[tgt.names.index(name)]
            pw = world_of(tgt.names[pi], f, cache) if pi >= 0 else R.identity()
            w = pw * tgt.rest_l(name)
        cache[name] = w; return w
    loc = {tn: [] for tn in TW}
    for f in range(n):
        cache = {}
        for tn in TW:
            pi = tgt.parent[tgt.names.index(tn)]
            pw = world_of(tgt.names[pi], f, cache) if pi >= 0 else R.identity()
            loc[tn].append((pw.inv() * world_of(tn, f, cache)).as_quat())
    # замыкание цикла: разница конец/начало раскладывается линейно по циклу
    res = {}
    for tn, qs in loc.items():
        qs = np.array(qs)
        for i in range(1, len(qs)):
            if np.dot(qs[i], qs[i - 1]) < 0: qs[i] = -qs[i]
        rq = R.from_quat(qs)
        err = rq[-1] * rq[0].inv()
        fix = R.from_rotvec(-np.outer(tt, err.as_rotvec()))
        rq = fix * rq
        sl = Slerp(np.arange(n), rq)
        res[tn] = sl(ts).as_quat().tolist()
    # таз: позиция в осях цели
    P = C.apply(inplace) * k
    P[:, 1] = tgt.rest_p('RightFoot')[1] + (hips[:, 1] - ground_src) * k + (hip_off_t - hip_off_s * k)
    P[:, 1] -= (P[-1, 1] - P[0, 1]) * tt
    hp = np.stack([np.interp(ts, np.arange(n), P[:, j]) for j in range(3)], 1)
    return {'fps': out_fps, 'length': m / out_fps, 'rot': res, 'hips': hp.tolist(),
            'speed': float(speed_src * k), 'dir': float(move_dir), 'src': [int(f0), int(f1)]}

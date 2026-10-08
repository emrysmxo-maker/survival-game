# Нарезка циклов 100STYLE и перенос на бойца → JSON для build_mocap.gd.
# python3 make_clips.py <папка 100STYLE> <swat_rest.json> <out.json>
import sys, json, numpy as np
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from bvh import Bvh
from cycles import analyse
from retarget import Target, retarget
import posture
SRC, REST, OUT = sys.argv[1:4]
tgt = Target(REST)
_cache = {}
def load(st, k):
    key = (st, k)
    if key not in _cache: _cache[key] = Bvh(f'{SRC}/{st}/{st}_{k}.bvh')
    return _cache[key]

def pick(st, k, want_speed=None, want_dir=None, kind='F'):
    """лучший цикл: ближе к нужной скорости (см/с) / направлению, с малым поворотом"""
    b = load(st, k)
    cs = analyse(b, kind, 30, 0.25)
    if want_dir is not None:
        cs = [c for c in cs if abs(np.angle(np.exp(1j * np.radians(c[3] - want_dir)))) < np.radians(35)]
    if not cs: raise SystemExit(f'нет циклов {st} {k} {want_speed} {want_dir}')
    def score(c):
        s = c[4] / 10.0
        if want_speed is not None: s += abs(c[2] - want_speed) / 20.0
        return s
    c = min(cs, key=score)
    return b, c

clips = {}
def add(name, st, k, **kw):
    b, c = pick(st, k, **kw)
    r = retarget(b, tgt, c[0], c[1])
    wd = kw.get('want_dir')
    if wd is not None:        # ход — ровно в нужную сторону: таз и ноги доворачиваются, грудь смотрит вперёд
        r = diagonal(r, float(np.degrees(np.angle(np.exp(1j * np.radians(wd - r['dir']))))))
    clips[name] = r
    print(name, st, k, 'кадры', c[0], c[1], 'скорость см/с', round(c[2]), 'направление', round(r['dir']), 'поворот', round(c[4]))

from scipy.spatial.transform import Rotation as R

def diagonal(src, ang_deg):
    """диагональ из шага вперёд/назад: таз и ноги повёрнуты на ang вокруг вертикали, грудь смотрит как была"""
    c = json.loads(json.dumps(src))
    a = np.radians(ang_deg)
    rot = c['rot']
    n = len(rot['Hips'])
    for i in range(n):
        H = R.from_quat(rot['Hips'][i]); S = H * R.from_quat(rot['Spine'][i])
        S1 = S * R.from_quat(rot['Spine1'][i]); S2 = S1 * R.from_quat(rot['Spine2'][i])
        Y = lambda k: R.from_euler('y', a * k)
        H2, S_2, S1_2 = Y(1.0) * H, Y(0.6) * S, Y(0.3) * S1
        rot['Hips'][i] = H2.as_quat().tolist()
        rot['Spine'][i] = (H2.inv() * S_2).as_quat().tolist()
        rot['Spine1'][i] = (S_2.inv() * S1_2).as_quat().tolist()
        rot['Spine2'][i] = (S1_2.inv() * S2).as_quat().tolist()
        p = np.array(c['hips'][i]); p0 = np.array([0, p[1], 0])
        c['hips'][i] = (R.from_euler('y', a).apply(p - p0) + p0).tolist()
    c['dir'] = src['dir'] + ang_deg
    return c

def idle(st):
    """стойка: отрезок ~3 с с наименьшим движением, замкнутый в петлю"""
    b = load(st, 'ID')
    WR, WP = b.world()
    hips = WP[:, b.idx['Hips']]
    fps = int(round(1 / b.dt)); L = fps * 3
    best, bi = 1e9, 0
    for i in range(fps, len(hips) - L - fps, fps // 4):
        mv = np.linalg.norm(hips[i + L, [0, 2]] - hips[i, [0, 2]]) + np.ptp(hips[i:i + L, 0]) + np.ptp(hips[i:i + L, 2])
        if mv < best: best, bi = mv, i
    r = retarget(b, tgt, bi, bi + L, straighten=False)
    r['speed'] = 0.0
    return r

if __name__ == '__main__':
    clips['Idle'] = idle('Neutral'); print('Idle')
    add('WalkSlow', 'Neutral', 'FW', want_speed=72)
    add('Walk', 'Neutral', 'FW', want_speed=85)
    add('WalkFast', 'Neutral', 'FR', want_speed=130)      # лёгкий бег трусцой
    add('RunSlow', 'Neutral', 'FR', want_speed=165)
    add('Run', 'Rushed', 'FR', want_speed=290)
    # RunFast — запись Rocketbox «Run» из модели (быстрый бег), см. player.use_mocap
    for pre, k in (('SWalk', 'W'), ('SRun', 'R')):
        add(pre + 'Forward', 'Swat', 'F' + k, want_speed=110 if k == 'W' else 160, want_dir=0)
        add(pre + 'Backward', 'Swat', 'B' + k, want_speed=70 if k == 'W' else 125, want_dir=180, kind='B')
        for side, d in (('Left', 90), ('Right', -90)):
            try:
                add(pre + side, 'Swat', 'S' + k, want_speed=75 if k == 'W' else 125, want_dir=d, kind='S')
            except SystemExit as e:
                print(e, '→ Neutral'); add(pre + side, 'Neutral', 'S' + k, want_dir=d, kind='S')
        clips[pre + 'ForwardLeft'] = diagonal(clips[pre + 'Forward'], 45)
        clips[pre + 'ForwardRight'] = diagonal(clips[pre + 'Forward'], -45)
        clips[pre + 'BackwardLeft'] = diagonal(clips[pre + 'Backward'], -45)
        clips[pre + 'BackwardRight'] = diagonal(clips[pre + 'Backward'], 45)
    for k in list(clips):
        if k == 'Idle': continue
        clips[k], l0, h0 = posture.fix(tgt, clips[k])
        print('осанка', k, 'корпус', round(l0), 'голова', round(h0))
    json.dump(clips, open(OUT, 'w'))
    for k, c in clips.items(): print(k, 'скорость', round(c['speed'], 2), 'направление', round(c['dir']), 'длина', round(c['length'], 2))

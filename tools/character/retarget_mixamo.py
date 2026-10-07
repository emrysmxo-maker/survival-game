# Перенос клипов бойца Mixamo (Soldier.glb + swim.json) на скелет Rocketbox (Biped).
# Совпадение по глобальным поворотам костей; A-поза Rocketbox выравнивается к T-позе Mixamo по направлениям костей.
# python3 -I retarget_mixamo.py Soldier.glb swim.json target.glb out.json [jog.glb]
import sys, json, numpy as np
sys.path.insert(0, __file__.rsplit('/', 2)[0] + '/models')
from glbutil import load, acc, qmul, qinv, qrot
SOL, SWIM, TGT, OUT = sys.argv[1:5]
JOG = sys.argv[5] if len(sys.argv) > 5 else None     # бег из присланного Mixamo «Jogging» (экспорт в glb, клип 'Run')
MAP = {'Pelvis': 'Hips', 'Spine': 'Spine', 'Spine1': 'Spine1', 'Spine2': 'Spine2', 'Neck': 'Neck', 'Head': 'Head'}
for s, m in (('L', 'Left'), ('R', 'Right')):
    MAP.update({f'{s} Clavicle': f'{m}Shoulder', f'{s} UpperArm': f'{m}Arm', f'{s} Forearm': f'{m}ForeArm', f'{s} Hand': f'{m}Hand',
                f'{s} Thigh': f'{m}UpLeg', f'{s} Calf': f'{m}Leg', f'{s} Foot': f'{m}Foot', f'{s} Toe0': f'{m}ToeBase'})
# кость -> кость-«ребёнок» для направления (по именам Mixamo)
CHILD = {'Hips': 'Spine', 'Spine': 'Spine1', 'Spine1': 'Spine2', 'Spine2': 'Neck', 'Neck': 'Head'}
for m in ('Left', 'Right'):
    CHILD.update({f'{m}Shoulder': f'{m}Arm', f'{m}Arm': f'{m}ForeArm', f'{m}ForeArm': f'{m}Hand', f'{m}UpLeg': f'{m}Leg', f'{m}Leg': f'{m}Foot', f'{m}Foot': f'{m}ToeBase'})

def parents(nodes):
    p = {}
    for i, n in enumerate(nodes):
        for c in n.get('children', []):
            p[c] = i
    return p
def order(nodes, par):
    res, seen = [], set()
    def go(i):
        if i in seen: return
        if i in par: go(par[i])
        seen.add(i); res.append(i)
    for i in range(len(nodes)): go(i)
    return res
def lrot(n): return np.array(n.get('rotation', [0, 0, 0, 1]), float)
def ltr(n): return np.array(n.get('translation', [0, 0, 0]), float)
def lsc(n): return float(np.mean(n.get('scale', [1, 1, 1])))
def glob(nodes, par, ordr, R, T):
    G = {}
    for i in ordr:
        r, t, s = R[i], T[i], lsc(nodes[i])
        if i in par:
            pr, pp, ps = G[par[i]]
            G[i] = (qmul(pr, r), pp + qrot(pr, t * ps), ps * s)
        else:
            G[i] = (r, t, s)
    return G
def qbetween(a, b):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    c = np.cross(a, b); d = float(np.dot(a, b))
    if d < -0.9999:
        ax = np.cross(a, [1, 0, 0]);
        if np.linalg.norm(ax) < 1e-6: ax = np.cross(a, [0, 1, 0])
        ax /= np.linalg.norm(ax); return np.array([*ax, 0.0])
    q = np.array([*c, 1 + d]); return q / np.linalg.norm(q)
def slerp(a, b, t):
    d = np.dot(a, b)
    if d < 0: b = -b; d = -d
    if d > 0.9995: r = a + t * (b - a); return r / np.linalg.norm(r)
    th = np.arccos(d); return (np.sin((1 - t) * th) * a + np.sin(t * th) * b) / np.sin(th)

tj, tb = load(TGT); tn = tj['nodes']; tp = parents(tn); to = order(tn, tp)
tname = {n.get('name'): i for i, n in enumerate(tn)}
TR0 = {i: lrot(tn[i]) for i in range(len(tn))}; TT0 = {i: ltr(tn[i]) for i in range(len(tn))}
TG0 = glob(tn, tp, to, TR0, TT0)

def set_source(path):
    """Подготовка источника анимации (скелет Mixamo из файла): родители, T-поза, выравнивание к A-позе Rocketbox."""
    global sj, sb, sn, sp, so, sname, SR0, ST0, SG0, mx, ALIGN, k, TPOSE
    sj, sb = load(path); sn = sj['nodes']; sp = parents(sn); so = order(sn, sp)
    sname = {n.get('name'): i for i, n in enumerate(sn)}
    SR0 = {i: lrot(sn[i]) for i in range(len(sn))}; ST0 = {i: ltr(sn[i]) for i in range(len(sn))}
    SG0 = glob(sn, sp, so, SR0, ST0)
    mx = {}   # имя Mixamo -> (индекс источника, индекс цели)
    for b_, m in MAP.items():
        mx[m] = (sname['mixamorig:' + m], tname['Bip01 ' + b_])
    ALIGN = {}
    for m, (si, ti) in mx.items():
        if m in CHILD:
            cs, ct = mx[CHILD[m]]
            ds = SG0[cs][1] - SG0[si][1]; dt = TG0[ct][1] - TG0[ti][1]
            ALIGN[m] = qbetween(dt, ds)
        else:
            ALIGN[m] = np.array([0, 0, 0, 1.0])
    k = TG0[mx['Hips'][1]][1][1] / SG0[mx['Hips'][0]][1][1]
    TPOSE = {m: qmul(ALIGN[m], TG0[ti][0]) for m, (si, ti) in mx.items()}
    print('source', path.split('/')[-1], 'height k', round(k, 3))

def clip_frames_glb(A):
    ch = {}; tmax = 0
    for c in A['channels']:
        s = A['samplers'][c['sampler']]
        times = acc(sj, sb, s['input'])[:, 0]; vals = acc(sj, sb, s['output'])
        ch[(c['target']['node'], c['target']['path'])] = (times, vals); tmax = max(tmax, float(times[-1]))
    def sample(key, t, default):
        if key not in ch: return default
        times, vals = ch[key]
        if t >= times[-1]: return np.array(vals[-1], float)
        i = max(int(np.searchsorted(times, t, side='right')) - 1, 0)
        f = (t - times[i]) / max(times[i + 1] - times[i], 1e-9)
        if key[1] == 'rotation': return slerp(np.array(vals[i], float), np.array(vals[i + 1], float), f)
        return vals[i] * (1 - f) + vals[i + 1] * f
    n = int(round(tmax * 30)) + 1
    hk = (sname['mixamorig:Hips'], 'translation')
    drift = None
    if INPLACE and hk in ch:
        vals_h = ch[hk][1]; drift = np.array(vals_h[-1], float) - np.array(vals_h[0], float)
        n -= 1                      # последний кадр петли = первый + путь: выбрасываем, иначе кадр задвоится
    for fi in range(n):
        t = fi / 30.0
        R = {i: np.array(sample((i, 'rotation'), t, SR0[i]), float) for i in range(len(sn))}
        T = {i: np.array(sample((i, 'translation'), t, ST0[i]), float) for i in range(len(sn))}
        if drift is not None:
            T[sname['mixamorig:Hips']] = T[sname['mixamorig:Hips']] - drift * (t / (n / 30.0))   # бег на месте: убираем путь вперёд
        yield R, T
    return
def clip_len_glb(A):
    L = max(float(acc(sj, sb, A['samplers'][c['sampler']]['input'])[-1, 0]) for c in A['channels'])
    return L - 1 / 30.0 if INPLACE else L

def retarget(frames):
    tracks = {}
    for R, T in frames:
        SG = glob(sn, sp, so, R, T)
        TR = dict(TR0); TT = dict(TT0); TG = {}
        bymx = {ti: m for m, (si, ti) in mx.items()}
        for i in to:
            m = bymx.get(i)
            if m is not None:
                si = mx[m][0]
                D = qmul(SG[si][0], qinv(SG0[si][0]))
                G = qmul(D, TPOSE[m])
                pr = TG[tp[i]][0] if i in tp else np.array([0, 0, 0, 1.0])
                loc = qmul(qinv(pr), G); TR[i] = loc / np.linalg.norm(loc)
                if m == 'Hips':
                    dp = (SG[si][1] - SG0[si][1]) * k
                    gp = TG0[i][1] + dp
                    if i in tp:
                        pr2, pp2, ps2 = TG[tp[i]]
                        TT[i] = qrot(qinv(pr2), gp - pp2) / ps2
                    else:
                        TT[i] = gp
            if i in tp:
                pr, pp, ps = TG[tp[i]]
                TG[i] = (qmul(pr, TR[i]), pp + qrot(pr, TT[i] * ps), ps * lsc(tn[i]))
            else:
                TG[i] = (TR[i], TT[i], lsc(tn[i]))
        for m, (si, ti) in mx.items():
            tracks.setdefault('mixamorig_' + m, []).append([round(float(x), 5) for x in TR[ti]])
        tracks.setdefault('mixamorig_Hips_pos', []).append([round(float(x), 4) for x in TT[mx['Hips'][1]]])
    return tracks

out = {'fps': 30, 'clips': {}}
INPLACE = False
set_source(SOL)
for A in sj['animations']:
    if A['name'] not in ('Idle', 'Walk') and not (A['name'] == 'Run' and not JOG):
        continue
    L = clip_len_glb(A)
    tr = retarget(clip_frames_glb(A))
    out['clips'][A['name']] = {'len': L, 'n': len(tr['mixamorig_Hips_pos']), 'tracks': tr}
    print(A['name'], L, len(tr['mixamorig_Hips_pos']))
if JOG:
    set_source(JOG); INPLACE = True
    A = [x for x in sj['animations'] if x['name'] == 'Run'][0]
    L = clip_len_glb(A); tr = retarget(clip_frames_glb(A))
    out['clips']['Run'] = {'len': L, 'n': len(tr['mixamorig_Hips_pos']), 'tracks': tr}
    print('Run (jog, на месте)', L, len(tr['mixamorig_Hips_pos']))
    INPLACE = False
    set_source(SOL)
# плавание: swim.json — локальные повороты костей Mixamo бойца
sw = json.load(open(SWIM))
for cname, c in sw['clips'].items():
    n = int(c['n'])
    def frames():
        for f in range(n):
            R = dict(SR0); T = dict(ST0)
            for bn, arr in c['tracks'].items():
                if bn.endswith('_pos'): continue
                i = sname.get('mixamorig:' + bn[len('mixamorig_'):])
                if i is not None: R[i] = np.array(arr[f], float)
            T[sname['mixamorig:Hips']] = np.array(c['tracks']['mixamorig_Hips_pos'][f], float)
            yield R, T
    tr = retarget(frames())
    out['clips'][cname] = {'len': c['len'], 'n': n, 'tracks': tr}
    print(cname, c['len'], n)
json.dump(out, open(OUT, 'w'))

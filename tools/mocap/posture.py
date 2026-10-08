# Осанка после переноса: актёр 100STYLE часто смотрит под ноги (голова −45°) и сутулится на трусце.
# Средний наклон корпуса ограничивается, голова поднимается до ~10° вперёд; покачивание из записи сохраняется.
import numpy as np
from scipy.spatial.transform import Rotation as R

def _fk(tgt, c, i):
    W, P = {}, {}
    for j, n in enumerate(tgt.names):
        q = R.from_quat(c['rot'][n][i]) if n in c['rot'] else tgt.rest_l(n)
        lp = np.array(c['hips'][i]) if n == 'Hips' else np.array(tgt.b[n]['lpos'])
        pi = tgt.parent[j]
        if pi < 0: W[n], P[n] = q, lp
        else:
            pn = tgt.names[pi]; W[n] = W[pn] * q; P[n] = P[pn] + W[pn].apply(lp)
    return W, P

def _pitch(v):          # наклон вперёд (цель смотрит в −Z), градусы
    return np.degrees(np.arctan2(-v[2], v[1]))

def fix(tgt, c, max_torso=12.0, head=10.0):
    n = len(c['hips'])
    lean = np.mean([_pitch(P['Neck'] - P['Hips']) for P in (_fk(tgt, c, i)[1] for i in range(n))])
    dt = max(0.0, lean - max_torso)                 # на сколько выпрямить корпус
    chain = [('Spine', 0.4), ('Spine1', 0.7), ('Spine2', 1.0)]
    for i in range(n):
        W, _ = _fk(tgt, c, i)
        Wn = {}
        for b, k in chain: Wn[b] = R.from_euler('x', np.radians(dt * k)) * W[b]
        par = {'Spine': W['Hips'], 'Spine1': Wn['Spine'], 'Spine2': Wn['Spine1']}
        for b, _k in chain: c['rot'][b][i] = (par[b].inv() * Wn[b]).as_quat().tolist()
    hp = np.mean([_pitch(P['HeadTop_End'] - P['Neck']) for P in (_fk(tgt, c, i)[1] for i in range(n))])
    dh = max(0.0, hp - head)
    for i in range(n):
        W, _ = _fk(tgt, c, i)
        Wn = R.from_euler('x', np.radians(dh * 0.5)) * W['Neck']
        Wh = R.from_euler('x', np.radians(dh)) * W['Head']
        c['rot']['Neck'][i] = (W['Spine2'].inv() * Wn).as_quat().tolist()
        # Head — ребёнок Neck1 (покой)
        n1 = Wn * tgt.rest_l('Neck1')
        c['rot']['Head'][i] = (n1.inv() * Wh).as_quat().tolist()
    return c, lean, hp

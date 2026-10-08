# Поиск ровных циклов шага в длинной записи 100STYLE: прямой ход, постоянная скорость, цикл = от левой ноги впереди до левой ноги впереди.
import numpy as np
from scipy.spatial.transform import Rotation as R
from scipy.ndimage import uniform_filter1d

def yaw_of(v):
    return np.arctan2(v[..., 0], v[..., 2])

def analyse(b, kind, max_turn=25, max_cv=0.15):
    """kind: F вперёд, B назад, S вбок. Возвращает список циклов (кадр0, кадр1, скорость см/с, направление хода относительно таза рад)"""
    WR, WP = b.world()
    I = b.idx
    hips = WP[:, I['Hips']]
    fps = 1.0 / b.dt
    vel = np.gradient(hips, axis=0) * fps
    vel[:, 1] = 0
    vs = uniform_filter1d(vel, int(fps * 0.6), axis=0)
    # «вперёд таза»: перпендикуляр к линии бёдер в горизонтали
    side = WP[:, I['LeftHip']] - WP[:, I['RightHip']]
    side[:, 1] = 0
    fwd = np.stack([-side[:, 2], np.zeros(len(side)), side[:, 0]], 1)    # вверх × (влево) = вперёд для Y-вверх
    fwd /= np.linalg.norm(fwd, axis=1, keepdims=True)
    mv = vs / np.maximum(np.linalg.norm(vs, axis=1, keepdims=True), 1e-6)
    rel = np.arctan2(np.cross(fwd, mv)[:, 1], np.sum(fwd * mv, 1))   # направление хода относительно таза
    axis = mv
    la, ra = WP[:, I['LeftAnkle']], WP[:, I['RightAnkle']]
    d = np.sum((la - ra) * axis, 1)
    d = uniform_filter1d(d, 3)
    if kind == 'S':        # вбок: ведущая нога одна и та же, знак разницы — по стороне хода
        d = d * np.sign(uniform_filter1d(d, int(fps)))
    peaks = [i for i in range(1, len(d) - 1) if d[i] > d[i - 1] and d[i] >= d[i + 1] and d[i] > 5]
    out = []
    for a, c in zip(peaks[:-1], peaks[1:]):
        if c - a < fps * 0.4 or c - a > fps * 2.0: continue
        sp = np.linalg.norm(vs[a:c], axis=1)
        turn = abs(np.angle(np.exp(1j * (yaw_of(mv[c]) - yaw_of(mv[a])))))
        hturn = abs(np.angle(np.exp(1j * (yaw_of(fwd[c]) - yaw_of(fwd[a])))))
        if turn > np.radians(max_turn) or hturn > np.radians(max_turn) or sp.std() > max_cv * sp.mean(): continue
        dist = np.linalg.norm((hips[c] - hips[a])[[0, 2]])
        rr = np.angle(np.mean(np.exp(1j * rel[a:c])))
        out.append((a, c, dist / ((c - a) / fps), float(np.degrees(rr)), float(np.degrees(turn))))
    return out

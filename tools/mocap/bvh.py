# Чтение BVH (100STYLE): иерархия, смещения, каналы, кадры → мировые повороты/позиции суставов.
import numpy as np
from scipy.spatial.transform import Rotation as R

class Bvh:
    def __init__(self, path):
        self.names, self.parent, self.offset, self.chan = [], [], [], []
        lines = open(path).read().split('\n')
        i, stack, cur = 0, [], -1
        while True:
            t = lines[i].split()
            i += 1
            if not t: continue
            if t[0] in ('ROOT', 'JOINT'):
                self.names.append(t[1]); self.parent.append(stack[-1] if stack else -1)
                self.offset.append(None); self.chan.append([]); cur = len(self.names) - 1
            elif t[0] == 'End':
                self.names.append(self.names[cur] + '_End'); self.parent.append(cur)
                self.offset.append(None); self.chan.append([]); cur = len(self.names) - 1
            elif t[0] == '{': stack.append(cur)
            elif t[0] == '}':
                stack.pop(); cur = stack[-1] if stack else -1
            elif t[0] == 'OFFSET': self.offset[cur] = np.array([float(x) for x in t[1:4]])
            elif t[0] == 'CHANNELS': self.chan[cur] = t[2:]
            elif t[0] == 'MOTION': break
        self.nframes = int(lines[i].split()[1]); self.dt = float(lines[i + 1].split()[2])
        data = np.array([[float(x) for x in l.split()] for l in lines[i + 2:i + 2 + self.nframes]])
        self.offset = np.array(self.offset)
        n = len(self.names)
        self.lrot = np.zeros((self.nframes, n, 4)); self.lrot[..., 3] = 1
        self.rootpos = np.zeros((self.nframes, 3))
        c = 0
        for j in range(n):
            ch = self.chan[j]
            if not ch: continue
            pos = [k for k, x in enumerate(ch) if x.endswith('position')]
            rot = [x[0] for x in ch if x.endswith('rotation')]
            if pos: self.rootpos = data[:, c + pos[0]:c + pos[0] + 3]
            ri = [k for k, x in enumerate(ch) if x.endswith('rotation')]
            ang = data[:, [c + k for k in ri]]
            self.lrot[:, j] = R.from_euler(''.join(rot).upper(), ang, degrees=True).as_quat()
            c += len(ch)
        self.idx = {nm: k for k, nm in enumerate(self.names)}

    def world(self, frames=None):
        """мировые повороты (кватернионы xyzw) и позиции суставов"""
        L = self.lrot if frames is None else self.lrot[frames]
        P = self.rootpos if frames is None else self.rootpos[frames]
        F, n = L.shape[0], L.shape[1]
        WR = [None] * n; WP = np.zeros((F, n, 3))
        for j in range(n):
            p = self.parent[j]
            lr = R.from_quat(L[:, j])
            if p < 0:
                WR[j] = lr; WP[:, j] = P + self.offset[j]
            else:
                WR[j] = WR[p] * lr; WP[:, j] = WP[:, p] + WR[p].apply(self.offset[j])
        return WR, WP

# Подготовка игровых 3D-моделей из оригиналов Poly Haven (CC0) — они на миллионы треугольников.
#  • ствол/кора/камни: упрощение gltfpack (meshoptimizer) до игрового уровня;
#  • листва/хвоя (сотни тысяч мелких карточек): оставляется часть карточек, каждая увеличивается
#    так, чтобы покрытие осталось прежним (так делают игровые деревья). Упрощением листву не сделать —
#    рассыпается в крапинки.
# Результат: <имя>_wood.glb (+ <имя>_leaf.glb, если у модели есть листва) — варианты (a, b, c…) — узлы сцены.
# python3 prep_models.py <папка с plants/ и rocks/> <куда класть .glb> <gltfpack> [имя ...]
import sys, os, json, subprocess, shutil
import numpy as np
from PIL import Image
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

SRC, OUT, GP = sys.argv[1], sys.argv[2], sys.argv[3]
ONLY = set(sys.argv[4:])
os.makedirs(OUT, exist_ok=True)

# имя -> (листва на вариант, дерево/ствол на вариант) — бюджет треугольников
BUDGET = {
    'fir_tree_01': (40000, 9000), 'pine_tree_01': (40000, 9000),
    'island_tree_01': (25000, 8000), 'island_tree_02': (25000, 8000), 'island_tree_03': (25000, 8000),
    'tree_small_02': (20000, 6000),
    'fir_sapling': (8000, 1500), 'fir_sapling_medium': (14000, 3000),
    'pine_sapling_small': (8000, 1500), 'pine_sapling_medium': (14000, 3000),
    'shrub_01': (9000, 1000), 'shrub_02': (9000, 1000), 'shrub_03': (8000, 1000), 'shrub_04': (9000, 1000),
    'fern_02': (7000, 0), 'nettle_plant': (3000, 0), 'celandine_01': (3000, 0), 'dandelion_01': (3000, 0),
    'grass_medium_01': (3000, 0), 'grass_medium_02': (3000, 0), 'weed_plant_02': (3000, 0), 'shrub_sorrel_01': (3500, 0),
    'tree_stump_01': (0, 6000), 'tree_stump_02': (0, 6000), 'dead_tree_trunk': (0, 8000), 'dead_tree_trunk_02': (0, 8000),
    'dry_branches_medium_01': (0, 5000), 'pine_roots': (0, 5000), 'root_cluster_01': (0, 8000),
    'root_cluster_02': (0, 8000), 'single_root': (0, 4000),
    'boulder_01': (0, 6000), 'namaqualand_boulder_02': (0, 6000), 'rock_07': (0, 5000), 'rock_09': (0, 5000),
    'rock_moss_set_01': (0, 4000), 'rock_moss_set_02': (0, 4000), 'stone_01': (0, 4000),
}
FOLIAGE_WORDS = ('twig', 'leaf', 'leaves', 'needle', 'frond')
CT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8, 5122: np.int16, 5120: np.int8}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}

class G:
    def __init__(self, path):
        self.dir = os.path.dirname(path)
        self.d = json.load(open(path))
        self.bufs = [np.fromfile(f"{self.dir}/{b['uri']}", dtype=np.uint8) for b in self.d['buffers']]
    def acc(self, i):
        a = self.d['accessors'][i]; bv = self.d['bufferViews'][a['bufferView']]
        dt = np.dtype(CT[a['componentType']]); nc = NC[a['type']]
        off = bv.get('byteOffset', 0) + a.get('byteOffset', 0); st = bv.get('byteStride', 0) or dt.itemsize * nc
        b = self.bufs[bv['buffer']]
        if st == dt.itemsize * nc:
            return b[off:off + a['count'] * nc * dt.itemsize].view(dt).reshape(a['count'], nc)
        raw = b[off:off + st * a['count']].reshape(a['count'], st)[:, :dt.itemsize * nc].copy()
        return raw.view(dt).reshape(a['count'], nc)

def is_foliage(mat):
    n = mat.lower()
    return any(w in n for w in FOLIAGE_WORDS)

def reduce_foliage(g, prim, budget, seed=7):
    """оставить часть связных кусков (карточек) и увеличить их — покрытие то же"""
    idx = g.acc(prim['indices']).reshape(-1, 3).astype(np.int64)
    attr = prim['attributes']
    pos = g.acc(attr['POSITION']).astype(np.float32)
    nrm = g.acc(attr['NORMAL']).astype(np.float32) if 'NORMAL' in attr else None
    uv = g.acc(attr['TEXCOORD_0']).astype(np.float32) if 'TEXCOORD_0' in attr else None
    total = len(idx)
    if total <= budget:
        return idx, pos, nrm, uv, 1.0
    nv = len(pos)
    r = np.concatenate([idx[:, 0], idx[:, 1]]); c = np.concatenate([idx[:, 1], idx[:, 2]])
    gr = coo_matrix((np.ones(len(r), dtype=np.int8), (r, c)), shape=(nv, nv))
    ncomp, lab = connected_components(gr, directed=False)
    tl = lab[idx[:, 0]]
    cnt = np.bincount(tl, minlength=ncomp)
    present = np.nonzero(cnt)[0]
    avg = total / len(present)
    keep_n = max(1, int(budget / avg))
    rng = np.random.RandomState(seed)
    keep = rng.choice(present, size=min(keep_n, len(present)), replace=False)
    f = len(keep) / len(present)
    scale = (1.0 / f) ** 0.5 * 0.78
    keepmask = np.zeros(ncomp, bool); keepmask[keep] = True
    tri_keep = keepmask[tl]
    idx = idx[tri_keep]
    used = np.unique(idx)
    remap = -np.ones(nv, np.int64); remap[used] = np.arange(len(used))
    idx = remap[idx]
    pos = pos[used]; lab2 = lab[used]
    nrm = nrm[used] if nrm is not None else None
    uv = uv[used] if uv is not None else None
    # центроид каждой карточки; масштаб вокруг него
    sums = np.zeros((ncomp, 3)); np.add.at(sums, lab2, pos)
    n = np.bincount(lab2, minlength=ncomp).astype(np.float64)
    cen = (sums / np.maximum(n, 1)[:, None])[lab2]
    pos = (cen + (pos - cen) * scale).astype(np.float32)
    return idx, pos, nrm, uv, scale

def write_gltf(g, prims_by_mesh, out_gltf, out_bin):
    """новый gltf: те же материалы/текстуры/узлы, но примитивы заменены на подготовленные массивы"""
    d = json.loads(json.dumps(g.d))
    data = bytearray(); views = []; accs = []
    def add(arr, target=None):
        b = arr.tobytes()
        while len(data) % 4: data.append(0)
        views.append({'buffer': 0, 'byteOffset': len(data), 'byteLength': len(b), **({'target': target} if target else {})})
        data.extend(b)
        return len(views) - 1
    for mi, m in enumerate(d['meshes']):
        newp = []
        for (mat, idx, pos, nrm, uv) in prims_by_mesh.get(mi, []):
            at = {}
            vi = add(pos.astype(np.float32), 34962)
            accs.append({'bufferView': vi, 'componentType': 5126, 'count': len(pos), 'type': 'VEC3', 'min': pos.min(0).tolist(), 'max': pos.max(0).tolist()})
            at['POSITION'] = len(accs) - 1
            if nrm is not None:
                accs.append({'bufferView': add(nrm.astype(np.float32), 34962), 'componentType': 5126, 'count': len(nrm), 'type': 'VEC3'}); at['NORMAL'] = len(accs) - 1
            if uv is not None:
                accs.append({'bufferView': add(uv.astype(np.float32), 34962), 'componentType': 5126, 'count': len(uv), 'type': 'VEC2'}); at['TEXCOORD_0'] = len(accs) - 1
            accs.append({'bufferView': add(idx.astype(np.uint32).reshape(-1), 34963), 'componentType': 5125, 'count': int(idx.size), 'type': 'SCALAR'})
            newp.append({'attributes': at, 'indices': len(accs) - 1, 'material': mat, 'mode': 4})
        m['primitives'] = newp
    d['meshes'] = [m for m in d['meshes']]
    d['bufferViews'] = views; d['accessors'] = accs
    d['buffers'] = [{'uri': os.path.basename(out_bin), 'byteLength': len(data)}]
    for k in ('animations', 'skins'):
        d.pop(k, None)
    open(out_bin, 'wb').write(bytes(data)); json.dump(d, open(out_gltf, 'w'))

def run_gp(gltf, out, ratio):
    cmd = [GP, '-i', gltf, '-o', out, '-noq', '-kn', '-km']
    if ratio < 1.0:
        cmd += ['-si', f'{ratio:.5f}', '-sa']
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        print(r.stderr[-300:])

def process(name):
    for sub in ('plants', 'rocks'):
        p = f'{SRC}/{sub}/{name}/{name}.gltf'
        if os.path.exists(p):
            break
    else:
        print('нет', name); return
    g = G(p)
    os.makedirs(f'{g.dir}/t512', exist_ok=True)
    for im in g.d.get('images', []):                       # текстуры 512 (JPEG): APK не раздувается
        u1 = im['uri'].replace('_2k', '_1k')
        src = f'{g.dir}/{u1}' if os.path.exists(f'{g.dir}/{u1}') else f'{g.dir}/{im["uri"]}'
        dst = f't512/{os.path.splitext(os.path.basename(src))[0]}.jpg'
        if not os.path.exists(f'{g.dir}/{dst}'):
            Image.open(src).convert('RGB').resize((512, 512), Image.LANCZOS).save(f'{g.dir}/{dst}', quality=82)
        im['uri'] = dst
    fb, wb = BUDGET[name]
    leaf, wood = {}, {}
    ftris = wtris = 0
    for mi, m in enumerate(g.d['meshes']):
        for pr in m['primitives']:
            mat = pr['material']; mname = g.d['materials'][mat].get('name', '')
            idx_n = g.acc(pr['indices']).size // 3
            if is_foliage(mname) or (wb == 0 and fb > 0):
                idx, pos, nrm, uv, sc = reduce_foliage(g, pr, fb)
                leaf.setdefault(mi, []).append((mat, idx, pos, nrm, uv)); ftris += len(idx)
            else:
                idx = g.acc(pr['indices']).reshape(-1, 3).astype(np.int64)
                attr = pr['attributes']
                wood.setdefault(mi, []).append((mat, idx, g.acc(attr['POSITION']).astype(np.float32),
                    g.acc(attr['NORMAL']).astype(np.float32) if 'NORMAL' in attr else None,
                    g.acc(attr['TEXCOORD_0']).astype(np.float32) if 'TEXCOORD_0' in attr else None)); wtris += len(idx)
    nvar = max(1, len(g.d['meshes']))
    tmp = g.dir
    os.makedirs(tmp, exist_ok=True)
    msg = [f'{name:24s}']
    if leaf:
        write_gltf(g, leaf, f'{tmp}/{name}_leaf.gltf', f'{tmp}/{name}_leaf.bin')
        run_gp(f'{tmp}/{name}_leaf.gltf', f'{OUT}/{name}_leaf.glb', 1.0)
        msg.append(f'листва {ftris:,} ({ftris // nvar:,}/вар.)')
    if wood:
        write_gltf(g, wood, f'{tmp}/{name}_wood.gltf', f'{tmp}/{name}_wood.bin')
        ratio = min(1.0, (wb * nvar) / max(wtris, 1)) if wb else 1.0
        run_gp(f'{tmp}/{name}_wood.gltf', f'{OUT}/{name}_wood.glb', ratio)
        msg.append(f'дерево/ствол {wtris:,} -> ~{int(wtris * ratio):,}')
    for ext in ('_leaf.gltf','_leaf.bin','_wood.gltf','_wood.bin'):
        try: os.remove(f'{tmp}/{name}{ext}')
        except OSError: pass
    print(' | '.join(msg), flush=True)

for n in BUDGET:
    if not ONLY or n in ONLY:
        process(n)

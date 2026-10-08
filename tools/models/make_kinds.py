# Таблица видов: ключ из world_gen -> файл модели, узел, высота. Из старой meta.json (assets/imp).
# python3 make_kinds.py <meta.json> <kinds.json>
import json, sys, os
meta = json.load(open(sys.argv[1]))
SUB = {   # у EZ-Tree нет настоящей геометрии — подставляем модели Poly Haven
    'aspen': ('tree_small_02', None, 8.0, False),
    'oak': ('island_tree_03', None, 7.0, False),
    'dead0': ('fir_tree_01', 'fir_tree_01_a_LOD0', 7.5, True), 'dead1': ('pine_tree_01', 'pine_tree_01_b_LOD0', 7.5, True),
    'dead2': ('fir_tree_01', 'fir_tree_01_c_LOD0', 6.5, True)}
out = {}
for k, m in meta.items():
    s = m['spec']
    if 'url' in s:
        model = os.path.basename(s['url']).replace('.gltf', '')
        d = {'m': model, 'n': s.get('node'), 'h': s.get('height', 0.0), 'sc': s.get('scale', 1.0), 'cat': s['cat'], 'yaw': s.get('yaw', 0), 'wood_only': False}
    else:
        base = k.split('_')[0]
        sk = base if base in SUB else base.rstrip('0123456789')
        model, node, h, wo = SUB[sk]
        d = {'m': model, 'n': node, 'h': h, 'sc': 1.0, 'cat': s['cat'], 'yaw': 0, 'wood_only': wo}
    out[k] = d
json.dump(out, open(sys.argv[2], 'w'), ensure_ascii=False)
print(len(out), 'видов')

# Переименовывает кости UE-скелета в mixamorig_* (под player.gd/rifle_ik.gd): python3 rename_bones.py in.glb out.glb
import json, struct, sys
src, dst = sys.argv[1:3]
d = open(src, 'rb').read()
jl, = struct.unpack_from('<I', d, 12)
j = json.loads(d[20:20 + jl])
rest = d[20 + jl:]
M = {'pelvis': 'Hips', 'spine_01': 'Spine', 'spine_02': 'Spine1', 'spine_03': 'Spine2', 'neck_01': 'Neck', 'Head': 'Head'}
for s, m in (('l', 'Left'), ('r', 'Right')):
    M.update({f'clavicle_{s}': f'{m}Shoulder', f'upperarm_{s}': f'{m}Arm', f'lowerarm_{s}': f'{m}ForeArm', f'hand_{s}': f'{m}Hand',
              f'thigh_{s}': f'{m}UpLeg', f'calf_{s}': f'{m}Leg', f'foot_{s}': f'{m}Foot', f'ball_{s}': f'{m}ToeBase'})
n = 0
for nd in j['nodes']:
    if nd.get('name') in M:
        nd['name'] = 'mixamorig_' + M[nd['name']]; n += 1
print('renamed', n)
js = json.dumps(j, separators=(',', ':')).encode()
js += b' ' * ((4 - len(js) % 4) % 4)
out = struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(js) + len(rest)) + struct.pack('<I4s', len(js), b'JSON') + js + rest
open(dst, 'wb').write(out)

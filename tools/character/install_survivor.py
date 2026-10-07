# Переименовать кости Biped → mixamorig_* и положить модель в игру: python3 -I install_survivor.py in.glb out.glb
import json, struct, sys
src, dst = sys.argv[1:3]
d = open(src, 'rb').read(); jl, = struct.unpack_from('<I', d, 12); j = json.loads(d[20:20 + jl]); rest = d[20 + jl:]
M = {'Pelvis': 'Hips', 'Spine': 'Spine', 'Spine1': 'Spine1', 'Spine2': 'Spine2', 'Neck': 'Neck', 'Head': 'Head'}
for s, m in (('L', 'Left'), ('R', 'Right')):
    M.update({f'{s} Clavicle': f'{m}Shoulder', f'{s} UpperArm': f'{m}Arm', f'{s} Forearm': f'{m}ForeArm', f'{s} Hand': f'{m}Hand',
              f'{s} Thigh': f'{m}UpLeg', f'{s} Calf': f'{m}Leg', f'{s} Foot': f'{m}Foot', f'{s} Toe0': f'{m}ToeBase'})
for nd in j['nodes']:
    nm = nd.get('name', '')
    if nm.startswith('Bip01 ') and nm[6:] in M:
        nd['name'] = 'mixamorig_' + M[nm[6:]]
js = json.dumps(j, separators=(',', ':')).encode(); js += b' ' * ((4 - len(js) % 4) % 4)
open(dst, 'wb').write(struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(js) + len(rest)) + struct.pack('<I4s', len(js), b'JSON') + js + rest)

# Достаёт из .blend набора Kevin Iglesias, как автомат лежит в правой кисти в записи AssaultRifle_Aim01.
# Запуск: python -I extract_rifle_hold.py HumanM_SoldierAnimationsFREE_2.0.blend out.json
# Пишет: матрицу автомата в осях кости B-hand.R (метры), имя меша, дуло/приклад/цевьё в осях меша.
import bpy, sys, json
from mathutils import Vector
bpy.ops.wm.open_mainfile(filepath=sys.argv[1])
rig = bpy.data.objects['Rig']; rf = bpy.data.objects['Human_AssaultRifle']
act = bpy.data.actions['HumanM@AssaultRifle_Aim01']
rig.animation_data.action = act
bpy.context.scene.frame_set(int(act.frame_range[0]))
dg = bpy.context.evaluated_depsgraph_get()
H = rig.matrix_world @ rig.pose.bones['B-hand.R'].matrix
M = rf.evaluated_get(dg).matrix_world
O = H.inverted() @ M
# ось ствола в осях меша: направление «вперёд» = к левой кисти
L = rig.matrix_world @ rig.pose.bones['B-hand.L'].matrix
lt = M.inverted() @ L.translation
vs = [v.co.copy() for v in rf.data.vertices]
ext = [max(v[i] for v in vs) - min(v[i] for v in vs) for i in range(3)]
ax = ext.index(max(ext)); sgn = 1.0 if lt[ax] >= 0 else -1.0
far = max(v[ax] * sgn for v in vs); near = min(v[ax] * sgn for v in vs)
tip = [v for v in vs if v[ax] * sgn > far - 0.015 * ext[ax]]
muzzle = sum(tip, Vector()) / len(tip)
mid = sum(vs, Vector()) / len(vs)
port = mid.copy(); port[ax] = mid[ax] - sgn * 0.05 * ext[ax]
butt = [v for v in vs if v[ax] * sgn < near + 0.015 * ext[ax]]
butt = sum(butt, Vector()) / len(butt)
print('mesh', rf.data.name, 'mats', [m.name for m in rf.data.materials], 'axis', ax, sgn, 'len', ext[ax] * M.to_scale()[0])
print('muzzle world', M @ muzzle, 'butt world', M @ butt, 'L hand', L.translation)
json.dump({'mesh': rf.data.name, 'O': [list(r) for r in O], 'muzzle': list(muzzle), 'port': list(port),
           'butt': list(butt), 'left_hand': list(lt)}, open(sys.argv[2], 'w'), indent=1)

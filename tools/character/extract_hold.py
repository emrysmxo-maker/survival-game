# Достаёт из .blend набора Kevin Iglesias, как оружие лежит в правой кисти в записи прицела.
# Запуск: python -I extract_hold.py HumanM_SoldierAnimationsFREE_2.0.blend <объект> <запись> out.json
#   автомат: Human_AssaultRifle HumanM@AssaultRifle_Aim01;  пистолет: Human_GunR HumanM@Gun_Aim02
# Пишет: матрицу оружия в осях кости B-hand.R (метры), имя меша, дуло/окно/торец в осях меша.
import bpy, sys, json
from mathutils import Vector
BLEND, OBJ, ACT, OUT = sys.argv[-4:]
bpy.ops.wm.open_mainfile(filepath=BLEND)
rig = bpy.data.objects['Rig']; rf = bpy.data.objects[OBJ]
act = bpy.data.actions[ACT]
rig.animation_data.action = act
bpy.context.scene.frame_set(int(act.frame_range[0]))
dg = bpy.context.evaluated_depsgraph_get()
H = rig.matrix_world @ rig.pose.bones['B-hand.R'].matrix
M = rf.evaluated_get(dg).matrix_world
O = H.inverted() @ M
# ствол — ось меша, ближе всего к «вперёд» бойца (в .blend боец смотрит в -Y)
fwd_l = (M.inverted().to_3x3() @ Vector((0, -1, 0))).normalized()
ax = max(range(3), key=lambda i: abs(fwd_l[i])); sgn = 1.0 if fwd_l[ax] > 0 else -1.0
vs = [v.co.copy() for v in rf.data.vertices]
ext = [max(v[i] for v in vs) - min(v[i] for v in vs) for i in range(3)]
far = max(v[ax] * sgn for v in vs); near = min(v[ax] * sgn for v in vs)
up_l = (M.inverted().to_3x3() @ Vector((0, 0, 1))).normalized()
tip = [v for v in vs if v[ax] * sgn > far - 0.03 * ext[ax]]
top = max(v.dot(up_l) for v in tip)
tip = [v for v in tip if v.dot(up_l) > top - 0.04 * ext[ax]] or tip       # дуло — верх переднего торца (у пистолета — затвор)
muzzle = sum(tip, Vector()) / len(tip)
mid = sum(vs, Vector()) / len(vs)
port = mid.copy(); port[ax] = mid[ax] - sgn * 0.05 * ext[ax]
butt = [v for v in vs if v[ax] * sgn < near + 0.03 * ext[ax]]
butt = sum(butt, Vector()) / len(butt)
print('mesh', rf.data.name, 'axis', ax, sgn, 'len', round(ext[ax] * M.to_scale()[0], 3))
print('muzzle world', M @ muzzle, 'butt world', M @ butt)
json.dump({'mesh': rf.data.name, 'O': [list(r) for r in O], 'muzzle': list(muzzle), 'port': list(port),
           'butt': list(butt)}, open(OUT, 'w'), indent=1)

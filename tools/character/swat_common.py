# Общее для сборки бойца Swat (Mixamo): импорт цели, таблица соответствия костей, направления покоя.
import bpy, sys, os, math
from mathutils import Matrix, Quaternion, Vector
MX = 'mixamorig:'
# (кость Mixamo, кость Rocketbox без 'Bip01 ', кость Iglesias)
PAIRS = [('Hips', 'Pelvis', None), ('Spine', 'Spine', 'B-spine'), ('Spine1', 'Spine1', 'B-spine+chest'), ('Spine2', 'Spine2', 'B-chest'),
         ('Neck', 'Neck', 'B-neck'), ('Head', 'Head', 'B-head')]
for _s, _S in (('Left', 'L'), ('Right', 'R')):
    PAIRS += [(f'{_s}Shoulder', f'{_S} Clavicle', f'B-shoulder.{_S}'), (f'{_s}Arm', f'{_S} UpperArm', f'B-upperArm.{_S}'),
              (f'{_s}ForeArm', f'{_S} Forearm', f'B-forearm.{_S}'), (f'{_s}Hand', f'{_S} Hand', f'B-hand.{_S}'),
              (f'{_s}UpLeg', f'{_S} Thigh', f'B-thigh.{_S}'), (f'{_s}Leg', f'{_S} Calf', f'B-shin.{_S}'),
              (f'{_s}Foot', f'{_S} Foot', f'B-foot.{_S}'), (f'{_s}ToeBase', f'{_S} Toe0', f'B-toe.{_S}')]
    for _mx, _rb, _ig in (('Thumb', '0', 'thumb'), ('Index', '1', 'indexFinger'), ('Middle', '2', 'middleFinger'), ('Ring', '3', 'ringFinger'), ('Pinky', '4', 'pinky')):
        for _i, _sfx in ((1, ''), (2, '1'), (3, '2')):
            PAIRS.append((f'{_s}Hand{_mx}{_i}', f'{_S} Finger{_rb}{_sfx}', f'B-{_ig}0{_i}.{_S}'))
RZ = Quaternion((0, 0, 1), math.pi)
def qof(M): return M.decompose()[1]

def load_target(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=path)
    for o in list(bpy.data.objects):
        if o.type == 'EMPTY': bpy.data.objects.remove(o)
    tgt = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    for o in bpy.data.objects: o.animation_data_clear()
    for a in list(bpy.data.actions): bpy.data.actions.remove(a)
    bpy.ops.object.select_all(action='SELECT'); bpy.context.view_layer.objects.active = tgt
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return tgt, meshes
def face_plus_y(tgt):
    # Mixamo смотрит в -Y Blender; игре нужно +Y (лицом в -Z glTF), как у прежних бойцов
    tgt.rotation_euler[2] += math.pi
    bpy.ops.object.select_all(action='SELECT'); bpy.context.view_layer.objects.active = tgt
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
def rest_world_q(arm, bname, z180):
    q = qof(arm.matrix_world @ arm.data.bones[bname].matrix_local)
    return RZ @ q if z180 else q
def head_w(arm, bname, z180):
    p = arm.matrix_world @ arm.data.bones[bname].head_local
    return (RZ @ p) if z180 else p

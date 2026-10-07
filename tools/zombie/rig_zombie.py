# Зомби: CC0-меш «Mobile Ready Zombie» привязывается к скелету Quaternius (Universal Base Characters)
# и получает клипы Universal Animation Library. Запуск (Blender как модуль, см. CLAUDE.md):
#   python -I rig_zombie.py <папка_с_пакетами> <папка_mob_с_Zombie.fbx_и_Zombie.png> <выход.glb>
# затем tools/character/rename_bones.py выход.glb Zombie.glb
import bpy, numpy as np, math, mathutils, sys, os
SRC, MOB, OUT = sys.argv[-3:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=f'{SRC}/ubc/Base Characters/Godot - UE/Superhero_Male_FullBody.gltf')
arm=[o for o in bpy.data.objects if o.type=='ARMATURE'][0]
for o in [o for o in bpy.data.objects if o.type=='MESH']:
    bpy.data.objects.remove(o, do_unlink=True)
ub=set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=f'{SRC}/ual/Unreal Engine/AL_Standard.fbx')
for o in list(set(bpy.data.objects)-ub): bpy.data.objects.remove(o)
want={'Idle_Loop':'Idle','Walk_Loop':'Walk','Jog_Fwd_Loop':'Run','Sprint_Loop':'Sprint'}
arm.animation_data_create()
for a in bpy.data.actions:
    sn=a.name.split('|')[-1]
    if sn in want:
        t=arm.animation_data.nla_tracks.new(); t.name=want[sn]; t.strips.new(want[sn], int(a.frame_range[0]), a)
arm.animation_data.action=None
bpy.ops.import_scene.fbx(filepath=f'{MOB}/Zombie.fbx')
z=bpy.data.objects['NormalDemon']
bpy.context.view_layer.update()
# применить трансформации зомби
bpy.ops.object.select_all(action='DESELECT'); z.select_set(True); bpy.context.view_layer.objects.active=z
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
S=1.08
uh=arm.data.bones['upperarm_l'].head_local
PX,PZ=abs(uh.x),uh.z
print('arm pivot',PX,PZ)
for v in z.data.vertices:
    x,y,zz=v.co
    x,y,zz = x*S, y*S, zz*S            # масштаб (лицом в -Y, как скелет)
    ax=abs(x)
    if zz>0.95 and ax>0.14:
        t=min(1,max(0,(ax-0.16)/0.10)); t=t*t*(3-2*t)
        sgn=1 if x>0 else -1
        px,pz=sgn*PX,PZ
        ang=math.radians(29)*t*sgn        # поднять руку в T-позу
        dx,dz=x-px,zz-pz
        c,s=math.cos(ang),math.sin(ang)
        x,zz=px+dx*c-dz*s, pz+dx*s+dz*c
    v.co=(x,y,zz)
z.data.update()
# материал: текстура зомби (в FBX материал пришёл прозрачным и без картинки)
import os
mat=bpy.data.materials.new('ZombieMat'); mat.use_nodes=True
nt=mat.node_tree; bsdf=nt.nodes['Principled BSDF']
img=bpy.data.images.load(os.path.abspath(f'{MOB}/Zombie.png'))
tex=nt.nodes.new('ShaderNodeTexImage'); tex.image=img
nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
bsdf.inputs['Roughness'].default_value=0.85
bsdf.inputs['Alpha'].default_value=1.0
z.data.materials.clear(); z.data.materials.append(mat)
print('uv layers', [u.name for u in z.data.uv_layers])
# привязка к скелету с автоматическими весами
bpy.ops.object.select_all(action='DESELECT')
z.select_set(True); arm.select_set(True); bpy.context.view_layer.objects.active=arm
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
print('parent inv', z.matrix_parent_inverse, 'arm world', arm.matrix_world, 'z basis', z.matrix_basis)
# «запечь» обратную матрицу родителя в вершины: меш в координатах скелета
z.data.transform(z.matrix_basis @ z.matrix_parent_inverse)
z.matrix_parent_inverse.identity(); z.matrix_basis.identity()
vg=[g.name for g in z.vertex_groups]; print('groups',len(vg))
empty=sum(1 for v in z.data.vertices if len(v.groups)==0); print('unweighted verts',empty)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_animation_mode='NLA_TRACKS', export_image_format='JPEG')
print('exported')

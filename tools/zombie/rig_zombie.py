import bpy, numpy as np, math, mathutils
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath='/home/user/survival-game/assets/character/Soldier.glb')
sold=list(bpy.context.scene.objects)
arm=[o for o in sold if o.type=='ARMATURE'][0]
bpy.ops.import_scene.fbx(filepath='mob/Zombie.fbx')
z=bpy.data.objects['NormalDemon']
bpy.context.view_layer.update()
# применить трансформации зомби
bpy.ops.object.select_all(action='DESELECT'); z.select_set(True); bpy.context.view_layer.objects.active=z
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
S=1.08
for v in z.data.vertices:
    x,y,zz=v.co
    x,y,zz = -x*S, -y*S, zz*S          # поворот на 180° и масштаб
    ax=abs(x)
    if zz>0.95 and ax>0.14:
        t=min(1,max(0,(ax-0.16)/0.10)); t=t*t*(3-2*t)
        sgn=1 if x>0 else -1
        px,pz=sgn*0.22,1.46
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
img=bpy.data.images.load(os.path.abspath('mob/Zombie.png'))
tex=nt.nodes.new('ShaderNodeTexImage'); tex.image=img
nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
bsdf.inputs['Roughness'].default_value=0.85
bsdf.inputs['Alpha'].default_value=1.0
z.data.materials.clear(); z.data.materials.append(mat)
print('uv layers', [u.name for u in z.data.uv_layers])
# привязка к скелету с автоматическими весами
for o in sold:
    if o.type=='MESH' or (o.type=='EMPTY'): pass
bpy.ops.object.select_all(action='DESELECT')
z.select_set(True); arm.select_set(True); bpy.context.view_layer.objects.active=arm
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
print('parent inv', z.matrix_parent_inverse, 'arm world', arm.matrix_world, 'z basis', z.matrix_basis)
# «запечь» обратную матрицу родителя в вершины: меш в координатах скелета
z.data.transform(z.matrix_basis @ z.matrix_parent_inverse)
z.matrix_parent_inverse.identity(); z.matrix_basis.identity()
# убрать меши солдата
for n in ['vanguard_Mesh','vanguard_visor','Icosphere']:
    o=bpy.data.objects.get(n)
    if o: bpy.data.objects.remove(o, do_unlink=True)
vg=[g.name for g in z.vertex_groups]; print('groups',len(vg))
empty=sum(1 for v in z.data.vertices if len(v.groups)==0); print('unweighted verts',empty)
bpy.ops.export_scene.gltf(filepath='/tmp/claude-0/-home-user-pionex-live-mcp-v2/4260c316-1475-59b6-bfd2-181a286fa1f0/scratchpad/zombie/Zombie.glb', export_format='GLB', export_animations=True, export_animation_mode='ACTIONS')
print('exported')

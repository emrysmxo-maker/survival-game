# Собирает бойца из CC0-пакетов Quaternius (Universal Base Characters + Universal Animation Library):
# тело Superhero_Male + гражданская одежда (куртка, джинсы, кроссовки — по зонам весов) + причёска и борода + клипы Idle/Walk/Run/Sprint/Swim_*.
# Запуск: /tmp/claude-0/blender/v/bin/python -I build_soldier.py <папка_с_пакетами> <выход.glb>
import bpy, sys, math, bmesh
from mathutils import Vector
SRC, OUT = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=f'{SRC}/ubc/Base Characters/Godot - UE/Superhero_Male_FullBody.gltf')
ca = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
body = [o for o in bpy.data.objects if o.type == 'MESH' and len(o.data.vertices) > 5000][0]
mats_old = list(body.data.materials)
before = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=f'{SRC}/ual/Unreal Engine/AL_Standard.fbx')
for o in list(set(bpy.data.objects) - before):
    bpy.data.objects.remove(o)

def mk(name, col, rough=0.9):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = col
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = 0.0
    return m
M = {'jacket': mk('Jacket', (0.20, 0.15, 0.10, 1)), 'pants': mk('Jeans', (0.07, 0.10, 0.17, 1)),
     'boots': mk('Sneakers', (0.32, 0.31, 0.29, 1)), 'shirt': mk('Shirt', (0.30, 0.31, 0.28, 1))}
base_n = len(body.data.materials)
for k in M:
    body.data.materials.append(M[k])
idx = {k: base_n + i for i, k in enumerate(M)}
vg = {g.index: g.name for g in body.vertex_groups}

def zone(gname):
    g = gname.lower()
    if any(s in g for s in ('index_', 'middle_', 'ring_', 'pinky_', 'thumb_', 'hand')):
        return None                     # руки голые
    if any(s in g for s in ('foot', 'ball')):
        return 'boots'
    if any(s in g for s in ('thigh', 'calf', 'pelvis')):
        return 'pants'
    if any(s in g for s in ('spine', 'clavicle', 'upperarm', 'lowerarm')):
        return 'jacket'
    if 'neck' in g:
        return None
    return None
me = body.data
def poly_group(p):
    w = {}
    for vi in p.vertices:
        for ge in me.vertices[vi].groups:
            w[vg[ge.group]] = w.get(vg[ge.group], 0) + ge.weight
    return max(w, key=w.get) if w else ''
pz = []
for p in me.polygons:
    gname = poly_group(p)
    z = zone(gname)
    pz.append((z, gname))
    if z:
        p.material_index = idx[z if z != 'jacket' else 'shirt']

# одежда — раздутые копии зон тела (не облегает как трико): куртка поверх футболки, джинсы
def shell(name, pred, off, mat):
    o = body.copy(); o.data = body.data.copy(); o.name = name
    bpy.context.collection.objects.link(o)
    bm = bmesh.new(); bm.from_mesh(o.data); bm.faces.ensure_lookup_table()
    kill = [f for f in bm.faces if not pred(pz[f.index])]
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bm.verts.ensure_lookup_table(); bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * off
    bm.to_mesh(o.data); bm.free()
    o.data.materials.clear(); o.data.materials.append(mat)
    for p in o.data.polygons:
        p.material_index = 0
    return o
shell('Jacket', lambda t: t[0] == 'jacket' and not t[1].startswith('spine_03_front'), 0.016, M['jacket'])
shell('Jeans', lambda t: t[0] == 'pants', 0.010, M['pants'])
shell('Sneakers', lambda t: t[0] == 'boots', 0.008, M['boots'])

# причёска и борода (CC0, привязаны к кости Head) — переносим на наш скелет
HD = f'{SRC}/ubc/Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)'
for hn in ('Hair_SimpleParted', 'Hair_Beard'):
    before_h = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f'{HD}/{hn}.gltf')
    new = list(set(bpy.data.objects) - before_h)
    for o in new:
        if o.type == 'MESH':
            mw = o.matrix_world.copy()
            o.parent = ca; o.matrix_world = mw
            for md in o.modifiers:
                if md.type == 'ARMATURE':
                    md.object = ca
            if not any(md.type == 'ARMATURE' for md in o.modifiers):
                md = o.modifiers.new('Armature', 'ARMATURE'); md.object = ca
    for o in new:
        if o.type != 'MESH':
            bpy.data.objects.remove(o)

# клипы
want = {'Idle_Loop': 'Idle', 'Walk_Loop': 'Walk', 'Jog_Fwd_Loop': 'Run', 'Sprint_Loop': 'Sprint', 'Walk_Formal_Loop': 'WalkF',
        'Swim_Fwd_Loop': 'Swim_Fwd', 'Swim_Idle_Loop': 'Swim_Idle'}
ca.animation_data_create()
for a in bpy.data.actions:
    short = a.name.split('|')[-1]
    if short in want:
        t = ca.animation_data.nla_tracks.new(); t.name = want[short]
        t.strips.new(want[short], int(a.frame_range[0]), a)
ca.animation_data.action = None
print('POSE', ca.data.bones['pelvis'].head_local)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_animation_mode='NLA_TRACKS',
                          export_apply=False, export_image_format='JPEG', export_jpeg_quality=80)

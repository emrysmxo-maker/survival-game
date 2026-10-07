# Собирает бойца из CC0-пакетов Quaternius (Universal Base Characters + Universal Animation Library):
# тело Superhero_Male + одежда/жилет/шлем (по зонам весов) + клипы Idle/Walk/Run/Sprint/Swim_*.
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
M = {'jacket': mk('Jacket', (0.16, 0.20, 0.10, 1)), 'pants': mk('Pants', (0.14, 0.16, 0.09, 1)),
     'boots': mk('Boots', (0.05, 0.04, 0.03, 1)), 'gloves': mk('Gloves', (0.06, 0.06, 0.05, 1)),
     'vest': mk('Vest', (0.11, 0.12, 0.08, 1)), 'helmet': mk('Helmet', (0.13, 0.17, 0.09, 1), 0.7)}
base_n = len(body.data.materials)
for k in M:
    body.data.materials.append(M[k])
idx = {k: base_n + i for i, k in enumerate(M)}
vg = {g.index: g.name for g in body.vertex_groups}

def zone(gname):
    g = gname.lower()
    if any(s in g for s in ('index_', 'middle_', 'ring_', 'pinky_', 'thumb_', 'hand')):
        return 'gloves'
    if any(s in g for s in ('foot', 'ball')):
        return 'boots'
    if any(s in g for s in ('thigh', 'calf', 'pelvis')):
        return 'pants'
    if any(s in g for s in ('spine', 'clavicle', 'upperarm', 'lowerarm')):
        return 'jacket'
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
        p.material_index = idx[z]

# жилет и «рукава-нашивки»: раздутая копия торса
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
shell('Vest', lambda t: t[1].startswith('spine_0') and t[0] == 'jacket', 0.018, M['vest'])
shell('Hips', lambda t: t[1] == 'pelvis', 0.012, M['pants'])

# шлем: сплюснутая сфера, вес 100% на кость Head
hb = ca.data.bones['Head']
hc = ca.matrix_world @ ((hb.head_local + hb.tail_local) / 2)
bpy.ops.mesh.primitive_uv_sphere_add(radius=1, segments=20, ring_count=12, location=(hc.x, hc.y + 0.01, hc.z + 0.055))
h = bpy.context.object; h.name = 'Helmet'
h.scale = (0.112, 0.125, 0.105)
bpy.ops.object.transform_apply(scale=True)
bm = bmesh.new(); bm.from_mesh(h.data)
for v in list(bm.verts):
    if v.co.z < hc.z - 0.02:      # нижняя часть срезана — лицо открыто
        v.co.z = hc.z - 0.02 + (v.co.z - (hc.z - 0.02)) * 0.0
bm.to_mesh(h.data); bm.free()
h.data.materials.append(M['helmet'])
g = h.vertex_groups.new(name='Head')
g.add(list(range(len(h.data.vertices))), 1.0, 'REPLACE')
h.parent = body.parent
mod = h.modifiers.new('Armature', 'ARMATURE'); mod.object = ca
for o in bpy.data.objects:
    if o.type == 'MESH' and o.parent != ca and o.parent is not None and o.parent.type == 'ARMATURE':
        pass

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
print('POSE', ca.data.bones['pelvis'].head_local, 'HELM', hc)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_animation_mode='NLA_TRACKS',
                          export_apply=False, export_image_format='JPEG', export_jpeg_quality=80)

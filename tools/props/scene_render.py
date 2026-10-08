# Вид сверху на локацию из Blender: props.glb + JSON расстановки (из mapcheck.gd) + деревья-болванки. Проверка расстановки в 3D.
# python -I scene_render.py <props.glb> <scene.json> <out.png> [угол_камеры_градусов=50] [вид=iso|top]
import sys, os, json, math
import bpy
from mathutils import Matrix, Vector
glb, js, outpng = sys.argv[-3:] if len(sys.argv) >= 4 and not sys.argv[-1].replace('.', '').isdigit() else sys.argv[-3:]
args = [a for a in sys.argv[1:]]
glb, js, outpng = args[0], args[1], args[2]
elev = float(args[3]) if len(args) > 3 else 50.0
d = json.load(open(js))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
lib = {o.name.split('.')[0]: o for o in bpy.data.objects if o.type == 'MESH'}
for o in lib.values(): o.hide_render = True; o.hide_viewport = True
Cg = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
cx, cy = d['cx'] * 0.837, d['cy'] * 0.837
h0 = d['h0']
n = 0
for it in d['props']:
    src = lib.get(it['m'])
    if src is None: continue
    b = it['b']
    Bg = Matrix(((b[0], b[3], b[6]), (b[1], b[4], b[7]), (b[2], b[5], b[8])))   # столбцы — оси Godot
    Bb = Cg @ Bg @ Cg.inverted()
    p = it['p']
    pos = Vector((p[0] - cx, -(p[2] - cy), p[1] - h0))
    M = Matrix.Translation(pos) @ Bb.to_4x4()
    o = bpy.data.objects.new(it['m'], src.data)
    o.matrix_world = M
    bpy.context.scene.collection.objects.link(o)
    n += 1
# деревья: ствол + два конуса
tm = bpy.data.materials.new('trunk'); tm.use_nodes = True; tm.node_tree.nodes['Principled BSDF'].inputs[0].default_value = (0.08, 0.05, 0.03, 1)
lm = bpy.data.materials.new('leaf'); lm.use_nodes = True; lm.node_tree.nodes['Principled BSDF'].inputs[0].default_value = (0.02, 0.07, 0.025, 1)
for t in d['trees']:
    x, y, z, sc = t[0] - cx, -(t[2] - cy), t[1] - h0, t[3]
    for (r, hh, zz) in ((1.0, 2.4, 1.1), (0.7, 2.0, 2.6)):
        bpy.ops.mesh.primitive_cone_add(vertices=7, radius1=r * sc, radius2=0.05, depth=hh * sc, location=(x, y, z + zz * sc))
        bpy.context.object.data.materials.append(lm)
sc = bpy.context.scene
sc.render.engine = 'CYCLES'; sc.cycles.samples = 14; sc.cycles.device = 'CPU'
sc.render.resolution_x = 1400; sc.render.resolution_y = 900
w = bpy.data.worlds.new('w'); w.use_nodes = True; w.node_tree.nodes['Background'].inputs[0].default_value = (0.55, 0.65, 0.78, 1); sc.world = w
sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); sun.data.energy = 3.5; sun.rotation_euler = (math.radians(50), 0, math.radians(-35)); sc.collection.objects.link(sun)
gm = bpy.data.materials.new('g'); gm.use_nodes = True; gm.node_tree.nodes['Principled BSDF'].inputs[0].default_value = (0.09, 0.14, 0.04, 1)
R = d['r'] * 0.837 + 8
bpy.ops.mesh.primitive_plane_add(size=R * 5, location=(0, 0, -0.1)); bpy.context.object.data.materials.append(gm)
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('c')); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = R * 2.2
e = math.radians(elev)
cam.location = Vector((0, -math.cos(e) * 120, math.sin(e) * 120)); cam.rotation_euler = (math.radians(90) - e, 0, 0)
sc.render.filepath = outpng
bpy.ops.render.render(write_still=True)
print('предметов', n, 'деревьев', len(d['trees']))

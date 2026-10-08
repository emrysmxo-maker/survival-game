# Проверка расстановки на локации: читает SETS из props.gd, ставит модели в Blender на плоскую землю, ищет пересечения
# (по габаритным прямоугольникам) и рисует вид сверху. python -I layout_check.py <ключ локации> <выход.png>
import sys, os, re, math, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector, Euler
key, outpng = sys.argv[-2:]
src = open(os.path.join(os.path.dirname(__file__), '../../godot/scripts/props.gd'), encoding='utf-8').read()
sets = re.search(r'const SETS := \{(.*?)\n\}\n', src, re.S).group(1)
blk = re.search(r'"%s": \[(.*?)\n\t\],' % key, sets, re.S).group(1)
items = [(m[0], float(m[1]), float(m[2]), float(m[3])) for m in re.findall(r'\["(\w+)", (-?[\d.]+), (-?[\d.]+), (-?[\d.]+)\]', blk)]
S, T = 0.8, 0.837
bpy.ops.wm.read_factory_settings(use_empty=True)
ASSETS = os.path.join(os.path.dirname(__file__), '../../godot/assets/props')
boxes = []
for i, (model, dx, dy, yaw) in enumerate(items):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f'{ASSETS}/{model}.glb')
    new = [o for o in bpy.data.objects if o not in before]
    root = [o for o in new if o.parent is None][0]
    # glTF → Blender: Godot (x, y, z) = Blender (x, -z_b, y_b); перенос: tile (dx,dy) → Godot (dx*T, ., dy*T) → Blender (dx*T, -dy*T)
    th = math.radians(yaw)
    root.scale = (S, S, S)
    root.rotation_euler = Euler((0, 0, th), 'XYZ')
    root.location = (dx * T, -dy * T, 0)
    bpy.context.view_layer.update()
    mesh = [o for o in new if o.type == 'MESH'][0]
    ws = [mesh.matrix_world @ Vector(c) for c in mesh.bound_box]
    xs = [w.x for w in ws]; ys = [w.y for w in ws]
    boxes.append((model, min(xs), max(xs), min(ys), max(ys)))
bad = []
for i in range(len(boxes)):
    for j in range(i + 1, len(boxes)):
        a, b = boxes[i], boxes[j]
        if a[1] < b[2] and b[1] < a[2] and a[3] < b[4] and b[3] < a[4]:
            bad.append((i, a[0], j, b[0]))
for b in boxes: print('BOX', b[0], [round(v / (0.837)) for v in b[1:]])
print('пересечения:', bad if bad else 'нет')
print('самый дальний от центра (тайлы):', max(math.hypot(it[1], it[2]) for it in items))
sc = bpy.context.scene
sc.render.engine = 'CYCLES'; sc.cycles.samples = 16; sc.cycles.device = 'CPU'
sc.render.resolution_x = 900; sc.render.resolution_y = 700
w = bpy.data.worlds.new('w'); w.use_nodes = True; w.node_tree.nodes['Background'].inputs[0].default_value = (0.6, 0.7, 0.8, 1); sc.world = w
sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); sun.data.energy = 4; sun.rotation_euler = (math.radians(50), 0, math.radians(35)); sc.collection.objects.link(sun)
gm = bpy.data.materials.new('g'); gm.use_nodes = True; gm.node_tree.nodes['Principled BSDF'].inputs[0].default_value = (0.3, 0.33, 0.18, 1)
bpy.ops.mesh.primitive_plane_add(size=120); g = bpy.context.object; g.data.materials.append(gm)
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('c')); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = 46
cam.location = (0, -30, 38); cam.rotation_euler = (math.radians(52), 0, 0)
sc.render.filepath = outpng
bpy.ops.render.render(write_still=True)

# Простой «сломанный автомобиль» (Blender как модуль): python -I car_wreck.py <выход.glb>
import bpy, sys, math
OUT = sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
def mat(name, col, rough=0.8, met=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = col; b.inputs['Roughness'].default_value = rough; b.inputs['Metallic'].default_value = met
    return m
PAINT = mat('Paint', (0.42, 0.10, 0.07, 1), 0.55, 0.3)
RUST = mat('Rust', (0.28, 0.13, 0.06, 1), 0.95, 0.2)
GLASS = mat('Glass', (0.03, 0.04, 0.05, 1), 0.2)
TIRE = mat('Tire', (0.02, 0.02, 0.02, 1), 0.95)
METAL = mat('Metal', (0.18, 0.18, 0.18, 1), 0.6, 0.6)
parts = []
def box(name, size, loc, m, rot=(0, 0, 0), bevel=0.04):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object; o.name = name; o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        bv = o.modifiers.new('b', 'BEVEL'); bv.width = bevel; bv.segments = 2
        bpy.ops.object.modifier_apply(modifier='b')
    o.data.materials.append(m); parts.append(o); return o
def cyl(name, r, d, loc, m, rot):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d, location=loc, rotation=rot, vertices=20)
    o = bpy.context.object; o.name = name; o.data.materials.append(m); parts.append(o); return o
# корпус (вдоль Y; перед = +Y)
box('Body', (1.8, 4.2, 0.65), (0, 0, 0.62), PAINT, bevel=0.08)
box('Cabin', (1.55, 1.9, 0.62), (0, -0.35, 1.2), PAINT, bevel=0.1)
box('Roof', (1.5, 1.8, 0.05), (0, -0.35, 1.53), RUST, bevel=0.02)
box('Windows', (1.58, 1.75, 0.38), (0, -0.35, 1.22), GLASS, bevel=0.03)
# выбитые стёкла: рваные «зубья» по краю лобового
for i, x in enumerate((-0.55, -0.15, 0.3, 0.62)):
    box(f'Shard{i}', (0.08, 0.04, 0.25 + 0.1 * (i % 2)), (x, 0.58, 1.18), GLASS, rot=(0.4, 0, 0.3 * (i - 1.5)), bevel=0)
# капот открыт (шарнир у лобового)
box('Hood', (1.7, 1.2, 0.06), (0.0, 1.55, 1.38), RUST, rot=(-1.15, 0, 0.04), bevel=0.02)
box('Engine', (1.1, 0.9, 0.4), (0, 1.35, 0.92), METAL, bevel=0.06)
# крылья/пороги ржавые
for sx in (-1, 1):
    box(f'Fender{sx}', (0.12, 1.3, 0.5), (sx * 0.92, 1.3, 0.62), RUST, bevel=0.03)
    box(f'Sill{sx}', (0.1, 2.0, 0.22), (sx * 0.92, -0.4, 0.4), RUST, bevel=0.03)
# дверь приоткрыта (левая)
box('Door', (0.07, 1.2, 0.7), (-1.28, -0.2, 0.95), PAINT, rot=(0, 0, 0.62), bevel=0.03)
# бамперы: передний сорван и висит
box('BumperB', (1.9, 0.18, 0.2), (0, -2.15, 0.42), METAL, bevel=0.04)
box('BumperF', (1.9, 0.18, 0.2), (0.35, 2.35, 0.2), METAL, rot=(0.0, 0.2, 0.25), bevel=0.04)
# фары разбиты, решётка
for sx in (-0.6, 0.6):
    box(f'Light{sx}', (0.3, 0.1, 0.18), (sx, 2.12, 0.72), GLASS, bevel=0.03)
# колёса: три на месте, четвёртого нет — голая ступица
wheels = [(-0.95, 1.35), (0.95, 1.35), (-0.95, -1.35), (0.95, -1.35)]
for i, (x, y) in enumerate(wheels):
    if i == 1:
        cyl('Hub', 0.14, 0.3, (x, y, 0.28), METAL, (0, math.pi / 2, 0))
        continue
    r = 0.42 if i != 2 else 0.34             # заднее левое спущено
    cyl(f'Tire{i}', r, 0.3, (x, y, r), TIRE, (0, math.pi / 2, 0))
    cyl(f'Rim{i}', r * 0.55, 0.32, (x, y, r), METAL, (0, math.pi / 2, 0))
# соединить всё, наклонить машину (нет колеса — просела на правый перед), поставить на землю
bpy.ops.object.select_all(action='DESELECT')
for o in parts: o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
car = bpy.context.object; car.name = 'CarWreck'
bpy.ops.object.shade_smooth()
car.rotation_euler = (math.radians(-2), math.radians(-5), math.radians(0))
bpy.ops.object.transform_apply(rotation=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB')

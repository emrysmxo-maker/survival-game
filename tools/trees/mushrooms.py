# Грибы для подлеска (Blender): мухомор, белый, подберёзовик, опята на пне-обломке. Цвет — цветом вершин, без текстур.
# /tmp/claude-0/blender/v/bin/python -I tools/trees/mushrooms.py <out_dir>  → mushrooms_wood.glb (узлы mush_a..mush_d)
import bpy, bmesh, math, random, sys, os
from mathutils import Vector, Matrix
OUT = sys.argv[-1]
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)

def srgb(c):
	return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)

def mushroom(bm, cl, pos, h, r, cap_col, stem_col, dots=False, rnd=None, tilt=0.0):
	"""Ножка (цилиндр-конус) и шляпка (сплюснутая полусфера)."""
	M = Matrix.Translation(pos) @ Matrix.Rotation(tilt, 4, "X")
	st = bmesh.ops.create_cone(bm, cap_ends=False, segments=8, radius1=r * 0.32, radius2=r * 0.24, depth=h, matrix=M @ Matrix.Translation((0, 0, h / 2)))
	for f in {f for v in st["verts"] for f in v.link_faces}:
		for l in f.loops:
			l[cl] = srgb(stem_col) + (1.0,)
	cap = bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=6, radius=r, matrix=M @ Matrix.Translation((0, 0, h)) @ Matrix.Diagonal((1, 1, 0.55, 1)))
	vs = cap["verts"]
	for v in vs:
		lz = (M.inverted() @ v.co).z - h
		if lz < -0.1 * r:                                            # низ шляпки — плоский (пластинки)
			p = M.inverted() @ v.co
			p.z = h - 0.1 * r
			v.co = M @ p
	for f in {f for v in vs for f in v.link_faces}:
		under = f.normal.dot(M.to_3x3() @ Vector((0, 0, 1))) < -0.3
		for l in f.loops:
			c = stem_col if under else cap_col
			if dots and not under and rnd.random() < 0.18:
				c = (0.95, 0.93, 0.88)                                 # белые хлопья мухомора
			l[cl] = srgb(c) + (1.0,)

def build(name, items, seed):
	rnd = random.Random(seed)
	bm = bmesh.new()
	cl = bm.loops.layers.color.new("Color")
	for it in items:
		mushroom(bm, cl, Vector(it[0]), it[1], it[2], it[3], it[4], it[5] if len(it) > 5 else False, rnd, it[6] if len(it) > 6 else rnd.uniform(-0.15, 0.15))
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me); bm.free()
	m = bpy.data.materials.new("mushroom")
	m.use_nodes = True
	b = m.node_tree.nodes["Principled BSDF"]
	b.inputs["Roughness"].default_value = 0.65
	vc = m.node_tree.nodes.new("ShaderNodeVertexColor"); vc.layer_name = "Color"
	m.node_tree.links.new(vc.outputs["Color"], b.inputs["Base Color"])
	me.materials.append(m)
	for p in me.polygons:
		p.use_smooth = True
	ob = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(ob)
	me.color_attributes.active_color = me.color_attributes["Color"]
	return ob

RED, WHITE_STEM = (0.78, 0.10, 0.06), (0.92, 0.90, 0.84)
BROWN, BEIGE = (0.42, 0.26, 0.14), (0.86, 0.80, 0.68)
objs = [
	build("mush_a", [((0, 0, 0), 0.16, 0.09, RED, WHITE_STEM, True), ((0.12, 0.05, 0), 0.10, 0.06, RED, WHITE_STEM, True)], 1),                   # мухоморы
	build("mush_b", [((0, 0, 0), 0.09, 0.08, BROWN, BEIGE), ((0.09, -0.04, 0), 0.06, 0.05, BROWN, BEIGE)], 2),                                       # белые
	build("mush_c", [((0, 0, 0), 0.14, 0.06, (0.55, 0.40, 0.25), (0.85, 0.85, 0.82)), ((-0.07, 0.06, 0), 0.10, 0.045, (0.50, 0.36, 0.22), (0.85, 0.85, 0.82))], 3),   # подберёзовики
	build("mush_d", [((math.cos(a) * 0.08, math.sin(a) * 0.08, 0), 0.07, 0.03, (0.70, 0.52, 0.28), (0.78, 0.68, 0.48)) for a in [k * 0.9 for k in range(7)]], 4),     # опята кучкой
]
bpy.ops.object.select_all(action="DESELECT")
for o in objs:
	o.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "mushrooms_wood.glb"), export_format="GLB", use_selection=True, export_apply=True,
	export_vertex_color="NAME", export_vertex_color_name="Color", export_all_vertex_colors=False)
for o in objs:
	print("MUSH", o.name, len(o.data.polygons), "граней")

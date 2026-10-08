# Показ игровых деревьев: загружает готовые <порода>_wood.glb/_leaf.glb (проверка экспорта) и рендерит
# ряд вариантов: вид с земли и игровой камерой (46.8°, орто).
# /tmp/claude-0/blender/v/bin/python -I tools/trees/show.py <game_dir> <out.png> <dl_dir> вариант1,вариант2,...  [human|game]
import bpy, math, sys, os
from mathutils import Vector

GAME, OUTP, DL, NAMES = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4].split(",")
VIEW = sys.argv[5] if len(sys.argv) > 5 else "human"
SAMPLES = int(os.environ.get("SAMPLES", "32"))
PCT = int(os.environ.get("PCT", "100"))

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
loaded = {}
for nm in NAMES:
	sp = nm.split("_")[0]
	for part in ("wood", "leaf"):
		f = os.path.join(GAME, "%s_%s.glb" % (sp, part))
		if (sp, part) in loaded or not os.path.exists(f):
			continue
		before = set(bpy.data.objects)
		bpy.ops.import_scene.gltf(filepath=f)
		loaded[(sp, part)] = [o for o in bpy.data.objects if o not in before]
x = 0.0
row = []
for nm in NAMES:
	sp = nm.split("_")[0]
	objs = [o for k in (("wood"), ("leaf")) for o in loaded.get((sp, k), []) if o.name.split(".")[0] == nm and o.type == "MESH"]
	w = 0.0
	for o in objs:
		bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
		w = max(w, max(v.x for v in bb) - min(v.x for v in bb))
	x += w / 2 + 1.0
	for o in objs:
		o.location.x += x
		o["keep"] = 1
	row.append((nm, x, max((o.dimensions.z for o in objs), default=1)))
	x += w / 2 + 1.0
for o in list(bpy.data.objects):
	if o.type == "MESH" and "keep" not in o:
		bpy.data.objects.remove(o)
	elif o.type != "MESH":
		bpy.data.objects.remove(o)
# свет и земля
sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = SAMPLES; sc.cycles.use_denoising = True
sc.cycles.transparent_max_bounces = 32
sc.view_settings.view_transform = "AgX"; sc.view_settings.look = "AgX - Medium High Contrast"
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
N, L = w.node_tree.nodes, w.node_tree.links
N.clear()
bg = N.new("ShaderNodeBackground"); bg.inputs["Strength"].default_value = 0.7
ev = N.new("ShaderNodeTexEnvironment"); ev.image = bpy.data.images.load(os.path.join(DL, "kloofendal_48d_partly_cloudy_puresky_2k.hdr"))
L.new(ev.outputs[0], bg.inputs[0])
o = N.new("ShaderNodeOutputWorld"); L.new(bg.outputs[0], o.inputs[0])
bpy.ops.mesh.primitive_plane_add(size=600, location=(x / 2, 0, 0))
g = bpy.context.object
gm = bpy.data.materials.new("ground"); gm.use_nodes = True
NN, LL = gm.node_tree.nodes, gm.node_tree.links
bs = NN["Principled BSDF"]
tc = NN.new("ShaderNodeTexCoord"); mp = NN.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (150, 150, 1)
LL.new(tc.outputs["UV"], mp.inputs[0])
t = NN.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(os.path.join(DL, "aerial_grass_rock_diff_2k.jpg"))
LL.new(mp.outputs[0], t.inputs[0]); LL.new(t.outputs[0], bs.inputs["Base Color"])
bs.inputs["Roughness"].default_value = 0.95
g.data.materials.append(gm)
sun = bpy.data.lights.new("sun", "SUN"); sun.energy = 2.4; sun.angle = math.radians(1.2)
so = bpy.data.objects.new("sun", sun); sc.collection.objects.link(so)
so.rotation_euler = (math.radians(50), 0, math.radians(200))
# человек 1.8 м для масштаба
bpy.ops.mesh.primitive_cylinder_add(radius=0.2, depth=1.55, location=(row[0][1] + 2.0, -2.0, 0.775))
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(row[0][1] + 2.0, -2.0, 1.68))
cd = bpy.data.cameras.new("cam"); cd.clip_end = 1000
co = bpy.data.objects.new("cam", cd); sc.collection.objects.link(co)
H = max(r[2] for r in row)
cx = x / 2
if VIEW == "human":
	cd.lens = 28
	dist = max(x * 0.75, H * 1.4)
	co.location = (cx, -dist, 1.7)
	look = Vector((cx, 0, H * 0.45))
	sc.render.resolution_x, sc.render.resolution_y = 1800, 1000
else:
	cd.type = "ORTHO"
	el = math.radians(46.8)
	d = Vector((0, -math.cos(el), math.sin(el)))
	look = Vector((cx, 0, H * 0.3))
	co.location = look + d * 200
	cd.ortho_scale = max(x * 1.05, H * 1.4)
	sc.render.resolution_x, sc.render.resolution_y = 1800, 1000
co.rotation_euler = (look - co.location).to_track_quat("-Z", "Y").to_euler()
sc.camera = co
sc.render.resolution_percentage = PCT
sc.render.filepath = OUTP
bpy.ops.render.render(write_still=True)
print("SHOW", OUTP, [r[0] for r in row], flush=True)

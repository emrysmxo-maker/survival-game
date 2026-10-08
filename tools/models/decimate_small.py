# Упростить мелкие растения (трава, цветы, крапива, папоротник, ветки): Poly Haven даёт 1,5–5 тыс. треугольников на кустик,
# в поле их сотни в кадре (замер сборки 84: ~950 тыс. треуг. в колхозе). Decimate (collapse) до TARGET на узел, имена узлов те же.
# /tmp/claude-0/blender/v/bin/python -I tools/models/decimate_small.py <in.glb> <out.glb> <target_tris>
import bpy, sys
src, dst, target = sys.argv[-3], sys.argv[-2], int(sys.argv[-1])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for o in list(bpy.data.objects):
	if o.type != "MESH":
		continue
	tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
	if tris <= target:
		continue
	md = o.modifiers.new("dec", "DECIMATE")
	md.ratio = target / tris
	md.use_collapse_triangulate = True
	bpy.context.view_layer.objects.active = o
	bpy.ops.object.modifier_apply(modifier=md.name)
	print("DEC", o.name, tris, "->", sum(len(p.vertices) - 2 for p in o.data.polygons))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", use_selection=True, export_image_format="AUTO", export_jpeg_quality=85, export_apply=True,
	export_vertex_color="NONE", export_tangents=False)

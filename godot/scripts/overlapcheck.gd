extends SceneTree
# Проверка наложений построек: следы (по AABB моделей, повёрнутые) всех зданий после расстановки; пары, что пересекаются.
# godot --headless --path godot -s res://scripts/overlapcheck.gd   (в лог: OVL пары, OVL итого)
const SKIP := ["radio_mast", "watch_tower", "mil_tower", "fence", "road_dash", "bridge", "concrete_pad", "rail_", "wire", "sign", "lamp", "pole", "graffiti", "_roof", "field", "garden", "bed", "dump_pile", "sawdust", "barbed", "jersey", "block_fbs"]
func _init() -> void:
	WorldGen.init()
	var pr = load("res://scripts/props.gd").new()
	pr._ready()
	var rects: Array = []
	for key in pr._batch:
		var b: Dictionary = pr._batch[key]
		var nm: String = b.model
		var skip := false
		for s in SKIP:
			if nm.contains(s): skip = true
		if skip: continue
		var ab: AABB = pr._meshes[nm].get_aabb()
		if pr._meshes.has(nm + "_roof"): ab = ab.merge(pr._meshes[nm + "_roof"].get_aabb())
		if ab.size.y < 1.6 or ab.size.x * ab.size.z < 6.0:
			continue
		for xf: Transform3D in b.xf:
			var c := xf * ab.get_center()
			var ax := xf.basis.x
			var th := atan2(-ax.z, ax.x)
			var sx := xf.basis.x.length()
			rects.append([Vector2(c.x, c.z) / WorldGen.T, th, ab.size.x * 0.5 * sx / WorldGen.T - 0.15, ab.size.z * 0.5 * sx / WorldGen.T - 0.15, nm])
	var n := 0
	var by := {}
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var a: Array = rects[i]
			var b: Array = rects[j]
			if a[0].distance_to(b[0]) > a[2] + a[3] + b[2] + b[3]:
				continue
			if pr._rect_overlap(a, b):
				n += 1
				var k := "%s + %s" % [a[4], b[4]] if a[4] < b[4] else "%s + %s" % [b[4], a[4]]
				by[k] = by.get(k, 0) + 1
				if n <= 40:
					print("OVL %s @%d:%d  ×  %s @%d:%d" % [a[4], roundi(a[0].x), roundi(a[0].y), b[4], roundi(b[0].x), roundi(b[0].y)])
	print("OVL итого пар: ", n, " зданий: ", rects.size())
	quit()

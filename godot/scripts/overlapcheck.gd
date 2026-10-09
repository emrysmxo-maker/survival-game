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
	# здания на дороге: точки следа ближе 2 тайлов к осевой дороги/просёлка/рельсов (машины, вагоны, мосты — можно)
	var nr := 0
	for a in rects:
		var nm: String = a[4]
		if nm.begins_with("car_") or nm.begins_with("tractor") or nm.begins_with("trailer") or nm.begins_with("wagon") or nm.begins_with("bus_stop") or nm.contains("checkpoint"):
			continue
		var u := Vector2(cos(a[1]), -sin(a[1]))
		var v := Vector2(sin(a[1]), cos(a[1]))
		var hit := 99.0
		for i in 7:
			for j in 7:
				var q: Vector2 = a[0] + u * a[2] * (i / 3.0 - 1.0) + v * a[3] * (j / 3.0 - 1.0)
				hit = minf(hit, minf(WorldGen.path_dist(q.x, q.y), WorldGen.asphalt_dist(q.x, q.y) - 1.4))   # асфальт виден до ~3,4 тайла
		if hit < 2.0:
			nr += 1
			if nr <= 40:
				var which := ""
				for ri in WorldGen._roads.size():
					var rd: Dictionary = WorldGen._roads[ri]
					var pts: PackedVector2Array = rd.pts
					for k in pts.size() - 1:
						if a[0].distance_to(Geometry2D.get_closest_point_to_segment(a[0], pts[k], pts[k + 1])) < a[2] + a[3] + 2.0:
							which = "дорога №%d (%d точек, %s) от %d:%d" % [ri, pts.size(), "тропа" if rd.get("trail", false) else ("просёлок" if rd.track else "асфальт"), roundi(pts[0].x), roundi(pts[0].y)]
				print("ROAD %s @%d:%d  до дороги %.1f  %s" % [nm, roundi(a[0].x), roundi(a[0].y), hit, which])
	print("ROAD итого зданий на дорогах: ", nr)
	# заборы и ворота сквозь здания и машины
	var nf := 0
	var fby := {}
	for key in pr._batch:
		var b: Dictionary = pr._batch[key]
		var nm: String = b.model
		if not (nm.begins_with("fence") or nm.begins_with("gate")):
			continue
		var ab: AABB = pr._meshes[nm].get_aabb()
		for xf: Transform3D in b.xf:
			var c := xf * ab.get_center()
			var ax := xf.basis.x
			var fr := [Vector2(c.x, c.z) / WorldGen.T, atan2(-ax.z, ax.x), ab.size.x * 0.5 / WorldGen.T - 0.1, maxf(ab.size.z * 0.5 / WorldGen.T - 0.1, 0.05)]
			for a in rects:
				if a[0].distance_to(fr[0]) > a[2] + a[3] + fr[2] + fr[3]:
					continue
				if pr._rect_overlap(a, fr):
					nf += 1
					fby[nm + " × " + a[4]] = fby.get(nm + " × " + a[4], 0) + 1
					if nf <= 40:
						print("FENCE %s @%d:%d  сквозь  %s @%d:%d" % [nm, roundi(fr[0].x), roundi(fr[0].y), a[4], roundi(a[0].x), roundi(a[0].y)])
	print("FENCE итого: ", nf, " ", fby)
	quit()

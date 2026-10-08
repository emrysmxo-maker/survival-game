extends SceneTree
# Выгрузка расстановки в JSON по локациям/хуторам для просмотра в Blender (tools/props/scene_render.py).
# godot --headless --path godot -s res://scripts/scenedump.gd -- <папка> <сайт1,сайт2,...>
func _init() -> void:
	WorldGen.init()
	var pr = load("res://scripts/props.gd").new()
	pr._ready()
	var args := OS.get_cmdline_user_args()
	var sites := {}
	for k in WorldGen.FEATURES: sites[k] = WorldGen.FEATURES[k]
	for k in WorldGen.HAMLETS: sites[k] = WorldGen.HAMLETS[k]
	for name in args[1].split(","):
		var st: Dictionary
		if name.begins_with("@"):                                      # @x:y — произвольная точка
			var xy := name.substr(1).split(":")
			st = {"x": float(xy[0]), "y": float(xy[1]), "r": 10.0}
		else:
			st = sites[name]
		var out := {"site": name, "cx": st.x, "cy": st.y, "r": st.r, "h0": WorldGen.height_m(st.x, st.y), "props": [], "trees": []}
		var lim: float = st.r + float(OS.get_environment("LIM") if OS.get_environment("LIM") != "" else "14")
		for key in pr._batch:
			var b: Dictionary = pr._batch[key]
			for xf in b.xf:
				var tx: float = xf.origin.x / WorldGen.T
				var ty: float = xf.origin.z / WorldGen.T
				if Vector2(tx - st.x, ty - st.y).length() < lim:
					var bs: Basis = xf.basis
					out.props.append({"m": b.model, "p": [xf.origin.x, xf.origin.y, xf.origin.z], "b": [bs.x.x, bs.x.y, bs.x.z, bs.y.x, bs.y.y, bs.y.z, bs.z.x, bs.z.y, bs.z.z]})
		# рельеф сеткой 1 тайл: высота и раскраска (вода, асфальт, грунт, лес)
		var grid := []
		var gx0 := floorf(st.x - lim)
		var gy0 := floorf(st.y - lim)
		var gn := int(lim * 2.0) + 1
		for j in gn:
			for i in gn:
				var x := gx0 + i
				var y := gy0 + j
				var t := WorldGen.terrain(x, y)
				var L := WorldGen.ground_layers_t(x, y, t)
				var wa := WorldGen.water_at(x, y)
				grid.append([snappedf(WorldGen.height_m(x, y), 0.01), snappedf(L[0], 0.01), snappedf(wa.x, 0.01), snappedf(wa.y * WorldGen.HK, 0.01), snappedf(WorldGen.forest_mask(x, y), 0.01)])
		out["grid"] = {"x0": gx0 * WorldGen.T, "y0": gy0 * WorldGen.T, "n": gn, "step": WorldGen.T, "v": grid}
		out["roads"] = []
		for rd in WorldGen._roads:
			var line := []
			for q in rd.pts:
				line.append([q.x * WorldGen.T, WorldGen.height_m(q.x, q.y), q.y * WorldGen.T])
			out.roads.append(line)
		var CH := WorldGen.CHUNK
		for cy in range(int(floor((st.y - lim) / CH)), int(floor((st.y + lim) / CH)) + 1):
			for cx in range(int(floor((st.x - lim) / CH)), int(floor((st.x + lim) / CH)) + 1):
				var cc := WorldGen.chunk_content(cx, cy, 1.0)
				for o in cc.trees:
					if Vector2(o.x - st.x, o.y - st.y).length() < lim:
						out.trees.append([o.x * WorldGen.T, WorldGen.height_m(o.x, o.y), o.y * WorldGen.T, o.scale])
		var f := FileAccess.open("%s/scene_%s.json" % [args[0], name], FileAccess.WRITE)
		f.store_string(JSON.stringify(out))
	quit()

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
		var st: Dictionary = sites[name]
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

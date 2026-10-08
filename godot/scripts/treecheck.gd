extends SceneTree
# Проверка деревьев без экрана: виды из kinds.json грузятся, у коры/листвы есть текстуры,
# размеры (м) и нагрузка: треугольники и экземпляры в лесу вокруг точки.
# godot --headless --path godot -s res://scripts/treecheck.gd -- [x,y]

func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		n += (ix.size() if ix.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n

func _init() -> void:
	WorldGen.init()
	var w = load("res://scripts/world.gd").new()
	root.add_child(w)
	w._ready()
	var tris := {}
	var lvt := {}
	for key in w.kinds:
		var kd: Dictionary = w.kinds[key]
		if not (kd.cat in ["tree", "dead", "sapling"]):
			continue
		var t := 0
		var info := []
		var per := []
		for arr in kd.get("lv", [kd.mmis]):
			var tl := 0
			for mmi in arr:
				tl += _tris(mmi.multimesh.mesh)
			per.append(tl)
		lvt[key] = per
		for mmi in kd.lv[0] if kd.has("lv") else kd.mmis:
			var m: Mesh = mmi.multimesh.mesh
			t += _tris(m)
			var mat = m.surface_get_material(0)
			if mat is ShaderMaterial:
				info.append("листва tex=%s n=%s" % [mat.get_shader_parameter("albedo_tex") != null, mat.get_shader_parameter("has_normal")])
			elif mat is BaseMaterial3D:
				info.append("кора tex=%s nrm=%s vcol=%s пов.%d" % [mat.albedo_texture != null, mat.normal_enabled, mat.vertex_color_use_as_albedo, m.get_surface_count()])
		tris[key] = t
		print("KIND %-14s %-8s высота %.1f м  крона r=%.1f м  тр.%d (уровни %s)  %s" % [key, kd.cat, kd.top, kd.cr, t, str(per), ", ".join(info)])
	var c := Vector2(40, -150)
	for a in OS.get_cmdline_user_args():
		if "," in a:
			var xy := a.split(",")
			c = Vector2(float(xy[0]), float(xy[1]))
	var R := 3
	var cx := floori(c.x / WorldGen.CHUNK)
	var cy := floori(c.y / WorldGen.CHUNK)
	var n_tree := 0
	var total := 0
	var tot_l := [0, 0, 0]
	for j in range(-R, R + 1):
		for i in range(-R, R + 1):
			var cc: Dictionary = WorldGen.chunk_content(cx + i, cy + j)
			if i == 0 and j == 0:
				print("CHUNK ", cc.eco, " объектов ", cc.objs.size(), " ", cc.objs.slice(0, 6).map(func(o): return o.key))
			for o in cc.objs:
				if tris.has(o.key):
					total += tris[o.key]
					for l in 3:
						tot_l[l] += lvt[o.key][mini(l, lvt[o.key].size() - 1)]
					if o.cat == "tree":
						n_tree += 1
	var side := (2 * R + 1) * WorldGen.CHUNK * WorldGen.T
	print("FOREST у (%d,%d): квадрат %.0f×%.0f м — деревьев %d (%.0f на га), треугольников деревьев по уровням %s" % [c.x, c.y, side, side, n_tree, n_tree / (side * side) * 10000.0, str(tot_l)])
	# время сборки чанка (фоновый поток в игре): рельеф + содержимое + данные MultiMesh
	var t0 := Time.get_ticks_usec()
	var nb := 0
	for j in range(-1, 2):
		for i in range(-1, 2):
			w._build_chunk(Vector2i(cx + 20 + i, cy + j))
			nb += 1
	print("CHUNKTIME %.1f мс на чанк" % [(Time.get_ticks_usec() - t0) / 1000.0 / nb])
	for r in [3, 8]:
		w.view_r = r * WorldGen.CHUNK
		w.ensure_now(c, r)
		var t1 := Time.get_ticks_usec()
		w._rebuild_sprites()
		print("REBUILD чанков %d: пересборка буферов %.1f мс" % [w.chunks.size(), (Time.get_ticks_usec() - t1) / 1000.0])
	quit()

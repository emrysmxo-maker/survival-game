extends Node3D
# Мир вокруг бойца: земля чанками (рельеф + 8 фототекстур с картами рельефа), лес.
# Весь лес — «импосторы»: модели Poly Haven / EZ-Tree, заранее отрендеренные под угол
# игровой камеры в высоком разрешении (цвет + нормаль + глубина + затенённость),
# здесь они освещаются солнцем по-настоящему и пересекаются по глубине.
# Чанки считаются в фоновых потоках, в главном — только сборка меша.

const LOAD_R := 3          # чанков вокруг бойца (7×7)
const DROP_R := 5
const GRID := 24           # клеток сетки земли на чанк (шаг 0.5 тайла)
# яркость по видам (модели сняты с разной экспозицией)
const GAIN := {"pine": 1.6, "fir": 1.3, "pinesap": 1.4, "pinesapm": 1.4, "firsap": 1.2, "firsapm": 1.2, "broad1": 1.2, "broad2": 1.2, "smalltree": 1.15, "birch0": 1.1, "birch1": 1.1, "birch2": 1.1, "oak0": 1.15, "oak1": 1.15}
const CAT_GAIN := {"tree": 1.45, "dead": 1.2, "sap": 1.3, "sapm": 1.35, "shrub": 1.25, "fern": 1.1, "nettle": 1.1}
const GROUND_LAYERS := ["floor", "grass", "moss", "ash", "rocky", "swamp", "path", "riverbed"]

var chunks := {}           # Vector2i -> {"mesh": MeshInstance3D, "c": content}
var pending := {}
var results := {}
var _mutex := Mutex.new()
var ground_mat: ShaderMaterial
var kinds := {}            # ключ импостора -> {"mmi", "top", "flat", "cat"}
var imp_meta := {}
var density := 1.0         # доля травяного яруса (настройка качества)
var _dirty := false
var _rebuild_t := 0.0
var center := Vector2i(999999, 999999)
var player_tile := Vector2.ZERO
var _fade := {}            # объект -> текущая видимость (для дерева перед бойцом)

func _ready() -> void:
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = load("res://shaders/ground.gdshader")
	ground_mat.set_shader_parameter("t_albedo", load("res://assets/ground2/ground_diff_array.jpg"))
	ground_mat.set_shader_parameter("t_normal", load("res://assets/ground2/ground_nor_array.jpg"))
	imp_meta = JSON.parse_string(FileAccess.open("res://assets/imp/meta.json", FileAccess.READ).get_as_text())
	var lim := 9999
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--implim="):
			lim = int(a.substr(9))
	for key in imp_meta:
		if lim <= 0:
			break
		lim -= 1
		_add_kind(key, imp_meta[key])

# ---------- импосторы ----------
func _quad(m: Dictionary) -> ArrayMesh:
	var ppm: float = m.ppm
	var x0: float = -m.ax / ppm
	var x1: float = (m.w - m.ax) / ppm
	var y1: float = m.ay / ppm
	var y0: float = (m.ay - m.h) / ppm
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(x0, y1, 0), Vector3(x1, y1, 0), Vector3(x1, y0, 0), Vector3(x0, y0, 0)])
	a[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	a[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	a[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return mesh

func _add_kind(key: String, m: Dictionary) -> void:
	var cat: String = m.spec.cat
	var flat: bool = cat in WorldGen.FLAT_CATS
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/impostor.gdshader")
	mat.set_shader_parameter("albedo_tex", load("res://assets/imp/%s_albedo.png" % key))
	mat.set_shader_parameter("ndt_tex", load("res://assets/imp/%s_ndt.png" % key))
	mat.set_shader_parameter("depth_range", m.R)
	mat.set_shader_parameter("gain", GAIN.get(key.split("_")[0], 1.0) * CAT_GAIN.get(cat, 1.0))
	mat.set_shader_parameter("sway", WorldGen.SWAY.get(cat, 0.0))
	mat.set_shader_parameter("push", WorldGen.PUSH.get(cat, 0.0))
	mat.set_shader_parameter("translucency", 0.3 if cat in ["tree", "sap", "sapm", "shrub", "fern", "nettle", "grass", "flower"] else 0.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _quad(m)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	# мелочь на земле теней не даёт; деревья, кусты, камни — дают
	var shadow: bool = not flat and not (cat in ["grass", "flower", "moss"])
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 16384.0
	add_child(mmi)
	var fmmi: MultiMeshInstance3D = null
	if cat in ["tree", "dead", "sapm", "shrub"]:
		# полупрозрачная копия для деревьев перед бойцом
		var fmat: ShaderMaterial = mat.duplicate()
		fmat.shader = load("res://shaders/impostor_fade.gdshader")
		var fmm := MultiMesh.new()
		fmm.transform_format = MultiMesh.TRANSFORM_3D
		fmm.use_custom_data = true
		fmm.mesh = mm.mesh
		fmmi = MultiMeshInstance3D.new()
		fmmi.multimesh = fmm
		fmmi.material_override = fmat
		fmmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fmmi.extra_cull_margin = 16384.0
		add_child(fmmi)
	kinds[key] = {"mmi": mmi, "fmmi": fmmi, "top": m.ay / m.ppm, "flat": flat, "cat": cat}

# ---------- чанки ----------
func update_world(tile_pos: Vector2, cam: Camera3D) -> void:
	player_tile = tile_pos
	var c := Vector2i(floori(tile_pos.x / WorldGen.CHUNK), floori(tile_pos.y / WorldGen.CHUNK))
	if c != center:
		center = c
		for k in chunks.keys():
			if absi(k.x - c.x) > DROP_R or absi(k.y - c.y) > DROP_R:
				chunks[k].mesh.queue_free()
				chunks.erase(k)
				_dirty = true
	if pending.size() < 4:
		var best := Vector2i.ZERO
		var bd := 1e9
		for dx in range(-LOAD_R, LOAD_R + 1):
			for dy in range(-LOAD_R, LOAD_R + 1):
				var k := Vector2i(c.x + dx, c.y + dy)
				if chunks.has(k) or pending.has(k):
					continue
				var d := float(dx * dx + dy * dy)
				if d < bd:
					bd = d
					best = k
		if bd < 1e9:
			var key := best
			pending[key] = WorkerThreadPool.add_task(_build_chunk.bind(key))
	for k in pending.keys():
		if WorkerThreadPool.is_task_completed(pending[k]):
			WorkerThreadPool.wait_for_task_completion(pending[k])
			pending.erase(k)
			_mutex.lock()
			var data = results.get(k)
			results.erase(k)
			_mutex.unlock()
			if data != null:
				_finish_chunk(k, data)
			break
	_rebuild_t -= get_process_delta_time()
	if _dirty and _rebuild_t <= 0.0:
		_rebuild_sprites()
	_update_fade(cam)

func ensure_now(tile_pos: Vector2, r: int) -> void:
	var c := Vector2i(floori(tile_pos.x / WorldGen.CHUNK), floori(tile_pos.y / WorldGen.CHUNK))
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var k := Vector2i(c.x + dx, c.y + dy)
			if chunks.has(k) or pending.has(k):
				continue
			_build_chunk(k)
			_mutex.lock()
			var data = results.get(k)
			results.erase(k)
			_mutex.unlock()
			_finish_chunk(k, data)
	_rebuild_sprites()

func set_density(d: float) -> void:
	# новая плотность травы: перестраиваем загруженные чанки
	if absf(d - density) < 0.01:
		return
	density = d
	for k in chunks.keys():
		chunks[k].mesh.queue_free()
	chunks.clear()
	_fade.clear()
	center = Vector2i(999999, 999999)
	ensure_now(player_tile, 2)

func _build_chunk(k: Vector2i) -> void:
	var sx := float(k.x * WorldGen.CHUNK)
	var sy := float(k.y * WorldGen.CHUNK)
	var step := float(WorldGen.CHUNK) / GRID
	var n := GRID + 1
	var hs := PackedFloat32Array()
	hs.resize((n + 2) * (n + 2))
	for j in n + 2:
		for i in n + 2:
			hs[j * (n + 2) + i] = WorldGen.height(sx + (i - 1) * step, sy + (j - 1) * step) * WorldGen.HK
	var verts := PackedVector3Array(); verts.resize(n * n)
	var norms := PackedVector3Array(); norms.resize(n * n)
	var cols := PackedColorArray(); cols.resize(n * n)
	var uv := PackedVector2Array(); uv.resize(n * n)
	var uv2 := PackedVector2Array(); uv2.resize(n * n)
	var st := step * WorldGen.T
	for j in n:
		for i in n:
			var x := sx + i * step
			var y := sy + j * step
			var id := j * n + i
			var h := hs[(j + 1) * (n + 2) + i + 1]
			verts[id] = Vector3(x * WorldGen.T, h, y * WorldGen.T)
			var hl := hs[(j + 1) * (n + 2) + i]
			var hr := hs[(j + 1) * (n + 2) + i + 2]
			var hu := hs[j * (n + 2) + i + 1]
			var hd := hs[(j + 2) * (n + 2) + i + 1]
			norms[id] = Vector3(hl - hr, 2.0 * st, hu - hd).normalized()
			var L := WorldGen.ground_layers(x, y)
			cols[id] = Color(L[0], L[1], L[2], L[3])
			uv[id] = Vector2(x, y)
			uv2[id] = Vector2(L[4], L[5])
	var idx := PackedInt32Array()
	for j in GRID:
		for i in GRID:
			var a := j * n + i
			idx.append_array([a, a + 1, a + n + 1, a, a + n + 1, a + n])
	var content := WorldGen.chunk_content(k.x, k.y, density)
	for o in content.objs:
		o["h"] = WorldGen.height(o.x, o.y) * WorldGen.HK
	var data := {"v": verts, "n": norms, "c": cols, "uv": uv, "uv2": uv2, "i": idx, "content": content}
	_mutex.lock()
	results[k] = data
	_mutex.unlock()

func _finish_chunk(k: Vector2i, data: Dictionary) -> void:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = data.v
	a[Mesh.ARRAY_NORMAL] = data.n
	a[Mesh.ARRAY_COLOR] = data.c
	a[Mesh.ARRAY_TEX_UV] = data.uv
	a[Mesh.ARRAY_TEX_UV2] = data.uv2
	a[Mesh.ARRAY_INDEX] = data.i
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = null if OS.get_cmdline_user_args().has("--noground") else ground_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	chunks[k] = {"mesh": mi, "c": data.content}
	_dirty = true

func _rebuild_sprites() -> void:
	_dirty = false
	_rebuild_t = 0.25
	var lists := {}
	for key in kinds:
		lists[key] = []
	for k in chunks:
		for o in chunks[k].c.objs:
			if lists.has(o.key):
				lists[o.key].append(o)
	for key in kinds:
		var kd: Dictionary = kinds[key]
		var mm: MultiMesh = kd.mmi.multimesh
		var arr: Array = lists[key]
		mm.instance_count = arr.size()
		for i in arr.size():
			var o: Dictionary = arr[i]
			o["mi"] = i
			var s: float = o.scale
			var pos := Vector3(o.x * WorldGen.T, o.h, o.y * WorldGen.T)
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), pos))
			mm.set_instance_custom_data(i, _custom(o, kd, 1.0 if _fade.get(o, 1.0) >= 0.999 else 0.0))

func _custom(o: Dictionary, kd: Dictionary, vis: float) -> Color:
	var flip := -1.0 if o.flip else 1.0
	return Color(o.x * 0.55 + o.y * 0.35, flip * (1.0 + vis), kd.top * o.scale, 1.0 if kd.flat else 0.0)

# Дерево/куст, закрывающее бойца, становится полупрозрачным (вместо «дырки» в кроне)
func _update_fade(cam: Camera3D) -> void:
	if cam == null or OS.get_cmdline_user_args().has("--nofade"):
		return
	var dt := get_process_delta_time()
	var pp := WorldGen.to_world(player_tile.x, player_tile.y, WorldGen.height(player_tile.x, player_tile.y))
	var right := cam.global_transform.basis.x
	var up := cam.global_transform.basis.y
	var back := cam.global_transform.basis.z           # к камере
	var want := {}
	var pc := Vector2i(floori(player_tile.x / WorldGen.CHUNK), floori(player_tile.y / WorldGen.CHUNK))
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			var k := Vector2i(pc.x + dx, pc.y + dy)
			if not chunks.has(k):
				continue
			for o in chunks[k].c.objs:
				if not (o.cat in ["tree", "dead", "sapm", "shrub"]):
					continue
				var d := Vector3(o.x * WorldGen.T, o.h, o.y * WorldGen.T) - pp
				if d.dot(back) < 0.3:          # не перед бойцом
					continue
				var kd: Dictionary = kinds.get(o.key, {})
				if kd.is_empty():
					continue
				var top: float = kd.top * o.scale
				var x := d.dot(right)
				var y := d.dot(up)                 # низ дерева на экране относительно бойца
				var half_w := top * 0.32
				# боец на экране: от y=0 до y=1.5 (м), по x ±0.4
				if absf(x) < half_w + 0.4 and -y + 1.5 > 0.0 and -y < top:
					want[o] = 0.35
	var changed := []
	for o in want.keys():
		if not _fade.has(o):
			_fade[o] = 1.0
	for o in _fade.keys():
		var target: float = want.get(o, 1.0)
		var v: float = move_toward(_fade[o], target, dt * 3.0)
		if v != _fade[o] or target < 1.0:
			_fade[o] = v
			changed.append(o)
		if v >= 1.0 and target >= 1.0:
			_fade.erase(o)
			changed.append(o)
	if changed.is_empty():
		return
	var per_kind := {}
	for o in changed:
		var kd2: Dictionary = kinds.get(o.key, {})
		if kd2.is_empty() or not o.has("mi"):
			continue
		var mm: MultiMesh = kd2.mmi.multimesh
		var f: float = _fade.get(o, 1.0)
		if o.mi < mm.instance_count:
			# основной экземпляр: 1 — виден, иначе не рисуется (тень остаётся)
			mm.set_instance_custom_data(o.mi, _custom(o, kd2, 1.0 if f >= 0.999 else 0.0))
		per_kind[o.key] = true
	# полупрозрачные копии
	for key in per_kind:
		var kd3: Dictionary = kinds[key]
		if kd3.fmmi == null:
			continue
		var list := []
		for o in _fade:
			if o.key == key and _fade[o] < 0.999:
				list.append(o)
		var fm: MultiMesh = kd3.fmmi.multimesh
		fm.instance_count = list.size()
		for i in list.size():
			var o2: Dictionary = list[i]
			var s2: float = o2.scale
			fm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s2, s2, s2)), Vector3(o2.x * WorldGen.T, o2.h, o2.y * WorldGen.T)))
			fm.set_instance_custom_data(i, _custom(o2, kd3, _fade[o2]))

# ---------- запросы ----------
func ecosystem_at(tile: Vector2) -> String:
	return WorldGen.ecosystem(floori(tile.x / WorldGen.CHUNK), floori(tile.y / WorldGen.CHUNK)).name

func count_trees() -> int:
	var n := 0
	for k in chunks:
		if absi(k.x - center.x) <= 2 and absi(k.y - center.y) <= 2:
			n += chunks[k].c.trees.size()
	return n

# препятствия рядом: [{x, y, r, tree}] в тайлах
func obstacles_near(tile: Vector2) -> Array:
	var out := []
	var c := Vector2i(floori(tile.x / WorldGen.CHUNK), floori(tile.y / WorldGen.CHUNK))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var k := Vector2i(c.x + dx, c.y + dy)
			if chunks.has(k):
				out.append_array(chunks[k].c.solid)
	return out

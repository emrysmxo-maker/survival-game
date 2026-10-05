extends Node3D
# Мир вокруг бойца: земля чанками (рельеф + 8 фототекстур с картами рельефа), лес.
# Весь лес — «импосторы»: модели Poly Haven / EZ-Tree, заранее отрендеренные под угол
# игровой камеры в высоком разрешении (цвет + нормаль + глубина + затенённость),
# здесь они освещаются солнцем по-настоящему и пересекаются по глубине.
# Чанки считаются в фоновых потоках, в главном — только сборка меша.

var load_radius := 3       # чанков вокруг бойца (5×5 / 7×7, настройка качества)
const DROP_R := 5
const GRID := 24           # клеток сетки земли на чанк (шаг 0.5 тайла)
# яркость по видам (модели сняты с разной экспозицией)
const GAIN := {}
const CAT_GAIN := {"tree": 1.1, "dead": 1.0, "sap": 1.05, "sapm": 1.05, "shrub": 1.05}
const OCCLUDERS := ["tree", "dead", "sapm", "shrub"]
const GROUND_LAYERS := ["floor", "grass", "moss", "ash", "rocky", "swamp", "path", "riverbed"]

var chunks := {}           # Vector2i -> {"mesh": MeshInstance3D, "c": content}
var pending := {}
var results := {}
var _mutex := Mutex.new()
var ground_mat: ShaderMaterial
var kinds := {}            # ключ импостора -> {"mmi", "top", "flat", "cat"}
var imp_meta := {}
var gallery := OS.get_cmdline_user_args().has("--gallery")
var density := 1.0         # доля травяного яруса (настройка качества)
var _dirty := false
var _rebuild_t := 0.0
var center := Vector2i(999999, 999999)
var player_tile := Vector2.ZERO

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
	# запись глубины в шейдере отключает ранний тест глубины (дорого на телефоне):
	# нужна только объёмным объектам; трава/цветы/ветки/брёвна рисуются плоско
	mat.set_shader_parameter("use_depth", not (cat in ["grass", "flower", "fern", "nettle", "branch", "log"]))
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
	kinds[key] = {"mmi": mmi, "top": m.ay / m.ppm, "flat": flat, "cat": cat}

# ---------- чанки ----------
func update_world(tile_pos: Vector2, _cam: Camera3D) -> void:
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
		for dx in range(-load_radius, load_radius + 1):
			for dy in range(-load_radius, load_radius + 1):
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
	if gallery:
		content = _gallery_content(k)
	# готовые данные для MultiMesh по видам: 12 чисел матрицы + 4 своих на экземпляр
	var bufs := {}
	for o in content.objs:
		o["h"] = WorldGen.height(o.x, o.y) * WorldGen.HK
		var kd: Dictionary = kinds.get(o.key, {})
		if kd.is_empty():
			continue
		if not bufs.has(o.key):
			bufs[o.key] = PackedFloat32Array()
		var s: float = o.scale
		var c := _custom(o, kd)
		bufs[o.key].append_array([s, 0.0, 0.0, o.x * WorldGen.T, 0.0, s, 0.0, o.h, 0.0, 0.0, s, o.y * WorldGen.T, c.r, c.g, c.b, c.a])
	content["bufs"] = bufs
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
	var all := {}
	for k in chunks:
		var bufs: Dictionary = chunks[k].c.bufs
		for key in bufs:
			if not all.has(key):
				all[key] = PackedFloat32Array()
			all[key].append_array(bufs[key])
	for key in kinds:
		var mm: MultiMesh = kinds[key].mmi.multimesh
		var buf: PackedFloat32Array = all.get(key, PackedFloat32Array())
		var n := buf.size() / 16
		if mm.instance_count != n:
			mm.instance_count = n
		if n > 0:
			mm.buffer = buf

func _custom(o: Dictionary, kd: Dictionary) -> Color:
	var flip := -1.0 if o.flip else 1.0
	return Color(o.x * 0.55 + o.y * 0.35, flip * 2.0, kd.top * o.scale, 1.0 if kd.flat else 0.0)

# ---------- запросы ----------
# Закрывает ли крона/куст бойца на экране: точки тела (ноги, пояс, грудь, голова)
# проверяются по маске непрозрачности картинки (meta.json → mask)
func occluded(pos: Vector3, h: float, cam: Camera3D) -> bool:
	var right := cam.global_transform.basis.x
	var up := cam.global_transform.basis.y
	var back := cam.global_transform.basis.z
	var t := Vector2(pos.x / WorldGen.T, pos.z / WorldGen.T)
	var pc := Vector2i(floori(t.x / WorldGen.CHUNK), floori(t.y / WorldGen.CHUNK))
	var hits := 0
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			var k := Vector2i(pc.x + dx, pc.y + dy)
			if not chunks.has(k):
				continue
			for o in chunks[k].c.objs:
				if not (o.cat in OCCLUDERS):
					continue
				var d := Vector3(o.x * WorldGen.T, o.h, o.y * WorldGen.T) - pos
				if d.dot(back) < 0.2:
					continue
				var m: Dictionary = imp_meta.get(o.key, {})
				if m.is_empty() or not m.has("mask"):
					continue
				var ppm: float = m.ppm
				var s: float = o.scale
				var fl := -1.0 if o.flip else 1.0
				var rx: float = -d.dot(right) / s * fl
				for fy in [0.15, 0.5, 0.85, 1.05]:
					var ry: float = (-d.dot(up) + h * fy) / s
					var u: float = (rx + m.ax / ppm) / (m.w / ppm)
					var v: float = (m.ay / ppm - ry) / (m.h / ppm)
					if u < 0.0 or u >= 1.0 or v < 0.0 or v >= 1.0:
						continue
					var mi: int = int(v * m.mask_h) * int(m.mask_w) + int(u * m.mask_w)
					if m.mask.unicode_at(mi) == 49:
						hits += 1
						if hits >= 2:
							return true
	return false

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

# --- проверка: все объекты рядами у старта (запуск с --gallery) ---
func _gallery_content(k: Vector2i) -> Dictionary:
	var objs := []
	if k == Vector2i(0, 0) or k == Vector2i(1, 0) or k == Vector2i(0, 1) or k == Vector2i(1, 1):
		var keys := imp_meta.keys()
		keys.sort()
		var i := 0
		for key in keys:
			var cat: String = imp_meta[key].spec.cat
			var step := 4.0 if cat in ["tree", "dead"] else 1.6
			var x := 2.0 + float(i % 12) * 2.0
			var y := 2.0 + float(i / 12) * 2.0
			i += 1
			if floori(x / WorldGen.CHUNK) != k.x or floori(y / WorldGen.CHUNK) != k.y:
				continue
			objs.append({"x": x, "y": y, "key": key, "cat": cat, "scale": 1.0, "flip": false})
	return {"objs": objs, "trees": [], "solid": [], "eco": "gallery"}

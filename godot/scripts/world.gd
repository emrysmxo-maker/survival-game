extends Node3D
# Мир вокруг бойца: земля чанками (рельеф + 8 фототекстур с картами рельефа) и лес из
# настоящих объёмных 3D-моделей (Poly Haven CC0, assets/models/*.glb): ствол/камень — меш с
# текстурами коры, листва/хвоя — карточки-иглы со своим шейдером (ветер, раздвигание).
# Все экземпляры одного вида рисуются одним MultiMesh. Чанки считаются в фоновых потоках.

var load_radius := 3       # чанков вокруг бойца (5×5 / 7×7, настройка качества)
const DROP_R := 5
const GRID := 24           # клеток сетки земли на чанк (шаг 0.5 тайла)
const OCCLUDERS := ["tree", "sapm", "shrub"]
const GROUND_LAYERS := ["floor", "grass", "moss", "ash", "rocky", "swamp", "path", "riverbed"]

var chunks := {}           # Vector2i -> {"mesh": MeshInstance3D, "c": content}
var pending := {}
var results := {}
var _mutex := Mutex.new()
var ground_mat: ShaderMaterial
var water_mat: ShaderMaterial
var kinds := {}            # вид -> {"mmis": [MultiMeshInstance3D], "pre", "bs", "top", "cr", "flat", "cat", "yaw"}
var kinds_meta := {}
var _scenes := {}
var gallery := OS.get_cmdline_user_args().has("--gallery")
var density := 1.0         # доля травяного яруса (настройка качества)
var _dirty := false
var _rebuild_t := 0.0
var center := Vector2i(999999, 999999)
var player_tile := Vector2.ZERO

func _ready() -> void:
	WorldGen.init()
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = load("res://shaders/ground.gdshader")
	ground_mat.set_shader_parameter("t_albedo", load("res://assets/ground2/ground_diff_array.jpg"))
	ground_mat.set_shader_parameter("t_normal", load("res://assets/ground2/ground_nor_array.jpg"))
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader")
	for pair in [["n1", 11, 0.012], ["n2", 23, 0.03]]:     # рябь: две карты нормалей из шума (генерирует Godot)
		var nz := FastNoiseLite.new()
		nz.seed = pair[1]
		nz.frequency = pair[2]
		var nt := NoiseTexture2D.new()
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 3.0
		nt.noise = nz
		water_mat.set_shader_parameter(pair[0], nt)
	kinds_meta = JSON.parse_string(FileAccess.open("res://assets/models/kinds.json", FileAccess.READ).get_as_text())
	var lim := 9999
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--implim="):
			lim = int(a.substr(9))
	for key in kinds_meta:
		if lim <= 0:
			break
		lim -= 1
		_add_kind(key, kinds_meta[key])

# ---------- модели ----------
# MeshInstance3D нужного узла из <модель>_<часть>.glb и его положение внутри файла
func _find_mesh(model: String, part: String, node: Variant) -> Array:
	var path := "res://assets/models/%s_%s.glb" % [model, part]
	if not ResourceLoader.exists(path):
		return []
	if not _scenes.has(path):
		_scenes[path] = load(path).instantiate()
	var root: Node3D = _scenes[path]
	var first: Array = []
	var st: Array = [[root, Transform3D.IDENTITY]]
	while st.size():
		var it: Array = st.pop_back()
		var n: Node = it[0]
		var t: Transform3D = it[1]
		if n != root and n is Node3D:
			t = t * (n as Node3D).transform
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			if node == null or n.name == node or n.get_parent().name == node:
				return [n, t]
			if first.is_empty():
				first = [n, t]
		for c in n.get_children():
			st.append([c, t])
	return first if node == null else []

func _foliage_mesh(src: ArrayMesh, cat: String, href: float) -> ArrayMesh:
	var m: ArrayMesh = src.duplicate()
	for s in m.get_surface_count():
		var o := m.surface_get_material(s)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/foliage.gdshader")
		if o is BaseMaterial3D:
			mat.set_shader_parameter("albedo_tex", o.albedo_texture)
			if o.normal_texture:
				mat.set_shader_parameter("normal_tex", o.normal_texture)
				mat.set_shader_parameter("has_normal", true)
		mat.set_shader_parameter("sway", WorldGen.SWAY.get(cat, 0.0))
		mat.set_shader_parameter("push", WorldGen.PUSH.get(cat, 0.0))
		mat.set_shader_parameter("height_ref", href)
		mat.set_shader_parameter("translucency", 0.3 if cat in ["tree", "sap", "sapm", "shrub", "fern", "nettle", "grass", "flower"] else 0.0)
		m.surface_set_material(s, mat)
	return m

func _add_kind(key: String, kd: Dictionary) -> void:
	var cat: String = kd.cat
	var wood := _find_mesh(kd.m, "wood", kd.n)
	var leaf := [] if kd.wood_only else _find_mesh(kd.m, "leaf", kd.n)
	var ref: Array = wood if not wood.is_empty() else leaf
	if ref.is_empty():
		return
	var aabb: AABB = (ref[1] as Transform3D) * (ref[0] as MeshInstance3D).mesh.get_aabb()
	var top := maxf(aabb.end.y, 0.05)
	var bs: float = float(kd.h) / top if kd.h > 0.0 else float(kd.sc)
	var flat: bool = cat in WorldGen.FLAT_CATS
	var pre := Transform3D((ref[1] as Transform3D).basis, Vector3(0.0, (ref[1] as Transform3D).origin.y, 0.0))
	var shadow: bool = not flat and not (cat in ["grass", "flower", "moss"])
	var mmis := []
	for part in [wood, leaf]:
		if part.is_empty():
			continue
		var is_leaf: bool = part == leaf and not leaf.is_empty()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var src: ArrayMesh = (part[0] as MeshInstance3D).mesh
		mm.mesh = _foliage_mesh(src, cat, top * bs) if is_leaf else src
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		# листва-иглы тени не даёт (тонкие карточки мерцают) — тень кроны от простого эллипсоида
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (shadow and not is_leaf) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.extra_cull_margin = 16384.0
		add_child(mmi)
		mmis.append(mmi)
	var proxy: MultiMeshInstance3D = null
	if shadow and not leaf.is_empty():
		var pm := MultiMesh.new()
		pm.transform_format = MultiMesh.TRANSFORM_3D
		var sph := SphereMesh.new()
		sph.radius = 1.0
		sph.height = 2.0
		sph.radial_segments = 10
		sph.rings = 5
		pm.mesh = sph
		proxy = MultiMeshInstance3D.new()
		proxy.multimesh = pm
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		proxy.extra_cull_margin = 16384.0
		add_child(proxy)
	kinds[key] = {"proxy": proxy, "mmis": mmis, "pre": pre, "bs": bs, "top": top * bs, "cr": maxf(aabb.size.x, aabb.size.z) * 0.5 * bs * 0.7, "flat": flat, "cat": cat, "yaw": deg_to_rad(float(kd.yaw))}

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
	# вода (река, озёра): поверхность на той же сетке, только там, где есть вода
	var wv := PackedVector3Array(); wv.resize(n * n)
	var wm := PackedFloat32Array(); wm.resize(n * n)
	var wc := PackedColorArray(); wc.resize(n * n)
	var any_w := false
	for j in n:
		for i in n:
			var x := sx + i * step
			var y := sy + j * step
			var W := WorldGen.water_at(x, y)
			var dr := WorldGen.water_draw(x, y)
			wm[j * n + i] = 1.0 if dr else 0.0
			var fl := WorldGen.flow_at(x, y)
			var gd := (W.y - hs[(j + 1) * (n + 2) + i + 1] / WorldGen.HK) * WorldGen.HK   # глубина воды в вершине, м
			wc[j * n + i] = Color(fl.x * 0.5 + 0.5, fl.y * 0.5 + 0.5, clampf(gd / 6.0, 0.0, 1.0), 1.0)
			wv[j * n + i] = Vector3(x * WorldGen.T, W.y * WorldGen.HK, y * WorldGen.T)
			if dr:
				any_w = true
	var widx := PackedInt32Array()
	if any_w:
		for j in GRID:
			for i in GRID:
				var a := j * n + i
				if minf(minf(wm[a], wm[a + 1]), minf(wm[a + n], wm[a + n + 1])) > 0.5:
					widx.append_array([a, a + 1, a + n + 1, a, a + n + 1, a + n])
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
		var s: float = o.scale * kd.bs
		var th: float = WorldGen.prand(int(o.x * 131.0 + o.y * 71.0)) * TAU + kd.yaw
		var sn := sin(th)
		var cs := cos(th)
		var pre: Transform3D = kd.pre
		var tr := Transform3D(Basis(Vector3(cs, 0, -sn), Vector3(0, 1, 0), Vector3(sn, 0, cs)) * s, Vector3(o.x * WorldGen.T, o.h, o.y * WorldGen.T)) * pre
		var bs: Basis = tr.basis
		bufs[o.key].append_array([bs.x.x, bs.y.x, bs.z.x, tr.origin.x, bs.x.y, bs.y.y, bs.z.y, tr.origin.y, bs.x.z, bs.y.z, bs.z.z, tr.origin.z])
	content["bufs"] = bufs
	var data := {"wv": wv, "wc": wc, "wi": widx, "v": verts, "n": norms, "c": cols, "uv": uv, "uv2": uv2, "i": idx, "content": content}
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
	if data.wi.size() > 0 and not OS.get_cmdline_user_args().has("--nowater"):
		var wa := []
		wa.resize(Mesh.ARRAY_MAX)
		wa[Mesh.ARRAY_VERTEX] = data.wv
		var nn := PackedVector3Array(); nn.resize(data.wv.size()); nn.fill(Vector3.UP)
		var tg := PackedFloat32Array(); tg.resize(data.wv.size() * 4)
		for ti in data.wv.size():
			tg[ti * 4] = 1.0
			tg[ti * 4 + 3] = 1.0
		wa[Mesh.ARRAY_NORMAL] = nn
		wa[Mesh.ARRAY_COLOR] = data.wc
		wa[Mesh.ARRAY_TANGENT] = tg
		wa[Mesh.ARRAY_INDEX] = data.wi
		var wmesh := ArrayMesh.new()
		wmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wa)
		var wi := MeshInstance3D.new()
		wi.mesh = wmesh
		wi.material_override = water_mat
		wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(wi)
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
		var buf: PackedFloat32Array = all.get(key, PackedFloat32Array())
		var n := buf.size() / 12
		for mmi in kinds[key].mmis:
			var mm: MultiMesh = mmi.multimesh
			if mm.instance_count != n:
				mm.instance_count = n
			if n > 0:
				mm.buffer = buf
		var px: MultiMeshInstance3D = kinds[key].proxy
		if px:
			var pb := PackedFloat32Array()
			pb.resize(n * 12)
			var kd: Dictionary = kinds[key]
			var tall: bool = kd.cat == "tree"
			for i in n:
				var o := i * 12
				var sc: float = sqrt(buf[o] * buf[o] + buf[o + 4] * buf[o + 4] + buf[o + 8] * buf[o + 8]) / kd.bs
				var rh: float = kd.cr * sc
				var rv: float = kd.top * (0.3 if tall else 0.5) * sc
				var ey: float = kd.top * (0.62 if tall else 0.5) * sc
				pb[o] = rh; pb[o + 5] = rv; pb[o + 10] = rh
				pb[o + 3] = buf[o + 3]; pb[o + 7] = buf[o + 7] + ey; pb[o + 11] = buf[o + 11]
			if px.multimesh.instance_count != n:
				px.multimesh.instance_count = n
			if n > 0:
				px.multimesh.buffer = pb

# ---------- запросы ----------
# Закрывает ли крона/куст бойца на экране: точки тела (ноги, пояс, грудь, голова) попадают
# в эллипс кроны (по высоте модели) на плоскости экрана камеры
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
				var kd: Dictionary = kinds.get(o.key, {})
				if kd.is_empty():
					continue
				var d := Vector3(o.x * WorldGen.T, o.h, o.y * WorldGen.T) - pos
				if d.dot(back) < 0.2:
					continue
				var top: float = kd.top * o.scale
				var cr: float = kd.cr * o.scale
				var ey := top * (0.62 if o.cat == "tree" else 0.5)
				var ry := top * (0.3 if o.cat == "tree" else 0.5)
				for fy in [0.15, 0.5, 0.85, 1.05]:
					var dxs: float = -d.dot(right)
					var dys: float = -d.dot(up) + h * fy - ey
					if (dxs * dxs) / (cr * cr) + (dys * dys) / (ry * ry) < 1.0:
						hits += 1
						if hits >= 2:
							if OS.get_cmdline_user_args().has("--xdbg"):
								print("XRAY by ", o.key, " cat=", o.cat, " at tile ", o.x, ",", o.y, " top=", top, " cr=", cr, " d=", d)
							return true
	return false

func ecosystem_at(tile: Vector2) -> String:
	return WorldGen.place_name(tile.x, tile.y)

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
		var keys := kinds_meta.keys()
		keys.sort()
		var i := 0
		for key in keys:
			var cat: String = kinds_meta[key].cat
			var step := 4.0 if cat in ["tree", "dead"] else 1.6
			var x := 2.0 + float(i % 12) * 2.0
			var y := 2.0 + float(i / 12) * 2.0
			i += 1
			if floori(x / WorldGen.CHUNK) != k.x or floori(y / WorldGen.CHUNK) != k.y:
				continue
			objs.append({"x": x, "y": y, "key": key, "cat": cat, "scale": 1.0, "flip": false})
	return {"objs": objs, "trees": [], "solid": [], "eco": "gallery"}

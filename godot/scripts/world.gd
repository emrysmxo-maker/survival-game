extends Node3D
# Мир вокруг бойца: земля чанками (рельеф + 8 текстур), деревья, подлесок, камни.
# Чанки считаются в фоновых потоках (WorkerThreadPool), в главном — только сборка меша.
# Спрайты одного вида рисуются одним MultiMesh на весь мир (мало вызовов отрисовки).

const LOAD_R := 3          # чанков вокруг бойца (7×7)
const DROP_R := 5
const GRID := 24           # клеток сетки земли на чанк (шаг 0.5 тайла)

var chunks := {}           # Vector2i -> {"mesh": MeshInstance3D, "c": content}
var pending := {}          # Vector2i -> task id
var results := {}          # Vector2i -> data (готово в потоке)
var _mutex := Mutex.new()
var ground_mat: ShaderMaterial
var kinds := {}            # ключ спрайта -> {"mm": MultiMeshInstance3D, "top": float}
var sprite_meta := {}
var _dirty := false
var _rebuild_t := 0.0
var center := Vector2i(999999, 999999)
var player_tile := Vector2.ZERO

func _ready() -> void:
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = load("res://shaders/ground.gdshader")
	for n in ["grass", "light", "path", "dark", "ash", "swamp", "riverbed", "rocky"]:
		ground_mat.set_shader_parameter("t_" + n, load("res://assets/ground/%s.jpg" % n))
	var f := FileAccess.open("res://data/sprites.json", FileAccess.READ)
	sprite_meta = JSON.parse_string(f.get_as_text())
	_make_kinds()

# ---------- настоящие 3D-деревья ----------
# порода (0..11) -> [файл, высота дерева (м), ширина-коэф., сила ветра, яркость]
const TREE_MODELS := [
	["tree_16_ponderosa_pine", 7.2, 0.72, 0.7, 0.95, 0.80, false],
	["tree_12_oak_green", 5.9, 0.72, 1.0, 0.95, 0.80, false],
	["tree_07_birch_cluster", 6.5, 0.72, 1.0, 1.0, 0.80, false],
	["tree_10_red_maple", 5.6, 0.72, 1.0, 0.85, 0.55, false],
	["tree_12_oak_green", 5.2, 0.72, 0.0, 1.0, 0.8, true],
	["tree_02_colorado_blue_spruce", 6.7, 0.72, 0.6, 0.95, 0.75, false],
	["tree_12_oak_green", 5.4, 0.83, 1.2, 1.0, 0.85, false],
	["tree_08_columnar_green", 6.8, 0.72, 1.0, 0.95, 0.80, false],
	["tree_14_autumn_rust", 5.0, 0.72, 1.0, 0.80, 0.50, false],
	["tree_22_black_spruce", 7.4, 0.72, 0.6, 0.9, 0.75, false],
	["tree_43_sitka_spruce", 7.4, 0.72, 0.6, 0.9, 0.75, false],
	["tree_09_round_green", 5.9, 0.72, 1.0, 0.95, 0.80, false],
]
var tree_mesh := {}        # порода -> Mesh
var tree_mat := {}         # порода -> Material
var tree_pivot := {}       # порода -> смещение низа модели (м, на единицу высоты)

func _load_tree_models() -> void:
	var tree_shader: Shader = load("res://shaders/tree.gdshader")
	var cache := {}
	for i in TREE_MODELS.size():
		var m: Array = TREE_MODELS[i]
		if not cache.has(m[0]):
			var scn2: PackedScene = load("res://assets/trees3d/%s.glb" % m[0])
			var inst2: Node = scn2.instantiate()
			var mi2 := _first_mesh(inst2)
			var bm: StandardMaterial3D = mi2.mesh.surface_get_material(0)
			var sm := ShaderMaterial.new()
			sm.shader = tree_shader
			sm.set_shader_parameter("albedo_tex", bm.albedo_texture)
			if bm.normal_enabled and bm.normal_texture:
				sm.set_shader_parameter("normal_tex", bm.normal_texture)
				sm.set_shader_parameter("has_normal", true)
			var bb2: AABB = mi2.mesh.get_aabb()
			cache[m[0]] = {"mesh": mi2.mesh, "mat": sm, "pivot": [bb2.position.y, bb2.size.y]}
			inst2.free()      # меш — ресурс, он остаётся у нас
		var c: Dictionary = cache[m[0]]
		tree_mesh[i] = c.mesh
		var mat: ShaderMaterial = c.mat.duplicate()
		mat.set_shader_parameter("sway", m[3])
		mat.set_shader_parameter("gain", m[4])
		mat.set_shader_parameter("sat", m[5])
		mat.set_shader_parameter("leafless", m[6])
		if m[0] == "tree_14_autumn_rust" or m[0] == "tree_10_red_maple":
			mat.set_shader_parameter("tint", Vector3(1.0, 0.92, 0.72))
		tree_mat[i] = mat
		tree_pivot[i] = c.pivot

func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r:
			return r
	return null

func _spawn_trees(k: Vector2i, trees: Array) -> Array:
	var nodes := []
	for t in trees:
		var type: int = t.type
		var m: Array = TREE_MODELS[type]
		var node := MeshInstance3D.new()
		node.mesh = tree_mesh[type]
		if tree_mat[type] != null:
			node.material_override = tree_mat[type]
		var pv: Array = tree_pivot[type]
		var h_m: float = m[1] * t.scale
		var sc: float = h_m / maxf(pv[1], 0.001)
		node.scale = Vector3(sc * m[2], sc, sc * m[2])
		var pos := Vector3(t.x * WorldGen.T, t.h - pv[0] * sc, t.y * WorldGen.T)
		node.position = pos
		node.rotation.y = WorldGen.prand(int(t.x * 13.0 + t.y * 7.0)) * TAU
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(node)
		nodes.append(node)
	return nodes

# ---------- виды спрайтов ----------
func _quad(w: float, h: float, ax: float, ay: float) -> ArrayMesh:
	# размеры в «px» старой игры -> метры; точка земли (ax, ay) — от левого верхнего угла
	var x0 := -ax * WorldGen.PX
	var x1 := (w - ax) * WorldGen.PX
	var y1 := ay * WorldGen.PX
	var y0 := (ay - h) * WorldGen.PX
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(x0, y1, 0), Vector3(x1, y1, 0), Vector3(x1, y0, 0), Vector3(x0, y0, 0)])
	a[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	a[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	a[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	m.custom_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 16, 16))
	return m

func _add_kind(key: String, tex_path: String, w: float, h: float, ax: float, ay: float, sway: float, push: float, flat: bool, shadow: bool, gain: float) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sprite.gdshader")
	mat.set_shader_parameter("tex", load(tex_path))
	mat.set_shader_parameter("sway", sway)
	mat.set_shader_parameter("push", push)
	mat.set_shader_parameter("light_gain", gain)
	mat.set_shader_parameter("hole", 1.0 if (key.begins_with("bush") or key.begins_with("sapling") or key.begins_with("fern") or key.begins_with("nettle")) else 0.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _quad(w, h, ax, ay)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 16384.0
	add_child(mmi)
	kinds[key] = {"mm": mmi, "top": ay * WorldGen.PX, "flat": flat}

func _make_kinds() -> void:
	_load_tree_models()
	var cov: Dictionary = sprite_meta.cover
	for kind in WorldGen.COVER_KINDS:
		var def: Dictionary = WorldGen.COVER_KINDS[kind]
		for key in def.keys:
			if not cov.has(key):
				continue
			var d: Dictionary = cov[key]
			_add_kind(key, d.file, d.w, d.h, d.ax, d.ay, def.sway, def.push, def.flat, not def.flat, 1.0)
	var rk: Dictionary = sprite_meta.rock
	for r in WorldGen.ROCK_TYPES:
		if rk.has(r[0]):
			var d2: Dictionary = rk[r[0]]
			_add_kind(r[0], d2.file, d2.w, d2.h, d2.ax, d2.ay, 0.0, 0.0, false, true, 1.0)

# ---------- чанки ----------
func update_world(tile_pos: Vector2) -> void:
	player_tile = tile_pos
	var c := Vector2i(floori(tile_pos.x / WorldGen.CHUNK), floori(tile_pos.y / WorldGen.CHUNK))
	if c != center:
		center = c
		for k in chunks.keys():
			if absi(k.x - c.x) > DROP_R or absi(k.y - c.y) > DROP_R:
				chunks[k].mesh.queue_free()
				for tn in chunks[k].trees:
					tn.queue_free()
				chunks.erase(k)
				_dirty = true
	# новые задачи — ближние первыми, не больше 4 одновременно
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
	# готовые — в сцену (по одному за кадр)
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
	# при старте/телепорте: сразу всё рядом, без ожидания
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

func _build_chunk(k: Vector2i) -> void:
	var sx := float(k.x * WorldGen.CHUNK)
	var sy := float(k.y * WorldGen.CHUNK)
	var step := float(WorldGen.CHUNK) / GRID
	var n := GRID + 1
	# высоты с запасом в 1 клетку — для нормалей
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
	var content := WorldGen.chunk_content(k.x, k.y)
	# высоты точек для спрайтов
	for arr in [content.trees, content.rocks, content.cover]:
		for o in arr:
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
	mi.material_override = ground_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	chunks[k] = {"mesh": mi, "c": data.content, "trees": _spawn_trees(k, data.content.trees)}
	_dirty = true

func _rebuild_sprites() -> void:
	_dirty = false
	_rebuild_t = 0.25
	var lists := {}
	for key in kinds:
		lists[key] = []
	for k in chunks:
		var c: Dictionary = chunks[k].c
		for r in c.rocks:
			var rk: String = WorldGen.ROCK_TYPES[r.type][0]
			if lists.has(rk):
				lists[rk].append(r)
		for o in c.cover:
			if lists.has(o.key):
				lists[o.key].append(o)
	for key in kinds:
		var kd: Dictionary = kinds[key]
		var mm: MultiMesh = kd.mm.multimesh
		var arr: Array = lists[key]
		mm.instance_count = arr.size()
		for i in arr.size():
			var o: Dictionary = arr[i]
			var s: float = o.get("scale", 1.0)
			var pos := Vector3(o.x * WorldGen.T, o.h, o.y * WorldGen.T)
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), pos))
			var flip := -1.0 if o.get("flip", false) else 1.0
			mm.set_instance_custom_data(i, Color(o.x * 0.55 + o.y * 0.35, flip, kd.top * s, 1.0 if kd.flat else 0.0))

# ---------- запросы ----------
func ecosystem_at(tile: Vector2) -> String:
	return WorldGen.ecosystem(floori(tile.x / WorldGen.CHUNK), floori(tile.y / WorldGen.CHUNK)).name

func count_trees() -> int:
	var n := 0
	for k in chunks:
		if absi(k.x - center.x) <= 2 and absi(k.y - center.y) <= 2:
			n += chunks[k].c.trees.size()
	return n

# препятствия рядом: [{x, y, r}] в тайлах
func obstacles_near(tile: Vector2) -> Array:
	var out := []
	var c := Vector2i(floori(tile.x / WorldGen.CHUNK), floori(tile.y / WorldGen.CHUNK))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var k := Vector2i(c.x + dx, c.y + dy)
			if not chunks.has(k):
				continue
			var cc: Dictionary = chunks[k].c
			for t in cc.trees:
				out.append({"x": t.x, "y": t.y, "r": WorldGen.tree_radius(t.type, t.scale), "tree": true})
			for r in cc.rocks:
				out.append({"x": r.x, "y": r.y, "r": WorldGen.rock_radius(r.type, r.scale), "tree": false})
	return out

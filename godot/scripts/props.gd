extends Node3D
# Постройки, заборы, огороды, машины и мелочь по всей карте. Модели — assets/props/props.glb (рисуются в Blender: tools/props),
# каждая — отдельный узел-меш. Всё ставится один раз при запуске, одинаковые модели собраны в MultiMesh по клеткам карты (видимость по клеткам).
# Координаты — тайлы; yaw в градусах. Дом: «лицо» (крыльцо) смотрит в +y карты при yaw 0; машина: нос смотрит в +x при yaw 0 (yaw — курс).
# Дворы: _yard() — дом, забор с воротами, огород позади, колодец, сарай, как в деревне. Масштаб S — как у мира (боец был 1,44 м).

const S := 0.8
const CELL := 40.0
const T := WorldGen.T
const CARS := ["car_sedan_red", "car_sedan_blue", "car_sedan_white", "car_sedan_burnt", "car_sedan_green", "car_sedan_yellow", "car_van_olive", "car_van_white", "car_van_orange", "car_truck_blue", "car_truck_green", "car_bus_yellow", "car_bus_blue", "tractor_blue", "tractor_red"]
const FOOT := {"club": 7.0, "barn": 7.5, "barn_long": 13.0, "barracks": 11.0, "sawmill_hall": 9.0, "machine_shed": 11.0, "shop": 5.0, "house_brick": 5.0, "house_brick_small": 4.2, "bunker_entrance": 6.0,
	"house_izba_a": 4.0, "house_izba_b": 4.0, "house_izba_c": 4.0, "chapel": 3.0, "silo_conc": 2.4, "silo_metal": 2.4, "water_tower": 2.2, "radio_mast": 1.8, "transmitter": 4.5, "fuel_tank": 3.0}
const HD := {"house_izba_a": 2.5, "house_izba_b": 2.5, "house_izba_c": 2.3, "house_cabin": 1.9, "house_dacha_a": 2.1, "house_dacha_b": 2.2, "house_dacha_c": 2.0, "house_dacha_d": 2.0, "house_brick_small": 2.6, "house_brick": 3.1}
const FENCE_STYLES := ["picket", "rails", "board"]
const RAD := {"shed_blue": 2.4, "shed_green": 2.4, "open_shed": 3.4, "house_cabin": 3.0, "house_banya": 2.6, "house_dacha_a": 3.4, "house_dacha_b": 3.6, "house_dacha_c": 3.3, "house_dacha_d": 3.4,
	"greenhouse": 3.0, "boat_shed": 4.2, "outhouse": 1.2, "well_a": 1.3, "well_b": 1.3, "tent_army": 2.6, "tent_tan": 2.6, "tarp_shelter": 2.4, "log_pile": 4.3, "lumber_stack": 2.6, "pier": 6.5, "container_g": 3.3, "container_b": 3.3, "container_r": 3.3,
	"checkpoint": 4.6, "mil_tower": 2.0, "sandbag_nest": 2.8, "watch_tower": 1.8, "generator_shed": 3.0, "sawdust": 2.6, "bunker_entrance": 6.5, "sawmill_hall": 9.0}
var _occ: Array = []

# хутора: дворы [дом, dx, dy, yaw, ширина, глубина] и отдельные предметы [модель, dx, dy, yaw]
const HAMLETS := {
	"h_stone": {"yards": [["house_izba_b", 0, 0, 20, 14, 13]], "ext": [["shed_blue", 9, -4, 20], ["haystack", -8, 6, 0], ["woodpile", 7, 6, 110], ["car_sedan_green", 10, 3, 60], ["tires", -9, -5, 20]]},
	"h_pond": {"yards": [["house_cabin", -2, 0, -30, 12, 11]], "ext": [["house_banya", 6, -3, -60], ["well_b", 5, 4, 0], ["nets", -7, 5, 40], ["boat_row_up", -5, -6, 20], ["woodpile", 6, 2, 100]]},
	"h_vyselki": {"yards": [["house_izba_a", -7, -3, 10, 14, 13], ["house_dacha_d", 7, -4, -15, 13, 12], ["house_cabin", 0, 8, 180, 12, 10]], "ext": [["haystack", -11, 6, 0], ["cellar", 11, 4, 60], ["car_van_white", 3, 2, 80], ["pole_wood", 0, -9, 0]]},
	"h_zarechye": {"yards": [["house_brick_small", -6, 0, 5, 14, 13], ["house_dacha_c", 7, -2, -10, 12, 11], ["house_izba_c", 0, 9, 180, 14, 12]], "ext": [["bus_stop", 11, 6, 0], ["car_sedan_blue", -2, 4, 100], ["woodpile", -11, 6, 0], ["greenhouse", 4, 5, 0]]},
	"h_novo": {"yards": [["house_izba_c", -3, -2, 0, 14, 12], ["house_dacha_b", 6, 5, 160, 13, 11]], "ext": [["open_shed", 5, -6, 10], ["tractor_blue", -2, 6, 30], ["trailer_cart", -8, 4, 80], ["haystack", -9, -7, 0], ["bales_round", 9, -2, 0]]},
	"h_bereza": {"yards": [["house_izba_a", -4, -2, -8, 14, 13], ["house_izba_b", 6, 5, 172, 14, 12], ["house_cabin", -4, 8, 200, 11, 10]], "ext": [["well_a", 1, 1, 0], ["haystack", 9, -5, 0], ["car_van_orange", -9, 3, 20]]},
	"h_ranger": {"yards": [["house_izba_c", 0, 0, 0, 15, 12]], "ext": [["open_shed", 7, -4, 0], ["watch_tower", -7, -4, 0], ["woodpile", 6, 4, 90], ["car_van_olive", -6, 5, 40], ["barrels_a", 8, 2, 0]]},
	"h_hunter": {"yards": [["house_cabin", 0, 0, 30, 11, 10]], "ext": [["woodpile", 4, 3, 120], ["outhouse", -4, -3, 20], ["fish_rack", -3, 4, 0]]},
	"h_sosn": {"yards": [["house_izba_b", -2, 0, 0, 14, 13], ["house_banya", 6, -4, -40, 9, 9]], "ext": [["log_heap", 3, 5, 20], ["log_heap", -6, 6, 100], ["haystack", 7, 4, 0]]},
	"h_cem": {"yards": [], "ext": [["chapel", 0, -2, 0], ["graves", -6, 1, 0], ["graves", 2, 4, 0], ["fence_rails_b", 0, 7, 0], ["fence_rails_a", 3, 7, 0]]},
	"h_yuzhny": {"yards": [["house_izba_a", -3, -1, 0, 14, 13], ["house_dacha_a", 7, 4, 190, 12, 11]], "ext": [["tractor_red", -6, 6, 140], ["trailer_cart", -9, 3, 60], ["haystack", 9, -6, 0], ["bales_square", 1, 8, 0]]},
}
# дачный посёлок: сетка участков вдоль просёлка
const DACHAS := [["house_dacha_a", -10, -7, 0], ["house_dacha_b", 0, -7, 8], ["house_dacha_c", 10, -7, -6], ["house_dacha_d", -10, 7, 180], ["house_dacha_b", 0, 7, 172], ["house_dacha_a", 10, 7, 188]]

# локации (смещения от центра, тайлы)
const LOCS := {
	"camp": [["tent_army", -4, -3, 10], ["tent_army", -5, 2.5, -20], ["tent_tan", 3.5, -5, 160], ["tarp_shelter", 5, 3, 15], ["campfire", 0, 0, 0], ["bench_log", -2.4, 2.2, 0], ["bench_log", 2.6, -1.8, 90],
		["bench_log", 1.4, 3.0, 20], ["camp_table", -8, -0.5, 80], ["barricade", 0, -9.5, 0], ["barricade", 7, -7, 40], ["barricade", -7, -7.5, -40], ["barricade", 9.5, 1, 90], ["watch_tower", 9, -8, 0], ["clothesline", -2, 7, 0],
		["sandbags", 7, 7, -20], ["barrels_a", -8, 6, 0], ["crates", 8, 0, 0], ["car_van_olive", -9, -6, 160], ["woodpile", 4.5, 8, 180], ["pole_wood", -11, 2, 0]],
	"village": [["well_a", -4.5, -3.5, 0], ["bus_stop", 20, -3, 0], ["car_bus_yellow", 5, 0.8, 12], ["car_sedan_blue", -9, 1.6, 84], ["car_sedan_burnt", 14, 2.6, 160],
		["tractor_blue", -2, -4, 70], ["pole_wood", -19, 3, 0], ["pole_wood", -8, 3, 0], ["pole_wood", 4, 3, 0], ["pole_wood", 16, 3, 0], ["haystack", -19, -14, 0], ["barrels_b", 12, -5, 0], ["tires", -14, 3, 30], ["pallets", 10, 6, 0]],
	"sawmill": [["sawmill_hall", 0, -2, 0], ["log_pile", -9, 6, 0], ["log_pile", -9, 10, 0], ["lumber_stack", 8, 7, 0], ["lumber_stack", 8, 10, 0], ["lumber_stack", 12, 7, 0], ["sawdust", 7, -8, 0], ["log_heap", -3, 9, 30], ["log_heap", 4, 11, -20],
		["house_cabin", -11, -8, 30], ["car_truck_logs", 11, 2, 160], ["tractor_red", 5, 13, 140], ["barrels_a", -12, -3, 0], ["fence_board_a", -13, -11, 0], ["fence_board_b", -10, -11, 0], ["pole_wood", -3, -10, 0], ["woodpile", -14, 0, 90]],
	"lakebase": [["pier", 8.5, 0.5, 0], ["boat_row_wood", 5.5, -1.5, 15], ["boat_row_up", 4, 3.5, -25], ["boat_motor", 6.5, 5, 80], ["boat_row_blue", 5.2, -5.5, 5], ["boat_shed", -3, -6, 0], ["fish_rack", 1, 6, 0], ["nets", -4.5, 4.5, 20], ["house_cabin", -9, 2, 90],
		["house_banya", -6, -9, 10], ["car_sedan_white", 2, 9, 200], ["barrels_b", -1, 2, 0], ["woodpile", -10, 8, 0], ["crates", 3, -8, 0], ["well_b", -8, -3, 0]],
	"farm": [["barn_long", -9, -11, 0], ["barn", 10, -13, 0], ["silo_conc", -1, -13, 0], ["silo_conc", -1, -17, 0], ["silo_metal", 4, -17, 0], ["water_tower", 15, 0, 0], ["machine_shed", 6, 9, 0], ["fuel_tank", -15, 5, 10],
		["house_brick", -15, -2, 90], ["tractor_blue", -1, 4, 30], ["tractor_red", -6, 8, 120], ["trailer_cart", 3, 7, 80], ["bales_round", 12, 6, 0], ["bales_round", 17, 5, 0], ["bales_square", -12, 12, 0], ["car_truck_green", -4, 2, 200],
		["car_van_white", -9, 3, 40], ["haystack", 17, -10, 0], ["pole_wood", -12, 0, 0], ["pole_wood", 0, 0, 0], ["pole_wood", 12, 0, 0], ["barrels_a", -11, -6, 0], ["tires", 9, 14, 0]],
	"bunker": [["bunker_entrance", 0, -3, 0], ["barracks", -7, 9, 0], ["checkpoint", 9, 4, 90], ["jersey", 7, 6.5, 90], ["jersey", 7, 9, 90], ["jersey", 11, 6, 90], ["mil_tower", 10, -9, 0], ["mil_tower", -10, -9, 0], ["sandbag_nest", 6, -7, 0],
		["container_g", -9, -6, 0], ["container_b", -9, -9.5, 0], ["container_r", -5, -9.5, 90], ["car_truck_green", 3, 7, 80], ["car_truck_green", -2, 6, 100], ["car_van_olive", 6, 9.5, 20], ["barrels_b", -12, 3, 0], ["crates", -11, -2, 0], ["sandbags", -4, 4, 0], ["pole_wood", -12, 6, 0]],
	"tower": [["radio_mast", 0, 0, 0], ["transmitter", -7, 4, 0], ["generator_shed", -10, -3, 0], ["dish", 6, -4, 0], ["car_van_white", 8, 6, 210], ["barrels_a", -8, -1, 0], ["pole_wood", 5, 6, 0], ["pole_wood", 11, 8, 0], ["woodpile", -4, -8, 0]],
}
# ограда локаций по окружности: [локация, радиус, модель-секция, от°, до°, пропуск (секции)]
const RINGS := [["bunker", 11.5, "fence_chain", 0, 360, 9], ["tower", 9.5, "fence_chain", 0, 360, 7], ["lakebase", 12.0, "fence_rails", 90, 270, 0], ["sawmill", 14.5, "fence_board", 60, 300, 0], ["farm", 20.0, "fence_rails", 200, 340, 0]]

var _meshes := {}
var _batch := {}
var _rng := RandomNumberGenerator.new()
var _n := 0

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	_rng.seed = 20261008
	_load()
	_locations()
	_hamlets()
	_rings()
	_road_stuff()
	_fields()
	_flush()
	print("props: ", _n, " партий ", _batch.size(), " за ", Time.get_ticks_msec() - t0, " мс")

# ---------------- загрузка и вывод ----------------
func _load() -> void:
	var path := "res://assets/props/props.glb"
	if not ResourceLoader.exists(path):
		return
	var root: Node = (load(path) as PackedScene).instantiate()
	_collect(root)
	root.free()

func _collect(n: Node) -> void:
	if n is MeshInstance3D and n.mesh != null:
		var m: Mesh = n.mesh
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			if mat is BaseMaterial3D and str(mat.resource_name).begins_with("chain") or mat is BaseMaterial3D and str(mat.resource_name).begins_with("net"):
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mat.alpha_scissor_threshold = 0.5
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_meshes[str(n.name)] = m
	for c in n.get_children():
		_collect(c)

func _flush() -> void:
	for key in _batch:
		var b: Dictionary = _batch[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[b.model]
		mm.instance_count = b.xf.size()
		for i in b.xf.size():
			mm.set_instance_transform(i, b.xf[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		add_child(mi)

func _h(x: float, y: float) -> float:
	return WorldGen.height_m(x, y)

# ---------------- установка предмета ----------------
func put(model: String, tx: float, ty: float, yaw_deg: float, mode := "") -> bool:
	if not _meshes.has(model):
		return false
	var t := WorldGen.terrain(tx, ty)
	var wet_ok := model == "pier" or model.begins_with("boat")
	if (t[1] > 0.02 and not wet_ok) or t[2] > 0.6:
		return false
	var th := deg_to_rad(yaw_deg)
	var yb := Basis(Vector3.UP, th)
	var y: float
	var solid := model.begins_with("house_") or FOOT.has(model) or RAD.has(model) or model.begins_with("car_") or model.begins_with("tractor") or model.begins_with("trailer") or model.begins_with("tent")
	if solid:
		var rr: float = RAD.get(model, FOOT.get(model, 2.4 if model.begins_with("car_") else 3.0))
		if model.begins_with("car_"): rr = 2.3
		if model.begins_with("tractor") or model.begins_with("trailer"): rr = 2.0
		for o in _occ:
			if Vector2(tx, ty).distance_to(o[0]) < (rr + o[1]) * 0.66:
				return false
		_occ.append([Vector2(tx, ty), rr])
	if mode == "":
		mode = "tilt" if (model.begins_with("car_") or model.begins_with("tractor") or model.begins_with("trailer")) else ("fence" if model.begins_with("fence") else ("min" if (model.begins_with("house_") or FOOT.has(model) or model.begins_with("shed") or model == "open_shed" or model == "boat_shed" or model == "greenhouse") else "pt"))
	var f := Vector2(cos(th), -sin(th))
	var r := Vector2(sin(th), cos(th))
	if mode == "tilt":
		var d := 2.2
		var hf := _h(tx + f.x * d, ty + f.y * d) - _h(tx - f.x * d, ty - f.y * d)
		var hr := _h(tx + r.x * d, ty + r.y * d) - _h(tx - r.x * d, ty - r.y * d)
		yb = yb * Basis(Vector3(0, 0, 1), atan2(hf, 2.0 * d * T)) * Basis(Vector3(1, 0, 0), -atan2(hr, 2.0 * d * T) + 0.03 * sin(tx * 3.1 + ty))
		y = _h(tx, ty) - 0.02
	elif mode == "fence":
		var d2 := 1.5
		var hf2 := _h(tx + f.x * d2, ty + f.y * d2) - _h(tx - f.x * d2, ty - f.y * d2)
		yb = yb * Basis(Vector3(0, 0, 1), atan2(hf2, 2.0 * d2 * T))
		y = _h(tx, ty) - 0.03
	elif mode == "min":
		var rad: float = FOOT.get(model, 3.2)
		y = _h(tx, ty)
		for k in 4:
			var a := k * PI / 2.0 + 0.7
			y = minf(y, _h(tx + cos(a) * rad, ty + sin(a) * rad))
		y -= 0.12
	else:
		y = _h(tx, ty) - 0.01
	if model.begins_with("pole_"):
		yb = yb * Basis(Vector3(1, 0, 0), _rng.randf_range(-0.05, 0.05)) * Basis(Vector3(0, 0, 1), _rng.randf_range(-0.05, 0.05))
	var key := "%s|%d|%d" % [model, int(floor(tx / CELL)), int(floor(ty / CELL))]
	if not _batch.has(key):
		_batch[key] = {"model": model, "xf": []}
	_batch[key].xf.append(Transform3D(yb * S, Vector3(tx * T, y, ty * T)))
	_n += 1
	return true

# точка в системе двора: lx вдоль «правой» стороны дома, ly к фасаду
func _loc(c: Vector2, th: float, lx: float, ly: float) -> Vector2:
	return c + Vector2(cos(th), -sin(th)) * lx + Vector2(sin(th), cos(th)) * ly

func _fence_line(p0: Vector2, p1: Vector2, style: String, broken: float, skip_from := 0.0, skip_to := 0.0) -> void:
	var len := p0.distance_to(p1)
	var n := maxi(1, roundi(len / 2.99))
	var dir := (p1 - p0) / len
	var yaw := rad_to_deg(atan2(-dir.y, dir.x))
	for i in n:
		var u := (i + 0.5) / n
		if skip_to > skip_from and u * len > skip_from and u * len < skip_to:
			continue
		var c := p0.lerp(p1, u)
		if WorldGen.path_dist(c.x, c.y) < 1.9:
			continue
		var sfx := "b" if _rng.randf() < broken else "a"
		put("fence_%s_%s" % [style, sfx], c.x, c.y, yaw)

# двор у центра site: пробует сместить по кругу, пока не найдётся место вне дороги/воды и без наложения на другие дворы
var _yards: Array = []
func _yard_near(site: Vector2, dx: float, dy: float, yaw: float, w: float, d: float, house: String, maxr := 30.0) -> bool:
	var base := Vector2(dx, dy)
	if base.length() < 7.0:
		base = (base if base.length() > 0.1 else Vector2(1, 0)).normalized() * 7.5
	for k in [0.0, 25.0, -25.0, 50.0, -50.0, 80.0, -80.0, 120.0, -120.0, 160.0, 200.0, 240.0, 280.0]:
		var off := base.rotated(deg_to_rad(k))
		var c := site + off
		var ok := WorldGen.path_dist(c.x, c.y) > 5.5 and WorldGen.terrain(c.x, c.y)[1] < 0.02
		for q in _yards:
			if c.distance_to(q[0]) < (w + q[1]) * 0.5 * 0.95:
				ok = false
		if ok:
			_yards.append([c, w])
			_yard(c.x, c.y, yaw + (k if k != 0.0 else 0.0) * 0.0, w, d, house)
			return true
	return false

func _yard(cx: float, cy: float, yaw: float, w: float, d: float, house: String, style := "", broken := 0.5, garden := true) -> void:
	var th := deg_to_rad(yaw)
	var c := Vector2(cx, cy)
	if style == "":
		style = FENCE_STYLES[_rng.randi() % 2] if _rng.randf() < 0.75 else "board"
	var hd: float = HD.get(house, 2.5)
	put(house, _loc(c, th, 0, d / 2.0 - 2.6 - hd).x, _loc(c, th, 0, d / 2.0 - 2.6 - hd).y, yaw)
	# забор: передняя сторона с воротами (ворота — слева от центра)
	var gx := -w * 0.25
	var fl := _loc(c, th, -w / 2.0, d / 2.0)
	var fr := _loc(c, th, w / 2.0, d / 2.0)
	var bl := _loc(c, th, -w / 2.0, -d / 2.0)
	var br := _loc(c, th, w / 2.0, -d / 2.0)
	_fence_line(fl, fr, style, broken, w * 0.5 + gx - 1.7, w * 0.5 + gx + 1.7)
	var gp := _loc(c, th, gx, d / 2.0)
	put("gate_wood", gp.x, gp.y, yaw)
	_fence_line(bl, br, style, broken)
	_fence_line(bl, fl, style, broken)
	_fence_line(br, fr, style, broken)
	if garden and d >= 10.0:
		var gpos := _loc(c, th, 0.5, -d / 2.0 + 3.4)
		if WorldGen.path_dist(gpos.x, gpos.y) > 3.6: put("garden_a" if _rng.randf() < 0.6 else "garden_b", gpos.x, gpos.y, yaw)
	if w >= 12.0 and _rng.randf() < 0.7:
		var wp := _loc(c, th, w / 2.0 - 2.2, d / 2.0 - 4.0)
		put("well_a" if _rng.randf() < 0.5 else "well_b", wp.x, wp.y, yaw + _rng.randf_range(-20, 20))
	if _rng.randf() < 0.8:
		var sp := _loc(c, th, -w / 2.0 + 2.6, -d / 2.0 + 2.4)
		put(["shed_blue", "shed_green", "open_shed"][_rng.randi() % 3], sp.x, sp.y, yaw)
	if _rng.randf() < 0.5:
		var op := _loc(c, th, w / 2.0 - 1.4, -d / 2.0 + 1.4)
		put("outhouse", op.x, op.y, yaw + 180.0)
	if _rng.randf() < 0.5:
		var wpo := _loc(c, th, -w / 2.0 + 3.2, d / 2.0 - 6.5)
		put("woodpile", wpo.x, wpo.y, yaw + 90.0)

# крупную постройку — на кольцо вокруг центра, смещая по углу, пока не найдётся место вне дороги (фасадом к центру)
func _free_put(model: String, site: Vector2, r: float, ang0: float, yaw_extra := 0.0) -> bool:
	var rad: float = RAD.get(model, FOOT.get(model, 3.0))
	for i in 12:
		var ang := deg_to_rad(ang0 + (i / 2 + 1) * 30.0 * (1 if i % 2 == 0 else -1) if i > 0 else ang0)
		var p := site + Vector2(cos(ang), sin(ang)) * r
		if WorldGen.path_dist(p.x, p.y) < rad * 0.55 + 1.6:
			continue
		if put(model, p.x, p.y, rad_to_deg(atan2(-cos(ang), -sin(ang))) + yaw_extra):
			return true
	return false

# ---------------- локации и хутора ----------------
func _locations() -> void:
	for key in LOCS:
		var f: Dictionary = WorldGen.FEATURES[key]
		for p in LOCS[key]:
			put(p[0], f.x + p[1], f.y + p[2], p[3])
	# дворы деревни
	var v: Dictionary = WorldGen.FEATURES["village"]
	var vc := Vector2(v.x, v.y)
	var models := ["house_izba_a", "house_izba_c", "house_izba_b", "house_brick_small", "house_cabin", "house_izba_a", "house_dacha_d", "house_izba_b", "house_izba_c", "house_cabin", "house_dacha_b"]
	for i in models.size():
		var ring2 := i >= 6
		var rr := 20.0 if ring2 else 13.5
		var ang := deg_to_rad(15.0 + (i - 6) * 72.0 + 36.0 if ring2 else 15.0 + i * 60.0)
		var yaw := rad_to_deg(atan2(-cos(ang), -sin(ang)))          # фасадом к центру деревни
		_yard_near(vc, cos(ang) * rr, sin(ang) * rr, yaw, 11.5, 11.0, models[i])
	_free_put("club", vc, 7.5, 250.0); _free_put("shop", vc, 8.0, 100.0); _free_put("chapel", vc, 17.0, 200.0)
	var fm: Dictionary = WorldGen.FEATURES["farm"]
	_yard_near(Vector2(fm.x, fm.y), 13, 12, 180, 12, 10, "house_cabin")
	var lb: Dictionary = WorldGen.FEATURES["lakebase"]
	_yard_near(Vector2(lb.x, lb.y), -8, 5, 90, 11, 10, "house_cabin")

func _hamlets() -> void:
	for key in HAMLETS:
		var h: Dictionary = WorldGen.HAMLETS[key]
		var s: Dictionary = HAMLETS[key]
		for yd in s.yards:
			_yard_near(Vector2(h.x, h.y), yd[1], yd[2], yd[3], yd[4], yd[5], yd[0], h.r - 3.0)
		for p in s.ext:
			put(p[0], h.x + p[1], h.y + p[2], p[3])
	var dz: Dictionary = WorldGen.HAMLETS["h_dachi"]
	for p in DACHAS:
		if WorldGen.path_dist(dz.x + p[1], dz.y + p[2]) < 4.0:
			continue
		_yard(dz.x + p[1], dz.y + p[2], p[3], 9, 9, p[0], "picket", 0.5, false)
		var tp := _loc(Vector2(dz.x + p[1], dz.y + p[2]), deg_to_rad(p[3]), 2.8, -2.4)
		put("greenhouse" if _rng.randf() < 0.4 else "woodpile", tp.x, tp.y, p[3])
	put("car_sedan_yellow", dz.x - 3, dz.y + 0.3, 5)
	put("car_van_orange", dz.x + 6, dz.y - 0.2, 190)

func _rings() -> void:
	for r in RINGS:
		var f: Dictionary = WorldGen.FEATURES[r[0]]
		var rad: float = r[1]
		var a0: float = r[3]
		var a1: float = r[4]
		var n := roundi(deg_to_rad(a1 - a0) * rad / 2.99)
		for i in n:
			var ang := deg_to_rad(a0 + (a1 - a0) * (i + 0.5) / n)
			if r[5] > 0 and (i % int(r[5])) == 0:
				continue
			var p := Vector2(f.x + cos(ang) * rad, f.y + sin(ang) * rad)
			var yaw := rad_to_deg(atan2(-cos(ang), -sin(ang))) * 1.0
			yaw = -rad_to_deg(ang) - 90.0
			var sfx := "b" if _rng.randf() < 0.35 else "a"
			var nm := "%s_%s" % [r[2], sfx]
			if path_blocked(p):
				continue
			put(nm, p.x, p.y, yaw)

func path_blocked(p: Vector2) -> bool:
	return WorldGen.path_dist(p.x, p.y) < 1.6

# ---------------- вдоль дорог ----------------
func _near_site(p: Vector2, pad: float) -> bool:
	for key in WorldGen.FEATURES:
		var f: Dictionary = WorldGen.FEATURES[key]
		if Vector2(p.x - f.x, p.y - f.y).length() < f.r + pad:
			return true
	for key in WorldGen.HAMLETS:
		var h: Dictionary = WorldGen.HAMLETS[key]
		if Vector2(p.x - h.x, p.y - h.y).length() < h.r + pad:
			return true
	return false

func _road_stuff() -> void:
	var ri := 0
	for rd in WorldGen._roads:
		var pts: PackedVector2Array = rd.pts
		var track: bool = rd.track
		# столбы вдоль дороги (на просёлках — реже)
		var acc := 0.0
		for i in pts.size() - 1:
			var seg := pts[i + 1] - pts[i]
			var L := seg.length()
			var dir := seg / maxf(L, 1e-3)
			var d := 0.0
			while d < L:
				if acc <= 0.0:
					var p := pts[i] + dir * d + Vector2(-dir.y, dir.x) * 3.4
					if not _near_site(p, 2.0) and not (track and _rng.randf() < 0.6):
						put("pole_wood", p.x, p.y, rad_to_deg(atan2(-dir.y, dir.x)) + 90.0)
					acc = 14.0
				d += 3.0
				acc -= 3.0
		# брошенные машины
		var n := (1 if track else 2) + (ri % 2)
		ri += 1
		for k in n:
			var i2 := 1 + _rng.randi() % (pts.size() - 3)
			var dir2 := (pts[i2 + 1] - pts[i2]).normalized()
			var p2 := pts[i2] + dir2 * _rng.randf() * 3.0 + Vector2(-dir2.y, dir2.x) * _rng.randf_range(-1.3, 1.3)
			if _near_site(p2, 3.0):
				continue
			var yaw := rad_to_deg(atan2(-dir2.y, dir2.x)) + (0.0 if _rng.randf() < 0.5 else 180.0) + _rng.randf_range(-16.0, 16.0)
			if _rng.randf() < 0.25:
				yaw += _rng.randf_range(40.0, 70.0)
			put(CARS[_rng.randi() % CARS.size()], p2.x, p2.y, yaw)
		# остановка на въезде в локацию
		if not track and ri % 2 == 1:
			var ip := pts.size() - 2
			var dd := (pts[ip + 1] - pts[ip]).normalized()
			var bp := pts[ip] - dd * 4.0 + Vector2(-dd.y, dd.x) * 3.0
			if not _near_site(bp, 1.0):
				put("bus_stop", bp.x, bp.y, rad_to_deg(atan2(-dd.y, dd.x)) + 90.0)

# ---------------- поля: стога, тюки, брошенная техника ----------------
func _fields() -> void:
	var placed: Array = []
	var tries := 0
	while placed.size() < 46 and tries < 3000:
		tries += 1
		var p := Vector2(_rng.randf_range(-205, 205), _rng.randf_range(-205, 205))
		if WorldGen.forest_mask(p.x, p.y) > 0.04 or WorldGen.forest_bias(p.x, p.y) > 0.34:
			continue
		if _near_site(p, 5.0) or WorldGen.path_dist(p.x, p.y) < 3.0:
			continue
		var ok := true
		for q in placed:
			if p.distance_to(q) < 22.0:
				ok = false
				break
		if not ok:
			continue
		var r := _rng.randf()
		var m: String = "haystack" if r < 0.5 else ("bales_round" if r < 0.75 else ("bales_square" if r < 0.85 else ["tractor_red", "tractor_blue", "car_truck_blue", "trailer_cart"][_rng.randi() % 4]))
		if put(m, p.x, p.y, _rng.randf() * 360.0):
			placed.append(p)
			if m == "haystack" and _rng.randf() < 0.6:
				put("haystack", p.x + 5.0, p.y + 2.0, 0.0)

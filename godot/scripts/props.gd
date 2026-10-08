extends Node3D
# Постройки, заборы, огороды, машины и мелочь по всей карте. Модели — assets/props/props.glb (Blender: tools/props, дома — tools/houses),
# каждая — отдельный узел-меш; у домов крыша — отдельный узел «<имя>_roof» (ставится вместе с домом).
# Всё ставится один раз при запуске, одинаковые модели собраны в MultiMesh по клеткам карты.
# Координаты — тайлы (0,837 м); yaw в градусах. Дом: фасад (крыльцо) смотрит в +y карты при yaw 0; машина: нос в +x при yaw 0.
# Поселения — улицами: участки вдоль дорог, дом фасадом к улице, за ним двор и огород, между участками — забор.
# Каждый участок и постройка записываются в WorldGen.add_clear — там не растут деревья и кусты (сады — WorldGen.add_tree).

const S := 1.0                        # модели в настоящем размере (было 0,8)
const K := 1.25                       # старые смещения и радиусы (подобраны под 0,8) — увеличить
const CELL := 40.0
const T := WorldGen.T
const M := 1.0 / WorldGen.T           # тайлов в метре
const CARS := ["car_sedan_red", "car_sedan_blue", "car_sedan_white", "car_sedan_burnt", "car_sedan_green", "car_sedan_yellow", "car_van_olive", "car_van_white", "car_van_orange", "car_truck_blue", "car_truck_green", "car_bus_yellow", "car_bus_blue", "tractor_blue", "tractor_red"]
const YARD_CARS := ["car_sedan_red", "car_sedan_blue", "car_sedan_white", "car_sedan_green", "car_van_white", "car_van_olive"]
# дома (tools/houses/house.py): длина по фасаду, глубина, вынос крыльца с ступенями — метры
const HOUSE := {"house_izba_a": [8.0, 6.6, 2.4], "house_izba_b": [7.2, 6.2, 2.0], "house_izba_c": [7.6, 6.4, 2.3], "house_brick": [10.0, 8.4, 2.3],
	"house_brick_small": [8.0, 7.0, 2.1], "house_new_a": [10.0, 9.0, 2.2], "house_new_b": [9.0, 8.0, 2.4], "house_cottage": [10.0, 10.0, 2.6],
	"house_dacha_a": [6.0, 5.0, 2.0], "house_dacha_b": [6.4, 5.2, 1.9], "house_dacha_c": [5.6, 5.0, 1.6], "house_dacha_d": [6.0, 5.4, 1.8],
	"house_cabin": [6.0, 5.0, 1.7], "house_banya": [4.6, 4.0, 0.4]}
# радиус занятости (тайлы, в масштабе 0,8 — умножается на K)
const FOOT := {"club": 7.0, "barn": 7.5, "barn_long": 13.0, "barracks": 11.0, "sawmill_hall": 9.0, "machine_shed": 11.0, "shop": 5.0, "bunker_entrance": 6.0,
	"chapel": 3.0, "silo_conc": 2.4, "silo_metal": 2.4, "water_tower": 2.2, "radio_mast": 1.8, "transmitter": 4.5, "fuel_tank": 3.0}
const RAD := {"shed_blue": 2.4, "shed_green": 2.4, "open_shed": 3.4, "greenhouse": 2.6, "boat_shed": 4.2, "outhouse": 1.0, "well_a": 1.1, "well_b": 1.1, "tent_army": 2.6, "tent_tan": 2.6,
	"tarp_shelter": 2.4, "log_pile": 4.3, "lumber_stack": 2.6, "pier": 6.5, "container_g": 3.3, "container_b": 3.3, "container_r": 3.3, "checkpoint": 4.6, "mil_tower": 2.0,
	"sandbag_nest": 2.8, "watch_tower": 1.8, "generator_shed": 3.0, "sawdust": 2.6, "cellar": 2.2, "haystack": 2.2}
var _occ: Array = []

# хутора: какие дома (по порядку вдоль улицы) и что вокруг [модель, dx, dy, yaw]
const HAMLETS := {
	"h_stone": {"houses": ["house_izba_b"], "kind": "old", "ext": [["haystack", -8, 6, 0], ["tires", -9, -5, 20]]},
	"h_pond": {"houses": ["house_cabin"], "kind": "old", "ext": [["well_b", 5, 4, 0], ["nets", -7, 5, 40], ["boat_row_up", -5, -6, 20]]},
	"h_vyselki": {"houses": ["house_izba_a", "house_dacha_d", "house_cabin", "house_izba_c"], "kind": "old", "ext": [["haystack", -11, 6, 0], ["pole_wood", 0, -9, 0]]},
	"h_zarechye": {"houses": ["house_brick_small", "house_izba_c", "house_dacha_c", "house_new_b"], "kind": "old", "ext": [["woodpile", -11, 6, 0]]},
	"h_novo": {"houses": ["house_new_a", "house_izba_c", "house_brick_small"], "kind": "old", "ext": [["tractor_blue", -2, 6, 30], ["trailer_cart", -8, 4, 80], ["haystack", -9, -7, 0], ["bales_round", 9, -2, 0]]},
	"h_bereza": {"houses": ["house_izba_a", "house_izba_b", "house_cabin", "house_brick"], "kind": "old", "ext": [["haystack", 9, -5, 0]]},
	"h_ranger": {"houses": ["house_izba_c"], "kind": "old", "ext": [["watch_tower", -7, -4, 0], ["car_van_olive", -6, 5, 40]]},
	"h_hunter": {"houses": ["house_cabin"], "kind": "old", "ext": [["fish_rack", -3, 4, 0]]},
	"h_sosn": {"houses": ["house_izba_b", "house_izba_a"], "kind": "old", "ext": [["log_heap", 3, 5, 20], ["log_heap", -6, 6, 100], ["haystack", 7, 4, 0]]},
	"h_cem": {"houses": [], "kind": "old", "ext": [["chapel", 0, -2, 0], ["graves", -6, 1, 0], ["graves", 2, 4, 0], ["fence_rails_b", 0, 7, 0], ["fence_rails_a", 3, 7, 0]]},
	"h_yuzhny": {"houses": ["house_izba_a", "house_dacha_a", "house_brick_small"], "kind": "old", "ext": [["tractor_red", -6, 6, 140], ["haystack", 9, -6, 0], ["bales_square", 1, 8, 0]]},
	"h_dachi": {"houses": ["house_dacha_a", "house_dacha_b", "house_dacha_c", "house_dacha_d", "house_dacha_b", "house_dacha_a", "house_dacha_d", "house_dacha_c"], "kind": "dacha", "ext": [["car_sedan_yellow", -3, 0.3, 5]]},
	"h_poselok": {"houses": ["house_new_a", "house_new_b", "house_cottage", "house_brick", "house_new_a", "house_new_b", "house_brick_small", "house_cottage", "house_new_b", "house_new_a"], "kind": "new",
		"ext": [["bus_stop", 3, -6, 0], ["well_a", -3, 5, 0]]},
}
const VILLAGE_HOUSES := ["house_izba_a", "house_izba_c", "house_brick", "house_izba_b", "house_brick_small", "house_izba_a", "house_new_b", "house_cabin", "house_izba_c", "house_brick",
	"house_izba_b", "house_new_a", "house_izba_a", "house_dacha_d", "house_izba_c", "house_brick_small", "house_izba_b", "house_cabin"]

# локации (смещения от центра, тайлы, в масштабе 0,8 — умножаются на K; причал и лодки — без умножения, они у воды)
const LOCS := {
	"camp": [["tent_army", -4, -3, 10], ["tent_army", -5, 2.5, -20], ["tent_tan", 3.5, -5, 160], ["tarp_shelter", 5, 3, 15], ["campfire", 0, 0, 0], ["bench_log", -2.4, 2.2, 0], ["bench_log", 2.6, -1.8, 90],
		["bench_log", 1.4, 3.0, 20], ["camp_table", -8, -0.5, 80], ["barricade", 0, -9.5, 0], ["barricade", 7, -7, 40], ["barricade", -7, -7.5, -40], ["barricade", 9.5, 1, 90], ["watch_tower", 9, -8, 0], ["clothesline", -2, 7, 0],
		["sandbags", 7, 7, -20], ["barrels_a", -8, 6, 0], ["crates", 8, 0, 0], ["car_van_olive", -9, -6, 160], ["woodpile", 4.5, 8, 180]],
	"village": [["well_a", -3.5, -2.5, 0], ["car_bus_yellow", 4, 1.2, 12], ["car_sedan_burnt", -6, 2.0, 160], ["tractor_blue", -2, -5, 70], ["barrels_b", 6, -4, 0]],
	"sawmill": [["sawmill_hall", 0, -2, 0], ["log_pile", -9, 6, 0], ["log_pile", -9, 10, 0], ["lumber_stack", 8, 7, 0], ["lumber_stack", 8, 10, 0], ["lumber_stack", 12, 7, 0], ["sawdust", 7, -8, 0], ["log_heap", -3, 9, 30], ["log_heap", 4, 11, -20],
		["house_cabin", -11, -8, 30], ["car_truck_logs", 11, 2, 160], ["tractor_red", 5, 13, 140], ["barrels_a", -12, -3, 0], ["woodpile", -14, 0, 90]],
	"lakebase": [["pier", 8.5, 0.5, 0], ["boat_row_wood", 5.5, -1.5, 15], ["boat_row_up", 4, 3.5, -25], ["boat_motor", 6.5, 5, 80], ["boat_row_blue", 5.2, -5.5, 5], ["boat_shed", -3, -6, 0], ["fish_rack", 1, 6, 0], ["nets", -4.5, 4.5, 20], ["house_cabin", -9, 2, 90],
		["house_banya", -6, -9, 10], ["car_sedan_white", 2, 9, 200], ["barrels_b", -1, 2, 0], ["woodpile", -10, 8, 0], ["crates", 3, -8, 0], ["well_b", -8, -3, 0]],
	"farm": [["barn_long", -9, -11, 0], ["barn", 10, -13, 0], ["silo_conc", -1, -13, 0], ["silo_conc", -1, -17, 0], ["silo_metal", 4, -17, 0], ["water_tower", 15, 0, 0], ["machine_shed", 6, 9, 0], ["fuel_tank", -15, 5, 10],
		["house_brick", -15, -2, 90], ["tractor_blue", -1, 4, 30], ["tractor_red", -6, 8, 120], ["trailer_cart", 3, 7, 80], ["bales_round", 12, 6, 0], ["bales_round", 17, 5, 0], ["bales_square", -12, 12, 0], ["car_truck_green", -4, 2, 200],
		["car_van_white", -9, 3, 40], ["haystack", 17, -10, 0], ["barrels_a", -11, -6, 0], ["tires", 9, 14, 0]],
	"tower": [["radio_mast", 0, 0, 0], ["transmitter", -7, 4, 0], ["generator_shed", -10, -3, 0], ["dish", 6, -4, 0], ["car_van_white", 8, 6, 210], ["barrels_a", -8, -1, 0], ["woodpile", -4, -8, 0]],
}
# ограда локаций по окружности: [локация, радиус (×K), модель-секция, от°, до°, пропуск (каждая N-я секция)]
const RINGS := [["tower", 9.5, "fence_chain", 0, 360, 7], ["lakebase", 12.0, "fence_rails", 90, 270, 0], ["sawmill", 14.5, "fence_board", 60, 300, 0], ["farm", 20.0, "fence_rails", 200, 340, 0]]
const FENCE_LEN := {"fence_picket": 2.6, "fence_rails": 2.7, "fence_board": 2.65, "fence_chain": 3.4, "fence_prof": 2.5, "fence_mil": 3.0}   # длина секции, м

var _meshes := {}
var _batch := {}
var _rng := RandomNumberGenerator.new()
var _n := 0
var _plots: Array = []                # участки: [центр, угол, полуширина, полуглубина]
var _rej := {}                        # отказы участков по причинам (для проверки)
var _last := ""

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	_rng.seed = 20261008
	_load()
	_bunker()
	_locations()
	_hamlet("h_poselok")                  # новый посёлок — первым: ему нужно поле целиком
	_village()
	for key in HAMLETS:
		if key != "h_poselok":
			_hamlet(key)
	_rings()
	_forest_houses()
	_road_stuff()
	_fields()
	_flush()
	print("props: ", _n, " партий ", _batch.size(), " участков ", _plots.size(), " за ", Time.get_ticks_msec() - t0, " мс; отказы участков: ", _rej)

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
			elif mat is BaseMaterial3D and str(mat.resource_name) == "glass":
				mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED          # стекло — тёмное зеркальное, без сортировки прозрачности
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

func _rad(model: String) -> float:
	if HOUSE.has(model):
		var hd: Array = HOUSE[model]
		return maxf(hd[0], hd[1] + hd[2]) * 0.5 * M
	if model.begins_with("car_"):
		return 2.6 * M * 1.2
	if model.begins_with("tractor") or model.begins_with("trailer"):
		return 2.5
	return float(RAD.get(model, FOOT.get(model, 3.0))) * K

# ---------------- установка предмета ----------------
func put(model: String, tx: float, ty: float, yaw_deg: float, mode := "", occ := true) -> bool:
	if not _meshes.has(model):
		return false
	var t := WorldGen.terrain(tx, ty)
	var wet_ok := model == "pier" or model.begins_with("boat")
	if (t[1] > 0.02 and not wet_ok) or t[2] > 0.6:
		return false
	var th := deg_to_rad(yaw_deg)
	var yb := Basis(Vector3.UP, th)
	var y: float
	var house := HOUSE.has(model)
	var solid := house or FOOT.has(model) or RAD.has(model) or model.begins_with("car_") or model.begins_with("tractor") or model.begins_with("trailer") or model.begins_with("tent")
	if occ and not house:
		for q in _plots:                                              # внутрь чужого двора — нельзя
			if _rect_overlap([Vector2(tx, ty), 0.0, 0.6, 0.6], q):
				return false
	if solid and occ:
		var rr := _rad(model)
		for o in _occ:
			if Vector2(tx, ty).distance_to(o[0]) < (rr + o[1]) * 0.66:
				return false
		_occ.append([Vector2(tx, ty), rr])
		if not house:
			WorldGen.add_clear(tx, ty, rr * 0.8, rr * 0.8, 0.0)      # под постройкой не растут деревья
	if mode == "":
		mode = "tilt" if (model.begins_with("car_") or model.begins_with("tractor") or model.begins_with("trailer")) else ("fence" if model.begins_with("fence") else ("min" if (house or FOOT.has(model) or model.begins_with("shed") or model == "open_shed" or model == "boat_shed" or model == "greenhouse" or model == "concrete_pad") else "pt"))
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
		var rad := _rad(model) * 0.8
		y = _h(tx, ty)
		for k in 4:
			var a := k * PI / 2.0 + 0.7
			y = minf(y, _h(tx + cos(a) * rad, ty + sin(a) * rad))
		y -= 0.12
	else:
		y = _h(tx, ty) - 0.01
	if model.begins_with("pole_"):
		yb = yb * Basis(Vector3(1, 0, 0), _rng.randf_range(-0.05, 0.05)) * Basis(Vector3(0, 0, 1), _rng.randf_range(-0.05, 0.05))
	var xf := Transform3D(yb * S, Vector3(tx * T, y, ty * T))
	_add(model, tx, ty, xf)
	if _meshes.has(model + "_roof"):
		_add(model + "_roof", tx, ty, xf)                             # крыша — отдельный узел (спрячем, когда герой внутри)
	_n += 1
	return true

func _add(model: String, tx: float, ty: float, xf: Transform3D) -> void:
	var key := "%s|%d|%d" % [model, int(floor(tx / CELL)), int(floor(ty / CELL))]
	if not _batch.has(key):
		_batch[key] = {"model": model, "xf": []}
	_batch[key].xf.append(xf)

# точка в системе участка: lx — вдоль фасада, ly — к улице (фасад смотрит в +ly)
func _loc(c: Vector2, th: float, lx: float, ly: float) -> Vector2:
	return c + Vector2(cos(th), -sin(th)) * lx + Vector2(sin(th), cos(th)) * ly

func _fence_line(p0: Vector2, p1: Vector2, model: String, broken: float, skip_from := 0.0, skip_to := 0.0) -> void:
	var len := p0.distance_to(p1)
	var sl: float = FENCE_LEN.get(model, 2.6) * M
	var n := maxi(1, roundi(len / sl))
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
		put("%s_%s" % [model, sfx], c.x, c.y, yaw)

# ---------------- участки ----------------
func _rect_overlap(a: Array, b: Array) -> bool:
	# пересечение повёрнутых прямоугольников [центр, угол, полуширина, полуглубина] (теорема о разделяющей оси)
	var axes := []
	for r in [a, b]:
		var th: float = r[1]
		axes.append(Vector2(cos(th), -sin(th)))
		axes.append(Vector2(sin(th), cos(th)))
	for ax in axes:
		var pa := _proj(a, ax)
		var pb := _proj(b, ax)
		if pa.y < pb.x or pb.y < pa.x:
			return false
	return true

func _proj(r: Array, ax: Vector2) -> Vector2:
	var th: float = r[1]
	var ex := Vector2(cos(th), -sin(th)) * float(r[2])
	var ey := Vector2(sin(th), cos(th)) * float(r[3])
	var c: float = (r[0] as Vector2).dot(ax)
	var e := absf(ex.dot(ax)) + absf(ey.dot(ax))
	return Vector2(c - e, c + e)

func _plot_ok(c: Vector2, th: float, w: float, d: float, own: String) -> bool:
	var rect := [c, th, w / 2.0, d / 2.0]
	for q in _plots:
		if _rect_overlap(rect, q):
			_rej["участок"] = _rej.get("участок", 0) + 1; _last = "участок " + str(q)
			return false
	for i in 5:
		for j in 5:
			var p := _loc(c, th, (i / 4.0 - 0.5) * w * 0.96, (j / 4.0 - 0.5) * d * 0.96)
			var t := WorldGen.terrain(p.x, p.y)
			if t[1] > 0.02 or t[2] > 0.5 or not WorldGen.in_map(p.x, p.y, 3.0):
				_rej["вода/скалы"] = _rej.get("вода/скалы", 0) + 1; _last = "вода/скалы"
				return false
			if j < 4 and WorldGen.path_dist(p.x, p.y) < 2.2:         # другая дорога через участок (передняя кромка — у своей улицы)
				_rej["дорога"] = _rej.get("дорога", 0) + 1; _last = "дорога"
				return false
	for key in WorldGen.FEATURES:
		if key == own:
			continue
		var f: Dictionary = WorldGen.FEATURES[key]
		if c.distance_to(Vector2(f.x, f.y)) < f.r * K + maxf(w, d) * 0.5:
			_rej["локация " + key] = _rej.get("локация " + key, 0) + 1; _last = "локация " + key
			return false
	for o in _occ:
		if c.distance_to(o[0]) < o[1] + minf(w, d) * 0.45:
			_rej["постройка"] = _rej.get("постройка", 0) + 1; _last = "постройка"
			return false
	return true

# участок: kind — old (деревенский), new (новый дом), dacha
func _plot(c: Vector2, yaw: float, w: float, d: float, house: String, kind: String) -> void:
	var th := deg_to_rad(yaw)
	_plots.append([c, th, w / 2.0, d / 2.0])
	WorldGen.add_clear(c.x, c.y, w / 2.0, d / 2.0, th)
	var hd: Array = HOUSE[house]
	var hl: float = hd[0] * M
	var hdp: float = hd[1] * M
	var por: float = hd[2] * M
	var side := -1.0 if _rng.randf() < 0.5 else 1.0                 # дом — у одной боковой стороны, подъезд — у другой
	var hx := side * (w / 2.0 - hl / 2.0 - 1.6 * M)
	var hy := d / 2.0 - 3.0 * M - por - hdp / 2.0
	var hp := _loc(c, th, hx, hy)
	put(house, hp.x, hp.y, yaw, "", false)
	_occ.append([hp, maxf(hl, hdp) * 0.5])
	# забор: спереди — ворота у подъезда (с другой стороны от дома)
	var style: String = "fence_prof" if kind == "new" else ("fence_picket" if kind == "dacha" else ["fence_picket", "fence_rails", "fence_board"][_rng.randi() % 3])
	var broken := 0.15 if kind == "new" else 0.5
	var gx := -side * (w / 2.0 - 2.4 * M)
	var fl := _loc(c, th, -w / 2.0, d / 2.0)
	var fr := _loc(c, th, w / 2.0, d / 2.0)
	var bl := _loc(c, th, -w / 2.0, -d / 2.0)
	var br := _loc(c, th, w / 2.0, -d / 2.0)
	_fence_line(fl, fr, style, broken, w * 0.5 + gx - 1.9 * M, w * 0.5 + gx + 1.9 * M)
	var gp := _loc(c, th, gx, d / 2.0)
	if kind != "new" or _rng.randf() < 0.5:
		put("gate_wood", gp.x, gp.y, yaw, "", false)
	_fence_line(bl, br, style, broken)
	_fence_line(bl, fl, style, broken)
	_fence_line(br, fr, style, broken)
	# задний двор: от задней стены дома до задней границы
	var back0 := hy - hdp / 2.0 - 1.0 * M                             # сразу за домом
	var back1 := -d / 2.0 + 0.8 * M
	var room := back0 - back1
	# огород (грядки) — в глубине участка
	if room > 6.0 * M:
		var gpos := _loc(c, th, -side * 1.0 * M, back1 + 2.6 * M)
		put("garden_a" if _rng.randf() < 0.6 else "garden_b", gpos.x, gpos.y, yaw + 90.0 * float(_rng.randi() % 2), "", false)
	# сарай — в углу за домом, со стороны дома
	if room > 7.0 * M and _rng.randf() < 0.85:
		var shed: String = ["shed_blue", "shed_green", "open_shed"][_rng.randi() % 3]
		var sp := _loc(c, th, side * (w / 2.0 - 3.4 * M), back0 - 3.4 * M)
		put(shed, sp.x, sp.y, yaw + (90.0 if shed != "open_shed" else 0.0), "", false)
	# туалет — в дальнем углу (у старых домов)
	if kind != "new" and _rng.randf() < 0.75:
		var op := _loc(c, th, -side * (w / 2.0 - 1.0 * M), back1 + 1.0 * M)
		put("outhouse", op.x, op.y, yaw + 180.0, "", false)
	# баня или теплица
	var r2 := _rng.randf()
	if kind == "old" and r2 < 0.35 and room > 9.0 * M:
		var bp := _loc(c, th, -side * (w / 2.0 - 3.0 * M), back0 - 3.0 * M)
		put("house_banya", bp.x, bp.y, yaw + 90.0 * side, "", false)
	elif (kind != "old" or r2 > 0.7) and room > 7.0 * M:
		var tp := _loc(c, th, -side * (w / 2.0 - 4.5 * M), back1 + 6.5 * M)
		put("greenhouse", tp.x, tp.y, yaw, "", false)
	# поленница вдоль боковой стены, колодец во дворе
	if kind != "new" and _rng.randf() < 0.7:
		var wp := _loc(c, th, side * (w / 2.0 - 0.9 * M), hy - hdp / 2.0 - 0.5 * M)
		put("woodpile", wp.x, wp.y, yaw + 90.0, "", false)
	if kind == "old" and _rng.randf() < 0.4:
		var wl := _loc(c, th, -side * (w / 2.0 - 2.0 * M), hy)
		put("well_a" if _rng.randf() < 0.5 else "well_b", wl.x, wl.y, yaw + _rng.randf_range(-20, 20), "", false)
	# машина на подъезде, носом к улице
	if _rng.randf() < (0.7 if kind == "new" else 0.22):
		var cp := _loc(c, th, gx, d / 2.0 - 4.2 * M)
		put(YARD_CARS[_rng.randi() % YARD_CARS.size()], cp.x, cp.y, yaw - 90.0 + _rng.randf_range(-6, 6), "", false)
	# сад: 1–2 яблони у огорода (подальше от построек)
	if room > 8.0 * M:
		for k in (1 + _rng.randi() % 2):
			var ap := _loc(c, th, -side * (w / 2.0 - (2.5 + k * 5.0) * M), back1 + 6.0 * M + k * 1.5 * M)
			WorldGen.add_tree(ap.x, ap.y, WorldGen.APPLE[_rng.randi() % WorldGen.APPLE.size()])

func _diff(before: String) -> String:
	return str(_rej).replace(before, "")

# точка и направление на полилинии на расстоянии s от начала
func _at(pts: PackedVector2Array, s: float) -> Array:
	var acc := 0.0
	for i in pts.size() - 1:
		var seg := pts[i + 1] - pts[i]
		var L := seg.length()
		if acc + L >= s:
			var u := (s - acc) / maxf(L, 1e-4)
			return [pts[i] + seg * u, seg / maxf(L, 1e-4)]
		acc += L
	var last := pts.size() - 1
	return [pts[last], (pts[last] - pts[last - 1]).normalized()]

# направление главной дороги из site (первая дорога, начинающаяся у site)
func _road_dir(site: Vector2) -> Vector2:
	for rd in WorldGen._roads:
		var pts: PackedVector2Array = rd.pts
		if pts[0].distance_to(site) < 4.0:
			return (pts[3] - pts[0]).normalized()
		if pts[pts.size() - 1].distance_to(site) < 4.0:
			return (pts[pts.size() - 4] - pts[pts.size() - 1]).normalized()
	return Vector2(1, 0)

# прямая улица через центр поселения: участки по обе стороны; улица добавляется в дороги мира (рисуется на земле)
func _street(site: Vector2, own: String, dir: Vector2, half_len: float, free_r: float, houses: Array, kind: String, w: float, d: float, cap := 999) -> int:
	if houses.is_empty():
		return 0
	# въездные дороги, идущие вдоль улицы, внутри поселения выпрямляются по улице (иначе петляют через дворы)
	for rd in WorldGen._roads:
		var rp: PackedVector2Array = rd.pts
		if rp.size() < 5 or (rp[0].distance_to(site) > 4.0 and rp[rp.size() - 1].distance_to(site) > 4.0):
			continue
		var ends_at0 := rp[0].distance_to(site) <= 4.0
		var rdir := ((rp[3] - rp[0]) if ends_at0 else (rp[rp.size() - 4] - rp[rp.size() - 1])).normalized()
		if absf(rdir.dot(dir)) < cos(deg_to_rad(40.0)):
			continue
		var np := PackedVector2Array()
		var bb := Rect2(rp[0], Vector2.ZERO)
		for p in rp:
			var off := p - site
			var along := off.dot(dir)
			var k := clampf(1.0 - (off.length() - half_len) / 14.0, 0.0, 1.0)
			var q := p.lerp(site + dir * along, k)
			np.append(q)
			bb = bb.expand(q)
		rd["pts"] = np
		rd["bb"] = bb.grow(4.0)
	var a := site - dir * (half_len + 3.0)
	var b := site + dir * (half_len + 3.0)
	var pts := PackedVector2Array([a, site, b])
	WorldGen._roads.append({"pts": pts, "bb": Rect2(a, Vector2.ZERO).expand(b).grow(4.0), "track": true})
	var placed := 0
	var hi := 0
	var step := w + 1.5 * M
	var n := int(half_len * 2.0 / step)
	for sd: float in [1.0, -1.0]:
		for i in n:
			if placed >= cap:
				break
			var s := -half_len + (i + 0.5) * step
			if free_r > 0.0 and absf(s) < free_r + w * 0.5:
				continue                                           # площадь в центре
			var nrm := Vector2(-dir.y, dir.x) * sd
			var c := site + dir * s + nrm * (4.2 + d / 2.0)
			var fdir := -nrm                                       # фасад — к улице
			var th := atan2(fdir.x, fdir.y)
			var okp := _plot_ok(c, th, w, d, own)
			if OS.get_environment("PLOTDBG") == own:
				print("PLOT %s s=%.0f sd=%d c=(%.0f,%.0f) %s" % [own, s, sd, c.x, c.y, "ok" if okp else _last.substr(0, 40)])
			if okp:
				_plot(c, rad_to_deg(th), w, d, houses[hi % houses.size()], kind)
				hi += 1
				placed += 1
	return placed

# крупная постройка — на кольцо вокруг центра, смещая по углу, пока не найдётся место вне дороги (фасадом к центру)
func _free_put(model: String, site: Vector2, r: float, ang0: float, yaw_extra := 0.0) -> bool:
	var rad := _rad(model)
	for i in 12:
		var ang := deg_to_rad(ang0 + (i / 2 + 1) * 30.0 * (1 if i % 2 == 0 else -1) if i > 0 else ang0)
		var p := site + Vector2(cos(ang), sin(ang)) * r
		if WorldGen.path_dist(p.x, p.y) < rad * 0.55 + 1.6:
			continue
		if put(model, p.x, p.y, rad_to_deg(atan2(-cos(ang), -sin(ang))) + yaw_extra):
			return true
	return false

# ---------------- локации ----------------
func _locations() -> void:
	for key in LOCS:
		var f: Dictionary = WorldGen.FEATURES[key]
		for p in LOCS[key]:
			var k: float = 1.0 if (str(p[0]) == "pier" or str(p[0]).begins_with("boat")) else K
			put(p[0], f.x + p[1] * k, f.y + p[2] * k, p[3])

# деревня: площадь в центре (колодец, магазин, клуб, остановка), улицы вдоль всех дорог
func _village() -> void:
	var v: Dictionary = WorldGen.FEATURES["village"]
	var vc := Vector2(v.x, v.y)
	_free_put("shop", vc, 11.0, 100.0)
	_free_put("club", vc, 12.0, 250.0)
	_free_put("bus_stop", vc, 8.0, 10.0)
	WorldGen.add_clear(vc.x, vc.y, 13.0, 13.0, 0.0)                    # площадь
	var dv := _road_dir(vc)
	var got := _street(vc, "village", dv, 66.0, 12.0, VILLAGE_HOUSES, "old", 19.0, 30.0)                       # главная улица
	got += _street(vc, "village", dv.orthogonal(), 58.0, 12.0, VILLAGE_HOUSES.slice(7) + VILLAGE_HOUSES.slice(0, 7), "old", 19.0, 30.0)   # поперечная
	_rej["поставлено village"] = got

func _hamlet(key: String) -> void:
	if true:
		var h: Dictionary = WorldGen.HAMLETS[key]
		var s: Dictionary = HAMLETS[key]
		var c := Vector2(h.x, h.y)
		var n: int = s.houses.size()
		var w := 15.0 if s.kind == "dacha" else (22.0 if s.kind == "new" else 19.0)
		var d := 20.0 if s.kind == "dacha" else (28.0 if s.kind == "new" else 30.0)
		var got := 0
		var dir := _road_dir(c)
		if n > 6:                                                      # большой посёлок — две улицы крестом
			var n1 := n / 2
			var half1: float = ceilf(n1 / 2.0) * (w + 1.5 * M) * 0.5 + w + 4.0
			got = _street(c, key, dir, half1, 10.0, s.houses.slice(0, n1), s.kind, w, d, n1)
			got += _street(c, key, dir.orthogonal(), half1, 10.0, s.houses.slice(n1), s.kind, w, d, n - n1)
		else:
			var half: float = ceilf(n / 2.0) * (w + 1.5 * M) * 0.5 + w * 0.5 + 2.0
			got = _street(c, key, dir, half, 0.0, s.houses, s.kind, w, d, n)
		if OS.is_debug_build() and OS.has_feature("editor"):
			pass
		if got < n:                                                   # не встали вдоль улицы — по кольцу вокруг центра, фасадом к центру
			for rr: float in [10.0, 18.0, 26.0, 34.0]:
				for ai in 12:
					if got >= n:
						break
					var ang := ai * TAU / 12.0 + rr * 0.1
					var pc := c + Vector2(cos(ang), sin(ang)) * (rr + d * 0.5)
					var fd := (c - pc).normalized()
					var th2 := atan2(fd.x, fd.y)
					if _plot_ok(pc, th2, w, d, key):
						_plot(pc, rad_to_deg(th2), w, d, s.houses[got], s.kind)
						got += 1
		_rej["поставлено " + key] = "%d/%d" % [got, n]
		for p in s.ext:
			put(p[0], h.x + p[1] * K, h.y + p[2] * K, p[3])
		WorldGen.add_clear(c.x, c.y, 5.0, 5.0, 0.0)

# ---------------- бункер: бетонная площадка, военный периметр, вышки по углам, КПП у ворот на дорогу ----------------
func _bunker() -> void:
	var f: Dictionary = WorldGen.FEATURES["bunker"]
	var c := Vector2(f.x, f.y)
	# ворота — туда, куда уходит первая дорога
	var gdir := Vector2(0, 1)
	for rd in WorldGen._roads:
		var pts: PackedVector2Array = rd.pts
		if pts[0].distance_to(c) < 4.0:
			gdir = (pts[2] - pts[0]).normalized()
			break
		if pts[pts.size() - 1].distance_to(c) < 4.0:
			gdir = (pts[pts.size() - 3] - pts[pts.size() - 1]).normalized()
			break
	var th := atan2(gdir.x, gdir.y)                                   # локальная +y — к воротам
	var yaw := rad_to_deg(th)
	var hw := 21.0
	var hd := 18.0
	WorldGen.add_clear(c.x, c.y, hw + 4.0, hd + 4.0, th)
	put("concrete_pad", c.x, c.y, yaw, "pt")
	var L := func(lx: float, ly: float) -> Vector2: return _loc(c, th, lx, ly)
	# периметр: высокая сетка с колючкой, проём ворот на дороге
	var corners := [L.call(-hw, -hd), L.call(hw, -hd), L.call(hw, hd), L.call(-hw, hd)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		if i == 2:                                                    # передняя сторона (к дороге) — с воротами в центре
			_fence_line(a, b, "fence_mil", 0.12, hw - 3.2, hw + 3.2)
		else:
			_fence_line(a, b, "fence_mil", 0.12)
	for p in corners:
		var q: Vector2 = c + (p - c) * 0.93
		put("mil_tower", q.x, q.y, yaw)
	# КПП и блоки у ворот
	var g: Vector2 = L.call(0.0, hd)
	var kp: Vector2 = L.call(6.5, hd - 3.5)
	put("checkpoint", kp.x, kp.y, yaw + 90.0)
	for k in [-4.2, 4.2]:
		var jp: Vector2 = L.call(k, hd + 2.5)
		put("jersey", jp.x, jp.y, yaw, "pt", false)
	var bar: Vector2 = L.call(-1.0, hd + 4.5)
	put("jersey", bar.x, bar.y, yaw + 90.0, "pt", false)
	# внутри: вход в бункер в глубине, казарма и склад вдоль плаца, техника
	var items := [["bunker_entrance", 2.0, -9.0, 0.0], ["barracks", -12.5, -1.5, 90.0], ["container_g", 14.0, -12.0, 0.0], ["container_b", 14.0, -7.5, 0.0], ["container_r", 9.0, -14.0, 90.0],
		["car_truck_green", 9.0, 6.0, -90.0], ["car_truck_green", 13.0, 6.5, -95.0], ["car_van_olive", 6.0, 12.0, -80.0], ["sandbag_nest", -5.0, 11.0, 0.0], ["sandbags", 5.0, -2.0, 0.0],
		["barrels_b", 16.0, -1.0, 0.0], ["crates", 16.5, 2.0, 0.0], ["generator_shed", -1.0, -15.0, 0.0]]
	for it in items:
		var p2: Vector2 = L.call(it[1], it[2])
		put(it[0], p2.x, p2.y, yaw + it[3])

# ---------------- лесные дома: избы, заимки, брошенные дачи в лесу; полянка и тропа к ближайшей дороге ----------------
const FOREST_HOUSES := ["house_cabin", "house_cabin", "house_izba_b", "house_dacha_c", "house_cabin", "house_banya", "house_izba_c", "house_dacha_d"]
func _forest_houses() -> void:
	var cands: Array = []
	var x := -196.0
	while x <= 196.0:
		var y := -196.0
		while y <= 196.0:
			var p := Vector2(x + _rng.randf_range(-4, 4), y + _rng.randf_range(-4, 4))
			if WorldGen.forest_mask(p.x, p.y) > 0.22 and WorldGen.in_map(p.x, p.y, 16.0) and WorldGen.terrain(p.x, p.y)[1] < 0.01:
				var pd := WorldGen.path_dist(p.x, p.y)
				if pd > 12.0 and pd < 90.0 and not _near_site(p, 18.0):
					cands.append(p)
			y += 9.0
		x += 9.0
	# случайный порядок (детерминированный)
	for i in range(cands.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var tmp = cands[i]
		cands[i] = cands[j]
		cands[j] = tmp
	var chosen: Array = []
	var why := {"кандидатов": cands.size()}
	for p: Vector2 in cands:
		if chosen.size() >= 18:
			break
		var ok := true
		for q in chosen:
			if p.distance_to(q) < 36.0:
				ok = false
				break
		if not ok:
			continue
		# ближайшая точка дороги — туда смотрит фасад и ведёт тропа
		var best := Vector2.ZERO
		var bd := 1e9
		for rd in WorldGen._roads:
			var pts: PackedVector2Array = rd.pts
			for i in pts.size() - 1:
				var cp := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
				if p.distance_to(cp) < bd:
					bd = p.distance_to(cp)
					best = cp
		var fd := (best - p).normalized()
		var th := atan2(fd.x, fd.y)
		var w := 17.0
		var d := 20.0
		if not _plot_ok(p, th, w, d, ""):
			why[_last.substr(0, 12)] = why.get(_last.substr(0, 12), 0) + 1
			continue
		# тропа без воды
		var gate := _loc(p, th, 0.0, d / 2.0 + 1.0)
		var trail := PackedVector2Array()
		var side := Vector2(-fd.y, fd.x) * _rng.randf_range(-6.0, 6.0)
		var wet := false
		for k in 7:
			var u := k / 6.0
			var q: Vector2 = gate.lerp(best, u) + side * sin(u * PI)
			if WorldGen.terrain(q.x, q.y)[1] > 0.02:
				wet = true
			trail.append(q)
		if wet:
			why["вода на тропе"] = why.get("вода на тропе", 0) + 1
			continue
		chosen.append(p)
		why["где"] = why.get("где", "") + "%d:%d " % [roundi(p.x), roundi(p.y)]
		_plot(p, rad_to_deg(th), w, d, FOREST_HOUSES[chosen.size() % FOREST_HOUSES.size()], "old")
		WorldGen.add_clear(p.x, p.y, w / 2.0 + 4.0, d / 2.0 + 4.0, th)          # полянка вокруг двора
		var bb := Rect2(trail[0], Vector2.ZERO)
		for q in trail:
			bb = bb.expand(q)
		WorldGen._roads.append({"pts": trail, "bb": bb.grow(4.0), "track": true, "trail": true})
	why["поставлено"] = chosen.size()
	_rej["лесных домов"] = why

func _rings() -> void:
	for r in RINGS:
		var f: Dictionary = WorldGen.FEATURES[r[0]]
		var rad: float = r[1] * K
		var a0: float = r[3]
		var a1: float = r[4]
		var sl: float = FENCE_LEN.get(r[2], 2.6) * M
		var n := roundi(deg_to_rad(a1 - a0) * rad / sl)
		for i in n:
			var ang := deg_to_rad(a0 + (a1 - a0) * (i + 0.5) / n)
			if r[5] > 0 and (i % int(r[5])) == 0:
				continue
			var p := Vector2(f.x + cos(ang) * rad, f.y + sin(ang) * rad)
			var yaw := -rad_to_deg(ang) - 90.0
			var sfx := "b" if _rng.randf() < 0.35 else "a"
			if path_blocked(p):
				continue
			put("%s_%s" % [r[2], sfx], p.x, p.y, yaw)

func path_blocked(p: Vector2) -> bool:
	return WorldGen.path_dist(p.x, p.y) < 1.6

# ---------------- вдоль дорог ----------------
func _near_site(p: Vector2, pad: float) -> bool:
	if WorldGen.cleared(p.x, p.y, pad):
		return true
	for key in WorldGen.FEATURES:
		var f: Dictionary = WorldGen.FEATURES[key]
		if Vector2(p.x - f.x, p.y - f.y).length() < f.r * K + pad:
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
		if pts.size() < 5:
			continue                                                  # улицы поселений
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
					acc = 16.0
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
				put("haystack", p.x + 6.0, p.y + 2.5, 0.0)

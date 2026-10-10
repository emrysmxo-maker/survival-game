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
# брошенные машины (tools/cars/car.py): ~55% 2010–2026, ~30% 2000-х, ~15% старые; без логотипов
const CARS := ["car_sedan_red", "car_sedan_white", "car_solaris_silver", "car_granta_graphite", "car_vesta_black", "car_hatch_white", "car_hatch_red", "car_sedan_blue",
	"car_duster_brown", "car_crossover_silver", "car_crossover_white", "car_suv_green", "car_wagon_silver", "car_wagon_beige", "car_van_white", "car_van_orange",
	"car_niva_beige", "car_niva_white", "car_classic_blue", "car_sedan_green", "car_sedan_burnt", "car_sedan_yellow", "car_van_olive",
	"car_truck_blue", "car_truck_green", "car_bus_yellow", "car_bus_blue", "tractor_blue", "tractor_red", "car_crossover_burnt", "car_hatch_burnt", "car_solaris_wreck",
	"car_solaris_wreck", "car_sedan_burnt"]
const YARD_CARS := ["car_solaris_silver", "car_granta_graphite", "car_duster_brown", "car_crossover_silver", "car_crossover_white", "car_suv_green", "car_wagon_silver",
	"car_wagon_beige", "car_hatch_white", "car_niva_white", "car_niva_beige", "car_classic_blue", "car_sedan_white", "car_vesta_black"]
# дома (tools/houses/house.py): длина по фасаду, глубина, вынос крыльца с ступенями — метры
const HOUSE := {"house_izba_a": [8.0, 6.6, 2.4], "house_izba_b": [7.2, 6.2, 2.0], "house_izba_c": [7.6, 6.4, 2.3], "house_brick": [10.0, 8.4, 2.3],
	"house_brick_small": [8.0, 7.0, 2.1], "house_new_a": [10.0, 9.0, 2.2], "house_new_b": [9.0, 8.0, 2.4], "house_cottage": [10.0, 10.0, 2.6],
	"house_dacha_a": [6.0, 5.0, 2.0], "house_dacha_b": [6.4, 5.2, 1.9], "house_dacha_c": [5.6, 5.0, 1.6], "house_dacha_d": [6.0, 5.4, 1.8],
	"house_cabin": [6.0, 5.0, 1.7], "house_banya": [4.6, 4.0, 0.4], "house_izba_burnt": [8.0, 6.6, 2.4], "house_brick_burnt": [8.0, 7.0, 2.1]}
const BURNT := {"house_izba_a": "house_izba_burnt", "house_izba_c": "house_izba_burnt", "house_brick_small": "house_brick_burnt"}   # часть дворов — пепелища
# радиус занятости (тайлы, в масштабе 0,8 — умножается на K)
const FOOT := {"club": 7.0, "barn": 7.5, "barn_long": 13.0, "barracks": 11.0, "sawmill_hall": 9.0, "machine_shed": 11.0, "shop": 5.0, "bunker_entrance": 6.0,
	"school": 14.0, "admin": 8.0, "fap": 6.0, "fire_station": 8.0, "supermarket": 13.0, "tire_shop": 5.0, "auto_service": 7.0, "motel": 8.0, "dps_post": 3.0,
	"chapel": 3.0, "silo_conc": 2.4, "silo_metal": 2.4, "water_tower": 2.2, "radio_mast": 1.8, "transmitter": 4.5, "fuel_tank": 3.0}
const RAD := {"shed_blue": 2.4, "shed_green": 2.4, "open_shed": 3.4, "greenhouse": 2.6, "boat_shed": 4.2, "outhouse": 1.0, "well_a": 1.1, "well_b": 1.1, "tent_army": 2.6, "tent_tan": 2.6,
	"tarp_shelter": 2.4, "log_pile": 4.3, "lumber_stack": 2.6, "pier": 6.5, "container_g": 3.3, "container_b": 3.3, "container_r": 3.3, "checkpoint": 4.6, "mil_tower": 2.0,
	"rock_cave": 6.5, "sandbag_nest": 2.8, "watch_tower": 1.8, "generator_shed": 3.0, "sawdust": 2.6, "cellar": 2.2, "haystack": 2.2}
var _occ: Array = []

# хутора: какие дома (по порядку вдоль улицы) и что вокруг [модель, dx, dy, yaw]
const HAMLETS := {
	"h_zarechye": {"houses": ["house_brick_small", "house_izba_c", "house_dacha_c", "house_new_b"], "kind": "old", "ext": [["woodpile", -11, 6, 0]]},
	"h_bereza": {"houses": ["house_izba_a", "house_izba_b", "house_cabin", "house_brick"], "kind": "old", "ext": [["haystack", 9, -5, 0]]},
	"h_ranger": {"houses": ["house_izba_c"], "kind": "old", "ext": [["watch_tower", -7, -4, 0], ["car_van_olive", -6, 5, 40]]},
	"h_hunter": {"houses": ["house_cabin"], "kind": "old", "ext": [["fish_rack", -3, 4, 0]]},
	"h_cem": {"houses": [], "kind": "old", "ext": [["chapel", 0, -2, 0], ["graves", -6, 1, 0], ["graves", 2, 4, 0], ["fence_rails_b", 0, 7, 0], ["fence_rails_a", 3, 7, 0]]},
	"h_dachi": {"houses": ["house_dacha_a", "house_dacha_b", "house_dacha_c", "house_dacha_d", "house_dacha_b", "house_dacha_a", "house_dacha_d", "house_dacha_c"], "kind": "dacha", "ext": [["car_sedan_yellow", -3, 0.3, 5]]},
	"h_poselok": {"houses": ["house_new_a", "house_new_b", "house_cottage", "house_brick", "house_new_a", "house_new_b", "house_brick_small", "house_cottage", "house_new_b", "house_new_a"], "kind": "new",
		"ext": [["bus_stop", 3, -6, 0], ["well_a", -3, 5, 0], ["car_ambulance", -6, 2, 60]], "shop": true},
}
const VILLAGE_HOUSES := ["house_izba_a", "house_izba_c", "house_brick", "house_izba_b", "house_brick_small", "house_izba_a", "house_new_b", "house_cabin", "house_izba_c", "house_brick",
	"house_izba_b", "house_new_a", "house_izba_a", "house_dacha_d", "house_izba_c", "house_brick_small", "house_izba_b", "house_cabin"]

# мини-город у локации: улица вдоль дороги за пределами локации (дома по теме места); бункер — без жилья
const TOWNS := {
	"farm": {"houses": ["house_brick", "house_brick_small", "house_new_a", "house_brick", "house_izba_c", "house_new_b"], "kind": "old", "off": 26.0, "extra": ["shop"]},
	"sawmill": {"houses": ["house_cabin", "house_izba_b", "house_cabin", "house_izba_a"], "kind": "old", "off": 22.0, "extra": ["barracks"]},
	"lakebase": {"houses": ["house_izba_a", "house_cabin", "house_izba_c", "house_izba_b"], "kind": "old", "off": 20.0, "extra": []},
	"tower": {"houses": ["house_brick_small", "house_cabin"], "kind": "old", "off": 20.0, "extra": []},
}
const NO_HOMES_R := 95.0              # вокруг бункера (тайлы, ~80 м) — ни одного жилого дома

# локации (смещения от центра, тайлы, в масштабе 0,8 — умножаются на K; причал и лодки — без умножения, они у воды)
const LOCS := {
	"camp": [["tent_army", -4, -3, 10], ["tent_army", -5, 2.5, -20], ["tent_tan", 3.5, -5, 160], ["tarp_shelter", 5, 3, 15], ["campfire", 0, 0, 0], ["bench_log", -2.4, 2.2, 0], ["bench_log", 2.6, -1.8, 90],
		["bench_log", 1.4, 3.0, 20], ["camp_table", -8, -0.5, 80], ["barricade", 0, -9.5, 0], ["barricade", 7, -7, 40], ["barricade", -7, -7.5, -40], ["barricade", 9.5, 1, 90], ["watch_tower", 9, -8, 0], ["clothesline", -2, 7, 0],
		["sandbags", 7, 7, -20], ["barrels_a", -8, 6, 0], ["crates", 8, 0, 0], ["car_van_olive", -9, -6, 160], ["woodpile", 4.5, 8, 180]],
	"village": [["well_a", -3.5, -2.5, 0], ["car_bus_yellow", 4, 1.2, 12], ["car_sedan_burnt", -6, 2.0, 160], ["tractor_blue", -2, -5, 70], ["barrels_b", 6, -4, 0],
		["car_police", 2, -7, 35], ["car_fire", -8, 6, 200]],
	"sawmill": [["sawmill_hall", 0, -2, 0], ["log_pile", -9, 6, 0], ["log_pile", -9, 10, 0], ["lumber_stack", 8, 7, 0], ["lumber_stack", 8, 10, 0], ["lumber_stack", 12, 7, 0], ["sawdust", 7, -8, 0], ["log_heap", -3, 9, 30], ["log_heap", 4, 11, -20],
		["house_cabin", -11, -8, 30], ["car_truck_logs", 11, 2, 160], ["tractor_red", 5, 13, 140], ["barrels_a", -12, -3, 0], ["woodpile", -14, 0, 90]],
	"lakebase": [["pier", 8.5, 0.5, 0], ["boat_row_wood", 5.5, -1.5, 15], ["boat_row_up", 4, 3.5, -25], ["boat_motor", 6.5, 5, 80], ["boat_row_blue", 5.2, -5.5, 5], ["boat_shed", -3, -6, 0], ["fish_rack", 1, 6, 0], ["nets", -4.5, 4.5, 20], ["house_cabin", -9, 2, 90],
		["house_banya", -6, -9, 10], ["car_sedan_white", 2, 9, 200], ["barrels_b", -1, 2, 0], ["woodpile", -10, 8, 0], ["crates", 3, -8, 0], ["well_b", -8, -3, 0]],
	"farm": [["barn_long", -12.8, -14.4, 0], ["silo_conc", 3.2, -17.6, 0], ["silo_conc", 3.2, -12.0, 0], ["barn", 16.4, -14.4, 0], ["machine_shed", 8.0, 11.2, 0], ["house_brick", -16.0, 9.6, 180], ["water_tower", 22.4, 1.6, 0], ["fuel_tank", -6.4, 14.4, 10], ["silo_metal", -24.0, 0.0, 0], ["tractor_blue", -1.6, 1.6, 30], ["tractor_red", -8.0, -2.4, 120], ["trailer_cart", 4.8, 0.0, 80], ["car_truck_green", -14.4, -2.4, 0], ["car_van_white", 11.2, -3.2, 40], ["bales_round", 15.2, 2.4, 0], ["bales_round", 24.0, 8.0, 0], ["bales_square", 20.8, 19.2, 0], ["haystack", 28.8, -4.0, 0], ["barrels_a", -4.8, -6.4, 0], ["tires", 9.6, 19.2, 0]],   # двор под настоящие размеры: сзади коровник, силосы, амбар; спереди мастерские и контора; техника посередине
	"tower": [["radio_mast", 0, 0, 0], ["transmitter", -7, 4, 0], ["generator_shed", -10, -3, 0], ["dish", 6, -4, 0], ["car_van_white", 8, 6, 210], ["barrels_a", -8, -1, 0], ["woodpile", -4, -8, 0]],
}
# ограда локаций по окружности: [локация, радиус (×K), модель-секция, от°, до°, пропуск (каждая N-я секция)]
const RINGS := [["tower", 9.5, "fence_chain", 0, 360, 7], ["lakebase", 12.0, "fence_rails", 90, 270, 0], ["sawmill", 14.5, "fence_board", 60, 300, 0], ["farm", 20.0, "fence_rails", 200, 340, 0]]
const FENCE_LEN := {"fence_picket": 2.6, "fence_rails": 2.7, "fence_board": 2.65, "fence_chain": 3.4, "fence_prof": 2.5, "fence_mil": 3.0}   # длина секции, м

var _meshes := {}
var _lit: Array = []                  # материалы окон, где по ночам горит свет
var _fire: OmniLight3D                # костёр в лагере
var loc_th := {}                      # поворот двора локации (рад), для меню: где скамейки у костра
var _night := -1.0
var _batch := {}
var _rng := RandomNumberGenerator.new()
var _n := 0
var _plots: Array = []                # участки: [центр, угол, полуширина, полуглубина]
var _rej := {}                        # отказы участков по причинам (для проверки)
var _last := ""

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	_rng.seed = 20261008
	var tm := {"_t": Time.get_ticks_usec()}
	var step := func(nm: String) -> void:                              # время шагов расстановки, мс (в лог «props:»)
		var now := Time.get_ticks_usec()
		tm[nm] = (now - int(tm["_t"])) / 1000
		tm["_t"] = now
	_load(); step.call("load")
	var ck := _cache_key()
	_story_pts()                                                      # точки заставки — всегда (и при кэше)
	if _cache_read(ck):                                               # расстановка уже посчитана этой сборкой — только прочитать
		_flush(); step.call("cache")
		tm.erase("_t")
		_rej = {"кэш": ck, "время, мс": tm}
		_after_ready(t0)
		return
	_bunker(); step.call("bunker")
	_hero_home(); _lab(); step.call("story")
	_locations(); step.call("locations")
	_railway(); step.call("railway")
	_children_camp(); step.call("lager")
	_hamlet("h_poselok"); step.call("poselok")            # новый посёлок — первым: ему нужно поле целиком
	_village(); step.call("village")
	for key in HAMLETS:
		if key != "h_poselok":
			_hamlet(key)
	step.call("hamlets")
	_towns(); step.call("towns")                          # мини-города у локаций — после хуторов, по свободным дорогам
	_gas_station(); step.call("gas")
	_roadside(); step.call("roadside")
	_quarry()
	_rocks()
	_hunting_towers(); step.call("towers")
	_dump_and_wreck()
	_rings()
	_forest_houses(); step.call("forest")
	_quarantine(); step.call("quarantine")
	_road_marks(); step.call("marks")
	_crosswalks(); step.call("zebra")
	_road_stuff(); step.call("roadstuff")
	_fields(); step.call("fields")
	_flush(); step.call("flush")
	tm.erase("_t")
	_rej["время, мс"] = tm
	_cache_write(ck)
	_after_ready(t0)

func _after_ready(t0: int) -> void:
	var cf: Dictionary = WorldGen.FEATURES["camp"]
	_fire = OmniLight3D.new()
	_fire.light_color = Color(1.0, 0.62, 0.3)
	_fire.omni_range = 9.0
	_fire.shadow_enabled = false
	_fire.position = Vector3(cf.x * T, _h(cf.x, cf.y) + 0.8, cf.y * T)
	_fire.visible = false
	add_child(_fire)
	_flames(Vector3(cf.x * T, _h(cf.x, cf.y), cf.y * T))
	print("props: ", _n, " партий ", _batch.size(), " участков ", _plots.size(), " за ", Time.get_ticks_msec() - t0, " мс; отказы участков: ", _rej)

# пламя костра: три перекрещенных языка (шейдер, без текстур) + искры
const FLAME_SH := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float seed = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void vertex() {   // поворот к камере вокруг вертикали
	vec3 z = normalize(vec3(INV_VIEW_MATRIX[2].x, 0.0, INV_VIEW_MATRIX[2].z));
	vec3 x = vec3(z.z, 0.0, -z.x);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(x * length(MODEL_MATRIX[0].xyz), 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(z, 0.0), MODEL_MATRIX[3]);
}
void fragment() {
	vec2 uv = UV; uv.y = 1.0 - uv.y;                 // 0 низ .. 1 верх
	float t = TIME * 1.6 + seed * 7.0;
	float nz = n(vec2(uv.x * 4.0 + seed * 3.0, uv.y * 3.0 - t * 2.2)) * 0.6 + n(vec2(uv.x * 9.0, uv.y * 7.0 - t * 3.7)) * 0.4;
	float w = (1.0 - uv.y) * 0.5 + 0.06;              // язык уже кверху
	float dx = abs(uv.x - 0.5 + (nz - 0.5) * 0.25 * uv.y);
	float m = smoothstep(w, w * 0.35, dx) * smoothstep(1.0, 0.25, uv.y + nz * 0.45) * smoothstep(0.0, 0.08, uv.y);
	vec3 c = mix(vec3(0.9, 0.18, 0.02), vec3(1.0, 0.62, 0.12), smoothstep(0.1, 0.5, m));
	c = mix(c, vec3(1.0, 0.95, 0.7), smoothstep(0.65, 1.0, m));
	ALBEDO = c * m * 2.2;
}
"""
func _flames(at: Vector3) -> void:
	var sh := Shader.new()
	sh.code = FLAME_SH
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.8)
	q.center_offset = Vector3(0, 0.4, 0)
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("seed", float(i) * 1.37)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = at + Vector3([0.0, 0.14, -0.12][i], 0.12, [0.0, 0.1, -0.08][i])
		mi.scale = Vector3.ONE * [1.0, 0.75, 0.8][i]
		add_child(mi)
	var sp := CPUParticles3D.new()                              # искры
	sp.amount = 22
	sp.lifetime = 2.2
	sp.position = at + Vector3(0, 0.35, 0)
	sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sp.emission_sphere_radius = 0.25
	sp.direction = Vector3.UP
	sp.spread = 18.0
	sp.initial_velocity_min = 0.8
	sp.initial_velocity_max = 1.8
	sp.gravity = Vector3(0.25, 0.15, 0.1)
	sp.damping_min = 0.3
	sp.damping_max = 0.6
	sp.scale_amount_min = 0.5
	sp.scale_amount_max = 1.0
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.8, 0.35, 1.0))
	g.set_color(1, Color(1.0, 0.25, 0.05, 0.0))
	sp.color_ramp = g
	var em := QuadMesh.new()
	em.size = Vector2(0.045, 0.045)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.vertex_color_use_as_albedo = true
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	em.material = mm
	sp.mesh = em
	add_child(sp)

# ночь: в некоторых окнах свет, костёр горит (вызывает main.gd каждый кадр)
func set_night(k: float) -> void:
	if _fire:
		_fire.light_energy = k * (1.6 + 0.35 * sin(Time.get_ticks_msec() * 0.011) + 0.2 * sin(Time.get_ticks_msec() * 0.027))
		_fire.visible = k > 0.05
	if absf(k - _night) < 0.02:
		return
	_night = k
	for m in _lit:
		m.set_shader_parameter("night", k)
	if _lone_light:
		_lone_light.visible = k > 0.1
		_lone_light.light_energy = k * 1.6

# ---------------- загрузка и вывод ----------------
# кэш расстановки (только на телефоне): расстановка детерминирована — после первого запуска сборки читается из файла
const CACHE := "user://props_cache.bin"
func _cache_key() -> String:
	if not OS.has_feature("android") and OS.get_environment("PROPS_CACHE") != "1":
		return ""                                                     # на ПК/сервере всегда считаем заново (проверки кода)
	var b := FileAccess.get_file_as_string("res://build.txt").strip_edges()
	var f := FileAccess.open("res://assets/props/props.glb", FileAccess.READ)
	return "%s|%d|v2" % [b, f.get_length() if f else 0]

func _cache_read(key: String) -> bool:
	if key == "" or not FileAccess.file_exists(CACHE):
		return false
	var f := FileAccess.open(CACHE, FileAccess.READ)
	if f == null:
		return false
	var d = f.get_var()
	if typeof(d) != TYPE_DICTIONARY or d.get("key", "") != key:
		return false
	_batch = d.batch
	WorldGen._roads = d.roads
	WorldGen._clr = d.clr
	WorldGen._xt = d.xt
	WorldGen._xt_keys = d.xt_keys
	_n = d.n
	loc_th = d.get("loc_th", {})
	return true

func _cache_write(key: String) -> void:
	if key == "":
		return
	var f := FileAccess.open(CACHE, FileAccess.WRITE)
	if f:
		f.store_var({"key": key, "batch": _batch, "roads": WorldGen._roads, "clr": WorldGen._clr, "xt": WorldGen._xt, "xt_keys": WorldGen._xt_keys, "n": _n, "loc_th": loc_th})

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
			elif mat is BaseMaterial3D and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				(m as ArrayMesh).surface_set_material(i, _wear_mat(mat))                  # свой шейдер: матовость + износ (shaders/props.gdshader)
		_meshes[str(n.name)] = m
	for c in n.get_children():
		_collect(c)

# ---------------- материалы и износ ----------------
const LIT_MODELS := ["admin", "camp_corpus", "hero_shed", "house_brick", "house_cabin", "house_cottage", "house_izba_a", "lab_main", "lab_wing", "motel", "phone", "school", "supermarket"]
# блеск по замеру (сборка 106): краска машин r=0.30 m=0.45 — пластик; профнастил 0.45; рамы/железо 0.4–0.6.
# [шероховатость, металл, блик, пачкается]; остальные — как в модели, но не глаже 0.9 (стены, шифер, дерево).
const MAT_FIX := {"paint": [0.58, 0.12, 0.4, 0.8], "car_glass": [0.18, 0.2, 0.5, 0.35], "chrome": [0.38, 0.85, 0.5, 0.6], "rim": [0.5, 0.6, 0.45, 0.8],
	"headlight": [0.2, 0.3, 0.5, 0.35], "glass_lit": [0.3, 0.0, 0.5, 0.3], "taillight": [0.3, 0.1, 0.5, 0.35], "brake": [0.6, 0.5, 0.4, 0.8], "metal": [0.6, 0.55, 0.4, 0.8],
	"metal_paint": [0.72, 0.1, 0.35, 1.0], "frame": [0.72, 0.1, 0.35, 0.8], "frame_white": [0.75, 0.0, 0.35, 0.8], "profnastil": [0.72, 0.15, 0.35, 1.0],
	"tin_rust": [0.9, 0.1, 0.3, 1.0], "steel": [0.55, 0.7, 0.45, 0.8], "steel_dark": [0.6, 0.65, 0.4, 0.8], "rail": [0.55, 0.7, 0.45, 0.5],
	"boat_alu": [0.6, 0.35, 0.4, 0.8], "cont_b": [0.78, 0.12, 0.35, 1.0], "cont_g": [0.78, 0.12, 0.35, 1.0], "cont_r": [0.78, 0.12, 0.35, 1.0],
	"tin_blue": [0.78, 0.12, 0.35, 1.0], "tin_gray": [0.78, 0.12, 0.35, 1.0], "tin_green": [0.78, 0.12, 0.35, 1.0], "tin_red": [0.78, 0.12, 0.35, 1.0],
	"dome_tin": [0.75, 0.15, 0.35, 1.0], "tank_rust": [0.85, 0.2, 0.3, 1.0], "onion": [0.5, 0.5, 0.45, 0.5], "fish": [0.6, 0.2, 0.4, 0.5],
	"gas": [0.65, 0.15, 0.4, 0.8], "plate": [0.65, 0.0, 0.4, 0.8], "film": [0.45, 0.0, 0.5, 0.4], "wagon_red": [0.8, 0.1, 0.35, 1.0],
	"wallpaper": [0.92, 0.0, 0.3, 0.15], "paint_wall": [0.92, 0.0, 0.3, 0.15], "floor_wood": [0.85, 0.0, 0.3, 0.15], "linoleum": [0.75, 0.0, 0.35, 0.15],
	"interior": [0.92, 0.0, 0.3, 0.2], "plastic": [0.7, 0.0, 0.4, 0.6], "hazard": [0.75, 0.0, 0.35, 0.8], "red_w": [0.8, 0.0, 0.35, 0.8]}
var _wsh: Shader
var _wmats := {}
func _wear_mat(src: BaseMaterial3D) -> Material:
	if _wmats.has(src):
		return _wmats[src]
	if _wsh == null:
		_wsh = load("res://shaders/props.gdshader")
	var nm := str(src.resource_name).get_slice(".", 0)
	var fx: Array = MAT_FIX.get(nm, [maxf(src.roughness, 0.92), src.metallic, 0.3, 1.0])
	var m := ShaderMaterial.new()
	m.shader = _wsh
	m.set_shader_parameter("albedo", src.albedo_color)
	m.set_shader_parameter("has_tex", src.albedo_texture != null)
	if src.albedo_texture:
		m.set_shader_parameter("albedo_tex", src.albedo_texture)
	m.set_shader_parameter("has_normal", src.normal_enabled and src.normal_texture != null)
	if src.normal_texture:
		m.set_shader_parameter("normal_tex", src.normal_texture)
		m.set_shader_parameter("normal_k", src.normal_scale)
	m.set_shader_parameter("use_vc", src.vertex_color_use_as_albedo)
	m.set_shader_parameter("roughness", fx[0])
	m.set_shader_parameter("metallic", fx[1])
	m.set_shader_parameter("specular", fx[2])
	m.set_shader_parameter("grime", fx[3])
	m.resource_name = src.resource_name
	if nm == "glass_lit" or nm == "headlight":
		m.set_shader_parameter("glow", 1 if nm == "glass_lit" else 2)        # свет в окне / плафон фонаря — где есть ток
		_lit.append(m)
	_wmats[src] = m
	return m

const CLEAN_AT := ["lab", "h_dachi"]                   # у НИИ и в дачном посёлке — ухоженнее
# износ постройки/машины 0..1 по типу, месту и случаю (без кэша: из позиции, всегда одинаково)
func wear_of(model: String, tp: Vector2) -> float:
	var r := fposmod(sin(tp.x * 12.9898 + tp.y * 78.233) * 43758.5453, 1.0)
	var base := model.trim_suffix("_roof")
	var w := 0.25 + 0.5 * r                                             # пожилой ± случай
	if base.contains("burnt") or base.contains("wreck"):
		return 1.0
	if base.contains("izba") or base.contains("cabin") or base.contains("banya") or base.contains("shed") or base.contains("barn") \
			or base.contains("outhouse") or base == "well_a" or base == "well_b" or base.contains("silo") or base.contains("wagon"):
		w += 0.22                                                       # дерево и хозпостройки стареют быстрее
	if base.contains("brick") or base.contains("new") or base.contains("cottage") or base.begins_with("lab") or base in ["school", "admin", "supermarket", "fap"]:
		w -= 0.18
	if base.begins_with("car_"):
		w = 0.15 + 0.75 * r
	for k in CLEAN_AT:
		var f: Dictionary = WorldGen.FEATURES[k] if WorldGen.FEATURES.has(k) else WorldGen.HAMLETS.get(k, {})
		if not f.is_empty() and tp.distance_to(Vector2(f.x, f.y)) < float(f.r) + 30.0:
			w -= 0.25
	for k in WorldGen.HAMLETS:                                          # хутора — запущеннее
		var f: Dictionary = WorldGen.HAMLETS[k]
		if k != "h_dachi" and tp.distance_to(Vector2(f.x, f.y)) < float(f.r) + 10.0:
			w += 0.18
	return clampf(w, 0.0, 0.95)

# ---------------- двери: открываются сами, когда рядом игрок (пока — точка камеры) ----------------
# полотна — отдельные модели door_leaf_wood/metal (tools/houses/house.py), петли домов — assets/props/doors.json
const DOOR_R := 1.9                   # м: ближе — дверь открыта
const DOOR_OPEN := 1.66               # рад (95°) внутрь
const DCELL := 8.0                    # тайлов: клетка поиска дверей
var doors: Array = []                 # {mm, i, base: Transform3D дома, p, t, n, w, h, rest, a, pos (тайлы)}
var _dgrid := {}
var _dactive := {}
func _build_doors() -> void:
	if not _meshes.has("door_leaf_wood") or not FileAccess.file_exists("res://assets/props/doors.json"):
		return                                                          # старый props.glb — двери в доме
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://assets/props/doors.json"))
	if typeof(spec) != TYPE_DICTIONARY:
		return
	var lists := {"wood": [], "metal": []}
	for key in _batch:
		var b: Dictionary = _batch[key]
		if not spec.has(b.model):
			continue
		for xf: Transform3D in b.xf:
			for d in spec[b.model]:
				var e := {"base": xf, "p": Vector3(d.p[0], d.p[2], -d.p[1]), "t": Vector3(d.tan[0], 0, -d.tan[1]), "n": Vector3(d["in"][0], 0, -d["in"][1]),
					"w": float(d.w), "h": float(d.h), "rest": float(d.open) * deg_to_rad(80.0), "kind": "metal" if d.kind == "metal" else "wood", "wear": wear_of(b.model, Vector2(xf.origin.x, xf.origin.z) / T)}
				e.a = e.rest
				var wp: Vector3 = xf * (e.p + e.t * e.w * 0.5)
				e.pos = Vector2(wp.x, wp.z) / T
				lists[e.kind].append(e)
	for kind in lists:
		var arr: Array = lists[kind]
		if arr.is_empty() or not _meshes.has("door_leaf_" + kind):
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _meshes["door_leaf_" + kind]
		mm.instance_count = arr.size()
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.name = "doors_" + kind
		add_child(mi)
		for i in arr.size():
			var e: Dictionary = arr[i]
			e.mm = mm
			e.i = i
			mm.set_instance_custom_data(i, Color(e.wear, fposmod(e.base.origin.x * 0.173 + e.base.origin.z * 0.311, 1.0), 0.0, 0.0))
			_door_xf(e)
			var ck := Vector2i(floori(e.pos.x / DCELL), floori(e.pos.y / DCELL))
			if not _dgrid.has(ck):
				_dgrid[ck] = []
			_dgrid[ck].append(doors.size())
			doors.append(e)
	print("props: дверей ", doors.size(), " горящих фонарей ", lamp_pts.size(), " генераторов ", _power.size(), " окно в деревне ", lone_window.round())
	for lp in lamp_pts:
		print("LAMP %.1f %.1f %s" % [lp[0].x / T, lp[0].z / T, str(lp[1])])
	if OS.get_environment("DOORDBG") != "":
		for e in doors.slice(0, 40):
			print("DOOR %.1f %.1f rest %.2f" % [e.pos.x, e.pos.y, e.rest])

func _door_xf(e: Dictionary) -> void:
	var dv: Vector3 = e.t * cos(e.a) + e.n * sin(e.a)
	var bx := Basis(dv * e.w, Vector3.UP * (e.h * 0.5), dv.cross(Vector3.UP))
	e.mm.set_instance_transform(e.i, e.base * Transform3D(bx, e.p))

# каждый кадр (main.gd): двери у точки at (тайлы) открываются, остальные — к своему положению
func update_doors(at: Vector2, dt: float) -> void:
	if doors.is_empty():
		return
	var c := Vector2i(floori(at.x / DCELL), floori(at.y / DCELL))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for i in _dgrid.get(c + Vector2i(dx, dy), []):
				_dactive[i] = true
	var done := []
	for i in _dactive:
		var e: Dictionary = doors[i]
		var want: float = DOOR_OPEN if at.distance_to(e.pos) * T < DOOR_R else e.rest
		var na: float = move_toward(e.a, want, dt * 2.6)
		if na != e.a:
			e.a = na
			_door_xf(e)
		elif at.distance_to(e.pos) > DCELL * 2.0:
			done.append(i)
	for i in done:
		_dactive.erase(i)

# ---------------- электричество: свет только у генераторов ----------------
# в зоне карантина тока нет; окна и фонари горят только рядом с генератором (generator_shed) и у НИИ;
# в деревне один фонарь мигает (последний, кто не сдался). Ближним горящим фонарям — настоящий свет (до 4 ламп).
const POWER_R := 40.0                 # тайлов от генератора
var _power: Array = []                # точки с током (тайлы)
var lamp_pts: Array = []              # [мир. позиция плафона, мигает, seed]
var _lamps: Array = []                # OmniLight3D — пул
var _flicker_i := -1
func _power_at(tp: Vector2) -> bool:
	for q in _power:
		if tp.distance_to(q) < POWER_R:
			return true
	return false

func _find_power() -> void:
	_power.clear()
	for key in _batch:
		if _batch[key].model == "generator_shed":
			for xf: Transform3D in _batch[key].xf:
				_power.append(Vector2(xf.origin.x, xf.origin.z) / T)
	var lab: Dictionary = WorldGen.FEATURES["lab"]
	_power.append(Vector2(lab.x, lab.y))
	var v: Dictionary = WorldGen.FEATURES["village"]                    # мигающий фонарь — ближний к центру деревни
	var best := 1e9
	var n := 0
	for key in _batch:
		if _batch[key].model != "lamp_post":
			continue
		for xf: Transform3D in _batch[key].xf:
			var d := Vector2(xf.origin.x, xf.origin.z).distance_to(Vector2(v.x, v.y) * T)
			if d < best:
				best = d
				_flicker_i = n
			n += 1

# одно светящееся окно в деревне (кто-то живой — будущее задание): ближний к центру деревни дом с окнами
var lone_window := Vector2.INF
func _find_lone() -> void:
	var v: Dictionary = WorldGen.FEATURES["village"]
	var best := 1e9
	for key in _batch:
		if not (_batch[key].model in LIT_MODELS):
			continue
		for xf: Transform3D in _batch[key].xf:
			var sd := fposmod(xf.origin.x * 0.173 + xf.origin.z * 0.311, 1.0)
			if fposmod(sd * 37.0 * 0.618 + 0.17, 1.0) < 0.3:
				continue                                                # шейдер оставил бы этот дом тёмным
			var tp := Vector2(xf.origin.x, xf.origin.z) / T
			var d := tp.distance_to(Vector2(v.x, v.y))
			if d < best and d < 60.0:
				best = d
				lone_window = tp
				_lone_pos = xf.origin
	if lone_window != Vector2.INF:                                       # тёплый свет внутри — пятном из окон и двери
		_lone_light = OmniLight3D.new()
		_lone_light.light_color = Color(1.0, 0.66, 0.34)
		_lone_light.omni_range = 9.0
		_lone_light.omni_attenuation = 0.8
		_lone_light.shadow_enabled = false                         # свет вокруг дома: сверху читается «в доме горит свет»
		_lone_light.position = _lone_pos + Vector3(0, 1.9, 0)
		_lone_light.visible = false
		add_child(_lone_light)
var _lone_pos := Vector3.ZERO
var _lone_light: OmniLight3D

func _flick(t: float, seed: float) -> float:                         # то же, что h21 в props.gdshader
	var p3 := Vector3(floor(t * 7.0), seed, floor(t * 7.0)) * 0.1031
	p3 = Vector3(fposmod(p3.x, 1.0), fposmod(p3.y, 1.0), fposmod(p3.z, 1.0))
	p3 += Vector3.ONE * p3.dot(Vector3(p3.y, p3.z, p3.x) + Vector3.ONE * 33.33)
	return 1.0 if fposmod((p3.x + p3.y) * p3.z, 1.0) >= 0.35 else 0.0

# каждый кадр (main.gd): лампы пула — на ближние к точке at горящие фонари
var _lamp_t := 0.0
func update_lights(at: Vector2, dt: float) -> void:
	if lamp_pts.is_empty() or _night < 0.05:
		for l in _lamps:
			l.visible = false
		return
	_lamp_t -= dt
	if _lamp_t <= 0.0:
		_lamp_t = 0.5
		var near := lamp_pts.duplicate()
		var a3 := Vector3(at.x * T, 0.0, at.y * T)
		near.sort_custom(func(p, q): return Vector2(p[0].x - a3.x, p[0].z - a3.z).length() < Vector2(q[0].x - a3.x, q[0].z - a3.z).length())
		while _lamps.size() < 4:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.82, 0.58)
			l.omni_range = 16.0
			l.omni_attenuation = 0.7
			l.shadow_enabled = false
			add_child(l)
			_lamps.append(l)
		for i in _lamps.size():
			var l: OmniLight3D = _lamps[i]
			l.visible = i < near.size() and Vector2(near[i][0].x - a3.x, near[i][0].z - a3.z).length() < 60.0
			if l.visible:
				l.position = near[i][0] - Vector3(0, 0.3, 0)
				l.set_meta("fl", near[i][1])
				l.set_meta("seed", near[i][2])
	var tt := Time.get_ticks_msec() / 1000.0
	for l in _lamps:
		if l.visible:
			l.light_energy = _night * 6.0 * (_flick(tt, l.get_meta("seed", 0.0)) if l.get_meta("fl", false) else 1.0)

func _flush() -> void:
	_find_power()
	_find_lone()
	var lamp_n := 0
	for key in _batch:
		var b: Dictionary = _batch[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true                                          # износ дома (shaders/props.gdshader)
		mm.mesh = _meshes[b.model]
		mm.instance_count = b.xf.size()
		var roof := 0.25 if str(b.model).ends_with("_roof") else 0.0
		var md := str(b.model)
		var lamp := md == "lamp_post"
		var lit := not roof and (md in LIT_MODELS)
		var car := 0.5 if (md.begins_with("car_") or md.begins_with("tractor") or md.begins_with("trailer") or md.begins_with("boat") or md.begins_with("wagon")) else 0.0
		for i in b.xf.size():
			mm.set_instance_transform(i, b.xf[i])
			var o: Vector3 = b.xf[i].origin
			var tp := Vector2(o.x, o.z) / T
			var sd := fposmod(o.x * 0.173 + o.z * 0.311, 1.0)
			var bflag := roof
			if lamp or lit:
				var pw := _power_at(tp)
				if lamp and lamp_n == _flicker_i:
					bflag = 0.75
				elif pw or (lit and tp.distance_to(lone_window) < 0.5):
					bflag = 0.5
				if lamp:
					if bflag > 0.4:
						lamp_pts.append([b.xf[i] * Vector3(1.55, 7.7, 0.0), bflag > 0.65, sd * 37.0])
					lamp_n += 1
			var wr := wear_of(b.model, tp)
			var kind := car
			if md == "road_dash":
				kind = 1.0                                              # разметка — стёртая краска (шейдер)
			elif md == "clothesline":
				kind = 0.25                                             # бельё качается на ветру (шейдер)
			mm.set_instance_custom_data(i, Color(wr, sd, bflag, kind))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.name = key.replace(".", "_")                                    # «модель|клетка» — по имени находит заставка (крыша дома героя)
		add_child(mi)
	_build_doors()
	_smokes()

# ---------------- дым: из труб у пары изб (там кто-то живёт) и над костром лагеря ----------------
const SMOKE_HOUSES := ["house_izba_a", "house_izba_b", "house_izba_c", "house_cabin"]
var _smoke_tex: Texture2D
func _chimney_top(model: String) -> Vector3:
	var m: Mesh = _meshes.get(model + "_roof")
	if m == null:
		return Vector3.INF
	var top := -1e9
	var pts: Array = []
	for si in m.get_surface_count():
		var arrs := m.surface_get_arrays(si)
		if arrs.size() <= Mesh.ARRAY_VERTEX or arrs[Mesh.ARRAY_VERTEX] == null:
			continue                                                    # без экрана (проверки) — данных сетки нет
		for v: Vector3 in arrs[Mesh.ARRAY_VERTEX]:
			if v.y > top + 0.03:
				top = v.y
				pts = [v]
			elif v.y > top - 0.03:
				pts.append(v)
	var c := Vector3.ZERO
	for v: Vector3 in pts:
		c += v
	return c / maxf(pts.size(), 1.0)

func _smoke_at(p: Vector3, k: float) -> void:
	if _smoke_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.55))
		g.set_color(1, Color(1, 1, 1, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		_smoke_tex = gt
	var sp := CPUParticles3D.new()
	sp.amount = int(14 * k)
	sp.lifetime = 7.0
	sp.preprocess = 7.0
	sp.position = p
	sp.direction = Vector3.UP
	sp.spread = 8.0
	sp.initial_velocity_min = 0.5
	sp.initial_velocity_max = 0.8
	sp.gravity = Vector3(0.35, 0.12, 0.12)                      # ветер сносит, тёплый дым поднимается
	sp.damping_min = 0.05
	sp.damping_max = 0.1
	sp.scale_amount_min = 0.8 * k
	sp.scale_amount_max = 1.2 * k
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(1, 2.2))
	sp.scale_amount_curve = sc
	var cr := Gradient.new()
	cr.set_color(0, Color(0.62, 0.62, 0.64, 0.0))
	cr.add_point(0.12, Color(0.6, 0.6, 0.62, 0.7))
	cr.set_color(1, Color(0.75, 0.76, 0.78, 0.0))
	sp.color_ramp = cr
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.vertex_color_use_as_albedo = true
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.albedo_texture = _smoke_tex
	mm.disable_receive_shadows = true
	q.material = mm
	sp.mesh = q
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sp)

func _smokes() -> void:
	var cands: Array = []
	for key in _batch:
		var md: String = _batch[key].model
		if md in SMOKE_HOUSES:
			for xf: Transform3D in _batch[key].xf:
				cands.append([fposmod(xf.origin.x * 0.731 + xf.origin.z * 0.193, 1.0), md, xf])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var n := 0
	for c in cands:
		if n >= 3:
			break
		var top := _chimney_top(c[1])
		if top == Vector3.INF:
			continue
		_smoke_at((c[2] as Transform3D) * top + Vector3(0, 0.15, 0), 1.0)
		if OS.get_environment("DOORDBG") != "": print("SMOKE %.0f %.0f" % [c[2].origin.x / T, c[2].origin.z / T])
		n += 1
	var cf: Dictionary = WorldGen.FEATURES["camp"]                    # костёр лагеря — дым пожиже
	_smoke_at(Vector3(cf.x * T, _h(cf.x, cf.y) + 1.0, cf.y * T), 0.7)

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

# ---------------- следы построек (против наложений) ----------------
const FOOT_SKIP := ["fence", "gate", "road_dash", "bridge", "concrete_pad", "rail_", "wire", "sign", "lamp", "pole", "graffiti", "_roof", "dump_pile", "sawdust",
	"barbed", "jersey", "block_fbs", "radio_mast", "dish", "bench", "campfire", "clothesline", "well_", "outhouse", "watch_tower", "mil_tower"]
var _zones: Array = []               # зоны: [центр, угол, полудлина, полуширина, тип] — для карты зон
var _foot: Array = []                 # следы поставленных зданий и машин: [центр, угол, полуширина, полуглубина] (тайлы)
var _fcache := {}
var _shifting := false

# след модели (повёрнутый прямоугольник по AABB) или [] — если это не здание/машина
func _footprint(model: String, tx: float, ty: float, th: float) -> Array:
	if not _fcache.has(model):
		var ab: AABB = _meshes[model].get_aabb()
		if _meshes.has(model + "_roof"):
			ab = ab.merge(_meshes[model + "_roof"].get_aabb())        # свес крыши — тоже след
		var ok := ab.size.y >= 1.2 and ab.size.x * ab.size.z >= 4.0
		for sk in FOOT_SKIP:
			if model.contains(sk):
				ok = false
		_fcache[model] = ab if ok else null
	var ab2 = _fcache[model]
	if ab2 == null:
		return []
	var g := 0.6 if (ab2.size.y > 2.2 and not model.begins_with("car_") and not model.begins_with("tractor")) else -0.1   # между зданиями — проход ~1 м
	var c3: Vector3 = Basis(Vector3.UP, th) * ab2.get_center() * S
	return [Vector2(tx + c3.x * M, ty + c3.z * M), th, ab2.size.x * 0.5 * S * M + g, ab2.size.z * 0.5 * S * M + g]

const ROAD_CLEAR := 2.3               # след здания не ближе к осевой дороги (тайлы): полотно ~1,6 + обочина
const ASPHALT_CLEAR := 3.7            # от осевой асфальта (его край ~3,6 тайла)
const ROAD_PUSH_MAX := 5.0            # насколько можно отодвинуть здание от дороги
const ON_ROAD := ["car_", "tractor", "trailer", "wagon", "bus_stop", "boat", "pier", "bridge"]
var _road_push := false
func _on_road_ok(model: String) -> bool:                               # true — модель должна стоять вне дороги
	if model == "boat_shed":
		return true
	for k in ON_ROAD:
		if model.begins_with(k):
			return false
	return true

# ближайшая к следу точка дорог (просёлки и рельсы тоже): [расстояние, точка на дороге]
func _road_hit(fp: Array) -> Array:
	var u := Vector2(cos(fp[1]), -sin(fp[1]))
	var v := Vector2(sin(fp[1]), cos(fp[1]))
	var best := [999.0, Vector2.ZERO]
	var c: Vector2 = fp[0]
	var ext: float = float(fp[2]) + float(fp[3]) + ROAD_CLEAR
	for rd in WorldGen._roads:
		if not rd.bb.grow(ext + 2.0).has_point(c):
			continue
		var clr: float = 3.0 if rd.get("rail", false) else (ROAD_CLEAR if rd.track else ASPHALT_CLEAR)   # асфальт виден до ~3,6 тайла от оси
		var pts: PackedVector2Array = rd.pts
		for i in 5:
			for j in 5:
				var q: Vector2 = c + u * float(fp[2]) * (i / 2.0 - 1.0) + v * float(fp[3]) * (j / 2.0 - 1.0)
				for k in pts.size() - 1:
					var cp := Geometry2D.get_closest_point_to_segment(q, pts[k], pts[k + 1])
					var d := q.distance_to(cp) - clr + ROAD_CLEAR          # приведено к ROAD_CLEAR: меньше — задевает
					if d < best[0]:
						best = [d, cp]
	return best

# точка дороги не задевает уже поставленные здания и машины
func _road_pt_free(q: Vector2) -> bool:
	for f in _foot:
		var d: Vector2 = q - f[0]
		if d.length() > float(f[2]) + float(f[3]) + ROAD_CLEAR:
			continue
		var lx := d.x * cos(f[1]) - d.y * sin(f[1])
		var ly := d.x * sin(f[1]) + d.y * cos(f[1])
		if absf(lx) < float(f[2]) + ROAD_CLEAR - 0.4 and absf(ly) < float(f[3]) + ROAD_CLEAR - 0.4:
			return false
	return true

func _clip_street(site: Vector2, dir: Vector2, len: float) -> Vector2:
	var s := 0.0
	while s + 1.0 <= len and _road_pt_free(site + dir * (s + 1.0)):
		s += 1.0
	return site + dir * s

func ab_big(model: String) -> bool:                                    # здание (не машина/мелочь): сдвигать «куда влезет» нельзя
	return _meshes[model].get_aabb().size.y > 2.6 and not model.begins_with("car_") and not model.begins_with("tractor")

var _fences: Array = []              # следы секций заборов и ворот (тонкие прямоугольники)
func _fence_rect(model: String, tx: float, ty: float, th: float) -> Array:
	var ab: AABB = _meshes[model].get_aabb()
	var c3: Vector3 = Basis(Vector3.UP, th) * ab.get_center() * S
	return [Vector2(tx + c3.x * M, ty + c3.z * M), th, ab.size.x * 0.5 * S * M - 0.1, maxf(ab.size.z * 0.5 * S * M - 0.1, 0.05)]

func _fences_hit(fp: Array) -> Array:                                  # индексы секций забора, которые задевает след
	var out := []
	for i in _fences.size():
		var q: Array = _fences[i]
		if (q[0] as Vector2).distance_to(fp[0]) < float(q[2]) + float(q[3]) + float(fp[2]) + float(fp[3]) and _rect_overlap(fp, q):
			out.append(i)
	return out

func _foot_free(fp: Array) -> bool:
	for q in _foot:
		if (q[0] as Vector2).distance_to(fp[0]) < float(q[2]) + float(q[3]) + float(fp[2]) + float(fp[3]) and _rect_overlap(fp, q):
			return false
	return true

# ---------------- установка предмета ----------------
func put(model: String, tx: float, ty: float, yaw_deg: float, mode := "", occ := true) -> bool:
	if not _meshes.has(model):
		return false
	var t := WorldGen.terrain(tx, ty)
	var wet_ok := model == "pier" or model.begins_with("boat") or model == "bridge"
	if (t[1] > 0.02 and not wet_ok) or t[2] > 0.6:
		return false
	if not wet_ok and occ and (HOUSE.has(model) or FOOT.has(model) or RAD.has(model) or model.begins_with("car_")):
		var rw := _rad(model) * 0.7
		for k in 4:                                                   # край постройки — тоже не в воде
			var a := k * PI / 2.0 + 0.4
			if WorldGen.terrain(tx + cos(a) * rw, ty + sin(a) * rw)[1] > 0.02:
				return false
	var th := deg_to_rad(yaw_deg)
	var yb := Basis(Vector3.UP, th)
	var y: float
	var house := HOUSE.has(model)
	var fp := _footprint(model, tx, ty, deg_to_rad(yaw_deg))
	var fence_fr := []
	if model.begins_with("fence") or model.begins_with("gate"):          # забор не проходит сквозь здания и машины — секция пропускается
		var fr := _fence_rect(model, tx, ty, deg_to_rad(yaw_deg))
		for q in _foot:
			if (q[0] as Vector2).distance_to(fr[0]) < float(q[2]) + float(q[3]) + float(fr[2]) + float(fr[3]) and _rect_overlap(fr, q):
				_rej["забор сквозь постройку"] = _rej.get("забор сквозь постройку", 0) + 1
				return false
		fence_fr = fr
	var mobile := model.begins_with("car_") or model.begins_with("tractor") or model.begins_with("trailer")
	if not fp.is_empty() and mobile and not _fences_hit(fp).is_empty():
		return false                                                    # машина не стоит в заборе
	if not fp.is_empty() and not _foot_free(fp):
		if _shifting:
			return false
		# место занято — сдвинуть рядом (здание — до 8 тайлов, дом во дворе — до 3), иначе не ставить
		var lim := 0.0 if (house or ab_big(model)) else 3.0
		_shifting = true
		var done := false
		for r: float in [1.5, 3.0, 5.0, 8.0]:
			if r > lim or done:
				break
			for k in 8:
				var a := k * TAU / 8.0 + r
				if put(model, tx + cos(a) * r, ty + sin(a) * r, yaw_deg, mode, occ):
					done = true
					break
		_shifting = false
		if not done:
			_rej["наложение"] = _rej.get("наложение", 0) + 1
		return done
	if not fp.is_empty() and _on_road_ok(model):
		var rh := _road_hit(fp)                                        # след здания задевает дорогу — отодвинуть от неё, иначе не ставить
		if rh[0] < ROAD_CLEAR:
			if _road_push:
				return false
			var need: float = ROAD_CLEAR - float(rh[0]) + 0.4
			var away: Vector2 = (fp[0] - rh[1]).normalized()
			var ok2 := false
			if need <= ROAD_PUSH_MAX and not house:                       # дом двора не уводить с участка
				_road_push = true
				ok2 = put(model, tx + away.x * need, ty + away.y * need, yaw_deg, mode, occ)
				_road_push = false
			if not ok2:
				_rej["на дороге"] = _rej.get("на дороге", 0) + 1
			return ok2
	if occ and not fp.is_empty() and not house and ab_big(model):
		for q in _plots:                                              # здание целиком — не во дворе чужого участка
			if _rect_overlap(fp, q):
				return false
	if house and occ and (_near_bunker(Vector2(tx, ty)) or WorldGen.path_dist(tx, ty) < _rad(model) * 0.75 + 1.5):
		return false                                                    # дом — не на дороге и не у бункера
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
	elif mode == "dash":
		y = _h(tx, ty) + 0.03
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
	if not fp.is_empty():
		_foot.append(fp)
		if model.begins_with("car_") or model.begins_with("tractor"):
			WorldGen.add_clear(fp[0].x, fp[0].y, fp[2] + 1.5, fp[3] + 1.5, fp[1])   # дерево не растёт сквозь машину
	if not fp.is_empty() and not mobile:                              # здание встало на готовый забор — эти секции убрать
		var hits := _fences_hit(fp)
		hits.reverse()
		for i in hits:
			var q: Array = _fences[i]
			(_batch[q[4]].xf as Array).erase(q[5])
			_fences.remove_at(i)
	_add(model, tx, ty, xf)
	if not fence_fr.is_empty():
		_fences.append(fence_fr + ["%s|%d|%d" % [model, int(floor(tx / CELL)), int(floor(ty / CELL))], xf])
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
	if _near_bunker(c):
		_rej["бункер"] = _rej.get("бункер", 0) + 1; _last = "бункер"
		return false
	var rect := [c, th, w / 2.0, d / 2.0]
	for q in _plots:
		if _rect_overlap(rect, q):
			_rej["участок"] = _rej.get("участок", 0) + 1; _last = "участок " + str(q)
			return false
	# дешёвые проверки — до рельефа
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
	for i in 5:
		for j in 5:
			var p := _loc(c, th, (i / 4.0 - 0.5) * w * 0.96, (j / 4.0 - 0.5) * d * 0.96)
			var t := WorldGen.terrain(p.x, p.y)
			if t[1] > 0.02 or t[2] > 0.5 or not WorldGen.in_map(p.x, p.y, 3.0):
				_rej["вода/скалы"] = _rej.get("вода/скалы", 0) + 1; _last = "вода/скалы"
				return false
			if j < 4 and (t[7] < 2.2 or t[8] < 3.7):                  # другая дорога через участок (передняя кромка — у своей улицы)
				_rej["дорога"] = _rej.get("дорога", 0) + 1; _last = "дорога"
				return false
	return true

# участок: kind — old (деревенский), new (новый дом), dacha
func _plot(c: Vector2, yaw: float, w: float, d: float, house: String, kind: String) -> bool:
	var th := deg_to_rad(yaw)
	if BURNT.has(house) and _rng.randf() < 0.12:
		house = BURNT[house]
	var hd: Array = HOUSE[house]
	var hl: float = hd[0] * M
	var hdp: float = hd[1] * M
	var por: float = hd[2] * M
	var side := -1.0 if _rng.randf() < 0.5 else 1.0                 # дом — у одной боковой стороны, подъезд — у другой
	var hx := side * (w / 2.0 - hl / 2.0 - 1.6 * M)
	var hy := d / 2.0 - 3.0 * M - por - hdp / 2.0
	var hp := _loc(c, th, hx, hy)
	if not put(house, hp.x, hp.y, yaw, "", false):                    # дом не встал — двора (забора, ворот, машины) тоже нет
		_rej["двор без дома"] = _rej.get("двор без дома", 0) + 1
		return false
	_plots.append([c, th, w / 2.0, d / 2.0])
	WorldGen.add_clear(c.x, c.y, w / 2.0, d / 2.0, th)
	WorldGen.add_clear(hp.x, hp.y, hl * 0.5 + 6.5 * M, (hdp + por) * 0.5 + 6.5 * M, th)   # крона лесного дерева не нависает над домом
	_occ.append([hp, maxf(hl, hdp) * 0.5])
	if _rng.randf() < 0.3:                                            # надпись краской на фасаде
		var F := Vector2(sin(th), cos(th))
		var gp0 := hp + F * (hdp / 2.0 + 0.03 * M) + Vector2(cos(th), -sin(th)) * _rng.randf_range(-hl * 0.2, hl * 0.2)
		var gfx: String = (["graffiti_chisto", "graffiti_ne_vhodit", "graffiti_lager", "graffiti_zarazheno", "graffiti_pomogite", "graffiti_ludi"] if kind != "new" else ["graffiti_chisto", "graffiti_ne_vhodit", "graffiti_zarazheno", "graffiti_pomogite"])[_rng.randi() % (6 if kind != "new" else 4)]
		put(gfx, gp0.x, gp0.y, yaw, "pt", false)
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
	# уходили в спешке: вещи брошены у калитки, иногда детская коляска
	if _rng.randf() < 0.3:
		var bp := _loc(c, th, gx + _rng.randf_range(-1.5, 1.5) * M, d / 2.0 - 1.6 * M)
		put(["suitcases", "bags", "stroller", "bags"][_rng.randi() % 4], bp.x, bp.y, _rng.randf() * 360.0, "pt", false)
	# машина на подъезде, носом к улице
	if _rng.randf() < (0.7 if kind == "new" else 0.22):
		var cp := _loc(c, th, gx, d / 2.0 - 4.2 * M)
		put(YARD_CARS[_rng.randi() % YARD_CARS.size()], cp.x, cp.y, yaw - 90.0 + _rng.randf_range(-6, 6), "", false)
	# сад: 1–2 яблони у огорода (подальше от построек)
	if room > 8.0 * M:
		for k in (1 + _rng.randi() % 2):
			var ap := _loc(c, th, -side * (w / 2.0 - (2.5 + k * 5.0) * M), back1 + 6.0 * M + k * 1.5 * M)
			var sp: String = WorldGen.APPLE[_rng.randi() % WorldGen.APPLE.size()] if _rng.randf() < 0.75 else ("cherry_a" if _rng.randf() < 0.5 else "cherry_b")
			WorldGen.add_tree(ap.x, ap.y, sp)                      # яблоня, иногда черёмуха
	return true

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
# дорога «начинается у места», если её конец ближе этого (у локаций с обрезанными дорогами — у края двора)
func _end_r(site: Vector2) -> float:
	for key in WorldGen.ROAD_END:
		var f: Dictionary = WorldGen.site(key)
		if site.distance_to(Vector2(f.x, f.y)) < 1.0:
			return float(WorldGen.ROAD_END[key]) + 4.0
	return 4.0

func _road_dir(site: Vector2) -> Vector2:
	for rd in WorldGen._roads:
		var pts: PackedVector2Array = rd.pts
		if pts[0].distance_to(site) < _end_r(site):
			return (pts[3] - pts[0]).normalized()
		if pts[pts.size() - 1].distance_to(site) < _end_r(site):
			return (pts[pts.size() - 4] - pts[pts.size() - 1]).normalized()
	return Vector2(1, 0)

func _road_dirs(site: Vector2) -> Array:
	var out: Array = []
	for rd in WorldGen._roads:
		var pts: PackedVector2Array = rd.pts
		if pts.size() < 5 or rd.get("rail", false):
			continue
		if pts[0].distance_to(site) < _end_r(site):
			out.append((pts[3] - pts[0]).normalized())
		elif pts[pts.size() - 1].distance_to(site) < _end_r(site):
			out.append((pts[pts.size() - 4] - pts[pts.size() - 1]).normalized())
	return out

# прямая улица через центр поселения: участки по обе стороны; улица добавляется в дороги мира (рисуется на земле)
func _street(site: Vector2, own: String, dir: Vector2, half_len: float, free_r: float, houses: Array, kind: String, w: float, d: float, cap := 999) -> int:
	if houses.is_empty():
		return 0
	# въездные дороги, идущие вдоль улицы, внутри поселения выпрямляются по улице (иначе петляют через дворы)
	for rd in WorldGen._roads:
		var rp: PackedVector2Array = rd.pts
		if rp.size() < 5 or (rp[0].distance_to(site) > _end_r(site) and rp[rp.size() - 1].distance_to(site) > _end_r(site)):
			continue
		var ends_at0 := rp[0].distance_to(site) <= _end_r(site)
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
		var free := true
		for i in np.size() - 1:                                         # выпрямленная дорога не должна пройти по уже стоящим зданиям
			if np[i] != rp[i] or np[i + 1] != rp[i + 1]:
				for t in 4:
					if not _road_pt_free(np[i].lerp(np[i + 1], t / 4.0)):
						free = false
		if not free:
			_rej["улица: дорогу не выпрямить"] = _rej.get("улица: дорогу не выпрямить", 0) + 1
			continue
		rd["pts"] = np
		rd["bb"] = bb.grow(4.0)
	var placed := 0
	var hi := 0
	var step := w + 1.5 * M
	var nrm0 := Vector2(-dir.y, dir.x)
	var want := mini(cap, houses.size()) if cap < 999 else houses.size()
	# места — ровной сеткой от центра наружу, по обе стороны; без сдвигов: занято — место пустует
	var slots: Array = []
	var s_start := (free_r if free_r > 0.0 else 0.0) + step * 0.5      # первый участок — сразу за площадью
	var k := 0
	while s_start + (k + 0.5) * step <= half_len + 0.01:
		for e: float in [1.0, -1.0]:
			slots.append(e * (s_start + k * step))
		k += 1
	var smax := 0.0
	for s0: float in slots:
		if placed >= want:
			break
		for sd: float in [1.0, -1.0]:
			if placed >= want:
				break
			var nrm := nrm0 * sd
			var fdir := -nrm                                       # фасад — к улице
			var th := atan2(fdir.x, fdir.y)
			var c := site + dir * s0 + nrm * (4.2 + d / 2.0)
			var okp := _plot_ok(c, th, w, d, own)
			if OS.get_environment("PLOTDBG") == own:
				print("PLOT %s s=%.0f sd=%d c=(%.0f,%.0f) %s" % [own, s0, sd, c.x, c.y, "ok" if okp else _last.substr(0, 40)])
			if okp and _plot(c, rad_to_deg(th), w, d, houses[hi % houses.size()], kind):
				hi += 1
				placed += 1
				smax = maxf(smax, absf(s0) + w * 0.5)
	if placed == 0:
		return 0
	var hl := maxf(smax, minf(half_len, 12.0))
	_zones.append([site, atan2(dir.x, dir.y) + PI / 2.0, hl, 4.2 + d, "жильё"])
	var a := _clip_street(site, -dir, hl + 3.0)                       # улица кончается перед чужим зданием (не идёт сквозь него)
	var b := _clip_street(site, dir, hl + 3.0)
	var pts := PackedVector2Array([a, site, b])
	WorldGen._roads.append({"pts": pts, "bb": Rect2(a, Vector2.ZERO).expand(b).grow(4.0), "track": true})
	for e: float in [-1.0, 1.0]:                                       # знак «населённый пункт» на въездах
		var sp := site + dir * e * (hl + 1.0) + nrm0 * 3.6 * e
		put("sign_town", sp.x, sp.y, rad_to_deg(atan2(-dir.y, dir.x)) + 90.0 * e, "pt", false)
	var ls := -hl + 6.0
	while ls < hl - 4.0:                                               # фонари вдоль улицы
		var lp := site + dir * ls + nrm0 * 3.3
		var bd := -nrm0
		put("lamp_post", lp.x, lp.y, rad_to_deg(atan2(-bd.y, bd.x)), "pt", false)
		ls += 30.0
	return placed

# сколько участков встанет вдоль улицы (без постройки)
func _street_count(site: Vector2, own: String, dir: Vector2, half_len: float, free_r: float, w: float, d: float) -> int:
	var step := w + 1.5 * M
	var nrm0 := Vector2(-dir.y, dir.x)
	var n := 0
	var k := 0
	var s_start := (free_r if free_r > 0.0 else 0.0) + step * 0.5
	while s_start + (k + 0.5) * step <= half_len + 0.01:
		for e: float in [1.0, -1.0]:
			var s0 := e * (s_start + k * step)
			for sd: float in [1.0, -1.0]:
				var nrm := nrm0 * sd
				if _plot_ok(site + dir * s0 + nrm * (4.2 + d / 2.0), atan2(-nrm.x, -nrm.y), w, d, own):
					n += 1
		k += 1
	return n

# общественное здание фасадом к улице: s — место вдоль улицы, sd — сторона; отступ от оси улицы по глубине здания
func _front_put(model: String, site: Vector2, dir: Vector2, s: float, sd: float) -> bool:
	if not _meshes.has(model):
		return false
	var ab: AABB = _meshes[model].get_aabb()
	var nrm := Vector2(-dir.y, dir.x) * sd
	var fdir := -nrm
	var th := atan2(fdir.x, fdir.y)
	var c := site + dir * s + nrm * (5.5 + ab.size.z * 0.5 * M)
	if put(model, c.x, c.y, rad_to_deg(th), "min"):
		var wz := ab.size.x * 0.5 * M + 1.5
		var dz := ab.size.z * 0.5 * M + 2.0
		_plots.append([c, th, wz, dz])                                # участок здания — дома не встанут поверх
		WorldGen.add_clear(c.x, c.y, wz + 2.0, dz + 2.0, th)
		return true
	return false

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
	var tw: Dictionary = WorldGen.FEATURES["tower"]
	WorldGen.add_clear(tw.x, tw.y, 20.0, 20.0, 0.0)                     # площадка радиовышки — без леса
	for key in LOCS:
		var f: Dictionary = WorldGen.FEATURES[key]
		var c := Vector2(f.x, f.y)
		# двор локации развёрнут по въездной дороге (у рыбацкой базы — по воде, у лагеря и деревни — как есть)
		var th := 0.0
		var cands := []
		if key in ["sawmill", "farm", "tower"]:                          # двор по въездной дороге: из 4 поворотов — где меньше зданий на дороге
			var rd := _road_dir(c)
			for k in 4:
				cands.append(atan2(rd.x, rd.y) + PI + k * PI / 2.0)
		elif key == "camp":                                              # в лагере сходятся дороги: палатки между ними
			for i in 24:
				cands.append(i * TAU / 24.0)
		if not cands.is_empty():
			var best := INF
			for t in cands:
				var hits := 0.0
				for p in LOCS[key]:
					var lp := Vector2(p[1] * K, p[2] * K).rotated(-t)
					var fp := _footprint(p[0], c.x + lp.x, c.y + lp.y, deg_to_rad(p[3]) + t)
					if not fp.is_empty() and _on_road_ok(p[0]) and _road_hit(fp)[0] < ROAD_CLEAR:
						hits += float(fp[2]) * float(fp[3])               # крупное здание на дороге — хуже мелочи
				if hits < best - 0.01:
					best = hits
					th = t
			_rej["поворот " + key] = "%d° задели %.0f" % [roundi(rad_to_deg(th)), best]
		loc_th[key] = th
		var far := 0.0
		for p in LOCS[key]:
			far = maxf(far, Vector2(p[1], p[2]).length() * K)
		if key != "lakebase":
			WorldGen.add_clear(c.x, c.y, far + 5.0, far + 5.0, th)          # двор целиком без леса (деревья не растут на штабелях)
		for p in LOCS[key]:
			var nm: String = p[0]
			var k: float = 1.0 if (nm == "pier" or nm.begins_with("boat")) else K
			var q := c + Vector2(p[1] * k, p[2] * k).rotated(-th)
			var yaw: float = p[3] + rad_to_deg(th)
			if _meshes.has(nm) and (ab_big(nm) or FOOT.has(nm) or nm.begins_with("tent") or nm.begins_with("tarp")):
				q = _off_road(q, _rad(nm))                            # здание не на дороге: отодвинуть от неё
			var okl := put(nm, q.x, q.y, yaw)
			if OS.get_environment("LOCDBG") == key:
				var fpd := _footprint(nm, q.x, q.y, deg_to_rad(yaw)) if _meshes.has(nm) else []
				print("LOC %s %s @%d:%d %s дорога %s" % [key, nm, roundi(q.x), roundi(q.y), "ok" if okl else "НЕТ", str(_road_hit(fpd)[0]) if not fpd.is_empty() else "-"])

# точка подальше от дороги: шагами по уклону расстояния до дороги, пока до неё не станет r + 2 тайла
func _off_road(q: Vector2, r: float) -> Vector2:
	for i in 12:
		var pd := WorldGen.path_dist(q.x, q.y)
		if pd >= r + 2.0:
			break
		var gx := WorldGen.path_dist(q.x + 1.0, q.y) - WorldGen.path_dist(q.x - 1.0, q.y)
		var gy := WorldGen.path_dist(q.x, q.y + 1.0) - WorldGen.path_dist(q.x, q.y - 1.0)
		var g := Vector2(gx, gy)
		if g.length() < 0.01:
			g = Vector2(1, 0)
		q += g.normalized() * 1.5
	return q

func _towns() -> void:
	for key in TOWNS:
		var f: Dictionary = WorldGen.FEATURES[key]
		var c := Vector2(f.x, f.y)
		var t: Dictionary = TOWNS[key]
		var n: int = t.houses.size()
		var w := 19.0
		var d := 28.0
		var got := 0
		var first := true
		var streets := 0
		var used_dirs: Array = []
		var tries: Array = []
		for dv: Vector2 in _road_dirs(c):                              # улица — вдоль одной дороги из локации (первой, где встанет)
			for ex_off: float in [0.0, 18.0, 36.0]:
				tries.append([dv, ex_off])
		for tr in tries:                                               # по очереди вдоль каждой дороги, пока не встанут все дома
			if got >= n:
				break
			var dir: Vector2 = tr[0]
			var site: Vector2 = c + dir * (f.r * K + float(t.off) + float(tr[1]))
			var rest: Array = t.houses.slice(got)
			var half: float = ceilf(rest.size() / 2.0) * (w + 1.5 * M) * 0.5 + w * 0.5 + 2.0
			if streets >= 2:
				break                                                      # не больше двух улиц, каждая вдоль своей дороги
			if used_dirs.has(dir):
				continue
			var g := _street(site, key, dir, half, 0.0, rest, t.kind, w, d, rest.size())
			if g > 0:
				if first:
					for ex in t.extra:
						_front_put(ex, site, dir, half + 8.0, 1.0)
				first = false
				streets += 1
				used_dirs.append(dir)
			got += g
		_rej["город " + key] = "%d/%d" % [got, n]

func _near_bunker(p: Vector2) -> bool:
	var b: Dictionary = WorldGen.FEATURES["bunker"]
	return p.distance_to(Vector2(b.x, b.y)) < NO_HOMES_R

# деревня: площадь в центре (колодец, магазин, клуб, остановка), улицы вдоль всех дорог
func _village() -> void:
	var v: Dictionary = WorldGen.FEATURES["village"]
	var vc := Vector2(v.x, v.y)
	var dirs := _road_dirs(vc)
	var d1: Vector2 = dirs[0] if dirs.size() > 0 else Vector2(1, 0)
	var d2 := d1.orthogonal()                                          # поперечная — строго под прямым углом
	var th := atan2(d1.x, d1.y)
	WorldGen.add_clear(vc.x, vc.y, 14.0, 14.0, th)                     # площадь
	_zones.append([vc, th, 14.0, 14.0, "площадь"])
	# у площади: на главной улице — администрация и школа, на поперечной — ФАП, пожарная, магазин, клуб
	var sq := 16.0
	_front_put("admin", vc, d1, sq + 9.0, 1.0)
	_front_put("school", vc, d1, sq + 16.0, -1.0)
	_front_put("fap", vc, d2, sq + 7.0, 1.0)
	_front_put("fire_station", vc, d2, sq + 9.0, -1.0)
	_front_put("shop", vc, d2, -(sq + 6.0), 1.0)
	_front_put("club", vc, d2, -(sq + 8.0), -1.0)
	var bs := vc + d1 * 6.0 + d1.orthogonal() * 7.5
	put("bus_stop", bs.x, bs.y, rad_to_deg(atan2(-d1.orthogonal().x, -d1.orthogonal().y)))
	var got := _street(vc, "village", d1, 115.0, sq, VILLAGE_HOUSES, "old", 19.0, 30.0, VILLAGE_HOUSES.size())
	if got < VILLAGE_HOUSES.size():
		var rest: Array = VILLAGE_HOUSES.slice(got)
		got += _street(vc, "village", d2, 95.0, 4.2 + 30.0, rest, "old", 19.0, 30.0, rest.size())   # поперечная — за дворами главной улицы
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
		# главная улица — вдоль той дороги, где встаёт больше домов (проба без постройки); большой посёлок — ещё поперечная
		var rd0 := _road_dirs(c)
		if rd0.is_empty():
			rd0 = [Vector2(1, 0)]
		var per_street: int = n if n <= 6 else ceili(n / 2.0)
		var half: float = (10.0 if n > 6 else 0.0) + (ceilf(per_street / 4.0) + 1.0) * (w + 1.5 * M)   # ровно под дома + одно запасное место
		var best: Vector2 = rd0[0]
		var bn := -1
		for dv: Vector2 in rd0 + rd0.map(func(x): return x.orthogonal()):
			var cnt := _street_count(c, key, dv, half, 10.0 if n > 6 else 0.0, w, d)
			if cnt > bn:
				bn = cnt
				best = dv
		got = _street(c, key, best, half, 10.0 if n > 6 else 0.0, s.houses, s.kind, w, d, n)
		if got < n and n > 6:
			var rest: Array = s.houses.slice(got)
			got += _street(c, key, best.orthogonal(), half, 10.0, rest, s.kind, w, d, rest.size())
		if OS.is_debug_build() and OS.has_feature("editor"):
			pass
		_rej["поставлено " + key] = "%d/%d" % [got, n]
		for p in s.ext:
			put(p[0], h.x + p[1] * K, h.y + p[2] * K, p[3])
		if s.get("shop", false):
			_free_put("shop", c, 11.0, 45.0)
		WorldGen.add_clear(c.x, c.y, 5.0, 5.0, 0.0)

# ---------------- бункер: бетонная площадка, военный периметр, вышки по углам, КПП у ворот на дорогу ----------------
func _bunker() -> void:
	var f: Dictionary = WorldGen.FEATURES["bunker"]
	var c := Vector2(f.x, f.y)
	# ворота — туда, куда уходит первая дорога
	var gdir := Vector2(0, 1)
	for rd in WorldGen._roads:
		var pts: PackedVector2Array = rd.pts
		if pts[0].distance_to(c) < _end_r(c):
			gdir = (pts[2] - pts[0]).normalized()
			break
		if pts[pts.size() - 1].distance_to(c) < _end_r(c):
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
			if WorldGen.forest_mask(p.x, p.y) > 0.22 and WorldGen.in_map(p.x, p.y, 16.0) and WorldGen.terrain(p.x, p.y)[1] < 0.01 and not _near_bunker(p):
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
		if chosen.size() >= 6:
			break
		var ok := true
		for q in chosen:
			if p.distance_to(q) < 48.0:
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
		var through := false
		for q in trail:
			if not _road_pt_free(q):
				through = true
		if through:
			why["тропа через дом"] = why.get("тропа через дом", 0) + 1
			continue
		if not _plot(p, rad_to_deg(th), w, d, FOREST_HOUSES[(chosen.size() + 1) % FOREST_HOUSES.size()], "old"):
			continue
		chosen.append(p)
		why["где"] = why.get("где", "") + "%d:%d " % [roundi(p.x), roundi(p.y)]
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
func _near_center(p: Vector2, pad: float) -> bool:                  # рядом с локацией или посёлком (без учёта расчисток)
	for key in WorldGen.FEATURES:
		var f: Dictionary = WorldGen.FEATURES[key]
		if Vector2(p.x - f.x, p.y - f.y).length() < f.r * K + pad:
			return true
	for key in WorldGen.HAMLETS:
		var h: Dictionary = WorldGen.HAMLETS[key]
		if Vector2(p.x - h.x, p.y - h.y).length() < h.r + pad:
			return true
	return false

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
		if pts.size() < 5 or rd.get("rail", false):
			continue                                                  # улицы поселений, железная дорога
		# столбы вдоль дороги (на просёлках — реже) и провода между ними
		var poles: Array = []
		var acc := 0.0
		for i in pts.size() - 1:
			var seg := pts[i + 1] - pts[i]
			var L := seg.length()
			var dir := seg / maxf(L, 1e-3)
			var d := 0.0
			while d < L:
				if acc <= 0.0:
					var p := pts[i] + dir * d + Vector2(-dir.y, dir.x) * 3.4
					var yaw0 := rad_to_deg(atan2(-dir.y, dir.x)) + 90.0
					if not _near_site(p, 2.0) and not (track and _rng.randf() < 0.6) and put("pole_wood", p.x, p.y, yaw0):
						if not poles.is_empty() and (poles[-1][0] as Vector2).distance_to(p) < 24.0:
							_wires(poles[-1][0], poles[-1][1], p, yaw0)
						poles.append([p, yaw0])
					else:
						poles.clear()
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

# провода ЛЭП между двумя столбами: по 2 провода на траверсе, с провисом
func _wires(p0: Vector2, yaw0: float, p1: Vector2, yaw1: float) -> void:
	for side: float in [-0.9, 0.9]:
		var a := _wire_pt(p0, yaw0, side)
		var b := _wire_pt(p1, yaw1, side)
		var mid := (a + b) * 0.5 - Vector3(0, 0.55, 0)
		for seg in [[a, mid], [mid, b]]:
			var s0: Vector3 = seg[0]
			var s1: Vector3 = seg[1]
			var xv := s1 - s0
			var zv := xv.cross(Vector3.UP).normalized()
			var yv := zv.cross(xv).normalized()
			_add("wire_unit", p0.x, p0.y, Transform3D(Basis(xv, yv, zv), s0))

func _wire_pt(p: Vector2, yaw: float, side: float) -> Vector3:
	var cb := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 0, -1)       # траверса столба (ось Y модели в Blender)
	return Vector3(p.x * T, _h(p.x, p.y) + 8.05, p.y * T) + cb * side

# разметка по оси асфальтовых дорог (кроме поселений), мосты через реку
func _road_marks() -> void:
	for rd in WorldGen._roads:
		var pts: PackedVector2Array = rd.pts
		if rd.track or pts.size() < 5:
			continue
		var acc := 0.0
		var wet_run: Array = []
		for i in pts.size() - 1:
			var seg := pts[i + 1] - pts[i]
			var L := seg.length()
			var dir := seg / maxf(L, 1e-3)
			var d := 0.0
			while d < L:
				var p := pts[i] + dir * d
				var tw := WorldGen.terrain(p.x, p.y)
				var river := tw[1] > 0.3 and WorldGen.river_dist(p.x, p.y) < 4.0 and WorldGen.ford_factor(p.x, p.y) < 0.5
				if river:
					wet_run.append([p, dir])
				elif not wet_run.is_empty():
					var a: Vector2 = wet_run[0][0]
					var b: Vector2 = wet_run[-1][0]
					var c := (a + b) * 0.5
					var bd: Vector2 = wet_run[0][1]
					var ya := maxf(_h(a.x - bd.x * 9.0, a.y - bd.y * 9.0), _h(b.x + bd.x * 9.0, b.y + bd.y * 9.0))
					var yaw := rad_to_deg(atan2(-bd.y, bd.x))
					var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), Vector3(c.x * T, ya + 0.15, c.y * T))
					_add("bridge", c.x, c.y, xf)
					WorldGen.add_clear(c.x, c.y, 17.0, 7.0, deg_to_rad(yaw))
					_rej["мостов"] = str(_rej.get("мостов", "")) + "%d:%d " % [roundi(c.x), roundi(c.y)]
					if not _rej.has("колонна у моста"):                     # брошенная колонна перед первым мостом: пытались уехать
						var cv := ["car_bus_yellow", "car_van_white", "car_sedan_white", "car_crossover_silver", "car_solaris_wreck", "car_truck_green", "car_hatch_red"]
						var dist := 12.0
						for k in cv.size():
							var ln: float = _meshes[cv[k]].get_aabb().size.x * M if _meshes.has(cv[k]) else 6.0
							dist += ln * 0.5
							var q: Vector2 = a - bd * dist + bd.orthogonal() * (1.2 if k % 2 == 0 else -0.6)
							put(cv[k], q.x, q.y, yaw + _rng.randf_range(-6, 6), "", false)
							dist += ln * 0.5 + 2.5                              # промежуток ~2 м между машинами
						_rej["колонна у моста"] = "%d:%d" % [roundi(a.x), roundi(a.y)]
					wet_run.clear()
				if acc <= 0.0 and not river and tw[1] < 0.02 and not _near_site(p, 6.0):
					put("road_dash", p.x, p.y, rad_to_deg(atan2(-dir.y, dir.x)), "dash", false)
				if acc <= 0.0:
					acc = 7.2
				d += 1.2
				acc -= 1.2

# пешеходные переходы: стёртая «зебра» на асфальте у центров деревень и хуторов, школы, магазинов, остановок
const ZEBRA_AT := ["school", "shop", "supermarket", "bus_stop", "cafe", "fap", "admin"]
func _crosswalks() -> void:
	var sites: Array = []
	var v: Dictionary = WorldGen.FEATURES["village"]
	sites.append(Vector2(v.x, v.y))
	for k in WorldGen.HAMLETS:
		sites.append(Vector2(WorldGen.HAMLETS[k].x, WorldGen.HAMLETS[k].y))
	for key in _batch:
		if _batch[key].model in ZEBRA_AT:
			for xf: Transform3D in _batch[key].xf:
				sites.append(Vector2(xf.origin.x, xf.origin.z) / T)
	var made: Array = []
	for st: Vector2 in sites:
		var best := 1e9
		var cp := Vector2.ZERO
		var dir := Vector2.RIGHT
		for rd in WorldGen._roads:
			if rd.track:
				continue
			var pts: PackedVector2Array = rd.pts
			for i in pts.size() - 1:
				var q := Geometry2D.get_closest_point_to_segment(st, pts[i], pts[i + 1])
				var d := st.distance_to(q)
				if d < best:
					best = d
					cp = q
					dir = (pts[i + 1] - pts[i]).normalized()
		if best > 22.0 or WorldGen.terrain(cp.x, cp.y)[1] > 0.02:
			continue
		var dup := false
		for m: Vector2 in made:
			if m.distance_to(cp) < 25.0:
				dup = true
		if dup:
			continue
		made.append(cp)
		var yaw := atan2(-dir.y, dir.x)
		var lat := dir.orthogonal()
		for k in 5:                                                    # 5 полос по 0,4 м поперёк дороги (~4 м), каждая 2,6 м вдоль
			var p := cp + lat * ((k - 2) * 0.85 * M)
			var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(0.87, 1.0, 3.4)), Vector3(p.x * T, _h(p.x, p.y) + 0.04, p.y * T))
			_add("road_dash", p.x, p.y, xf)
	_rej["переходов"] = made.size()

# ---------------- следы карантина: блокпосты на дорогах, брошенная колонна, вещи ----------------
func _road_of(a: String, b: String) -> PackedVector2Array:
	for i in WorldGen.ROADS.size():
		var r: Array = WorldGen.ROADS[i]
		if (r[0] == a and r[1] == b) or (r[0] == b and r[1] == a):
			return WorldGen._roads[i].pts
	return PackedVector2Array()

func _road_len(pts: PackedVector2Array) -> float:
	var t := 0.0
	for i in pts.size() - 1:
		t += pts[i].distance_to(pts[i + 1])
	return t

func _quarantine() -> void:
	for ps in [["camp", "sawmill", 0.5], ["farm", "bunker", 0.5], ["village", "tower", 0.55]]:
		var pts := _road_of(ps[0], ps[1])
		if pts.is_empty():
			continue
		var at := _at(pts, _road_len(pts) * float(ps[2]))
		var c: Vector2 = at[0]
		var dir: Vector2 = at[1]
		var nrm := Vector2(-dir.y, dir.x)
		var along := rad_to_deg(atan2(-dir.y, dir.x))
		var across := rad_to_deg(atan2(-nrm.y, nrm.x))
		WorldGen.add_clear(c.x, c.y, 14.0, 12.0, deg_to_rad(along))
		_rej["блокпост"] = str(_rej.get("блокпост", "")) + "%d:%d " % [roundi(c.x), roundi(c.y)]
		for k: float in [-2.6, -1.6, 1.6, 2.6]:                           # бетонные блоки поперёк, проезд в середине
			var bp := c + nrm * k * 2.6 + dir * (0.6 if k > 0 else -0.6)
			put("block_fbs", bp.x, bp.y, across + _rng.randf_range(-8, 8), "pt", false)
		for sd: float in [-1.0, 1.0]:
			for k in 3:                                                # колючая спираль вдоль поля в стороны
				var cp := c + nrm * sd * (9.0 + k * 3.6)
				put("barbed_coil", cp.x, cp.y, across, "pt", false)
			var sp := c - dir * sd * 7.0 + nrm * sd * 4.0
			put("sign_quarantine", sp.x, sp.y, along + 90.0 * sd, "pt", false)
		var tp := c + nrm * 9.0 + dir * 5.0
		put("tent_med", tp.x, tp.y, along)
		var tr := c - nrm * 8.5 - dir * 4.0
		put("car_truck_green", tr.x, tr.y, along + 180.0)
		var wt := c - nrm * 7.5 + dir * 6.0
		put("mil_tower", wt.x, wt.y, along)
		var sb := c + nrm * 5.0 - dir * 2.5
		put("sandbags", sb.x, sb.y, across)
		var bg := c + nrm * 6.0 + dir * 10.0
		put("bags", bg.x, bg.y, _rng.randf() * 360.0, "pt", false)
	# брошенная колонна: машины одна за другой в сторону лагеря (эвакуация), вещи на обочине
	var cp := _road_of("camp", "village")
	if not cp.is_empty():
		var L := _road_len(cp)
		var s0 := L * 0.35
		var c0: Vector2 = _at(cp, s0 + 25.0)[0]
		_rej["колонна"] = "%d:%d" % [roundi(c0.x), roundi(c0.y)]
		for i in 9:
			var at2 := _at(cp, s0 + i * 6.2 * M)
			var p: Vector2 = at2[0]
			var d2: Vector2 = at2[1]
			var n2 := Vector2(-d2.y, d2.x)
			var q := p + n2 * 1.25
			var m: String = (["car_crossover_white", "car_solaris_silver", "car_van_white", "car_wagon_beige", "car_hatch_red", "car_niva_white", "car_granta_graphite", "car_bus_blue", "car_duster_brown"])[i]
			put(m, q.x, q.y, rad_to_deg(atan2(d2.y, -d2.x)) + _rng.randf_range(-7, 7), "", false)   # носом к лагерю
			if i % 2 == 0:
				var vp := p + n2 * (4.2 + _rng.randf() * 1.5)
				put(["suitcases", "bags", "stroller", "suitcases"][(i / 2) % 4], vp.x, vp.y, _rng.randf() * 360.0, "pt", false)
		var sp2 := _at(cp, s0 - 8.0)
		var spp: Vector2 = sp2[0] + Vector2(-sp2[1].y, sp2[1].x) * 4.0
		put("sign_quarantine", spp.x, spp.y, rad_to_deg(atan2(-sp2[1].y, sp2[1].x)) + 90.0, "pt", false)

# ---------------- новые места: железная дорога, АЗС с кафе, детский лагерь, свалка, крушение вертолёта ----------------
func _rail() -> Dictionary:
	for rd in WorldGen._roads:
		if rd.get("rail", false):
			return rd
	return {}

func _railway() -> void:
	var rd := _rail()
	if rd.is_empty():
		return
	var pts: PackedVector2Array = rd.pts
	var L := _road_len(pts)
	var step := 6.0 * M
	var s := 0.0
	var wet: Array = []
	while s < L:
		var at := _at(pts, s)
		var p: Vector2 = at[0]
		var dir: Vector2 = at[1]
		var yaw := rad_to_deg(atan2(-dir.y, dir.x))
		var tw := WorldGen.terrain(p.x, p.y)
		if tw[1] > 0.02:
			wet.append(p)
		else:
			if not wet.is_empty():                                     # мост через реку
				var c: Vector2 = (wet[0] + wet[-1]) * 0.5
				var ya := maxf(_h(wet[0].x - dir.x * 9.0, wet[0].y - dir.y * 9.0), _h(wet[-1].x + dir.x * 9.0, wet[-1].y + dir.y * 9.0))
				_add("bridge", c.x, c.y, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), Vector3(c.x * T, ya + 0.15, c.y * T)))
				wet.clear()
			if WorldGen.in_map(p.x, p.y, 1.0):
				put("rail_seg", p.x, p.y, yaw, "pt", false)
		WorldGen.add_clear(p.x, p.y, 4.0, 4.0, deg_to_rad(yaw))          # полоса отвода без деревьев
		s += step
	# переезды: пересечения с дорогами
	for other in WorldGen._roads:
		if other.get("rail", false) or other.get("trail", false):
			continue
		var op: PackedVector2Array = other.pts
		for i in op.size() - 1:
			for j in pts.size() - 1:
				var hit = Geometry2D.segment_intersects_segment(op[i], op[i + 1], pts[j], pts[j + 1])
				if hit == null:
					continue
				var hp: Vector2 = hit
				var odir := (op[i + 1] - op[i]).normalized()
				for sd: float in [-1.0, 1.0]:
					var cp := hp + odir * sd * 5.5
					put("rail_crossing", cp.x, cp.y, rad_to_deg(atan2(-odir.y, odir.x)) + (0.0 if sd > 0 else 180.0), "pt", false)
				_rej["переездов"] = _rej.get("переездов", 0) + 1
	# брошенный состав: 6 вагонов на путях
	var s0 := L * 0.62
	for k in 6:
		var at2 := _at(pts, s0 + k * 15.0 * M)
		var p2: Vector2 = at2[0]
		var d2: Vector2 = at2[1]
		var wm: String = ["wagon_box_red", "wagon_tank", "wagon_box_green", "wagon_tank", "wagon_box_red", "wagon_box_green"][k]
		var xf := Transform3D(Basis(Vector3.UP, atan2(-d2.y, d2.x)), Vector3(p2.x * T, _h(p2.x, p2.y) + 0.6, p2.y * T))
		_add(wm, p2.x, p2.y, xf)
		var wfp := _footprint(wm, p2.x, p2.y, atan2(-d2.y, d2.x))
		if not wfp.is_empty():
			_foot.append(wfp)                                         # вагоны — тоже занятое место
	# платформа ближе к лагерю
	var best := 0.0
	var bd := 1e9
	var sc := 0.0
	while sc < L:
		var pc: Vector2 = _at(pts, sc)[0]
		if pc.length() < bd:
			bd = pc.length()
			best = sc
		sc += 4.0
	var ap := _at(pts, best + 14.0)
	var pp: Vector2 = ap[0] + Vector2(-ap[1].y, ap[1].x) * 3.6
	put("rail_platform", pp.x, pp.y, rad_to_deg(atan2(-ap[1].y, ap[1].x)), "pt", false)

func _free_rect(c: Vector2, th: float, w: float, d: float) -> bool:
	return _plot_ok(c, th, w, d, "")

func _gas_station() -> void:
	var cands := []
	for fr in [0.5, 0.45, 0.55, 0.4, 0.6, 0.35, 0.65, 0.3, 0.7]:
		for r in WorldGen.ROADS:
			cands.append([r[0], r[1], fr])
	for cand in cands:
		var pts := _road_of(cand[0], cand[1])
		if pts.is_empty():
			continue
		var at := _at(pts, _road_len(pts) * float(cand[2]))
		var p: Vector2 = at[0]
		var dir: Vector2 = at[1]
		for sd: float in [1.0, -1.0]:
			var nrm := Vector2(-dir.y, dir.x) * sd
			var c := p + nrm * (5.5 + 14.0)
			var fd := -nrm
			var th := atan2(fd.x, fd.y)
			var okg := _free_rect(c, th, 30.0, 28.0)
			if okg:
				_plots.append([c, th, 15.0, 14.0])
				WorldGen.add_clear(c.x, c.y, 17.0, 16.0, th)
				var gs := _loc(c, th, -4.0, 2.0)
				put("gas_station", gs.x, gs.y, rad_to_deg(th) + 180.0, "min", false)
				var cf := _loc(c, th, 10.0, 0.0)
				put("cafe", cf.x, cf.y, rad_to_deg(th), "min", false)
				var cp := _loc(c, th, 2.0, -6.0)
				put("car_sedan_white", cp.x, cp.y, rad_to_deg(th) - 90.0, "", false)
				_rej["АЗС"] = "%d:%d" % [roundi(c.x), roundi(c.y)]
				return

# придорожные места: по одному, редко, вдоль асфальтовых дорог (не у локаций и посёлков)
const ROADSIDE := [["supermarket", 30.0, 25.0, [["car_sedan_white", -8.0, -9.0, 80.0], ["car_solaris_silver", 4.0, -10.0, 95.0]]],
	["tire_shop", 16.0, 14.0, [["tires", 6.0, -4.0, 0.0], ["tires", -6.0, -5.0, 30.0], ["car_granta_graphite", 0.0, -7.0, 90.0]]],
	["auto_service", 22.0, 18.0, [["car_crossover_silver", -4.0, -9.0, 80.0], ["barrels_a", 8.0, 2.0, 0.0]]],
	["motel", 22.0, 17.0, [["car_vesta_black", 6.0, -9.0, 85.0], ["car_hatch_white", -6.0, -9.0, 95.0]]],
	["dps_post", 12.0, 10.0, [["car_police", 4.0, -4.5, 90.0], ["jersey", -4.0, -6.0, 0.0]]]]
func _roadside() -> void:
	var done: Array = []
	var fr_list := [0.5, 0.35, 0.65, 0.25, 0.75, 0.42, 0.58, 0.2, 0.8, 0.3, 0.7, 0.46, 0.54, 0.38, 0.62]
	var ri := 0
	for item in ROADSIDE:
		var ok := false
		for k in WorldGen.ROADS.size() * fr_list.size():
			var r: Array = WorldGen.ROADS[(ri + k) % WorldGen.ROADS.size()]
			var fr: float = fr_list[(k / WorldGen.ROADS.size()) % fr_list.size()]
			var pts := _road_of(r[0], r[1])
			if pts.is_empty():
				continue
			var at := _at(pts, _road_len(pts) * fr)
			var p: Vector2 = at[0]
			var dir: Vector2 = at[1]
			var far := true
			for q in done:
				if p.distance_to(q) < 55.0:
					far = false
			if not far or _near_center(p, 30.0) or _near_bunker(p):
				continue
			for sd: float in [1.0, -1.0]:
				var w: float = item[1]
				var d: float = item[2]
				var nrm := Vector2(-dir.y, dir.x) * sd
				var c := p + nrm * (5.5 + d * 0.5)
				var fd := -nrm
				var th := atan2(fd.x, fd.y)
				if not _free_rect(c, th, w, d):
					continue
				var bp := _loc(c, th, 0.0, -d * 0.12)
				if not put(item[0], bp.x, bp.y, rad_to_deg(th), "min", false):
					continue                                              # здание не встало — места нет (без пустой парковки)
				_plots.append([c, th, w * 0.5, d * 0.5])
				WorldGen.add_clear(c.x, c.y, w * 0.5 + 2.0, d * 0.5 + 2.0, th)
				for ex in item[3]:
					var ep := _loc(c, th, ex[1], -float(ex[2]))                   # минус — перед фасадом, у дороги
					put(ex[0], ep.x, ep.y, rad_to_deg(th) + ex[3], "", false)
				done.append(p)
				_rej[item[0]] = "%d:%d" % [roundi(c.x), roundi(c.y)]
				ok = true
				break
			if ok:
				break
		ri += 3
		if not ok:                                                     # у дорог тесно — на окраину деревни
			_rej[item[0]] = "нет места"
			for sk in ["village", "h_poselok", "farm"]:
				var v: Dictionary = WorldGen.site(sk)
				for rr: float in [30.0, 40.0, 50.0]:
					if _free_put(item[0], Vector2(v.x, v.y), rr, 120.0):
						_rej[item[0]] = sk
						break
				if _rej[item[0]] != "нет места":
					break

# карьер: самосвалы и трактор на дне, вагончик и бочки у въезда, кучи грунта
func _quarry() -> void:
	var q := WorldGen.QUARRY
	var c := Vector2(q.x, q.y)
	var items := [["car_truck_blue", 3.0, 1.0, 30.0], ["car_truck_blue", -5.0, 5.0, 200.0], ["tractor_red", 6.0, 7.0, 120.0], ["sawdust", -7.0, -6.0, 0.0], ["sawdust", -10.0, -2.0, 30.0],
		["sawdust", 1.0, -9.0, 40.0], ["generator_shed", 0.0, 15.0, 0.0], ["barrels_a", 3.0, 16.0, 0.0], ["container_b", -4.0, 16.5, 90.0], ["tires", -7.0, 14.0, 0.0]]
	for it in items:
		put(it[0], c.x + it[1], c.y + it[2], it[3])
	_plots.append([c, 0.0, q.z, q.z])                                 # чужие дома в карьер не встанут

# скалы с пещерой: в лесу на северных холмах, вдали от посёлков и дорог
func _rocks() -> void:
	var got := 0
	var where := ""
	var x := -180.0
	while x <= 180.0 and got < 2:
		var y := -205.0
		while y <= -120.0 and got < 2:
			var p := Vector2(x, y)
			if WorldGen.in_map(p.x, p.y, 12.0) and WorldGen.forest_mask(p.x, p.y) > 0.4 and not _near_center(p, 40.0) and WorldGen.path_dist(p.x, p.y) > 18.0:
				var ok := true
				for q in where.split(" ", false):
					var xy := q.split(":")
					if p.distance_to(Vector2(float(xy[0]), float(xy[1]))) < 120.0:
						ok = false
				if ok and put("rock_cave", p.x, p.y, _rng.randf_range(0, 360), "min"):
					got += 1
					where += "%d:%d " % [roundi(p.x), roundi(p.y)]
			y += 17.0
		x += 31.0
	_rej["скалы"] = where

# охотничьи вышки: на опушках, лицом к полю, вдали от посёлков и дорог
func _hunting_towers() -> void:
	var got := 0
	var placed: Array = []
	var x := -190.0
	while x <= 190.0 and got < 7:
		var y := -190.0
		while y <= 190.0 and got < 7:
			var p := Vector2(x + 7.0, y + 3.0)
			var fm := WorldGen.forest_mask(p.x, p.y)
			if fm > 0.25 and WorldGen.in_map(p.x, p.y, 10.0) and not _near_center(p, 30.0) and WorldGen.path_dist(p.x, p.y) > 10.0:
				var far := true
				for o in placed:
					if p.distance_to(o) < 60.0:
						far = false
				# лицом туда, где леса меньше
				var best := 0.0
				var bm := 9.0
				for k in 8:
					var a := k * TAU / 8.0
					var m := WorldGen.forest_mask(p.x + cos(a) * 16.0, p.y + sin(a) * 16.0)
					if m < bm:
						bm = m
						best = a
				if far and bm < 0.12 and put("watch_tower", p.x, p.y, rad_to_deg(atan2(cos(best), sin(best)))):
					placed.append(p)
					got += 1
			y += 11.0
		x += 11.0
	_rej["охотничьих вышек"] = got

func _children_camp() -> void:
	var h: Dictionary = WorldGen.HAMLETS["h_lager"]
	var c := Vector2(h.x, h.y)
	var dir := _road_dir(c)
	var th := atan2(dir.x, dir.y)
	var yaw := rad_to_deg(th)
	WorldGen.add_clear(c.x, c.y, 28.0, 32.0, th)
	for sd: float in [-1.0, 1.0]:                                      # два корпуса фасадами к линейке
		var p := _loc(c, th, sd * 13.0, 0.0)
		put("camp_corpus", p.x, p.y, yaw + 90.0 * sd, "min", false)
	_plots.append([c, th, 28.0, 24.0])                                # территория лагеря — чужие дома не встанут
	var din := _loc(c, th, 0.0, -24.0)
	put("house_brick", din.x, din.y, yaw, "min", false)               # столовая
	for k in [-1.0, 1.0]:
		var bp := _loc(c, th, k * 4.0, 6.0)
		put("bench_log", bp.x, bp.y, yaw)
	var pole := _loc(c, th, 0.0, 9.0)
	put("pole_wood", pole.x, pole.y, yaw)                              # флагшток
	var sg := _loc(c, th, 4.0, 24.0)
	put("sign_info", sg.x, sg.y, yaw, "pt", false)
	var rad := 27.0
	var n := roundi(TAU * rad / (FENCE_LEN["fence_chain"] * M))
	for i in n:
		var ang := TAU * (i + 0.5) / n
		var fp := c + Vector2(cos(ang), sin(ang)) * rad
		if path_blocked(fp) or i % 9 == 0:
			continue
		put("fence_chain_" + ("b" if _rng.randf() < 0.3 else "a"), fp.x, fp.y, -rad_to_deg(ang) - 90.0, "", false)
	var bus := _loc(c, th, -6.0, 18.0)
	put("car_bus_yellow", bus.x, bus.y, yaw - 90.0, "", false)

func _dump_and_wreck() -> void:
	# свалка: в поле подальше от посёлков, у дороги
	var placed := false
	var tries := 0
	while not placed and tries < 3000:
		tries += 1
		var p := Vector2(_rng.randf_range(-190, 190), _rng.randf_range(-190, 190))
		var pd := WorldGen.path_dist(p.x, p.y)
		if pd < 6.0 or pd > 60.0 or WorldGen.forest_mask(p.x, p.y) > 0.45 or _near_site(p, 14.0):
			continue
		if not _free_rect(p, 0.0, 28.0, 24.0):
			continue
		WorldGen.add_clear(p.x, p.y, 15.0, 13.0, 0.0)
		_plots.append([p, 0.0, 14.0, 12.0])
		for k in 7:
			var q := p + Vector2(_rng.randf_range(-10, 10), _rng.randf_range(-8, 8))
			put("dump_pile_a" if k % 2 == 0 else "dump_pile_b", q.x, q.y, _rng.randf() * 360.0, "pt", false)
		for k in 4:
			var q2 := p + Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-10, 10))
			put(["car_sedan_burnt", "car_classic_blue", "car_sedan_green", "car_niva_beige"][k], q2.x, q2.y, _rng.randf() * 360.0, "", false)
		put("tires", p.x + 9.0, p.y - 6.0, 30.0, "", false)
		_rej["свалка"] = "%d:%d" % [roundi(p.x), roundi(p.y)]
		placed = true
	# вертолёт: в глухом лесу, вдали от дорог
	tries = 0
	while tries < 600:
		tries += 1
		var p3 := Vector2(_rng.randf_range(-190, 190), _rng.randf_range(-190, 190))
		if WorldGen.forest_mask(p3.x, p3.y) < 0.6 or WorldGen.path_dist(p3.x, p3.y) < 26.0 or _near_site(p3, 36.0) or WorldGen.terrain(p3.x, p3.y)[1] > 0.0:
			continue
		WorldGen.add_clear(p3.x, p3.y, 15.0, 10.0, 0.4)
		put("heli_wreck", p3.x, p3.y, 23.0, "pt", false)
		_rej["вертолёт"] = "%d:%d" % [roundi(p3.x), roundi(p3.y)]
		break

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


# ---------------- сюжет: хутор героя у Большого озера и лаборатория ----------------
var story := {}                       # точки заставки (тайлы, углы; высоты — метры над землёй)
func _story_pts() -> void:
	var h: Dictionary = WorldGen.HAMLETS["h_hero"]
	var c := Vector2(h.x, h.y)
	var lake := Vector2(WorldGen.LAKES[0].x, WorldGen.LAKES[0].y)
	var f := (c - lake).normalized()                                  # фасад — от озера, веранда — к озеру
	var th := atan2(f.x, f.y)
	story = {"c": c, "th": th, "f": f, "u": Vector2(cos(th), -sin(th))}
	# точки в метрах модели дома (Blender: +X вправо, +Y назад к озеру) → тайлы
	var P := func(bx: float, by: float) -> Vector2:
		return c + Vector2(cos(th), -sin(th)) * bx * M - f * by * M
	story.pt = P
	story.bed = P.call(3.3, 3.25)                                     # голова на подушке, ноги к −X
	story.bed_feet = P.call(1.7, 3.25)
	story.door = P.call(-3.4, -5.6)                                   # у крыльца снаружи
	story.chair = P.call(1.5, 5.6)
	story.table = P.call(2.6, 5.6)
	story.lounger = P.call(-2.6, 8.9)
	story.shed = P.call(9.0, -1.0)
	story.shed_door = P.call(9.0 - 0.9, -1.0 - 2.6)
	story.hatch = P.call(9.0 + 0.7, -1.0 + 0.35)
	story.lid = P.call(9.0 + 0.7, -1.0 - 0.1)                         # петля крышки
	story.car = P.call(-6.0, -9.0)
	story.boat = P.call(3.0, 15.0)
	var lb: Dictionary = WorldGen.FEATURES["lab"]
	story.lab = Vector2(lb.x, lb.y)
	story.house_y = _min_y("hero_house", c.x, c.y)                   # высота основания дома (как ставит put «min»), пол — +0,6 м
	story.shed_y = _min_y("hero_shed", story.shed.x, story.shed.y)

func _min_y(model: String, tx: float, ty: float) -> float:
	var rad := _rad(model) * 0.8
	var y := _h(tx, ty)
	for k in 4:
		var a := k * PI / 2.0 + 0.7
		y = minf(y, _h(tx + cos(a) * rad, ty + sin(a) * rad))
	return y - 0.12

func _hero_home() -> void:
	var c: Vector2 = story.c
	var th: float = story.th
	var yaw := rad_to_deg(th)
	WorldGen.add_clear(c.x, c.y, 26.0, 26.0, th)
	put("hero_house", c.x, c.y, yaw, "min", false)
	_plots.append([c, th, 9.0, 12.0])
	put("lounger", story.lounger.x, story.lounger.y, yaw, "pt", false)
	put("hero_shed", story.shed.x, story.shed.y, yaw, "min", false)
	put("car_duster_brown", story.car.x, story.car.y, yaw + 80.0, "", false)
	put("boat_row_wood", story.boat.x, story.boat.y, yaw + 70.0, "pt", false)
	var wp: Vector2 = story.pt.call(-6.0, -1.0)
	put("woodpile", wp.x, wp.y, yaw + 90.0, "", false)
	_rej["дом героя"] = "%d:%d" % [roundi(c.x), roundi(c.y)]

func _lab() -> void:
	var f: Dictionary = WorldGen.FEATURES["lab"]
	var c := Vector2(f.x, f.y)
	var fd := _road_dir(c)                                            # фасад — к въездной дороге
	var th := atan2(fd.x, fd.y)
	var yaw := rad_to_deg(th)
	WorldGen.add_clear(c.x, c.y, 50.0, 40.0, th)
	var L := func(lx: float, ly: float) -> Vector2:
		return _loc(c, th, lx, ly)
	var items := [["lab_main", 0.0, 0.0, 0.0], ["lab_wing", 0.0, -22.0, 0.0], ["lab_stack", 30.0, -16.0, 0.0], ["lab_tank", 32.0, 6.0, 0.0], ["lab_tank", 32.0, -5.0, 0.0],
		["checkpoint", 0.0, 24.0, 0.0], ["lab_sign", 9.0, 27.0, 0.0], ["lab_sign", -9.0, 27.0, 0.0], ["mil_tower", 40.0, 21.0, 0.0], ["mil_tower", -40.0, 21.0, 0.0],
		["mil_tower", 40.0, -31.0, 0.0], ["mil_tower", -40.0, -31.0, 0.0], ["car_truck_green", 14.0, 15.0, 90.0], ["car_police", -12.0, 17.0, 70.0],
		["car_ambulance", -20.0, 12.0, 100.0], ["tent_med", -30.0, 9.0, 0.0], ["tent_med", -30.0, -2.0, 0.0], ["barrels_a", 22.0, -12.0, 0.0], ["crates", -24.0, -14.0, 0.0],
		["lamp_post", 12.0, 21.0, 180.0], ["lamp_post", -12.0, 21.0, 0.0], ["lamp_post", 22.0, 4.0, 180.0], ["lamp_post", -22.0, 4.0, 0.0]]   # у НИИ есть ток — фонари горят
	for it in items:
		var q: Vector2 = L.call(it[1], it[2])
		put(it[0], q.x, q.y, yaw + float(it[3]), "", false)
	# бетонный забор по периметру, ворота у дороги
	var a: Vector2 = L.call(-42.0, 24.0); var b: Vector2 = L.call(42.0, 24.0)
	var a2: Vector2 = L.call(-42.0, -33.0); var b2: Vector2 = L.call(42.0, -33.0)
	_fence_line(a, b, "fence_mil", 0.1, 42.0 - 6.0, 42.0 + 6.0)
	_fence_line(a2, b2, "fence_mil", 0.1)
	_fence_line(a2, a, "fence_mil", 0.1)
	_fence_line(b2, b, "fence_mil", 0.1)
	_plots.append([c, th, 44.0, 34.0])                                 # территория института — чужие дворы сюда не встают
	_rej["лаборатория"] = "%d:%d" % [roundi(c.x), roundi(c.y)]

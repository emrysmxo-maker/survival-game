class_name WorldGen
extends RefCounted
# Мир — перенос из браузерной версии (src/ground.js, src/world.js, src/cover.js).
# Все формулы — в «тайлах» старой игры (x, y на земле), как было; в Godot
# точка (x, y) тайлов -> Vector3(x * T, h * HK, y * T).

const CHUNK := 12                 # тайлов в чанке
const T := 0.837                  # метров Godot в одном тайле (так боец/деревья в тех же пропорциях)
const HK := 0.75                  # высота рельефа старой игры (м) -> метры Godot
const MAP_RADIUS := 220.0
const RAIL_Y0 := -10.0                    # железная дорога: y на западном и восточном краю карты (тайлы)
const RAIL_Y1 := 100.0
const PX := 0.016                 # метров Godot в одном «экранном px» старой игры (размеры спрайтов)

# ---------- карта: 7 локаций (пока пустые поляны — места под будущие миссии) ----------
# Координаты — тайлы. Карта 440×440 тайлов (~370 м): бегом через всю карту ~2 мин.
const FEATURES := {
	"camp": {"x": 0.0, "y": 0.0, "r": 12.0, "name": "Лагерь выживших"},
	"village": {"x": -120.0, "y": -105.0, "r": 22.0, "name": "Заброшенная деревня"},
	"sawmill": {"x": 105.0, "y": -125.0, "r": 16.0, "name": "Лесопилка"},
	"lakebase": {"x": 118.0, "y": 52.0, "r": 13.0, "name": "Рыбацкая база"},
	"farm": {"x": 25.0, "y": 150.0, "r": 22.0, "name": "Колхоз «Рассвет»"},
	"bunker": {"x": -150.0, "y": 125.0, "r": 22.0, "name": "Военный бункер"},
	"tower": {"x": -35.0, "y": -178.0, "r": 18.0, "name": "Радиовышка"},
}
const LANDMARKS := ["camp", "village", "sawmill", "lakebase", "farm", "bunker", "tower"]
# хутора, дачи, кордоны: малые поляны с постройками (расстановка — scripts/props.gd); ровная земля, леса нет, к каждому ведёт просёлок
const HAMLETS := {
	"h_vyselki": {"x": -85.0, "y": -60.0, "r": 12.0, "name": "Выселки"},
	"h_zarechye": {"x": -45.0, "y": 118.0, "r": 12.0, "name": "Заречье"},
	"h_dachi": {"x": 70.0, "y": 25.0, "r": 14.0, "name": "Дачный посёлок"},
	"h_bereza": {"x": 140.0, "y": -25.0, "r": 11.0, "name": "Берёзовка"},
	"h_ranger": {"x": 15.0, "y": -105.0, "r": 9.0, "name": "Лесничество"},
	"h_hunter": {"x": -20.0, "y": -140.0, "r": 7.0, "name": "Охотничья заимка"},
	"h_cem": {"x": -140.0, "y": -62.0, "r": 8.0, "name": "Старое кладбище"},
	"h_poselok": {"x": -54.0, "y": -105.0, "r": 12.0, "name": "Посёлок Луговой"},
	"h_lager": {"x": -100.0, "y": -22.0, "r": 16.0, "name": "Детский лагерь «Берёзка»"},
	"h_quarry": {"x": -105.0, "y": 50.0, "r": 6.0, "name": "Песчаный карьер"},
}
const TRACKS := [["h_vyselki", "village"], ["h_zarechye", "farm"], ["h_dachi", "camp"],
	["h_bereza", "lakebase"], ["h_ranger", "camp"], ["h_hunter", "tower"], ["h_cem", "village"],
	["h_poselok", "village"], ["h_poselok", "h_ranger"], ["h_lager", "h_vyselki"], ["h_quarry", "h_lager"]]
# дороги между локациями (ведут от лагеря, плюс объездные)
const ROADS := [["camp", "village"], ["camp", "sawmill"], ["camp", "lakebase"], ["camp", "farm"], ["camp", "bunker"], ["village", "tower"], ["sawmill", "tower"], ["farm", "lakebase"], ["farm", "bunker"]]
# карьер: центр и радиус (тайлы) — террасная выемка ~6 м, каменистое дно
const QUARRY := Vector3(-105.0, 50.0, 17.0)
# овраги в лесу: от, до, ручей по дну (1 — есть)
const RAVINES := [[Vector2(90.0, 120.0), Vector2(135.0, 165.0), 1.0], [Vector2(105.0, -75.0), Vector2(169.0, -75.0), 0.0]]
static var _rv := PackedFloat32Array()      # отрезки оврагов: x0, y0, x1, y1, ручей
static var _rv_bb := Rect2()

# озёра: центр, радиус (берег неровный), глубина
const LAKES := [
	{"x": 165.0, "y": 45.0, "r": 38.0, "d": 2.6},     # Большое озеро (восток)
	{"x": -168.0, "y": -40.0, "r": 17.0, "d": 1.8},   # Деревенский пруд
	{"x": 55.0, "y": -80.0, "r": 12.0, "d": 1.6},     # Лесное озеро
	{"x": -120.0, "y": 170.0, "r": 11.0, "d": 1.4},   # болотные окна
	{"x": -185.0, "y": 95.0, "r": 9.0, "d": 1.3},
]
# зоны растительности: центр (тайлы) и состав; зона — ближайший центр (с «изгибом» границ)
const ZONES := [
	{"name": "Северный бор", "x": 40.0, "y": -150.0, "canopy": [["FIR", 5], ["PINE", 4], ["BIRCH", 1]], "bias": 0.80, "dens": 5, "dead": 0.05, "fern": 0.9, "grass": 0.3, "shrub": 0.4},
	{"name": "Скалистые холмы", "x": -60.0, "y": -195.0, "canopy": [["PINE", 3], ["FIR", 2]], "bias": 0.36, "dens": 3, "dead": 0.15, "fern": 0.3, "grass": 0.5, "shrub": 0.3},
	{"name": "Поля у деревни", "x": -135.0, "y": -95.0, "canopy": [["BIRCH", 3], ["BROAD", 1]], "bias": 0.12, "dens": 1, "dead": 0.02, "fern": 0.1, "grass": 1.6, "shrub": 0.5},
	{"name": "Смешанный лес", "x": -10.0, "y": -30.0, "canopy": [["FIR", 2], ["PINE", 2], ["BIRCH", 3], ["ASPEN", 1], ["OAK", 1], ["BROAD", 1]], "bias": 0.58, "dens": 3, "dead": 0.05, "fern": 0.8, "grass": 0.6, "shrub": 0.6},
	{"name": "Смешанный лес", "x": 60.0, "y": -40.0, "canopy": [["FIR", 2], ["PINE", 1], ["BIRCH", 3], ["ASPEN", 2], ["BROAD", 1]], "bias": 0.58, "dens": 3, "dead": 0.05, "fern": 0.8, "grass": 0.6, "shrub": 0.6},
	{"name": "Озёрный край", "x": 150.0, "y": 40.0, "canopy": [["BIRCH", 3], ["ASPEN", 2], ["BROAD", 2]], "bias": 0.38, "dens": 2, "dead": 0.04, "fern": 0.4, "grass": 1.1, "shrub": 0.8},
	{"name": "Южные поля", "x": 40.0, "y": 165.0, "canopy": [["OAK", 2], ["BROAD", 2], ["BIRCH", 1]], "bias": 0.12, "dens": 1, "dead": 0.03, "fern": 0.1, "grass": 1.6, "shrub": 0.6},
	{"name": "Дубрава", "x": 120.0, "y": 150.0, "canopy": [["OAK", 4], ["BROAD", 2], ["ASPEN", 1]], "bias": 0.72, "dens": 3, "dead": 0.04, "fern": 0.5, "grass": 0.8, "shrub": 0.8},
	{"name": "Гиблые топи", "x": -150.0, "y": 130.0, "canopy": [["BIRCH", 3], ["PINE", 1], ["DEAD", 3]], "bias": 0.42, "dens": 2, "dead": 0.3, "fern": 0.3, "grass": 0.9, "shrub": 0.4},
	{"name": "Западный ельник", "x": -160.0, "y": 20.0, "canopy": [["FIR", 4], ["PINE", 2], ["BIRCH", 1]], "bias": 0.78, "dens": 4, "dead": 0.06, "fern": 1.0, "grass": 0.3, "shrub": 0.4},
]

# ---------- лес: свои деревья из Blender (tools/trees/treegen.py), настоящие размеры ----------
const FIR := ["spruce_a", "spruce_b", "spruce_c"]
const PINE := ["pine_a", "pine_b", "pine_c"]
const BIRCH := ["birch_a", "birch_b", "birch_c"]
const BROAD := ["alder_a", "alder_b", "aspen_b", "birch_b"]
const OAK := ["oak_a", "oak_b", "oak_c"]
const ASPEN := ["aspen_a", "aspen_b"]
const WET := ["alder_a", "alder_b", "willow_a", "willow_b", "cherry_a", "cherry_b"]        # сырые низины, берега (черёмуха — у воды и на опушках)
const APPLE := ["apple_a", "apple_b", "apple_c"]                   # одичавшие сады (ставятся у дворов — этап расстановки)
const DEAD := ["pine_dead_a", "spruce_dead_a"]
const SAP_SMALL := ["spruce_sap_a", "pine_sap_a", "birch_sap_a"]
const SAP_MED := ["spruce_sap_b", "pine_sap_b", "birch_sap_b", "aspen_sap_a", "oak_sap_a"]
const SHRUB := ["shrub2_a", "shrub2_b", "shrub2_c", "shrub2_d", "shrub3_a", "shrub3_b", "shrub3_c", "shrub3_d", "shrub4"]
const FERN := ["fern_a", "fern_b", "fern_c", "fern_d"]
const NETTLE := ["nettle_medium_a", "nettle_medium_b", "nettle_small_a", "nettle_small_b", "nettle_tall_a", "nettle_tall_b"]
const GRASS := ["grass1_small_a", "grass1_mid_b", "grass1_tall_a", "grass1_tall_b", "grass1_large_b", "grass1_small_b", "grass2_a", "grass2_b", "grass2_c", "grass2_d", "grass2_e"]
const FLOWERS := ["celandine_a", "celandine_b", "celandine_c", "celandine_d", "celandine_e", "dandelion_a", "dandelion_b", "dandelion_c", "dandelion_d", "dandelion_e"]
const STUMP := ["stump1", "stump2"]
const MUSH := ["mush_a", "mush_b", "mush_b", "mush_c", "mush_c", "mush_d"]   # грибы: под деревьями, у пней
const LOG := ["log1", "log1b", "log2", "log2b"]
const BRANCH := ["branches_a", "branches_b", "branches_c"]
const ROCK := ["boulder1", "mrock1", "mrock2", "mrock3", "mrock4", "mrock5", "mrock6", "mrock7", "mrock8", "mrock9", "mrock10", "mrock11", "mrock12", "mrock13", "rock7", "stone1"]
# что лежит на земле (рисуется «на земле», без раздвигания) и что твёрдое (столкновения), радиус — тайлы
const FLAT_CATS := ["moss", "branch", "roots", "log"]
const SOLID_R := {"tree": 0.55, "dead": 0.5, "stump": 0.45, "log": 0.75, "rock": 0.6, "sapm": 0.3}
# раздвигание растений бойцом и ветер (как в браузерной версии)
const PUSH := {"grass": 1.0, "fern": 0.9, "nettle": 0.9, "flower": 0.8, "shrub": 0.7, "sap": 0.35}
const SWAY := {"tree": 0.45, "dead": 0.15, "sapm": 0.5, "sap": 0.6, "shrub": 0.7, "fern": 0.6, "nettle": 0.8, "grass": 1.0, "flower": 0.9}

static func ss(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func prand(s: int) -> float:
	var x := sin(float(s)) * 10000.0
	return x - floor(x)

static func to_world(x: float, y: float, h: float) -> Vector3:
	return Vector3(x * T, h * HK, y * T)

# ---------- река, дороги, озёра ----------
# Река Быстрянка: течёт с запада и впадает в Большое озеро
static func river_center_y(wx: float) -> float:
	return 75.0 + 16.0 * sin(wx * 0.018 + 0.4) + 6.0 * sin(wx * 0.045)

static func river_dist(wx: float, wy: float) -> float:
	if wx > 150.0:
		return 999.0
	var dy := wy - river_center_y(wx)
	var k := 16.0 * 0.018 * cos(wx * 0.018 + 0.4) + 6.0 * 0.045 * cos(wx * 0.045)
	return absf(dy) / sqrt(1.0 + k * k)

const FORD := Vector2(14.0, 0.0)   # брод — там, где дорога лагерь→колхоз пересекает реку (y считается)
static func ford_factor(wx: float, wy: float) -> float:
	return ss(16.0, 5.0, Vector2(wx - FORD.x, wy - river_center_y(FORD.x)).length())

# дороги — ломаные с плавным изгибом (считаются один раз)
static var _roads: Array = []
static var _lk := PackedFloat32Array()   # озёра: x, y, r, глубина, уровень (числами — безопасно из потоков)
static var _ft := PackedFloat32Array()   # локации: x, y, r, высота поляны
static var _zn := PackedFloat32Array()   # центры зон: x, y
static var _zb := PackedFloat32Array()   # лесистость зон (0..1)
# ---------- участки и постройки (заполняет props.gd до генерации чанков): там не растут деревья и кусты ----------
static var _clr := PackedFloat32Array()   # прямоугольники: cx, cy, полуширина, полуглубина, угол (рад, как у дворов в props.gd)
static var _xt := PackedFloat32Array()    # отдельные деревья (сады во дворах): x, y, индекс вида
static var _xt_keys := PackedStringArray()
static func add_clear(cx: float, cy: float, hw: float, hd: float, ang: float) -> void:
	_clr.append_array([cx, cy, hw, hd, ang])
static func add_tree(x: float, y: float, key: String) -> void:
	var i := _xt_keys.find(key)
	if i < 0:
		_xt_keys.append(key)
		i = _xt_keys.size() - 1
	_xt.append_array([x, y, float(i)])
# точка внутри участка/постройки (pad — запас, тайлы: крона дерева не должна нависать над домом)
static func cleared(wx: float, wy: float, pad := 0.0) -> bool:
	for i in _clr.size() / 5:
		var dx: float = wx - _clr[i * 5]
		var dy: float = wy - _clr[i * 5 + 1]
		var hw: float = _clr[i * 5 + 2] + pad
		var hd: float = _clr[i * 5 + 3] + pad
		if absf(dx) > hw + hd or absf(dy) > hw + hd:
			continue
		var a: float = _clr[i * 5 + 4]
		var lx := dx * cos(a) - dy * sin(a)
		var ly := dx * sin(a) + dy * cos(a)
		if absf(lx) < hw and absf(ly) < hd:
			return true
	return false

# ---------- морок: места, где «что-то не так» — мёртвый лес, серая земля (центр x, y и радиус, тайлы) ----------
const MOROK := [[-150.0, 132.0, 40.0], [92.0, -62.0, 24.0], [-62.0, -190.0, 28.0]]
static func morok(wx: float, wy: float) -> float:
	var k := 0.0
	for m in MOROK:
		var d := Vector2(wx - m[0], wy - m[1]).length()
		if d < m[2]:
			k = maxf(k, ss(m[2], m[2] * 0.45, d + (vnoise(wx, wy, 7.0, 77) - 0.5) * 9.0))
	return k

static func site(key: String) -> Dictionary:
	return FEATURES[key] if FEATURES.has(key) else HAMLETS[key]
static func init() -> void:
	if not _roads.is_empty():
		return
	var lk := PackedFloat32Array()
	for L in LAKES:
		lk.append_array([L.x, L.y, L.r, L.d * 2.0, base_height(L.x, L.y) - 0.35])   # дно вдвое глубже: видна толща воды, вода темнеет с глубиной
	var ft := PackedFloat32Array()
	for key in LANDMARKS:
		var f: Dictionary = FEATURES[key]
		ft.append_array([f.x, f.y, f.r, base_height(f.x, f.y)])
	for key in HAMLETS:
		var f2: Dictionary = HAMLETS[key]
		ft.append_array([f2.x, f2.y, f2.r, base_height(f2.x, f2.y)])
	var zb := PackedFloat32Array()
	for z in ZONES:
		zb.append(z.bias)
	_zb = zb
	var zn := PackedFloat32Array()
	for z in ZONES:
		zn.append_array([z.x, z.y])
	var rvs := PackedFloat32Array()
	var rvbb := Rect2(RAVINES[0][0], Vector2.ZERO)
	for rr in RAVINES:
		var a: Vector2 = rr[0]
		var b: Vector2 = rr[1]
		var nn := (b - a).normalized().orthogonal()
		var prev := a
		for i in range(1, 9):
			var t := i / 8.0
			var q := a.lerp(b, t) + nn * sin(t * PI * 2.0) * 5.0 * (1.0 if i < 8 else 0.0)
			rvs.append_array([prev.x, prev.y, q.x, q.y, rr[2]])
			rvbb = rvbb.expand(q)
			prev = q
	_rv = rvs
	_rv_bb = rvbb.grow(12.0)
	_lk = lk
	_ft = ft
	_zn = zn
	var out := []
	var seed := 1
	for r in ROADS + TRACKS:
		var a: Dictionary = site(r[0])
		var b: Dictionary = site(r[1])
		var pa := Vector2(a.x, a.y)
		var pb := Vector2(b.x, b.y)
		var n := (pb - pa).normalized().orthogonal()
		var pts := PackedVector2Array()
		for i in 21:
			var t := i / 20.0
			var wob := sin(t * PI) * (9.0 * sin(seed * 1.7) + 5.0 * sin(t * PI * 3.0 + seed))
			var q := pa.lerp(pb, t) + n * wob
			if i > 0 and i < 20:
				for L in LAKES:                                        # дорога огибает озеро (берег неровный — запас)
					var lc := Vector2(L.x, L.y)
					var rr: float = L.r * 1.45 + 5.0
					if q.distance_to(lc) < rr:
						q = lc + (q - lc).normalized() * rr
			pts.append(q)
		seed += 1
		var bb := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			bb = bb.expand(p)
		out.append({"pts": pts, "bb": bb.grow(4.0), "track": r in TRACKS})
	# железная дорога через всю карту (в стороне от озёр и посёлков)
	var rp := PackedVector2Array()
	var x := -218.0
	while x <= 218.0:
		rp.append(Vector2(x, RAIL_Y0 + (RAIL_Y1 - RAIL_Y0) * (x + 210.0) / 420.0 + sin(x * 0.012) * 8.0))
		x += 14.0
	var rbb := Rect2(rp[0], Vector2.ZERO)
	for q in rp:
		rbb = rbb.expand(q)
	out.append({"pts": rp, "bb": rbb.grow(4.0), "track": true, "rail": true})
	_roads = out

# расстояние до асфальтовых дорог (ROADS; просёлки и тропы — грунт)
static func asphalt_dist(wx: float, wy: float) -> float:
	var p := Vector2(wx, wy)
	var d := 999.0
	for r in _roads:
		if r.track or not r.bb.has_point(p):
			continue
		var pts: PackedVector2Array = r.pts
		for i in pts.size() - 1:
			d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])))
	return d

static func path_dist(wx: float, wy: float) -> float:
	var p := Vector2(wx, wy)
	var d := 999.0
	for r in _roads:
		if not r.bb.has_point(p):
			continue
		var pts: PackedVector2Array = r.pts
		for i in pts.size() - 1:
			d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])))
	return d

# озеро в точке: x — доля воды 0..1, y — глубина 0..1 (к центру), z — индекс (-1 нет),
# w — «берег» 0..1 (полоса ~6 тайлов вокруг: там земля поднимается над водой)
static func lake_at(wx: float, wy: float) -> Vector4:
	for i in _lk.size() / 5:
		var lx: float = _lk[i * 5]
		var ly: float = _lk[i * 5 + 1]
		var lr: float = _lk[i * 5 + 2]
		var dx: float = wx - lx
		var dy: float = wy - ly
		var d := sqrt(dx * dx + dy * dy)
		if d > lr * 1.3 + 7.0:
			continue
		var a := atan2(dy, dx)
		var re: float = lr * (1.0 + 0.16 * sin(3.0 * a + i) + 0.08 * sin(5.0 * a + 2.0 * i) + 0.05 * sin(9.0 * a + 3.0 * i) + 0.03 * sin(17.0 * a + i))
		re += 2.3 * sin(wx * 0.19 + wy * 0.13 + i) + 1.5 * sin(wx * 0.37 - wy * 0.29 + 2.0 * i) + 0.8 * sin(wx * 0.71 + wy * 0.83)   # заливчики и мысы (неровная кромка)
		var ring := ss(re + 6.0, re, d)
		if ring > 0.0:
			# x — вода (резкая кромка по ватерлинии), y — глубина: от 0 у берега плавно вниз на 60% радиуса
			var tdeep := clampf((re - d) / (re * 0.6), 0.0, 1.0)
			return Vector4(ss(re + 1.6, re - 1.6, d), tdeep * tdeep * (3.0 - 2.0 * tdeep), i, ring)   # пологий переход берег→дно (иначе кромка «ступеньками» по сетке)
	return Vector4(0, 0, -1, 0)

static func radial(x: float, y: float, f: Dictionary) -> float:
	var r: float = f.r
	return ss(r, r * 0.25, Vector2(x - f.x, y - f.y).length())

static func soil_noise(wx: float, wy: float) -> float:
	return (sin(wx * 0.03 + wy * 0.017) + sin(wx * 0.017 - wy * 0.035) * 1.3 + sin(wx * 0.06 + wy * 0.045) * 0.5) / 2.8

# рельеф без русла и озёр (по нему — уровень воды)
static func base_height(wx: float, wy: float) -> float:
	var north := ss(-90.0, -200.0, wy) * (4.0 + 1.5 * sin(wx * 0.035 + 1.2))
	var south := ss(100.0, 210.0, wy) * (1.2 + 0.6 * sin(wx * 0.03 - wy * 0.02))
	var bumps := 0.32 * sin(wx * 0.28 + wy * 0.14) * sin(wy * 0.25 - wx * 0.12)
	return north + south + bumps

static func swamp_at(wx: float, wy: float) -> float:
	return ss(-95.0, -130.0, wx) * ss(70.0, 100.0, wy) * ss(215.0, 190.0, wy)

# до ближайшего оврага: x — расстояние (тайлы), y — 1, если по дну течёт ручей
static func ravine_dist(wx: float, wy: float) -> Vector2:
	var p := Vector2(wx, wy)
	if not _rv_bb.has_point(p):
		return Vector2(999.0, 0.0)
	var best := Vector2(999.0, 0.0)
	for i in _rv.size() / 5:
		var a := Vector2(_rv[i * 5], _rv[i * 5 + 1])
		var b := Vector2(_rv[i * 5 + 2], _rv[i * 5 + 3])
		var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
		if d < best.x:
			best = Vector2(d, _rv[i * 5 + 4])
	return best

# ---------- всё о месте (x, y) ----------
# Возвращает массив: [h, water, ravine, swamp, clearing, rocky, path]
static func terrain(wx: float, wy: float) -> PackedFloat32Array:
	var rd := river_dist(wx, wy)
	var ford := ford_factor(wx, wy)
	var water_w := 1.4 * (1.0 - 0.75 * ford)
	var rwater := ss(water_w, water_w * 0.6, rd) * (1.0 - 0.85 * ford)
	var ravine := ss(7.0, 1.8, rd)
	var swamp := swamp_at(wx, wy) * (1.0 - ravine * 0.8)
	var lk := lake_at(wx, wy)
	var hb := base_height(wx, wy)
	var h := hb * (1.0 - ravine * 0.7) - ravine * 2.6 * (1.0 - 0.85 * ford) - swamp * 1.0
	var clearing := 0.0
	for i in _ft.size() / 4:
		var fr: float = _ft[i * 4 + 2]
		var c := ss(fr, fr * 0.25, Vector2(wx - _ft[i * 4], wy - _ft[i * 4 + 1]).length())
		if c > 0.0:
			clearing = maxf(clearing, c)
			h = lerpf(h, _ft[i * 4 + 3], c * 0.85)       # поляна под локацию — ровная (до озёр: вода её не заливает и не поднимает дно)
	if lk.z >= 0.0:
		var lvl := lake_level(int(lk.z))
		if lk.x < 1.0:   # берег у кромки не ниже воды (без «канавы» с водой); дальше 6 тайлов — как было
			h = maxf(h, lvl + 0.1 - 0.7 * ss(0.15, 0.0, lk.w))
		h = lerpf(h, lvl - 0.04 - lk.y * _lk[int(lk.z) * 5 + 3], lk.x)          # дно: мелко у берега, глубже к центру
	var rocky := ss(3.2, 5.2, hb) * 0.85
	# карьер: террасы, каменистое дно, без леса
	var qd := Vector2(wx - QUARRY.x, wy - QUARRY.y).length()
	if qd < QUARRY.z + 6.0:
		var qk := ss(QUARRY.z, QUARRY.z * 0.3, qd)
		h -= 8.0 * (roundf(qk * 3.0) / 3.0 * 0.65 + qk * 0.35)
		rocky = maxf(rocky, ss(QUARRY.z + 1.0, QUARRY.z * 0.8, qd))
		clearing = maxf(clearing, ss(QUARRY.z + 6.0, QUARRY.z, qd))
	# овраги (и ручей по дну)
	var rvd := ravine_dist(wx, wy)
	if rvd.x < 9.0:
		var rk := ss(9.0, 1.5, rvd.x)
		h -= rk * 3.2
		ravine = maxf(ravine, rk)
		if rvd.y > 0.5:
			rwater = maxf(rwater, ss(1.4, 0.7, rvd.x))
	var pd := path_dist(wx, wy)
	var ad := asphalt_dist(wx, wy)
	var path := maxf(ss(2.0, 0.8, pd), ss(3.6, 2.4, ad))
	var lwet := ss(0.8, 1.0, lk.w) if lk.z >= 0.0 else 0.0     # мягкий переход «мокро» у кромки (без ступенек на текстуре)
	return PackedFloat32Array([h, maxf(rwater, lwet), ravine, swamp, clearing, rocky, path, pd, ad])

static func lake_level(i: int) -> float:
	return _lk[i * 5 + 4]

# Вода в точке: x — есть ли (0..1), y — уровень поверхности (старые метры, как height)
static func water_at(wx: float, wy: float) -> Vector2:
	var lk := lake_at(wx, wy)
	if lk.z >= 0.0:
		return Vector2(lk.x, lake_level(int(lk.z)))
	var rvd := ravine_dist(wx, wy)
	if rvd.y > 0.5 and rvd.x < 2.5:
		return Vector2(ss(1.6, 0.8, rvd.x), base_height(wx, wy) - 3.2 + 0.45)   # ручей по дну оврага
	var rd := river_dist(wx, wy)
	if rd < 5.0:
		var hb := base_height(wx, wy)
		return Vector2(ss(2.6, 1.2, rd) * (1.0 - 0.85 * ford_factor(wx, wy)), hb * 0.3 - 1.3)
	return Vector2.ZERO

# течение в точке (тайлы/с, условно): река течёт на восток вдоль русла, в озёрах — лёгкий дрейф
static func flow_at(wx: float, wy: float) -> Vector2:
	if lake_at(wx, wy).z >= 0.0:
		return Vector2(0.06, 0.04)
	if river_dist(wx, wy) < 6.0:
		var k := 16.0 * 0.018 * cos(wx * 0.018 + 0.4) + 6.0 * 0.045 * cos(wx * 0.045)
		return Vector2(1.0, k).normalized() * 0.9
	return Vector2.ZERO

# рисовать ли воду в точке (шире самой воды: кромку обрезает земля, без «зубцов»)
static func water_draw(wx: float, wy: float) -> bool:
	if lake_at(wx, wy).w > 0.15:
		return true
	var rvd := ravine_dist(wx, wy)
	if rvd.y > 0.5 and rvd.x < 2.5:
		return true
	return river_dist(wx, wy) < 5.0

static func height(wx: float, wy: float) -> float:
	return terrain(wx, wy)[0]

# высота в метрах Godot
static func height_m(wx: float, wy: float) -> float:
	return terrain(wx, wy)[0] * HK

# Слои земли в точке: path, swamp, riverbed, rocky, water, clearing (0..1)
static func ground_layers(wx: float, wy: float) -> PackedFloat32Array:
	return ground_layers_t(wx, wy, terrain(wx, wy))

# то же по уже посчитанному terrain(): при постройке чанка рельеф считается один раз
static func ground_layers_t(wx: float, wy: float, t: PackedFloat32Array) -> PackedFloat32Array:
	var swamp := t[3]
	var path := ss(1.9, 0.7, t[7]) * (1.0 - swamp * 0.7)
	# асфальт (главные дороги ~4,5 м) с грунтовой обочиной; кодируется в том же канале: 0..0,5 — грунт, 0,5..1 — асфальт
	var asph := ss(2.9, 2.2, t[8])
	path = maxf(path, ss(3.7, 2.6, t[8]))
	if asph > 0.01:
		path = 0.5 + 0.5 * asph
	else:
		path *= 0.5
	var lkb := lake_at(wx, wy)
	var sand := ss(0.25, 1.0, lkb.w) * (1.0 - lkb.x * 0.0) if lkb.z >= 0.0 else 0.0     # песчаная полоса вокруг озёр
	var riverbed := maxf(maxf(ss(2.6, 1.2, river_dist(wx, wy)), t[1]), sand)   # песок с галькой (Poly Haven coast_sand_01) — берега и дно
	var meadow := 1.0 - forest_mask(wx, wy) * 0.95
	return PackedFloat32Array([path, swamp, riverbed, t[5] * 0.6, t[1], maxf(t[4], meadow * (1.0 - swamp))])

# название места: локация (если внутри) или зона
static func place_name(wx: float, wy: float) -> String:
	for key in FEATURES:
		var f: Dictionary = FEATURES[key]
		if Vector2(wx - f.x, wy - f.y).length() < f.r:
			return f.name
	for key in HAMLETS:
		var h: Dictionary = HAMLETS[key]
		if Vector2(wx - h.x, wy - h.y).length() < h.r:
			return h.name
	if river_dist(wx, wy) < 14.0:
		return "Река Быстрянка"
	if lake_at(wx, wy).x > 0.3:
		return "Озеро"
	return zone_at(wx, wy).name

static func zone_at(wx: float, wy: float) -> Dictionary:
	var x := wx + 22.0 * sin(wy * 0.021 + 1.3)       # «изгиб» границ зон
	var y := wy + 22.0 * sin(wx * 0.024 + 0.4)
	var best := 0
	var bd := 1e12
	for i in _zn.size() / 2:
		var d: float = (x - _zn[i * 2]) * (x - _zn[i * 2]) + (y - _zn[i * 2 + 1]) * (y - _zn[i * 2 + 1])
		if d < bd:
			bd = d
			best = i
	return ZONES[best]

static func ecosystem(cx: int, cy: int) -> Dictionary:
	var wx := float(cx * CHUNK) + CHUNK * 0.5
	var wy := float(cy * CHUNK) + CHUNK * 0.5
	var z: Dictionary = zone_at(wx, wy)
	var sets := {"FIR": FIR, "PINE": PINE, "BIRCH": BIRCH, "OAK": OAK, "ASPEN": ASPEN, "BROAD": BROAD, "DEAD": DEAD}
	var canopy := []
	for c in z.canopy:
		canopy.append([sets[c[0]], c[1]])
	var e := {"name": z.name, "canopy": canopy, "dens": z.dens, "dead": z.dead, "moss": 0.5, "fern": z.fern, "grass": z.grass, "shrub": z.shrub}
	if river_dist(wx, wy) < 18.0:      # речная долина: лиственные, реже
		e.name = "Река Быстрянка"
		e.canopy = [[BROAD, 3], [BIRCH, 2], [ASPEN, 2]]
		e.dens = mini(int(e.dens), 3)
		e.grass = 1.0
	return e

static func _pick_weighted(groups: Array, r: float) -> Array:
	var sum := 0.0
	for g in groups:
		sum += g[1]
	var x := r * sum
	for g in groups:
		if x < g[1]:
			return g[0]
		x -= g[1]
	return groups[0][0]

# ---------- шум и лесистость: лес — крупные массивы, между ними поляны и луга; на лугах — редкие рощицы ----------
static func _hash2(ix: int, iy: int, sd: int) -> float:
	var n: int = (ix * 374761393 + iy * 668265263 + sd * 1274126177) & 0x7FFFFFFF
	n = ((n ^ (n >> 13)) * 1103515245 + 12345) & 0x7FFFFFFF
	return float(n & 0xFFFF) / 65535.0

static func vnoise(x: float, y: float, scale: float, sd: int) -> float:
	var fx := x / scale
	var fy := y / scale
	var ix := int(floor(fx))
	var iy := int(floor(fy))
	var tx := fx - ix
	var ty := fy - iy
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := _hash2(ix, iy, sd)
	var b := _hash2(ix + 1, iy, sd)
	var c := _hash2(ix, iy + 1, sd)
	var d := _hash2(ix + 1, iy + 1, sd)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)

# лесистость зоны с плавными переходами (веса по расстоянию до центров зон)
static func forest_bias(wx: float, wy: float) -> float:
	var sum := 0.0
	var ws := 0.0
	for i in _zb.size():
		var dx: float = wx - _zn[i * 2]
		var dy: float = wy - _zn[i * 2 + 1]
		var w := 1.0 / pow(dx * dx + dy * dy + 900.0, 2.0)
		sum += w * _zb[i]
		ws += w
	return sum / maxf(ws, 1e-12)

# 0..1: сплошной лес (массивы 40–120 тайлов), резкая кромка
static func forest_mask(wx: float, wy: float) -> float:
	var n := 0.55 * vnoise(wx, wy, 38.0, 11) + 0.3 * vnoise(wx, wy, 17.0, 12) + 0.15 * vnoise(wx, wy, 7.0, 13)
	return ss(0.47, 0.56, n + (forest_bias(wx, wy) - 0.5) * 1.25)

# плотность деревьев: лес + небольшие рощицы на открытых местах
static func tree_density(wx: float, wy: float) -> float:
	var grove := ss(0.72, 0.8, vnoise(wx, wy, 11.0, 21)) * 0.85
	return maxf(forest_mask(wx, wy), grove)

# Лесистость (0..1): крупные пятна — густой лес, редколесье, поляны без деревьев.
# В полях (мало деревьев в зоне) — только редкие рощицы.
static func forest_patch(wx: float, wy: float, dens: int) -> float:
	var n := (sin(wx * 0.045 + 0.7) * sin(wy * 0.038 - 1.1) + 0.6 * sin(wx * 0.021 - wy * 0.027 + 2.0) + 0.35 * sin((wx + wy) * 0.09)) / 1.95
	if dens <= 1:
		return ss(0.35, 0.6, n)                 # поля: рощи только в «пиках» шума
	return 0.12 + 0.88 * ss(-0.35, 0.3, n)      # лес: местами густо, местами редко/пусто

static func in_map(x: float, y: float, m: float) -> bool:
	return absf(x) < MAP_RADIUS - m and absf(y) < MAP_RADIUS - m

# внутри поляны локации (там стоят постройки: деревья, подрост и кусты не растут)
static func in_feature(wx: float, wy: float, k: float = 0.98) -> bool:
	for i in _ft.size() / 4:
		if Vector2(wx - _ft[i * 4], wy - _ft[i * 4 + 1]).length() < _ft[i * 4 + 2] * k:
			return true
	return false

static func tree_spot(wx: float, wy: float, r: float) -> PackedFloat32Array:
	var t := terrain(wx, wy)
	if t[1] > 0.05 or t[2] > 0.8 or t[6] > 0.35 or t[4] > 0.35 or in_feature(wx, wy):
		return PackedFloat32Array()
	if t[3] > 0.5 and r > 0.45:
		return PackedFloat32Array()
	if t[5] > 0.65 and r > 0.6:
		return PackedFloat32Array()
	return t

# ---------- содержимое чанка ----------
static func _obj(rng: RandomNumberGenerator, x: float, y: float, key: String, cat: String, sc: float) -> Dictionary:
	return {"x": x, "y": y, "key": key, "cat": cat, "scale": sc, "flip": rng.randf() > 0.5}

# Каждый объект: {x, y, key, cat, scale, flip}; solid — те, что не пропускают бойца и пули (+ r)
static func chunk_content(cx: int, cy: int, density: float = 1.0) -> Dictionary:
	var eco := ecosystem(cx, cy)
	var sx := float(cx * CHUNK)
	var sy := float(cy * CHUNK)
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(((cx * 73856093) & 0xFFFFFFFF) ^ ((cy * 19349663) & 0xFFFFFFFF)) + 12345
	var objs: Array = []
	var trees: Array = []
	# 1) деревья: массивы леса (густо) и рощицы; на лугах и в полях пусто
	var cap: int = 3 + int(eco.dens)              # деревья в настоящий размер (крона 6–9 м): до 8 на чанк 10×10 м
	for i in 90:
		if trees.size() >= cap:
			break
		var x: float = sx + 0.8 + rng.randf() * (CHUNK - 1.6)
		var y: float = sy + 0.8 + rng.randf() * (CHUNK - 1.6)
		var r0: float = rng.randf()
		var rd: float = rng.randf()
		if not in_map(x, y, 1.0):
			continue
		var td := tree_density(x, y)
		if td < 0.04 or rd > td:
			continue
		var spacing := 4.8 + (1.0 - td) * 2.4         # 4–6 м между стволами (в тайлах по 0.84 м), как в спелом лесу
		var ok := true
		for t in trees:
			if Vector2(t.x - x, t.y - y).length() < spacing:
				ok = false
				break
		if not ok:
			continue
		var spot := tree_spot(x, y, r0)
		if spot.is_empty() or cleared(x, y, 4.5):            # запас 4,5 тайла (~3,8 м): крона не нависает над домом
			continue
		var dead: bool = rng.randf() < (eco.dead + (0.2 if spot[3] > 0.5 else 0.0) + morok(x, y) * 0.7)
		var set: Array = DEAD if dead else _pick_weighted(eco.canopy, rng.randf())
		if not dead and spot[3] > 0.25 and rng.randf() < 0.75:
			set = WET                                  # у воды и в сырых низинах — ольха и ива
		var key: String = set[int(rng.randf() * set.size())]
		var o: Dictionary = _obj(rng, x, y, key, "dead" if dead else "tree", 0.88 + rng.randf() * 0.24)
		objs.append(o)
		trees.append(o)
	# 1б) сады во дворах (яблони) — из props.gd
	for i in _xt.size() / 3:
		var xa: float = _xt[i * 3]
		var ya: float = _xt[i * 3 + 1]
		if xa >= sx and xa < sx + CHUNK and ya >= sy and ya < sy + CHUNK:
			var oa: Dictionary = _obj(rng, xa, ya, _xt_keys[int(_xt[i * 3 + 2])], "tree", 0.85 + rng.randf() * 0.3)
			objs.append(oa)
			trees.append(oa)
	# 2) подрост и кусты: под пологом и по опушкам; на лугах — куртинами
	for i in 7:
		var x2: float = sx + rng.randf() * CHUNK
		var y2: float = sy + rng.randf() * CHUNK
		var r2: float = rng.randf()
		var ra: float = rng.randf()
		var t2 := terrain(x2, y2)
		if t2[1] > 0.02 or t2[6] > 0.3 or t2[4] > 0.5 or in_feature(x2, y2):
			continue
		var td2 := tree_density(x2, y2)
		if ra > 0.12 + 0.75 * td2 or cleared(x2, y2, 1.0):
			continue
		if r2 < 0.5:
			objs.append(_obj(rng, x2, y2, SAP_SMALL[int(rng.randf() * SAP_SMALL.size())], "sap", 0.8 + rng.randf() * 0.4))
		elif r2 < 0.75:
			objs.append(_obj(rng, x2, y2, SAP_MED[int(rng.randf() * SAP_MED.size())], "sapm", 0.8 + rng.randf() * 0.35))
	var nshrub := int(round(9.0 * eco.shrub * density))
	for i in nshrub:
		var x3: float = sx + rng.randf() * CHUNK
		var y3: float = sy + rng.randf() * CHUNK
		var rs: float = rng.randf()
		var t3 := terrain(x3, y3)
		if t3[1] > 0.02 or path_dist(x3, y3) < 1.5 or t3[3] > 0.6 or in_feature(x3, y3):
			continue
		var td3 := tree_density(x3, y3)
		if cleared(x3, y3, 0.5):
			continue
		var edge := 4.0 * td3 * (1.0 - td3)                        # опушка
		var clump := ss(0.62, 0.78, vnoise(x3, y3, 5.0, 31))      # куртина
		if rs > 0.08 + 0.55 * edge + 0.7 * clump + 0.25 * td3:
			continue
		objs.append(_obj(rng, x3, y3, SHRUB[int(rng.randf() * SHRUB.size())], "shrub", 0.8 + rng.randf() * 0.4))
	# 3) травяной ярус по месту: тень леса — папоротник и мох, поляны — трава и цветы, у воды — крапива
	var ncover := int(50.0 * density * (1.0 - 0.6 * morok(sx + CHUNK * 0.5, sy + CHUNK * 0.5)))   # в мороке трава редеет
	for i in ncover:
		var x4: float = sx + rng.randf() * CHUNK
		var y4: float = sy + rng.randf() * CHUNK
		var r4: float = rng.randf()
		var k4: float = rng.randf()
		var t4 := terrain(x4, y4)
		if t4[1] > 0.02 or path_dist(x4, y4) < 1.2:
			continue
		var clearing := maxf(t4[4], 1.0 - forest_mask(x4, y4) * 0.92)
		var w := {
			"fern": (0.35 + t4[2] * 0.5) * (1.0 - clearing) * (1.0 - t4[5] * 0.6) * eco.fern,
			"grass": (0.25 + clearing * 1.2 + t4[3] * 0.6) * eco.grass,
			"flower": clearing * 0.45 * eco.grass,
			"nettle": (0.05 + clearing * 0.15 + t4[2] * 0.3) * (1.0 - t4[3]),
		}
		var sum := 0.0
		for kk in w:
			sum += w[kk]
		if r4 > minf(0.92, sum * 0.6):
			continue
		var pick := k4 * sum
		var kind := "grass"
		for kk in w:
			if pick < w[kk]:
				kind = kk
				break
			pick -= w[kk]
		var lst: Array = {"fern": FERN, "grass": GRASS, "flower": FLOWERS, "nettle": NETTLE}[kind]
		var sk: float = 0.7 if kind == "fern" else 1.0
		objs.append(_obj(rng, x4, y4, lst[int(rng.randf() * lst.size())], kind, (0.8 + rng.randf() * 0.4) * sk))
	# 4) валежник: пни, брёвна, ветки, корни
	if rng.randf() < 0.45:
		var x5: float = sx + 1.0 + rng.randf() * (CHUNK - 2)
		var y5: float = sy + 1.0 + rng.randf() * (CHUNK - 2)
		if not tree_spot(x5, y5, 0.0).is_empty() and not cleared(x5, y5):
			objs.append(_obj(rng, x5, y5, STUMP[int(rng.randf() * STUMP.size())], "stump", 0.85 + rng.randf() * 0.3))
	if rng.randf() < 0.3:
		var x6: float = sx + 2.0 + rng.randf() * (CHUNK - 4)
		var y6: float = sy + 2.0 + rng.randf() * (CHUNK - 4)
		if not tree_spot(x6, y6, 0.0).is_empty() and not cleared(x6, y6):
			objs.append(_obj(rng, x6, y6, LOG[int(rng.randf() * LOG.size())], "log", 0.85 + rng.randf() * 0.3))
	for i in 2:
		var x7: float = sx + rng.randf() * CHUNK
		var y7: float = sy + rng.randf() * CHUNK
		if rng.randf() < 0.6 and terrain(x7, y7)[1] < 0.02 and path_dist(x7, y7) > 1.2:
			objs.append(_obj(rng, x7, y7, BRANCH[int(rng.randf() * BRANCH.size())], "branch", 0.8 + rng.randf() * 0.4))
	# грибы: под деревьями (в лесу чаще), иногда у пня
	for i in 3:
		var xm: float = sx + rng.randf() * CHUNK
		var ym: float = sy + rng.randf() * CHUNK
		if rng.randf() < 0.55 * forest_mask(xm, ym) and terrain(xm, ym)[1] < 0.02 and path_dist(xm, ym) > 1.5 and not cleared(xm, ym):
			objs.append(_obj(rng, xm, ym, MUSH[int(rng.randf() * MUSH.size())], "mushroom", 0.9 + rng.randf() * 0.4))
	# 5) камни: на каменистых местах — валуны, везде — редкие камешки
	for i in 3:
		var x8: float = sx + 1.0 + rng.randf() * (CHUNK - 2)
		var y8: float = sy + 1.0 + rng.randf() * (CHUNK - 2)
		var t8 := terrain(x8, y8)
		var pr: float = 0.08 + t8[5] * 0.8
		if rng.randf() < pr and t8[1] < 0.05 and t8[6] < 0.35 and not cleared(x8, y8):
			var big: bool = t8[5] > 0.4 and rng.randf() < 0.4
			objs.append(_obj(rng, x8, y8, "boulder1" if big else ROCK[1 + int(rng.randf() * (ROCK.size() - 1))], "rock", 0.8 + rng.randf() * 0.5))
			if big or rng.randf() < 0.35:            # камни лежат группами: рядом 1–3 поменьше
				for g in 1 + int(rng.randf() * 3.0):
					var a: float = rng.randf() * TAU
					var dd: float = 1.2 + rng.randf() * 1.6
					var xg := x8 + cos(a) * dd
					var yg := y8 + sin(a) * dd
					if terrain(xg, yg)[1] < 0.05 and path_dist(xg, yg) > 1.2:
						objs.append(_obj(rng, xg, yg, ROCK[1 + int(rng.randf() * (ROCK.size() - 1))], "rock", 0.4 + rng.randf() * 0.4))
	# берег: камни разного размера по пляжу и на мелководье, пучки травы на краю пляжа
	for i in 6:
		var xs: float = sx + rng.randf() * CHUNK
		var ys: float = sy + rng.randf() * CHUNK
		var lb := lake_at(xs, ys)
		var rbd := river_dist(xs, ys)
		var shore := 0.0
		if lb.z >= 0.0:
			shore = lb.w * (1.0 - lb.y * 3.0)        # пляж и мелководье (не глубина)
		elif rbd < 6.0:
			shore = ss(6.0, 2.0, rbd)
		if shore > 0.2 and rng.randf() < shore:
			var small := rng.randf() < 0.75
			var key: String = ["stone1", "rock7", "mrock8", "mrock9", "mrock12"][int(rng.randf() * 5)] if small else ["mrock7", "mrock10", "mrock11", "mrock13"][int(rng.randf() * 4)]
			objs.append(_obj(rng, xs, ys, key, "rock", (0.35 + rng.randf() * 0.5) if small else (0.6 + rng.randf() * 0.4)))
		elif lb.z >= 0.0 and lb.x < 0.5 and lb.w > 0.45 and rng.randf() < 0.22:      # у самой воды: плавник, ветки
			if rng.randf() < 0.3:
				objs.append(_obj(rng, xs, ys, LOG[int(rng.randf() * LOG.size())], "log", 0.45 + rng.randf() * 0.3))
			else:
				objs.append(_obj(rng, xs, ys, BRANCH[int(rng.randf() * BRANCH.size())], "branch", 0.7 + rng.randf() * 0.5))
		elif lb.z >= 0.0 and lb.w > 0.05 and lb.w < 0.6 and rng.randf() < 0.7:
			objs.append(_obj(rng, xs, ys, GRASS[int(rng.randf() * GRASS.size())], "grass", 0.9 + rng.randf() * 0.4))
	var dry: Array = []        # в воде не растёт ничего; камни — можно
	for o in objs:
		if o.cat == "rock" or not water_draw(o.x, o.y):
			dry.append(o)
	objs = dry
	var solid: Array = []
	for o in objs:
		if SOLID_R.has(o.cat):
			var r: float = SOLID_R[o.cat] * (o.scale if o.cat == "rock" else 1.0)
			if o.key == "boulder1":
				r = 1.0 * o.scale
			solid.append({"x": o.x, "y": o.y, "r": r, "tree": o.cat in ["tree", "dead", "stump", "sapm"]})
	return {"objs": objs, "trees": trees, "solid": solid, "eco": eco.name}

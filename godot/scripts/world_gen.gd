class_name WorldGen
extends RefCounted
# Мир — перенос из браузерной версии (src/ground.js, src/world.js, src/cover.js).
# Все формулы — в «тайлах» старой игры (x, y на земле), как было; в Godot
# точка (x, y) тайлов -> Vector3(x * T, h * HK, y * T).

const CHUNK := 12                 # тайлов в чанке
const T := 0.837                  # метров Godot в одном тайле (так боец/деревья в тех же пропорциях)
const HK := 0.75                  # высота рельефа старой игры (м) -> метры Godot
const MAP_RADIUS := 360.0
const PX := 0.016                 # метров Godot в одном «экранном px» старой игры (размеры спрайтов)

# 5 локаций + воронка и яма (координаты — тайлы, как в v7.x)
const FEATURES := {
	"cabin": {"x": 0.0, "y": -6.0, "r": 10.0, "name": "Заимка"},
	"post": {"x": 42.0, "y": -190.0, "r": 14.0, "name": "Блокпост «Север»"},
	"ford": {"x": 45.0, "y": 62.0, "r": 12.0, "name": "Вороний Брод"},
	"ruins": {"x": 60.0, "y": 190.0, "r": 15.0, "name": "Кордон «Дубки»"},
	"bunker": {"x": -175.0, "y": 145.0, "r": 11.0, "name": "Бункер «Топи»"},
	"crater": {"x": 75.0, "y": 165.0, "r": 8.0, "depth": 3.2, "name": "Воронка"},
	"pit": {"x": -25.0, "y": -45.0, "r": 6.5, "depth": 2.5, "name": "Карстовая яма"},
}
const LANDMARKS := ["cabin", "post", "ford", "ruins", "bunker", "crater"]

# ---------- лес: наборы картинок-импосторов (assets/imp, запечены из моделей Poly Haven CC0 и EZ-Tree MIT) ----------
const FIR := ["fir_a_0", "fir_a_1", "fir_b_0", "fir_b_1", "fir_c_0", "fir_c_1"]
const PINE := ["pine_a_0", "pine_a_1", "pine_b_0", "pine_b_1", "pine_c_0", "pine_c_1"]
const BROAD := ["broad1_0", "broad1_1", "broad2_0", "broad2_1", "smalltree_0", "smalltree_1"]
const BIRCH := ["birch0_0", "birch1_0", "birch2_0"]
const OAK := ["oak0_0", "oak1_0"]
const ASPEN := ["aspen0_0", "aspen1_0"]
const DEAD := ["dead0_0", "dead1_0", "dead2_0"]
const SAP_SMALL := ["firsap_a", "firsap_b", "firsap_c", "pinesap_a", "pinesap_b", "pinesap_c"]
const SAP_MED := ["firsapm_a", "firsapm_b", "firsapm_c", "pinesapm_a", "pinesapm_b", "pinesapm_c"]
const SHRUB := ["shrub2_a", "shrub2_b", "shrub2_c", "shrub2_d", "shrub3_a", "shrub3_b", "shrub3_c", "shrub3_d", "shrub4"]
const FERN := ["fern_a", "fern_b", "fern_c", "fern_d"]
const NETTLE := ["nettle_medium_a", "nettle_medium_b", "nettle_small_a", "nettle_small_b", "nettle_tall_a", "nettle_tall_b"]
const GRASS := ["grass1_small_a", "grass1_mid_b", "grass1_tall_a", "grass1_tall_b", "grass1_large_b", "grass1_small_b", "grass2_a", "grass2_b", "grass2_c", "grass2_d", "grass2_e"]
const FLOWERS := ["celandine_a", "celandine_b", "celandine_c", "celandine_d", "celandine_e", "dandelion_a", "dandelion_b", "dandelion_c", "dandelion_d", "dandelion_e"]
const MOSS := []   # мох — слой текстуры земли
const STUMP := ["stump1", "stump2"]
const LOG := ["log1", "log1b", "log2", "log2b"]
const BRANCH := ["branches_a", "branches_b", "branches_c"]
const ROOTS := []  # корни убраны (выглядели как «тарелки» земли)
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

# ---------- река, брод, дороги ----------
static func river_center_y(wx: float) -> float:
	return 62.0 + 18.0 * sin(wx * 0.018 + 0.4) + 6.0 * sin(wx * 0.045)

static func river_dist(wx: float, wy: float) -> float:
	var dy := wy - river_center_y(wx)
	var k := 18.0 * 0.018 * cos(wx * 0.018 + 0.4) + 6.0 * 0.045 * cos(wx * 0.045)
	return absf(dy) / sqrt(1.0 + k * k)

static func ford_factor(wx: float, wy: float) -> float:
	return ss(18.0, 5.0, Vector2(wx - 45.0, wy - 62.0).length())

static func main_road_x(wy: float) -> float:
	return 20.0 + 32.0 * sin(wy * 0.014 - 0.3) + 10.0 * sin(wy * 0.038)

static func path_dist(wx: float, wy: float) -> float:
	var dx := wx - main_road_x(wy)
	var k := 32.0 * 0.014 * cos(wy * 0.014 - 0.3) + 10.0 * 0.038 * cos(wy * 0.038)
	var d := absf(dx) / sqrt(1.0 + k * k)
	if wx <= 25.0 and wx >= -220.0 and wy >= 10.0 and wy <= 180.0:
		var t := clampf((18.0 - wx) / 195.0, 0.0, 1.0)
		var ty := 18.0 + 127.0 * t + 14.0 * sin(t * PI * 2.0)
		d = minf(d, Vector2(wx - (18.0 - t * 195.0), wy - ty).length())
	if wx >= 20.0 and wx <= 170.0 and wy >= -160.0 and wy <= -50.0:
		var t2 := clampf((wx - 28.0) / 112.0, 0.0, 1.0)
		var ty2 := -60.0 - 60.0 * t2 + 10.0 * sin(t2 * PI)
		d = minf(d, Vector2(wx - (28.0 + t2 * 112.0), wy - ty2).length())
	return d

static func radial(x: float, y: float, f: Dictionary) -> float:
	var r: float = f.r
	return ss(r, r * 0.25, Vector2(x - f.x, y - f.y).length())

static func soil_noise(wx: float, wy: float) -> float:
	return (sin(wx * 0.03 + wy * 0.017) + sin(wx * 0.017 - wy * 0.035) * 1.3 + sin(wx * 0.06 + wy * 0.045) * 0.5) / 2.8

# ---------- всё о месте (x, y) ----------
# Возвращает массив: [h, water, ravine, swamp, clearing, rocky, path]
static func terrain(wx: float, wy: float) -> PackedFloat32Array:
	var rd := river_dist(wx, wy)
	var ford := ford_factor(wx, wy)
	var water_w := 1.25 * (1.0 - 0.75 * ford)
	var water := ss(water_w, water_w * 0.6, rd) * (1.0 - 0.85 * ford)
	var ravine := ss(8.5, 1.8, rd)
	var swamp := ss(-60.0, -130.0, wx) * ss(30.0, 80.0, wy) * ss(240.0, 190.0, wy) * (1.0 - ravine * 0.8)
	var north := ss(-40.0, -180.0, wy) * (4.2 + 1.6 * sin(wx * 0.035 + 1.2))
	var south := ss(90.0, 220.0, wy) * (2.2 + 1.0 * sin(wx * 0.03 - wy * 0.02))
	var crater := radial(wx, wy, FEATURES.crater)
	var fpit := radial(wx, wy, FEATURES.pit)
	var bumps := 0.32 * sin(wx * 0.28 + wy * 0.14) * sin(wy * 0.25 - wx * 0.12) * (1.0 - ravine) * (1.0 - swamp)
	var rav_depth := 2.8 * (1.0 - 0.85 * ford)
	var h := north + south + bumps - ravine * rav_depth - swamp * 1.2 - crater * 3.2 - fpit * 2.5
	var clearing := maxf(maxf(radial(wx, wy, FEATURES.cabin), radial(wx, wy, FEATURES.post)), maxf(radial(wx, wy, FEATURES.ruins), radial(wx, wy, FEATURES.bunker)))
	var rocky := ss(3.2, 5.2, north) * 0.85
	if crater > 0.1:
		rocky += ss(0.2, 0.6, crater) * 0.7
	var path := ss(2.0, 0.8, path_dist(wx, wy))
	return PackedFloat32Array([h, water, ravine, swamp, clearing, rocky, path])

static func height(wx: float, wy: float) -> float:
	return terrain(wx, wy)[0]

# высота в метрах Godot
static func height_m(wx: float, wy: float) -> float:
	return terrain(wx, wy)[0] * HK

# Слои земли в точке: path, swamp, riverbed, rocky, water, clearing (0..1)
static func ground_layers(wx: float, wy: float) -> PackedFloat32Array:
	var t := terrain(wx, wy)
	var swamp := t[3]
	var path := ss(1.9, 0.7, path_dist(wx, wy)) * (1.0 - swamp * 0.7)
	var riverbed := ss(1.7, 0.95, river_dist(wx, wy))
	return PackedFloat32Array([path, swamp, riverbed, t[5] * 0.6, t[1], t[4]])

static func ecosystem(cx: int, cy: int) -> Dictionary:
	# canopy: [набор, вес]…, dens — деревьев на чанк, dead — доля сухостоя
	var wx := float(cx * CHUNK)
	var wy := float(cy * CHUNK)
	if wy < -70.0:
		return {"name": "Северный Скалистый Бор", "canopy": [[PINE, 5], [FIR, 4], [BIRCH, 1]], "dens": 7, "dead": 0.05, "moss": 1.0, "fern": 0.6, "grass": 0.3, "shrub": 0.3}
	if wy > 110.0 and wx > -70.0:
		return {"name": "Заброшенный Дубовый Хутор", "canopy": [[OAK, 4], [BROAD, 3], [BIRCH, 1], [ASPEN, 1]], "dens": 4, "dead": 0.04, "moss": 0.2, "fern": 0.4, "grass": 1.0, "shrub": 1.0}
	if absf(wy - river_center_y(wx)) < 26.0:
		return {"name": "Долина Реки Быстрянки", "canopy": [[BROAD, 4], [BIRCH, 2], [ASPEN, 2], [OAK, 1]], "dens": 5, "dead": 0.04, "moss": 0.3, "fern": 0.5, "grass": 1.0, "shrub": 1.0}
	if wx < -60.0 and wy >= 30.0 and wy <= 220.0:
		return {"name": "Гиблые Мшистые Топи", "canopy": [[BIRCH, 3], [PINE, 2], [DEAD, 2]], "dens": 3, "dead": 0.25, "moss": 1.0, "fern": 0.3, "grass": 0.8, "shrub": 0.4}
	return {"name": "Центральная Лесная Заимка", "canopy": [[FIR, 3], [PINE, 3], [BIRCH, 3], [ASPEN, 1], [OAK, 1], [BROAD, 1]], "dens": 6, "dead": 0.05, "moss": 0.6, "fern": 1.0, "grass": 0.6, "shrub": 0.6}

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

static func in_map(x: float, y: float, m: float) -> bool:
	return absf(x) < MAP_RADIUS - m and absf(y) < MAP_RADIUS - m

static func tree_spot(wx: float, wy: float, r: float) -> PackedFloat32Array:
	var t := terrain(wx, wy)
	if t[1] > 0.05 or t[2] > 0.8 or t[6] > 0.35 or t[4] > 0.35:
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
	# 1) деревья: кандидаты с минимальным расстоянием
	var want: int = eco.dens
	for i in want * 3:
		if trees.size() >= want:
			break
		var x: float = sx + 0.8 + rng.randf() * (CHUNK - 1.6)
		var y: float = sy + 0.8 + rng.randf() * (CHUNK - 1.6)
		var r0: float = rng.randf()
		if not in_map(x, y, 1.0):
			continue
		var ok := true
		for t in trees:
			if Vector2(t.x - x, t.y - y).length() < 3.0:
				ok = false
				break
		if not ok:
			continue
		var spot := tree_spot(x, y, r0)
		if spot.is_empty():
			continue
		var dead: bool = rng.randf() < (eco.dead + (0.2 if spot[3] > 0.5 else 0.0))
		var set: Array = DEAD if dead else _pick_weighted(eco.canopy, rng.randf())
		var key: String = set[int(rng.randf() * set.size())]
		var o: Dictionary = _obj(rng, x, y, key, "dead" if dead else "tree", 0.88 + rng.randf() * 0.24)
		objs.append(o)
		trees.append(o)
	# 2) подрост, кусты
	for i in 3:
		var x2: float = sx + rng.randf() * CHUNK
		var y2: float = sy + rng.randf() * CHUNK
		var t2 := terrain(x2, y2)
		if t2[1] > 0.02 or t2[6] > 0.3 or t2[4] > 0.5:
			continue
		var r2: float = rng.randf()
		if r2 < 0.45:
			objs.append(_obj(rng, x2, y2, SAP_SMALL[int(rng.randf() * SAP_SMALL.size())], "sap", 0.8 + rng.randf() * 0.4))
		elif r2 < 0.7:
			objs.append(_obj(rng, x2, y2, SAP_MED[int(rng.randf() * SAP_MED.size())], "sapm", 0.8 + rng.randf() * 0.35))
	var nshrub := int(round(3.0 * eco.shrub * density))
	for i in nshrub:
		var x3: float = sx + rng.randf() * CHUNK
		var y3: float = sy + rng.randf() * CHUNK
		var t3 := terrain(x3, y3)
		if t3[1] > 0.02 or path_dist(x3, y3) < 1.5 or t3[3] > 0.6:
			continue
		objs.append(_obj(rng, x3, y3, SHRUB[int(rng.randf() * SHRUB.size())], "shrub", 0.8 + rng.randf() * 0.4))
	# 3) травяной ярус по месту: тень леса — папоротник и мох, поляны — трава и цветы, у воды — крапива
	var ncover := int(70.0 * density)
	for i in ncover:
		var x4: float = sx + rng.randf() * CHUNK
		var y4: float = sy + rng.randf() * CHUNK
		var r4: float = rng.randf()
		var k4: float = rng.randf()
		var t4 := terrain(x4, y4)
		if t4[1] > 0.02 or path_dist(x4, y4) < 1.2:
			continue
		var clearing := maxf(t4[4], ss(0.18, 0.46, soil_noise(x4, y4)))
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
		if not tree_spot(x5, y5, 0.0).is_empty():
			objs.append(_obj(rng, x5, y5, STUMP[int(rng.randf() * STUMP.size())], "stump", 0.85 + rng.randf() * 0.3))
	if rng.randf() < 0.3:
		var x6: float = sx + 2.0 + rng.randf() * (CHUNK - 4)
		var y6: float = sy + 2.0 + rng.randf() * (CHUNK - 4)
		if not tree_spot(x6, y6, 0.0).is_empty():
			objs.append(_obj(rng, x6, y6, LOG[int(rng.randf() * LOG.size())], "log", 0.85 + rng.randf() * 0.3))
	for i in 2:
		var x7: float = sx + rng.randf() * CHUNK
		var y7: float = sy + rng.randf() * CHUNK
		if rng.randf() < 0.6 and terrain(x7, y7)[1] < 0.02 and path_dist(x7, y7) > 1.2:
			objs.append(_obj(rng, x7, y7, BRANCH[int(rng.randf() * BRANCH.size())], "branch", 0.8 + rng.randf() * 0.4))
	for t in trees:
		if not ROOTS.is_empty() and rng.randf() < 0.35:
			var a := rng.randf() * TAU
			objs.append(_obj(rng, t.x + cos(a) * 0.3, t.y + sin(a) * 0.3, ROOTS[int(rng.randf() * ROOTS.size())], "roots", 0.7 + rng.randf() * 0.3))
	# 5) камни: на каменистых местах — валуны, везде — редкие камешки
	for i in 3:
		var x8: float = sx + 1.0 + rng.randf() * (CHUNK - 2)
		var y8: float = sy + 1.0 + rng.randf() * (CHUNK - 2)
		var t8 := terrain(x8, y8)
		var pr: float = 0.08 + t8[5] * 0.8
		if rng.randf() < pr and t8[1] < 0.05 and t8[6] < 0.35:
			var big: bool = t8[5] > 0.4 and rng.randf() < 0.4
			objs.append(_obj(rng, x8, y8, "boulder1" if big else ROCK[1 + int(rng.randf() * (ROCK.size() - 1))], "rock", 0.8 + rng.randf() * 0.5))
	var solid: Array = []
	for o in objs:
		if SOLID_R.has(o.cat):
			var r: float = SOLID_R[o.cat] * (o.scale if o.cat == "rock" else 1.0)
			if o.key == "boulder1":
				r = 1.0 * o.scale
			solid.append({"x": o.x, "y": o.y, "r": r, "tree": o.cat in ["tree", "dead", "stump", "sapm"]})
	return {"objs": objs, "trees": trees, "solid": solid, "eco": eco.name}

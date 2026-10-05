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

# Породы деревьев (3D-модели assets/trees3d, список — TREE_MODELS в world.gd)
const TREE_FILES := ["00_pine", "01_oak", "02_birch", "03_maple", "04_deadwood", "05_bluespruce",
	"06_willow", "07_aspen", "08_rowan", "09_cedar", "10_larch", "11_linden"]
const TREE_DRAW_W := 214.0
const TREE_DRAW_H := 428.0
const TREE_BASE_FRAC := 0.9
const TREE_TRUNK_W := [0.04, 0.05, 0.092, 0.04, 0.1, 0.04, 0.05, 0.03, 0.03, 0.035, 0.04, 0.06]
const SWAMP_TREES := [2, 0, 4]
const ROCK_TYPES := [["boulder_01", 0.49], ["namaqualand_boulder_02", 0.70], ["rock_09", 0.29], ["stone_01", 0.57]]
const ROCK_DRAW := 119.0

const COVER_KINDS := {
	"grass": {"keys": ["grass_0", "grass_1", "grass_2", "grass_3"], "flat": false, "sway": 1.0, "push": 1.0},
	"fern": {"keys": ["fern_0", "fern_1", "fern_2", "fern_3"], "flat": false, "sway": 0.6, "push": 0.9},
	"nettle": {"keys": ["nettle_0", "nettle_1"], "flat": false, "sway": 0.8, "push": 0.9},
	"bush": {"keys": ["bush_0", "bush_1", "bush_2"], "flat": false, "sway": 0.7, "push": 0.75},
	"sapling": {"keys": ["sapling_0", "sapling_1", "sapling_2", "sapling_3", "sapling_4", "sapling_5"], "flat": false, "sway": 0.5, "push": 0.3},
	"branch": {"keys": ["branch_0", "branch_1", "branch_2"], "flat": true, "sway": 0.0, "push": 0.0},
	"log": {"keys": ["log_0", "log_1"], "flat": true, "sway": 0.0, "push": 0.0},
	"roots": {"keys": ["roots_0", "roots_1"], "flat": true, "sway": 0.0, "push": 0.0},
}

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
	var wx := float(cx * CHUNK)
	var wy := float(cy * CHUNK)
	if wy < -70.0:
		return {"name": "Северный Скалистый Бор", "canopy": [9, 10, 0, 5], "sub": [8, 2, 4, 7]}
	if wy > 110.0 and wx > -70.0:
		return {"name": "Заброшенный Дубовый Хутор", "canopy": [1, 3, 11, 8], "sub": [8, 2, 6, 7]}
	if absf(wy - river_center_y(wx)) < 26.0:
		return {"name": "Долина Реки Быстрянки", "canopy": [6, 3, 7, 11], "sub": [6, 2, 11]}
	if wx < -60.0 and wy >= 30.0 and wy <= 220.0:
		return {"name": "Гиблые Мшистые Топи", "canopy": [2, 0, 4], "sub": [2, 4, 7]}
	return {"name": "Центральная Лесная Заимка", "canopy": [0, 2, 11, 8], "sub": [2, 7, 3, 8]}

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

static func tree_radius(type: int, scale: float) -> float:
	var half_px: float = TREE_TRUNK_W[type] * TREE_DRAW_W * scale / 2.0
	return maxf(0.5, half_px * 1.15 / (74.0 * 0.7) + 0.28)

static func rock_radius(type: int, scale: float) -> float:
	var half_px: float = ROCK_TYPES[type][1] * ROCK_DRAW * scale / 2.0
	return half_px / (74.0 * 0.7) + 0.22

# ---------- содержимое чанка ----------
# Деревья: {x, y, type, scale, giant}; камни: {x, y, type, scale, flip};
# подлесок: {x, y, kind, key, flip, scale}
static func chunk_content(cx: int, cy: int) -> Dictionary:
	var trees: Array = []
	var rocks: Array = []
	var eco := ecosystem(cx, cy)
	var sx := float(cx * CHUNK)
	var sy := float(cy * CHUNK)
	var hseed := absi(((cx * 73856093) & 0xFFFFFFFF) ^ ((cy * 19349663) & 0xFFFFFFFF))
	var seed := hseed
	var giants := 2 + int(prand(seed) * 3.0); seed += 1
	for g in giants:
		var gx := sx + 1.5 + prand(seed) * (CHUNK - 3); seed += 1
		var gy := sy + 1.5 + prand(seed) * (CHUNK - 3); seed += 1
		if not in_map(gx, gy, 1.0):
			continue
		var close := false
		for t in trees:
			if Vector2(t.x - gx, t.y - gy).length() < 3.2:
				close = true
				break
		var spot := tree_spot(gx, gy, prand(seed)); seed += 1
		if close or spot.is_empty():
			continue
		var pool: Array = SWAMP_TREES if spot[3] > 0.5 else eco.canopy
		var type: int = pool[int(prand(seed) * pool.size())]; seed += 1
		trees.append({"x": gx, "y": gy, "type": type, "scale": 1.0 + prand(seed) * 0.12, "giant": true}); seed += 1
		var sats := 1 + int(prand(seed) * 3.0); seed += 1
		for s in sats:
			var ang := prand(seed) * TAU; seed += 1
			var dist := 1.8 + prand(seed) * 1.6; seed += 1
			var tx := gx + cos(ang) * dist
			var ty := gy + sin(ang) * dist
			if not in_map(tx, ty, 1.0):
				continue
			var sp := tree_spot(tx, ty, prand(seed)); seed += 1
			if sp.is_empty():
				continue
			var sp_pool: Array = SWAMP_TREES if sp[3] > 0.5 else eco.sub
			var st: int = sp_pool[int(prand(seed) * sp_pool.size())]; seed += 1
			trees.append({"x": tx, "y": ty, "type": st, "scale": 0.88 + prand(seed) * 0.1, "giant": false}); seed += 1
	if prand(seed) < 0.22:
		seed += 1
		var dx := sx + 1.5 + prand(seed) * (CHUNK - 3); seed += 1
		var dy := sy + 1.5 + prand(seed) * (CHUNK - 3); seed += 1
		if in_map(dx, dy, 1.0) and not tree_spot(dx, dy, prand(seed)).is_empty():
			var ok := true
			for t in trees:
				if Vector2(t.x - dx, t.y - dy).length() < 3.0:
					ok = false
			if ok:
				trees.append({"x": dx, "y": dy, "type": 4, "scale": 0.95 + prand(seed + 1) * 0.1, "giant": true})
	seed += 2
	# валуны на каменистых местах
	if prand(seed) < 0.35:
		seed += 1
		var rx := sx + 2.0 + prand(seed) * (CHUNK - 4); seed += 1
		var ry := sy + 2.0 + prand(seed) * (CHUNK - 4); seed += 1
		var rt := terrain(rx, ry)
		if rt[5] > 0.3 and rt[1] < 0.05 and rt[6] < 0.35 and in_map(rx, ry, 1.0):
			rocks.append({"x": rx, "y": ry, "type": int(prand(seed) * ROCK_TYPES.size()), "scale": 0.85 + prand(seed + 1) * 0.3, "flip": prand(seed + 2) > 0.5})
	var cover := _cover(trees, sx, sy, hseed + 7777)
	return {"trees": trees, "rocks": rocks, "cover": cover, "eco": eco.name}

static func _cover(trees: Array, sx: float, sy: float, seed0: int) -> Array:
	var seed := seed0
	var cover: Array = []
	for i in 70:
		var x := sx + prand(seed) * CHUNK; seed += 1
		var y := sy + prand(seed) * CHUNK; seed += 1
		var t := terrain(x, y)
		if t[1] > 0.02 or path_dist(x, y) < 1.3:
			seed += 2
			continue
		var r := prand(seed); seed += 1
		var clearing := t[4]
		var w := {
			"grass": 0.30 + clearing * 1.2 + t[3] * 0.5,
			"fern": (0.32 + t[2] * 0.5) * (1.0 - clearing) * (1.0 - t[5] * 0.6),
			"nettle": 0.06 + clearing * 0.25,
			"bush": 0.10 * (1.0 - t[3]),
			"sapling": 0.07 * (1.0 - clearing * 0.5),
			"branch": 0.12 * (1.0 - clearing),
			"log": 0.018 * (1.0 - t[3]),
		}
		var sum := 0.0
		for k in w:
			sum += w[k]
		if r > minf(0.9, sum * 0.62):
			seed += 1
			continue
		var pick := prand(seed) * sum; seed += 1
		var kind := "grass"
		for k in w:
			if pick < w[k]:
				kind = k
				break
			pick -= w[k]
		if kind != "grass" and kind != "fern":
			var near := false
			for tr in trees:
				if Vector2(tr.x - x, tr.y - y).length() < 0.9:
					near = true
					break
			if near:
				continue
		var keys: Array = COVER_KINDS[kind].keys
		cover.append({"x": x, "y": y, "kind": kind, "key": keys[int(prand(seed) * keys.size())], "flip": prand(seed + 1) > 0.5, "scale": 0.85 + prand(seed + 2) * 0.3})
		seed += 3
	# кромки склонов: гуще трава, папоротник, корни
	for i in 60:
		var x := sx + prand(seed) * CHUNK; seed += 1
		var y := sy + prand(seed) * CHUNK; seed += 1
		var r1 := prand(seed); var r2 := prand(seed + 1); var r3 := prand(seed + 2); seed += 3
		var t := terrain(x, y)
		if t[1] > 0.02 or path_dist(x, y) < 1.3:
			continue
		var h := t[0]
		var slope := Vector2(height(x + 0.5, y) - h, height(x, y + 0.5) - h).length() / 0.5
		if slope < 0.45 or r1 > minf(0.9, (slope - 0.45) * 1.6):
			continue
		var kind := "roots" if r2 < 0.22 else ("grass" if r2 < 0.62 else "fern")
		var keys: Array = COVER_KINDS[kind].keys
		cover.append({"x": x, "y": y, "kind": kind, "key": keys[int(r3 * keys.size())], "flip": r3 > 0.5, "scale": (0.7 + r1 * 0.3) if kind == "roots" else (0.8 + r1 * 0.35)})
	# корни у больших деревьев
	for tr in trees:
		if not tr.giant or prand(seed) > 0.5:
			seed += 1
			continue
		var a := prand(seed + 1) * TAU
		cover.append({"x": tr.x + cos(a) * 0.25, "y": tr.y + sin(a) * 0.25, "kind": "roots", "key": "roots_%d" % int(prand(seed + 2) * 2.0), "flip": prand(seed + 3) > 0.5, "scale": 0.9})
		seed += 4
	return cover

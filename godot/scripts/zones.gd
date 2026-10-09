extends RefCounted
# Карта зон до любых построек: прямоугольники (центр, угол оси, полудлина вдоль оси, полуширина).
# Зоны не пересекаются друг с другом, с чужими дорогами, рельсами, водой и оврагами; своя дорога (что ведёт
# к месту) идёт по оси зоны. Не помещается — зона уменьшается (до 60%), потом сдвигается вдоль дороги, иначе её нет.
# Постройки (props.gd) ставятся только внутри зоны своего места.
#   var Z = load("res://scripts/zones.gd"); var zones: Array = Z.build()
# Зона: {key, name, type, c: Vector2, a: угол оси (рад), hl, hw, own: [индексы дорог WorldGen._roads], water_ok, size_k}

const SH := [Vector2(0, 0), Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6), Vector2(12, 0), Vector2(-12, 0), Vector2(6, 6), Vector2(-6, 6), Vector2(6, -6), Vector2(-6, -6), Vector2(0, 12), Vector2(0, -12)]
const GAP := 3.0                  # зазор между зонами (тайлы)
const ROAD_FREE := 3.5            # чужая дорога не ближе (от осевой)
const RAIL_FREE := 6.0
const BUNKER_NO_HOMES := 75.0     # вокруг бункера — без жилья

# места: ключ, тип, длина вдоль своей дороги, ширина (тайлы)
const SITES := [
	["camp", "локация", 34.0, 34.0], ["bunker", "локация", 54.0, 50.0], ["farm", "локация", 64.0, 48.0],
	["sawmill", "локация", 44.0, 38.0], ["tower", "локация", 34.0, 34.0], ["lakebase", "локация", 34.0, 32.0],
	["village", "деревня", 100.0, 58.0], ["h_poselok", "посёлок", 70.0, 50.0], ["h_lager", "лагерь", 56.0, 48.0],
	["h_dachi", "дачи", 60.0, 40.0], ["h_zarechye", "хутор", 64.0, 40.0], ["h_bereza", "хутор", 64.0, 40.0],
	["h_ranger", "кордон", 30.0, 26.0], ["h_hunter", "кордон", 24.0, 22.0], ["h_cem", "кладбище", 24.0, 20.0],
	["h_quarry", "карьер", 40.0, 40.0],
]
# мини-города у локаций: улица вдоль одной из дорог сразу за зоной локации
const TOWNS := {"sawmill": [52.0, 36.0], "tower": [40.0, 32.0]}       # у колхоза — Заречье, у рыбацкой базы — Берёзовка (свои просёлки к ним)
# придорожные места у асфальта: здание фасадом к трассе, парковка перед ним (длина вдоль дороги, глубина)
const ROADSIDE := [["gas_station", 48.0, 28.0], ["supermarket", 34.0, 28.0], ["tire_shop", 20.0, 16.0],
	["auto_service", 26.0, 20.0], ["dps_post", 16.0, 12.0]]
const NAMES := {"gas_station": "АЗС, кафе, гостиница", "supermarket": "Супермаркет", "tire_shop": "Шиномонтаж", "auto_service": "Автосервис",
	"motel": "Гостиница", "dps_post": "Пост ДПС", "dump": "Свалка", "h_quarry": "Карьер"}

static func _ends(i: int) -> Array:
	var all: Array = WorldGen.ROADS + WorldGen.TRACKS
	return all[i] if i < all.size() else []

static func _own_roads(key: String) -> Array:
	var r := []
	for i in WorldGen._roads.size():
		if key in _ends(i):
			r.append(i)
	return r

# направление дороги i, уходящей от места key (с её начала у места)
static func _dir_from(i: int, key: String) -> Vector2:
	var pts: PackedVector2Array = WorldGen._roads[i].pts
	var e := _ends(i)
	if not key in e:                                             # дорога идёт мимо: направление у ближайшей точки
		var f: Dictionary = WorldGen.site(key)
		var p := Vector2(f.x, f.y)
		var best := 0
		for k in pts.size() - 1:
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1])) < p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[best], pts[best + 1])):
				best = k
		return (pts[best + 1] - pts[best]).normalized()
	if e[0] == key:
		return (pts[3] - pts[0]).normalized()
	var n := pts.size() - 1
	return (pts[n - 3] - pts[n]).normalized()

static func corners(z: Dictionary) -> Array:
	var u := Vector2(cos(z.a), sin(z.a))
	var v := Vector2(-u.y, u.x)
	var c: Vector2 = z.c
	return [c + u * z.hl + v * z.hw, c - u * z.hl + v * z.hw, c - u * z.hl - v * z.hw, c + u * z.hl - v * z.hw]

static func inside(z: Dictionary, p: Vector2, pad := 0.0) -> bool:
	var u := Vector2(cos(z.a), sin(z.a))
	var d: Vector2 = p - z.c
	return absf(d.dot(u)) <= z.hl - pad and absf(d.dot(Vector2(-u.y, u.x))) <= z.hw - pad

static func to_local(z: Dictionary, p: Vector2) -> Vector2:
	var u := Vector2(cos(z.a), sin(z.a))
	var d: Vector2 = p - z.c
	return Vector2(d.dot(u), d.dot(Vector2(-u.y, u.x)))

static func to_world(z: Dictionary, lx: float, ly: float) -> Vector2:
	var u := Vector2(cos(z.a), sin(z.a))
	return z.c + u * lx + Vector2(-u.y, u.x) * ly

static func overlap(a: Dictionary, b: Dictionary, gap := 0.0) -> bool:
	var ca := corners(a)
	var cb := corners(b)
	for z in [a, b]:
		var u := Vector2(cos(z.a), sin(z.a))
		for ax in [u, Vector2(-u.y, u.x)]:
			var a0 := INF; var a1 := -INF; var b0 := INF; var b1 := -INF
			for p in ca:
				var t: float = p.dot(ax); a0 = minf(a0, t); a1 = maxf(a1, t)
			for p in cb:
				var t: float = p.dot(ax); b0 = minf(b0, t); b1 = maxf(b1, t)
			if a1 + gap < b0 or b1 + gap < a0:
				return false
	return true

static func _road_d(i: int, p: Vector2) -> float:
	var r: Dictionary = WorldGen._roads[i]
	if not r.bb.grow(8.0).has_point(p):
		return 999.0
	var pts: PackedVector2Array = r.pts
	var d := 999.0
	for k in pts.size() - 1:
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1])))
	return d

# причина, почему зона не подходит ("" — подходит)
static func why_bad(z: Dictionary, placed: Array) -> String:
	for q in corners(z):
		if not WorldGen.in_map(q.x, q.y, 4.0):
			return "край карты"
	for o in placed:
		if overlap(z, o, GAP):
			return "зона " + o.key
	var bk: Dictionary = WorldGen.FEATURES["bunker"]
	if z.type in ["деревня", "посёлок", "хутор", "дачи", "мини-город", "лагерь"]:
		for q in corners(z) + [z.c]:
			if q.distance_to(Vector2(bk.x, bk.y)) < BUNKER_NO_HOMES:
				return "у бункера"
	var nl := maxi(2, ceili(z.hl * 2.0 / 2.5))
	var nw := maxi(2, ceili(z.hw * 2.0 / 2.5))
	var qc := Vector2(WorldGen.QUARRY.x, WorldGen.QUARRY.y)
	for i in nl + 1:
		for j in nw + 1:
			var p := to_world(z, -z.hl + 2.0 * z.hl * i / nl, -z.hw + 2.0 * z.hw * j / nw)
			if not z.water_ok and WorldGen.water_at(p.x, p.y).x > 0.05:
				return "вода"
			if WorldGen.ravine_dist(p.x, p.y).x < 5.0:
				return "овраг"
			if z.key != "h_quarry" and p.distance_to(qc) < WorldGen.QUARRY.z + 4.0:
				return "карьер"
			for ri in WorldGen._roads.size():
				if ri in z.own:
					continue
				var lim := RAIL_FREE if WorldGen._roads[ri].get("rail", false) else ROAD_FREE
				if _road_d(ri, p) < lim:
					return "дорога " + ("ж/д" if WorldGen._roads[ri].get("rail", false) else "-".join(_ends(ri)))
	return ""

# подобрать зону: размер 100…60%, сдвиг вдоль оси (и поперёк для мест без дороги внутри)
static func _fit(z: Dictionary, placed: Array, shifts: Array, keep: Vector2 = Vector2.INF) -> String:
	var hl0: float = z.hl
	var hw0: float = z.hw
	var c0: Vector2 = z.c
	var u := Vector2(cos(z.a), sin(z.a))
	var last := ""
	for k in [1.0, 0.9, 0.8, 0.7, 0.6]:
		for s in shifts:
			z.hl = hl0 * k
			z.hw = hw0 * maxf(k, 0.8)
			var sv: Vector2 = s if s is Vector2 else Vector2(float(s), 0.0)
			z.c = c0 + u * sv.x + Vector2(-u.y, u.x) * sv.y
			if keep != Vector2.INF and not inside(z, keep, 3.0):
				continue
			last = why_bad(z, placed)
			if last == "":
				z.size_k = k
				return ""
	z.hl = hl0; z.hw = hw0; z.c = c0
	return last

static func build(log := false) -> Array:
	var placed: Array = []
	var fails: Array = []
	# 1) локации, посёлки, хутора — вокруг своего места, ось по главной своей дороге (асфальт первым)
	for s in SITES:
		var key: String = s[0]
		var f: Dictionary = WorldGen.site(key)
		var c := Vector2(f.x, f.y)
		var own := _own_roads(key)
		if s[1] != "локация":                                    # посёлок прямо на трассе: трасса — его улица
			for ri in WorldGen.ROADS.size():
				if not ri in own and _road_d(ri, c) < float(f.r):
					own.insert(0, ri)
		var a := 0.0
		if not own.is_empty():
			var d := _dir_from(own[0], key)
			a = atan2(d.y, d.x)
		var z := {"key": key, "name": f.name if not NAMES.has(key) else NAMES[key], "type": s[1], "c": c, "a": a,
			"hl": float(s[2]) * 0.5, "hw": float(s[3]) * 0.5, "own": own, "water_ok": key == "lakebase", "size_k": 1.0}
		var why := _fit(z, placed, SH, c)
		if why == "":                                            # не влезло вдоль главной дороги — поперёк
			placed.append(z)
		else:
			z.a += PI * 0.5
			var why2 := _fit(z, placed, SH, c)
			if why2 == "":
				placed.append(z)
			else:
				fails.append("%s: %s / %s" % [key, why, why2])
	# 2) мини-города: вдоль одной из дорог локации, сразу за её зоной
	for key in TOWNS:
		var lz := _find(placed, key)
		if lz.is_empty():
			continue
		var ok := false
		var why := ""
		for ri in _own_roads(key):
			if ri >= WorldGen.ROADS.size():
				continue                                        # только у асфальта (не на просёлке)
			var pts: PackedVector2Array = WorldGen._roads[ri].pts
			var from_start: bool = _ends(ri)[0] == key
			var L := _len(pts)
			var sz: Array = TOWNS[key]
			for extra: float in [4.0, 10.0, 16.0, 24.0, 34.0, 46.0]:
				var s0 := 0.0
				while s0 < L * 0.45 and inside(lz, _at(pts, s0 if from_start else L - s0)[0]):
					s0 += 1.0
				var sm: float = s0 + float(sz[0]) * 0.5 + extra
				var at := _at(pts, sm if from_start else L - sm)
				var d: Vector2 = at[1]
				var z := {"key": "town_" + key, "name": "Мини-город (" + str(lz.name) + ")", "type": "мини-город", "c": at[0], "a": atan2(d.y, d.x),
					"hl": float(sz[0]) * 0.5, "hw": float(sz[1]) * 0.5, "own": [ri], "water_ok": false, "size_k": 1.0}
				why = _fit(z, placed, [0.0])
				if log and why != "":
					print("ZONE проба town_%s дорога %s +%d: %s" % [key, "-".join(_ends(ri)), extra, why])
				if why == "":
					placed.append(z)
					ok = true
					break
			if ok:
				break
		if not ok:
			fails.append("town_%s: %s" % [key, why])
	# 3) придорожные: сбоку от асфальта, без дороги внутри (фасад к трассе), подальше от посёлков
	for item in ROADSIDE:
		var hist := {}
		var ok := false
		var why := ""
		var FR := []
		for k in 31:                                             # от середины дороги к краям, шаг ~3%
			FR.append(0.5 + (k + 1) / 2 * 0.03 * (1 if k % 2 == 0 else -1))
		for fr: float in FR:
			for ri in WorldGen.ROADS.size():
				var pts: PackedVector2Array = WorldGen._roads[ri].pts
				var at := _at(pts, _len(pts) * fr)
				var d: Vector2 = at[1]
				for sd: float in [1.0, -1.0]:
					var n := Vector2(-d.y, d.x) * sd
					var z := {"key": item[0], "name": NAMES[item[0]], "type": "придорожное", "c": at[0] + n * (ROAD_FREE + 1.5 + float(item[2]) * 0.5),
						"a": atan2(d.y, d.x), "hl": float(item[1]) * 0.5, "hw": float(item[2]) * 0.5, "own": [], "water_ok": false, "size_k": 1.0,
						"front": -n}
					why = why_bad(z, placed)
					if why == "" and not _far_from_homes(z, placed, 12.0):
						why = "рядом зона"
					if log:
						var wk := why.split(" ")[0] + (" " + why.split(" ")[1] if why.begins_with("дорога") else "")
						hist[wk] = hist.get(wk, 0) + 1
					if why == "":
						placed.append(z)
						ok = true
						break
				if ok: break
			if ok: break
		if not ok:
			fails.append("%s: %s" % [item[0], str(hist)])
	if log:
		for z in placed:
			print("ZONE %-12s %-11s c %4d,%4d  %3dx%3d  угол %4d°  размер %d%%" % [z.key, z.type, roundi(z.c.x), roundi(z.c.y),
				roundi(z.hl * 2.0), roundi(z.hw * 2.0), roundi(rad_to_deg(z.a)), roundi(z.size_k * 100.0)])
		for f in fails:
			print("ZONE НЕТ ", f)
	return placed

static func _far_from_homes(z: Dictionary, placed: Array, r: float) -> bool:
	for o in placed:
		if overlap(z, o, r if o.type != "придорожное" else 18.0):
			return false
	return true

static func _find(placed: Array, key: String) -> Dictionary:
	for z in placed:
		if z.key == key:
			return z
	return {}

static func _len(pts: PackedVector2Array) -> float:
	var L := 0.0
	for i in pts.size() - 1:
		L += pts[i].distance_to(pts[i + 1])
	return L

static func _at(pts: PackedVector2Array, s: float) -> Array:
	var acc := 0.0
	for i in pts.size() - 1:
		var l := pts[i].distance_to(pts[i + 1])
		if acc + l >= s or i == pts.size() - 2:
			var t := clampf((s - acc) / maxf(l, 0.001), 0.0, 1.0)
			return [pts[i].lerp(pts[i + 1], t), (pts[i + 1] - pts[i]).normalized()]
		acc += l
	return [pts[0], Vector2(1, 0)]

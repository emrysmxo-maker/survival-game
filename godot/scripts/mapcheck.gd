extends SceneTree
# Проверка карты без экрана: считает деревья по чанкам и рисует карту (лес, вода, дороги, локации, деревья точками).
# godot --headless --path godot -s res://scripts/mapcheck.gd -- <out.png>
func _init() -> void:
	WorldGen.init()
	var R := int(WorldGen.MAP_RADIUS)
	var K := 3                                   # пикселей на тайл
	var img := Image.create(R * 2 * K, R * 2 * K, false, Image.FORMAT_RGB8)
	for py in R * 2 * K:
		for px in R * 2 * K:
			var x := float(px) / K - R
			var y := float(py) / K - R
			var t := WorldGen.terrain(x, y)
			var c: Color
			if t[1] > 0.3:
				c = Color(0.2, 0.4, 0.62)
			else:
				var fm := WorldGen.forest_mask(x, y)
				c = Color(0.62, 0.72, 0.4).lerp(Color(0.18, 0.34, 0.18), fm)
				if t[3] > 0.3:
					c = c.lerp(Color(0.35, 0.4, 0.3), 0.5)
				if t[6] > 0.35:
					c = Color(0.62, 0.5, 0.32)
			img.set_pixel(px, py, c)
	var total := 0
	var maxc := 0
	var forest_chunks := 0
	var n := 0
	var CH := WorldGen.CHUNK
	for cy in range(-R / CH - 1, R / CH + 1):
		for cx in range(-R / CH - 1, R / CH + 1):
			var cc := WorldGen.chunk_content(cx, cy, 1.0)
			n += 1
			var nt: int = cc.trees.size()
			total += nt
			maxc = maxi(maxc, nt)
			if nt >= 8:
				forest_chunks += 1
			for o in cc.trees:
				var px := int((o.x + R) * K)
				var py := int((o.y + R) * K)
				if px >= 0 and py >= 0 and px < R * 2 * K and py < R * 2 * K:
					img.set_pixel(px, py, Color(0.05, 0.16, 0.05))
	for key in WorldGen.FEATURES:
		var f: Dictionary = WorldGen.FEATURES[key]
		_dot(img, f.x, f.y, R, K, 6, Color(1, 0.9, 0.1))
	for key in WorldGen.HAMLETS:
		var h: Dictionary = WorldGen.HAMLETS[key]
		_dot(img, h.x, h.y, R, K, 4, Color(1, 0.4, 0.1))
	img.save_png(OS.get_cmdline_user_args()[0])
	# постройки: карта расстановки (дома, машины, заборы, остальное) крупно по каждой локации и хутору
	var pr = load("res://scripts/props.gd").new()
	pr._ready()
	var pts := []
	for key in pr._batch:
		var b: Dictionary = pr._batch[key]
		for xf in b.xf:
			pts.append([b.model, xf.origin.x / WorldGen.T, xf.origin.z / WorldGen.T, atan2(xf.basis.x.z, xf.basis.x.x)])
	print("pts ", pts.size(), " ", pts[0] if pts.size() > 0 else "")
	var sites := {}
	for k in WorldGen.FEATURES: sites[k] = WorldGen.FEATURES[k]
	for k in WorldGen.HAMLETS: sites[k] = WorldGen.HAMLETS[k]
	var args := OS.get_cmdline_user_args()
	# выгрузка сцены в JSON для просмотра в Blender (tools/props/scene_render.py): аргументы: <png> <сайты через запятую> <json> <сайт>
	if args.size() > 3:
		var st0: Dictionary = sites[args[3]]
		var out := {"site": args[3], "cx": st0.x, "cy": st0.y, "r": st0.r, "h0": WorldGen.height_m(st0.x, st0.y), "props": [], "trees": []}
		var lim: float = st0.r + 14.0
		for key in pr._batch:
			var b2: Dictionary = pr._batch[key]
			for xf in b2.xf:
				var tx: float = xf.origin.x / WorldGen.T
				var ty: float = xf.origin.z / WorldGen.T
				if Vector2(tx - st0.x, ty - st0.y).length() < lim:
					var bs: Basis = xf.basis
					out.props.append({"m": b2.model, "p": [xf.origin.x, xf.origin.y, xf.origin.z], "b": [bs.x.x, bs.x.y, bs.x.z, bs.y.x, bs.y.y, bs.y.z, bs.z.x, bs.z.y, bs.z.z]})
		var CHs := WorldGen.CHUNK
		for cy2 in range(int(floor((st0.y - lim) / CHs)), int(floor((st0.y + lim) / CHs)) + 1):
			for cx2 in range(int(floor((st0.x - lim) / CHs)), int(floor((st0.x + lim) / CHs)) + 1):
				var cc2 := WorldGen.chunk_content(cx2, cy2, 1.0)
				for o in cc2.trees:
					if Vector2(o.x - st0.x, o.y - st0.y).length() < lim:
						out.trees.append([o.x * WorldGen.T, WorldGen.height_m(o.x, o.y), o.y * WorldGen.T, o.scale])
		var fj := FileAccess.open(args[2], FileAccess.WRITE)
		fj.store_string(JSON.stringify(out))
	if args.size() > 1:
		for k in args[1].split(","):
			var st: Dictionary = sites[k]
			var Z := 14
			var half := int(st.r) + 6
			var im2 := Image.create(half * 2 * Z, half * 2 * Z, false, Image.FORMAT_RGB8)
			for py in half * 2 * Z:
				for px in half * 2 * Z:
					var x: float = st.x - half + float(px) / Z
					var y: float = st.y - half + float(py) / Z
					var t := WorldGen.terrain(x, y)
					var c := Color(0.62, 0.72, 0.4).lerp(Color(0.18, 0.34, 0.18), WorldGen.forest_mask(x, y))
					if t[1] > 0.3: c = Color(0.2, 0.4, 0.62)
					if t[6] > 0.35: c = Color(0.66, 0.54, 0.36)
					if Vector2(x - st.x, y - st.y).length() > st.r and Vector2(x - st.x, y - st.y).length() < st.r + 0.15: c = Color(1, 1, 0)
					im2.set_pixel(px, py, c)
			for p in pts:
				var px2 := int((p[1] - (st.x - half)) * Z)
				var py2 := int((p[2] - (st.y - half)) * Z)
				var m: String = p[0]
				var col := Color(0.5, 0.5, 0.5)
				var rr := 3
				if m.begins_with("house_") or m in ["club", "shop", "barn", "barn_long", "barracks", "chapel", "machine_shed", "sawmill_hall", "bunker_entrance", "transmitter"] or m.begins_with("shed") or m == "open_shed" or m == "boat_shed":
					col = Color(0.9, 0.35, 0.1); rr = int(Z * pr.FOOT.get(m, 3.0) * 0.6)
				elif m.begins_with("car_") or m.begins_with("tractor") or m.begins_with("trailer"):
					col = Color(0.85, 0.1, 0.1); rr = int(Z * 1.6)
				elif m.begins_with("fence") or m.begins_with("gate"):
					col = Color(0.4, 0.25, 0.1); rr = 3
				elif m.begins_with("garden"):
					col = Color(0.2, 0.7, 0.2); rr = int(Z * 2.0)
				for dy in range(-rr, rr + 1):
					for dx in range(-rr, rr + 1):
						var ax := px2 + dx
						var ay := py2 + dy
						if ax >= 0 and ay >= 0 and ax < half * 2 * Z and ay < half * 2 * Z:
							im2.set_pixel(ax, ay, col)
			im2.save_png(args[0].replace(".png", "_" + k + ".png"))
	print("chunks ", n, " trees ", total, " avg/chunk ", snappedf(float(total) / n, 0.1), " max ", maxc, " dense(>=8) ", forest_chunks, " (", snappedf(100.0 * forest_chunks / n, 0.1), "%)")
	quit()

func _dot(img: Image, x: float, y: float, R: int, K: int, r: int, c: Color) -> void:
	var cx := int((x + R) * K)
	var cy := int((y + R) * K)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				var px := cx + dx
				var py := cy + dy
				if px >= 0 and py >= 0 and px < R * 2 * K and py < R * 2 * K:
					img.set_pixel(px, py, c)

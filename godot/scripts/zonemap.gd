extends SceneTree
# Карта зон сверху: лес/поле/вода, дороги и их полоса, жилые зоны (улицы с дворами), локации, следы зданий.
# godot --headless --path godot -s res://scripts/zonemap.gd -- <out.png>
const R := 220.0
const PX := 2.0
func _init() -> void:
	WorldGen.init()
	var pr = load("res://scripts/props.gd").new()
	pr._ready()
	var n := int(R * 2.0 * PX)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for j in n:
		for i in n:
			var x := -R + i / PX
			var y := -R + j / PX
			var c := Color(0.62, 0.70, 0.42).lerp(Color(0.18, 0.36, 0.16), clampf(WorldGen.forest_mask(x, y) * 1.5 - 0.2, 0.0, 1.0))
			if WorldGen.water_at(x, y).x > 0.3: c = Color(0.25, 0.45, 0.75)
			var pd := WorldGen.path_dist(x, y)
			if pd < 6.0: c = c.lerp(Color(0.85, 0.82, 0.75), 0.35)      # полоса дороги
			if pd < 1.6: c = Color(0.45, 0.42, 0.38)
			if not WorldGen.in_map(x, y, 0.0): c = c.darkened(0.5)
			img.set_pixel(i, j, c)
	var fill := func(rect: Array, col: Color, a: float) -> void:
		var c0: Vector2 = rect[0]
		var e: float = float(rect[2]) + float(rect[3])
		for yy in range(int((c0.y - e + R) * PX), int((c0.y + e + R) * PX)):
			for xx in range(int((c0.x - e + R) * PX), int((c0.x + e + R) * PX)):
				if xx < 0 or yy < 0 or xx >= n or yy >= n: continue
				var p := Vector2(-R + xx / PX, -R + yy / PX) - c0
				var th: float = rect[1]
				var lx := p.x * cos(th) - p.y * sin(th)
				var ly := p.x * sin(th) + p.y * cos(th)
				if absf(lx) <= float(rect[2]) and absf(ly) <= float(rect[3]):
					img.set_pixel(xx, yy, img.get_pixel(xx, yy).lerp(col, a))
	for z in pr._zones:
		fill.call(z, Color(1.0, 0.75, 0.2) if z[4] == "жильё" else Color(1.0, 0.95, 0.4), 0.35)
	for q in pr._plots:
		fill.call([q[0], q[1], q[2], q[3]], Color(1.0, 0.55, 0.1), 0.25)
	for f in pr._foot:
		fill.call([f[0], f[1], f[2], f[3]], Color(0.1, 0.08, 0.08), 0.85)
	for key in WorldGen.FEATURES:
		var ft: Dictionary = WorldGen.FEATURES[key]
		for k in 90:
			var a := k * TAU / 90.0
			var xx := int((ft.x + cos(a) * ft.r * 1.25 + R) * PX)
			var yy := int((ft.y + sin(a) * ft.r * 1.25 + R) * PX)
			if xx >= 0 and yy >= 0 and xx < n and yy < n: img.set_pixel(xx, yy, Color(0.85, 0.1, 0.1))
	img.save_png(OS.get_cmdline_user_args()[0])
	print("ZONEMAP ok зон ", pr._zones.size(), " участков ", pr._plots.size(), " следов ", pr._foot.size())
	quit()

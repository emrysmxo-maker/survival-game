extends SceneTree
# Картинка карты зон (zones.gd) до построек: лес/поле/вода, дороги, зоны с номерами; в лог — список зон.
# godot --headless --path godot -s res://scripts/zonesplan.gd -- <out.png>
const R := 220.0
const PX := 3.0
const COL := {"локация": Color(0.9, 0.15, 0.15), "деревня": Color(1.0, 0.6, 0.0), "посёлок": Color(1.0, 0.85, 0.1), "дачи": Color(0.95, 0.4, 0.75),
	"хутор": Color(0.85, 0.55, 0.3), "лагерь": Color(0.2, 0.75, 0.95), "кордон": Color(0.55, 0.35, 0.15), "кладбище": Color(0.6, 0.6, 0.65),
	"карьер": Color(0.75, 0.65, 0.45), "мини-город": Color(0.75, 0.3, 1.0), "придорожное": Color(0.1, 0.9, 0.6)}
# цифры 3×5
const DIG := ["111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",
	"111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111"]

func _init() -> void:
	WorldGen.init()
	var zones: Array = load("res://scripts/zones.gd").build(true)
	var n := int(R * 2.0 * PX)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for j in n:
		for i in n:
			var x := -R + i / PX
			var y := -R + j / PX
			var c := Color(0.70, 0.76, 0.55).lerp(Color(0.36, 0.50, 0.32), clampf(WorldGen.forest_mask(x, y) * 1.5 - 0.2, 0.0, 1.0))
			if WorldGen.water_at(x, y).x > 0.3: c = Color(0.35, 0.55, 0.85)
			var pd := WorldGen.path_dist(x, y)
			if pd < 1.6: c = Color(0.3, 0.28, 0.26)
			img.set_pixel(i, j, c)
	var Z = load("res://scripts/zones.gd")
	var idx := 1
	for z in zones:
		var col: Color = COL.get(z.type, Color.WHITE)
		var e: float = z.hl + z.hw
		for yy in range(int((z.c.y - e + R) * PX), int((z.c.y + e + R) * PX)):
			for xx in range(int((z.c.x - e + R) * PX), int((z.c.x + e + R) * PX)):
				if xx < 0 or yy < 0 or xx >= n or yy >= n: continue
				var p := Vector2(-R + xx / PX, -R + yy / PX)
				if Z.inside(z, p):
					var edge: bool = not Z.inside(z, p, 1.0)
					img.set_pixel(xx, yy, col.darkened(0.3) if edge else img.get_pixel(xx, yy).lerp(col, 0.45))
		_num(img, idx, int((z.c.x + R) * PX), int((z.c.y + R) * PX))
		print("№%d %s — %s" % [idx, z.name, z.type])
		idx += 1
	img.save_png(OS.get_cmdline_user_args()[0])
	quit()

func _num(img: Image, v: int, cx: int, cy: int) -> void:
	var s := str(v)
	var k := 4
	var w := s.length() * 4 * k
	var x0 := cx - w / 2
	var y0 := cy - 5 * k / 2
	img.fill_rect(Rect2i(x0 - k, y0 - k, w + k, 7 * k), Color.WHITE)
	for ci in s.length():
		var g: String = DIG[int(s[ci])]
		for r in 5:
			for q in 3:
				if g[r * 3 + q] == "1":
					img.fill_rect(Rect2i(x0 + ci * 4 * k + q * k, y0 + r * k, k, k), Color.BLACK)

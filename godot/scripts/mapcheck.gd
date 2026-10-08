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

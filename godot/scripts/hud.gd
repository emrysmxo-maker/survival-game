extends CanvasLayer
# Интерфейс: экосистема/координаты/деревья, версия и fps, мини-карта (тап — большая
# карта с 5 локациями), телепорт 📍, «ЗОМБИ +», «АВТО ОГОНЬ», время суток с паузой.

const VERSION := "G0.3"
var main
var info: Label
var ver: Label
var mini: TextureRect
var big: Control
var big_tex: TextureRect
var time_lbl: Label
var slider: HSlider
var pause_btn: Button
var auto_btn: Button
var zombie_btn: Button
var tp_btn: Button
var tp_panel: VBoxContainer
var _mini_img: Image
var _mini_tex: ImageTexture
var _mini_t := 0.0
var _mini_task := -1
var _mini_at := Vector2.ZERO
var _big_task := -1
var _big_img: Image
var _slider_lock := false

const MINI_R := 42.0
const MINI_N := 84
const BIG_N := 300

func _ready() -> void:
	var font_col := Color(0.92, 0.95, 0.9)
	var panel := PanelContainer.new()
	panel.position = Vector2(10, 8)
	panel.add_theme_stylebox_override("panel", _box(Color(0.06, 0.09, 0.06, 0.78)))
	add_child(panel)
	info = Label.new()
	info.add_theme_font_size_override("font_size", 15)
	info.add_theme_color_override("font_color", font_col)
	panel.add_child(info)
	ver = Label.new()
	ver.position = Vector2(12, 92)
	ver.add_theme_font_size_override("font_size", 13)
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	add_child(ver)

	tp_btn = _button("📍", Vector2(10, 116), Vector2(46, 46), Color(0.06, 0.09, 0.06, 0.8))
	tp_btn.pressed.connect(func(): tp_panel.visible = not tp_panel.visible)
	tp_panel = VBoxContainer.new()
	tp_panel.position = Vector2(62, 116)
	tp_panel.visible = false
	add_child(tp_panel)
	for key in WorldGen.LANDMARKS:
		var f: Dictionary = WorldGen.FEATURES[key]
		var b := _button(f.name, Vector2.ZERO, Vector2(190, 38), Color(0.06, 0.09, 0.06, 0.9))
		b.reparent(tp_panel)
		b.pressed.connect(func():
			main.teleport(Vector2(f.x + 4.0, f.y + 4.0))
			tp_panel.visible = false)

	mini = TextureRect.new()
	mini.size = Vector2(150, 150)
	mini.stretch_mode = TextureRect.STRETCH_SCALE
	mini.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var mm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item; void fragment(){ vec4 c = texture(TEXTURE, UV); float d = length(UV - vec2(0.5)); c.a *= smoothstep(0.5, 0.48, d); if (d > 0.47 && d < 0.5) c = vec4(0.85,0.85,0.8,1.0); COLOR = c; }"
	mm.shader = sh
	mini.material = mm
	mini.gui_input.connect(func(e):
		if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed):
			_open_big())
	add_child(mini)
	mini.draw.connect(_draw_mini)
	_mini_img = Image.create(MINI_N, MINI_N, false, Image.FORMAT_RGB8)
	_mini_tex = ImageTexture.create_from_image(_mini_img)
	mini.texture = _mini_tex

	big = Control.new()
	big.visible = false
	big.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed):
			big.visible = false)
	big.add_child(dim)
	big_tex = TextureRect.new()
	big_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	big_tex.stretch_mode = TextureRect.STRETCH_SCALE
	big_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big.add_child(big_tex)
	big.draw.connect(_draw_big_marks)
	add_child(big)

	zombie_btn = _button("ЗОМБИ +", Vector2.ZERO, Vector2(120, 46), Color(0.7, 0.15, 0.12, 0.92))
	zombie_btn.pressed.connect(func(): main.zombies.spawn())
	auto_btn = _button("АВТО\nОГОНЬ", Vector2.ZERO, Vector2(96, 96), Color(0.18, 0.24, 0.18, 0.85))
	auto_btn.pressed.connect(func():
		main.weapon.auto = not main.weapon.auto
		_style(auto_btn, Color(0.75, 0.45, 0.1, 0.92) if main.weapon.auto else Color(0.18, 0.24, 0.18, 0.85)))
	var tbox := PanelContainer.new()
	tbox.add_theme_stylebox_override("panel", _box(Color(0.06, 0.09, 0.06, 0.8)))
	tbox.name = "TimeBox"
	add_child(tbox)
	var hb := HBoxContainer.new()
	tbox.add_child(hb)
	time_lbl = Label.new()
	time_lbl.add_theme_font_size_override("font_size", 16)
	time_lbl.custom_minimum_size = Vector2(56, 0)
	hb.add_child(time_lbl)
	slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 24.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(220, 30)
	slider.value_changed.connect(func(v):
		if not _slider_lock:
			main.daynight.t = v)
	hb.add_child(slider)
	pause_btn = _button("II", Vector2.ZERO, Vector2(40, 32), Color(0.85, 0.5, 0.1, 0.95))
	pause_btn.reparent(hb)
	pause_btn.pressed.connect(func():
		main.daynight.auto = not main.daynight.auto
		pause_btn.text = "II" if main.daynight.auto else "▶")
	get_viewport().size_changed.connect(_layout)
	_layout()

func _box(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(10)
	s.content_margin_left = 10; s.content_margin_right = 10; s.content_margin_top = 6; s.content_margin_bottom = 6
	return s

func _style(b: Button, c: Color) -> void:
	for st in ["normal", "hover", "pressed", "focus"]:
		var s := _box(c)
		s.set_corner_radius_all(int(minf(b.size.x, b.size.y) / 2.0) if b.size.x == b.size.y else 12)
		b.add_theme_stylebox_override(st, s)

func _button(text: String, pos: Vector2, sz: Vector2, c: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = sz
	b.custom_minimum_size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	add_child(b)
	_style(b, c)
	return b

func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	mini.position = Vector2(vs.x - 160, 8)
	zombie_btn.position = Vector2(12, vs.y - 58)
	auto_btn.position = Vector2(vs.x - 112, vs.y - 112)
	var tb: Control = get_node("TimeBox")
	tb.position = Vector2(vs.x / 2.0 - 170, vs.y - 50)
	var s := minf(vs.y - 40, vs.x - 40)
	big_tex.size = Vector2(s, s)
	big_tex.position = (vs - big_tex.size) / 2.0

# кнопки, на которых стики не начинаются
func ui_rects() -> Array:
	var out := []
	for c in [mini, zombie_btn, auto_btn, tp_btn, get_node("TimeBox")]:
		out.append(func(): return c.get_global_rect() if c.visible else Rect2())
	out.append(func(): return tp_panel.get_global_rect() if tp_panel.visible else Rect2())
	out.append(func(): return get_viewport().get_visible_rect() if big.visible else Rect2())
	return out

func update_hud(dt: float, tile: Vector2, eco: String, trees: int) -> void:
	info.text = "Экосистема: %s\nКоординаты: X: %d, Y: %d\nДеревьев рядом: %d" % [eco, roundi(tile.x), roundi(tile.y), trees]
	ver.text = "%s · %d fps · %dx%d" % [VERSION, Engine.get_frames_per_second(), get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	time_lbl.text = main.daynight.label()
	_slider_lock = true
	slider.value = main.daynight.t
	_slider_lock = false
	_mini_t -= dt
	if _mini_task >= 0 and WorkerThreadPool.is_task_completed(_mini_task):
		WorkerThreadPool.wait_for_task_completion(_mini_task)
		_mini_task = -1
		_mini_tex.update(_mini_img)
	if _mini_t <= 0.0 and _mini_task < 0:
		_mini_t = 1.0
		_mini_at = tile
		_mini_task = WorkerThreadPool.add_task(_build_mini.bind(tile))
	if _big_task >= 0 and WorkerThreadPool.is_task_completed(_big_task):
		WorkerThreadPool.wait_for_task_completion(_big_task)
		_big_task = -1
		big_tex.texture = ImageTexture.create_from_image(_big_img)
	mini.queue_redraw()
	if big.visible:
		big.queue_redraw()

static func terrain_color(x: float, y: float) -> Color:
	var t := WorldGen.terrain(x, y)
	if t[1] > 0.3:
		return Color(0.25, 0.42, 0.55)
	var L := WorldGen.ground_layers(x, y)
	var c := Color(0.29, 0.40, 0.22)
	c = c.lerp(Color(0.40, 0.47, 0.27), L[5] * 0.8)
	c = c.lerp(Color(0.22, 0.28, 0.20), L[1])
	c = c.lerp(Color(0.55, 0.55, 0.52), L[3])
	c = c.lerp(Color(0.62, 0.53, 0.36), L[2] * 0.7)
	c = c.lerp(Color(0.80, 0.68, 0.45), L[0])
	var sh := clampf(t[0] * 0.04, -0.15, 0.15)
	return c.lightened(sh) if sh > 0.0 else c.darkened(-sh)

func _build_mini(at: Vector2) -> void:
	for j in MINI_N:
		for i in MINI_N:
			# карта в осях экрана (ромб): вправо по экрану = (+x, -y)
			var sx := (i - MINI_N / 2.0) / (MINI_N / 2.0) * MINI_R
			var sy := (j - MINI_N / 2.0) / (MINI_N / 2.0) * MINI_R
			var tx := at.x + (sx + sy) / 1.414
			var ty := at.y + (sy - sx) / 1.414
			_mini_img.set_pixel(i, j, terrain_color(tx, ty))

func _open_big() -> void:
	big.visible = true
	if _big_img == null and _big_task < 0:
		_big_img = Image.create(BIG_N, BIG_N, false, Image.FORMAT_RGB8)
		_big_task = WorkerThreadPool.add_task(_build_big)

func _build_big() -> void:
	var R := WorldGen.MAP_RADIUS
	for j in BIG_N:
		for i in BIG_N:
			var x := (i / float(BIG_N) * 2.0 - 1.0) * R
			var y := (j / float(BIG_N) * 2.0 - 1.0) * R
			_big_img.set_pixel(i, j, terrain_color(x, y))

func _draw_big_marks() -> void:
	if not big.visible:
		return
	var r := big_tex.get_rect()
	var R := WorldGen.MAP_RADIUS
	var font := ThemeDB.fallback_font
	for key in WorldGen.LANDMARKS:
		var f: Dictionary = WorldGen.FEATURES[key]
		var p := r.position + Vector2((f.x / R + 1.0) / 2.0, (f.y / R + 1.0) / 2.0) * r.size
		big.draw_circle(p, 6, Color(0.95, 0.77, 0.06))
		big.draw_string(font, p + Vector2(-50, -10), f.name, HORIZONTAL_ALIGNMENT_CENTER, 100, 14, Color.WHITE)
	var pt: Vector2 = main.player.tile
	var pp := r.position + Vector2((pt.x / R + 1.0) / 2.0, (pt.y / R + 1.0) / 2.0) * r.size
	big.draw_circle(pp, 7, Color(1, 0.2, 0.2))

func _draw_mini() -> void:
	var c := mini.size / 2.0
	var k := (mini.size.x / 2.0) / MINI_R
	var off: Vector2 = main.player.tile - _mini_at        # карта считается раз в секунду — сдвиг до бойца
	var to_px := func(d: Vector2) -> Vector2: return c + Vector2(d.x - d.y, d.x + d.y) / 1.414 * k
	if main.zombies:
		for z in main.zombies.list:
			if not z.dead:
				var p: Vector2 = to_px.call(z.tile - _mini_at)
				if p.distance_to(c) < c.x - 4:
					mini.draw_circle(p, 3.5, Color(0.9, 0.2, 0.15))
	var pp: Vector2 = to_px.call(off)
	var a: float = main.player.yaw
	# yaw (Godot) -> направление на экране
	var d3 := Vector2(sin(a), cos(a))
	var dir: Vector2 = Vector2(d3.x - d3.y, d3.x + d3.y).normalized()
	var n := Vector2(-dir.y, dir.x)
	mini.draw_colored_polygon(PackedVector2Array([pp + dir * 8, pp - dir * 5 + n * 5, pp - dir * 5 - n * 5]), Color.WHITE)

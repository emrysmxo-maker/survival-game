extends CanvasLayer
# Интерфейс: экосистема/координаты/деревья, версия и fps, мини-карта (тап — большая
# карта с локациями), перелёт камеры 📍 к локации, время суток с паузой.

const VERSION := "G0.14"
var fps_btn: Button
var snd_btn: Button
var _ft: Array = []
var _ft_sum := 0.0
var main
var info: Label
var ver: Label
var mini: TextureRect
var big: Control
var big_tex: TextureRect
var time_lbl: Label
var slider: HSlider
var pause_btn: Button
var tp_btn: Button
var gear_btn: Button
var toast_lbl: Label
var _toast_t := 0.0
var q_panel: VBoxContainer
var q_btns: Array = []
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

	gear_btn = _button("⚙", Vector2(10, 168), Vector2(46, 46), Color(0.06, 0.09, 0.06, 0.8))
	gear_btn.pressed.connect(func(): q_panel.visible = not q_panel.visible)
	q_panel = VBoxContainer.new()
	q_panel.position = Vector2(62, 168)
	q_panel.visible = false
	add_child(q_panel)
	var qt := Label.new()
	qt.text = "Качество графики"
	qt.add_theme_font_size_override("font_size", 15)
	q_panel.add_child(qt)
	var ub := _button("⟳ Обновления", Vector2.ZERO, Vector2(190, 40), Color(0.18, 0.3, 0.2, 0.95))
	ub.reparent(q_panel)
	ub.pressed.connect(func():
		Engine.set_meta("from_game", true)
		get_tree().change_scene_to_file("res://boot.tscn"))
	var ib := _button("▶ Заставка", Vector2.ZERO, Vector2(190, 40), Color(0.25, 0.12, 0.1, 0.95))
	ib.reparent(q_panel)
	ib.pressed.connect(func():
		q_panel.visible = false
		main.start_intro())
	fps_btn = _button("", Vector2.ZERO, Vector2(190, 40), Color(0.12, 0.12, 0.2, 0.95))
	fps_btn.reparent(q_panel)
	fps_btn.pressed.connect(func():
		main.settings.set_fps_max(not main.settings.fps_max)
		_refresh_q())
	snd_btn = _button("", Vector2.ZERO, Vector2(190, 40), Color(0.12, 0.12, 0.2, 0.95))
	snd_btn.reparent(q_panel)
	snd_btn.pressed.connect(func():
		main.settings.set_sound(not main.settings.sound)
		_refresh_q())
	for i in 4:
		var qb := _button("", Vector2.ZERO, Vector2(190, 40), Color(0.06, 0.09, 0.06, 0.9))
		qb.reparent(q_panel)
		q_btns.append(qb)
		qb.pressed.connect(func():
			main.settings.apply(i)
			_refresh_q())
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
			main.teleport(Vector2(f.x, f.y))
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
	dim.show_behind_parent = true       # подписи карты (рисует big) — поверх картинки
	big_tex.show_behind_parent = true
	big.draw.connect(_draw_big_marks)
	add_child(big)

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
	toast_lbl = Label.new()
	toast_lbl.add_theme_font_size_override("font_size", 20)
	toast_lbl.add_theme_color_override("font_color", Color(1.0, 0.93, 0.7))
	toast_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	toast_lbl.add_theme_constant_override("outline_size", 6)
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_lbl)
	get_viewport().size_changed.connect(_layout)
	_layout()

func toast(t: String) -> void:
	toast_lbl.text = t
	_toast_t = 2.8

func _process(dt: float) -> void:
	# fps за последние 5 с: среднее и худшее (по самому долгому кадру)
	_ft.append(dt)
	_ft_sum += dt
	while _ft_sum > 5.0 and _ft.size() > 1:
		_ft_sum -= _ft.pop_front()
	_toast_t -= dt
	toast_lbl.modulate.a = clampf(_toast_t / 0.6, 0.0, 1.0)

func _refresh_q() -> void:
	if fps_btn:
		fps_btn.text = "Кадры: максимум" if main.settings.fps_max else "Кадры: 60"
	if snd_btn:
		snd_btn.text = "Звук: вкл" if main.settings.sound else "Звук: выкл"
	for i in q_btns.size():
		q_btns[i].text = ("● " if main.settings.level == i else "   ") + main.settings.NAMES[i]

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
	toast_lbl.position = Vector2(vs.x / 2.0 - 300, 64)
	toast_lbl.size = Vector2(600, 30)
	var tb: Control = get_node("TimeBox")
	tb.position = Vector2(vs.x / 2.0 - 170, vs.y - 50)
	var s := minf(vs.y - 40, vs.x - 40)
	big_tex.size = Vector2(s, s)
	big_tex.position = (vs - big_tex.size) / 2.0

# кнопки и панели, на которых палец не двигает камеру
func ui_rects() -> Array:
	var out := []
	for c in [mini, tp_btn, gear_btn, get_node("TimeBox")]:
		out.append(func(): return c.get_global_rect() if c.visible else Rect2())
	out.append(func(): return tp_panel.get_global_rect() if tp_panel.visible else Rect2())
	out.append(func(): return q_panel.get_global_rect() if q_panel.visible else Rect2())
	out.append(func(): return get_viewport().get_visible_rect() if big.visible else Rect2())
	return out

var _hud_t := 0.0
# true раз в 0.25 с: подписи и карта обновляются редко (не каждый кадр)
func due(dt: float) -> bool:
	_hud_t -= dt
	if _hud_t > 0.0:
		return false
	_hud_t = 0.25
	return true

func update_hud(dt: float, tile: Vector2, eco: String, trees: int) -> void:
	info.text = "Экосистема: %s\nКоординаты: X: %d, Y: %d\nДеревьев рядом: %d" % [eco, roundi(tile.x), roundi(tile.y), trees]
	var worst := 0.0
	for f in _ft:
		worst = maxf(worst, f)
	var avg := float(_ft.size()) / maxf(_ft_sum, 0.001)
	ver.text = "%s · %d fps (ср %d, мин %d) · %dx%d" % [VERSION, Engine.get_frames_per_second(), roundi(avg), roundi(1.0 / maxf(worst, 0.001)), get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	time_lbl.text = main.daynight.label()
	_slider_lock = true
	slider.value = main.daynight.t
	_slider_lock = false
	_mini_t -= dt
	if _mini_task >= 0 and WorkerThreadPool.is_task_completed(_mini_task):
		WorkerThreadPool.wait_for_task_completion(_mini_task)
		_mini_task = -1
		_mini_tex.update(_mini_img)
	# пересчёт миникарты — только когда камера ушла на 3+ тайла (или раз в 5 с), а не каждую секунду
	if _mini_t <= 0.0 and _mini_task < 0 and (tile.distance_to(_mini_at) > 3.0 or _mini_t < -4.0 or _mini_tex == null):
		_mini_t = 0.5
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
	var L := WorldGen.ground_layers_t(x, y, t)     # рельеф уже посчитан — не считать второй раз
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
	var seen := {}
	for z in WorldGen.ZONES:          # зоны — серым, мелко
		if seen.has(z.name):
			continue
		seen[z.name] = true
		var zp := r.position + Vector2((z.x / R + 1.0) / 2.0, (z.y / R + 1.0) / 2.0) * r.size
		big.draw_string(font, zp + Vector2(-70, 4), z.name, HORIZONTAL_ALIGNMENT_CENTER, 140, 12, Color(1, 1, 1, 0.55))
	for key in WorldGen.LANDMARKS:
		var f: Dictionary = WorldGen.FEATURES[key]
		var p := r.position + Vector2((f.x / R + 1.0) / 2.0, (f.y / R + 1.0) / 2.0) * r.size
		big.draw_circle(p, 6, Color(0.95, 0.77, 0.06))
		big.draw_string(font, p + Vector2(-110, -10), f.name, HORIZONTAL_ALIGNMENT_CENTER, 220, 15, Color.WHITE)
	var pt: Vector2 = main.focus
	var pp := r.position + Vector2((pt.x / R + 1.0) / 2.0, (pt.y / R + 1.0) / 2.0) * r.size
	big.draw_circle(pp, 7, Color(1, 0.2, 0.2))

func _draw_mini() -> void:
	var c := mini.size / 2.0
	var k := (mini.size.x / 2.0) / MINI_R
	var off: Vector2 = main.focus - _mini_at        # карта считается не каждый кадр — сдвиг до точки обзора
	var to_px := func(d: Vector2) -> Vector2: return c + Vector2(d.x - d.y, d.x + d.y) / 1.414 * k
	var pp: Vector2 = to_px.call(off)
	# куда смотрит камера (вперёд по земле): yaw камеры + 180° в осях «yaw бойца»
	var a: float = deg_to_rad(main.cam_yaw) + PI
	var d3 := Vector2(sin(a), cos(a))
	var dir: Vector2 = Vector2(d3.x - d3.y, d3.x + d3.y).normalized()
	var n := Vector2(-dir.y, dir.x)
	mini.draw_colored_polygon(PackedVector2Array([pp + dir * 8, pp - dir * 5 + n * 5, pp - dir * 5 - n * 5]), Color.WHITE)

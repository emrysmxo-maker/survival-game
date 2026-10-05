extends Control
# Правая половина экрана разделена (как в PUBG): ВЕРХНЯЯ часть — свайп пальцем вращает камеру
# (вправо/влево — на 360°, вверх/вниз — наклон), НИЖНЯЯ — стик прицела (joystick.gd).
# Тут же кнопки «−»/«+» (приближение) и большая кнопка «ОГОНЬ» (держать — стрелять).
var zoom := 0.0            # -1 приближение / +1 отдаление (кнопки)
var fire_held := false
var blocked_rects: Array = []
var _cam_finger := -1
var _zfinger := -1
var _ffinger := -1
var _t0 := 0.0
var _moved := 0.0
const SPLIT := 0.5         # доля высоты: выше — камера, ниже — прицел
signal reset_view
signal swiped(delta: Vector2)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(queue_redraw)

func _vs() -> Vector2:
	return get_viewport().get_visible_rect().size

func zoom_rect(dir: int) -> Rect2:
	var vs := _vs()
	return Rect2(Vector2(vs.x - 128.0 + (dir + 1) * 32.0, vs.y * SPLIT - 70.0), Vector2(56, 56))

func fire_rect() -> Rect2:
	var vs := _vs()
	return Rect2(Vector2(vs.x - 290.0, vs.y - 170.0), Vector2(120, 120))

func rect() -> Rect2:
	return zoom_rect(-1).merge(zoom_rect(1)).merge(fire_rect())

func _cam_zone(p: Vector2) -> bool:
	var vs := _vs()
	return p.x >= vs.x * 0.5 and p.y < vs.y * SPLIT

func _input(e: InputEvent) -> void:
	var vs := _vs()
	if e is InputEventScreenTouch:
		if e.pressed:
			if _zfinger == -1:
				for dir in [-1, 1]:
					if zoom_rect(dir).has_point(e.position):
						_zfinger = e.index
						zoom = -1.0 if dir > 0 else 1.0
						queue_redraw()
						get_viewport().set_input_as_handled()
						return
			if _ffinger == -1 and fire_rect().grow(8).has_point(e.position):
				_ffinger = e.index
				fire_held = true
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
			if _cam_finger == -1 and _cam_zone(e.position):
				for r in blocked_rects:
					if r.call().has_point(e.position):
						return
				_cam_finger = e.index
				_t0 = Time.get_ticks_msec() / 1000.0
				_moved = 0.0
				get_viewport().set_input_as_handled()
		else:
			if e.index == _zfinger:
				_zfinger = -1
				zoom = 0.0
				queue_redraw()
			elif e.index == _ffinger:
				_ffinger = -1
				fire_held = false
				queue_redraw()
			elif e.index == _cam_finger:
				if _moved < 12.0 and Time.get_ticks_msec() / 1000.0 - _t0 < 0.25:
					reset_view.emit()
				_cam_finger = -1
	elif e is InputEventScreenDrag and e.index == _cam_finger:
		_moved += e.relative.length()
		swiped.emit(e.relative)

func _draw() -> void:
	var vs := _vs()
	# линия раздела: сверху — камера, снизу — прицел
	draw_line(Vector2(vs.x * 0.5 + 20.0, vs.y * SPLIT), Vector2(vs.x - 20.0, vs.y * SPLIT), Color(1, 1, 1, 0.07), 1.5)
	for dir in [-1, 1]:
		var r := zoom_rect(dir)
		draw_rect(r, Color(0, 0, 0, 0.4 if zoom != 0.0 and (zoom < 0.0) == (dir > 0) else 0.3), true)
		draw_rect(r, Color(1, 1, 1, 0.4), false, 2.0)
		var cc := r.get_center()
		draw_line(cc - Vector2(11, 0), cc + Vector2(11, 0), Color(1, 1, 1, 0.85), 3.0)
		if dir > 0:
			draw_line(cc - Vector2(0, 11), cc + Vector2(0, 11), Color(1, 1, 1, 0.85), 3.0)
	var fr := fire_rect()
	var c := fr.get_center()
	draw_circle(c, 58.0, Color(0.75, 0.15, 0.1, 0.6 if fire_held else 0.35))
	draw_arc(c, 58.0, 0, TAU, 40, Color(1, 1, 1, 0.55), 3.0)
	draw_circle(c, 9.0, Color(1, 1, 1, 0.8))
	draw_arc(c, 24.0, 0, TAU, 28, Color(1, 1, 1, 0.7), 2.5)
	for a in 4:
		var d := Vector2.from_angle(a * PI / 2.0)
		draw_line(c + d * 24.0, c + d * 38.0, Color(1, 1, 1, 0.7), 2.5)

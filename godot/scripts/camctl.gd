extends Control
# Свободная камера пальцами: один палец — тащить карту; два пальца — сводить/разводить (приближение),
# крутить (поворот вокруг вертикали), вместе вверх/вниз (наклон). Кнопки «−»/«+» — приближение.
# На ПК: левая кнопка мыши — тащить, колесо — приближение, правая кнопка — поворот/наклон.
var zoom := 0.0            # -1 приближение / +1 отдаление (кнопки)
var blocked_rects: Array = []
var _touch := {}           # палец -> позиция
var _zfinger := -1
var _mouse_l := false
var _mouse_r := false
signal panned(delta: Vector2)
signal pinched(k: float)
signal twisted(angle: float)
signal tilted(dy: float)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(queue_redraw)

func _vs() -> Vector2:
	return get_viewport().get_visible_rect().size

func zoom_rect(dir: int) -> Rect2:
	var vs := _vs()
	return Rect2(Vector2(vs.x - 128.0 + (dir + 1) * 32.0, vs.y * 0.5 - 70.0), Vector2(56, 56))

func _blocked(p: Vector2) -> bool:
	for r in blocked_rects:
		if r.call().has_point(p):
			return true
	return false

func _input(e: InputEvent) -> void:
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
			if _blocked(e.position):
				return
			_touch[e.index] = e.position
			get_viewport().set_input_as_handled()
		else:
			if e.index == _zfinger:
				_zfinger = -1
				zoom = 0.0
				queue_redraw()
			_touch.erase(e.index)
	elif e is InputEventScreenDrag and _touch.has(e.index):
		if _touch.size() == 1:
			panned.emit(e.relative)
		else:
			# два пальца: этот и другой (первый попавшийся)
			var other := -1
			for k in _touch:
				if k != e.index:
					other = k
					break
			var o: Vector2 = _touch[other]
			var a0: Vector2 = _touch[e.index]
			var a1: Vector2 = e.position
			var d0 := a0 - o
			var d1 := a1 - o
			if d0.length() > 20.0 and d1.length() > 20.0:
				pinched.emit(d1.length() / d0.length())
				twisted.emit(d0.angle_to(d1))
			tilted.emit(e.relative.y * 0.5)
		_touch[e.index] = e.position
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_mouse_l = e.pressed and not _blocked(e.position)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_r = e.pressed
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			pinched.emit(1.1)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			pinched.emit(1.0 / 1.1)
	elif e is InputEventMouseMotion:
		if _mouse_l:
			panned.emit(e.relative)
		elif _mouse_r:
			twisted.emit(-e.relative.x * 0.005)
			tilted.emit(e.relative.y)

func _draw() -> void:
	for dir in [-1, 1]:
		var r := zoom_rect(dir)
		draw_rect(r, Color(0, 0, 0, 0.4 if zoom != 0.0 and (zoom < 0.0) == (dir > 0) else 0.3), true)
		draw_rect(r, Color(1, 1, 1, 0.4), false, 2.0)
		var cc := r.get_center()
		draw_line(cc - Vector2(11, 0), cc + Vector2(11, 0), Color(1, 1, 1, 0.85), 3.0)
		if dir > 0:
			draw_line(cc - Vector2(0, 11), cc + Vector2(0, 11), Color(1, 1, 1, 0.85), 3.0)

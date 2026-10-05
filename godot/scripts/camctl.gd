extends Control
# Джойстик камеры (справа по центру): тяни влево/вправо — камера вращается на все 360°,
# вверх — приближение, вниз — отдаление. Быстрое касание без движения — вернуть вид.
var vec := Vector2.ZERO
var active := false
var _finger := -1
var _t0 := 0.0
var _moved := false
var center := Vector2.ZERO
const RADIUS := 62.0
signal reset_view

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	center = Vector2(vs.x - 88.0, vs.y * 0.5 - 6.0)
	queue_redraw()

func rect() -> Rect2:
	return Rect2(center - Vector2(RADIUS, RADIUS) * 1.25, Vector2(RADIUS, RADIUS) * 2.5)

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and _finger == -1 and rect().has_point(e.position):
			_finger = e.index
			active = true
			_moved = false
			_t0 = Time.get_ticks_msec() / 1000.0
			_upd(e.position)
			get_viewport().set_input_as_handled()
		elif not e.pressed and e.index == _finger:
			if not _moved and Time.get_ticks_msec() / 1000.0 - _t0 < 0.3:
				reset_view.emit()
			_finger = -1
			active = false
			vec = Vector2.ZERO
			queue_redraw()
	elif e is InputEventScreenDrag and e.index == _finger:
		_upd(e.position)

func _upd(pos: Vector2) -> void:
	var d := pos - center
	if d.length() > RADIUS:
		d = d.normalized() * RADIUS
	vec = d / RADIUS
	if vec.length() > 0.2:
		_moved = true
	queue_redraw()

func _draw() -> void:
	var a := 0.55 if active else 0.32
	draw_circle(center, RADIUS, Color(0, 0, 0, 0.28))
	draw_arc(center, RADIUS, 0, TAU, 40, Color(1, 1, 1, a), 2.5)
	var c := Color(1, 1, 1, a + 0.15)
	# стрелки: ◄ ► вращение, ▲ приближение, ▼ отдаление
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var tip: Vector2 = center + dir * (RADIUS - 11)
		var n := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * 12 + n * 7, tip - dir * 12 - n * 7]), c)
	draw_arc(center, 15, 0.4, 5.9, 20, c, 2.0)               # значок вращения
	draw_circle(center + vec * RADIUS * 0.8, 17.0, Color(1, 1, 1, 0.5 if active else 0.28))

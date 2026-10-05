extends Control
# Плавающий стик: появляется под пальцем в своей половине экрана (left/right).
# vec — от -1 до 1 (x вправо, y вниз), как на экране; len_px — насколько оттянут.

@export var right_side := false
var vec := Vector2.ZERO
var active := false
var len_px := 0.0
var _center := Vector2.ZERO
var _finger := -1
var blocked_rects: Array = []      # кнопки, на которых стик не начинается
const RADIUS := 90.0
const DEAD := 0.12

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _mine(x: float) -> bool:
	var half := get_viewport_rect().size.x * 0.5
	return x >= half if right_side else x < half

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and _finger == -1 and _mine(e.position.x) and (not right_side or e.position.y >= get_viewport_rect().size.y * 0.5):
			for r in blocked_rects:
				if r.call().has_point(e.position):
					return
			_finger = e.index
			_center = e.position
			active = true
			vec = Vector2.ZERO
			len_px = 0.0
		elif not e.pressed and e.index == _finger:
			_finger = -1
			active = false
			vec = Vector2.ZERO
			len_px = 0.0
		queue_redraw()
	elif e is InputEventScreenDrag and e.index == _finger:
		var d: Vector2 = e.position - _center
		var l := d.length()
		if l > RADIUS:
			_center += d.normalized() * (l - RADIUS)   # стик «тянется» за пальцем
			d = d.normalized() * RADIUS
			l = RADIUS
		len_px = l
		vec = d / RADIUS
		if not right_side and vec.length() < DEAD:
			vec = Vector2.ZERO
		queue_redraw()

func _draw() -> void:
	if not active:
		return
	var col := Color(1, 0.55, 0.35, 0.35) if right_side else Color(1, 1, 1, 0.35)
	draw_circle(_center, RADIUS, Color(1, 1, 1, 0.08))
	draw_arc(_center, RADIUS, 0, TAU, 48, col, 3.0)
	if right_side:
		draw_arc(_center, 18.0, 0, TAU, 24, Color(1, 1, 1, 0.25), 2.0)
	draw_circle(_center + vec * RADIUS, 34.0, Color(1, 1, 1, 0.42))

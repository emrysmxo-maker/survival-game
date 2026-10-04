extends Control
# Плавающий джойстик: появляется под пальцем в своей половине экрана.
# vec — вектор от -1 до 1 (x вправо, y вниз), как на экране.

var vec := Vector2.ZERO
var active := false
var _center := Vector2.ZERO
var _finger := -1
const RADIUS := 90.0
const DEAD := 0.12

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and _finger == -1 and e.position.x < get_viewport_rect().size.x * 0.5:
			_finger = e.index
			_center = e.position
			active = true
			vec = Vector2.ZERO
		elif not e.pressed and e.index == _finger:
			_finger = -1
			active = false
			vec = Vector2.ZERO
		queue_redraw()
	elif e is InputEventScreenDrag and e.index == _finger:
		var d: Vector2 = e.position - _center
		var l := d.length()
		if l > RADIUS:
			_center += d.normalized() * (l - RADIUS)   # стик «тянется» за пальцем
			d = d.normalized() * RADIUS
		vec = d / RADIUS
		if vec.length() < DEAD:
			vec = Vector2.ZERO
		queue_redraw()

func _draw() -> void:
	if not active:
		return
	draw_circle(_center, RADIUS, Color(1, 1, 1, 0.10))
	draw_arc(_center, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
	draw_circle(_center + vec * RADIUS, 34.0, Color(1, 1, 1, 0.45))

extends CPUParticles3D
# Листья по ветру: у точки камеры (потом — у игрока) ветер несёт осенние листья низко над землёй — больше в порывы,
# в лесу и под деревьями, меньше в поле; ночью и при отдалении камеры (cam_size > 30) не рисуются.
var main
var _t := 0.0
var _scan := 0.0
var _forest := 0.0
const T := WorldGen.T

func _ready() -> void:
	amount = 70
	lifetime = 6.0
	local_coords = false
	emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emission_box_extents = Vector3(22.0, 1.2, 16.0)
	direction = Vector3(1.0, 0.25, 0.35)
	spread = 25.0
	initial_velocity_min = 1.5
	initial_velocity_max = 3.5
	gravity = Vector3(0.6, -0.35, 0.2)                    # ветер вдоль и медленное падение
	angular_velocity_min = -220.0
	angular_velocity_max = 220.0
	damping_min = 0.2
	damping_max = 0.5
	scale_amount_min = 0.7
	scale_amount_max = 1.3
	var g := Gradient.new()                               # жёлтые, рыжие, бурые
	g.set_color(0, Color(0.85, 0.62, 0.16))
	g.add_point(0.5, Color(0.72, 0.36, 0.1))
	g.set_color(1, Color(0.45, 0.3, 0.14))
	color_initial_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.12)                         # крупнее настоящих — чтобы читались сверху
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true                   # с освещением: без него цвет высветляется до белых точек
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	q.material = m
	mesh = q
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitting = false

func _process(dt: float) -> void:
	_t += dt
	var day: float = 1.0 - main.daynight.night
	var near: bool = main.cam_size < 30.0
	_scan -= dt
	if _scan <= 0.0:
		_scan = 1.0
		_forest = WorldGen.tree_density(main.focus.x, main.focus.y)
	var gust := 0.5 + 0.5 * sin(_t * 0.23) * sin(_t * 0.071 + 1.3)
	var k := day * gust * (0.25 + 0.75 * _forest)
	emitting = near and k > 0.12
	if emitting:
		speed_scale = 0.6 + gust
		var f: Vector2 = main.focus
		global_position = Vector3(f.x * T, main.cam_h + 1.5, f.y * T)

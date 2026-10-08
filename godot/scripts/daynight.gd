extends Node
# День и ночь: сутки = 30 реальных минут (15 день, 15 ночь), ползунок времени
# и пауза — в HUD. Солнце идёт по небу (тени длинные утром и вечером), ночью —
# слабый лунный свет. Перенос src/daynight.js.

const DAY_REAL_MIN := 30.0
var t := 10.0          # часы 0..24
var auto := true
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var night := 0.0       # 0 день .. 1 ночь (окна, костёр)
var cloud := 0.0       # облачность 0..1 (weather.gd): солнце слабее, тени мягче

const C_DAY := Color(1.0, 0.98, 0.94)
const C_GOLD := Color(1.0, 0.77, 0.55)
const C_NIGHT := Color(0.28, 0.35, 0.56)

func setup(root: Node3D) -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	root.add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 24.0
	sun.shadow_blur = 1.2
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 0.4
	root.add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.shadow_enabled = false
	moon.rotation_degrees = Vector3(-60, 120, 0)
	root.add_child(moon)
	apply()

static func elevation(h: float) -> float:
	return sin(PI * (h - 6.0) / 12.0)

func _process(dt: float) -> void:
	if auto:
		t = fmod(t + dt * 24.0 / (DAY_REAL_MIN * 60.0), 24.0)
	apply()

func apply() -> void:
	var e := elevation(t)
	# азимут: утром солнце слева экрана, в полдень — сверху, вечером — справа (как раньше)
	var th := clampf(PI * (t - 6.0) / 12.0, 0.0, PI)
	var sxs := -cos(th)
	var sys := -sin(th)
	var dx := (sxs + sys) / 2.0
	var dy := (sys - sxs) / 2.0
	var hor := Vector2(dx, dy).normalized()
	var alt := deg_to_rad(lerpf(12.0, 62.0, clampf(e, 0.0, 1.0)))
	var to_sun := Vector3(hor.x * cos(alt), sin(alt), hor.y * cos(alt)).normalized()
	if to_sun.length() > 0.01:
		sun.look_at_from_position(Vector3.ZERO, -to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD)
	var day := clampf(e / 0.15 + 0.2, 0.0, 1.0)          # 0 ночь .. 1 день
	night = 1.0 - day
	var gold := clampf(1.0 - e / 0.35, 0.0, 1.0) * day
	var col := C_DAY.lerp(C_GOLD, gold * 0.85)
	sun.light_color = col
	sun.light_energy = 0.82 * day * (1.0 - 0.55 * cloud)
	sun.shadow_opacity = 1.0 - 0.6 * cloud
	sun.visible = day > 0.01
	moon.light_energy = 0.22 * (1.0 - day)
	moon.visible = day < 0.99
	env.ambient_light_color = Color(0.62, 0.66, 0.62).lerp(C_NIGHT, 1.0 - day)
	env.ambient_light_energy = lerpf(0.3, 0.5, day) * (1.0 + 0.25 * cloud)

func label() -> String:
	var hh := int(t)
	var mm := int((t - hh) * 60.0)
	return "%02d:%02d" % [hh, mm]

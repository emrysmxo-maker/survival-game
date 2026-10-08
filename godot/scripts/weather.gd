extends Node3D
# Погода: ясно / облачно / дождь сменяются сами (раз в 3–8 реальных минут). Дождь — частицы у камеры,
# земля мокнет и сохнет (лужи — ground.gdshader rain_wet), ветер сильнее; облачность приглушает солнце (daynight.cloud).
# Туман в низинах: полупрозрачные пласты над водой, болотами и поймой реки — утром, вечером и в дождь.
# Отладка: --weather=rain|cloudy|clear, --fog (туман всегда).
var main
var state := "clear"
var rain := 0.0                 # 0..1 сейчас
var wet := 0.0                  # мокрая земля 0..1 (сохнет медленно)
var cloud := 0.0
var fog := 0.0
var _rain_goal := 0.0
var _cloud_goal := 0.0
var _left := 0.0
var _drops: GPUParticles3D
var _fog_mm: MultiMeshInstance3D
var _fog_mat: ShaderMaterial
var _force := ""
var _fog_always := false
var _rng := RandomNumberGenerator.new()

const FOG_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float k = 0.0;
uniform vec3 col : source_color = vec3(0.78, 0.81, 0.82);
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz * 0.06 + vec2(TIME * 0.015, TIME * 0.008);
	float m = n(p) * 0.55 + n(p * 2.3 + 7.0) * 0.3 + n(p * 5.1 - 3.0) * 0.15;
	float edge = smoothstep(0.5, 0.15, length(UV - 0.5));
	ALBEDO = col;
	ALPHA = clamp((m - 0.35) * 1.6, 0.0, 1.0) * edge * k * 0.36;
}
"""

func _ready() -> void:
	_rng.seed = 4242
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weather="): _force = a.substr(10)
		if a == "--fog": _fog_always = true
	_make_rain()
	_make_fog()
	_next("clear" if _force == "" else _force)

func _next(s: String) -> void:
	state = s
	_rain_goal = 1.0 if s == "rain" else 0.0
	_cloud_goal = 1.0 if s == "rain" else (0.55 if s == "cloudy" else 0.0)
	_left = _rng.randf_range(180.0, 480.0)

func _process(dt: float) -> void:
	if _force == "":
		_left -= dt
		if _left <= 0.0:
			var r := _rng.randf()
			_next("rain" if r < 0.22 else ("cloudy" if r < 0.5 else "clear"))
	rain = move_toward(rain, _rain_goal, dt / 25.0)                  # дождь начинается и стихает за ~25 с
	cloud = move_toward(cloud, _cloud_goal, dt / 30.0)
	wet = clampf(wet + (rain * dt / 40.0) - (1.0 - rain) * dt / 240.0, 0.0, 1.0)   # мокнет за 40 с, сохнет за 4 мин
	var hr: float = main.daynight.t
	var morning := clampf(1.0 - absf(hr - 6.5) / 2.5, 0.0, 1.0)
	var evening := clampf(1.0 - absf(hr - 21.0) / 2.5, 0.0, 1.0)
	fog = 1.0 if _fog_always else maxf(maxf(morning, evening * 0.7), rain * 0.8)
	main.daynight.cloud = cloud
	RenderingServer.global_shader_parameter_set("wind_on", 1.0 + rain * 1.6 + cloud * 0.4)
	main.world.ground_mat.set_shader_parameter("rain_wet", wet)
	var foc: Vector2 = main.focus
	var c := Vector3(foc.x * WorldGen.T, WorldGen.height_m(foc.x, foc.y), foc.y * WorldGen.T)
	_drops.global_position = c + Vector3(0, 22.0, 0)
	_drops.emitting = rain > 0.03
	_drops.amount_ratio = clampf(rain, 0.05, 1.0)
	_fog_mat.set_shader_parameter("k", fog)
	_fog_mm.visible = fog > 0.02

func _make_rain() -> void:
	_drops = GPUParticles3D.new()
	_drops.amount = 2500
	_drops.lifetime = 1.4
	_drops.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 60, 80))
	_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(32, 1, 32)
	pm.direction = Vector3(0.15, -1, 0.05)
	pm.spread = 3.0
	pm.initial_velocity_min = 17.0
	pm.initial_velocity_max = 21.0
	pm.gravity = Vector3(0, -4, 0)
	_drops.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.55)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.8, 0.88, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = m
	_drops.draw_pass_1 = q
	_drops.emitting = false
	add_child(_drops)

# пласты тумана: над водой, болотами и у реки (одна партия — один вызов отрисовки)
func _make_fog() -> void:
	var spots: Array = []
	var x := -210.0
	while x <= 210.0:
		var y := -210.0
		while y <= 210.0:
			var low := WorldGen.water_at(x, y).x > 0.05 or WorldGen.swamp_at(x, y) > 0.3 or WorldGen.river_dist(x, y) < 12.0
			if low and WorldGen.in_map(x, y, 5.0):
				spots.append(Vector2(x + _rng.randf_range(-4, 4), y + _rng.randf_range(-4, 4)))
			y += 20.0
		x += 20.0
	var q := QuadMesh.new()
	q.size = Vector2(30.0, 30.0)
	q.orientation = PlaneMesh.FACE_Y
	_fog_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FOG_SHADER
	_fog_mat.shader = sh
	q.material = _fog_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = spots.size()
	for i in spots.size():
		var p: Vector2 = spots[i]
		var w := WorldGen.water_at(p.x, p.y)
		var hgt := WorldGen.height_m(p.x, p.y)
		if w.x > 0.05:
			hgt = maxf(hgt, w.y * WorldGen.HK)                         # над водой — от её поверхности
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.8, 1.4))
		mm.set_instance_transform(i, Transform3D(b, Vector3(p.x * WorldGen.T, hgt + 0.9, p.y * WorldGen.T)))
	_fog_mm = MultiMeshInstance3D.new()
	_fog_mm.multimesh = mm
	_fog_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fog_mm)
	print("погода: пластов тумана ", spots.size())

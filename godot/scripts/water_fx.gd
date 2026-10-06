extends Node3D
# Вода вокруг бойца: брызги из-под ног при ходьбе по мелководью, фонтан и «усы» за плывущим,
# расходящиеся круги по поверхности. Включается, когда под бойцом есть вода.
var player
var splash: GPUParticles3D
var wake: GPUParticles3D
var rings: Array = []
var drip: GPUParticles3D
var puffs: Array = []          # пенный след за плывущим (V-образный) и круги от шагов
var _wake_t := 0.0
var _idle_t := 0.0
var _foot := 1.0
const PUFF_N := 44
var _ring_t := 0.0
var _step_t := 0.0
var _was_in := false
var _tex: Texture2D
const RING_N := 8

func _soft() -> Texture2D:
	if _tex:
		return _tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf((1.0 - d) * 5.0, 0.0, 1.0)))     # чёткая капля (не мягкий дым)
	img.generate_mipmaps()
	_tex = ImageTexture.create_from_image(img)
	return _tex

func _make_particles(amount: int, life: float, size: float, speed: float, spread: float, grav: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 8, 16))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = spread
	m.initial_velocity_min = speed * 0.5
	m.initial_velocity_max = speed
	m.gravity = Vector3(0, -grav, 0)
	m.scale_min = size * 0.6
	m.scale_max = size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.7))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.5))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(0.92, 0.97, 1.0, 0.95))
	g.set_color(1, Color(0.85, 0.94, 1.0, 0.7))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true       # иначе масштаб частицы теряется и капли — по метру
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft()
	mat.disable_receive_shadows = true
	q.material = mat
	p.draw_pass_1 = q
	add_child(p)
	return p

func _ready() -> void:
	splash = _make_particles(10, 0.45, 0.04, 1.7, 55.0, 9.8)
	wake = _make_particles(26, 0.6, 0.05, 2.8, 40.0, 9.8)
	for p in [splash, wake]:
		p.one_shot = true
		p.explosiveness = 1.0
	# капли с мокрого бойца после выхода из воды: падают отвесно, ~3 секунды
	drip = _make_particles(16, 0.55, 0.03, 0.15, 180.0, 9.8)
	drip.explosiveness = 0.0
	drip.one_shot = false
	var dm := drip.process_material as ParticleProcessMaterial
	dm.direction = Vector3(0, -1, 0)
	dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dm.emission_box_extents = Vector3(0.28, 0.5, 0.18)
	# пенные пятна: мягкие диски на воде (след, круги шагов) — одна общая картинка
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
instance uniform float age = 0.0;
instance uniform float ring = 0.0;
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float disc = (1.0 - smoothstep(0.35, 1.0, d));
	float rg = smoothstep(0.62, 0.84, d) * (1.0 - smoothstep(0.84, 1.0, d));
	float a = mix(disc * 0.5, rg * 0.7, ring);
	ALBEDO = vec3(0.93, 0.97, 1.0);
	ALPHA = a * (1.0 - age);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	for i in PUFF_N:
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		mi.top_level = true
		add_child(mi)
		puffs.append({"n": mi, "age": 1.0, "life": 1.0, "s0": 0.2, "s1": 0.8, "v": Vector3.ZERO, "ring": 0.0})

func _spawn(p: Vector3, v: Vector3, life: float, s0: float, s1: float, ring: float) -> void:
	var best: Dictionary = puffs[0]
	for r in puffs:
		if r.age >= 1.0:
			best = r
			break
		if r.age > best.age:
			best = r
	best.age = 0.0
	best.life = life
	best.s0 = s0
	best.s1 = s1
	best.v = v
	best.ring = ring
	best.n.global_position = p
	best.n.set_instance_shader_parameter("ring", ring)
	best.n.visible = true

func update_fx(dt: float) -> void:
	var tile: Vector2 = player.tile
	var W := WorldGen.water_at(tile.x, tile.y)
	var h: float = WorldGen.height_m(tile.x, tile.y)
	var surf: float = W.y * WorldGen.HK
	var depth: float = surf - h
	var in_water: bool = W.x > 0.3 and depth > 0.12
	var spd: float = player.vel.length()
	var moving: bool = spd > 0.25
	var pos := Vector3(player.global_position.x, surf + 0.03, player.global_position.z)
	var fwd := Vector3(sin(player.yaw), 0.0, cos(player.yaw))
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	splash.global_position = pos
	wake.global_position = pos + Vector3(0, 0.05, 0)
	# мокрый: в воде глубже колена — 1, мелководье — 0.5, после выхода сохнет ~5 с
	if in_water:
		player.wet = maxf(player.wet, 1.0 if depth > 0.35 else 0.5)
	else:
		player.wet = maxf(0.0, player.wet - dt / 5.0)
	player.apply_wet()
	drip.global_position = player.global_position + Vector3(0, 1.0, 0)
	drip.emitting = player.wet > 0.35 and not in_water
	# шаги по мелководью: всплеск капель и маленький круг у ноги
	_step_t -= dt
	if in_water and not player.swimming and moving and depth < 0.9 and _step_t <= 0.0:
		_step_t = 0.34
		splash.restart()
		_foot = -_foot
		_spawn(pos + side * 0.12 * _foot + fwd * 0.05, Vector3.ZERO, 1.0, 0.12, 0.8, 1.0)
	if in_water and not _was_in:
		wake.restart()                      # вошёл в воду — всплеск и большой круг
		_spawn(pos, Vector3.ZERO, 1.6, 0.3, 2.4, 1.0)
	_was_in = in_water
	# плывёт: V-образный пенный след позади (два ряда пятен расходятся в стороны)
	if player.swimming:
		if moving:
			_wake_t -= dt
			if _wake_t <= 0.0:
				_wake_t = 0.1
				for sgn in [-1.0, 1.0]:
					_spawn(pos - fwd * 0.45 + side * 0.22 * sgn, side * sgn * 0.38 - fwd * 0.12, 2.2, 0.22, 0.75, 0.0)
		else:
			_idle_t -= dt
			if _idle_t <= 0.0:       # на месте — редкие слабые круги
				_idle_t = 1.4
				_spawn(pos + side * randf_range(-0.2, 0.2), Vector3.ZERO, 1.8, 0.3, 1.6, 1.0)
	for r in puffs:
		if r.age < 1.0:
			r.age += dt / r.life
			r.n.global_position += r.v * dt
			var s: float = lerpf(r.s0, r.s1, minf(r.age, 1.0))
			r.n.scale = Vector3(s, 1, s)
			r.n.set_instance_shader_parameter("age", minf(r.age, 1.0))
			if r.age >= 1.0:
				r.n.visible = false

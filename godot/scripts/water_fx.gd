extends Node3D
# Вода вокруг бойца: брызги из-под ног при ходьбе по мелководью, фонтан и «усы» за плывущим,
# расходящиеся круги по поверхности. Включается, когда под бойцом есть вода.
var player
var splash: GPUParticles3D
var wake: GPUParticles3D
var rings: Array = []
var collar: MeshInstance3D     # пенный «воротник» вокруг тела в воде (вода обтекает бойца)
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
	# круги на воде: плоский диск с шейдером-кольцом
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
instance uniform float age = 0.0;
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float ring = smoothstep(0.78, 0.9, d) * (1.0 - smoothstep(0.9, 1.0, d));
	ALBEDO = vec3(0.92, 0.97, 1.0);
	ALPHA = ring * (1.0 - age) * 0.55;
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	var csh := Shader.new()
	csh.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float strength = 1.0;
void fragment() {
	vec2 q = UV - 0.5;
	float d = length(q) * 2.0;
	float ang = atan(q.y, q.x);
	float wob = 0.06 * sin(ang * 7.0 + TIME * 3.0) + 0.04 * sin(ang * 13.0 - TIME * 4.3);
	float band = smoothstep(0.36 + wob, 0.55 + wob, d) * (1.0 - smoothstep(0.62 + wob, 0.98, d));
	float bits = 0.7 + 0.3 * sin(ang * 9.0 + TIME * 2.5 + d * 6.0);
	ALBEDO = vec3(0.9, 0.95, 0.97);
	ALPHA = band * bits * 0.45 * strength;
}"""
	var cmat := ShaderMaterial.new()
	cmat.shader = csh
	var cpm := PlaneMesh.new()
	cpm.size = Vector2(1.3, 1.3)
	collar = MeshInstance3D.new()
	collar.mesh = cpm
	collar.material_override = cmat
	collar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	collar.top_level = true
	collar.visible = false
	add_child(collar)
	for i in RING_N:
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		mi.top_level = true
		add_child(mi)
		rings.append({"n": mi, "age": 1.0})

func _spawn_ring(p: Vector3) -> void:
	var best: Dictionary = rings[0]
	for r in rings:
		if r.age >= 1.0:
			best = r
			break
		if r.age > best.age:
			best = r
	best.age = 0.0
	best.n.global_position = p
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
	splash.global_position = pos
	wake.global_position = pos + Vector3(0, 0.05, 0)
	# капли — только событиями: шаг по мелководью и вход в воду; на плаву только круги/пена
	_step_t -= dt
	if in_water and not player.swimming and moving and depth < 0.9 and _step_t <= 0.0:
		_step_t = 0.34
		splash.restart()
	if in_water and not _was_in:
		wake.restart()                      # вошёл в воду — всплеск
	_was_in = in_water
	collar.visible = in_water and depth > 0.2
	if collar.visible:
		collar.global_position = pos + Vector3(0, 0.01, 0)
		var sc: float = 1.6 if player.swimming else 1.0
		collar.scale = Vector3(sc, 1, sc)
		collar.rotation.y = player.yaw
	_ring_t -= dt
	if in_water and _ring_t <= 0.0 and (moving or player.swimming) and not OS.get_cmdline_user_args().has("--noring"):
		_ring_t = 0.2 if player.swimming else 0.4
		_spawn_ring(pos)
	for r in rings:
		if r.age < 1.0:
			r.age += dt / 1.3
			var s: float = 0.4 + r.age * (3.2 if player.swimming else 2.2)
			r.n.scale = Vector3(s, 1, s)
			r.n.set_instance_shader_parameter("age", minf(r.age, 1.0))
			if r.age >= 1.0:
				r.n.visible = false

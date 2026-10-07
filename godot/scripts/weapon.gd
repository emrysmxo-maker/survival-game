extends Node3D
# Стрельба: пули с трассером из дула, гильзы из окна выброса, дымок у дула,
# пыль/щепки в месте попадания, автострельба по ближнему зомби.
# Перенос src/weapon.js.

const FIRE_INTERVAL := 0.11
const BULLET_SPEED := 30.0     # тайлов/с
const BULLET_LIFE := 0.55
const BULLET_SPREAD := 0.02
const BULLET_HIT_R := 0.28     # тайлов — попадание в ствол дерева
const AUTO_FIRE_RANGE := 11.0
const CASING_LIE := 6.0

var player
var world
var zombies
var auto := false
var cooldown := 0.0
var bullets: Array = []
var casings: Array = []
var puffs: Array = []
var _tracer_mesh: BoxMesh
var _tracer_mat: StandardMaterial3D
var _casing_mat: StandardMaterial3D
var _puff_mesh: QuadMesh
var _puff_mat: ShaderMaterial
var _casing_mesh: QuadMesh
# пулы: объекты создаются один раз и переиспользуются (раньше — новые на каждый выстрел)
var _tracer_pool: Array = []
var _casing_pool: Array = []
var _puff_pool: Array = []

func _ready() -> void:
	_tracer_mesh = BoxMesh.new()
	_tracer_mesh.size = Vector3(0.005, 0.005, 0.22)
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1.0, 0.92, 0.65, 0.55)
	_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_casing_mat = StandardMaterial3D.new()
	_casing_mat.albedo_texture = load("res://assets/fx/casing.png")
	_casing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_casing_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_casing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_puff_mesh = QuadMesh.new()
	_puff_mesh.size = Vector2(1, 1)
	_puff_mat = ShaderMaterial.new()
	_puff_mat.shader = load("res://shaders/puff.gdshader")
	_puff_mat.set_shader_parameter("tex", _soft_tex())
	_casing_mesh = QuadMesh.new()
	_casing_mesh.size = Vector2(0.05, 0.05)
	_make_gun_sound()

# Автострельба: ближайший живой зомби в радиусе. Возвращает экранный вектор прицела или null.
func auto_target(force := false):
	if not (auto or force) or zombies == null:
		return null
	var best = null
	var bd := AUTO_FIRE_RANGE
	for z in zombies.list:
		if z.dead:
			continue
		var d: float = (z.tile - player.tile).length()
		if d < bd:
			bd = d
			best = z
	if best == null:
		return null
	var d2: Vector2 = best.tile - player.tile
	return player.tiles_to_aim(d2)

func update_weapon(dt: float, firing: bool) -> void:
	if _warm < 3:
		_warm_up()
	cooldown -= dt
	var ready: bool = player.aim_blend > 0.75 and player.barrel_on_target()
	if firing and ready and cooldown <= 0.0:
		_shoot()
		cooldown = FIRE_INTERVAL
	_update_bullets(dt)
	_update_casings(dt)
	_update_puffs(dt)

func _shoot() -> void:
	player.shot_fired()
	_gun_sound()
	var mz: Vector3 = player.muzzle_world()
	var dir3: Vector3 = player.barrel_dir()
	var d := Vector2(dir3.x, dir3.z).normalized().rotated(randf_range(-BULLET_SPREAD, BULLET_SPREAD))
	var tr: MeshInstance3D = _tracer_pool.pop_back() if not _tracer_pool.is_empty() else null
	if tr == null:
		tr = MeshInstance3D.new()
		tr.mesh = _tracer_mesh
		tr.material_override = _tracer_mat
		tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tr)
	tr.visible = true
	var b := {"x": mz.x / WorldGen.T, "y": mz.z / WorldGen.T, "z": mz.y, "dx": d.x, "dy": d.y, "vz": clampf(dir3.y, -0.3, 0.3), "age": 0.0, "node": tr}
	bullets.append(b)
	_place_bullet(b)
	# дымок у дула
	for i in 2:
		_puff(mz + Vector3(d.x, 0, d.y) * 0.1, Vector3(d.x * 0.3, 0.25, d.y * 0.3), Color(0.8, 0.8, 0.78, 0.35), 0.18, 0.7)
	# гильза: вправо-вверх от окна выброса
	var port: Vector3 = player.port_world()
	var right := Vector3(d.y, 0, -d.x)
	var c: MeshInstance3D = _casing_pool.pop_back() if not _casing_pool.is_empty() else null
	if c == null:
		c = MeshInstance3D.new()
		c.mesh = _casing_mesh
		c.material_override = _casing_mat
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(c)
	c.visible = true
	c.global_position = port
	casings.append({"node": c, "v": right * randf_range(1.6, 2.4) + Vector3(0, randf_range(1.8, 2.6), 0) - Vector3(d.x, 0, d.y) * 0.3, "rest": false, "age": 0.0, "b": 0})
	if casings.size() > 80:
		_free_casing(casings[0].node)
		casings.remove_at(0)

func _place_bullet(b: Dictionary) -> void:
	var p := Vector3(b.x * WorldGen.T, b.z, b.y * WorldGen.T)
	var n: MeshInstance3D = b.node
	n.global_position = p
	var fwd := Vector3(b.dx, b.vz, b.dy).normalized()
	n.global_position = p + fwd * 0.11
	n.look_at(p + fwd * 2.0, Vector3.UP)

func _update_bullets(dt: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var b: Dictionary = bullets[i]
		b.age += dt
		var sp := BULLET_SPEED * dt
		b.x += b.dx * sp
		b.y += b.dy * sp
		b.z += b.vz * sp * WorldGen.T
		var gz := WorldGen.height_m(b.x, b.y)
		var hit := false
		if b.z < gz + 0.08:
			_impact(Vector2(b.x, b.y), gz, false)
			hit = true
		elif zombies and zombies.bullet_hit(b):
			hit = true
		elif _hits_tree(b):
			_impact(Vector2(b.x, b.y), b.z, true)
			hit = true
		elif b.age > BULLET_LIFE:
			_impact(Vector2(b.x, b.y), gz, false)
			hit = true
		if hit:
			b.node.visible = false
			_tracer_pool.append(b.node)
			bullets.remove_at(i)
		else:
			_place_bullet(b)

func _hits_tree(b: Dictionary) -> bool:
	for o in world.obstacles_near(Vector2(b.x, b.y)):
		if not o.tree:
			continue
		if Vector2(b.x - o.x, b.y - o.y).length() < BULLET_HIT_R:
			return true
	return false

func _impact(t: Vector2, z: float, wood: bool) -> void:
	var p := Vector3(t.x * WorldGen.T, z + 0.05, t.y * WorldGen.T)
	var col := Color(0.55, 0.42, 0.28, 0.6) if wood else Color(0.6, 0.55, 0.45, 0.5)
	for i in (4 if wood else 3):
		_puff(p, Vector3(randf_range(-0.6, 0.6), randf_range(0.4, 1.2), randf_range(-0.6, 0.6)), col, 0.12, 0.6)

func _puff(p: Vector3, v: Vector3, col: Color, size: float, life: float) -> void:
	var m: MeshInstance3D = _puff_pool.pop_back() if not _puff_pool.is_empty() else null
	if m == null:
		m = MeshInstance3D.new()
		m.mesh = _puff_mesh
		m.material_override = _puff_mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
	m.visible = true
	m.global_position = p
	m.scale = Vector3.ONE * size
	m.set_instance_shader_parameter("col", col)
	puffs.append({"node": m, "v": v, "age": 0.0, "life": life, "size": size, "col": col})
	if puffs.size() > 120:
		_free_puff(puffs[0].node)
		puffs.remove_at(0)

func _free_puff(m: MeshInstance3D) -> void:
	m.visible = false
	_puff_pool.append(m)

func _free_casing(c: MeshInstance3D) -> void:
	c.visible = false
	_casing_pool.append(c)

var _soft: Texture2D
func _soft_tex() -> Texture2D:
	if _soft:
		return _soft
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.5))
	img.generate_mipmaps()
	_soft = ImageTexture.create_from_image(img)
	return _soft

func _update_puffs(dt: float) -> void:
	for i in range(puffs.size() - 1, -1, -1):
		var p: Dictionary = puffs[i]
		p.age += dt
		var k: float = p.age / p.life
		if k >= 1.0:
			_free_puff(p.node)
			puffs.remove_at(i)
			continue
		p.node.global_position += p.v * dt
		p.v *= 1.0 - 2.5 * dt
		p.node.scale = Vector3.ONE * p.size * (1.0 + k * 2.0)
		var c: Color = p.col
		c.a = p.col.a * (1.0 - k)
		p.node.set_instance_shader_parameter("col", c)

func _update_casings(dt: float) -> void:
	for i in range(casings.size() - 1, -1, -1):
		var c: Dictionary = casings[i]
		var n: Node3D = c.node
		if c.rest:
			c.age += dt
			if c.age > CASING_LIE:
				_free_casing(n)
				casings.remove_at(i)
			continue
		c.v.y -= 9.8 * dt
		n.global_position += c.v * dt
		var gp := n.global_position
		var gz := WorldGen.height_m(gp.x / WorldGen.T, gp.z / WorldGen.T) + 0.02
		if gp.y <= gz:
			n.global_position.y = gz
			if c.b < 2 and absf(c.v.y) > 0.6:
				c.v = Vector3(c.v.x * 0.45, -c.v.y * 0.32, c.v.z * 0.45)
				c.b += 1
			else:
				c.rest = true

# --- прогрев: первый выстрел не должен подвисать (шейдеры/пулы создаются заранее) ---
var _warm := 0
func _warm_up() -> void:
	_warm += 1
	if _warm == 1:
		var p: Vector3 = player.global_position
		var tr := MeshInstance3D.new()
		tr.mesh = _tracer_mesh
		tr.material_override = _tracer_mat
		tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tr.scale = Vector3.ONE * 0.01
		add_child(tr)
		tr.global_position = p + Vector3(0, 1, 0)
		var c := MeshInstance3D.new()
		c.mesh = _casing_mesh
		c.material_override = _casing_mat
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.scale = Vector3.ONE * 0.01
		add_child(c)
		c.global_position = p + Vector3(0, 1, 0)
		_puff(p + Vector3(0, 1, 0), Vector3.ZERO, Color(1, 1, 1, 0.01), 0.01, 0.05)
		_tracer_pool.append(tr)
		_casing_pool.append(c)
	elif _warm == 3:
		for n in [_tracer_pool, _casing_pool]:
			for m in n:
				m.scale = Vector3.ONE
				m.visible = false

# --- звук автомата: синтез при старте (щелчок + треск + низкий удар), пул из 4 плееров ---
var _gun_snd: Array = []
var _gun_players: Array = []
var _gun_i := 0
func _make_gun_sound() -> void:
	var rate := 22050
	for v in 3:
		var n := int(rate * 0.22)
		var data := PackedByteArray()
		data.resize(n * 2)
		var rng := RandomNumberGenerator.new()
		rng.seed = 900 + v
		var lp := 0.0
		var ph := 0.0
		for i in n:
			var t := float(i) / rate
			var crack := rng.randf_range(-1.0, 1.0) * exp(-t * 90.0)
			lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.22
			var body := lp * exp(-t * 20.0) * 1.6
			var f := 140.0 * exp(-t * 14.0) + 45.0
			ph += TAU * f / rate
			var thump := sin(ph) * exp(-t * 26.0) * 0.9
			var x := clampf((crack * 0.9 + body + thump) * 0.8, -1.0, 1.0)
			data.encode_s16(i * 2, int(x * 30000.0))
		var st := AudioStreamWAV.new()
		st.format = AudioStreamWAV.FORMAT_16_BITS
		st.mix_rate = rate
		st.data = data
		_gun_snd.append(st)
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.volume_db = -7.0
		add_child(p)
		_gun_players.append(p)

const SOUND_ON := false          # звук пока выключен (владелец: добавим позже)
func _gun_sound() -> void:
	if not SOUND_ON:
		return
	var p: AudioStreamPlayer = _gun_players[_gun_i % _gun_players.size()]
	_gun_i += 1
	p.stream = _gun_snd[randi() % _gun_snd.size()]
	p.pitch_scale = randf_range(0.95, 1.06)
	p.play()

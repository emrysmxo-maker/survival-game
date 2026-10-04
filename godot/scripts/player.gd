extends Node3D
# Боец: ходьба (левый стик), прицел и огонь (правый стик), разворот к цели,
# столкновения с деревьями/камнями, замедление в воде/болоте/в гору.
# Позиция бойца хранится в тайлах (tile), как в браузерной версии.

const SPEED := 2.0                 # тайлов/с по каждой оси (как в v7: ~2.85 тайла/с по диагонали)
const ACCEL := 14.0
const BODY_TURN_RATE := 5.5        # рад/с — поворот тела при стрельбе
const SPEED_WATER := 0.5
const SPEED_SWAMP := 0.65
const MODEL_YAW_OFFSET := 0.0      # если модель смотрит «спиной» — PI

var world
var tile := Vector2.ZERO
var vel := Vector2.ZERO
var move_dir := Vector2.ZERO       # куда хочет идти (тайлы), единичный
var moving := false
var yaw := 0.0                     # куда смотрит тело (Godot, вокруг Y)
var aim_yaw := 0.0                 # куда смотрит ствол
var aiming := false                # правый стик нажат (автомат поднят)
var firing := false                # стик за порогом — огонь
var aim_world_dir := Vector3.FORWARD
var aim_blend := 0.0
var recoil := 0.0
var backpedal := false
var slope_along := 0.0

var model: Node3D
var skel: Skeleton3D
var anim: AnimationPlayer
var rifle_rig: Node3D
var muzzle_flash: Node3D
var flash_t := 0.0
var _cur_anim := ""
var _anim_speed := 1.0

const RIFLE_GRIP := Vector3(0, -0.10, -0.125)
const RIFLE_HANDGUARD := Vector3(0, -0.035, 0.15)
const RIFLE_MUZZLE := Vector3(0, 0.02, 0.37)
const RIFLE_PORT := Vector3(0.03, 0.03, -0.02)

func _ready() -> void:
	var scn: PackedScene = load("res://assets/character/Soldier.glb")
	model = scn.instantiate()
	add_child(model)
	skel = _find(model, "Skeleton3D")
	anim = _find(model, "AnimationPlayer")
	_recolor(model)
	_make_rifle()
	if skel:
		var ik = load("res://scripts/rifle_ik.gd").new()
		ik.player = self
		skel.add_child(ik)

func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null

func _recolor(n: Node) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		for s in mi.mesh.get_surface_count():
			var m = mi.get_active_material(s)
			if m is BaseMaterial3D and m.albedo_texture:
				var sm := ShaderMaterial.new()
				sm.shader = load("res://shaders/recolor.gdshader")
				sm.set_shader_parameter("albedo_tex", m.albedo_texture)
				if m.normal_enabled and m.normal_texture:
					sm.set_shader_parameter("normal_tex", m.normal_texture)
					sm.set_shader_parameter("has_normal", true)
				mi.set_surface_override_material(s, sm)
	for c in n.get_children():
		_recolor(c)

func _make_rifle() -> void:
	rifle_rig = Node3D.new()
	model.add_child(rifle_rig)
	var r: Node3D = (load("res://assets/character/Rifle_Assault.glb") as PackedScene).instantiate()
	r.rotation.y = PI          # в файле ствол смотрит в -Z
	rifle_rig.add_child(r)
	_brighten(r)
	# вспышка у дула: два перекрещенных язычка + звезда, аддитивно
	muzzle_flash = Node3D.new()
	muzzle_flash.position = RIFLE_MUZZLE
	rifle_rig.add_child(muzzle_flash)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = _flash_tex()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	for i in 2:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.42, 0.16)
		qm.center_offset = Vector3(0.21, 0, 0)
		q.mesh = qm
		q.material_override = mat
		q.rotation = Vector3(0, -PI / 2, 0) if i == 0 else Vector3(PI / 2, -PI / 2, 0)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		muzzle_flash.add_child(q)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.4)
	light.light_energy = 2.5
	light.omni_range = 3.5
	muzzle_flash.add_child(light)
	muzzle_flash.visible = false

func _brighten(n: Node) -> void:
	if n is MeshInstance3D:
		for s in n.mesh.get_surface_count():
			var m = n.get_active_material(s)
			if m is BaseMaterial3D:
				var m2: BaseMaterial3D = m.duplicate()
				m2.albedo_color = m2.albedo_color.lightened(0.12)
				n.set_surface_override_material(s, m2)
	for c in n.get_children():
		_brighten(c)

func _flash_tex() -> Texture2D:
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 64:
			var u := x / 63.0
			var v := absf(y / 31.0 - 0.5) * 2.0
			var w := (1.0 - u) * 0.85 + 0.15
			var a := clampf(1.0 - v / maxf(w, 0.05), 0.0, 1.0) * (1.0 - u * 0.7)
			img.set_pixel(x, y, Color(1.0, 0.85 - u * 0.3, 0.45 - u * 0.3, a))
	return ImageTexture.create_from_image(img)

func shot_fired() -> void:
	recoil = 1.0
	flash_t = 0.035
	if muzzle_flash:
		var k := randf_range(0.75, 1.25)
		muzzle_flash.scale = Vector3(k, k, k)
		muzzle_flash.rotation.z = randf() * TAU

# экранный вектор стика -> направление в мире (тайлы): как в браузерной версии
static func screen_to_tiles(v: Vector2) -> Vector2:
	return Vector2(v.x + v.y, v.y - v.x)

static func tiles_to_yaw(d: Vector2) -> float:
	# тайлы (x, y) -> Godot (x, z); yaw: +Z = 0
	return atan2(d.x, d.y)

func set_tile(p: Vector2) -> void:
	tile = p
	vel = Vector2.ZERO
	_place()

func _place() -> void:
	var h := WorldGen.height(tile.x, tile.y)
	global_position = WorldGen.to_world(tile.x, tile.y, h)

func step(dt: float, stick: Vector2, aim_stick: Vector2, aim_active: bool, fire_now: bool) -> void:
	# --- ходьба ---
	var want := Vector2.ZERO
	moving = stick.length() > 0.01
	if moving:
		var mf := 1.0
		if firing:
			mf = 0.45 if stick.length() < 0.28 else 0.72
		want = screen_to_tiles(stick) * SPEED * mf
		want *= _terrain_speed(want)
		move_dir = want.normalized()
		vel += (want - vel) * minf(1.0, ACCEL * dt)
	else:
		vel *= maxf(0.0, 1.0 - 18.0 * dt)
		if vel.length() < 0.05:
			vel = Vector2.ZERO
	var prev := tile
	tile += vel * dt
	_collide(prev)
	var lim := WorldGen.MAP_RADIUS - 5.0
	tile = tile.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	_place()
	var real_speed := (tile - prev).length() / maxf(dt, 1e-4)

	# --- прицел ---
	aiming = aim_active
	firing = fire_now and aim_active
	if aim_active and aim_stick.length() > 0.01:
		var d := screen_to_tiles(aim_stick)
		aim_yaw = tiles_to_yaw(d)
	aim_blend = move_toward(aim_blend, 1.0 if aiming else 0.0, dt * 9.0 * (1.0 if aiming else 0.6))
	recoil = maxf(0.0, recoil - dt * 14.0)
	flash_t = maxf(0.0, flash_t - dt)
	muzzle_flash.visible = flash_t > 0.0

	# --- тело ---
	var move_yaw := tiles_to_yaw(move_dir) if moving else yaw
	var body_target := move_yaw
	if aiming:
		body_target = aim_yaw
	if aiming:
		# разворот почти на 180° — в сторону прицела, а не как выпадет
		var d2 := wrapf(body_target - yaw, -PI, PI)
		yaw = wrapf(yaw + clampf(d2, -BODY_TURN_RATE * dt, BODY_TURN_RATE * dt), -PI, PI)
	elif moving:
		yaw = lerp_angle(yaw, body_target, minf(1.0, 14.0 * dt))
	model.rotation.y = yaw + MODEL_YAW_OFFSET

	# ноги: вперёд или пятится (если тело смотрит назад от движения)
	backpedal = false
	if moving and aiming:
		var rel := absf(wrapf(move_yaw - yaw, -PI, PI))
		backpedal = rel > 1.75
	if moving and real_speed > 0.15:
		var spd := real_speed / 2.85
		_play("Run", -1.0 * clampf(spd * 1.1, 0.5, 1.4) if backpedal else clampf(spd * 1.1, 0.5, 1.4))
	else:
		_play("Idle", 1.0)

func barrel_on_target() -> bool:
	return absf(wrapf(aim_yaw - yaw, -PI, PI)) < 0.25

func _play(n: String, speed: float) -> void:
	if anim == null:
		return
	if n != _cur_anim:
		anim.play(n, 0.15)
		_cur_anim = n
	anim.speed_scale = speed

func _terrain_speed(want: Vector2) -> float:
	var t := WorldGen.terrain(tile.x, tile.y)
	var k := 1.0 - (1.0 - SPEED_WATER) * t[1]
	k *= 1.0 - (1.0 - SPEED_SWAMP) * t[3]
	var l := want.length()
	if l > 1e-6:
		var u := want / l
		var e := 0.5
		var slope := (WorldGen.height(tile.x + u.x * e, tile.y + u.y * e) - WorldGen.height(tile.x - u.x * e, tile.y - u.y * e)) / (2.0 * e)
		var sm := slope / 1.39
		slope_along = sm
		k *= 1.0 / (1.0 + sm * 0.75) if sm > 0.0 else 1.0 + 0.22 * tanh(-sm * 1.6)
	return k

func _collide(prev: Vector2) -> void:
	if world == null:
		return
	var obs: Array = world.obstacles_near(tile)
	for _i in 3:
		for o in obs:
			var d := tile - Vector2(o.x, o.y)
			var r: float = o.r
			if absf(d.x) > r or absf(d.y) > r:
				continue
			var l := d.length()
			if l < r:
				if l < 1e-4:
					d = Vector2(1, 0); l = 1.0
				tile = Vector2(o.x, o.y) + d / l * r
	for o in obs:
		if (tile - Vector2(o.x, o.y)).length() < o.r - 0.02:
			tile = prev
			return

# точки автомата в мире (для пуль, гильз)
func muzzle_world() -> Vector3:
	return rifle_rig.global_transform * RIFLE_MUZZLE

func port_world() -> Vector3:
	return rifle_rig.global_transform * RIFLE_PORT

func barrel_dir() -> Vector3:
	return (rifle_rig.global_transform.basis * Vector3(0, 0, 1)).normalized()

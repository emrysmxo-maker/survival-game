extends Node3D
# Боец: ходьба (левый стик), прицел и огонь (правый стик), разворот к цели,
# столкновения с деревьями/камнями, замедление в воде/болоте/в гору.
# Позиция бойца хранится в тайлах (tile), как в браузерной версии.

const SPEED := 3.5                 # тайлов/с (×1.41 в screen_to_tiles): до упора ≈ 4.1 м/с — спринт (RunFast), середина — бег
const ACCEL := 14.0
const BODY_TURN_RATE := 5.5        # рад/с — поворот тела при стрельбе
# Стрельба на ходу (стиль «Корпус 90° → пятится» из браузерной версии):
# НОГИ ВСЕГДА ИДУТ ПО НАПРАВЛЕНИЮ ДВИЖЕНИЯ — лицом вперёд или спиной вперёд (тот же
# бег, проигранный назад). К цели поворачивается только верх: корпус (скручивание
# позвоночника до TWIST) и руки (ещё ARMS). Цель дальше — боец разворачивается и пятится.
const TWIST := 1.05                # 60°: скрутка 90° у реалистичной модели выглядела как резина — дальше разворачиваются ноги
const ARMS := 0.2618               # 15°
const REACH := TWIST + ARMS
const FIRE_SPEED := 0.65           # скорость бега при прицеле (×)
const BACK_SPEED := 0.45           # скорость пятясь (×)
var AIM_ELEV_K := 0.7297           # sin(угла камеры): по вертикали экрана земля сжата — поправка прицела (задаёт main.gd)
const SPEED_WATER := 0.5
const SPEED_SWAMP := 0.65
const CHAR_SCALE := 0.8            # боец в тех же пропорциях к деревьям, что в браузерной версии

var world
var tile := Vector2.ZERO
var vel := Vector2.ZERO
var anim_speed := 0.0
var swimming := false
var water_depth := 0.0             # м воды над землёй под бойцом (0 — суша)
var wet_mat: ShaderMaterial        # «мокрый» слой тела (общий для всех частей модели)
var wet := 0.0                     # 0..1: мокрый (в воде 1, потом сохнет ~5 с)
var _wet_set := -1.0
var swim_t := 0.0                  # фаза гребков (процедурное плавание, rifle_ik.gd)
const SWIM_SPEED := 0.5
const SWIM_DEPTH := 1.0             # м: насколько ноги-точка модели ниже поверхности воды при плавании (подбирается по виду)
var _running := false
var _gait := 0
const GAIT_NAMES := ["WalkSlow", "Walk", "WalkFast", "RunSlow", "Run", "RunFast"]
var _gait_mps := [0.66, 0.81, 1.2, 1.93, 2.3, 4.67]     # м/с при speed_scale 1 — из survivor_speeds.json (путь таза в записи × масштаб)
var move_dir := Vector2.ZERO       # куда хочет идти (тайлы), единичный
var moving := false
var yaw := 0.0                     # куда смотрит тело (Godot, вокруг Y)
var aim_yaw := 0.0                 # куда целится игрок (цель)
var aim_world := NAN               # куда ствол довернулся сейчас (плавно, как в старой версии: 260°/с)
const AIM_TURN := 4.54             # рад/с
var aiming := false                # правый стик нажат (автомат поднят)
var firing := false                # стик за порогом — огонь
var aim_world_dir := Vector3.FORWARD
var aim_blend := 0.0
var recoil := 0.0
var backpedal := false
var slope_along := 0.0
var aim_local := 0.0              # на сколько ствол повёрнут относительно ног (рад): корпус + руки
var cam_yaw := 0.7853982          # поворот камеры (рад), задаёт main.gd

var model: Node3D
var skel: Skeleton3D
var anim: AnimationPlayer
var rifle_rig: Node3D
var muzzle_flash: Node3D
var flash_t := 0.0
var _cur_anim := ""
var blob: MeshInstance3D
var _anim_speed := 1.0

const RIFLE_GRIP := Vector3(0, -0.10, -0.125)
const RIFLE_HANDGUARD := Vector3(0, -0.035, 0.15)
const RIFLE_MUZZLE := Vector3(0, 0.02, 0.37)
const RIFLE_PORT := Vector3(0.03, 0.03, -0.02)

func _ready() -> void:
	var scn: PackedScene = load("res://assets/character/Survivor.glb")
	# модель (Rocketbox Male_Adult_07, MIT) в файле смотрит в -Z: кладём её в «опору», развёрнутую на 180°,
	# у опоры +Z — лицо бойца (на опору опираются автомат и прицел)
	model = Node3D.new()
	model.scale = Vector3.ONE * CHAR_SCALE
	add_child(model)
	var glb: Node3D = scn.instantiate()
	glb.rotation.y = PI
	model.add_child(glb)
	skel = _find(glb, "Skeleton3D")
	anim = _find(glb, "AnimationPlayer")
	if anim == null:
		# в модели Rocketbox нет клипов — плеер создаём сами, клипы из survivor_clips.json
		anim = AnimationPlayer.new()
		glb.add_child(anim)
		anim.add_animation_library("", AnimationLibrary.new())
	_add_json_clips("res://assets/character/survivor_clips.json")
	loop_all(anim)
	var sf := FileAccess.open("res://assets/character/survivor_speeds.json", FileAccess.READ)
	if sf:
		var sp = JSON.parse_string(sf.get_as_text())
		if sp is Dictionary:
			for gi in GAIT_NAMES.size():
				if sp.has(GAIT_NAMES[gi]) and float(sp[GAIT_NAMES[gi]]) > 0.1:
					_gait_mps[gi] = float(sp[GAIT_NAMES[gi]]) * CHAR_SCALE
	_make_rifle()
	add_xray(model, true)
	blob = make_blob(0.75)
	add_child(blob)
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
	for c in skel.get_children() if skel else []:
		if c.has_method("fire"):
			c.fire()
	flash_t = 0.035
	if muzzle_flash:
		var k := randf_range(0.75, 1.25)
		muzzle_flash.scale = Vector3(k, k, k)
		muzzle_flash.rotation.z = randf() * TAU

# экранный вектор стика -> направление в мире (тайлы). «Вверх» — туда, куда смотрит камера.
func screen_to_tiles(v: Vector2) -> Vector2:
	var fwd := Vector2(-sin(cam_yaw), -cos(cam_yaw))
	var right := Vector2(cos(cam_yaw), -sin(cam_yaw))
	return (right * v.x + fwd * (-v.y)) * 1.4142

# то же для прицела: с поправкой на сжатие земли по вертикали экрана
func aim_to_tiles(v: Vector2) -> Vector2:
	return screen_to_tiles(Vector2(v.x, v.y / AIM_ELEV_K))

# обратное (для автострельбы): направление на цель в тайлах -> «стик» прицела
func tiles_to_aim(d: Vector2) -> Vector2:
	var fwd := Vector2(-sin(cam_yaw), -cos(cam_yaw))
	var right := Vector2(cos(cam_yaw), -sin(cam_yaw))
	return Vector2(d.dot(right), -d.dot(fwd) * AIM_ELEV_K).normalized()

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
	# вода: глубже ~1 м — плывёт (над водой голова и плечи), автомат за спиной
	var W := WorldGen.water_at(tile.x, tile.y)
	var surf: float = W.y * WorldGen.HK
	var ground: float = h * WorldGen.HK
	var depth: float = surf - ground
	water_depth = depth if W.x > 0.3 else 0.0
	swimming = W.x > 0.5 and depth > (0.85 if swimming else 0.95)
	if swimming:
		global_position.y = maxf(ground, surf - SWIM_DEPTH)   # тело лежит на воде: клип плавания горизонтальный

func step(dt: float, stick: Vector2, aim_stick: Vector2, aim_active: bool, fire_now: bool) -> void:
	# --- ходьба ---
	var want := Vector2.ZERO
	moving = stick.length() > 0.01
	if moving:
		var mf := 1.0
		if aiming:
			mf = BACK_SPEED if backpedal else FIRE_SPEED
		# лёгкий наклон стика — шаг (не меньше 55% скорости), чтобы не топтаться на месте
		want = screen_to_tiles(stick.normalized()) * SPEED * mf * lerpf(0.15, 1.0, clampf((stick.length() - 0.1) / 0.75, 0.0, 1.0))   # слегка — медленный шаг, до упора — бег
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
	aiming = aim_active and not swimming      # плывёт — не стреляет
	firing = fire_now and aiming
	if aim_active and aim_stick.length() > 0.01:
		aim_yaw = tiles_to_yaw(aim_to_tiles(aim_stick))
	if aiming:
		if is_nan(aim_world):
			aim_world = yaw + aim_local
		aim_world = wrapf(aim_world + clampf(wrapf(aim_yaw - aim_world, -PI, PI), -AIM_TURN * dt, AIM_TURN * dt), -PI, PI)
	else:
		aim_world = NAN
	aim_blend = move_toward(aim_blend, 1.0 if aiming else 0.0, dt * 9.0 * (1.0 if aiming else 0.6))
	recoil = maxf(0.0, recoil - dt * 14.0)
	flash_t = maxf(0.0, flash_t - dt)
	muzzle_flash.visible = flash_t > 0.0

	# --- тело: точный перенос браузерной версии (src/character.js) ---
	# Ноги — строго по движению; цель дальше REACH — разворот лицом к цели и шаг назад.
	# Тело поворачивается с ограниченной скоростью (5.5 рад/с), на ~180° — в сторону прицела.
	var move_yaw := tiles_to_yaw(move_dir) if moving else yaw
	var legs := move_yaw
	if aiming and moving:
		var rel := absf(wrapf(aim_world - move_yaw, -PI, PI))
		backpedal = rel > (REACH - 0.17 if backpedal else REACH)   # гистерезис 10°
		if backpedal:
			legs = wrapf(move_yaw + PI, -PI, PI)
	elif aiming:
		backpedal = false
		legs = aim_world
	else:
		backpedal = false
	if aiming:
		var d2 := wrapf(legs - yaw, -PI, PI)
		if absf(d2) > 2.9:
			var side := signf(wrapf(aim_world - yaw, -PI, PI))
			if side != 0.0 and signf(d2) != side:
				d2 += side * TAU
		yaw = wrapf(yaw + clampf(d2, -BODY_TURN_RATE * dt, BODY_TURN_RATE * dt), -PI, PI)
	elif moving:
		yaw = lerp_angle(yaw, move_yaw, minf(1.0, 24.0 * dt))
	model.rotation.y = yaw

	# ствол относительно ног: добирают корпус (скручивание) и руки, дальше — не довернуть
	var aim_rel := 0.0
	if aiming:
		aim_rel = clampf(wrapf(aim_world - yaw, -PI, PI), -REACH, REACH)
	aim_local += (aim_rel - aim_local) * minf(1.0, (12.0 if aiming else 8.0) * dt)

	# Анимация как в браузерной версии: по скорости — ходьба (Walk) или бег (Run) с гистерезисом;
	# пятится — всегда шагом, тот же клип назад. Темп шага = скорость по земле / скорость клипа.
	model.rotation.x = lerpf(model.rotation.x, 0.0, minf(1.0, 5.0 * dt))   # плывя — наклон вперёд
	if swimming:
		# плавание: база — стойка, руки и ноги гребут процедурно (rifle_ik.gd), тело наклонено вперёд
		_play("Swim_Fwd" if moving else "Swim_Idle", 1.0)
		return
	if moving and real_speed > 0.15:
		anim_speed += (real_speed - anim_speed) * minf(1.0, 6.0 * dt)
		var mps := anim_speed * WorldGen.T
		# походка по скорости (живой мокап Rocketbox): медленный шаг → шаг → быстрый шаг → лёгкий бег → бег;
		# темп = скорость по земле / скорость клипа (путь таза в записи) — стопа не скользит
		if backpedal or water_depth > 0.15:
			_gait = 1                 # пятясь и по воде — обычный шаг
		else:
			while _gait < _gait_mps.size() - 1 and mps > (_gait_mps[_gait] + _gait_mps[_gait + 1]) * 0.5 * 1.06:
				_gait += 1
			while _gait > 0 and mps < (_gait_mps[_gait] + _gait_mps[_gait - 1]) * 0.5 * 0.94:
				_gait -= 1
		_running = _gait >= 3
		var k := clampf(mps / _gait_mps[_gait], 0.55, 1.5) * (0.82 if water_depth > 0.15 else 1.0)   # в воде шаг тяжелее
		_play(GAIT_NAMES[_gait], -k if backpedal else k)
	else:
		anim_speed = 0.0
		_running = false
		_play("Idle", 1.0)

func apply_wet() -> void:
	if wet_mat == null or absf(wet - _wet_set) < 0.01:
		return
	_wet_set = wet
	wet_mat.set_shader_parameter("wet", wet)

func foot_offset() -> float:
	# высота самой низкой точки стоп над точкой земли (м, мир)
	var lo := 1e9
	for n in ["LeftFoot", "LeftToeBase", "RightFoot", "RightToeBase"]:
		var b := skel.find_bone("mixamorig_" + n)
		if b >= 0:
			lo = minf(lo, (skel.global_transform * skel.get_bone_global_pose(b).origin).y)
	return lo - global_position.y

func barrel_on_target() -> bool:
	# ствол реально смотрит туда, куда прицел (с допуском ~11°)
	return absf(wrapf(aim_yaw - (yaw + aim_local), -PI, PI)) < 0.2

var forced_clip := ""          # отладка (devtest --gait=): принудительный клип, темп 1
func _play(n: String, speed: float) -> void:
	if anim == null:
		return
	if forced_clip != "" and n in GAIT_NAMES:
		n = forced_clip
		speed = signf(speed)
	if n != _cur_anim:
		anim.play(n, 0.15)
		_cur_anim = n
	anim.speed_scale = speed

func _terrain_speed(want: Vector2) -> float:
	var t := WorldGen.terrain(tile.x, tile.y)
	if swimming:
		return SWIM_SPEED
	# брод: до колена почти без потерь, глубже — тяжелее (до 0.55 на пороге плавания); влажный песок не тормозит
	var k := 1.0 - 0.45 * smoothstep(0.12, 0.95, water_depth)
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

# --- тень-пятно под ногами и силуэт сквозь деревья (общие для бойца и зомби) ---
static func make_blob(size: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(size, size)
	m.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/blob.gdshader")
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position.y = 0.07
	return m

func add_xray(n: Node, with_wet := false) -> void:
	var xr := ShaderMaterial.new()
	xr.shader = load("res://shaders/xray.gdshader")
	xr.render_priority = 10
	var first: Material = xr
	if with_wet:
		wet_mat = ShaderMaterial.new()
		wet_mat.shader = load("res://shaders/wet.gdshader")
		wet_mat.next_pass = xr
		first = wet_mat
	_xray_walk(n, first)

static func _xray_walk(n: Node, xr: Material) -> void:
	if n is MeshInstance3D and n.mesh:
		for i in n.mesh.get_surface_count():
			var m: Material = n.get_active_material(i)
			if m == null:
				continue
			if n.get_surface_override_material(i) == null:
				m = m.duplicate()
				n.set_surface_override_material(i, m)
			m.next_pass = xr
	for c in n.get_children():
		_xray_walk(c, xr)

var _xray := false
func set_xray(on: bool) -> void:
	if on == _xray:
		return
	_xray = on
	_xr_set(model, on)

func _xr_set(n: Node, on: bool) -> void:
	if n is GeometryInstance3D:
		n.set_instance_shader_parameter("xray_on", 1.0 if on else 0.0)
	for c in n.get_children():
		_xr_set(c, on)

# Клипы из .glb импортируются без повтора: бег играл один раз (0.7 с — «пара шагов»)
# и замирал в позе полёта. Включаем зацикливание у всех.
# Клипы плавания Swim_Fwd / Swim_Idle — из Universal Animation Library (Quaternius, CC0),
# Клипы бойца (Idle/Walk/Run/Swim_*) перенесены со скелета Mixamo на Rocketbox (tools/character/retarget_mixamo.py → survivor_clips.json)
func _add_json_clips(path: String) -> void:
	if anim == null or skel == null:
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var base: String = str(anim.get_node(anim.root_node).get_path_to(skel))
	var lib := anim.get_animation_library("")
	for cname in data.clips:
		if anim.has_animation(cname):
			continue          # свои клипы модели важнее (из json берётся только плавание)
		var c: Dictionary = data.clips[cname]
		var a := Animation.new()
		a.length = c.len
		a.loop_mode = Animation.LOOP_LINEAR
		var n: int = int(c.n)
		for bone in c.tracks:
			if bone.ends_with("_pos"):
				continue
			var ti := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(ti, NodePath(base + ":" + bone))
			var q: Array = c.tracks[bone]
			for i in n:
				a.rotation_track_insert_key(ti, float(i) / 30.0, Quaternion(q[i][0], q[i][1], q[i][2], q[i][3]))
		var hp := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(hp, NodePath(base + ":mixamorig_Hips"))
		var pos: Array = c.tracks["mixamorig_Hips_pos"]
		for i in n:
			a.position_track_insert_key(hp, float(i) / 30.0, Vector3(pos[i][0], pos[i][1], pos[i][2]))
		lib.add_animation(cname, a)

static func loop_all(ap: AnimationPlayer) -> void:
	if ap == null:
		return
	for n in ap.get_animation_list():
		ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR

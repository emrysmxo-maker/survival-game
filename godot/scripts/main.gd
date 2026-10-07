extends Node3D
# Главная сцена: мир, боец, оружие, зомби, эффекты, день/ночь, интерфейс, камера.

const CAM_ELEV_DEG := 46.8          # угол камеры над землёй (asin(54/74)), как в браузерной версии
const CAM_YAW_DEG := 45.0
const CAM_ELEV_MIN := 22.0          # наклон камеры: почти горизонт ... вид сверху
const CAM_ELEV_MAX := 82.0
const CAM_ELEV_SPEED := 60.0
const CAM_SIZE := 7.6               # метров по вертикали на экране (боец ~1/6 высоты экрана, как раньше)
const CAM_SIZE_MIN := 1.0           # приближение (вплотную к бойцу)
const CAM_SIZE_MAX := 16.0          # отдаление
const CAM_ROT_SPEED := 150.0        # °/с при полном отклонении джойстика камеры
const CAM_ZOOM_SPEED := 1.1         # скорость приближения (экспонента)

var world
var player
var weapon
var zombies
var effects
var daynight
var settings
var hud
var cam: Camera3D
var stick_l
var stick_r
var cam_h := 0.0
var cam_yaw := CAM_YAW_DEG
var cam_elev := CAM_ELEV_DEG
var cam_size := CAM_SIZE
var camctl
var water_fx
var _shot := ""
var _shot_frames := 0
var _test_script := ""
var _shot_at := 2.0
var _clock := 0.0
var _xray_t := 0.0
var _start := Vector2(4, 6)          # старт — Лагерь выживших
var _shots := 1
var _shot_i := 0
var _fixed_dt := 0.0

func _ready() -> void:
	WorldGen.init()
	daynight = load("res://scripts/daynight.gd").new()
	add_child(daynight)
	daynight.setup(self)
	world = load("res://scripts/world.gd").new()
	add_child(world)
	effects = load("res://scripts/effects.gd").new()
	add_child(effects)
	player = load("res://scripts/player.gd").new()
	player.world = world
	add_child(player)
	weapon = load("res://scripts/weapon.gd").new()
	weapon.player = player
	weapon.world = world
	add_child(weapon)
	effects.weapon = weapon
	var wfx = load("res://scripts/water_fx.gd").new()
	wfx.player = player
	add_child(wfx)
	water_fx = wfx
	zombies = load("res://scripts/zombies.gd").new()
	zombies.player = player
	zombies.world = world
	zombies.weapon = weapon
	zombies.effects = effects
	add_child(zombies)
	weapon.zombies = zombies

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAM_SIZE
	cam.near = 1.0
	cam.far = 200.0
	cam.rotation_degrees = Vector3(-CAM_ELEV_DEG, CAM_YAW_DEG, 0)
	add_child(cam)

	settings = load("res://scripts/settings.gd").new()
	settings.main = self
	add_child(settings)
	hud = load("res://scripts/hud.gd").new()
	hud.main = self
	add_child(hud)
	var ui := CanvasLayer.new()
	ui.layer = 0
	add_child(ui)
	stick_l = load("res://scripts/joystick.gd").new()
	stick_r = load("res://scripts/joystick.gd").new()
	stick_r.right_side = true
	ui.add_child(stick_l)
	camctl = load("res://scripts/camctl.gd").new()
	camctl.reset_view.connect(func():
		cam_yaw = CAM_YAW_DEG
		cam_elev = CAM_ELEV_DEG
		cam_size = CAM_SIZE)
	camctl.swiped.connect(func(d: Vector2):
		cam_yaw = fposmod(cam_yaw - d.x * 0.28, 360.0)
		cam_elev = clampf(cam_elev - d.y * 0.22, CAM_ELEV_MIN, CAM_ELEV_MAX))
	ui.add_child(camctl)
	var rects: Array = hud.ui_rects()
	camctl.blocked_rects = rects.duplicate()
	rects.append(func(): return camctl.rect())
	stick_l.blocked_rects = rects
	stick_r.blocked_rects = rects

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.substr(7)
			_shot_frames = 1
		if a.begins_with("--shots="):
			_shots = int(a.substr(8))
		if a.begins_with("--fixeddt="):
			_fixed_dt = float(a.substr(10))
		if a.begins_with("--at="):
			_shot_at = float(a.substr(5))
		if a.begins_with("--cam="):
			cam_size = float(a.substr(6))
		if a.begins_with("--tp="):
			var xy := a.substr(5).split(",")
			_start = Vector2(float(xy[0]), float(xy[1]))
		if a.begins_with("--camelev="):
			cam_elev = float(a.substr(10))
		if a.begins_with("--camyaw="):
			cam_yaw = float(a.substr(9))
		if a.begins_with("--time="):
			daynight.t = float(a.substr(7)); daynight.auto = false
		if a.begins_with("--test="):
			_test_script = a.substr(7)
	settings.load_saved()
	hud._refresh_q()
	teleport(_start)
	if OS.get_cmdline_user_args().has("--bigmap"):
		hud._open_big()

func teleport(t: Vector2) -> void:
	world.ensure_now(t, 2)
	player.set_tile(t)
	cam_h = player.global_position.y
	_follow(1.0)

func _follow(k: float) -> void:
	var p: Vector3 = player.global_position
	cam_h = lerpf(cam_h, p.y, k)
	# вплотную камера смотрит на корпус, а не на ступни (иначе голова уходит за кадр)
	var lift := 1.1 * (1.0 - smoothstep(1.3, 5.0, cam_size))
	var target := Vector3(p.x, cam_h + lift, p.z)
	cam.global_position = target + cam.global_transform.basis.z * 60.0

func _update_camera(dt: float) -> void:
	if camctl.zoom != 0.0:
		cam_size = clampf(cam_size * exp(camctl.zoom * CAM_ZOOM_SPEED * dt), CAM_SIZE_MIN, CAM_SIZE_MAX)
	if Input.is_key_pressed(KEY_Q): cam_yaw = fposmod(cam_yaw + 90.0 * dt, 360.0)
	if Input.is_key_pressed(KEY_E): cam_yaw = fposmod(cam_yaw - 90.0 * dt, 360.0)
	cam.rotation_degrees = Vector3(-cam_elev, cam_yaw, 0)
	cam.size = cam_size
	player.AIM_ELEV_K = sin(deg_to_rad(cam_elev))
	var vs := get_viewport().get_visible_rect().size
	var hw: float = cam_size * vs.x / maxf(vs.y, 1.0) * 0.5
	var hh: float = cam_size * 0.5 / maxf(sin(deg_to_rad(cam_elev)), 0.25)
	world.view_r = sqrt(hw * hw + hh * hh) / WorldGen.T + 2.0
	player.cam_yaw = deg_to_rad(cam_yaw)
	daynight.sun.directional_shadow_max_distance = clampf(roundf(cam_size * 3.2 / 6.0) * 6.0, 24.0, 60.0)

func _process_game(dt: float) -> void:
	_update_camera(dt)
	var move: Vector2 = stick_l.vec
	var kb := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if kb != Vector2.ZERO:
		move = kb.limit_length(1.0)
	# правая половина — только камера; целится и стреляет кнопка «ОГОНЬ» (тянуть — целиться в сторону)
	var aim_active: bool = camctl.fire_held
	var aim: Vector2 = camctl.fire_vec
	var fire: bool = camctl.fire_held
	if _test_script != "" and stick_r.active:      # проверки без экрана
		aim_active = true
		aim = stick_r.vec
		fire = stick_r.len_px > 18.0
	if camctl.fire_held and aim.length() < 0.3:
		var at = weapon.auto_target(true)
		if at == null:
			at = player.tiles_to_aim(Vector2(sin(player.yaw), cos(player.yaw)))
		aim = at
	elif not aim_active:
		var at2 = weapon.auto_target()
		if at2 != null:
			aim_active = true
			aim = at2
			fire = true
	player.step(dt, move, aim, aim_active, fire)
	if not player.swimming:
		effects.step(player, player.tile, dt, false)
	weapon.update_weapon(dt, player.firing)
	water_fx.update_fx(dt)
	zombies.update_zombies(dt)
	world.update_world(player.tile, cam)
	_xray_t -= dt
	if _xray_t <= 0.0:
		_xray_t = 0.1
		player.set_xray(world.occluded(player.global_position, 1.5, cam))
		for z in zombies.list:
			if not z.dead:
				var on: bool = world.occluded(z.node.global_position, 1.5, cam)
				if on != z.node.get_meta("xr", false):
					z.node.set_meta("xr", on)
					_set_xray_node(z.node, on)
	RenderingServer.global_shader_parameter_set("player_pos", player.global_position)
	RenderingServer.global_shader_parameter_set("sun_dir", daynight.sun.global_transform.basis.z)
	_follow(minf(1.0, 2.6 * dt))

func _process(dt_raw: float) -> void:
	var dt := minf(dt_raw, 0.05)      # всё считаем каждый кадр (145 fps), без шагов физики 60 Гц — иначе рывки
	if _fixed_dt > 0.0:
		dt = _fixed_dt
	_process_game(dt)
	if hud.due(dt):
		hud.update_hud(0.25, player.tile, world.ecosystem_at(player.tile), world.count_trees())
	if _test_script != "":
		_tt += dt
		load("res://scripts/devtest.gd").run(self, dt)
	_clock = Time.get_ticks_msec() / 1000.0
	if _shot != "" and _clock > _shot_at and _shot_frames > 0:
		var path := _shot if _shots <= 1 else _shot.replace(".png", "_%02d.png" % _shot_i)
		get_viewport().get_texture().get_image().save_png(path)
		_shot_i += 1
		if _shot_i >= _shots:
			_shot_frames = 0
			get_tree().quit()

var _tt := 0.0

func _set_xray_node(n: Node, on: bool) -> void:
	if n is GeometryInstance3D:
		n.set_instance_shader_parameter("xray_on", 1.0 if on else 0.0)
	for c in n.get_children():
		_set_xray_node(c, on)

extends Node3D
# Главная сцена: мир, боец, оружие, зомби, эффекты, день/ночь, интерфейс, камера.

const CAM_ELEV_DEG := 46.8          # угол камеры над землёй (asin(54/74)), как в браузерной версии
const CAM_YAW_DEG := 45.0
const CAM_ELEV_MIN := 22.0          # наклон камеры: почти горизонт ... вид сверху
const CAM_ELEV_MAX := 82.0
const CAM_ELEV_SPEED := 60.0
const CAM_SIZE := 7.6               # метров по вертикали на экране (боец ~1/6 высоты экрана, как раньше)
const CAM_SIZE_MIN := 3.2           # приближение
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
var _shot := ""
var _shot_frames := 0
var _test_script := ""
var _shot_at := 2.0
var _clock := 0.0
var _xray_t := 0.0
var _shots := 1
var _shot_i := 0
var _fixed_dt := 0.0

func _ready() -> void:
	RenderingServer.global_shader_parameter_set("gl_compat", RenderingServer.get_rendering_device() == null)
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
	teleport(Vector2(10, 10))

func teleport(t: Vector2) -> void:
	world.ensure_now(t, 2)
	player.set_tile(t)
	cam_h = player.global_position.y
	_follow(1.0)

func _follow(k: float) -> void:
	var p: Vector3 = player.global_position
	cam_h = lerpf(cam_h, p.y, k)
	var target := Vector3(p.x, cam_h, p.z)
	cam.global_position = target + cam.global_transform.basis.z * 60.0

func _update_camera(dt: float) -> void:
	if camctl.zoom != 0.0:
		cam_size = clampf(cam_size * exp(camctl.zoom * CAM_ZOOM_SPEED * dt), CAM_SIZE_MIN, CAM_SIZE_MAX)
	if Input.is_key_pressed(KEY_Q): cam_yaw = fposmod(cam_yaw + 90.0 * dt, 360.0)
	if Input.is_key_pressed(KEY_E): cam_yaw = fposmod(cam_yaw - 90.0 * dt, 360.0)
	cam.rotation_degrees = Vector3(-cam_elev, cam_yaw, 0)
	cam.size = cam_size
	player.AIM_ELEV_K = sin(deg_to_rad(cam_elev))
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
	effects.step(player, player.tile, dt, false)
	weapon.update_weapon(dt, player.firing)
	zombies.update_zombies(dt)
	world.update_world(player.tile, cam)
	_xray_t -= dt
	if _xray_t <= 0.0:
		_xray_t = 0.1
		player.set_xray(world.occluded(player.global_position, 1.5, cam))
		for z in zombies.list:
			if not z.dead:
				_set_xray_node(z.node, world.occluded(z.node.global_position, 1.5, cam))
	RenderingServer.global_shader_parameter_set("cam_back", cam.global_transform.basis.z)
	RenderingServer.global_shader_parameter_set("player_pos", player.global_position)
	_follow(minf(1.0, 2.6 * dt))

var _fo_n := 0
func _process(dt_raw: float) -> void:
	var dt := minf(dt_raw, 0.05)      # всё считаем каждый кадр (145 fps), без шагов физики 60 Гц — иначе рывки
	if _fixed_dt > 0.0:
		dt = _fixed_dt
	_process_game(dt)
	if _test_script == "run" and Engine.get_process_frames() % 10 == 0 and _fo_n < 40:
		_fo_n += 1
		var an = player.anim
		print("ANIM t=", snappedf(_clock, 0.1), " name=", an.current_animation, " playing=", an.is_playing(), " pos=", snappedf(an.current_animation_position, 0.01), " loop=", an.get_animation(an.current_animation).loop_mode if an.current_animation != "" else -1, " foot=", snappedf(player.foot_offset(), 0.001))
	if hud.due(dt):
		hud.update_hud(0.25, player.tile, world.ecosystem_at(player.tile), world.count_trees())
	if _test_script != "":
		_run_test(dt)
	_clock = Time.get_ticks_msec() / 1000.0
	if _shot != "" and _clock > _shot_at and _shot_frames > 0:
		var path := _shot if _shots <= 1 else _shot.replace(".png", "_%02d.png" % _shot_i)
		get_viewport().get_texture().get_image().save_png(path)
		_shot_i += 1
		if _shot_i >= _shots:
			_shot_frames = 0
			get_tree().quit()

# --- проверки без экрана (запуск с --test=...) ---
var _tt := 0.0
func _run_test(dt: float) -> void:
	_tt += dt
	match _test_script:
		"run":
			stick_l.active = true
			stick_l.vec = Vector2(0, -1)
		"fireback":
			stick_l.vec = Vector2(0, -1)
			if _tt > 0.5:
				stick_r.active = true
				stick_r.vec = Vector2(0.6, 0.8)
				stick_r.len_px = 60.0
			if _tt > 0.3 and zombies.list.is_empty():
				zombies.spawn()
		"zombie":
			if zombies.list.is_empty():
				zombies.spawn(); zombies.spawn()
				zombies.list[0].tile = player.tile + Vector2(3, 1)
				zombies.list[1].tile = player.tile + Vector2(-1, 3)
			weapon.auto = _tt > 1.0
		"behind":
			if not has_meta("done"):
				set_meta("done", true)
				# встать за ближайшее дерево (дальше от камеры)
				var best = null
				var bd := 1e9
				for o in world.obstacles_near(player.tile):
					if o.tree:
						var d: float = Vector2(o.x, o.y).distance_to(player.tile)
						if d < bd:
							bd = d
							best = o
				if best != null:
					var back: Vector3 = cam.global_transform.basis.z
					var bt := Vector2(back.x, back.z).normalized()
					player.set_tile(Vector2(best.x, best.y) - bt * 1.6)
		"runaim", "runback":
			stick_l.active = true
			stick_l.vec = Vector2(0, -1)
			stick_r.active = true
			stick_r.vec = Vector2(1, 0) if _test_script == "runaim" else Vector2(0.2, 1)
			stick_r.len_px = 60.0
			if Engine.get_process_frames() % 20 == 0 and _tt > 1.0:
				var bd: Vector3 = player.barrel_dir()
				print("RUNAIM t=", snappedf(_tt, 0.1), " legs=", snappedf(rad_to_deg(player.yaw), 1), " move=", snappedf(rad_to_deg(WorldGen_yaw(player.move_dir)), 1), " aim=", snappedf(rad_to_deg(player.aim_yaw), 1), " twist=", snappedf(rad_to_deg(player.aim_local), 1), " barrel=", snappedf(rad_to_deg(atan2(bd.x, bd.z)), 1), " back=", player.backpedal, " anim=", player.anim.current_animation, " spd=", snappedf(player.anim.speed_scale, 0.01), " bullets=", weapon.bullets.size())
		"aim":
			stick_r.active = true
			stick_r.vec = Vector2(1, 0.3)
			stick_r.len_px = 10.0

func _set_xray_node(n: Node, on: bool) -> void:
	if n is GeometryInstance3D:
		n.set_instance_shader_parameter("xray_on", 1.0 if on else 0.0)
	for c in n.get_children():
		_set_xray_node(c, on)

func WorldGen_yaw(d: Vector2) -> float:
	return atan2(d.x, d.y)

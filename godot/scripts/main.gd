extends Node3D
# Главная сцена: мир, боец, оружие, зомби, эффекты, день/ночь, интерфейс, камера.

const CAM_ELEV_DEG := 46.8          # угол камеры над землёй (asin(54/74)), как в браузерной версии
const CAM_YAW_DEG := 45.0
const CAM_SIZE := 7.6               # метров по вертикали на экране (боец ~1/6 высоты экрана, как раньше)

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
var _shot := ""
var _shot_frames := 0
var _test_script := ""
var _shot_at := 2.0
var _clock := 0.0

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
	ui.add_child(stick_r)
	var rects: Array = hud.ui_rects()
	stick_l.blocked_rects = rects
	stick_r.blocked_rects = rects

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.substr(7)
			_shot_frames = 1
		if a.begins_with("--at="):
			_shot_at = float(a.substr(5))
		if a.begins_with("--cam="):
			cam.size = float(a.substr(6))
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

func _process_game(dt: float) -> void:
	var move: Vector2 = stick_l.vec
	var kb := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if kb != Vector2.ZERO:
		move = kb.limit_length(1.0)
	var aim_active: bool = stick_r.active
	var aim: Vector2 = stick_r.vec
	var fire: bool = stick_r.active and stick_r.len_px > 18.0
	if not aim_active:
		var at = weapon.auto_target()
		if at != null:
			aim_active = true
			aim = at
			fire = true
	player.step(dt, move, aim, aim_active, fire)
	effects.step(player, player.tile, dt, false)
	weapon.update_weapon(dt, player.firing)
	zombies.update_zombies(dt)
	world.update_world(player.tile, cam)
	RenderingServer.global_shader_parameter_set("cam_back", cam.global_transform.basis.z)
	RenderingServer.global_shader_parameter_set("player_pos", player.global_position)
	_follow(minf(1.0, 2.6 * dt))

var _fo_n := 0
func _process(dt_raw: float) -> void:
	var dt := minf(dt_raw, 0.05)      # всё считаем каждый кадр (145 fps), без шагов физики 60 Гц — иначе рывки
	_process_game(dt)
	if _test_script == "run" and Engine.get_process_frames() % 20 == 0 and _fo_n < 12:
		_fo_n += 1
		print("FOOT ", player.foot_offset(), " moving=", player.moving, " anim=", player._cur_anim)
	hud.update_hud(dt, player.tile, world.ecosystem_at(player.tile), world.count_trees())
	if _test_script != "":
		_run_test(dt)
	_clock = Time.get_ticks_msec() / 1000.0
	if _shot != "" and _clock > _shot_at and _shot_frames > 0:
		_shot_frames = 0
		if true:
			get_viewport().get_texture().get_image().save_png(_shot)
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
		"aim":
			stick_r.active = true
			stick_r.vec = Vector2(1, 0.3)
			stick_r.len_px = 10.0

extends Node3D
# Сцена собирается кодом: земля, свет, камера, боец, деревья, джойстик.
# Единицы — метры (в браузерной версии 1 тайл = 1.39 м).

const CAMERA_ELEV_DEG := 46.8         # угол камеры над землёй: asin(54/74), как в браузерной версии
const CAMERA_YAW_DEG := 45.0          # ромбовидная изометрия
const VIEW_HEIGHT_M := 9.0           # сколько метров по вертикали видно на экране
const PLAYER_SPEED := 4.0             # м/с (2.85 тайла/с)
const TREE_COUNT := 260
const WORLD_R := 150.0

var cam: Camera3D
var player: Node3D
var anim: AnimationPlayer
var joy
var _cur_anim := ""
var _shot_frames := -1

func _ready() -> void:
	_make_env()
	_make_ground()
	_make_trees()
	_make_player()
	_make_camera()
	_make_ui()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_frames = 90

func _make_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.07, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.55)
	env.ambient_light_energy = 0.55
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -45, 0)   # солнце сверху-слева экрана
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

func _make_ground() -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(WORLD_R * 4, WORLD_R * 4)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/ground/grass.jpg")
	mat.uv1_scale = Vector3(WORLD_R * 4 / 6.0, WORLD_R * 4 / 6.0, 1)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.albedo_color = Color(0.62, 0.66, 0.55)
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)

func _make_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var texs: Array = []
	for i in 12:
		var n := "res://assets/trees/%02d_" % i
		for f in DirAccess.get_files_at("res://assets/trees"):
			if f.begins_with("%02d_" % i) and f.ends_with(".png"):
				texs.append(load("res://assets/trees/" + f))
	if texs.is_empty():
		return
	for i in TREE_COUNT:
		var p := Vector2(rng.randf_range(-WORLD_R, WORLD_R), rng.randf_range(-WORLD_R, WORLD_R))
		if p.length() < 4.0:
			continue
		var tex: Texture2D = texs[rng.randi() % texs.size()]
		var s := Sprite3D.new()
		s.texture = tex
		var h_m := rng.randf_range(5.0, 8.0)
		s.pixel_size = h_m / tex.get_height()
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		s.shaded = false
		s.centered = true
		s.offset = Vector2(0, tex.get_height() * 0.5)   # основание ствола — в точке на земле
		s.position = Vector3(p.x, 0, p.y)
		add_child(s)

func _make_player() -> void:
	player = Node3D.new()
	add_child(player)
	var scn: PackedScene = load("res://assets/character/Soldier.glb")
	if scn:
		var model := scn.instantiate()
		player.add_child(model)
		anim = _find_anim(model)
		if anim:
			print("ANIMS: ", anim.get_animation_list())
	else:
		push_warning("Soldier.glb не загрузился")

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r:
			return r
	return null

func _make_camera() -> void:
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = VIEW_HEIGHT_M
	cam.near = 0.5
	cam.far = 300.0
	cam.rotation_degrees = Vector3(-CAMERA_ELEV_DEG, CAMERA_YAW_DEG, 0)
	add_child(cam)
	_follow(1.0)

func _follow(k: float) -> void:
	var target := player.global_position
	var back := cam.global_transform.basis.z
	cam.global_position = cam.global_position.lerp(target + back * 60.0, k)

func _make_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	joy = preload("res://scripts/joystick.gd").new()
	layer.add_child(joy)

func _input_dir() -> Vector2:
	var v: Vector2 = joy.vec
	var k := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if k != Vector2.ZERO:
		v = k
	return v

func _physics_process(dt: float) -> void:
	var v := _input_dir()
	var moving := v.length() > 0.05
	if moving:
		# экранный «вверх» = вперёд по взгляду камеры
		var right := cam.global_transform.basis.x
		right.y = 0
		right = right.normalized()
		var fwd := -cam.global_transform.basis.z
		fwd.y = 0
		fwd = fwd.normalized()
		var dir: Vector3 = (right * v.x + fwd * (-v.y)).limit_length(1.0)
		player.global_position += dir * PLAYER_SPEED * dt * minf(1.0, v.length() * 1.2)
		var want := atan2(dir.x, dir.z)
		player.rotation.y = lerp_angle(player.rotation.y, want, minf(1.0, 14.0 * dt))
	_play("Run" if moving else "Idle")
	_follow(minf(1.0, 12.0 * dt))

func _play(name: String) -> void:
	if anim == null or name == _cur_anim:
		return
	if anim.has_animation(name):
		anim.play(name, 0.15)
		_cur_anim = name

func _process(_dt: float) -> void:
	if _shot_frames > 0:
		_shot_frames -= 1
		if _shot_frames == 0:
			var img := get_viewport().get_texture().get_image()
			img.save_png("/tmp/claude-0/godot/shot.png")
			get_tree().quit()

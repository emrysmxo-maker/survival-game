extends Node3D
# Главная сцена: мир, день/ночь, интерфейс и свободная камера (бойца нет — свободный обзор карты).

const CAM_ELEV_DEG := 46.8          # угол камеры над землёй
const CAM_YAW_DEG := 45.0
const CAM_ELEV_MIN := 22.0          # наклон камеры: почти горизонт ... вид сверху
const CAM_ELEV_MAX := 82.0
const CAM_SIZE := 18.0              # метров по вертикали на экране (деревья теперь 15–25 м)
const CAM_SIZE_MIN := 2.0           # приближение
const CAM_SIZE_MAX := 60.0          # отдаление
const CAM_ZOOM_SPEED := 1.1         # кнопки −/+ (экспонента)
const KEY_PAN := 12.0               # м/с при стрелках/WASD (на ПК)
const LOD1_SIZE := 24.0             # до этого приближения деревья полные, дальше — проще
const LOD2_SIZE := 40.0             # дальше — силуэты

var world
var props
var weather
var ambience
var daynight
var settings
var hud
var cam: Camera3D
var camctl
var focus := Vector2(4, 6)          # куда смотрит камера (тайлы); старт — Лагерь выживших
var cam_h := 0.0
var cam_yaw := CAM_YAW_DEG
var cam_elev := CAM_ELEV_DEG
var cam_size := CAM_SIZE

func _ready() -> void:
	WorldGen.init()
	daynight = load("res://scripts/daynight.gd").new()
	add_child(daynight)
	daynight.setup(self)
	world = load("res://scripts/world.gd").new()
	add_child(world)
	props = load("res://scripts/props.gd").new()
	add_child(props)                                        # дома, машины, заборы, следы карантина
	var wth = load("res://scripts/weather.gd").new()
	wth.main = self
	add_child(wth)                                          # дождь, туман в низинах, ветер, мокрая земля
	weather = wth

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAM_SIZE
	cam.near = 1.0
	cam.far = 800.0
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
	camctl = load("res://scripts/camctl.gd").new()
	camctl.blocked_rects = hud.ui_rects()
	camctl.panned.connect(_pan)
	camctl.pinched.connect(func(k: float): cam_size = clampf(cam_size / k, CAM_SIZE_MIN, CAM_SIZE_MAX))
	camctl.twisted.connect(func(a: float): cam_yaw = fposmod(cam_yaw + rad_to_deg(a), 360.0))
	camctl.tilted.connect(func(dy: float): cam_elev = clampf(cam_elev + dy * 0.2, CAM_ELEV_MIN, CAM_ELEV_MAX))
	ui.add_child(camctl)

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam="):
			cam_size = float(a.substr(6))
		if a.begins_with("--tp="):
			var xy := a.substr(5).split(",")
			focus = Vector2(float(xy[0]), float(xy[1]))
		if a.begins_with("--camelev="):
			cam_elev = float(a.substr(10))
		if a.begins_with("--camyaw="):
			cam_yaw = float(a.substr(9))
		if a.begins_with("--time="):
			daynight.t = float(a.substr(7)); daynight.auto = false
	settings.load_saved()
	ambience = load("res://scripts/ambience.gd").new()
	ambience.main = self
	ambience.on = settings.sound
	add_child(ambience)                                     # ветер, дождь, птицы, сверчки, вороны
	var crows = load("res://scripts/crows.gd").new()
	crows.main = self
	add_child(crows)                                        # стаи ворон над полями
	var clouds = load("res://scripts/clouds.gd").new()
	clouds.main = self
	add_child(clouds)                                       # живые облака — видны при отдалении камеры
	hud._refresh_q()
	# трава/кусты раздвигаются у ног бойца — бойца нет, точка вдали
	RenderingServer.global_shader_parameter_set("player_pos", Vector3(1e6, 0.0, 1e6))
	teleport(focus)
	if OS.get_cmdline_user_args().has("--bigmap"):
		hud._open_big()
	var args := OS.get_cmdline_user_args()
	if args.has("--intro") or (not FileAccess.file_exists("user://intro_done") and not _has_prefix(args, "--shot=") and not args.has("--nointro")):
		start_intro.call_deferred()                         # заставка «как всё началось» — при первом входе
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):                        # снимки без телефона (scripts/shot.gd)
			var sh = load("res://scripts/shot.gd").new()
			sh.main = self
			add_child(sh)

func _has_prefix(args: PackedStringArray, pre: String) -> bool:
	for a in args:
		if a.begins_with(pre):
			return true
	return false

var intro = null
func start_intro() -> void:
	if intro != null or props.story.is_empty() or not ResourceLoader.exists("res://assets/character/hero.glb"):
		return
	intro = load("res://scripts/intro.gd").new()
	intro.main = self
	add_child(intro)
	hud.visible = false
	intro.finished.connect(func():
		intro = null
		hud.visible = true)

func teleport(t: Vector2) -> void:
	var lim := WorldGen.MAP_RADIUS - 5.0
	focus = t.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	world.ensure_now(focus, 2)
	cam_h = WorldGen.height_m(focus.x, focus.y)
	_place_camera(1.0)

# сдвиг пальцем (пиксели экрана): карта едет за пальцем
func _pan(d: Vector2) -> void:
	var vh := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var mpp := cam_size / vh                                   # метров на пиксель (по вертикали экрана)
	var b := cam.global_transform.basis
	var right := Vector3(b.x.x, 0.0, b.x.z).normalized()
	var fwd := Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	var s := maxf(sin(deg_to_rad(cam_elev)), 0.25)              # вертикаль экрана на земле длиннее в 1/sin раз
	var m: Vector3 = -right * d.x * mpp + fwd * d.y * mpp / s
	var lim := WorldGen.MAP_RADIUS - 5.0
	focus = (focus + Vector2(m.x, m.z) / WorldGen.T).clamp(Vector2(-lim, -lim), Vector2(lim, lim))

func _place_camera(k: float) -> void:
	cam_h = lerpf(cam_h, WorldGen.height_m(focus.x, focus.y), k)
	var target := Vector3(focus.x * WorldGen.T, cam_h, focus.y * WorldGen.T)
	cam.global_position = target + cam.global_transform.basis.z * 300.0   # далеко: орто-вид тот же, а облака (clouds.gd) не срезает ближняя граница

func _update_camera(dt: float) -> void:
	if camctl.zoom != 0.0:
		cam_size = clampf(cam_size * exp(camctl.zoom * CAM_ZOOM_SPEED * dt), CAM_SIZE_MIN, CAM_SIZE_MAX)
	if Input.is_key_pressed(KEY_Q): cam_yaw = fposmod(cam_yaw + 90.0 * dt, 360.0)
	if Input.is_key_pressed(KEY_E): cam_yaw = fposmod(cam_yaw - 90.0 * dt, 360.0)
	var kb := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if kb != Vector2.ZERO:
		var vh := maxf(get_viewport().get_visible_rect().size.y, 1.0)
		_pan(-kb * KEY_PAN * dt * vh / cam_size)
	cam.rotation_degrees = Vector3(-cam_elev, cam_yaw, 0)
	cam.size = cam_size
	# деревья проще при отдалении (орто-камера: мельчают от приближения, а не от расстояния)
	var want := (0 if cam_size <= LOD1_SIZE else (1 if cam_size <= LOD2_SIZE else 2))
	if settings.level == 0:
		want = mini(want + 1, 2)
	if want != world.lod:
		world.set_lod(want)
	var vs := get_viewport().get_visible_rect().size
	var hw: float = cam_size * vs.x / maxf(vs.y, 1.0) * 0.5
	var hh: float = cam_size * 0.5 / maxf(sin(deg_to_rad(cam_elev)), 0.25)
	world.view_r = sqrt(hw * hw + hh * hh) / WorldGen.T + 2.0
	daynight.sun.directional_shadow_max_distance = clampf(roundf(cam_size * 3.2 / 6.0) * 6.0, 24.0, 60.0)

func _process(dt_raw: float) -> void:
	var dt := minf(dt_raw, 0.05)
	_update_camera(dt)
	world.update_world(focus, cam)
	RenderingServer.global_shader_parameter_set("sun_dir", daynight.sun.global_transform.basis.z)
	props.set_night(daynight.night)
	_place_camera(minf(1.0, 6.0 * dt))
	if hud.due(dt):
		hud.update_hud(0.25, focus, world.ecosystem_at(focus), world.count_trees())

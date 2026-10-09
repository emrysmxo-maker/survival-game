extends Node3D
# Заставка «Как всё началось» (~2,5 мин, медленно). Утро в доме у озера: герой спит, сидит на краю кровати, встаёт,
# потягивается, идёт на кухню умыться, смотрит в окно на озеро, выходит на улицу, садится на стул на веранде,
# достаёт телефон и читает новости — утечка в НИИ «Вектор-7», власти просят не выходить из домов. Сирена —
# он бежит к сараю, в деревне паника (жители бегут по домам, вертолёт, истребители), спускается по лестнице в бункер.
# «Прошёл месяц…» — поднимается по лестнице, выходит: тишина, никого.
# Движения героя — мокап живого человека (CMU), клипы и их числа — tools/character/hero_mocap.py → hero.glb.
# Точки — props.story (props.gd), модели — props.glb. Запуск: при первом входе в игру, «▶ Заставка» (⚙), --intro.
# Проверка без телефона: --intro --introshot=<папка>  → кадр каждые 2 с в JPG, в конце игра закрывается.
signal finished
var main
var props
var S: Dictionary
var hero: Node3D
var anim: AnimationPlayer
var skel: Skeleton3D
var phone_mi: MeshInstance3D
var lid: Node3D
var cam: Camera3D
var ui: CanvasLayer
var fade: ColorRect
var sub: Label
var title: Label
var phone_ui: PanelContainer
var news: VBoxContainer
var skip_btn: Button
var npcs: Array = []
var air: Array = []                    # [узел, скорость (м/с), направление, вращать_винт]
var hidden: Array = []                  # спрятанные крыши
var skipping := false
var jump_to := ""                       # --introfrom=<метка>: всё до метки проматывается мгновенно (проверка кадрами)
var cam_a := Vector3.ZERO
var cam_b := Vector3.ZERO
var look_a := Vector3.ZERO
var look_b := Vector3.ZERO
var cam_t := 0.0
var cam_len := 1.0
var follow := false                     # камера идёт за героем: смещение follow_off, взгляд — на грудь
var follow_off := Vector3.ZERO
var shot_dir := ""
var shot_n := 0
var t_all := 0.0
var _rng := RandomNumberGenerator.new()
# звук: сирена, вертолёт, самолёты, будильник, вода — синтез
var _pb: AudioStreamGeneratorPlayback
var siren := 0.0
var heli_v := 0.0
var jet_v := 0.0
var alarm_v := 0.0
var water_v := 0.0
var _ph := [0.0, 0.0, 0.0]
var _lp := 0.0
var _wl := 0.0
var _st := 0.0
const RATE := 16000.0
const T := WorldGen.T
# числа клипов (hero_clips.json из hero.py): скорость шага м/с, сдвиг таза в конце клипа (м, вперёд +), вертикаль лестницы
const SPEED := {"Walk": 1.518, "WalkSlow": 1.002, "Run": 3.761}
const MOVE := {"StandUp": 0.433, "SitDown": -0.376}
const CLIMB_DOWN_V := 0.228
const CLIMB_UP_V := 0.12
const SLEEP_HIPS := Vector3(0.0, 0.0, 0.193)         # таз и голова в первом кадре Sleep (Blender, м) — из hero_clips.json
const SLEEP_HEAD := Vector3(0.334, 0.467, 0.218)

func _ready() -> void:
	_rng.seed = 11
	props = main.props
	S = props.story
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--introshot="):
			shot_dir = a.substr(12)
			DirAccess.make_dir_recursive_absolute(shot_dir)
		if a.begins_with("--introfrom="):
			jump_to = a.substr(12)
			skipping = true
	_build()
	_run()

# ---------- построение ----------
func w3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x * T, y, p.y * T)
func gh(p: Vector2) -> float:
	return WorldGen.height_m(p.x, p.y)
func yaw_to(d: Vector2) -> float:                      # лицом (+Z модели) в сторону d (тайлы)
	return atan2(d.x, d.y)
func L(x: float, y: float) -> Vector2:                 # точка дома (метры модели: +X вправо, +Y к озеру) → тайлы
	return S.pt.call(x, y)
func SL(x: float, y: float) -> Vector2:                # точка сарая
	return S.pt.call(9.0 + x, -1.0 + y)
func ld(dx: float, dy: float) -> Vector2:              # направление в осях дома → тайлы
	return (S.u as Vector2) * dx - (S.f as Vector2) * dy
func ld3(dx: float, dy: float) -> Vector3:             # то же в метрах мира
	var v := ld(dx, dy)
	return Vector3(v.x, 0, v.y)
func local(p: Vector2) -> Vector2:                     # тайлы → метры модели дома
	var d: Vector2 = (p - (S.c as Vector2)) * T
	return Vector2(d.dot(S.u), -d.dot(S.f))
func tile_of(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z) / T

func floor_y(p: Vector2) -> float:
	# высота пола под ногами: дом, веранда, ступени к воде, сарай, иначе земля
	var q := local(p)
	var hy: float = S.house_y
	if absf(q.x) < 4.5 and absf(q.y) < 4.0:
		return hy + 0.64
	if absf(q.x) < 4.7 and q.y >= 4.0 and q.y <= 7.2:
		return hy + 0.6
	if absf(q.x) < 0.95 and q.y > 7.2 and q.y < 8.5:
		return lerpf(hy + 0.6, gh(p), (q.y - 7.2) / 1.3)
	if absf(q.x - 9.0) < 2.0 and absf(q.y + 1.0) < 1.7:
		return (S.shed_y as float) + 0.35 + 0.02
	return gh(p)

func _mesh(name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = props._meshes.get(name)
	return mi

func _build() -> void:
	var hs: PackedScene = load("res://assets/character/hero.glb")
	hero = hs.instantiate()
	add_child(hero)
	anim = hero.find_child("AnimationPlayer", true, false)
	skel = _find_skel(hero)
	for n in ["Idle", "Walk", "WalkSlow", "Run", "Sleep", "SitIdle", "PhoneRead", "SitPhoneRead", "ClimbDown", "ClimbUp"]:
		if anim and anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	if skel:
		var att := BoneAttachment3D.new()
		att.bone_name = "LeftHand"
		skel.add_child(att)
		phone_mi = _mesh("phone")
		phone_mi.position = Vector3(0.0, 0.09, 0.03)
		phone_mi.rotation_degrees = Vector3(90, 0, 0)
		phone_mi.visible = false
		att.add_child(phone_mi)
	# крышка люка в сарае (петля по оси X)
	lid = Node3D.new()
	add_child(lid)
	lid.position = w3(S.lid, S.shed_y + 0.35 + 0.16 + 0.004)
	lid.rotation.y = S.th
	var lm := _mesh("bunker_lid")
	lid.add_child(lm)
	# жители (тот же человек, рост чуть разный) — бегут по домам в деревне
	var vc := Vector2(WorldGen.FEATURES["village"].x, WorldGen.FEATURES["village"].y)
	var plots: Array = props._plots.filter(func(q): return (q[0] as Vector2).distance_to(vc) < 60.0)
	plots.sort_custom(func(a, b): return (a[0] as Vector2).distance_to(vc) < (b[0] as Vector2).distance_to(vc))
	for i in mini(7, plots.size()):
		var q: Array = plots[i]
		var f := Vector2(sin(q[1]), cos(q[1]))
		var a: Vector2 = q[0] + f * (float(q[3]) + 6.0) + Vector2(f.y, -f.x) * _rng.randf_range(-6, 6)
		var b: Vector2 = q[0] + f * (float(q[3]) * 0.3)
		var npc: Node3D = hs.instantiate()
		npc.scale = Vector3.ONE * _rng.randf_range(0.93, 1.05)
		npc.visible = false
		add_child(npc)
		npcs.append([npc, a, b, _rng.randf_range(0.0, 0.7)])
	cam = Camera3D.new()
	cam.fov = 48.0
	cam.near = 0.05
	cam.far = 700.0
	add_child(cam)
	cam.make_current()
	_ui()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.3
	var pl := AudioStreamPlayer.new()
	pl.stream = gen
	pl.volume_db = -4.0
	add_child(pl)
	pl.play()
	_pb = pl.get_stream_playback()

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null

func _ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 20
	add_child(ui)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(fade)
	sub = Label.new()
	sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sub.position = Vector2(-560, -120)
	sub.size = Vector2(1120, 70)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	sub.add_theme_font_size_override("font_size", 30)
	sub.add_theme_color_override("font_color", Color(1, 1, 0.94))
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	sub.add_theme_constant_override("outline_size", 8)
	ui.add_child(sub)
	title = Label.new()
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	title.modulate.a = 0.0
	ui.add_child(title)
	# экран телефона: лента новостей (справа, герой виден слева)
	phone_ui = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.97, 0.97, 0.98)
	st.set_corner_radius_all(26)
	st.border_color = Color(0.08, 0.08, 0.09)
	st.set_border_width_all(14)
	st.content_margin_left = 24; st.content_margin_right = 24; st.content_margin_top = 30; st.content_margin_bottom = 30
	phone_ui.add_theme_stylebox_override("panel", st)
	phone_ui.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	phone_ui.position = Vector2(-500, -330)
	phone_ui.custom_minimum_size = Vector2(420, 660)
	phone_ui.visible = false
	ui.add_child(phone_ui)
	news = VBoxContainer.new()
	news.add_theme_constant_override("separation", 14)
	phone_ui.add_child(news)
	skip_btn = Button.new()
	skip_btn.text = "Пропустить ▶"
	skip_btn.add_theme_font_size_override("font_size", 22)
	skip_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip_btn.position = Vector2(-230, 20)
	skip_btn.size = Vector2(200, 52)
	skip_btn.pressed.connect(func(): skipping = true)
	ui.add_child(skip_btn)

func _news_item(head: String, body: String, col: Color) -> void:
	var v := VBoxContainer.new()
	var h := Label.new()
	h.text = head
	h.autowrap_mode = TextServer.AUTOWRAP_WORD
	h.custom_minimum_size = Vector2(360, 0)
	h.add_theme_font_size_override("font_size", 22)
	h.add_theme_color_override("font_color", col)
	v.add_child(h)
	var b := Label.new()
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD
	b.custom_minimum_size = Vector2(360, 0)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", Color(0.25, 0.25, 0.28))
	v.add_child(b)
	v.modulate.a = 0.0
	news.add_child(v)
	news.move_child(v, 0)
	create_tween().tween_property(v, "modulate:a", 1.0, 0.6)

# ---------- управление ----------
func _wait(s: float) -> void:
	var e := 0.0
	while e < s and not skipping:
		await get_tree().process_frame
		e += get_process_delta_time()

func _mark(name: String) -> void:
	if name == jump_to:
		skipping = false
		jump_to = ""

func _fade(to: float, s: float) -> void:
	if skipping:
		fade.color.a = to
		return
	var tw := create_tween()
	tw.tween_property(fade, "color:a", to, s)
	await _wait(s)

func _say(text: String) -> void:
	sub.text = text

func _shot(a: Vector3, b: Vector3, la: Vector3, lb: Vector3, length: float) -> void:
	follow = false
	cam_a = a; cam_b = b; look_a = la; look_b = lb; cam_t = 0.0; cam_len = maxf(length, 0.01)
	main.focus = Vector2(lb.x, lb.z) / T                       # мир (лес, трава) подгружается у кадра, а не у точки игры
	main.world.ensure_now(main.focus, 2)
	_cam_update()

func _follow(off: Vector3) -> void:
	follow = true
	follow_off = off
	cam.global_position = hero.global_position + off
	cam.look_at(hero.global_position + Vector3.UP * 1.0, Vector3.UP)

func _cam_update() -> void:
	if follow:
		var want := hero.global_position + follow_off
		cam.global_position = cam.global_position.lerp(want, 0.04)
		cam.look_at(hero.global_position + Vector3.UP * 1.0, Vector3.UP)
		return
	var k := clampf(cam_t / cam_len, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	cam.global_position = cam_a.lerp(cam_b, k)
	var lt := look_a.lerp(look_b, k)
	if cam.global_position.distance_to(lt) > 0.01:
		cam.look_at(lt, Vector3.UP)

func _play(n: String, blend := 0.3, speed := 1.0) -> void:
	if anim and anim.has_animation(n):
		anim.play(n, blend, speed)

func _clip_len(n: String) -> float:
	return anim.get_animation(n).length if anim and anim.has_animation(n) else 1.0

func _act(n: String, blend := 0.3, speed := 1.0) -> void:
	# разовый клип до конца; сдвиг таза из записи (встал, сел) переносится в узел героя
	_play(n, blend, speed)
	await _wait(maxf(_clip_len(n) / speed - 0.05, 0.0))
	if MOVE.has(n):
		var fw := Vector3(sin(hero.rotation.y), 0, cos(hero.rotation.y))
		hero.global_position += fw * float(MOVE[n])

func _place(p: Vector2, y: float, yaw: float) -> void:
	hero.global_position = w3(p, y)
	hero.rotation = Vector3(0, yaw, 0)

func _turn(d: Vector2, s := 0.6) -> void:
	# плавный поворот на месте лицом в сторону d (тайлы)
	var a0 := hero.rotation.y
	var a1 := a0 + wrapf(yaw_to(d) - a0, -PI, PI)
	var e := 0.0
	while e < s and not skipping:
		await get_tree().process_frame
		e += get_process_delta_time()
		var k := clampf(e / s, 0.0, 1.0)
		hero.rotation.y = lerpf(a0, a1, k * k * (3.0 - 2.0 * k))
	hero.rotation.y = a1

func _move(path: Array, clip: String, blend := 0.35) -> void:
	# пройти по точкам (тайлы) со скоростью клипа; корпус плавно доворачивает на следующий отрезок
	var speed: float = SPEED.get(clip, 1.0)
	_play(clip, blend)
	for i in range(1, path.size()):
		var a: Vector2 = path[i - 1]
		var b: Vector2 = path[i]
		var len_m := a.distance_to(b) * T
		if len_m < 0.01:
			continue
		var tt := len_m / speed
		var want := yaw_to(b - a)
		var e := 0.0
		while e < tt and not skipping:
			await get_tree().process_frame
			var dt := get_process_delta_time()
			e += dt
			var p := a.lerp(b, clampf(e / tt, 0.0, 1.0))
			hero.global_position = w3(p, floor_y(p))
			hero.rotation.y += wrapf(want - hero.rotation.y, -PI, PI) * minf(1.0, dt * 7.0)
		if skipping:
			hero.global_position = w3(b, floor_y(b))
			hero.rotation.y = want

func _hide_roofs(models: Array) -> void:
	for c in props.get_children():
		for m in models:
			if str(c.name).begins_with(m + "|") and c.visible:
				c.visible = false
				hidden.append(c)

func _show_roofs() -> void:
	for c in hidden:
		c.visible = true
	hidden.clear()

func _fly(model: String, from: Vector3, dir: Vector3, speed: float, rotor := false) -> void:
	var n := Node3D.new()
	add_child(n)
	n.global_position = from
	n.look_at(from + dir, Vector3.UP)
	var body := _mesh(model)
	body.rotation.y = -PI / 2.0                       # нос модели — по +X (Blender), узел смотрит в −Z
	n.add_child(body)
	if rotor:
		var r := _mesh("heli_rotor")
		r.position = Vector3(0, 4.0, 0)
		n.add_child(r)
	air.append([n, speed, dir.normalized(), rotor])

func _vert(v: float, s: float) -> void:
	# герой едет по вертикали (лестница) со скоростью v м/с s секунд
	if skipping:
		hero.global_position.y += v * s
		return
	var e := 0.0
	while e < s and not skipping:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		e += dt
		hero.global_position.y += v * dt

func _sleep_place(hy: float) -> void:
	# лёжа на боку: голова на подушке (у изголовья, +X дома), тело вдоль кровати, на матрасе
	var hv := Vector2(SLEEP_HEAD.x - SLEEP_HIPS.x, -(SLEEP_HEAD.y - SLEEP_HIPS.y))   # таз → голова в осях модели Godot (x, z)
	var want := ld(1, 0)
	var yaw := atan2(want.x, want.y) - atan2(hv.x, hv.y)
	hero.rotation = Vector3(0, yaw, 0)
	var head_m := Vector3(SLEEP_HEAD.x, 0, -SLEEP_HEAD.y).rotated(Vector3.UP, yaw)
	var pos := w3(L(3.2, 3.25), 0.0) - head_m
	hero.global_position = Vector3(pos.x, hy + 1.12, pos.z)

# ---------- сценарий ----------
var _env: Environment
var _bg_keep := [0, Color.BLACK]
var _cam_size_keep := 18.0
func _run() -> void:
	var wes: Array = main.find_children("*", "WorldEnvironment", true, false)
	if not wes.is_empty():                                     # небо (в игре камера смотрит сверху и неба не видит)
		_env = (wes[0] as WorldEnvironment).environment
		_bg_keep = [_env.background_mode, _env.background_color]
		var sky := Sky.new()
		var sm := ProceduralSkyMaterial.new()
		sm.sky_top_color = Color(0.32, 0.5, 0.78)
		sm.sky_horizon_color = Color(0.72, 0.78, 0.84)
		sm.ground_horizon_color = Color(0.6, 0.62, 0.6)
		sm.ground_bottom_color = Color(0.3, 0.3, 0.28)
		sky.sky_material = sm
		_env.sky = sky
		_env.background_mode = Environment.BG_SKY
	_cam_size_keep = main.cam_size
	main.cam_size = 38.0                                       # шире радиус подгрузки чанков
	main.camctl.visible = false
	main.daynight.auto = false
	var t_keep: float = main.daynight.t
	main.daynight.t = 9.0
	if main.weather:
		main.weather.set("rain", 0.0)
	var f: Vector2 = S.f
	var hy: float = S.house_y
	var up := Vector3.UP
	var F3 := Vector3(f.x, 0, f.y)
	var U3 := ld3(1, 0)
	var LK := -F3                                              # к озеру
	main.focus = S.c
	main.world.ensure_now(main.focus, 2)
	_hide_roofs(["hero_house_roof"])

	_mark("bed")
	# 1. Спальня. Спит на боку; будильник
	_sleep_place(hy)
	_play("Sleep", 0.0)
	var bedc := w3(L(2.6, 3.25), hy + 1.1)
	_shot(w3(L(1.2, -1.6), hy + 2.5), w3(L(1.6, -0.6), hy + 2.3), bedc + up * 0.1, bedc + up * 0.15, 12.0)
	_say("Субботнее утро. Дом у озера.")
	await _fade(0.0, 2.5)
	await _wait(5.0)
	_say("")
	alarm_v = 1.0
	await _wait(3.5)
	alarm_v = 0.0
	await _fade(1.0, 1.2)

	_mark("sit")
	# 2. Сидит на краю кровати, встаёт, потягивается
	_place(L(2.3, 2.62), hy + 0.64, yaw_to(ld(0, -1)))
	_play("SitIdle", 0.0)
	var hp3 := hero.global_position
	_shot(hp3 + ld3(0.6, -3.3) + up * 1.6, hp3 + ld3(0.3, -3.0) + up * 1.55, hp3 + up * 0.9, hp3 + up * 1.25, 13.0)
	_say("Проснулся. Ещё минуту посидеть…")
	await _fade(0.0, 1.5)
	await _wait(3.5)
	_say("")
	await _act("StandUp", 0.4)
	_say("Потянуться, зевнуть.")
	await _act("Stretch", 0.4)
	_play("Idle", 0.4)
	await _wait(1.0)

	_mark("kitchen")
	# 3. На кухню (камера сверху — крыша снята)
	_say("Сначала — умыться.")
	_follow(ld3(0.8, -1.8) + up * 6.0)
	await _move([tile_of(hero.global_position), L(1.5, 1.5), L(-0.2, 1.5), L(-2.0, 1.0), L(-2.0, -0.6), L(-2.6, -2.55)], "WalkSlow")
	await _turn(ld(0, -1), 0.7)
	_say("")
	# 4. Умывается у раковины
	_shot(w3(L(-1.0, -1.7), hy + 2.2), w3(L(-1.2, -2.0), hy + 2.1), w3(L(-2.6, -3.0), hy + 1.6), w3(L(-2.6, -3.1), hy + 1.55), 8.5)
	water_v = 1.0
	await _act("WashFace", 0.4)
	water_v = 0.0
	_play("Idle", 0.4)
	await _wait(0.8)

	_mark("window")
	# 5. К окну на озеро
	_follow(ld3(-0.8, -1.8) + up * 6.0)
	await _move([tile_of(hero.global_position), L(-2.0, -0.6), L(-2.0, 1.0), L(-0.9, 2.6), L(-0.6, 3.3)], "WalkSlow")
	await _turn(ld(0, 1), 0.8)
	_play("Idle", 0.4)
	var hpw := hero.global_position
	_shot(w3(L(-2.3, 2.2), hy + 2.0), w3(L(-2.1, 2.5), hy + 1.95), hpw + up * 1.5, hpw + up * 1.6 + LK * 0.3, 6.0)   # сбоку: стоит у окна
	_say("За окном — озеро. Ни ветерка.")
	await _wait(6.0)
	var win := w3(L(-0.6, 4.2), hy + 1.7)                                # то, что он видит: озеро с веранды
	_shot(win + LK * 0.3 + U3 * 0.3, win + LK * 1.2 + U3 * 0.2, win + LK * 20.0 - up * 1.4, win + LK * 22.0 - up * 1.3 - U3 * 3.0, 6.0)
	_say("Хороший день, чтобы ничего не делать.")
	await _wait(6.0)
	_say("")
	await _fade(1.0, 0.8)

	_mark("outside")
	# 6. На улицу: от крыльца вокруг дома к веранде
	var pc := L(-3.4, -5.0)
	_place(pc, floor_y(pc), yaw_to(ld(-1, -0.3)))
	_shot(w3(L(-9.5, -9.0), hy + 3.0), w3(L(-10.0, -6.0), hy + 3.0), w3(pc, hy + 1.2), w3(L(-5.8, -3.0), hy + 1.0), 6.0)
	await _fade(0.0, 0.8)
	await _move([pc, L(-5.6, -5.6), L(-5.9, -2.5)], "WalkSlow")
	await _fade(1.0, 0.5)
	var st0 := L(-3.0, 9.6)
	_place(st0, floor_y(st0), yaw_to(ld(1, 0)))
	_shot(w3(L(4.5, 12.5), hy + 2.6), w3(L(5.5, 11.0), hy + 2.6), w3(L(-1.0, 9.0), hy + 1.2), w3(L(1.5, 6.0), hy + 1.6), 9.0)
	await _fade(0.0, 0.5)
	await _move([st0, L(-0.2, 9.2), L(0.0, 8.0), L(0.2, 6.9), L(1.5, 6.6), L(1.5, 6.0)], "WalkSlow")
	_mark("chair")
	# 7. Садится на стул лицом к озеру
	await _turn(ld(0, 1), 0.7)
	await _act("SitDown", 0.4)
	_play("SitIdle", 0.4)
	var cp := w3(S.chair, hy + 0.6)
	_shot(cp + U3 * 2.4 + LK * 0.6 + up * 1.5, cp + U3 * 1.7 + LK * 1.3 + up * 1.35, cp + up * 0.8 - U3 * 0.5, cp + LK * 20.0 - U3 * 4.0, 8.0)
	_say("Тихо. Только вода и птицы.")
	await _wait(8.0)

	_mark("phone")
	# 8. Достаёт телефон из кармана, читает новости
	_say("Что там в новостях?")
	_shot(cp + LK * 1.7 + U3 * 1.0 + up * 1.45, cp + LK * 1.3 + U3 * 0.7 + up * 1.4, cp + up * 1.0, cp + up * 1.05, 20.0)   # спереди-сбоку: видно телефон в руках
	_play("SitPhoneOut", 0.4)
	await _wait(0.45)
	if phone_mi:
		phone_mi.visible = true
	await _wait(_clip_len("SitPhoneOut") - 0.5)
	_play("SitPhoneRead", 0.4)
	await _wait(1.0)
	_say("")
	phone_ui.visible = true
	for it in [["Погода: +21°, солнечно", "Выходные обещают быть тёплыми. Ветер слабый.", Color(0.2, 0.3, 0.5)],
			["СРОЧНО: авария в НИИ «Вектор-7»", "На территории закрытого института произошла утечка неизвестного вещества. Район оцеплен.", Color(0.75, 0.08, 0.06)],
			["Власти: не выходите из домов", "Жителей окрестных посёлков просят закрыть окна и двери и оставаться в укрытиях до особого распоряжения.", Color(0.75, 0.08, 0.06)],
			["К институту стянуты войска", "Над районом закрыто воздушное пространство. Связь может пропадать.", Color(0.4, 0.1, 0.08)]]:
		_news_item(it[0], it[1], it[2])
		await _wait(3.8)
	await _wait(2.0)
	phone_ui.visible = false

	_mark("siren")
	# 9. Сирена. Вскочил — и бегом к сараю
	siren = 1.0
	_say("Сирена… Это не учения.")
	await _wait(1.5)
	if phone_mi:
		phone_mi.visible = false
	await _act("StandUp", 0.25, 1.6)
	_play("Idle", 0.2)
	await _turn(ld(-1, 0.6), 0.4)
	var pp: Vector3 = w3(L(4.0, 8.0), hy)
	_shot(pp + LK * 8.0 + U3 * 10.0 + up * 7.0, pp + U3 * 14.0 + up * 8.0 - LK * 2.0, w3(L(1.0, 7.0), hy + 1.0), w3(S.shed, S.shed_y + 1.0), 6.0)
	await _move([tile_of(hero.global_position), L(0.3, 6.6), L(0.0, 8.4), L(5.8, 8.8), L(7.6, 2.4), S.shed_door + f * 1.5], "Run", 0.2)
	_play("Idle", 0.2)

	_mark("village")
	# 10. Деревня: паника, вертолёт, истребители
	await _fade(1.0, 0.4)
	var vc := Vector2(WorldGen.FEATURES["village"].x, WorldGen.FEATURES["village"].y)
	var vg := gh(vc)
	var nc := Vector2.ZERO                                       # середина путей жителей — туда смотрит камера
	for n in npcs:
		nc += ((n[1] as Vector2) + (n[2] as Vector2)) * 0.5
	if not npcs.is_empty():
		nc /= float(npcs.size())
	else:
		nc = vc
	var ng := gh(nc)
	var vcam := w3(nc, ng) + Vector3(7, 8, 11)
	_shot(vcam, vcam + Vector3(-3, -1, -2), w3(nc, ng) + Vector3(-4, 4, -6), w3(nc, ng) + Vector3(-5, 5, -7), 9.0)   # жители внизу кадра, небо с авиацией сверху
	_say("Люди в панике прячутся по домам.")
	for n in npcs:
		var nd: Node3D = n[0]
		nd.visible = true
		var p0: Vector2 = n[1]
		nd.global_position = w3(p0, gh(p0))
		nd.rotation.y = yaw_to((n[2] as Vector2) - p0)
		var ap: AnimationPlayer = nd.find_child("AnimationPlayer", true, false)
		if ap and ap.has_animation("Run"):
			ap.get_animation("Run").loop_mode = Animation.LOOP_LINEAR
			ap.play("Run")
			ap.seek(float(n[3]), true)
	var mid := w3(nc, ng)                                      # авиация проходит поперёк кадра за жителями: вертолёт на 4-й с, истребители на 3-й
	var across := Vector3(11, 0, -7).normalized()
	var over := mid + Vector3(-6, 10, -9)
	_fly("heli_fly", over - across * 100.0, across, 24.0, true)
	_fly("plane_jet", over + Vector3(-10, 25, -30) + across * 420.0, -across, 140.0)
	_fly("plane_jet", over + Vector3(-4, 28, -40) + across * 440.0, -across, 140.0)
	heli_v = 1.0
	jet_v = 1.0
	await _fade(0.0, 0.4)
	var e := 0.0
	while e < 9.0 and not skipping:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		e += dt
		for n in npcs:
			var nd: Node3D = n[0]
			if not nd.visible:
				continue
			var a: Vector2 = n[1]
			var b: Vector2 = n[2]
			var k := clampf((e - 0.3 - float(n[3])) * SPEED["Run"] / maxf(a.distance_to(b) * T, 0.5), 0.0, 1.0)
			var p := a.lerp(b, k)
			nd.global_position = w3(p, gh(p))
			if k >= 1.0:
				nd.visible = false                      # забежал в дом
	await _fade(1.0, 0.4)
	for n in npcs:
		(n[0] as Node3D).visible = false

	_mark("shed")
	# 11. Сарай: открыл люк, спускается по лестнице
	_hide_roofs(["hero_shed_roof"])
	var sy: float = S.shed_y + 0.35 + 0.02
	var side := SL(1.6, 0.35)
	_place(S.shed_door, floor_y(S.shed_door), yaw_to(side - (S.shed_door as Vector2)))
	var hc := w3(SL(0.7, 0.35), sy)
	_shot(hc + F3 * 3.2 - U3 * 1.4 + up * 3.6, hc + F3 * 2.4 - U3 * 0.8 + up * 3.0, hc + up * 0.9, hc + up * 0.3, 14.0)
	_say("Скорее — в бункер.")
	await _fade(0.0, 0.4)
	await _move([S.shed_door, SL(-0.9, -1.2), side], "Walk")
	await _turn(ld(-1, 0), 0.4)
	_play("Idle", 0.3)
	var tw := create_tween()
	tw.tween_property(lid, "rotation:x", deg_to_rad(110.0), 0.9)
	await _wait(1.0)
	await _move([side, SL(0.7, 0.3)], "WalkSlow", 0.3)
	hero.global_position = w3(SL(0.7, 0.3), sy)
	await _turn(ld(0, 1), 0.5)
	_play("ClimbDown", 0.4, 1.4)
	_say("")
	await _vert(-CLIMB_DOWN_V * 1.4, 7.0)
	hero.visible = false
	var tw2 := create_tween()
	tw2.tween_property(lid, "rotation:x", 0.0, 0.8)
	await _wait(1.2)
	siren = 0.0
	heli_v = 0.0
	jet_v = 0.0
	await _fade(1.0, 1.5)

	_mark("month")
	# 12. «Прошёл месяц…»
	title.text = "Прошёл месяц…"
	var tt := create_tween()
	tt.tween_property(title, "modulate:a", 1.0, 1.0)
	await _wait(3.5)
	var tt2 := create_tween()
	tt2.tween_property(title, "modulate:a", 0.0, 1.0)
	await _wait(1.1)

	_mark("exit")
	# 13. Поднимается по лестнице, выходит: тишина, никого
	for a in air:
		(a[0] as Node3D).queue_free()
	air.clear()
	main.daynight.t = 17.5
	var lid_up := create_tween()
	lid_up.tween_property(lid, "rotation:x", deg_to_rad(110.0), 0.8)
	hero.visible = true
	hero.global_position = w3(SL(0.7, 0.3), sy - 1.75)
	hero.rotation.y = yaw_to(ld(0, 1))
	_play("ClimbUp", 0.0, 1.8)
	_shot(hc + F3 * 2.6 + U3 * 1.2 + up * 3.2, hc + F3 * 2.2 + U3 * 1.0 + up * 2.9, hc + up * 0.4, hc + up * 1.0, 8.0)
	await _fade(0.0, 1.0)
	await _vert(CLIMB_UP_V * 1.8, 1.75 / (CLIMB_UP_V * 1.8) - 1.0)
	hero.global_position.y = sy
	_play("Idle", 0.5)
	await _wait(0.6)
	await _turn(ld(0, -1), 0.8)
	_show_roofs()
	var out_p: Vector2 = S.shed_door + f * 6.0
	var op := w3(out_p, gh(out_p))
	_shot(op + F3 * 6.0 + U3 * 3.0 + up * 2.2, op + F3 * 7.0 + U3 * 4.0 + up * 2.6, w3(S.shed_door, gh(S.shed_door) + 1.2), op + up * 1.2, 7.0)
	await _move([tile_of(hero.global_position), SL(-0.9, -1.2), S.shed_door, out_p], "WalkSlow")
	_play("LookAround", 0.5)
	_shot(op + F3 * 3.0 + U3 * 2.0 + up * 1.8, op + F3 * 9.0 + U3 * 5.0 + up * 6.0, op + up * 1.3, op + up * 0.8, 9.0)
	_say("Тишина. Никого.")
	await _wait(7.0)
	await _fade(1.0, 1.6)
	# конец: обратно в игру
	_say("")
	main.daynight.t = t_keep
	main.daynight.auto = true
	if _env:
		_env.background_mode = _bg_keep[0]
		_env.background_color = _bg_keep[1]
	main.cam_size = _cam_size_keep
	main.camctl.visible = true
	_show_roofs()
	main.cam.make_current()
	main.teleport(out_p)
	var fo := create_tween()
	fo.tween_property(fade, "color:a", 0.0, 0.8)
	await get_tree().create_timer(0.85).timeout
	var cf := FileAccess.open("user://intro_done", FileAccess.WRITE)
	if cf:
		cf.store_string("1")
	finished.emit()
	if shot_dir != "":
		get_tree().quit()
	queue_free()

func _process(dt: float) -> void:
	if not skipping:
		t_all += dt
	cam_t += dt
	if cam:
		_cam_update()
	for a in air:
		var n: Node3D = a[0]
		n.global_position += (a[2] as Vector3) * float(a[1]) * dt
		if a[3]:
			var r: Node3D = n.get_child(1)
			r.rotation.y += dt * 22.0
	_audio()
	if shot_dir != "" and not skipping and int(t_all / 2.0) >= shot_n:
		shot_n += 1
		_snap()

func _snap() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_jpg("%s/intro_%03d.jpg" % [shot_dir, shot_n], 0.8)

func _audio() -> void:
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	if n <= 0:
		return
	var on: bool = main.settings.sound
	var buf := PackedVector2Array()
	buf.resize(n)
	var dt := 1.0 / RATE
	for i in n:
		_st += dt
		var s := 0.0
		if siren > 0.0:                                             # сирена: тон ползёт 300→800→300 Гц за 6 с
			var fr := 300.0 + 500.0 * (0.5 - 0.5 * cos(_st * TAU / 6.0))
			_ph[0] += fr * dt
			s += (2.0 * fmod(_ph[0], 1.0) - 1.0) * 0.18 * siren
		if heli_v > 0.0:                                            # вертолёт: удары лопастей ~5 Гц
			var w := _rng.randf() * 2.0 - 1.0
			_lp += 0.08 * (w - _lp)
			var thump := pow(0.5 + 0.5 * sin(_st * TAU * 5.2), 6.0)
			s += _lp * 1.6 * thump * heli_v
		if jet_v > 0.0:                                             # самолёты: гул (шум), нарастает и уходит
			var w2 := _rng.randf() * 2.0 - 1.0
			var k := clampf(1.0 - absf(fmod(_st, 7.0) - 2.5) / 2.5, 0.0, 1.0)
			s += w2 * 0.12 * k * jet_v
		if alarm_v > 0.0:                                           # будильник: 4 коротких писка в секунду, пауза
			var on_b := fmod(_st, 1.0) < 0.5 and fmod(_st, 0.125) < 0.07
			_ph[1] += 2300.0 * dt
			s += (0.08 * sin(_ph[1] * TAU) if on_b else 0.0) * alarm_v
		if water_v > 0.0:                                           # вода из крана: мягкий шум
			var w3n := _rng.randf() * 2.0 - 1.0
			_wl += 0.25 * (w3n - _wl)
			s += (w3n - _wl) * 0.07 * water_v
		s = clampf(s * (1.0 if on else 0.0), -1.0, 1.0)
		buf[i] = Vector2(s, s)
	_pb.push_buffer(buf)

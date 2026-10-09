extends Node3D
# Заставка «Как всё началось» (~50 с). Утро в доме у озера: герой просыпается, сидит на веранде, лежит на шезлонге,
# читает новости в телефоне — утечка в НИИ «Вектор-7», власти просят не выходить из домов. Он бежит к сараю,
# в деревне паника (жители бегут по домам, сирена, вертолёт, истребители), герой спускается в свой бункер.
# «Прошёл месяц…» — он выходит: тишина, никого. Точки — props.story (props.gd), модели — props.glb, герой — hero.glb.
# Запуск: при первом входе в игру, кнопка «▶ Заставка» (⚙), аргумент --intro. Проверка без телефона:
#   --intro --introshot=<папка>  → кадр каждые 2 с в JPG, в конце игра закрывается.
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
var cam_a := Vector3.ZERO
var cam_b := Vector3.ZERO
var look_a := Vector3.ZERO
var look_b := Vector3.ZERO
var cam_t := 0.0
var cam_len := 1.0
var shot_dir := ""
var shot_n := 0
var t_all := 0.0
var _rng := RandomNumberGenerator.new()
# звук: сирена, вертолёт, самолёты — синтез
var _pb: AudioStreamGeneratorPlayback
var siren := 0.0
var heli_v := 0.0
var jet_v := 0.0
var _ph := [0.0, 0.0, 0.0]
var _lp := 0.0
var _st := 0.0
const RATE := 16000.0
const T := WorldGen.T

func _ready() -> void:
	_rng.seed = 11
	props = main.props
	S = props.story
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--introshot="):
			shot_dir = a.substr(12)
			DirAccess.make_dir_recursive_absolute(shot_dir)
	_build()
	_run()

# ---------- построение ----------
func w3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x * T, y, p.y * T)
func gh(p: Vector2) -> float:
	return WorldGen.height_m(p.x, p.y)
func yaw_to(d: Vector2) -> float:                      # лицом (+Z модели) в сторону d (тайлы)
	return atan2(d.x, d.y)

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
	for n in ["Idle", "Walk", "Run", "SitChair", "LieLounger", "Lie"]:
		if anim and anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	if skel:
		var att := BoneAttachment3D.new()
		att.bone_name = "RightHand"
		skel.add_child(att)
		phone_mi = _mesh("phone")
		phone_mi.position = Vector3(0.0, 0.09, 0.02)
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
		npcs.append([npc, a, b, _rng.randf_range(0.0, 1.6)])
	cam = Camera3D.new()
	cam.fov = 48.0
	cam.near = 0.1
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
	sub.position = Vector2(-500, -110)
	sub.size = Vector2(1000, 60)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	# экран телефона: лента новостей
	phone_ui = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.97, 0.97, 0.98)
	st.set_corner_radius_all(26)
	st.border_color = Color(0.08, 0.08, 0.09)
	st.set_border_width_all(14)
	st.content_margin_left = 24; st.content_margin_right = 24; st.content_margin_top = 30; st.content_margin_bottom = 30
	phone_ui.add_theme_stylebox_override("panel", st)
	phone_ui.set_anchors_preset(Control.PRESET_CENTER)
	phone_ui.position = Vector2(-210, -330)
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
	create_tween().tween_property(v, "modulate:a", 1.0, 0.4)

# ---------- управление ----------
func _wait(s: float) -> void:
	var e := 0.0
	while e < s and not skipping:
		await get_tree().process_frame
		e += get_process_delta_time()

func _fade(to: float, s: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", to, s)
	await _wait(s)

func _say(text: String) -> void:
	sub.text = text

func _shot(a: Vector3, b: Vector3, la: Vector3, lb: Vector3, length: float) -> void:
	cam_a = a; cam_b = b; look_a = la; look_b = lb; cam_t = 0.0; cam_len = maxf(length, 0.01)
	_cam_update()

func _cam_update() -> void:
	var k := clampf(cam_t / cam_len, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	cam.global_position = cam_a.lerp(cam_b, k)
	var lt := look_a.lerp(look_b, k)
	if cam.global_position.distance_to(lt) > 0.01:
		cam.look_at(lt, Vector3.UP)

func _play(n: String, blend := 0.25) -> void:
	if anim and anim.has_animation(n):
		anim.play(n, blend)

func _place(p: Vector2, y: float, yaw: float) -> void:
	hero.global_position = w3(p, y)
	hero.rotation = Vector3(0, yaw, 0)

func _move(path: Array, speed: float, clip: String) -> void:
	# пройти по точкам (тайлы) по земле со скоростью (м/с)
	_play(clip, 0.2)
	for i in range(1, path.size()):
		var a: Vector2 = path[i - 1]
		var b: Vector2 = path[i]
		var len_m := a.distance_to(b) * T
		var tt := len_m / speed
		hero.rotation.y = yaw_to(b - a)
		var e := 0.0
		while e < tt and not skipping:
			await get_tree().process_frame
			e += get_process_delta_time()
			var p := a.lerp(b, clampf(e / tt, 0.0, 1.0))
			hero.global_position = w3(p, gh(p))

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

# ---------- сценарий ----------
func _run() -> void:
	main.daynight.auto = false
	var t_keep: float = main.daynight.t
	main.daynight.t = 8.0
	if main.weather:
		main.weather.set("rain", 0.0)
	var u: Vector2 = S.u
	var f: Vector2 = S.f
	var lakedir := -f
	var hy: float = S.house_y
	var up := Vector3.UP
	# 1. Утро. Спальня (крыша спрятана): лежит, просыпается, потягивается
	_hide_roofs(["hero_house_roof"])
	var bed: Vector2 = S.pt.call(2.55, 3.25)
	_place(bed, hy + 1.12, atan2(-u.x, -u.y))
	_play("Lie", 0.0)
	var head := w3(bed, hy + 1.3)
	_shot(head + Vector3(u.x * T, 0, u.y * T) * 3.0 + up * 2.6 + Vector3(f.x, 0, f.y) * 1.5, head + Vector3(u.x * T, 0, u.y * T) * 2.0 + up * 2.0 + Vector3(f.x, 0, f.y) * 2.2,
		head, head - Vector3(u.x, 0, u.y) * 0.4, 6.0)
	_say("Обычное утро. Дом у озера.")
	await _fade(0.0, 1.5)
	await _wait(0.8)
	_play("WakeUp", 0.2)
	await _wait(4.3)
	await _fade(1.0, 0.6)
	_show_roofs()
	# 2. Веранда: сидит, смотрит на озеро
	var ch: Vector2 = S.chair
	_place(ch, hy + 0.6, yaw_to(lakedir))
	_play("SitChair", 0.0)
	var cp := w3(ch, hy + 0.6)
	var ld := Vector3(lakedir.x, 0, lakedir.y)
	var side := Vector3(u.x, 0, u.y)
	_shot(cp - ld * 2.6 + side * 1.2 + up * 1.9, cp - ld * 2.2 - side * 1.0 + up * 1.7, cp + ld * 25.0, cp + ld * 25.0 - side * 4.0, 6.5)
	_say("Тихо. Только вода и птицы.")
	await _fade(0.0, 0.8)
	await _wait(5.2)
	await _fade(1.0, 0.5)
	# 3. Шезлонг у воды: лежит, достаёт телефон, читает новости
	var lo: Vector2 = S.lounger
	var lg := gh(lo)
	_place(lo, lg + 0.12, atan2(-f.x, -f.y))
	_play("LieLounger", 0.0)
	var lp := w3(lo, lg + 0.8)
	_shot(lp + ld * 2.8 + side * 1.8 + up * 1.2, lp + ld * 1.9 + side * 0.9 + up * 1.0, lp, lp + up * 0.1, 7.0)
	_say("")
	await _fade(0.0, 0.6)
	await _wait(1.6)
	_play("Phone", 0.3)
	if phone_mi:
		phone_mi.visible = true
	await _wait(1.4)
	sub.text = ""
	phone_ui.visible = true
	for it in [["Погода: +21°, солнечно", "Выходные обещают быть тёплыми.", Color(0.2, 0.3, 0.5)],
			["СРОЧНО: авария в НИИ «Вектор-7»", "На территории закрытого института произошла утечка неизвестного вещества. Район оцеплен.", Color(0.75, 0.08, 0.06)],
			["Власти: не выходите из домов", "Жителей окрестных посёлков просят закрыть окна и двери и оставаться в укрытиях до особого распоряжения.", Color(0.75, 0.08, 0.06)],
			["К институту стянуты войска", "Над районом закрыто воздушное пространство. Связь может пропадать.", Color(0.4, 0.1, 0.08)]]:
		_news_item(it[0], it[1], it[2])
		await _wait(1.6)
	await _wait(1.2)
	phone_ui.visible = false
	# 4. Испуг и бег к сараю
	if phone_mi:
		phone_mi.visible = false
	_play("Scared", 0.1)
	siren = 1.0
	_say("Сирена…")
	await _wait(1.0)
	var path := [lo, S.pt.call(5.8, 8.6), S.pt.call(7.4, 2.4), S.shed_door + f * 1.5]
	var pp: Vector3 = w3(S.pt.call(4.0, 6.0), gh(S.pt.call(4.0, 6.0)))
	_shot(pp + ld * 6.0 + side * 9.0 + up * 6.0, pp + side * 12.0 + up * 7.0 - ld * 3.0, w3(lo, lg + 1.0), w3(S.shed, S.shed_y + 1.0), 3.2)
	await _move(path, 5.5, "Run")
	# 5. Деревня: паника, вертолёт, истребители
	await _fade(1.0, 0.3)
	var vc := Vector2(WorldGen.FEATURES["village"].x, WorldGen.FEATURES["village"].y)
	var vg := gh(vc)
	var vcam := w3(vc, vg) + Vector3(18, 22, 30)
	_shot(vcam, vcam + Vector3(-6, -2, -4), w3(vc, vg), w3(vc, vg) + Vector3(-4, 0, -4), 6.5)
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
	_fly("heli_fly", w3(vc, vg) + Vector3(-160, 45, 60), Vector3(1, 0, -0.35), 28.0, true)
	_fly("plane_jet", w3(vc, vg) + Vector3(260, 120, -200), Vector3(-1, 0, 0.75), 160.0)
	_fly("plane_jet", w3(vc, vg) + Vector3(275, 125, -170), Vector3(-1, 0, 0.75), 160.0)
	heli_v = 1.0
	jet_v = 1.0
	await _fade(0.0, 0.3)
	var e := 0.0
	while e < 6.0 and not skipping:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		e += dt
		for n in npcs:
			var nd: Node3D = n[0]
			if not nd.visible:
				continue
			var a: Vector2 = n[1]
			var b: Vector2 = n[2]
			var k := clampf((e - 0.2) * 4.2 / maxf(a.distance_to(b) * T, 0.5), 0.0, 1.0)
			var p := a.lerp(b, k)
			nd.global_position = w3(p, gh(p))
			if k >= 1.0:
				nd.visible = false                      # забежал в дом
	await _fade(1.0, 0.3)
	for n in npcs:
		(n[0] as Node3D).visible = false
	# 6. Сарай: открыл люк, спустился, люк закрылся
	_hide_roofs(["hero_shed_roof"])
	var hp: Vector2 = S.hatch
	var sy: float = S.shed_y + 0.35 + 0.16
	_place(S.shed_door, gh(S.shed_door), yaw_to(hp - S.shed_door))
	var hc := w3(hp, sy)
	_shot(hc + Vector3(f.x, 0, f.y) * T * 3.5 - side * 1.2 + up * 4.2, hc + Vector3(f.x, 0, f.y) * T * 2.5 - side * 0.6 + up * 3.4, hc + up * 0.8, hc + up * 0.2, 6.0)
	_say("Скорее — в бункер.")
	await _fade(0.0, 0.3)
	await _move([S.shed_door, hp], 1.6, "Walk")
	hero.global_position = w3(hp, sy)
	hero.rotation.y = S.th + PI
	_play("Idle", 0.2)
	var tw := create_tween()
	tw.tween_property(lid, "rotation:x", deg_to_rad(110.0), 0.7)
	await _wait(0.8)
	_play("ClimbDown", 0.15)
	await _wait(2.5)
	hero.visible = false
	var tw2 := create_tween()
	tw2.tween_property(lid, "rotation:x", 0.0, 0.6)
	await _wait(0.9)
	siren = 0.0
	heli_v = 0.0
	jet_v = 0.0
	await _fade(1.0, 1.0)
	_say("")
	# 7. «Прошёл месяц…»
	title.text = "Прошёл месяц…"
	var tt := create_tween()
	tt.tween_property(title, "modulate:a", 1.0, 0.8)
	await _wait(2.6)
	var tt2 := create_tween()
	tt2.tween_property(title, "modulate:a", 0.0, 0.8)
	await _wait(0.9)
	# 8. Выход: тишина, никого
	for a in air:
		(a[0] as Node3D).queue_free()
	air.clear()
	main.daynight.t = 17.5
	hero.visible = true
	hero.global_position = w3(hp, sy)
	hero.rotation.y = S.th
	_play("ClimbUp", 0.0)
	var tw3 := create_tween()
	tw3.tween_property(lid, "rotation:x", deg_to_rad(110.0), 0.6)
	_shot(hc + Vector3(f.x, 0, f.y) * T * 3.0 + side * 1.0 + up * 3.8, hc + Vector3(f.x, 0, f.y) * T * 3.0 + side * 1.0 + up * 3.8, hc + up * 0.6, hc + up * 1.2, 3.0)
	await _fade(0.0, 0.8)
	await _wait(2.4)
	_show_roofs()
	var out_p: Vector2 = S.shed_door + f * 6.0
	_shot(w3(out_p, gh(out_p)) + Vector3(f.x, 0, f.y) * 8.0 + side * 3.0 + up * 3.0, w3(out_p, gh(out_p)) + Vector3(f.x, 0, f.y) * 26.0 + side * 10.0 + up * 26.0,
		w3(out_p, gh(out_p) + 1.0), w3(out_p, gh(out_p)), 7.0)
	await _move([hp, S.shed_door, out_p], 1.4, "Walk")
	_play("Idle", 0.3)
	_say("Тишина. Никого.")
	await _wait(3.5)
	await _fade(1.0, 1.2)
	# конец: обратно в игру
	_say("")
	main.daynight.t = t_keep
	main.daynight.auto = true
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
	if shot_dir != "" and int(t_all / 2.0) >= shot_n:
		shot_n += 1
		_snap()

func _snap() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_jpg("%s/intro_%02d.jpg" % [shot_dir, shot_n], 0.8)

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
		s = clampf(s * (1.0 if on else 0.0), -1.0, 1.0)
		buf[i] = Vector2(s, s)
	_pb.push_buffer(buf)

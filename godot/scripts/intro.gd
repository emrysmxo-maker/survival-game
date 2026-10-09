extends Node3D
# Заставка «Как всё началось» — 3D-комикс. Каждый кадр снимается в самой игре (дом у озера, сарай, деревня — те же
# модели, свет и тени) с героем в неподвижной выверенной позе (поза — кадр клипа мокапа из hero.glb), затем кадры
# раскладываются по страницам: рамки, плашки рассказчика, облачка, звуки буквами; кадр появляется с наездом камеры.
# Сюжет: суббота, дом у озера → будильник → сел на кровати → потянулся → умылся → окно → веранда, телефон: утечка
# в НИИ «Вектор-7» → сирена → бегом к сараю → паника в деревне, вертолёт → люк, лестница вниз → «Прошёл месяц…» →
# люк открывается, выходит: тишина, никого. Тап — следующий кадр, «Пропустить» — в игру.
# Запуск: первый вход, ⚙ «▶ Заставка», --intro. Проверка: --intro --introshot=<папка> → снимок каждой готовой страницы.
signal finished
var main
var props
var S: Dictionary
var hero: Node3D
var anim: AnimationPlayer
var skel: Skeleton3D
var phone_mi: MeshInstance3D
var lid: Node3D
var npcs: Array = []
var air: Array = []
var hidden: Array = []
var vp: SubViewport
var cur_tr: TextureRect                 # живой кадр (показывает экран съёмки)
var live_a := Vector3.ZERO
var live_b := Vector3.ZERO
var live_look := Vector3.ZERO
var live_t := 0.0
var pcam: Camera3D
var fill: OmniLight3D
var ui: CanvasLayer
var page: Control
var fade: ColorRect
var skip_btn: Button
var skipping := false
var tapped := false
var shot_dir := ""
var page_n := 0
var _rng := RandomNumberGenerator.new()
# звук — синтез
var _pb: AudioStreamGeneratorPlayback
var siren := 0.0
var heli_v := 0.0
var alarm_v := 0.0
var water_v := 0.0
var _ph := [0.0, 0.0]
var _lp := 0.0
var _wl := 0.0
var _st := 0.0
const RATE := 16000.0
const T := WorldGen.T
const PAPER := Color(0.95, 0.93, 0.88)
const INK := Color(0.06, 0.06, 0.07)
const CAPTION := Color(1.0, 0.92, 0.55)
const MOVE_STAND := 0.433                       # StandUp: таз уходит вперёд (hero_clips.json)
const SLEEP_HIPS := Vector3(0.0, 0.0, 0.193)   # первый кадр Sleep: таз и голова (Blender, м)
const SLEEP_HEAD := Vector3(0.334, 0.467, 0.218)

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

# ---------- геометрия места ----------
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
func ld(dx: float, dy: float) -> Vector2:              # направление в осях дома (тайлы)
	return (S.u as Vector2) * dx - (S.f as Vector2) * dy
func hv(x: float, y: float, z: float) -> Vector3:      # вектор в осях дома, метры мира
	var v := ld(x, y)
	return Vector3(v.x, z, v.y)
func hy() -> float:
	return S.house_y

# ---------- построение ----------
func _mesh(name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = props._meshes.get(name)
	return mi

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null

const TOON := """
shader_type spatial;
render_mode diffuse_toon, specular_toon;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 col : source_color = vec4(1.0);
uniform bool has_tex = true;
void fragment() {
	vec3 c = has_tex ? texture(tex, UV).rgb : vec3(1.0);
	c *= col.rgb;
	c = mix(vec3(dot(c, vec3(0.3, 0.59, 0.11))), c, 1.25);   // ярче, как краска в комиксе
	ALBEDO = clamp(c, 0.0, 1.0);
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	RIM = 0.5;
	RIM_TINT = 0.4;
}
"""
const OUTLINE := """
shader_type spatial;
render_mode unshaded, cull_front;
uniform float w = 0.011;
void vertex() { VERTEX += NORMAL * w; }
void fragment() { ALBEDO = vec3(0.03, 0.03, 0.04); }
"""
var _toon_sh: Shader
var _line_mat: ShaderMaterial

func _comic_look(n: Node) -> void:
	# все сетки героя: краска плоскими полосами света и чёрный контур (вывернутая оболочка)
	if _toon_sh == null:
		_toon_sh = Shader.new()
		_toon_sh.code = TOON
		var ls := Shader.new()
		ls.code = OUTLINE
		_line_mat = ShaderMaterial.new()
		_line_mat.shader = ls
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var src := m.get_active_material(i)
			var tm := ShaderMaterial.new()
			tm.shader = _toon_sh
			if src is BaseMaterial3D:
				var bm := src as BaseMaterial3D
				tm.set_shader_parameter("col", bm.albedo_color)
				tm.set_shader_parameter("has_tex", bm.albedo_texture != null)
				if bm.albedo_texture:
					tm.set_shader_parameter("tex", bm.albedo_texture)
			tm.next_pass = _line_mat
			m.set_surface_override_material(i, tm)

func _build() -> void:
	var hs: PackedScene = load("res://assets/character/hero.glb")
	hero = hs.instantiate()
	add_child(hero)
	anim = hero.find_child("AnimationPlayer", true, false)
	skel = _find_skel(hero)
	_comic_look(hero)
	if skel:
		var att := BoneAttachment3D.new()
		att.bone_name = "LeftHand"
		skel.add_child(att)
		phone_mi = _mesh("phone")
		phone_mi.position = Vector3(0.0, 0.09, 0.03)
		phone_mi.rotation_degrees = Vector3(90, 0, 0)
		phone_mi.visible = false
		att.add_child(phone_mi)
	lid = Node3D.new()                                         # крышка люка (петля по оси X)
	add_child(lid)
	lid.position = w3(S.lid, S.shed_y + 0.35 + 0.16 + 0.004)
	lid.rotation.y = S.th
	lid.add_child(_mesh("bunker_lid"))
	for i in 5:                                                # жители для кадра паники
		var npc: Node3D = hs.instantiate()
		npc.visible = false
		npc.scale = Vector3.ONE * _rng.randf_range(0.93, 1.05)
		add_child(npc)
		_comic_look(npc)
		npcs.append(npc)
	# съёмка кадров: отдельный экран с тем же миром
	vp = SubViewport.new()
	vp.size = Vector2i(640, 360)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	pcam = Camera3D.new()
	pcam.near = 0.05
	pcam.far = 800.0
	vp.add_child(pcam)
	pcam.current = true
	fill = OmniLight3D.new()                                   # подсветка героя в комнатах (объём, как в комиксе)
	fill.light_color = Color(1.0, 0.9, 0.78)
	fill.omni_range = 7.0
	fill.light_energy = 0.0
	add_child(fill)
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

func _ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 20
	add_child(ui)
	var bg := ColorRect.new()                                  # бумага страницы
	bg.color = PAPER
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bg)
	page = Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(page)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(fade)
	var tap := Control.new()                                   # тап — следующий кадр
	tap.set_anchors_preset(Control.PRESET_FULL_RECT)
	tap.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			tapped = true)
	ui.add_child(tap)
	skip_btn = Button.new()
	skip_btn.text = "Пропустить ▶"
	skip_btn.add_theme_font_size_override("font_size", 22)
	skip_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip_btn.position = Vector2(-230, 14)
	skip_btn.size = Vector2(200, 50)
	skip_btn.modulate.a = 0.75
	skip_btn.pressed.connect(func(): skipping = true)
	ui.add_child(skip_btn)

# ---------- сцена кадра ----------
func _pose(clip: String, t: float, p: Vector2, y: float, yaw: float) -> void:
	hero.visible = true
	hero.global_position = w3(p, y)
	hero.rotation = Vector3(0, yaw, 0)
	if anim and anim.has_animation(clip):
		anim.play(clip, 0.0)
		anim.seek(t, true)
		if clip in ["Idle", "SitIdle", "Sleep", "SitPhoneRead", "LookAround"]:
			anim.speed_scale = 0.35
		else:
			anim.pause()

func _npc_pose(n: Node3D, clip: String, t: float, p: Vector2, yaw: float) -> void:
	n.visible = true
	n.global_position = w3(p, gh(p))
	n.rotation = Vector3(0, yaw, 0)
	var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
	if ap and ap.has_animation(clip):
		ap.play(clip, 0.0)
		ap.seek(t, true)
		ap.pause()

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

func _clear_scene() -> void:
	for n in npcs:
		(n as Node3D).visible = false
	for a in air:
		(a as Node3D).queue_free()
	air.clear()
	if phone_mi:
		phone_mi.visible = false
	fill.light_energy = 0.0
	_show_roofs()

func _air(model: String, at: Vector3, dir: Vector3) -> void:
	var n := Node3D.new()
	add_child(n)
	n.global_position = at
	n.look_at(at + dir, Vector3.UP)
	var body := _mesh(model)
	body.rotation.y = -PI / 2.0
	n.add_child(body)
	if model == "heli_fly":
		var r := _mesh("heli_rotor")
		r.position = Vector3(0, 4.0, 0)
		r.rotation.y = 0.4
		n.add_child(r)
	air.append(n)

func _snap_panel(eye: Vector3, look: Vector3, fov: float, size: Vector2i) -> Texture2D:
	# живой кадр: камера медленно плывёт к цели (вода, листва, герой дышат), мир вокруг подгружен
	vp.size = size
	pcam.fov = fov
	live_a = eye
	live_b = eye.lerp(look, 0.07) + (look - eye).cross(Vector3.UP).normalized() * 0.25
	live_look = look
	live_t = 0.0
	pcam.global_position = eye
	pcam.look_at(look, Vector3.UP)
	main.focus = Vector2(look.x, look.z) / T
	main.world.ensure_now(main.focus, 2)
	for i in 3:
		await RenderingServer.frame_post_draw
	return vp.get_texture()

func _freeze() -> void:
	# кадр уходит в прошлое — остаётся снимком, а экран съёмки свободен для следующего
	if cur_tr and is_instance_valid(cur_tr) and cur_tr.texture is ViewportTexture:
		cur_tr.texture = ImageTexture.create_from_image(vp.get_texture().get_image())
	cur_tr = null

# ---------- страница ----------
func _panel_rect(r: Rect2) -> Rect2:
	var sz := page.get_viewport_rect().size
	var m := sz.y * 0.035                                       # поля и промежутки между кадрами
	var g := sz.y * 0.022
	var area := Rect2(Vector2(m, m), sz - Vector2(m, m) * 2.0)
	var p := area.position + area.size * r.position
	var s := area.size * r.size
	var x0 := p.x + (g * 0.5 if r.position.x > 0.001 else 0.0)
	var y0 := p.y + (g * 0.5 if r.position.y > 0.001 else 0.0)
	var x1 := p.x + s.x - (g * 0.5 if r.end.x < 0.999 else 0.0)
	var y1 := p.y + s.y - (g * 0.5 if r.end.y < 0.999 else 0.0)
	return Rect2(x0, y0, x1 - x0, y1 - y0)

func _frame(rect: Rect2, tex: Texture2D, dark := false) -> Control:
	# кадр: чёрная рамка, внутри снимок (обрезка по рамке), лёгкий наезд
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = INK if dark or tex == null else Color.WHITE
	sb.border_color = INK
	sb.set_border_width_all(4)
	box.add_theme_stylebox_override("panel", sb)
	box.position = rect.position
	box.size = rect.size
	box.clip_contents = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(box)
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.position = Vector2(4, 4)
		tr.size = rect.size - Vector2(8, 8)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(tr)
		if tex is ViewportTexture:
			cur_tr = tr
	box.modulate.a = 0.0
	box.pivot_offset = rect.size * 0.5
	box.scale = Vector2.ONE * 0.96
	var tw := create_tween().set_parallel(true)
	tw.tween_property(box, "modulate:a", 1.0, 0.45)
	tw.tween_property(box, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return box

func _window_frame(box: Control) -> void:
	# кадр «из окна»: белая рама с переплётом и подоконник поверх вида
	var col := Color(0.96, 0.95, 0.92)
	var w := box.size
	var t := w.y * 0.045
	for rr in [Rect2(0, 0, w.x, t), Rect2(0, w.y - t * 1.6, w.x, t * 1.6), Rect2(0, 0, t, w.y), Rect2(w.x - t, 0, t, w.y),
			Rect2(w.x * 0.5 - t * 0.4, 0, t * 0.8, w.y), Rect2(0, w.y * 0.36, w.x, t * 0.6)]:
		var c := ColorRect.new()
		c.color = col
		c.position = rr.position
		c.size = rr.size
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(c)
	var sh := ColorRect.new()                                    # тень на подоконнике
	sh.color = Color(0, 0, 0, 0.18)
	sh.position = Vector2(0, w.y - t * 1.6)
	sh.size = Vector2(w.x, t * 0.25)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(sh)

func _font(sz: float) -> int:
	return int(page.get_viewport_rect().size.y * sz)

func _caption(box: Control, text: String, at := Vector2(0.0, 0.0), w := 0.55) -> void:
	# плашка рассказчика: жёлтый прямоугольник у края кадра
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CAPTION
	sb.border_color = INK
	sb.set_border_width_all(3)
	sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 6; sb.content_margin_bottom = 6
	pc.add_theme_stylebox_override("panel", sb)
	var lb := Label.new()
	lb.text = text
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD
	lb.custom_minimum_size = Vector2(box.size.x * w - 20, 0)
	lb.add_theme_font_size_override("font_size", _font(0.032))
	lb.add_theme_color_override("font_color", INK)
	pc.add_child(lb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pc)
	pc.position = Vector2(4 + (box.size.x - box.size.x * w - 8) * at.x, 4 + (box.size.y * 0.75) * at.y)
	pc.modulate.a = 0.0
	create_tween().tween_property(pc, "modulate:a", 1.0, 0.4).set_delay(0.35)

func _bubble(box: Control, text: String, at: Vector2, tail: Vector2, think := false) -> void:
	# облачко: белое, с хвостиком к говорящему (tail — точка в кадре, 0..1); мысли — кружочками
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.border_color = INK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(40)
	sb.content_margin_left = 18; sb.content_margin_right = 18; sb.content_margin_top = 10; sb.content_margin_bottom = 10
	pc.add_theme_stylebox_override("panel", sb)
	var lb := Label.new()
	lb.text = text
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", _font(0.034))
	lb.add_theme_color_override("font_color", INK)
	if think:
		lb.add_theme_font_size_override("font_size", _font(0.031))
	pc.add_child(lb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.size = box.size
	box.add_child(layer)
	var tp := box.size * tail
	var c := box.size * at
	if think:
		for k in 3:                                              # кружочки мысли от головы к облаку
			var f := 0.25 + 0.25 * k
			var r := 5.0 + 4.0 * k
			var d := _disc(tp.lerp(c, f), r)
			layer.add_child(d)
	else:
		var dir := (tp - c).normalized()
		var side := Vector2(-dir.y, dir.x) * 12.0
		var tl := Polygon2D.new()
		tl.polygon = PackedVector2Array([c + side, c - side, tp])
		tl.color = Color.WHITE
		var ol := Line2D.new()
		ol.points = PackedVector2Array([c + side, tp, c - side])
		ol.width = 3.0
		ol.default_color = INK
		layer.add_child(ol)
		layer.add_child(tl)
	layer.add_child(pc)
	await get_tree().process_frame
	pc.position = c - pc.size * 0.5
	layer.modulate.a = 0.0
	create_tween().tween_property(layer, "modulate:a", 1.0, 0.35).set_delay(0.5)

func _disc(p: Vector2, r: float) -> Control:
	var d := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.border_color = INK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(r))
	d.add_theme_stylebox_override("panel", sb)
	d.size = Vector2(r, r) * 2.0
	d.position = p - Vector2(r, r)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d

func _sfx(box: Control, text: String, at: Vector2, rot_deg: float, col: Color, k := 1.0) -> void:
	# звук буквами: крупно, с толстой обводкой, под углом
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", _font(0.075 * k))
	lb.add_theme_color_override("font_color", col)
	lb.add_theme_color_override("font_outline_color", INK)
	lb.add_theme_constant_override("outline_size", int(_font(0.016 * k)))
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lb)
	await get_tree().process_frame
	lb.position = box.size * at - lb.size * 0.5
	lb.pivot_offset = lb.size * 0.5
	lb.rotation = deg_to_rad(rot_deg)
	lb.scale = Vector2.ONE * 1.6
	lb.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(lb, "scale", Vector2.ONE, 0.3).set_delay(0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lb, "modulate:a", 1.0, 0.2).set_delay(0.3)

func _phone_screen(box: Control, at: Vector2, h: float) -> void:
	# экран телефона — врезка в кадр: лента новостей
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.97, 0.98)
	sb.set_corner_radius_all(18)
	sb.border_color = Color(0.08, 0.08, 0.09)
	sb.set_border_width_all(9)
	sb.content_margin_left = 14; sb.content_margin_right = 14; sb.content_margin_top = 18; sb.content_margin_bottom = 18
	pc.add_theme_stylebox_override("panel", sb)
	var hh := box.size.y * h
	pc.custom_minimum_size = Vector2(hh * 0.66, hh)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pc.add_child(v)
	for it in [["СРОЧНО: авария в НИИ «Вектор-7»", "Утечка неизвестного вещества. Район оцеплен.", Color(0.75, 0.08, 0.06)],
			["Власти: не выходите из домов", "Закройте окна и двери. Оставайтесь в укрытиях.", Color(0.75, 0.08, 0.06)],
			["Погода: +21°, солнечно", "Выходные будут тёплыми.", Color(0.2, 0.3, 0.5)]]:
		var a := Label.new()
		a.text = it[0]
		a.autowrap_mode = TextServer.AUTOWRAP_WORD
		a.custom_minimum_size = Vector2(hh * 0.66 - 46, 0)
		a.add_theme_font_size_override("font_size", _font(0.024))
		a.add_theme_color_override("font_color", it[2])
		v.add_child(a)
		var b := Label.new()
		b.text = it[1]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		b.custom_minimum_size = Vector2(hh * 0.66 - 46, 0)
		b.add_theme_font_size_override("font_size", _font(0.02))
		b.add_theme_color_override("font_color", Color(0.25, 0.25, 0.28))
		v.add_child(b)
	box.add_child(pc)
	pc.position = box.size * at
	pc.rotation = deg_to_rad(-4.0)
	pc.modulate.a = 0.0
	create_tween().tween_property(pc, "modulate:a", 1.0, 0.4).set_delay(0.6)

# ---------- управление ----------
func _wait(s: float) -> void:
	tapped = false
	var e := 0.0
	while e < s and not skipping and not tapped:
		await get_tree().process_frame
		e += get_process_delta_time()

func _hold(s: float) -> void:
	# держать кадр s секунд (тап — дальше); при проверке кадрами — коротко
	await _wait(1.2 if shot_dir != "" else s)
	_freeze()

func _new_page() -> void:
	if page.get_child_count() > 0:
		await _page_snap()
		var tw := create_tween()
		tw.tween_property(page, "modulate:a", 0.0, 0.5)
		await tw.finished                                          # иначе твин успевает вернуть 0 после 1 — страница пустая
	for c in page.get_children():
		c.queue_free()
	page.modulate.a = 1.0
	page_n += 1

func _page_snap() -> void:
	if shot_dir == "":
		return
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_jpg("%s/page_%02d.jpg" % [shot_dir, page_n], 0.85)

func _px(r: Rect2) -> Vector2i:
	var s := _panel_rect(r).size * page.get_viewport().get_screen_transform().get_scale()
	return Vector2i(maxi(64, int(s.x)), maxi(64, int(s.y)))

func _cam(target: Vector3, off: Vector3) -> Vector3:
	return target + off

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
		sm.sky_top_color = Color(0.3, 0.5, 0.8)
		sm.sky_horizon_color = Color(0.74, 0.8, 0.86)
		sm.ground_horizon_color = Color(0.6, 0.62, 0.6)
		sm.ground_bottom_color = Color(0.3, 0.3, 0.28)
		sky.sky_material = sm
		_env.sky = sky
		_env.background_mode = Environment.BG_SKY
	_cam_size_keep = main.cam_size
	main.cam_size = 38.0
	main.camctl.visible = false
	main.daynight.auto = false
	var t_keep: float = main.daynight.t
	main.daynight.t = 8.5
	if main.weather:
		main.weather.set("rain", 0.0)
	var up := Vector3.UP
	var h := hy()
	var floor_y := h + 0.64
	var sy: float = S.shed_y + 0.35 + 0.02
	await get_tree().process_frame
	create_tween().tween_property(fade, "color:a", 0.0, 0.8)

	# ===== Страница 1: утро =====
	await _new_page()
	var r := Rect2(0, 0, 1, 0.52)
	hero.visible = false
	var hc := w3(L(0.0, 2.0), h + 1.8)
	var tex := await _snap_panel(hc + hv(-9.0, 24.0, 6.0), hc + hv(0.5, 0.0, -0.5), 46.0, _px(r))
	var b := _frame(_panel_rect(r), tex)
	_caption(b, "Суббота. Дом у Большого озера.", Vector2(0, 0), 0.42)
	await _hold(3.5)
	if skipping:
		await _finish(t_keep)
		return
	_hide_roofs(["hero_house_roof"])
	r = Rect2(0, 0.52, 0.5, 0.48)
	_sleep_place(h)
	_play_pose("Sleep", 0.2)
	fill.global_position = w3(L(2.0, 1.4), h + 2.3)
	fill.light_energy = 1.4
	var head := w3(L(3.0, 3.25), h + 1.25)
	tex = await _snap_panel(head + hv(-1.6, -2.0, 1.2), head + hv(-0.6, 0.0, -0.15), 44.0, _px(r))
	b = _frame(_panel_rect(r), tex)
	_caption(b, "7:00", Vector2(0, 0), 0.22)
	_sfx(b, "БИП-БИП-БИП!", Vector2(0.62, 0.22), -8.0, Color(1.0, 0.35, 0.2))
	alarm_v = 1.0
	await _hold(3.0)
	alarm_v = 0.0
	if skipping:
		await _finish(t_keep)
		return
	r = Rect2(0.5, 0.52, 0.5, 0.48)
	_pose("SitIdle", 1.0, L(2.3, 2.62), floor_y, yaw_to(ld(0, -1)))
	var ch := hero.global_position + up * 1.15
	fill.global_position = ch + hv(0.6, -1.4, 0.8)
	tex = await _snap_panel(ch + hv(0.9, -2.3, 0.3), ch + hv(0.0, 0.0, -0.15), 42.0, _px(r))
	b = _frame(_panel_rect(r), tex)
	_bubble(b, "Ещё пять минут…\nили пять часов.", Vector2(0.3, 0.2), Vector2(0.48, 0.38), true)
	await _hold(3.5)
	if skipping:
		await _finish(t_keep)
		return

	# ===== Страница 2: потянулся, умылся, окно =====
	await _new_page()
	r = Rect2(0, 0, 0.38, 1)
	var sp := L(2.3, 2.62) + ld(0, -1) * MOVE_STAND / T
	_pose("Stretch", 1.35, sp, floor_y, yaw_to(ld(0, -1)))
	ch = hero.global_position + up * 1.3
	fill.global_position = ch + hv(-0.8, -1.6, 0.8)
	tex = await _snap_panel(ch + hv(-1.0, -3.4, 0.1), ch + hv(0.0, 0.0, 0.0), 46.0, _px(r))
	b = _frame(_panel_rect(r), tex)
	_sfx(b, "У-А-АХ…", Vector2(0.5, 0.12), 6.0, Color(1.0, 0.85, 0.3), 0.8)
	await _hold(3.0)
	if skipping:
		await _finish(t_keep)
		return
	r = Rect2(0.38, 0, 0.62, 0.55)
	_pose("WashFace", 6.6, L(-2.6, -2.55), floor_y, yaw_to(ld(0, -1)))
	ch = hero.global_position + up * 1.45
	fill.global_position = ch + hv(1.2, 1.0, 0.6)
	tex = await _snap_panel(ch + hv(1.6, 0.35, 0.25), ch + hv(0.0, -0.2, -0.2), 44.0, _px(r))
	b = _frame(_panel_rect(r), tex)
	_caption(b, "Холодная вода — лучший будильник.", Vector2(0, 0), 0.5)
	_sfx(b, "ПЛЮХ!", Vector2(0.25, 0.75), -10.0, Color(0.4, 0.75, 1.0), 0.9)
	water_v = 1.0
	await _hold(3.0)
	water_v = 0.0
	if skipping:
		await _finish(t_keep)
		return
	r = Rect2(0.38, 0.55, 0.62, 0.45)
	_pose("Idle", 0.5, L(-0.6, 3.3), floor_y, yaw_to(ld(0, 1)))
	ch = hero.global_position + up * 1.5
	fill.global_position = ch + hv(-1.5, -1.0, 0.5)
	tex = await _snap_panel(ch + hv(-1.7, -1.2, 0.25), ch + hv(0.2, 0.6, -0.1), 46.0, _px(r))
	b = _frame(_panel_rect(r), tex)
	_bubble(b, "А там что?..", Vector2(0.28, 0.25), Vector2(0.5, 0.42), true)
	await _hold(3.0)
	if skipping:
		await _finish(t_keep)
		return
	_show_roofs()

	# ===== Страница: вид из окна — во всю страницу =====
	await _new_page()
	fill.light_energy = 0.0
	hero.visible = false
	r = Rect2(0, 0, 1, 1)
	var wp := w3(L(-0.6, 4.3), h + 2.2)                         # из проёма окна гостиной — на озеро
	tex = await _snap_panel(wp, w3(L(2.0, 26.0), h + 0.2), 52.0, _px(r))
	b = _frame(_panel_rect(r), tex)
	_window_frame(b)
	_caption(b, "План на день: ничего не делать. Выполню на все сто.", Vector2(0, 1), 0.42)
	await _hold(4.5)
	if skipping:
		await _finish(t_keep)
		return
	hero.visible = true

	# ===== Страница 3: веранда, телефон =====
	await _new_page()
	fill.light_energy = 0.0
	main.daynight.t = 9.5
	r = Rect2(0, 0, 1, 0.46)
	var chair_p := L(1.5, 5.62)
	_pose("SitIdle", 0.6, chair_p, h + 0.6, yaw_to(ld(0, 1)))
	ch = hero.global_position + up * 1.0
	tex = await _snap_panel(ch + hv(-3.0, -1.0, 1.2), ch + hv(1.5, 6.0, -0.7), 50.0, _px(r))
	b = _frame(_panel_rect(r), tex)
	_caption(b, "Кофе на веранде. Озеро как зеркало.", Vector2(0, 0), 0.4)
	await _hold(3.5)
	if skipping:
		await _finish(t_keep)
		return
	r = Rect2(0, 0.46, 0.55, 0.54)
	_pose("SitPhoneRead", 0.4, chair_p, h + 0.6, yaw_to(ld(0, 1)))
	phone_mi.visible = true
	ch = hero.global_position + up * 1.15
	fill.global_position = ch + hv(0.5, 1.0, 0.3)
	fill.light_energy = 0.8
	tex = await _snap_panel(ch + hv(-0.5, -0.6, 0.45), ch + hv(0.1, 0.4, -0.3), 40.0, _px(r))
	b = _frame(_panel_rect(r), tex)
	_phone_screen(b, Vector2(0.5, 0.08), 0.84)
	_caption(b, "Что там в новостях?", Vector2(0, 0), 0.45)
	await _hold(5.0)
	if skipping:
		await _finish(t_keep)
		return
	r = Rect2(0.55, 0.46, 0.45, 0.54)
	var face := hero.global_position + up * 1.2
	fill.global_position = face + hv(0.0, 0.6, -0.1)
	fill.light_color = Color(0.75, 0.85, 1.0)                  # свет экрана на лице
	fill.light_energy = 1.2
	tex = await _snap_panel(face + hv(0.35, 1.1, 0.05), face + hv(0.0, 0.0, 0.05), 32.0, _px(r))
	fill.light_color = Color(1.0, 0.9, 0.78)
	b = _frame(_panel_rect(r), tex)
	_bubble(b, "Утечка?.. А я только\nкофе налил.", Vector2(0.5, 0.17), Vector2(0.5, 0.42), true)
	await _hold(4.0)
	if skipping:
		await _finish(t_keep)
		return

	# ===== Страница 4: сирена, бег, паника =====
	await _new_page()
	phone_mi.visible = false
	fill.light_energy = 0.0
	main.daynight.t = 10.5
	r = Rect2(0, 0, 0.5, 0.55)
	_pose("StandUp", 0.9, chair_p, h + 0.6, yaw_to(ld(0, 1)))
	ch = hero.global_position + up * 1.0
	tex = await _snap_panel(ch + hv(1.8, 3.4, 0.2), ch + hv(0.0, 0.0, 0.2), 42.0, _px(r))
	b = _frame(_panel_rect(r), tex)
	_sfx(b, "ВУУУУУУ!", Vector2(0.5, 0.18), -6.0, Color(1.0, 0.25, 0.2))
	siren = 1.0
	await _hold(3.0)
	if skipping:
		await _finish(t_keep)
		return
	r = Rect2(0.5, 0, 0.5, 0.55)
	var rp := L(7.0, 4.5)
	var rdir: Vector2 = (S.shed_door as Vector2) - rp
	_pose("Run", 0.18, rp, gh(rp), yaw_to(rdir))
	ch = hero.global_position + up * 1.0
	var rf := Vector3(rdir.x, 0, rdir.y).normalized()
	var rs := rf.cross(up)
	tex = await _snap_panel(ch + rf * 3.2 + rs * 1.6 - up * 0.3, ch + up * 0.1, 46.0, _px(r))
	b = _frame(_panel_rect(r), tex)
	_caption(b, "Это не учения.", Vector2(0, 1), 0.4)
	_bubble(b, "Кофе, прости!", Vector2(0.25, 0.2), Vector2(0.47, 0.38))
	await _hold(3.0)
	if skipping:
		await _finish(t_keep)
		return
	r = Rect2(0, 0.55, 1, 0.45)
	hero.visible = false
	var vc := Vector2(WorldGen.FEATURES["village"].x, WorldGen.FEATURES["village"].y)
	var plots: Array = props._plots.filter(func(q): return (q[0] as Vector2).distance_to(vc) < 50.0)
	plots.sort_custom(func(a, c): return (a[0] as Vector2).distance_to(vc) < (c[0] as Vector2).distance_to(vc))
	var cen := vc
	if not plots.is_empty():
		cen = plots[0][0]
	var cg := gh(cen)
	var look := w3(cen, cg + 2.0)
	var eye := look + Vector3(9, 0.2, 13)                      # камера на уровне глаз: жители бегут перед пожаркой
	var vdir := (look - eye).normalized()
	var vside := vdir.cross(up).normalized()
	for i in npcs.size():                                       # жители бегут через кадр, между камерой и домами
		var hd := Vector3(vdir.x, 0, vdir.z).normalized()          # по земле: 6–11 м от камеры, ближе здания в центре
		var gx := Vector3(eye.x, 0, eye.z) + hd * (6.0 + 1.3 * i) + vside * (float(i % 3) - 1.0) * 2.8
		var np := Vector2(gx.x, gx.z) / T
		var to := Vector2(vside.x, vside.z) * (1.0 if i % 2 == 0 else -1.0) + Vector2(vdir.x, vdir.z) * 0.4
		_npc_pose(npcs[i], "Run", 0.12 * i, np, yaw_to(to))
	_air("heli_fly", look + vdir * 40.0 + vside * 8.0 + up * 16.0, -vside)
	heli_v = 1.0
	tex = await _snap_panel(eye, look + up * 2.5, 50.0, _px(r))
	b = _frame(_panel_rect(r), tex)
	_caption(b, "В деревне — паника. Над крышами — вертолёт.", Vector2(0, 0), 0.4)
	_sfx(b, "ДЫН-ДЫН-ДЫН", Vector2(0.75, 0.2), 4.0, Color(0.95, 0.85, 0.4), 0.8)
	await _hold(4.0)
	if skipping:
		await _finish(t_keep)
		return
	_clear_scene()

	# ===== Страница 5: бункер =====
	await _new_page()
	heli_v = 0.0
	_hide_roofs(["hero_shed_roof"])
	lid.rotation.x = deg_to_rad(110.0)
	r = Rect2(0, 0, 0.5, 1)
	_pose("Idle", 0.3, SL(1.45, 0.35), sy, yaw_to(ld(-1, 0)))
	ch = hero.global_position + up * 1.0
	var hatch := w3(SL(0.7, 0.35), sy)
	fill.global_position = hatch + hv(0.0, -1.0, 2.0)
	fill.light_energy = 1.2
	tex = await _snap_panel(hatch + hv(-0.9, -2.1, 2.6), hatch + hv(0.35, 0.0, 0.5), 50.0, _px(r))
	b = _frame(_panel_rect(r), tex)
	_caption(b, "Бункер. Три года копал. Соседи смеялись.", Vector2(0, 0), 0.8)
	await _hold(4.0)
	if skipping:
		await _finish(t_keep)
		return
	r = Rect2(0.5, 0, 0.5, 0.62)
	_pose("ClimbDown", 0.3, SL(0.7, 0.3), sy - 0.75, yaw_to(ld(0, 1)))
	tex = await _snap_panel(hatch + hv(0.5, -1.9, 2.4), hatch + hv(0.0, 0.1, 0.2), 48.0, _px(r))
	b = _frame(_panel_rect(r), tex)
	_sfx(b, "ЛЯЗГ", Vector2(0.72, 0.8), -12.0, Color(0.85, 0.85, 0.9), 0.8)
	siren = 0.0
	await _hold(3.0)
	if skipping:
		await _finish(t_keep)
		return
	r = Rect2(0.5, 0.62, 0.5, 0.38)
	b = _frame(_panel_rect(r), null, true)
	var mlb := Label.new()
	mlb.text = "Прошёл месяц…"
	mlb.add_theme_font_size_override("font_size", _font(0.06))
	mlb.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	mlb.set_anchors_preset(Control.PRESET_FULL_RECT)
	mlb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mlb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(mlb)
	await _hold(3.5)
	if skipping:
		await _finish(t_keep)
		return

	# ===== Страница 6: тишина =====
	await _new_page()
	main.daynight.t = 17.6
	r = Rect2(0, 0, 0.42, 1)
	_pose("ClimbUp", 0.2, SL(0.7, 0.3), sy - 1.05, yaw_to(ld(0, 1)))
	fill.global_position = hatch + hv(0.0, -0.8, 1.2)
	fill.light_color = Color(1.0, 0.7, 0.45)
	fill.light_energy = 1.0
	tex = await _snap_panel(hatch + hv(1.0, -0.6, 0.65), hatch + hv(0.0, 0.15, 0.4), 50.0, _px(r))
	b = _frame(_panel_rect(r), tex)
	_sfx(b, "СКРИИП…", Vector2(0.5, 0.15), 8.0, Color(0.9, 0.8, 0.6), 0.7)
	await _hold(3.5)
	if skipping:
		await _finish(t_keep)
		return
	_show_roofs()
	lid.rotation.x = 0.0
	fill.light_energy = 0.0
	r = Rect2(0.42, 0, 0.58, 1)
	var out_p: Vector2 = (S.shed_door as Vector2) + (S.f as Vector2) * 6.0
	_pose("LookAround", 3.0, out_p, gh(out_p), yaw_to(S.f))
	ch = hero.global_position + up * 1.2
	var ff := Vector3((S.f as Vector2).x, 0, (S.f as Vector2).y)
	tex = await _snap_panel(ch - ff * 2.6 + hv(1.2, 0, 0) + up * 0.4, ch + ff * 20.0 - up * 0.8, 50.0, _px(r))
	b = _frame(_panel_rect(r), tex)
	_caption(b, "Тишина. Никого.", Vector2(0, 0), 0.4)
	_bubble(b, "Кажется, я немного\nпроспал…", Vector2(0.55, 0.35), Vector2(0.82, 0.5), true)
	await _hold(5.0)
	await _finish(t_keep)

func _sleep_place(h: float) -> void:
	# лёжа на боку: голова на подушке (у изголовья, +X дома), тело вдоль кровати, на матрасе
	var hv2 := Vector2(SLEEP_HEAD.x - SLEEP_HIPS.x, -(SLEEP_HEAD.y - SLEEP_HIPS.y))
	var want := ld(1, 0)
	var yaw := atan2(want.x, want.y) - atan2(hv2.x, hv2.y)
	hero.rotation = Vector3(0, yaw, 0)
	var head_m := Vector3(SLEEP_HEAD.x, 0, -SLEEP_HEAD.y).rotated(Vector3.UP, yaw)
	var pos := w3(L(3.2, 3.25), 0.0) - head_m
	hero.global_position = Vector3(pos.x, h + 1.12, pos.z)

func _play_pose(clip: String, t: float) -> void:
	hero.visible = true
	if anim and anim.has_animation(clip):
		anim.play(clip, 0.0)
		anim.seek(t, true)
		anim.pause()

func _finish(t_keep: float) -> void:
	await _page_snap()
	siren = 0.0
	heli_v = 0.0
	alarm_v = 0.0
	water_v = 0.0
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.8)
	await get_tree().create_timer(0.85).timeout
	_clear_scene()
	hero.visible = false
	lid.rotation.x = 0.0
	main.daynight.t = t_keep
	main.daynight.auto = true
	if _env:
		_env.background_mode = _bg_keep[0]
		_env.background_color = _bg_keep[1]
	main.cam_size = _cam_size_keep
	main.camctl.visible = true
	main.cam.make_current()
	var out_p: Vector2 = (S.shed_door as Vector2) + (S.f as Vector2) * 6.0
	main.teleport(out_p)
	page.visible = false
	ui.get_child(0).visible = false
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
	if cur_tr:
		live_t += dt
		var k := clampf(live_t / 6.0, 0.0, 1.0)
		pcam.global_position = live_a.lerp(live_b, k * k * (3.0 - 2.0 * k))
		pcam.look_at(live_look, Vector3.UP)
	_audio()

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
			s += (2.0 * fmod(_ph[0], 1.0) - 1.0) * 0.16 * siren
		if heli_v > 0.0:                                            # вертолёт: удары лопастей ~5 Гц
			var w := _rng.randf() * 2.0 - 1.0
			_lp += 0.08 * (w - _lp)
			var thump := pow(0.5 + 0.5 * sin(_st * TAU * 5.2), 6.0)
			s += _lp * 1.6 * thump * heli_v
		if alarm_v > 0.0:                                           # будильник: 4 писка, пауза
			var on_b := fmod(_st, 1.0) < 0.5 and fmod(_st, 0.125) < 0.07
			_ph[1] += 2300.0 * dt
			s += (0.08 * sin(_ph[1] * TAU) if on_b else 0.0) * alarm_v
		if water_v > 0.0:                                           # вода из крана: мягкий шум
			var wn := _rng.randf() * 2.0 - 1.0
			_wl += 0.25 * (wn - _wl)
			s += (wn - _wl) * 0.07 * water_v
		s = clampf(s * (1.0 if on else 0.0), -1.0, 1.0)
		buf[i] = Vector2(s, s)
	_pb.push_buffer(buf)

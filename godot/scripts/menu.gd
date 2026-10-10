extends CanvasLayer
# Главное меню «КАРАНТИН». Фон — живой мир игры: ночь, Лагерь выживших, костёр (пламя и искры — props.gd), герой
# сидит на бревне у огня, камера медленно кружит; за баррикадами по кругу бродят тёмные силуэты.
# Поверх — зерно плёнки и виньетка, название с печатью «ЗОНА ЗАКРЫТА», внизу рация: обрывки сводок печатаются
# по буквам под треск эфира. Кнопки — бумажные бирки на бечёвке справа, качаются на ветру, от тапа дёргаются.
# Новая игра → сложность (бирки) → карточка с условиями → «Начать». Настройки, Авторы — карточки на бумаге.
# Проверка без телефона: --menu --menushot=<файл.jpg> → снимок меню через 25 с и выход.
signal closed
var main
var _rng := RandomNumberGenerator.new()
var hero: Node3D
var walkers: Array = []                 # [узел, угол, радиус, скорость]
var fire_c := Vector2.ZERO              # центр костра (тайлы)
var t := 0.0
var orbit := 0.0
var root: Control
var tags_c: Control
var card: Control = null
var title_box: Control
var stamp: Control
var radio_lbl: Label
var radio_dot: ColorRect
var fade: ColorRect
var tags: Array = []                    # {text, sub, act, a, v, rest}
var _pending := Callable()
var _pending_t := 0.0
var _busy := false
var screen := "root"
var F_TITLE: Font
var F_TAG: Font
var F_MONO: Font
const T := WorldGen.T
const PAPER := Color(0.87, 0.81, 0.67)
const INK := Color(0.12, 0.10, 0.08)
const RED := Color(0.72, 0.1, 0.07)
const BONE := Color(0.93, 0.9, 0.82)
const DIFFS := [
	["Турист", "зомби редко и медленные · лута много · урон по тебе ×0,5 · смерть: возрождение в лагере, вещи остаются"],
	["Выживший", "зомби обычно · лут обычный · урон ×1 · смерть: возрождение, рюкзак остаётся на месте гибели"],
	["Ветеран", "зомби часто, ночью быстрее · лута мало · урон ×1,5 · смерть: всё снаряжение теряется"],
	["Одна жизнь", "как Ветеран · смерть удаляет сохранение · только автосохранение"],
]
const RADIO := [
	"…говорит штаб гражданской обороны района. Сохраняйте спокойствие…",
	"…трасса перекрыта. Не пытайтесь покинуть зону карантина…",
	"…эвакуационный пункт у НИИ «Вектор-7» закрыт. Повторяю: закрыт…",
	"…двери не открывать. На голоса родных не выходить…",
	"…ночью они идут на свет и на шум…",
	"…приём… есть кто живой? Лесопилка, ответьте… приём…",
	"…день сто восемьдесят третий. Связи с районом нет…",
]
var _radio_i := 0
var _radio_n := 0.0
var _radio_hold := 0.0
# звук: треск костра и эфир — синтез
var _pb: AudioStreamGeneratorPlayback
var _br := 0.0
var _cr := 0.0
var _click := 0.0
var _hp := 0.0
var _static := 0.0
const RATE := 16000.0

func _ready() -> void:
	layer = 5
	_rng.randomize()
	F_TITLE = _font(["Roboto Condensed", "sans-serif-condensed", "DejaVu Sans Condensed", "Arial Narrow", "sans-serif"], 800, 10)
	F_TAG = _font(["Roboto Condensed", "sans-serif-condensed", "DejaVu Sans Condensed", "sans-serif"], 700, 2)
	F_MONO = _font(["Droid Sans Mono", "monospace", "DejaVu Sans Mono", "Courier New"], 400, 0)
	_scene()
	_ui()
	_sound()
	_root_tags()
	var sp := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--menushot="):
			sp = a.substr(11)
	if sp != "":
		_shot(sp)

func _font(names: Array, w: int, sp: int) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.font_weight = w
	var v := FontVariation.new()
	v.base_font = f
	v.spacing_glyph = sp
	return v

# ---------------- сцена: лагерь ночью ----------------
func _scene() -> void:
	var cf: Dictionary = WorldGen.FEATURES["camp"]
	fire_c = Vector2(cf.x, cf.y)
	main.daynight.auto = false
	main.daynight.t = 23.4
	main.hud.visible = false
	main.camctl.visible = false
	main.camctl.process_mode = Node.PROCESS_MODE_DISABLED
	main.teleport(fire_c)
	orbit = _rng.randf_range(0.0, 360.0)
	if not ResourceLoader.exists("res://assets/character/hero.glb"):
		return
	var hs: PackedScene = load("res://assets/character/hero.glb")
	var th: float = main.props.loc_th.get("camp", 0.0)
	var bp: Vector2 = fire_c + Vector2(1.4 * 1.25, 3.0 * 1.25).rotated(-th)   # бревно у костра (props.gd LOCS.camp)
	hero = hs.instantiate()
	main.add_child(hero)
	hero.global_position = Vector3(bp.x * T, WorldGen.height_m(bp.x, bp.y), bp.y * T)
	var d := fire_c - bp
	hero.rotation.y = atan2(d.x, d.y)
	var ap: AnimationPlayer = hero.find_child("AnimationPlayer", true, false)
	if ap and ap.has_animation("SitIdle"):
		ap.play("SitIdle")
		ap.speed_scale = 0.45
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.035, 0.035, 0.04)
	dark.roughness = 1.0
	for i in 3:                                                    # силуэты за баррикадами
		var w: Node3D = hs.instantiate()
		main.add_child(w)
		for mi in w.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = dark
		w.scale = Vector3(1.0, _rng.randf_range(0.92, 1.02), 1.0)
		var wa: AnimationPlayer = w.find_child("AnimationPlayer", true, false)
		var clip := "WalkSlow" if wa and wa.has_animation("WalkSlow") else "Walk"
		if wa and wa.has_animation(clip):
			wa.play(clip)
			wa.speed_scale = _rng.randf_range(0.5, 0.62)
			wa.seek(_rng.randf_range(0.0, 2.0), true)
		var r := _rng.randf_range(14.5, 17.0)                       # тайлов от костра (баррикады ~12)
		walkers.append([w, float(i) * TAU / 3.0 + _rng.randf_range(-0.4, 0.4), r, 0.5 * _rng.randf_range(0.85, 1.1) / (r * T) * (1.0 if i != 1 else -1.0)])

func _process(dt: float) -> void:
	t += dt
	# камера: низко, медленный облёт костра; костёр — левее центра (справа бирки), чуть ниже
	orbit = fposmod(orbit + dt * 2.2, 360.0)
	main.cam_yaw = orbit
	main.cam_elev = 24.0 + 2.0 * sin(t * 0.11)
	main.cam_size = 9.5
	var vs := get_viewport().get_visible_rect().size
	var yr := deg_to_rad(orbit)
	var right := Vector2(cos(yr), -sin(yr))
	var fwd := Vector2(-sin(yr), -cos(yr))
	var hw: float = main.cam_size * vs.x / maxf(vs.y, 1.0) * 0.5
	main.focus = fire_c + (right * hw * 0.32 + fwd * 2.6) / T
	main.daynight.t = 23.4
	var fh := WorldGen.height_m(fire_c.x, fire_c.y)
	main.world.set_see_hole(Vector3(fire_c.x * T, fh + 1.0, fire_c.y * T), 7.5)
	for wk in walkers:
		var n: Node3D = wk[0]
		wk[1] = fposmod(wk[1] + wk[3] * dt, TAU)
		var p: Vector2 = fire_c + Vector2(cos(wk[1]), sin(wk[1])) * (wk[2] + 0.8 * sin(t * 0.3 + wk[2]))
		n.global_position = Vector3(p.x * T, WorldGen.height_m(p.x, p.y), p.y * T)
		var tg := Vector2(-sin(wk[1]), cos(wk[1])) * signf(wk[3])
		n.rotation.y = atan2(tg.x, tg.y)
	_tags_step(dt)
	_radio_step(dt)
	radio_dot.modulate.a = 0.35 + 0.65 * float(int(t * 2.0) % 2)
	if _pending.is_valid():
		_pending_t -= dt
		if _pending_t <= 0.0:
			var c := _pending
			_pending = Callable()
			c.call()
	_audio()

# ---------------- интерфейс ----------------
func _ui() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var film := ColorRect.new()                                    # виньетка + зерно плёнки
	film.set_anchors_preset(Control.PRESET_FULL_RECT)
	film.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	float d = length((UV - vec2(0.42, 0.5)) * vec2(1.5, 1.0));
	float v = smoothstep(0.38, 1.0, d) * 0.92;
	v = max(v, smoothstep(0.55, 1.0, UV.x) * 0.45);                 // справа темнее — под бирками
	float g = h(floor(FRAGCOORD.xy / 2.0) + vec2(floor(TIME * 20.0) * 17.0, 0.0));
	float ga = abs(g - 0.5) * 0.16;
	float a = v + ga - v * ga;
	vec3 c = mix(vec3(0.01, 0.012, 0.02), vec3(step(0.5, g)), ga / max(a, 0.001));
	COLOR = vec4(c, a);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	film.material = m
	root.add_child(film)

	title_box = Control.new()
	title_box.position = Vector2(46, 26)
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_box)
	var ttl := Label.new()
	ttl.text = "КАРАНТИН"
	ttl.add_theme_font_override("font", F_TITLE)
	ttl.add_theme_font_size_override("font_size", 82)
	ttl.add_theme_color_override("font_color", BONE)
	ttl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	ttl.add_theme_constant_override("shadow_offset_x", 3)
	ttl.add_theme_constant_override("shadow_offset_y", 4)
	title_box.add_child(ttl)
	var sub := Label.new()
	sub.text = "северная глубинка · конец октября · связи нет"
	sub.position = Vector2(6, 100)
	sub.add_theme_font_override("font", F_MONO)
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color(BONE, 0.62))
	title_box.add_child(sub)
	stamp = PanelContainer.new()                                    # красная печать поверх названия
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(0, 0, 0, 0)
	ss.border_color = RED
	ss.set_border_width_all(4)
	ss.set_corner_radius_all(4)
	ss.content_margin_left = 12; ss.content_margin_right = 12; ss.content_margin_top = 2; ss.content_margin_bottom = 2
	stamp.add_theme_stylebox_override("panel", ss)
	var sl := Label.new()
	sl.text = "ЗОНА ЗАКРЫТА"
	sl.add_theme_font_override("font", F_TITLE)
	sl.add_theme_font_size_override("font_size", 26)
	sl.add_theme_color_override("font_color", RED)
	stamp.add_child(sl)
	stamp.position = Vector2(470, 2)
	stamp.rotation = deg_to_rad(-9.0)
	stamp.modulate.a = 0.0
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.add_child(stamp)
	var tw := create_tween()                                        # печать бьёт с размаху
	tw.tween_interval(1.4)
	tw.tween_callback(func():
		stamp.pivot_offset = stamp.size / 2.0
		stamp.scale = Vector2(2.2, 2.2)
		_click = 1.0)
	tw.tween_property(stamp, "modulate:a", 0.88, 0.12)
	tw.parallel().tween_property(stamp, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	var radio := HBoxContainer.new()                                # рация внизу слева
	radio.add_theme_constant_override("separation", 10)
	radio.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	radio.position = Vector2(48, -58)
	radio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(radio)
	radio_dot = ColorRect.new()
	radio_dot.color = Color(0.95, 0.15, 0.1)
	radio_dot.custom_minimum_size = Vector2(9, 9)
	radio_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	radio.add_child(radio_dot)
	var fq := Label.new()
	fq.text = "ЭФИР 1458 кГц"
	fq.add_theme_font_override("font", F_MONO)
	fq.add_theme_font_size_override("font_size", 15)
	fq.add_theme_color_override("font_color", Color(0.95, 0.55, 0.3, 0.85))
	radio.add_child(fq)
	radio_lbl = Label.new()
	radio_lbl.add_theme_font_override("font", F_MONO)
	radio_lbl.add_theme_font_size_override("font_size", 17)
	radio_lbl.add_theme_color_override("font_color", Color(BONE, 0.8))
	radio.add_child(radio_lbl)
	var ver := Label.new()
	ver.text = main.hud.VERSION
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.position = Vector2(-200, -30)
	ver.size = Vector2(186, 20)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.add_theme_font_size_override("font_size", 12)
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	root.add_child(ver)

	tags_c = Control.new()
	tags_c.set_anchors_preset(Control.PRESET_FULL_RECT)
	tags_c.mouse_filter = Control.MOUSE_FILTER_PASS
	tags_c.draw.connect(_draw_tags)
	tags_c.gui_input.connect(_tags_input)
	root.add_child(tags_c)

	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	create_tween().tween_property(fade, "color:a", 0.0, 1.6)

# ---------------- бирки на бечёвке ----------------
const TAG_W := 286.0
const TAG_H := 58.0
func _set_tags(list: Array) -> void:
	tags.clear()
	for i in list.size():
		var e: Dictionary = list[i]
		e.a = -0.9                                                  # влетают сверху-сбоку
		e.v = 0.0
		e.rest = -0.035 + 0.05 * sin(float(i) * 2.3)
		e.d = float(i) * 0.07                                       # задержка появления
		tags.append(e)
	tags_c.queue_redraw()

func _tw_x(y: float) -> float:
	return get_viewport().get_visible_rect().size.x - 64.0 + sin(y * 0.012 + t * 0.6) * 3.0

func _knot(i: int) -> Vector2:
	var vs := get_viewport().get_visible_rect().size
	var gap := minf(78.0, (vs.y - 90.0) / maxf(tags.size(), 1.0))
	var y0 := (vs.y - gap * (tags.size() - 1)) * 0.5 - 6.0
	var y := y0 + gap * i
	return Vector2(_tw_x(y), y)

func _tag_xf(i: int) -> Transform2D:
	var e: Dictionary = tags[i]
	return Transform2D(e.a, _knot(i) + Vector2(-26.0, 3.0))

func _tags_step(dt: float) -> void:
	for i in tags.size():
		var e: Dictionary = tags[i]
		if e.d > 0.0:
			e.d -= dt
			continue
		var wind := 0.9 * sin(t * 1.3 + i * 0.9) + 0.5 * sin(t * 2.9 + i * 2.1)
		e.v += (-34.0 * (e.a - e.rest) - 4.2 * e.v + wind) * dt
		e.a += e.v * dt
	tags_c.queue_redraw()

func _tag_poly() -> PackedVector2Array:
	var L := -TAG_W + 18.0
	var R := 18.0
	var c := 16.0
	var h2 := TAG_H * 0.5
	return PackedVector2Array([Vector2(L, -h2), Vector2(R - c, -h2), Vector2(R, -h2 + c), Vector2(R, h2 - c), Vector2(R - c, h2), Vector2(L, h2)])

func _draw_tags() -> void:
	var vs := get_viewport().get_visible_rect().size
	var pts := PackedVector2Array()                                 # бечёвка сверху донизу
	var y := -10.0
	while y <= vs.y + 10.0:
		pts.append(Vector2(_tw_x(y), y))
		y += 12.0
	tags_c.draw_polyline(pts, Color(0.08, 0.06, 0.04, 0.6), 5.0)
	tags_c.draw_polyline(pts, Color(0.62, 0.5, 0.33), 3.0)
	y = -6.0
	while y <= vs.y:                                                # скрутка
		var x := _tw_x(y)
		tags_c.draw_line(Vector2(x - 1.5, y), Vector2(x + 1.5, y + 4.0), Color(0.35, 0.27, 0.16), 1.0)
		y += 6.0
	var poly := _tag_poly()
	for i in tags.size():
		var e: Dictionary = tags[i]
		if e.d > 0.0:
			continue
		var k := _knot(i)
		var xf := _tag_xf(i)
		tags_c.draw_set_transform_matrix(Transform2D.IDENTITY)
		tags_c.draw_line(k, xf.origin, Color(0.62, 0.5, 0.33), 2.0)
		tags_c.draw_circle(k, 4.0, Color(0.5, 0.4, 0.26))
		tags_c.draw_set_transform_matrix(Transform2D(e.a, xf.origin + Vector2(5, 7)))
		tags_c.draw_colored_polygon(poly, Color(0, 0, 0, 0.4))      # тень
		tags_c.draw_set_transform_matrix(xf)
		var pc: Color = PAPER.darkened(0.06 * float(i % 3)) if not e.get("dim", false) else PAPER.darkened(0.35)
		tags_c.draw_colored_polygon(poly, pc)
		tags_c.draw_polyline(poly + PackedVector2Array([poly[0]]), Color(0.45, 0.38, 0.27, 0.8), 1.5)
		tags_c.draw_rect(Rect2(-TAG_W + 18.0, -TAG_H * 0.5, 7.0, TAG_H), Color(RED, 0.75) if e.get("red", false) else Color(0.4, 0.33, 0.22, 0.5))
		tags_c.draw_circle(Vector2.ZERO, 8.0, Color(0.55, 0.5, 0.38))   # люверс
		tags_c.draw_circle(Vector2.ZERO, 4.5, Color(0.1, 0.08, 0.06))
		var sub: String = e.get("sub", "")
		var ty := 8.0 if sub == "" else 0.0
		tags_c.draw_string(F_TAG, Vector2(-TAG_W + 36.0, ty), e.text, HORIZONTAL_ALIGNMENT_LEFT, TAG_W - 70.0, 27, INK)
		if sub != "":
			tags_c.draw_string(F_MONO, Vector2(-TAG_W + 37.0, 20.0), sub, HORIZONTAL_ALIGNMENT_LEFT, TAG_W - 70.0, 13, Color(INK, 0.6))
		tags_c.draw_string(F_MONO, Vector2(-36.0, -14.0), "%02d" % (i + 1), HORIZONTAL_ALIGNMENT_RIGHT, 24.0, 11, Color(RED, 0.7))
	tags_c.draw_set_transform_matrix(Transform2D.IDENTITY)

func _tags_input(ev: InputEvent) -> void:
	var p := Vector2.ZERO
	if ev is InputEventScreenTouch and ev.pressed:
		p = ev.position
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		p = ev.position
	else:
		return
	if _busy or _pending.is_valid():
		return
	var poly := _tag_poly()
	for i in tags.size():
		var e: Dictionary = tags[i]
		if e.d > 0.0:
			continue
		var lp: Vector2 = _tag_xf(i).affine_inverse() * p
		if Geometry2D.is_point_in_polygon(lp, poly):
			e.v += 7.0                                              # дёрнуть бирку
			_click = 0.8
			_pending = e.act
			_pending_t = 0.28
			tags_c.accept_event()
			return

func _root_tags() -> void:
	screen = "root"
	_close_card()
	var list := []
	if main.has_save():
		list.append({"text": "Продолжить", "sub": main.save_label(), "act": func(): _go(main.continue_game), "red": true})
	list.append({"text": "Новая игра", "act": _diff_tags})
	list.append({"text": "Настройки", "act": _settings})
	list.append({"text": "Авторы", "act": _authors})
	list.append({"text": "Выход", "act": func(): get_tree().quit()})
	_set_tags(list)

func _diff_tags() -> void:
	screen = "diff"
	_close_card()
	var list := []
	for i in DIFFS.size():
		var di := i
		list.append({"text": DIFFS[i][0], "sub": ["легко", "как задумано", "тяжело", "без права на ошибку"][i], "act": func(): _diff_card(di), "red": i == 3})
	list.append({"text": "← Назад", "act": _root_tags})
	_set_tags(list)

# ---------------- карточки ----------------
func _paper(w: float) -> PanelContainer:
	_close_card()
	var pc := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = PAPER
	st.border_color = Color(0.5, 0.42, 0.3)
	st.set_border_width_all(1)
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 10
	st.shadow_offset = Vector2(5, 7)
	st.set_content_margin_all(22)
	pc.add_theme_stylebox_override("panel", st)
	pc.custom_minimum_size = Vector2(w, 0)
	var vs := get_viewport().get_visible_rect().size
	pc.position = Vector2(vs.x - 400.0 - w, 150.0)
	pc.rotation = deg_to_rad(-1.2)
	pc.modulate.a = 0.0
	root.add_child(pc)
	card = pc
	var tw := create_tween()
	tw.tween_property(pc, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(pc, "position:y", 150.0, 0.25).from(185.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	return pc

func _close_card() -> void:
	if card:
		card.queue_free()
		card = null

func _lbl(parent: Node, text: String, sz: int, col := INK, f: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", f if f else F_TAG)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l

func _ink_btn(parent: Node, text: String, on: bool, cb: Callable, w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 46)
	b.add_theme_font_override("font", F_TAG)
	b.add_theme_font_size_override("font_size", 20)
	for s in ["normal", "hover", "pressed", "focus"]:
		var st := StyleBoxFlat.new()
		st.bg_color = INK if on else Color(0, 0, 0, 0)
		st.border_color = INK
		st.set_border_width_all(2)
		st.set_corner_radius_all(3)
		st.set_content_margin_all(8)
		b.add_theme_stylebox_override(s, st)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, PAPER if on else INK)
	b.pressed.connect(func():
		_click = 0.6
		cb.call())
	parent.add_child(b)
	return b

func _diff_card(i: int) -> void:
	var pc := _paper(430.0)
	var vb: VBoxContainer = pc.get_child(0)
	_lbl(vb, "ДЕЛО № %03d" % (183 + i), 15, Color(RED, 0.85), F_MONO)
	_lbl(vb, DIFFS[i][0].to_upper(), 28)
	for line in DIFFS[i][1].split(" · "):
		_lbl(vb, "— " + line, 17, Color(INK, 0.85), F_MONO)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(hb)
	_ink_btn(hb, "Начать ▶", true, func(): _go(func(): main.new_game(i)), 180.0)
	if main.has_save():
		_lbl(vb, "Текущее сохранение будет заменено.", 14, Color(RED, 0.9), F_MONO)

func _settings() -> void:
	screen = "set"
	_set_tags([{"text": "← Назад", "act": _root_tags}])
	_settings_card()

func _settings_card() -> void:
	var s = main.settings
	var pc := _paper(520.0)
	var vb: VBoxContainer = pc.get_child(0)
	_lbl(vb, "НАСТРОЙКИ", 26)
	_lbl(vb, "Графика", 16, Color(INK, 0.7), F_MONO)
	var g := HBoxContainer.new()
	vb.add_child(g)
	for i in 4:
		var li := i
		_ink_btn(g, s.NAMES[i], s.level == i, func():
			s.apply(li)
			_settings_card(), 112.0)
	var r2 := HBoxContainer.new()
	vb.add_child(r2)
	_ink_btn(r2, "Кадры: " + ("максимум" if s.fps_max else "60"), false, func():
		s.set_fps_max(not s.fps_max)
		_settings_card(), 230.0)
	_ink_btn(r2, "Звук: " + ("вкл" if s.sound else "выкл"), false, func():
		s.set_sound(not s.sound)
		_settings_card(), 220.0)
	var r3 := HBoxContainer.new()
	vb.add_child(r3)
	_ink_btn(r3, "▶ Заставка", false, func(): _go(func(): main.start_intro()), 230.0)
	_ink_btn(r3, "⟳ Обновления", false, func():
		Engine.set_meta("from_game", true)
		get_tree().change_scene_to_file("res://boot.tscn"), 220.0)

func _authors() -> void:
	screen = "auth"
	_set_tags([{"text": "← Назад", "act": _root_tags}])
	var pc := _paper(520.0)
	var vb: VBoxContainer = pc.get_child(0)
	_lbl(vb, "АВТОРЫ", 26)
	_lbl(vb, "Игра — владелец проекта и Claude (Anthropic).", 17, INK, F_MONO)
	_lbl(vb, "Деревья и камни — Poly Haven (CC0). Основа героя — Human Base Meshes (CC0). Движения — CMU Graphics Lab Motion Capture. Текстуры — ambientCG, Poly Haven (CC0). Дома, машины, места — свои, Blender.", 15, Color(INK, 0.8), F_MONO)
	_lbl(vb, "Движок Godot Engine (MIT).", 15, Color(INK, 0.8), F_MONO)

# ---------------- выход из меню ----------------
func _go(cb: Callable) -> void:
	if _busy:
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.5)
	tw.tween_callback(func():
		close()
		cb.call())

func close() -> void:
	main.world.set_see_hole(Vector3.ZERO, 0.0)
	if hero:
		hero.queue_free()
	for wk in walkers:
		(wk[0] as Node).queue_free()
	walkers.clear()
	main.hud.visible = true
	main.camctl.visible = true
	main.camctl.process_mode = Node.PROCESS_MODE_INHERIT
	main.daynight.auto = true
	closed.emit()
	queue_free()

func back() -> void:                                             # кнопка «назад» на телефоне
	if screen == "root":
		get_tree().quit()
	else:
		_root_tags()

# ---------------- рация и звук ----------------
func _radio_step(dt: float) -> void:
	var line: String = RADIO[_radio_i]
	if _radio_n < line.length():
		var before := int(_radio_n)
		_radio_n += dt * 21.0
		if int(_radio_n) != before and line[mini(int(_radio_n), line.length() - 1)] != " ":
			_click = maxf(_click, 0.12)
		_static = 0.5
		radio_lbl.text = line.substr(0, int(_radio_n)) + ("▌" if int(t * 3.0) % 2 == 0 else " ")
		_radio_hold = 3.2
	else:
		_static = 0.12
		radio_lbl.text = line
		_radio_hold -= dt
		if _radio_hold <= 0.0:
			_radio_i = (_radio_i + 1) % RADIO.size()
			_radio_n = 0.0
			_static = 1.0

func _sound() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.25
	var pl := AudioStreamPlayer.new()
	pl.stream = gen
	pl.volume_db = -6.0
	add_child(pl)
	pl.play()
	_pb = pl.get_stream_playback()

func _audio() -> void:
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	var vol := 1.0 if main.settings.sound else 0.0
	var fade_k := 1.0 - fade.color.a if _busy else 1.0
	for i in n:
		var w := _rng.randf() * 2.0 - 1.0
		_br = clampf(_br * 0.996 + w * 0.018, -1.0, 1.0)             # гул огня
		if _rng.randf() < 0.0009:                                   # треск полена
			_cr = _rng.randf_range(0.25, 0.8)
		_cr *= 0.991
		_hp = _hp * 0.6 + w * 0.4
		var s := _br * 0.35 + _cr * w * 0.6 + (w - _hp) * _static * 0.07 + _click * w * 0.5
		_click *= 0.985
		_pb.push_frame(Vector2(s, s) * vol * fade_k)
	_static = maxf(_static - 0.01, 0.0)

func _shot(path: String) -> void:
	await get_tree().create_timer(25.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg(path.replace(".jpg", "_root.jpg"), 0.88)
	_diff_tags()
	await get_tree().create_timer(1.0).timeout
	_diff_card(1)
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg(path, 0.88)
	print("MENUSHOT ", path)
	_settings()
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg(path.replace(".jpg", "_set.jpg"), 0.88)
	get_tree().quit()

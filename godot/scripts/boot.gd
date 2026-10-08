extends Control
# Стартовый экран и обновление «по воздуху» (только для тестовых сборок).
# Игра — это APK (движок + большие модели) + маленький пакет code.pck (скрипты, шейдеры, сцены, ~1–2 МБ),
# который выкладывается на GitHub вместе с каждой сборкой. При запуске (и по кнопке) игра смотрит
# update.json, и если сборка новее — докачивает code.pck, подключает его поверх APK и запускает игру.
# Большие файлы (модели, текстуры) в пакет не входят: их смена требует нового APK (apk_min в update.json).
const BASE := "https://github.com/emrysmxo-maker/survival-game/releases/download/godot-latest/"
const UPD_DIR := "user://update/"
var base_url := BASE
var status: Label
var info: Label
var bar: ProgressBar
var btn_check: Button
var btn_play: Button
var http: HTTPRequest
var from_game := false
var apk_build := 0
var cur_build := 0
var _phase := ""          # "json" | "pck" | ""
var _remote: Dictionary = {}
var _apk_url := ""
var _preload: Array = []      # модели грузятся в фоне, пока на экране проверка обновления
var _want_play := false

func _read_int(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return int(f.get_as_text().strip_edges()) if f else 0

# подключить ранее скачанный code.pck (если он не старее самого APK) — один раз за запуск
func _mount_saved() -> void:
	if Engine.has_meta("pck_mounted"):
		return
	var pck := UPD_DIR + "code.pck"
	var mf := FileAccess.open(UPD_DIR + "meta.json", FileAccess.READ)
	if mf == null or not FileAccess.file_exists(pck):
		return
	var meta = JSON.parse_string(mf.get_as_text())
	if meta is Dictionary and int(meta.get("build", 0)) >= apk_build:
		if ProjectSettings.load_resource_pack(ProjectSettings.globalize_path(pck), true):
			Engine.set_meta("pck_mounted", int(meta.build))

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--updurl="):
			base_url = a.substr(9)
	from_game = Engine.has_meta("from_game")
	apk_build = _read_int("res://apk_build.txt")
	_mount_saved()
	cur_build = _read_int("res://build.txt")
	_build_ui()
	_start_preload()
	http = HTTPRequest.new()
	http.max_redirects = 8
	http.timeout = 15.0
	add_child(http)
	http.request_completed.connect(_on_done)
	if from_game:
		status.text = "Нажми «Проверить обновления»"
	else:
		check()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(560, 0)
	box.position = Vector2(-280, -170)
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	var title := Label.new()
	title.text = "SURVIVAL"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	info = Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 16)
	info.modulate = Color(1, 1, 1, 0.6)
	info.text = "APK: сборка %d · код: сборка %d" % [apk_build, cur_build]
	box.add_child(info)
	status = Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 20)
	box.add_child(status)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 14)
	bar.show_percentage = false
	bar.visible = false
	box.add_child(bar)
	btn_check = _btn("Проверить обновления", Color(0.18, 0.3, 0.2))
	btn_check.pressed.connect(check)
	box.add_child(btn_check)
	btn_play = _btn("▶  ИГРАТЬ" if not from_game else "◀  Вернуться в игру", Color(0.5, 0.3, 0.08))
	btn_play.pressed.connect(play)
	box.add_child(btn_play)

func _btn(t: String, c: Color) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_font_size_override("font_size", 22)
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(10)
	b.add_theme_stylebox_override("normal", s)
	b.add_theme_stylebox_override("hover", s)
	b.add_theme_stylebox_override("pressed", s)
	return b

func _start_preload() -> void:
	var f := FileAccess.open("res://assets/models/kinds.json", FileAccess.READ)
	if f == null:
		return
	var kinds = JSON.parse_string(f.get_as_text())
	var seen := {}
	for k in kinds:
		for part in ["wood", "leaf"]:
			var p := "res://assets/models/%s_%s.glb" % [kinds[k].m, part]
			if not seen.has(p) and ResourceLoader.exists(p):
				seen[p] = true
	for p in seen:
		if ResourceLoader.load_threaded_request(p, "", true) == OK:
			_preload.append(p)

func _preload_left() -> int:
	var n := 0
	for p in _preload:
		if ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			n += 1
	return n

func _stamp() -> String:
	return str(int(Time.get_unix_time_from_system()))

var _retry := 0
func check() -> void:
	if _phase != "":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UPD_DIR))
	status.text = "Проверяю обновления…"
	bar.visible = false
	btn_check.disabled = true
	_phase = "json"
	http.download_file = ""
	var err := http.request(base_url + "update.json?t=" + _stamp())
	if err != OK:
		_fail("Нет связи (%d)" % err)

func _fail(msg: String) -> void:
	_phase = ""
	btn_check.disabled = false
	bar.visible = false
	status.text = msg
	if not from_game:
		get_tree().create_timer(1.6).timeout.connect(play)      # без сети — играем с тем, что есть

func _on_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if _phase == "json" and _retry < 2:
			_retry += 1                     # GitHub иногда не отвечает с первого раза — повторяем
			_phase = ""
			status.text = "Сеть не ответила, повторяю (%d)…" % _retry
			get_tree().create_timer(1.0).timeout.connect(check)
			return
		var why := "сеть не ответила" if result == HTTPRequest.RESULT_TIMEOUT else "код %d/%d" % [result, code]
		_fail("Не удалось проверить (%s). Запускаю как есть." % why)
		return
	_retry = 0
	if _phase == "json":
		var d = JSON.parse_string(body.get_string_from_utf8())
		if not (d is Dictionary):
			_fail("Ответ обновления не распознан.")
			return
		_remote = d
		var rb := int(d.get("build", 0))
		if int(d.get("apk_min", 0)) > apk_build:
			_phase = ""
			btn_check.disabled = false
			status.text = "Нужен новый APK (сборка %d+). Скачай по ссылке в чате." % int(d.apk_min)
			return
		if rb <= cur_build:
			_phase = ""
			btn_check.disabled = false
			status.text = "Установлена последняя версия (сборка %d)." % cur_build
			if not from_game:
				get_tree().create_timer(0.7).timeout.connect(play)
			return
		_phase = "pck"
		status.text = "Скачиваю обновление: сборка %d…" % rb
		bar.visible = true
		bar.value = 0
		http.download_file = ProjectSettings.globalize_path(UPD_DIR + "code.pck.tmp")
		var err := http.request(base_url + "code.pck?t=" + _stamp())
		if err != OK:
			_fail("Не удалось начать загрузку (%d)" % err)
	elif _phase == "pck":
		var tmp := ProjectSettings.globalize_path(UPD_DIR + "code.pck.tmp")
		var f := FileAccess.open(tmp, FileAccess.READ)
		var sz := f.get_length() if f else 0
		f = null
		if int(_remote.get("size", 0)) > 0 and sz != int(_remote.size):
			DirAccess.remove_absolute(tmp)
			_fail("Файл обновления повреждён. Попробуй ещё раз.")
			return
		var final := ProjectSettings.globalize_path(UPD_DIR + "code.pck")
		if FileAccess.file_exists(UPD_DIR + "code.pck"):
			DirAccess.remove_absolute(final)
		DirAccess.rename_absolute(tmp, final)
		var mf := FileAccess.open(UPD_DIR + "meta.json", FileAccess.WRITE)
		mf.store_string(JSON.stringify({"build": int(_remote.build), "sha": str(_remote.get("sha", ""))}))
		mf = null
		_phase = ""
		btn_check.disabled = false
		bar.visible = false
		if from_game:
			status.text = "Обновлено до сборки %d. Закрой игру (смахни) и открой снова." % int(_remote.build)
		else:
			if ProjectSettings.load_resource_pack(final, true):
				Engine.set_meta("pck_mounted", int(_remote.build))
				cur_build = int(_remote.build)
			info.text = "APK: сборка %d · код: сборка %d" % [apk_build, cur_build]
			status.text = "Обновлено до сборки %d" % cur_build
			get_tree().create_timer(0.8).timeout.connect(play)

func _process(_dt: float) -> void:
	if _want_play:
		var left := _preload_left()
		status.text = "Загрузка мира… %d%%" % int(100.0 * (1.0 - float(left) / maxf(_preload.size(), 1.0)))
		if left == 0:
			_want_play = false
			play()
		return
	if _phase == "pck" and http:
		var total := http.get_body_size()
		bar.max_value = maxf(total, 1.0) if total > 0 else maxf(float(_remote.get("size", 1)), 1.0)
		bar.value = http.get_downloaded_bytes()
		status.text = "Скачиваю обновление: %d%%" % int(100.0 * bar.value / bar.max_value)

func play() -> void:
	if _phase == "pck":
		return
	if _preload_left() > 0:
		_want_play = true      # дождаться фоновой загрузки моделей
		return
	for p in _preload:
		ResourceLoader.load_threaded_get(p)     # забрать готовое (дальше load() берёт из памяти)
	_preload.clear()
	Engine.remove_meta("from_game") if Engine.has_meta("from_game") else null
	get_tree().change_scene_to_file("res://main.tscn")

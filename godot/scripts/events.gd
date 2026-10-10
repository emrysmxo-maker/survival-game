extends Node3D
# Редкие события мира — за лесом кто-то есть:
#  вертолёт — раз в 4–9 мин пролетает над картой (60 м, ~30 м/с) рядом с камерой: гул винта по месту, тень бежит по земле;
#  выстрелы — раз в 1–3 мин далёкая очередь с одной стороны (тихо, гулко);
#  сигнализация — раз в 5–10 мин у ближней брошенной машины (до 60 м) воет ~12 с и затихает.
# Звук — синтез (16 кГц, стерео), выключается вместе со звуком мира (⚙ «Звук»). Отладка: --events (всё чаще: каждые 20–40 с).
var main
const T := WorldGen.T
const RATE := 16000.0
var _rng := RandomNumberGenerator.new()
var _pb: AudioStreamGeneratorPlayback
var _fast := false
# вертолёт
var _heli: Node3D
var _rotor: Node3D
var _heli_wait := 0.0
var _heli_t := -1.0
var _heli_a := Vector3.ZERO
var _heli_b := Vector3.ZERO
var _heli_g := 0.0
var _heli_pan := 0.0
var _ph := 0.0
var _hlp := 0.0
# выстрелы
var _shot_wait := 0.0
var _shots: Array = []               # [время до выстрела]
var _shot_env := 0.0
var _shot_pan := 0.0
var _shot_lp := 0.0
# сигнализация
var _alarm_wait := 0.0
var _alarm_t := 0.0
var _alarm_g := 0.0
var _alarm_pan := 0.0
var _aph := 0.0
var _t := 0.0

func _ready() -> void:
	_rng.randomize()
	_fast = OS.get_cmdline_user_args().has("--events")
	_heli_wait = _wait(240.0, 540.0)
	_shot_wait = _wait(60.0, 180.0)
	_alarm_wait = _wait(300.0, 600.0)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.3
	var pl := AudioStreamPlayer.new()
	pl.stream = gen
	pl.volume_db = -5.0
	add_child(pl)
	pl.play()
	_pb = pl.get_stream_playback()

func _wait(a: float, b: float) -> float:
	return _rng.randf_range(20.0, 40.0) if _fast else _rng.randf_range(a, b)

# громкость и лево/право точки мира (м) для слушателя (точка камеры)
func _place(p: Vector3, fade_m: float) -> Vector2:
	var f: Vector2 = main.focus * T
	var d := Vector2(p.x, p.z) - f
	var yr := deg_to_rad(main.cam_yaw)
	var right := Vector2(cos(yr), -sin(yr))
	var g := clampf(1.0 - d.length() / fade_m, 0.0, 1.0)
	return Vector2(g * g, clampf(d.normalized().dot(right), -1.0, 1.0) * 0.8 if d.length() > 1.0 else 0.0)

func _process(dt: float) -> void:
	if main.menu != null or main.intro != null:
		return
	_heli_step(dt)
	_shots_step(dt)
	_alarm_step(dt)
	_audio()

# ---------------- вертолёт ----------------
func _heli_step(dt: float) -> void:
	if _heli_t < 0.0:
		_heli_wait -= dt
		if _heli_wait > 0.0 or not main.props._meshes.has("heli_fly"):
			return
		if _heli == null:
			_heli = Node3D.new()
			add_child(_heli)
			var body := MeshInstance3D.new()
			body.mesh = main.props._meshes["heli_fly"]
			body.rotation.y = -PI / 2.0
			_heli.add_child(body)
			_rotor = MeshInstance3D.new()
			_rotor.mesh = main.props._meshes.get("heli_rotor")
			_rotor.position = Vector3(0, 4.0, 0)
			_heli.add_child(_rotor)
		# курс: прямая через точку рядом с камерой, из-за края карты — за край
		var f: Vector2 = main.focus * T
		var mid := f + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(10.0, 60.0)
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		var h := WorldGen.height_m(mid.x / T, mid.y / T) + 60.0
		_heli_a = Vector3(mid.x - dir.x * 400.0, h, mid.y - dir.y * 400.0)
		_heli_b = Vector3(mid.x + dir.x * 400.0, h, mid.y + dir.y * 400.0)
		_heli_t = 0.0
		_heli.visible = true
	_heli_t += dt / (800.0 / 30.0)
	if _heli_t >= 1.0:
		_heli_t = -1.0
		_heli.visible = false
		_heli_g = 0.0
		_heli_wait = _wait(240.0, 540.0)
		return
	var p := _heli_a.lerp(_heli_b, _heli_t)
	_heli.global_position = p
	_heli.look_at(p + (_heli_b - _heli_a).normalized(), Vector3.UP)
	_heli.rotate_object_local(Vector3.RIGHT, -0.12)              # нос чуть вниз — летит вперёд
	_rotor.rotation.y += dt * 22.0
	var pl := _place(p, 420.0)
	_heli_g = pl.x
	_heli_pan = pl.y

# ---------------- далёкие выстрелы ----------------
func _shots_step(dt: float) -> void:
	_shot_wait -= dt
	if _shot_wait <= 0.0 and _shots.is_empty():
		_shot_wait = _wait(60.0, 180.0)
		var n := _rng.randi_range(1, 3) if _rng.randf() < 0.5 else _rng.randi_range(4, 9)   # одиночные или очередь
		var t := 0.0
		for i in n:
			_shots.append(t)
			t += _rng.randf_range(0.09, 0.14) if n > 3 else _rng.randf_range(0.6, 1.8)
		_shot_pan = _rng.randf_range(-0.9, 0.9)
	for i in range(_shots.size() - 1, -1, -1):
		_shots[i] -= dt
		if _shots[i] <= 0.0:
			_shot_env = 1.0
			_shots.remove_at(i)

# ---------------- сигнализация машины ----------------
func _alarm_step(dt: float) -> void:
	if _alarm_t > 0.0:
		_alarm_t -= dt
		if _alarm_t <= 0.0:
			_alarm_g = 0.0
		return
	_alarm_wait -= dt
	if _alarm_wait > 0.0:
		return
	_alarm_wait = _wait(300.0, 600.0)
	var f: Vector2 = main.focus * T
	var best := Vector3.INF
	for key in main.props._batch:
		if not str(main.props._batch[key].model).begins_with("car_"):
			continue
		for xf: Transform3D in main.props._batch[key].xf:
			var d := Vector2(xf.origin.x, xf.origin.z).distance_to(f)
			if d < 60.0 and (best == Vector3.INF or d < Vector2(best.x, best.z).distance_to(f)):
				best = xf.origin
	if best == Vector3.INF:
		return
	var pl := _place(best, 90.0)
	_alarm_g = pl.x
	_alarm_pan = pl.y
	_alarm_t = 12.0

# ---------------- звук ----------------
func _audio() -> void:
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	if n <= 0:
		return
	var vol := 1.0 if main.settings.sound else 0.0
	var buf := PackedVector2Array()
	buf.resize(n)
	var dt := 1.0 / RATE
	var hl := 1.0 - _heli_pan
	var hr := 1.0 + _heli_pan
	for i in n:
		_t += dt
		var wh := _rng.randf() * 2.0 - 1.0
		var L := 0.0
		var R := 0.0
		if _heli_g > 0.002:                                       # винт: удары ~17 Гц по гулу
			_ph = fmod(_ph + 17.0 * dt, 1.0)
			_hlp += 0.06 * (wh - _hlp)
			var thump := pow(1.0 - _ph, 6.0)
			var s := (_hlp * 3.0 * (0.35 + thump) + sin(TAU * 90.0 * _t) * thump * 0.4) * _heli_g * 0.7
			L += s * hl
			R += s * hr
		if _shot_env > 0.001:                                     # выстрел: глухой хлопок + раскат
			_shot_lp += 0.12 * (wh - _shot_lp)
			var s2 := _shot_lp * 2.5 * _shot_env * 0.35
			_shot_env *= 0.9994
			L += s2 * (1.0 - _shot_pan)
			R += s2 * (1.0 + _shot_pan)
		if _alarm_g > 0.002 and _alarm_t > 0.0:                    # сигнализация: вой 600–1300 Гц, пачками
			var sw := 950.0 + 350.0 * sin(TAU * 2.2 * _t)
			_aph += sw * dt
			var on := 1.0 if fmod(_t, 1.2) < 0.85 else 0.0
			var s3 := (2.0 * fmod(_aph, 1.0) - 1.0) * 0.12 * _alarm_g * on * clampf(_alarm_t / 2.0, 0.0, 1.0)
			L += s3 * (1.0 - _alarm_pan)
			R += s3 * (1.0 + _alarm_pan)
		buf[i] = Vector2(clampf(L * vol, -1.0, 1.0), clampf(R * vol, -1.0, 1.0))
	_pb.push_buffer(buf)

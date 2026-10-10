extends Node
# Звуки мира без файлов — синтез в реальном времени (AudioStreamGenerator, 16 кГц, СТЕРЕО), ЗВУК ПО МЕСТУ:
# слушатель — точка камеры (потом — игрок), лево/право — относительно поворота камеры.
#  вода — журчание у реки/ручья, плеск у озера; громкость по расстоянию до ближайшей воды (за ~45 м не слышно), с её стороны;
#  ветер — в поле сильнее, в лесу тише и глуше (раньше ровный гул по всей карте звучал как вода — замер сборки 110);
#  птицы днём — 3 птицы сидят на деревьях рядом: свой голос, своё место; отошёл — тише, далеко — пересаживаются ближе;
#    в поле птиц почти нет; сверчки ночью — только в траве/полях; вороны — каркают там, где стая (crows.gd);
#  дождь — шорох везде. Громкость слоёв — от погоды (weather.gd) и времени суток (daynight.gd). Выключается в ⚙ («Звук»).
var main
var on := true
const RATE := 16000.0
const T := WorldGen.T
var _pb: AudioStreamGeneratorPlayback
var _player: AudioStreamPlayer
var _t := 0.0
var _brown := 0.0
var _wlp := 0.0
var _rainlp := 0.0
var _rng := RandomNumberGenerator.new()
# место (обновляется 4 раза в секунду)
var _scan := 0.0
var _water := 0.0                   # громкость воды 0..1 (цель)
var _water_s := 0.0                 # плавно
var _water_pan := 0.0
var _river := true                  # ближняя вода — река/ручей (журчит) или озеро (плещет)
var _forest := 0.0
var _forest_s := 0.0
var _right := Vector2.RIGHT
var _at := Vector2.ZERO
# вода — синтез
var _w1 := 0.0
var _w2 := 0.0
var _bub := [0.0, 0.0, 0.0, 0.0]   # время, длительность, частота, фаза — один «бульк»
var _lap := 0.0
# птицы: [место (тайлы), пауза, слогов, длит. слога, част. начала, конца, пауза слога, фаза, t, громкость, пан]
var _birds: Array = []
var _crow_wait := 20.0
var _crow := [0.0, 0, 0.0]          # время в «кар», сколько «кар», фаза
var _crow_g := 0.0
var _crow_pan := 0.0

func _ready() -> void:
	_rng.seed = 77
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.4
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.volume_db = -6.0
	add_child(_player)
	_player.play()
	_pb = _player.get_stream_playback()
	for i in 3:
		_birds.append([Vector2(1e6, 1e6), _rng.randf_range(1.0, 4.0), 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])

# громкость (по расстоянию, м) и лево/право (-1..1) точки p (тайлы) для слушателя
func _place(p: Vector2, fade_m: float) -> Vector2:
	var d := p - _at
	var dm := d.length() * T
	var g := clampf(1.0 - dm / fade_m, 0.0, 1.0)
	return Vector2(g * g, clampf(d.normalized().dot(_right) if dm > 0.5 else 0.0, -1.0, 1.0) * 0.85)

func _scan_place() -> void:
	_at = main.focus
	var yr := deg_to_rad(main.cam_yaw)
	_right = Vector2(cos(yr), -sin(yr))
	# ближняя вода: лучи в 12 сторон, шаг 4 тайла до ~55 тайлов (45 м)
	var best := 1e9
	var bdir := Vector2.ZERO
	if WorldGen.water_at(_at.x, _at.y).x > 0.3:
		best = 0.0
	else:
		for k in 12:
			var dir := Vector2.from_angle(k * TAU / 12.0)
			var r := 4.0
			while r <= 56.0 and r < best:
				var q := _at + dir * r
				if WorldGen.water_at(q.x, q.y).x > 0.3:
					best = r
					bdir = dir
					break
				r += 4.0
	if best < 1e8:
		var dm := best * T
		_water = clampf(1.0 - (dm - 3.0) / 44.0, 0.0, 1.0)
		_water *= _water
		_water_pan = bdir.dot(_right) * 0.8 * clampf(dm / 10.0, 0.0, 1.0)
		var wp := _at + bdir * best
		_river = WorldGen.lake_at(wp.x, wp.y).z < 0.0
	else:
		_water = 0.0
	# лесистость вокруг (5 точек)
	var f := 0.0
	for o in [Vector2.ZERO, Vector2(12, 0), Vector2(-12, 0), Vector2(0, 12), Vector2(0, -12)]:
		f += WorldGen.tree_density(_at.x + o.x, _at.y + o.y)
	_forest = clampf(f / 5.0, 0.0, 1.0)
	# птицы: сидят на деревьях; ушли далеко (>45 м) — новая птица рядом, если там есть деревья
	for b in _birds:
		if (b[0] as Vector2).distance_to(_at) * T > 45.0:
			var q := _at + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(8.0, 40.0)
			b[0] = q if WorldGen.tree_density(q.x, q.y) > 0.35 or _rng.randf() < 0.12 else Vector2(1e6, 1e6)
		var pl := _place(b[0], 45.0)
		b[9] = pl.x
		b[10] = pl.y
	# вороны — у ближней стаи
	_crow_g = 0.0
	var cr = main.get_node_or_null("Crows")
	if cr and "_flocks" in cr:
		for fl in cr._flocks:
			var pl := _place(fl[0], 70.0)
			if pl.x > _crow_g:
				_crow_g = pl.x
				_crow_pan = pl.y
	if OS.get_environment("SNDDBG") != "":
		print("SND at %s вода %.2f %s пан %.2f лес %.2f птицы %s" % [str(_at), _water, "река" if _river else "озеро", _water_pan, _forest, str(_birds.map(func(b): return snappedf(b[9], 0.01)))])

func _process(dt: float) -> void:
	if _pb == null:
		return
	_scan -= dt
	if _scan <= 0.0:
		_scan = 0.25
		_scan_place()
	var n := _pb.get_frames_available()
	if n <= 0:
		return
	var w = main.weather
	var rain: float = w.rain if w else 0.0
	var night: float = main.daynight.night
	var day := (1.0 - night) * (1.0 - rain)
	var open := 1.0 - _forest_s
	var wind: float = (0.2 + (w.cloud * 0.25 if w else 0.0) + rain * 0.45) * (0.45 + 0.75 * open)
	var g := 1.0 if on else 0.0
	var buf := PackedVector2Array()
	buf.resize(n)
	var dt_s := 1.0 / RATE
	var bird_k := day * (0.15 + 0.85 * _forest_s)
	var crick := clampf(night - 0.3, 0.0, 1.0) * (1.0 - rain) * (0.25 + 0.75 * open)
	var wl := cos((_water_pan + 1.0) * PI * 0.25) * 1.41
	var wr := sin((_water_pan + 1.0) * PI * 0.25) * 1.41
	for i in n:
		_t += dt_s
		_water_s += (_water - _water_s) * 0.00008
		_forest_s += (_forest - _forest_s) * 0.00005
		var wh := _rng.randf() * 2.0 - 1.0
		# ветер: бурый шум, медленные порывы; в лесу глуше (сильнее сглажен)
		_brown = (_brown + 0.02 * wh) / 1.02
		_wlp += (0.25 + 0.6 * open) * (_brown - _wlp)
		var gust := 0.55 + 0.45 * sin(_t * 0.23) * sin(_t * 0.071 + 1.3)
		var c := _wlp * 2.6 * wind * gust
		# дождь: шорох + редкие капли
		_rainlp += 0.45 * (wh - _rainlp)
		c += _rainlp * 0.16 * rain
		var L := c
		var R := c
		# вода
		if _water_s > 0.003:
			var ws := _water_sample(wh, dt_s) * _water_s
			L += ws * wl
			R += ws * wr
		# птицы (у каждой своё место)
		if bird_k > 0.02:
			for b in _birds:
				if b[9] > 0.003:
					var bs: float = _bird_sample(b, dt_s) * 0.24 * bird_k * b[9]
					L += bs * (1.0 - b[10])
					R += bs * (1.0 + b[10])
		# сверчки ночью: 4,3 кГц, пачки импульсов (в траве — с обеих сторон)
		if crick > 0.01:
			var chirp := fmod(_t, 0.62)
			if chirp < 0.16:
				var pulse := 0.5 + 0.5 * sin(TAU * 30.0 * chirp)
				L += sin(TAU * 4300.0 * _t) * pulse * 0.05 * crick
				R += sin(TAU * 4100.0 * (_t + 0.31)) * pulse * 0.04 * crick
		# вороны: «кар» у стаи
		if day > 0.2 and _crow_g > 0.01:
			var cs := _crow_sample(dt_s) * 0.2 * day * _crow_g
			L += cs * (1.0 - _crow_pan)
			R += cs * (1.0 + _crow_pan)
		buf[i] = Vector2(clampf(L * g, -1.0, 1.0), clampf(R * g, -1.0, 1.0))
	_pb.push_buffer(buf)

# вода: река/ручей — журчание (полосовой шум с быстрой модуляцией + «бульки»); озеро — медленный плеск о берег
func _water_sample(wh: float, dt: float) -> float:
	_w1 += 0.35 * (wh - _w1)
	_w2 += 0.08 * (_w1 - _w2)
	var band := _w1 - _w2                                        # полоса ~300–1500 Гц
	if _river:
		var s := band * (0.55 + 0.45 * sin(_t * 9.0 + 3.0 * sin(_t * 2.3))) * 0.9
		var b := _bub
		if b[1] <= 0.0 and _rng.randf() < 0.0025:
			b[0] = 0.0; b[1] = _rng.randf_range(0.03, 0.08); b[2] = _rng.randf_range(350.0, 900.0)
		if b[1] > 0.0:
			b[0] += dt
			var u: float = b[0] / b[1]
			b[3] += TAU * b[2] * (1.0 + u * 0.8) * dt
			s += sin(b[3]) * (1.0 - u) * 0.35
			if u >= 1.0:
				b[1] = 0.0
		return s * 0.35
	_lap += dt
	var swell := pow(maxf(sin(_lap * TAU / 4.2), 0.0), 3.0) + 0.35 * pow(maxf(sin(_lap * TAU / 2.9 + 1.0), 0.0), 3.0)
	return (_w2 * 1.6 + band * 0.4) * (0.15 + swell) * 0.45

func _bird_sample(b: Array, dt: float) -> float:
	if b[2] <= 0:
		b[1] -= dt
		if b[1] <= 0.0:                                               # новая трель
			b[2] = _rng.randi_range(2, 6)
			b[3] = _rng.randf_range(0.06, 0.16)
			b[4] = _rng.randf_range(2400.0, 4200.0)
			b[5] = b[4] * _rng.randf_range(0.7, 1.35)
			b[6] = _rng.randf_range(0.04, 0.12)
			b[8] = 0.0
			b[1] = _rng.randf_range(2.0, 8.0)
		return 0.0
	b[8] += dt
	if b[8] < b[3]:
		var u: float = b[8] / b[3]
		var f: float = lerpf(b[4], b[5], u)
		b[7] += TAU * f * dt
		return sin(b[7]) * sin(PI * u)
	if b[8] > b[3] + b[6]:
		b[8] = 0.0
		b[2] -= 1
	return 0.0

func _crow_sample(dt: float) -> float:
	if _crow[1] <= 0:
		_crow_wait -= dt
		if _crow_wait <= 0.0:
			_crow[1] = _rng.randi_range(2, 4)
			_crow[0] = 0.0
			_crow_wait = _rng.randf_range(18.0, 45.0)
		return 0.0
	_crow[0] += dt
	var L := 0.32
	if _crow[0] < L:
		var u: float = _crow[0] / L
		var f := lerpf(520.0, 380.0, u)
		_crow[2] += f * dt
		var saw := 2.0 * fmod(_crow[2], 1.0) - 1.0                    # хриплый «кар»: пила + шум
		return (saw * 0.7 + (_rng.randf() - 0.5) * 0.6) * sin(PI * u) * (0.6 + 0.4 * sin(TAU * 28.0 * _crow[0]))
	if _crow[0] > L + 0.22:
		_crow[0] = 0.0
		_crow[1] -= 1
	return 0.0

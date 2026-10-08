extends Node
# Звуки мира без файлов — синтез в реальном времени (AudioStreamGenerator, 16 кГц, моно):
# ветер (бурый шум, порывы), дождь (шорох), птицы днём (трели), сверчки ночью, редкое карканье ворон.
# Громкость слоёв — от погоды (weather.gd) и времени суток (daynight.gd). Выключается в ⚙ («Звук»).
var main
var on := true
const RATE := 16000.0
var _pb: AudioStreamGeneratorPlayback
var _player: AudioStreamPlayer
var _t := 0.0
var _brown := 0.0
var _rainlp := 0.0
var _rng := RandomNumberGenerator.new()
# птица: [время до старта, длительность слога, частота начала, конца, слогов осталось, пауза, фаза]
var _bird := [2.0, 0.0, 0.0, 0.0, 0, 0.0, 0.0]
var _bird_t := 0.0
var _crow_wait := 20.0
var _crow := [0.0, 0, 0.0]          # осталось в «кар», сколько «кар», фаза
var _cr_ph := 0.0

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

func _process(_dt: float) -> void:
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	if n <= 0:
		return
	var w = main.weather
	var rain: float = w.rain if w else 0.0
	var wind: float = 0.35 + (w.cloud * 0.3 if w else 0.0) + rain * 0.5
	var night: float = main.daynight.night
	var day := (1.0 - night) * (1.0 - rain)
	var g := 1.0 if on else 0.0
	var buf := PackedVector2Array()
	buf.resize(n)
	var dt := 1.0 / RATE
	for i in n:
		_t += dt
		var wh := _rng.randf() * 2.0 - 1.0
		# ветер: бурый шум, медленные порывы
		_brown = (_brown + 0.02 * wh) / 1.02
		var gust := 0.6 + 0.4 * sin(_t * 0.23) * sin(_t * 0.071 + 1.3)
		var s := _brown * 3.2 * wind * gust
		# дождь: шорох (сглаженный белый шум) + редкие капли
		_rainlp += 0.45 * (wh - _rainlp)
		s += _rainlp * 0.16 * rain
		# птицы днём: серии слогов-свистов
		if day > 0.05:
			s += _bird_sample(dt) * 0.22 * day
		# сверчки ночью: 4,3 кГц, пачки импульсов
		if night > 0.3:
			var chirp := fmod(_t, 0.62)
			if chirp < 0.16:
				var pulse := 0.5 + 0.5 * sin(TAU * 30.0 * chirp)
				s += sin(TAU * 4300.0 * _t) * pulse * 0.05 * (night - 0.3) * (1.0 - rain)
				s += sin(TAU * 4100.0 * (_t + 0.31)) * pulse * 0.03 * (night - 0.3) * (1.0 - rain)
		# вороны: редкое «кар» (днём)
		if day > 0.2:
			s += _crow_sample(dt) * 0.18 * day
		s = clampf(s * g, -1.0, 1.0)
		buf[i] = Vector2(s, s)
	_pb.push_buffer(buf)

func _bird_sample(dt: float) -> float:
	var b := _bird
	if b[4] <= 0:
		b[0] -= dt
		if b[0] <= 0.0:                                               # новая трель
			b[4] = _rng.randi_range(2, 6)
			b[1] = _rng.randf_range(0.06, 0.16)
			b[2] = _rng.randf_range(2400.0, 4200.0)
			b[3] = b[2] * _rng.randf_range(0.7, 1.35)
			b[5] = _rng.randf_range(0.04, 0.12)
			_bird_t = 0.0
			b[0] = _rng.randf_range(1.0, 5.0)
		return 0.0
	_bird_t += dt
	if _bird_t < b[1]:
		var u: float = _bird_t / b[1]
		var f: float = lerpf(b[2], b[3], u)
		b[6] += TAU * f * dt
		return sin(b[6]) * sin(PI * u)
	if _bird_t > b[1] + b[5]:
		_bird_t = 0.0
		b[4] -= 1
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
		_cr_ph += f * dt
		var saw := 2.0 * fmod(_cr_ph, 1.0) - 1.0                      # хриплый «кар»: пила + шум
		return (saw * 0.7 + (_rng.randf() - 0.5) * 0.6) * sin(PI * u) * (0.6 + 0.4 * sin(TAU * 28.0 * _crow[0]))
	if _crow[0] > L + 0.22:
		_crow[0] = 0.0
		_crow[1] -= 1
	return 0.0

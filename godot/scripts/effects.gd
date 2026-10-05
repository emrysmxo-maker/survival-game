extends Node3D
# Следы ног (на тропе, грязи, болоте, у реки — заметнее; на траве — едва),
# брызги на воде, пыль из-под ног на бегу. Перенос src/effects.js.

const FX_STEP := 0.5
const PRINT_LIFE := 25.0
const PRINT_MAX := 180

var weapon
var _mm: MultiMeshInstance3D
var _prints: Array = []      # {pos: Vector3, yaw, a, age}
var _dirty := false
var _state := {}             # объект -> {x, y, acc, side}

func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := PlaneMesh.new()
	q.size = Vector2(0.13, 0.28)
	mm.mesh = q
	_mm = MultiMeshInstance3D.new()
	_mm.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _print_tex()
	mat.roughness = 1.0
	_mm.material_override = mat
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mm.extra_cull_margin = 16384.0
	add_child(_mm)

func _print_tex() -> Texture2D:
	var img := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 32:
			# ступня: подошва + каблук
			var u := (x - 15.5) / 15.5
			var v := (y - 31.5) / 31.5
			var sole := 1.0 - Vector2(u / 0.85, (v + 0.25) / 0.7).length()
			var heel := 1.0 - Vector2(u / 0.7, (v - 0.62) / 0.33).length()
			var a := clampf(maxf(sole, heel) * 3.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func step(ent, tile: Vector2, dt: float, heavy: bool) -> void:
	var key: int = ent.get_instance_id() if ent is Object else 0
	if not _state.has(key):
		_state[key] = {"p": tile, "acc": 0.0, "side": 1.0}
		return
	var s: Dictionary = _state[key]
	var d: Vector2 = tile - s.p
	s.p = tile
	var l := d.length()
	if l < 1e-5 or l > 1.0:
		return
	s.acc += l
	if s.acc < FX_STEP:
		return
	s.acc -= FX_STEP
	s.side = -s.side
	var speed := l / maxf(dt, 1e-4)
	var n := d / l
	var f: Vector2 = tile + Vector2(-n.y, n.x) * 0.07 * s.side
	var t := WorldGen.terrain(f.x, f.y)
	var L := WorldGen.ground_layers(f.x, f.y)
	var h := t[0] * WorldGen.HK
	var pos := Vector3(f.x * WorldGen.T, h + 0.015, f.y * WorldGen.T)
	if t[1] > 0.15:
		if weapon:
			for i in 3:
				weapon._puff(pos, Vector3(randf_range(-0.4, 0.4), randf_range(0.4, 0.9), randf_range(-0.4, 0.4)), Color(0.75, 0.85, 0.9, 0.5), 0.06, 0.5)
		return
	var soft := clampf(L[0] + L[1] + L[2] * 0.8, 0.0, 1.0)
	var a := lerpf(0.28, 0.6, soft) * (1.2 if heavy else 1.0)
	if not heavy:
		_step_sound(soft)
	_prints.append({"pos": pos, "yaw": atan2(n.x, n.y), "a": a, "age": 0.0})
	if _prints.size() > PRINT_MAX:
		_prints.remove_at(0)
	_dirty = true
	if speed > 2.2 and soft < 0.4 and weapon and randf() < 0.5:
		weapon._puff(pos, Vector3(randf_range(-0.2, 0.2), 0.3, randf_range(-0.2, 0.2)), Color(0.6, 0.55, 0.45, 0.25), 0.15, 0.8)

func _process(dt: float) -> void:
	var changed := _dirty
	for i in range(_prints.size() - 1, -1, -1):
		_prints[i].age += dt
		if _prints[i].age > PRINT_LIFE:
			_prints.remove_at(i)
			changed = true
	if not changed and Engine.get_process_frames() % 30 != 0:
		return
	_dirty = false
	var mm := _mm.multimesh
	mm.instance_count = _prints.size()
	for i in _prints.size():
		var p: Dictionary = _prints[i]
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, p.yaw), p.pos))
		var fade := 1.0 - clampf((p.age - PRINT_LIFE * 0.6) / (PRINT_LIFE * 0.4), 0.0, 1.0)
		mm.set_instance_color(i, Color(0.10, 0.07, 0.04, p.a * fade))

# --- звук шагов: короткий шорох (шум с затуханием), синтезируется при запуске ---
var _steps: Array = []
var _players: Array = []
var _pi := 0
func _make_steps() -> void:
	for v in 4:
		var rate := 22050
		var n := int(rate * 0.11)
		var data := PackedByteArray()
		data.resize(n * 2)
		var lp := 0.0
		var rng := RandomNumberGenerator.new()
		rng.seed = 77 + v
		for i in n:
			var t := float(i) / n
			var env := pow(1.0 - t, 3.0) * minf(1.0, t * 40.0)
			lp += (rng.randf_range(-1.0, 1.0) - lp) * (0.18 + 0.06 * v)
			var x := int(clampf(lp * env * 2.2, -1.0, 1.0) * 32000.0)
			data.encode_s16(i * 2, x)
		var st := AudioStreamWAV.new()
		st.format = AudioStreamWAV.FORMAT_16_BITS
		st.mix_rate = rate
		st.data = data
		_steps.append(st)
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.volume_db = -16.0
		add_child(p)
		_players.append(p)

func _step_sound(soft: float) -> void:
	if _steps.is_empty():
		_make_steps()
	var p: AudioStreamPlayer = _players[_pi % _players.size()]
	_pi += 1
	p.stream = _steps[randi() % _steps.size()]
	p.pitch_scale = randf_range(0.85, 1.15) * (0.85 if soft > 0.5 else 1.0)
	p.play()

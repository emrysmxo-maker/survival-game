extends Node3D
# Вороны: 3 стаи по 8 птиц кружат над полями недалеко от камеры (днём); улетели далеко от камеры — стая
# перелетает к новому полю рядом. Иногда стая садится в поле (сидят врассыпную, крылья сложены, вертят головой);
# камера (потом — игрок) ближе 14 м — взлетают разом. Все птицы — одна MultiMesh, взмах крыльев — в шейдере.
var main
var _mm: MultiMesh
var _flocks: Array = []           # [центр (тайлы), высота (м), радиус (м), скорость, фаза, птиц, сидят 0..1, таймер, садятся?]
var _rng := RandomNumberGenerator.new()
const N := 24

const SH := """
shader_type spatial;
render_mode cull_disabled;
void vertex() {
	float sit = INSTANCE_CUSTOM.y;                       // 1 — сидит: крылья сложены, не машет
	float side = abs(VERTEX.x);
	if (side > 0.07) { VERTEX.x *= mix(1.0, 0.3, sit); }
	VERTEX.y += sin(TIME * (7.5 + INSTANCE_CUSTOM.z * 8.0) + INSTANCE_CUSTOM.x * 6.28) * side * 0.55 * (1.0 - sit);
}
void fragment() { ALBEDO = vec3(0.035, 0.035, 0.04); ROUGHNESS = 0.6; }
"""

func _ready() -> void:
	_rng.seed = 909
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# тело (ромб вдоль +z), голова, хвост, два крыла
	var P := [Vector3(0, 0, 0.26), Vector3(0.06, 0, 0.0), Vector3(0, 0.05, 0.0), Vector3(-0.06, 0, 0.0), Vector3(0, -0.03, 0.0), Vector3(0, 0, -0.2)]
	for tri in [[0, 1, 2], [0, 2, 3], [0, 4, 1], [0, 3, 4], [5, 2, 1], [5, 3, 2], [5, 1, 4], [5, 4, 3]]:
		for k in tri:
			st.add_vertex(P[k])
	for sx: float in [1.0, -1.0]:                                      # крылья
		st.add_vertex(Vector3(0.05 * sx, 0.01, 0.08)); st.add_vertex(Vector3(0.46 * sx, 0.0, 0.0)); st.add_vertex(Vector3(0.05 * sx, 0.01, -0.08))
		st.add_vertex(Vector3(0.46 * sx, 0.0, 0.0)); st.add_vertex(Vector3(0.36 * sx, 0.0, -0.12)); st.add_vertex(Vector3(0.05 * sx, 0.01, -0.08))
	st.add_vertex(Vector3(0, 0.005, -0.18)); st.add_vertex(Vector3(0.08, 0.0, -0.34)); st.add_vertex(Vector3(-0.08, 0.0, -0.34))   # хвост
	st.generate_normals()
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH
	mat.shader = sh
	mesh.surface_set_material(0, mat)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = mesh
	_mm.instance_count = N
	for i in N:
		_mm.set_instance_custom_data(i, Color(_rng.randf(), 0, 0, 0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.custom_aabb = AABB(Vector3(-300, -50, -300), Vector3(600, 200, 600))     # птицы летают по всей карте — не отсекать по старым границам
	add_child(mi)
	for f in 3:
		_flocks.append(_new_flock(main.focus))

func _new_flock(near: Vector2) -> Array:
	for k in 20:                                                       # над полем (не над лесом), недалеко от камеры
		var p := near + Vector2(_rng.randf_range(-28, 28), _rng.randf_range(-28, 28))
		if WorldGen.forest_mask(p.x, p.y) < 0.3 and WorldGen.in_map(p.x, p.y, 10.0):
			return [p, _rng.randf_range(12.0, 20.0), _rng.randf_range(5.0, 9.0), _rng.randf_range(0.3, 0.5) * (1 if _rng.randf() < 0.5 else -1), _rng.randf() * TAU, 8, 0.0, _rng.randf_range(20.0, 50.0), false]
	return [near, 16.0, 7.0, 0.35, 0.0, 8, 0.0, 30.0, false]

var _t := 0.0
func _process(dt: float) -> void:
	_t += dt
	var day: float = 1.0 - main.daynight.night
	visible = day > 0.2
	if not visible:
		return
	var i := 0
	for f in _flocks:
		var c: Vector2 = f[0]
		if c.distance_to(main.focus) > 75.0:
			f.assign(_new_flock(main.focus))
			c = f[0]
		# посадка/взлёт: таймер; камера ближе 14 м — взлёт разом
		var near: bool = c.distance_to(main.focus) * WorldGen.T < 14.0
		f[7] -= dt
		if f[8] and near:
			f[8] = false
			f[7] = _rng.randf_range(25.0, 50.0)
		elif f[7] <= 0.0:
			f[8] = (not f[8]) and not near and WorldGen.water_at(c.x, c.y).x < 0.1
			f[7] = _rng.randf_range(25.0, 60.0) if f[8] else _rng.randf_range(20.0, 50.0)
		f[6] = move_toward(f[6], 1.0 if f[8] else 0.0, dt * (0.12 if f[8] else 0.8))   # садятся плавно, взлетают быстро
		var land: float = f[6]
		f[4] += f[3] * dt * (1.0 - land)
		c += Vector2(cos(f[4] * 0.13), sin(f[4] * 0.11)) * dt * 1.2 * (1.0 - land)  # стая медленно сносится
		f[0] = c
		var g0: float = WorldGen.height_m(c.x, c.y)
		var gh: float = g0 + float(f[1])
		for b in f[5]:
			if i >= N:
				break
			var a: float = f[4] + b * TAU / f[5] + sin(f[4] * 0.7 + b) * 0.4
			var r: float = f[2] * (0.75 + 0.35 * sin(b * 1.7))
			var pos := Vector3(c.x * WorldGen.T + cos(a) * r, gh + sin(f[4] * 1.3 + b) * 1.5, c.y * WorldGen.T + sin(a) * r)
			var fwd := Vector3(-sin(a), 0, cos(a)) * signf(f[3])               # по касательной к кругу
			var bs := Basis.looking_at(-fwd, Vector3.UP) * Basis(Vector3(0, 0, 1), -0.35 * signf(f[3]))   # крен в вираже
			if land > 0.0:                                                  # на земле: врассыпную, головой туда-сюда
				var gp: Vector2 = Vector2(c.x * WorldGen.T, c.y * WorldGen.T) + Vector2(cos(b * 2.4), sin(b * 2.4)) * (1.0 + 0.6 * b)
				var gpos := Vector3(gp.x, WorldGen.height_m(gp.x / WorldGen.T, gp.y / WorldGen.T) + 0.06, gp.y)
				var k := land * land * (3.0 - 2.0 * land)
				pos = pos.lerp(gpos, k)
				var gb := Basis(Vector3.UP, float(b) * 1.3 + sin(_t * 0.8 + float(b) * 3.0) * 0.8)
				bs = bs.slerp(gb, k)
			_mm.set_instance_transform(i, Transform3D(bs.scaled(Vector3.ONE * 1.1), pos))
			_mm.set_instance_custom_data(i, Color(float(i) * 0.137, clampf(land * 1.6 - 0.6, 0.0, 1.0), 1.0 - land if not f[8] and land > 0.02 else 0.0, 0.0))
			i += 1
	while i < N:
		_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
		i += 1

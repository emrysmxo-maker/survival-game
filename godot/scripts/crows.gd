extends Node3D
# Вороны: 3 стаи по 8 птиц кружат над полями недалеко от камеры (днём); улетели далеко от камеры — стая
# перелетает к новому полю рядом. Все птицы — одна MultiMesh (один вызов отрисовки), взмах крыльев — в шейдере.
var main
var _mm: MultiMesh
var _flocks: Array = []           # [центр (тайлы), высота (м), радиус (м), скорость, фаза, птиц]
var _rng := RandomNumberGenerator.new()
const N := 24

const SH := """
shader_type spatial;
render_mode cull_disabled;
void vertex() {
	float side = abs(VERTEX.x);
	VERTEX.y += sin(TIME * 7.5 + INSTANCE_CUSTOM.x * 6.28) * side * 0.55;
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
			return [p, _rng.randf_range(12.0, 20.0), _rng.randf_range(5.0, 9.0), _rng.randf_range(0.3, 0.5) * (1 if _rng.randf() < 0.5 else -1), _rng.randf() * TAU, 8]
	return [near, 16.0, 7.0, 0.35, 0.0, 8]

func _process(dt: float) -> void:
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
		f[4] += f[3] * dt
		c += Vector2(cos(f[4] * 0.13), sin(f[4] * 0.11)) * dt * 1.2                # стая медленно сносится
		f[0] = c
		var gh := WorldGen.height_m(c.x, c.y) + float(f[1])
		for b in f[5]:
			if i >= N:
				break
			var a: float = f[4] + b * TAU / f[5] + sin(f[4] * 0.7 + b) * 0.4
			var r: float = f[2] * (0.75 + 0.35 * sin(b * 1.7))
			var pos := Vector3(c.x * WorldGen.T + cos(a) * r, gh + sin(f[4] * 1.3 + b) * 1.5, c.y * WorldGen.T + sin(a) * r)
			var fwd := Vector3(-sin(a), 0, cos(a)) * signf(f[3])               # по касательной к кругу
			var bs := Basis.looking_at(-fwd, Vector3.UP) * Basis(Vector3(0, 0, 1), -0.35 * signf(f[3]))   # крен в вираже
			_mm.set_instance_transform(i, Transform3D(bs.scaled(Vector3.ONE * 1.1), pos))
			i += 1
	while i < N:
		_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
		i += 1

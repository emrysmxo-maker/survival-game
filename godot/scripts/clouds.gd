extends Node3D
# Живые облака: два слоя над картой (≈40 и 48 м над землёй), видны при отдалении камеры (cam_size > 26),
# вблизи исчезают и не рисуются вовсе (0 затрат). Плывут по ветру и меняют форму (слои шума едут
# с разной скоростью), густота — по погоде (weather.cloud), цвет — по солнцу и времени суток,
# объём — облако из «клубов» (ячеистый шум), свет по наклону его поверхности: верх к солнцу светлый, бока и низ в тени,
# края тоньше и светлее на просвет. Тени облаков по земле — две большие декали плывут по ветру (видны и вблизи).
# Отладка: --clouds (видны всегда).
var main
var _layers: Array[MeshInstance3D] = []
var _mat: Array[ShaderMaterial] = []
var _always := false

const H := [40.0, 48.0]            # высота слоёв над землёй у фокуса, м
const FADE_A := 26.0               # cam_size: с этого отдаления появляются
const FADE_B := 50.0               # ... полностью видны

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D puffs : filter_linear_mipmap, repeat_enable;   // ячеистый шум — «клубы»
uniform float k = 0.0;              // видимость (отдаление)
uniform float cover = 0.3;          // густота 0..1
uniform float layer = 0.0;          // 0 нижний, 1 верхний (сдвиг шума)
uniform vec3 lit : source_color = vec3(1.0);
uniform vec3 shade : source_color = vec3(0.6, 0.64, 0.7);
uniform vec2 sun_xz = vec2(0.5, 0.5);
uniform vec2 wind = vec2(1.0, 0.35);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float dens(vec2 p) {
	float t = TIME * (1.0 + layer * 0.35);                 // верхний слой быстрее
	vec2 o = vec2(layer * 0.37, layer * 0.71);
	vec2 side = vec2(-wind.y, wind.x);
	// масштабы едут с разной скоростью и вбок друг к другу — облака плывут ≈4 м/с и меняют форму
	float d = texture(noise, p * 0.0022 + o - wind * t * 0.0088).r * 0.58
		+ texture(noise, p * 0.0061 - o - wind * t * 0.019 + side * t * 0.006).r * 0.29
		+ texture(noise, p * 0.019 + o * 2.0 - wind * t * 0.05 - side * t * 0.02).r * 0.13;
	float pf = texture(puffs, p * 0.009 + o - wind * t * 0.012).r;          // клубы: облако бугристое, а не ровное пятно
	d = d * 0.82 + pf * 0.26 - 0.06;
	float thr = mix(0.66, 0.38, cover) + layer * 0.05;
	return smoothstep(thr, thr + 0.16, d);
}
void fragment() {
	vec2 p = wp.xz;
	float d = dens(p);
	if (d < 0.004) discard;
	// поверхность облака — «холм» высотой d: наклон по разности соседних точек, свет — по наклону к солнцу
	float dx = dens(p + vec2(6.0, 0.0)) - d;
	float dz = dens(p + vec2(0.0, 6.0)) - d;
	vec3 n = normalize(vec3(-dx * 7.0, 1.0, -dz * 7.0));
	vec3 sl = normalize(vec3(sun_xz.x, 0.9, sun_xz.y));
	float lam = clamp(dot(n, sl), 0.0, 1.0);
	float thick = smoothstep(0.2, 1.0, d);                       // толща — темнее (низ облака), края — светлее на просвет
	float light = clamp(lam * (1.0 - 0.45 * thick) + 0.35 * (1.0 - thick), 0.0, 1.0);
	ALBEDO = mix(shade, lit, light);
	float edge = 1.0 - smoothstep(0.38, 0.5, length(UV - 0.5));
	ALPHA = d * k * edge * (0.82 - layer * 0.14);
}
"""

func _ready() -> void:
	_always = OS.get_cmdline_user_args().has("--clouds")
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = 0.012
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = 4
	nz.seed = 1907
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.normalize = true
	tex.noise = nz
	var cn := FastNoiseLite.new()                        # клубы
	cn.noise_type = FastNoiseLite.TYPE_CELLULAR
	cn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	cn.frequency = 0.05
	cn.fractal_type = FastNoiseLite.FRACTAL_FBM
	cn.fractal_octaves = 2
	cn.seed = 77
	var ptex := NoiseTexture2D.new()
	ptex.width = 256
	ptex.height = 256
	ptex.seamless = true
	ptex.generate_mipmaps = true
	ptex.normalize = true
	ptex.invert = true
	ptex.noise = cn
	var sh := Shader.new()
	sh.code = SHADER
	var pm := PlaneMesh.new()
	pm.size = Vector2(700, 700)
	for i in H.size():
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("noise", tex)
		m.set_shader_parameter("puffs", ptex)
		m.set_shader_parameter("layer", float(i))
		m.render_priority = i                            # верхний слой рисуется поверх нижнего
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_layers.append(mi)
		_mat.append(m)
	_make_shadows(tex)

# ---------------- тени облаков по земле ----------------
# пятна тени считает шейдер земли (ground.gdshader cloud_*): шум периодом 640 м плывёт по ветру ≈4 м/с
const SH_S := 640.0
const WIND_V := 4.0
var _sh_off := Vector2.ZERO
func _make_shadows(_tex: NoiseTexture2D) -> void:
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = 0.03                                  # пятно тени ~80 м — от одного облака
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = 3
	nz.seed = 4242
	var st := NoiseTexture2D.new()
	st.width = 256
	st.height = 256
	st.seamless = true
	st.normalize = true
	st.generate_mipmaps = true
	st.noise = nz
	if main and main.world and main.world.ground_mat:
		main.world.ground_mat.set_shader_parameter("cloud_tex", st)

func _update_shadows(dt: float, cl: float, day: float) -> void:
	if not (main and main.world and main.world.ground_mat):
		return
	var a := clampf((cl - 0.12) / 0.45, 0.0, 1.0) * day
	_sh_off -= Vector2(1.0, 0.35).normalized() * WIND_V * dt / SH_S
	_sh_off = Vector2(fposmod(_sh_off.x, 1.0), fposmod(_sh_off.y, 1.0))
	main.world.ground_mat.set_shader_parameter("cloud_k", a)
	main.world.ground_mat.set_shader_parameter("cloud_off", _sh_off)

func _process(_dt: float) -> void:
	_update_shadows(_dt, main.weather.cloud, 1.0 - main.daynight.night)
	var k := 1.0 if _always else smoothstep(FADE_A, FADE_B, main.cam_size)
	for mi in _layers:
		mi.visible = k > 0.01
	if k <= 0.01:
		return
	var dn = main.daynight
	var day: float = 1.0 - dn.night
	var cl: float = main.weather.cloud
	var gold: Color = dn.sun.light_color
	var lit := Color(0.16, 0.18, 0.26).lerp(Color(1.0, 1.0, 1.0) * gold, day).lerp(Color(0.72, 0.74, 0.78), cl * 0.6 * day)
	var shade := Color(0.06, 0.07, 0.11).lerp(Color(0.58, 0.62, 0.7), day).lerp(Color(0.42, 0.44, 0.48), cl * 0.6 * day)
	var sd: Vector3 = dn.sun.global_transform.basis.z         # к солнцу
	var sxz := Vector2(sd.x, sd.z)
	sxz = sxz.normalized() if sxz.length() > 0.01 else Vector2(0.5, 0.5)
	# слой сдвинут к камере: линия взгляда через фокус пересекает его на высоте h
	var b: Basis = main.cam.global_transform.basis
	var back := Vector3(b.z.x, 0.0, b.z.z).normalized()
	var tn := tan(deg_to_rad(maxf(main.cam_elev, 15.0)))
	var foc: Vector2 = main.focus
	var base := Vector3(foc.x * WorldGen.T, main.cam_h, foc.y * WorldGen.T)
	for i in _layers.size():
		var h: float = H[i]
		_layers[i].global_position = base + Vector3(0, h, 0) + back * (h / tn)
		var m := _mat[i]
		m.set_shader_parameter("k", k)
		m.set_shader_parameter("cover", clampf(0.22 + cl * 0.7, 0.0, 1.0))
		m.set_shader_parameter("lit", lit)
		m.set_shader_parameter("shade", shade)
		m.set_shader_parameter("sun_xz", sxz)

// Полупрозрачная копия импостора (дерево/куст перед бойцом). Видимость — |INSTANCE_CUSTOM.y|-1.
// Импостор: высокодетальная модель (Poly Haven, CC0), заранее отрендеренная под угол
// игровой камеры в две картинки — цвет и «нормаль+глубина+затенённость».
// Здесь по ним считается настоящий свет от солнца (объём), тени на кроне,
// и глубина каждого пикселя (боец правильно заходит за ствол и под крону).
// INSTANCE_CUSTOM: x — фаза ветра, y — зеркало*(1+видимость), z — высота верха (м), w — 1 = лежит на земле.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert_wrap, specular_disabled, blend_mix, depth_draw_never;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D ndt_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform float depth_range = 4.0;      // ± метров, на которые разложена глубина в ndt.b
uniform float sway = 0.0;
uniform float push = 0.0;
uniform float translucency = 0.25;    // просвет листвы против солнца
uniform float ao_strength = 0.5;
uniform float gain = 1.0;            // яркость цвета (у разных моделей разная экспозиция)
uniform bool use_depth = true;
global uniform bool gl_compat;
global uniform vec3 cam_back;      // ось камеры «к зрителю»: по ней отличаем проход теней от основного
global uniform vec3 player_pos;
global uniform float wind_on;

varying float v_scale;
varying float v_flip;
varying float v_vis;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	v_scale = s;
	v_flip = sign(INSTANCE_CUSTOM.y);
	v_vis = clamp(abs(INSTANCE_CUSTOM.y) - 1.0, 0.0, 1.0);
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 to_cam = normalize(INV_VIEW_MATRIX[2].xyz);
	float vx = VERTEX.x * s * v_flip;
	float vy = VERTEX.y * s;
	float top = max(INSTANCE_CUSTOM.z, 0.05);
	float hf = clamp(vy / top, 0.0, 1.0);
	vec3 wp = origin + right * vx + up * vy;
	float ph = INSTANCE_CUSTOM.x;
	float wind = sin(TIME * 2.0 * 3.14159 * 0.32 + ph) * 0.7 + sin(TIME * 3.1 + ph * 2.3) * 0.3;
	wp += right * sway * wind_on * 0.035 * top * hf * hf * wind;
	if (push > 0.0) {
		vec3 d = origin - player_pos; d.y = 0.0;
		float dist = length(d);
		float R = 0.9;
		if (dist < R) {
			float k = 1.0 - dist / R;
			vec3 dir = dist > 0.001 ? d / dist : right;
			wp += (dir * 0.9 * top - vec3(0.0, 0.35 * top, 0.0)) * k * k * push * hf;
		}
	}
	// часть картинки ниже точки земли (и лежачие предметы) — к камере: на экране то же место, но не под землёй
	float below = (INSTANCE_CUSTOM.w > 0.5) ? (vy + 0.02 / 0.684) : min(vy, 0.0);
	if (below < 0.0 || INSTANCE_CUSTOM.w > 0.5) {
		wp += to_cam * ((0.03 - 0.684 * below) / 0.729);
	}
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

// упорядоченный дизеринг 4×4 — ровная «сетка», на экране телефона почти незаметна
float dither(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int i = q.x + q.y * 4;
	float b[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (b[i] + 0.5) / 16.0;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	if (c.a < 0.35) { discard; }
	bool shadow_pass = false;
	vec4 nd = texture(ndt_tex, UV);
	vec2 nxy = nd.rg * 2.0 - 1.0;
	nxy.x *= v_flip;
	NORMAL = normalize(vec3(nxy, sqrt(max(0.0, 1.0 - dot(nxy, nxy)))));
	if (false) {
		float d = (nd.b * 2.0 - 1.0) * depth_range * v_scale;
		vec3 pos = VERTEX + vec3(0.0, 0.0, d);
		LIGHT_VERTEX = pos;
		vec4 clip = PROJECTION_MATRIX * vec4(pos, 1.0);
		DEPTH = gl_compat ? clip.z / clip.w * 0.5 + 0.5 : clip.z / clip.w;
	}
	ALBEDO = clamp(c.rgb * gain, 0.0, 1.0);
	AO = mix(1.0, nd.a, ao_strength);
	ALPHA = v_vis;
	AO_LIGHT_AFFECT = 0.6;
	BACKLIGHT = c.rgb * translucency;
}

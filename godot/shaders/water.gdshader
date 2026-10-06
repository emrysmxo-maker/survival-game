// Вода (река, озёра). Глубина в каждой вершине считается заранее (цвет вершины .b = глубина/6 м),
// течение — .rg. Волны — смещение вершин + рябь картой нормалей. Прозрачность по глубине: дно видно
// на 2–3 м, дальше темнеет. Блики солнца (global sun_dir), отражение неба и облаков, каустика на дне
// мелководья, пена прибоя у кромки.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
uniform sampler2D n1 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D n2 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_col : source_color = vec3(0.45, 0.62, 0.52);
uniform vec3 mid_col : source_color = vec3(0.10, 0.40, 0.42);
uniform vec3 deep_col : source_color = vec3(0.025, 0.13, 0.22);
uniform vec3 sky_col : source_color = vec3(0.60, 0.76, 0.92);
uniform vec3 cloud_col : source_color = vec3(0.95, 0.96, 0.98);
uniform float wave_amp = 0.045;
global uniform vec3 sun_dir;

varying vec2 flow;
varying float depth;
varying float dteff;
varying vec3 wpos;
varying vec3 wnrm;

float swell(vec2 p, float t) {
	return sin(dot(p, vec2(0.62, 0.35)) * 1.1 + t * 1.25) * 0.5
		+ sin(dot(p, vec2(-0.41, 0.78)) * 1.7 + t * 1.7) * 0.3
		+ sin(dot(p, vec2(0.9, -0.2)) * 2.9 + t * 2.4) * 0.2;
}

void vertex() {
	flow = COLOR.rg * 2.0 - 1.0;
	depth = COLOR.b * 6.0;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wp.xz - flow * TIME * 0.6;
	float a = wave_amp * smoothstep(0.0, 0.5, depth);
	float e = 0.15;
	float h = swell(p, TIME);
	// прилив-отлив: уровень «дышит», прибой набегает на пологий берег и откатывается неровно
	float tide = 0.07 * sin(TIME * 0.55 + dot(wp.xz, vec2(0.21, 0.14))) + 0.04 * sin(TIME * 0.9 - dot(wp.xz, vec2(0.37, -0.22)));
	VERTEX.y += h * a + tide;
	dteff = depth + tide;
	float hx = swell(p + vec2(e, 0.0), TIME);
	float hz = swell(p + vec2(0.0, e), TIME);
	NORMAL = normalize(vec3(-(hx - h) / e * a, 1.0, -(hz - h) / e * a));
	wnrm = NORMAL;
	wpos = wp;
}

void fragment() {
	vec2 uv = wpos.xz;
	vec2 fl = flow * TIME;
	vec3 a = texture(n1, uv * 0.11 - fl * 0.11 + TIME * vec2(0.012, 0.007)).rgb;
	vec3 b = texture(n2, uv * 0.23 - fl * 0.22 - TIME * vec2(0.009, 0.014)).rgb;
	NORMAL_MAP = normalize((a + b) - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.22;
	float d = dteff;
	// цвет по глубине: мелко — светлая бирюза, ~2 м — бирюза, глубже — тёмно-синяя
	vec3 col = mix(shallow_col, mid_col, smoothstep(0.1, 1.8, d));
	col = mix(col, deep_col, smoothstep(2.2, 5.0, d));
	// мировая нормаль с рябью (для бликов и отражений)
	vec3 nt = normalize((a + b) - 1.0);
	vec3 nW = normalize(wnrm + vec3(nt.x, 0.0, nt.y) * 0.30);
	vec3 vW = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(nW, vW), 0.0, 1.0), 3.0);
	float cl = smoothstep(0.45, 0.8, texture(n1, uv * 0.012 + TIME * vec2(0.002, 0.001)).b * 0.6 + texture(n2, uv * 0.02 - TIME * 0.0015).g * 0.5);
	vec3 sky = mix(sky_col, cloud_col, cl);
	col = mix(col, sky, clamp(fres * 0.5 + 0.08 * smoothstep(0.3, 1.5, d), 0.0, 0.6));
	// блики солнца на волнах: отражённый луч совпадает с направлением на солнце
	vec3 r = reflect(-vW, nW);
	float sunk = clamp(sun_dir.y * 4.0, 0.0, 1.0);
	float glint = pow(max(dot(r, normalize(sun_dir)), 0.0), 90.0) * 3.0;
	float sparkle = smoothstep(0.35, 0.8, texture(n2, uv * 0.9 + TIME * vec2(0.03, -0.02)).b);
	// каустика: подвижная сетка света на дне мелководья
	float c1 = texture(n1, uv * 0.42 + TIME * vec2(0.035, 0.02)).g;
	float c2 = texture(n2, uv * 0.55 - TIME * vec2(0.03, 0.04)).g;
	float caustic = smoothstep(0.80, 1.0, 1.0 - abs(c1 + c2 - 1.0) * 1.5);
	float cw = (1.0 - smoothstep(0.3, 2.4, d)) * smoothstep(0.02, 0.2, d);
	// пена прибоя у кромки
	float lap = 0.05 + 0.035 * sin(TIME * 1.1 + wpos.x * 0.45 + wpos.z * 0.3);
	float noise = texture(n2, uv * 0.6 + TIME * 0.03).g;
	float foam = (1.0 - smoothstep(0.0, lap, d)) * smoothstep(0.4, 0.7, noise + 0.2) * 0.85;
	float streak = length(flow) > 0.3 ? smoothstep(0.64, 0.9, texture(n2, uv * vec2(0.05, 0.22) - fl * 0.2).g) * 0.3 : 0.0;
	ALBEDO = mix(col, vec3(0.86, 0.9, 0.88), clamp(foam + streak, 0.0, 1.0));
	EMISSION = vec3(1.0, 0.96, 0.85) * (glint * (0.35 + 0.65 * sparkle)) * sunk + vec3(0.8, 1.0, 0.9) * caustic * cw * 0.5 * sunk;
	// прозрачность: дно видно до ~2–3 м, дальше вода непрозрачная
	ALPHA = clamp(0.07 + 0.88 * smoothstep(0.0, 4.2, d) + foam * 0.5, 0.0, 0.96);
	ROUGHNESS = 0.08;
	SPECULAR = 0.5;
}

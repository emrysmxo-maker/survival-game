// Вода (река, озёра). Без буфера глубины (на телефоне он давал резкие края): глубина в каждой
// вершине считается заранее (цвет вершины .b = глубина/3 м), течение — .rg.
// Волны — смещение вершин (несколько синусов) + мелкая рябь картой нормалей; у берега прозрачно
// и видно дно, вглубь — бирюза и тёмная вода; у кромки «дышит» пена прибоя.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
uniform sampler2D n1 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D n2 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_col : source_color = vec3(0.42, 0.58, 0.50);   // прозрачная бирюза над песком
uniform vec3 mid_col : source_color = vec3(0.12, 0.38, 0.40);
uniform vec3 deep_col : source_color = vec3(0.04, 0.16, 0.24);     // глубина — сине-бирюзовая
uniform vec3 sky_col : source_color = vec3(0.66, 0.78, 0.90);
uniform vec3 cloud_col : source_color = vec3(0.93, 0.95, 0.97);
uniform float wave_amp = 0.045;

varying vec2 flow;
varying float depth;
varying float dteff;
varying vec3 wpos;

float swell(vec2 p, float t) {
	return sin(dot(p, vec2(0.62, 0.35)) * 1.1 + t * 1.25) * 0.5
		+ sin(dot(p, vec2(-0.41, 0.78)) * 1.7 + t * 1.7) * 0.3
		+ sin(dot(p, vec2(0.9, -0.2)) * 2.9 + t * 2.4) * 0.2;
}

void vertex() {
	flow = COLOR.rg * 2.0 - 1.0;
	depth = COLOR.b * 3.0;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wp.xz - flow * TIME * 0.6;
	float a = wave_amp * smoothstep(0.0, 0.5, depth);   // у самой кромки волна гаснет
	float e = 0.15;
	float h = swell(p, TIME);
	// прилив-отлив: уровень воды «дышит», прибой набегает на пологий берег и откатывается неровно
	float tide = 0.07 * sin(TIME * 0.55 + dot(wp.xz, vec2(0.21, 0.14))) + 0.04 * sin(TIME * 0.9 - dot(wp.xz, vec2(0.37, -0.22)));
	VERTEX.y += h * a + tide;
	dteff = depth + tide;
	float hx = swell(p + vec2(e, 0.0), TIME);
	float hz = swell(p + vec2(0.0, e), TIME);
	NORMAL = normalize(vec3(-(hx - h) / e * a, 1.0, -(hz - h) / e * a));
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
	vec3 col = mix(shallow_col, mid_col, smoothstep(0.05, 0.8, d));
	col = mix(col, deep_col, smoothstep(0.7, 2.2, d));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	// отражение неба с облаками (как на фото озёр): облака — крупный шум, плывут медленно
	float cl = smoothstep(0.45, 0.8, texture(n1, uv * 0.012 + TIME * vec2(0.002, 0.001)).b * 0.6 + texture(n2, uv * 0.02 - TIME * 0.0015).g * 0.5);
	vec3 sky = mix(sky_col, cloud_col, cl);
	col = mix(col, sky, clamp(fres * 0.6 + 0.1 * smoothstep(0.3, 1.5, d), 0.0, 1.0));
	// прибой: полоса пены у кромки, набегает и откатывается
	float lap = 0.05 + 0.035 * sin(TIME * 1.1 + wpos.x * 0.45 + wpos.z * 0.3);   // кромка набегает/откатывается
	float noise = texture(n2, uv * 0.6 + TIME * 0.03).g;
	float foam = (1.0 - smoothstep(0.0, lap, d)) * smoothstep(0.4, 0.7, noise + 0.2) * 0.85;
	float streak = length(flow) > 0.3 ? smoothstep(0.64, 0.9, texture(n2, uv * vec2(0.05, 0.22) - fl * 0.2).g) * 0.3 : 0.0;
	ALBEDO = mix(col, vec3(0.86, 0.9, 0.88), clamp(foam + streak, 0.0, 1.0));
	ALPHA = clamp(0.1 + 0.8 * smoothstep(0.0, 1.6, d) + foam * 0.5, 0.0, 0.95);
	ROUGHNESS = 0.16;
	SPECULAR = 0.42;
}

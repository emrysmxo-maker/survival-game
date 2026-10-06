// Вода (река, озёра). Без буфера глубины (на телефоне он давал резкие края): глубина в каждой
// вершине считается заранее (цвет вершины .b = глубина/3 м), течение — .rg.
// Волны — смещение вершин (несколько синусов) + мелкая рябь картой нормалей; у берега прозрачно
// и видно дно, вглубь — бирюза и тёмная вода; у кромки «дышит» пена прибоя.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
uniform sampler2D n1 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D n2 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_col : source_color = vec3(0.36, 0.44, 0.36);
uniform vec3 mid_col : source_color = vec3(0.10, 0.27, 0.29);
uniform vec3 deep_col : source_color = vec3(0.03, 0.09, 0.11);
uniform vec3 sky_col : source_color = vec3(0.62, 0.72, 0.80);
uniform float wave_amp = 0.045;

varying vec2 flow;
varying float depth;
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
	VERTEX.y += h * a;
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
	float d = depth;
	vec3 col = mix(shallow_col, mid_col, smoothstep(0.05, 0.8, d));
	col = mix(col, deep_col, smoothstep(0.7, 2.2, d));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	col = mix(col, sky_col, clamp(fres * 0.55 + 0.06, 0.0, 1.0));
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

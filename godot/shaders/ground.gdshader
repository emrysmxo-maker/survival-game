// Земля: 8 фототекстур Poly Haven (CC0, 2K) с картами рельефа (normal map), смешиваются по весам.
// Слои (массив текстур): 0 лесная подстилка, 1 трава, 2 мох/листва, 3 гарь, 4 камни, 5 болото, 6 тропа, 7 дно реки.
// COLOR = (тропа, болото, дно реки, камни), UV2 = (вода, поляна); UV — тайлы мира.
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform sampler2DArray t_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray t_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float meters_per_texture = 2.6;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 morok_c[3];                 // морок: центр x, z (м), радиус (м) — серая, выцветшая земля   // бесшовный шум (Godot NoiseTexture2D): крупные пятна, анти-повтор, лужи
uniform bool detail = true;          // false (Низкое/Среднее): одна выборка на слой, слабые слои пропускаются
global uniform bool q_ground_normals;

float ssf(float e0, float e1, float x) { float t = clamp((x - e0) / (e1 - e0), 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }

varying vec4 w1;
varying vec2 w2;
varying vec2 tile;

void vertex() {
	w1 = COLOR;
	w2 = UV2;
	tile = UV;
	// касательные для карт рельефа: земля почти горизонтальная — оси мира
	TANGENT = normalize(vec3(1.0, 0.0, 0.0) - NORMAL * NORMAL.x);
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

// анти-повтор: каждый слой берётся в двух масштабах со сдвигом и смешивается по шуму
vec4 lay(sampler2DArray s, vec2 uv, float i, float mixk) {
	if (!detail) { return texture(s, vec3(uv, i)); }
	vec4 a = texture(s, vec3(uv, i));
	vec4 b = texture(s, vec3(uv * 0.43 + vec2(0.37, 0.71), i));
	return mix(a, b, mixk);
}

void fragment() {
	vec2 uv = tile * 0.837 / meters_per_texture;
	float n = (sin(tile.x * 0.03 + tile.y * 0.017) + sin(tile.x * 0.017 - tile.y * 0.035) * 1.3 + sin(tile.x * 0.06 + tile.y * 0.045) * 0.5) / 2.8;
	float eco = sin(tile.x / 12.0 * 0.3) + cos(tile.y / 12.0 * 0.3);
	vec2 wm = tile * 0.837;                                  // метры
	float m40 = texture(macro_tex, wm / 46.0).r;             // пятна ~десятки метров
	float m11 = texture(macro_tex, wm / 11.0 + vec2(0.31, 0.67)).r;
	float m4 = texture(macro_tex, wm / 3.7 + vec2(0.71, 0.13)).r;
	float mk = ssf(0.38, 0.62, m11);                         // анти-повтор — по шуму, а не правильным узором
	float rr = w1.r;                                         // 0..0,5 — грунтовая дорога, 0,5..1 — асфальт
	float asph = clamp((rr - 0.5) * 2.0, 0.0, 1.0);
	float path = rr < 0.5 ? clamp(rr * 2.0, 0.0, 1.0) : 0.0;
	float swamp = w1.g, riverbed = w1.b, rocky = w1.a;
	float water = w2.x, clearing = w2.y;
	float w[8];
	w[0] = 1.0;
	w[1] = max(ssf(0.18, 0.46, n), clearing * 0.9);
	w[2] = ssf(-0.14, -0.42, n) * (1.0 - clearing);
	w[3] = ssf(-0.55, -1.1, eco) * (1.0 - swamp);
	w[4] = rocky;
	w[5] = swamp;
	w[6] = path;
	w[7] = riverbed;
	vec3 c = vec3(0.0);
	vec3 nm = vec3(0.5, 0.5, 1.0);
	// послойное наложение снизу вверх
	for (int i = 0; i < 8; i++) {
		if (w[i] < (detail ? 0.004 : 0.06)) { continue; }
		vec3 ci = lay(t_albedo, uv, float(i), mk).rgb;
		c = i == 0 ? ci : mix(c, ci, w[i]);
		if (q_ground_normals) {
			vec3 ni = lay(t_normal, uv, float(i), mk).rgb;
			nm = i == 0 ? ni : mix(nm, ni, w[i]);
		}
	}
	// крупные пятна: светлее/темнее, суше/зеленее — поле и лес не выглядят «штампом»
	float bright = mix(0.84, 1.12, m40) * mix(0.94, 1.06, m4);
	c *= bright;
	c = mix(c, c * vec3(1.10, 1.03, 0.80), ssf(0.55, 0.8, m11) * (w[1] * 0.6 + clearing * 0.3));   // выгоревшая трава
	c = mix(c, c * vec3(0.86, 1.04, 0.84), ssf(0.45, 0.2, m40) * 0.5);                             // сочная зелень в низинах
	// асфальт: тёмный, с заплатками, трещинами и выбоинами (заброшено ~2 года)
	if (asph > 0.0) {
		vec3 ac = vec3(0.105, 0.105, 0.11) * mix(0.82, 1.18, m4) * mix(0.9, 1.1, m40);
		ac = mix(ac, vec3(0.07, 0.07, 0.075), ssf(0.62, 0.66, m11) * 0.8);                 // заплатки
		float crack = 1.0 - ssf(0.0, 0.035, abs(m4 - 0.5)) * 1.0;
		ac = mix(ac, vec3(0.05, 0.05, 0.05), crack * 0.55 * ssf(0.4, 0.6, m11));              // трещины
		ac = mix(ac, c * 0.8, ssf(0.72, 0.8, m40) * 0.6);                                     // земля и трава в выбоинах
		c = mix(c, ac, asph);
	}
	// морок: земля выцветает и сереет, с рваным краем
	float mk2 = 0.0;
	for (int i = 0; i < 3; i++) {
		float dm = length(wm - morok_c[i].xy) + (m11 - 0.5) * 9.0;
		mk2 = max(mk2, ssf(morok_c[i].z, morok_c[i].z * 0.45, dm));
	}
	if (mk2 > 0.0) {
		float lum = dot(c, vec3(0.3, 0.59, 0.11));
		c = mix(c, vec3(lum) * vec3(0.66, 0.62, 0.70), mk2 * 0.8);
	}
	// лужи на болоте — неровные, по шуму
	float puddle = swamp * ssf(0.6, 0.7, m11 * 0.7 + m4 * 0.3) * 0.8;
	c = mix(c, c * 0.45 + vec3(0.02, 0.04, 0.04), puddle);
	// вода
	float ripple = sin(tile.x * 2.1 + TIME * 1.3) * sin(tile.y * 1.7 - TIME * 1.1) * 0.5 + 0.5;
	vec3 wc = mix(vec3(0.07, 0.12, 0.11), vec3(0.16, 0.22, 0.21), ripple * 0.5);
	float wet = max(water * 0.88, puddle);
	// под водой и у кромки — мокрый грунт: темнее, с зеленоватым налётом (саму воду рисует water.gdshader)
	c = mix(c, c * vec3(0.52, 0.58, 0.56) + vec3(0.0, 0.015, 0.012), water * 0.9);
	ALBEDO = c;
	if (q_ground_normals) {
		NORMAL_MAP = mix(nm, vec3(0.5, 0.5, 1.0), puddle);
		NORMAL_MAP_DEPTH = 1.2;
	}
	ROUGHNESS = mix(mix(mix(0.95, 0.85, asph), 0.78, water * 0.9), 0.12, puddle);     // мокрый песок матовый, глянец только в лужах
	SPECULAR = mix(0.2, 0.6, wet);
}

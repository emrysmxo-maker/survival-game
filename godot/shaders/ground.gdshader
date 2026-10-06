// Земля: 8 фототекстур Poly Haven (CC0, 2K) с картами рельефа (normal map), смешиваются по весам.
// Слои (массив текстур): 0 лесная подстилка, 1 трава, 2 мох/листва, 3 гарь, 4 камни, 5 болото, 6 тропа, 7 дно реки.
// COLOR = (тропа, болото, дно реки, камни), UV2 = (вода, поляна); UV — тайлы мира.
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform sampler2DArray t_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray t_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float meters_per_texture = 2.6;
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
	vec4 a = texture(s, vec3(uv, i));
	vec4 b = texture(s, vec3(uv * 0.43 + vec2(0.37, 0.71), i));
	return mix(a, b, mixk);
}

void fragment() {
	vec2 uv = tile * 0.837 / meters_per_texture;
	float n = (sin(tile.x * 0.03 + tile.y * 0.017) + sin(tile.x * 0.017 - tile.y * 0.035) * 1.3 + sin(tile.x * 0.06 + tile.y * 0.045) * 0.5) / 2.8;
	float eco = sin(tile.x / 12.0 * 0.3) + cos(tile.y / 12.0 * 0.3);
	float mk = ssf(-0.3, 0.3, sin(tile.x * 0.11 + 1.3 * sin(tile.y * 0.07)) * sin(tile.y * 0.13 + 0.9 * sin(tile.x * 0.05)));
	float path = w1.r, swamp = w1.g, riverbed = w1.b, rocky = w1.a;
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
		if (w[i] < 0.004) { continue; }
		vec3 ci = lay(t_albedo, uv, float(i), mk).rgb;
		c = i == 0 ? ci : mix(c, ci, w[i]);
		if (q_ground_normals) {
			vec3 ni = lay(t_normal, uv, float(i), mk).rgb;
			nm = i == 0 ? ni : mix(nm, ni, w[i]);
		}
	}
	// лужи на болоте
	float puddle = swamp * ssf(0.35, 0.75, sin(tile.x * 0.7 + sin(tile.y * 0.5) * 2.0) * sin(tile.y * 0.63 + 1.3 + sin(tile.x * 0.41) * 2.0)) * 0.8;
	c = mix(c, c * 0.45 + vec3(0.02, 0.04, 0.04), puddle);
	// вода
	float ripple = sin(tile.x * 2.1 + TIME * 1.3) * sin(tile.y * 1.7 - TIME * 1.1) * 0.5 + 0.5;
	vec3 wc = mix(vec3(0.07, 0.12, 0.11), vec3(0.16, 0.22, 0.21), ripple * 0.5);
	float wet = max(water * 0.88, puddle);
	// под водой и у кромки — мокрый грунт: темнее, с зеленоватым налётом (саму воду рисует water.gdshader)
	c = mix(c, c * vec3(0.52, 0.58, 0.56) + vec3(0.0, 0.015, 0.012), water * 0.9);
	ALBEDO = c;
	if (q_ground_normals) {
		NORMAL_MAP = mix(nm, vec3(0.5, 0.5, 1.0), wet);
		NORMAL_MAP_DEPTH = 1.2;
	}
	ROUGHNESS = mix(0.95, 0.12, wet);
	SPECULAR = mix(0.2, 0.6, wet);
}

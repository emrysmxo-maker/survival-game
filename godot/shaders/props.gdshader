// Постройки, машины, мелочь из props.glb — один шейдер вместо стандартного материала (props.gd _collect):
// те же текстура, карта рельефа, цвет вершин, шероховатость, металл + ИЗНОС на каждый экземпляр
// (INSTANCE_CUSTOM: r — износ 0 ухоженный .. 0.35 пожилой .. 0.7 запущенный .. 1; g — случайное число дома; b — 1 у крыши; a — 1 у машин и техники).
// Износ: тёмный низ стен (грязь, брызги дождя), потёки сверху вниз, выцветание краски, мох и пятна на крышах.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_tex = false;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_normal = false;
uniform float normal_k = 1.0;
uniform bool use_vc = true;
uniform float roughness = 0.9;
uniform float metallic = 0.0;
uniform float specular = 0.35;
uniform float grime = 1.0;            // насколько материал пачкается (стекло/фары — 0.3)

varying vec3 lp;                       // точка в осях модели (м): y — высота над землёй
varying vec3 ln;                       // нормаль в осях модели
varying vec4 cd;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	cd = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 c = albedo.rgb;
	if (has_tex) { c *= texture(albedo_tex, UV).rgb; }
	if (use_vc) { c *= COLOR.rgb; }
	float wear = clamp(cd.r, 0.0, 1.0);
	float seed = cd.g * 37.0;
	bool roof = cd.b > 0.5 || ln.y > 0.55;
	float along = lp.x * 0.83 + lp.z * 0.57;
	float rough = roughness;
	if (wear > 0.01 && grime > 0.0) {
		float w = wear * grime;
		// выцветание: светлее и серее, у старых сильнее
		float l = dot(c, vec3(0.3, 0.59, 0.11));
		c = mix(c, vec3(l) * vec3(1.04, 1.0, 0.93) + 0.03, 0.45 * w);
		if (roof) {
			// мох и тёмные пятна на крыше (сверху — не по краям), ржавчина/лишайник
			float m = vn(lp.xz * 0.9 + seed) * 0.65 + vn(lp.xz * 3.1 - seed) * 0.35;
			float moss = smoothstep(0.62 - 0.32 * w, 0.95, m) * w;
			c = mix(c, c * (cd.a > 0.5 ? vec3(0.78, 0.72, 0.62) : vec3(0.52, 0.6, 0.36)), moss);   // у машин — пыль, не мох
			float spot = smoothstep(0.55, 0.9, vn(lp.xz * 1.7 + seed * 2.0)) * w;
			c *= 1.0 - 0.35 * spot;
		} else {
			// низ стены: грязь и брызги от земли (до ~0.9 м), полосой с неровным краем
			float edge = 0.35 + 0.55 * w + 0.25 * vn(vec2(along * 2.0, seed));
			float mud = (1.0 - smoothstep(0.0, edge, lp.y)) * (0.35 + 0.55 * w);
			c = mix(c, c * vec3(0.42, 0.37, 0.31), mud);
			// потёки: вертикальные полосы сверху вниз
			float st = vn(vec2(along * 5.0 + seed, lp.y * 0.35));
			float streak = smoothstep(0.58, 0.92, st) * smoothstep(0.2, 1.4, lp.y) * w;
			c *= 1.0 - 0.32 * streak;
			// общая неравномерность — пятна сырости
			c *= 1.0 - 0.16 * w * vn(vec2(along, lp.y) * 1.3 + seed);
		}
		rough = mix(rough, 1.0, 0.6 * w);
	}
	// соседние дома не одного оттенка
	c *= 0.94 + 0.12 * fract(seed * 0.618);
	ALBEDO = clamp(c, 0.0, 1.0);
	ROUGHNESS = rough;
	METALLIC = metallic;
	SPECULAR = specular;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_k;
	}
}

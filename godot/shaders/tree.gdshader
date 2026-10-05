// Настоящее 3D-дерево (модель Polyy.AI, CC0): листва — геометрия, не картинка.
// Ветер качает верхушку; когда крона перед бойцом, над ним появляется «окошко»
// (дизеринг), чтобы его и автомат было видно.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform float gain = 1.0;
uniform float sway = 1.0;
uniform float hole_r = 1.6;
uniform vec3 tint = vec3(1.0);
uniform float sat = 0.8;
uniform bool leafless = false;      // сухостой: листва отбрасывается, остаются ветки и ствол
global uniform vec3 player_pos;
global uniform float wind_on;

void vertex() {
	float h = clamp(VERTEX.y + 0.5, 0.0, 1.0);
	float ph = MODEL_MATRIX[3].x * 0.55 + MODEL_MATRIX[3].z * 0.35;
	float w = sin(TIME * 2.0 * 3.14159 * 0.32 + ph) * 0.7 + sin(TIME * 3.1 + ph * 2.3) * 0.3;
	VERTEX.x += sway * wind_on * 0.012 * h * h * w;
	VERTEX.z += sway * wind_on * 0.006 * h * h * w;
}

void fragment() {
	// окошко над бойцом: ближе к камере, чем он, и в круге вокруг него на экране
	vec3 pv = (VIEW_MATRIX * vec4(player_pos + vec3(0.0, 0.9, 0.0), 1.0)).xyz;
	float d = length(VERTEX.xy - pv.xy);
	if (VERTEX.z > pv.z + 0.25 && d < hole_r) {
		float a = smoothstep(hole_r * 0.45, hole_r, d);
		float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (n > a) { discard; }
	}
	vec3 c = texture(albedo_tex, UV).rgb;
	if (leafless) {
		if (c.g > c.r + 0.02 && c.g > c.b + 0.05) { discard; }
		c = mix(c, vec3(0.30, 0.25, 0.20), 0.65);
	}
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, sat);
	ALBEDO = clamp(c * gain * tint, 0.0, 1.0);
	ROUGHNESS = 1.0;
	if (has_normal) { NORMAL_MAP = texture(normal_tex, UV).rgb; }
}

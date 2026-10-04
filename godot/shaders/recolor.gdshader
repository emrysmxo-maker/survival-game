// Боец: исходная оранжевая текстура -> оливково-хаки (как в браузерной версии:
// hue-rotate 58°, saturate 0.55, brightness 0.8).
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;
uniform float hue_deg = 58.0;
uniform float sat = 0.55;
uniform float bright = 0.8;

vec3 hue_rotate(vec3 c, float a) {
	float cs = cos(a), sn = sin(a);
	mat3 m = mat3(
		vec3(0.213 + cs * 0.787 - sn * 0.213, 0.213 - cs * 0.213 + sn * 0.143, 0.213 - cs * 0.213 - sn * 0.787),
		vec3(0.715 - cs * 0.715 - sn * 0.715, 0.715 + cs * 0.285 + sn * 0.140, 0.715 - cs * 0.715 + sn * 0.715),
		vec3(0.072 - cs * 0.072 + sn * 0.928, 0.072 - cs * 0.072 - sn * 0.283, 0.072 + cs * 0.928 + sn * 0.072));
	return m * c;
}
void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	c = hue_rotate(c, radians(hue_deg));
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, sat) * bright;
	ALBEDO = clamp(c, 0.0, 1.0);
	ROUGHNESS = 0.85;
	if (has_normal) { NORMAL_MAP = texture(normal_tex, UV).rgb; }
}

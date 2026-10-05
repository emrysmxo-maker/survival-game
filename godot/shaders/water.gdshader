// Вода (река, озёра): полупрозрачная, с бликами и мелкой рябью; у берега — светлее и прозрачнее.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
uniform vec4 deep : source_color = vec4(0.05, 0.14, 0.15, 0.9);
uniform vec4 shallow : source_color = vec4(0.18, 0.30, 0.26, 0.55);

float wave(vec2 p, float t) {
	return sin(p.x * 1.7 + t * 1.3) * 0.5 + sin(p.y * 2.3 - t * 1.1) * 0.35 + sin((p.x + p.y) * 3.1 + t * 2.0) * 0.15;
}

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wp.xz;
	float t = TIME;
	float e = 0.05;
	float h0 = wave(p, t);
	vec3 n = normalize(vec3(-(wave(p + vec2(e, 0.0), t) - h0) / e * 0.05, 1.0, -(wave(p + vec2(0.0, e), t) - h0) / e * 0.05));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	float f = 0.5 + 0.5 * sin(p.x * 0.11 + p.y * 0.07);
	vec4 c = mix(shallow, deep, 0.7 + 0.3 * f);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ROUGHNESS = 0.35;
	SPECULAR = 0.2;
}

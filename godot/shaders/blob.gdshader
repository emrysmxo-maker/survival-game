// Мягкая тень-пятно под ногами (контакт с землёй, как в изометрических играх).
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix, shadows_disabled;
uniform float strength = 0.45;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = smoothstep(1.0, 0.15, d);
	ALBEDO = vec3(0.02, 0.025, 0.02);
	ALPHA = a * a * strength;
}

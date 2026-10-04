// Эффекты (трассер пули, вспышка, дым, пыль, кровь): цвет из COLOR, без освещения.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform bool use_tex = false;
uniform bool additive = false;
void fragment() {
	vec4 c = COLOR;
	if (use_tex) { c *= texture(tex, UV); }
	else {
		float d = length(UV - vec2(0.5)) * 2.0;
		c.a *= clamp(1.0 - d, 0.0, 1.0);
	}
	ALBEDO = c.rgb;
	ALPHA = c.a;
}

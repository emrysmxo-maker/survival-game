// Силуэт бойца/зомби поверх деревьев и кустов: включается, только когда их
// закрывает крона (проверка в world.gd → occluded), рисуется поверх всего.
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_back, blend_mix, shadows_disabled;
uniform vec4 color : source_color = vec4(0.62, 0.9, 0.6, 0.5);
instance uniform float xray_on = 0.0;

void fragment() {
	if (xray_on < 0.5) { discard; }
	float rim = 1.0 - abs(dot(normalize(NORMAL), vec3(0.0, 0.0, 1.0)));
	ALBEDO = color.rgb;
	ALPHA = color.a * (0.5 + 0.5 * rim);
}

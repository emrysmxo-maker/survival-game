// «Мокрый» слой поверх любой модели (одежды): тёмный и глянцевый. Сила — instance uniform wet (0..1):
// 1 пока боец в воде, потом за ~5 секунд высыхает. Работает с любым нарядом на скелете (next_pass).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
instance uniform float wet = 0.0;
void fragment() {
	if (wet < 0.01) { discard; }
	ALBEDO = vec3(0.015, 0.03, 0.04);
	ALPHA = clamp(wet, 0.0, 1.0) * 0.42;
	ROUGHNESS = 0.12;
	SPECULAR = 0.9;
}

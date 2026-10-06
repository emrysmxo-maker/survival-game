// Вода (река, озёра). Цвет от толщины воды (по буферу глубины): у берега прозрачная,
// видно дно, вглубь — тёмная; у самой кромки — пена; рябь — две бегущие карты нормалей;
// небо отражается сильнее под косым углом (Френель).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D n1 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D n2 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep_col : source_color = vec3(0.025, 0.075, 0.085);
uniform vec3 shallow_col : source_color = vec3(0.30, 0.42, 0.36);
uniform vec3 mid_col : source_color = vec3(0.07, 0.24, 0.27);
uniform vec3 sky_col : source_color = vec3(0.62, 0.72, 0.78);

varying vec2 flow;
void vertex() {
	flow = COLOR.rg * 2.0 - 1.0;
}

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = wp.xz;
	vec2 fl = flow * TIME;                       // течение: рябь едет вдоль русла
	vec3 a = texture(n1, uv * 0.06 - fl * 0.07 + TIME * vec2(0.010, 0.006)).rgb;
	vec3 b = texture(n2, uv * 0.15 - fl * 0.16 - TIME * vec2(0.008, 0.013)).rgb;
	NORMAL_MAP = normalize((a + b) - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.5;
	// толщина воды до дна вдоль луча
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	vp.xyz /= vp.w;
	float thick = max(VERTEX.z - vp.z, 0.0);
	float k = 1.0 - exp(-thick * 0.75);          // 0 у берега … 1 на глубине
	vec3 col = mix(shallow_col, mid_col, smoothstep(0.0, 0.45, k));
	col = mix(col, deep_col, smoothstep(0.4, 1.0, k));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	col = mix(col, sky_col, clamp(fres * 0.6 + 0.08, 0.0, 1.0));
	float foam = (1.0 - smoothstep(0.0, 0.22, thick)) * (0.55 + 0.45 * sin(TIME * 1.3 + uv.x * 2.7 + uv.y * 1.9));
	float streak = length(flow) > 0.3 ? smoothstep(0.62, 0.9, texture(n2, uv * vec2(0.05, 0.22) - fl * 0.2).g) * 0.35 : 0.0;   // пенные полосы по течению
	ALBEDO = mix(col, vec3(0.82, 0.86, 0.84), clamp(foam * 0.55 + streak, 0.0, 1.0));
	ALPHA = clamp(0.12 + k * 0.82 + foam * 0.35, 0.0, 0.95) * smoothstep(0.0, 0.04, thick);
	ROUGHNESS = 0.1;
	SPECULAR = 0.5;
}

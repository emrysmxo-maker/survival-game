// Спрайты (деревья, кусты, трава, камни, ветки): плоская картинка всегда
// повёрнута к камере, стоит на точке земли. Ветер качает верх, боец раздвигает
// растения. Картинки нарисованы под угол камеры, поэтому выглядят объёмно.
// INSTANCE_CUSTOM: x — фаза, y — 1/-1 (зеркало), z — высота верха над точкой земли (м), w — 1 = лежит на земле.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert, specular_disabled, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float sway = 0.0;
uniform float push = 0.0;
uniform float light_gain = 1.0;
uniform float hole = 0.0;           // 1 — деревья: окошко в кроне над бойцом
global uniform vec3 player_pos;
global uniform float wind_on;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 to_cam = normalize(INV_VIEW_MATRIX[2].xyz);
	float vx = VERTEX.x * s * INSTANCE_CUSTOM.y;
	float vy = VERTEX.y * s;
	float top = max(INSTANCE_CUSTOM.z, 0.05);
	float hf = clamp(vy / top, 0.0, 1.0);
	vec3 wp = origin + right * vx + up * vy;
	float ph = INSTANCE_CUSTOM.x;
	float wind = (sin(TIME * 2.0 * 3.14159 * 0.32 + ph) * 0.7 + sin(TIME * 3.1 + ph * 2.3) * 0.3);
	wp += right * sway * wind_on * 0.07 * top * hf * hf * wind;
	if (push > 0.0) {
		vec3 d = origin - player_pos; d.y = 0.0;
		float dist = length(d);
		float R = 0.9;
		if (dist < R) {
			float k = (1.0 - dist / R);
			vec3 dir = dist > 0.001 ? d / dist : right;
			wp += (dir * 0.9 * top - vec3(0.0, 0.35 * top, 0.0)) * k * k * push * hf;
		}
	}
	// часть картинки ниже точки земли (и лежачие предметы целиком) сдвигаем к камере
	// — на экране то же место, но не уходит под землю
	float below = (INSTANCE_CUSTOM.w > 0.5) ? (vy + 0.02 / 0.684) : min(vy, 0.0);
	if (below < 0.0 || INSTANCE_CUSTOM.w > 0.5) {
		wp += to_cam * ((0.03 - 0.684 * below) / 0.729);
	}
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	if (hole > 0.5) {
		// окошко: крона перед бойцом (ближе к камере) прозрачна в круге вокруг него
		vec3 pv = (VIEW_MATRIX * vec4(player_pos + vec3(0.0, 0.9, 0.0), 1.0)).xyz;
		float d = length(VERTEX.xy - pv.xy);
		if (VERTEX.z > pv.z + 0.3) {
			ALPHA *= smoothstep(0.75, 1.25, d);
		}
	}
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
}

void light() {
	// без зависимости от угла: картинка уже нарисована со светом; только тень и сила солнца
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * light_gain / PI;
}

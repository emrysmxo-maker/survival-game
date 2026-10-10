// Листва, хвоя, кусты, трава: настоящая 3D-геометрия с вырезом по альфе (alpha scissor),
// ветер качает верх, боец раздвигает низкие растения. Цвет и нормали берутся из текстур модели.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_normal = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cut = 0.5;
uniform float sway = 0.5;              // сила ветра (0 — не качается)
uniform float push = 0.0;              // раздвигание бойцом (0 — не раздвигается)
uniform float height_ref = 4.0;        // высота модели, м (для ветра)
uniform float translucency = 0.2;
uniform vec3 see_pos;                  // «окно» в кронах (главное меню): листва ближе к камере, чем эта точка,
uniform float see_r = 0.0;             // в круге see_r м вокруг неё на экране растворяется точками (0 — выкл)
global uniform vec3 player_pos;
global uniform float wind_on;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = clamp((wp.y - origin.y) / max(height_ref, 0.1), 0.0, 1.0);
	float ph = origin.x * 0.55 + origin.z * 0.35;
	float w = sin(TIME * 2.0 * 3.14159 * 0.32 + ph + wp.y * 0.4) * 0.7 + sin(TIME * 3.1 + ph * 2.3 + wp.x * 0.7) * 0.3;
	vec3 off = vec3(w * 0.05 * sway * wind_on * h * h * height_ref, 0.0, w * 0.025 * sway * wind_on * h * h * height_ref);
	if (push > 0.0) {
		vec3 d = origin - player_pos; d.y = 0.0;
		float dist = length(d);
		float R = 0.9;
		if (dist < R) {
			float k = 1.0 - dist / R;
			vec3 dir = dist > 0.001 ? d / dist : vec3(1.0, 0.0, 0.0);
			off += (dir * 0.8 - vec3(0.0, 0.25, 0.0)) * k * k * push * h * height_ref * 0.5;
		}
	}
	// смещение в мировых координатах -> в локальные (модель повёрнута/масштабирована)
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * off);
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	if (c.a < alpha_cut) { discard; }
	if (see_r > 0.0) {
		vec3 dv = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz - see_pos;
		float front = dot(dv, INV_VIEW_MATRIX[2].xyz);
		float d = length(vec2(dot(dv, INV_VIEW_MATRIX[0].xyz), dot(dv, INV_VIEW_MATRIX[1].xyz)));
		float k = smoothstep(see_r, see_r * 0.55, d) * smoothstep(1.0, 3.0, front);
		vec2 q = mod(floor(FRAGCOORD.xy), 4.0);
		float bayer = (mod(q.x + q.y * 2.0, 4.0) * 4.0 + mod(q.y, 2.0) * 2.0 + mod(q.x, 2.0) + 0.5) / 16.0;
		if (k > bayer) { discard; }
	}
	ALBEDO = c.rgb * tint.rgb * COLOR.rgb;     // затенение внутри кроны (цвет вершин; без него — белый)
	ROUGHNESS = 0.9;
	if (has_normal) { NORMAL_MAP = texture(normal_tex, UV).rgb; }
	BACKLIGHT = c.rgb * translucency;
}

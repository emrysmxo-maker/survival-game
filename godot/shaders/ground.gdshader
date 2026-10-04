// Земля: 8 фототекстур (Poly Haven, CC0), смешиваются по весам.
// COLOR = (тропа, болото, дно реки, камни), UV2 = (вода, поляна); UV — тайлы мира.
// Светлая/тёмная трава и пепел считаются здесь по тем же формулам, что в браузерной версии.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D t_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_light : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_path : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_dark : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_ash : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_swamp : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_riverbed : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_rocky : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tiles_per_texture = 3.2;

float ssf(float e0, float e1, float x) { float t = clamp((x - e0) / (e1 - e0), 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }

varying vec4 w1;
varying vec2 w2;
varying vec2 tile;

void vertex() {
	w1 = COLOR;
	w2 = UV2;
	tile = UV;
}

void fragment() {
	// изометрия: повторение текстуры по осям тайлов, как раньше
	vec2 uv = tile / tiles_per_texture;
	float n = (sin(tile.x * 0.03 + tile.y * 0.017) + sin(tile.x * 0.017 - tile.y * 0.035) * 1.3 + sin(tile.x * 0.06 + tile.y * 0.045) * 0.5) / 2.8;
	float eco = sin(tile.x / 12.0 * 0.3) + cos(tile.y / 12.0 * 0.3);
	float path = w1.r, swamp = w1.g, riverbed = w1.b, rocky = w1.a;
	float water = w2.x, clearing = w2.y;
	float lightw = max(ssf(0.18, 0.46, n), clearing * 0.85);
	float darkw = ssf(-0.14, -0.42, n) * (1.0 - clearing);
	float ashw = ssf(-0.55, -1.1, eco) * (1.0 - swamp);
	vec3 c = texture(t_grass, uv).rgb;
	c = mix(c, texture(t_light, uv).rgb, lightw);
	c = mix(c, texture(t_dark, uv).rgb, darkw);
	c = mix(c, texture(t_ash, uv).rgb, ashw);
	c = mix(c, texture(t_rocky, uv).rgb, rocky);
	c = mix(c, texture(t_swamp, uv).rgb, swamp);
	c = mix(c, texture(t_path, uv).rgb, path);
	c = mix(c, texture(t_riverbed, uv).rgb, riverbed);
	// лужи на болоте
	float puddle = swamp * ssf(0.35, 0.75, sin(tile.x * 0.7 + sin(tile.y * 0.5) * 2.0) * sin(tile.y * 0.63 + 1.3 + sin(tile.x * 0.41) * 2.0)) * 0.8;
	c = mix(c, c * 0.45 + vec3(0.02, 0.04, 0.04), puddle);
	// вода
	float ripple = sin(tile.x * 2.1 + TIME * 1.3) * sin(tile.y * 1.7 - TIME * 1.1) * 0.5 + 0.5;
	vec3 wc = mix(vec3(0.10, 0.17, 0.16), vec3(0.20, 0.28, 0.27), ripple * 0.5);
	c = mix(c, wc, water * 0.85);
	ALBEDO = c;
	ROUGHNESS = mix(1.0, 0.25, max(water, puddle));
}

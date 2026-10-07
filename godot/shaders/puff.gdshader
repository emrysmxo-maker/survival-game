// Облачко (дым у дула, пыль, щепки, брызги крови): мягкий диск лицом к камере.
// Один общий материал на все облачка; цвет и прозрачность — у каждого свои (instance uniform).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
instance uniform vec4 col = vec4(1.0);
void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}
void fragment() {
	ALBEDO = col.rgb;
	ALPHA = texture(tex, UV).a * col.a;
}

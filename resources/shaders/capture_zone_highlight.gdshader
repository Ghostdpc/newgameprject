// 职责：地面拍照取景区域高亮 —— 半透明黄光渐变 + 圆角边框 + 四角括号
// 铺在地面梯形四边形上（unshaded，双面，弱强度），标识玩家站在哪会被拍到。
// 遮挡：关闭深度测试 → 场景模型不遮光圈。玩家用隐形胶囊写 stencil=1，
//        本材质只画在 stencil!=1 处 → 只有玩家会遮住光圈。
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, depth_test_disabled, blend_mix;
stencil_mode read, compare_not_equal, 1;

uniform vec4 glow_color : source_color = vec4(1.0, 0.82, 0.35, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.95, 0.62, 1.0);
uniform float overall_alpha : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float fill_strength : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform float glow_strength : hint_range(0.0, 2.0, 0.01) = 0.85;
uniform float edge_alpha : hint_range(0.0, 1.0, 0.01) = 0.95;
uniform float border_width : hint_range(0.001, 0.12, 0.001) = 0.03;
uniform float border_radius : hint_range(0.0, 0.5, 0.01) = 0.1;
uniform float bracket_width : hint_range(0.001, 0.12, 0.001) = 0.04;
uniform float bracket_arm : hint_range(0.05, 0.5, 0.01) = 0.16;
uniform float pulse_amount : hint_range(0.0, 0.5, 0.01) = 0.15;
uniform float pulse_speed : hint_range(0.0, 8.0, 0.1) = 2.0;

// 圆角矩形 SDF（p 以中心为原点）
float rounded_rect(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - half_size + vec2(radius);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
	vec2 p = UV - vec2(0.5);

	float dist = length(p) / 0.7071;
	float glow = pow(clamp(1.0 - dist, 0.0, 1.0), 2.0) * glow_strength;

	float d_outer = rounded_rect(p, vec2(0.47), border_radius);
	float border = 1.0 - smoothstep(0.0, border_width, abs(d_outer));

	float d_inner = rounded_rect(p, vec2(0.39), border_radius * 0.5);
	float inner_line = 1.0 - smoothstep(0.0, bracket_width, abs(d_inner));
	vec2 cm = step(vec2(0.5 - bracket_arm), abs(p));
	float bracket = inner_line * cm.x * cm.y;

	float edge = clamp(border + bracket, 0.0, 1.0);

	float area_a = clamp(fill_strength + glow, 0.0, 1.0) * overall_alpha;
	float a = clamp(area_a + edge * edge_alpha, 0.0, 1.0);
	a *= (1.0 - pulse_amount) + pulse_amount * (0.5 + 0.5 * sin(TIME * pulse_speed));

	vec3 col = mix(glow_color.rgb, edge_color.rgb, edge);

	ALBEDO = col;
	ALPHA = a;
}

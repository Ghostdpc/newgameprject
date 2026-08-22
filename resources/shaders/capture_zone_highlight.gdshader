// 职责：地面拍照取景区域高亮 —— 半透明黄光渐变 + 圆角边框 + 四角括号
// 铺在地面梯形四边形上（unshaded，双面，弱强度），标识玩家站在哪会被拍到。
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_mix;

uniform vec4 glow_color : source_color = vec4(1.0, 0.82, 0.35, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.95, 0.62, 1.0);
// 整体透明度上限
uniform float overall_alpha : hint_range(0.0, 1.0, 0.01) = 0.7;
// 区域内基础平铺填充（让整片地面明显着色）
uniform float fill_strength : hint_range(0.0, 1.0, 0.01) = 0.22;
// 中心光晕强度
uniform float glow_strength : hint_range(0.0, 2.0, 0.01) = 0.85;
// 边框 / 括号独立透明度（做得比填充更实，线框才明显）
uniform float edge_alpha : hint_range(0.0, 1.0, 0.01) = 0.95;
// 外边框线宽 / 圆角
uniform float border_width : hint_range(0.001, 0.12, 0.001) = 0.03;
uniform float border_radius : hint_range(0.0, 0.5, 0.01) = 0.1;
// 四角括号线宽 / 臂长
uniform float bracket_width : hint_range(0.001, 0.12, 0.001) = 0.04;
uniform float bracket_arm : hint_range(0.05, 0.5, 0.01) = 0.16;
// 呼吸脉动
uniform float pulse_amount : hint_range(0.0, 0.5, 0.01) = 0.15;
uniform float pulse_speed : hint_range(0.0, 8.0, 0.1) = 2.0;

// 圆角矩形 SDF（p 以中心为原点）
float rounded_rect(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - half_size + vec2(radius);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
	vec2 p = UV - vec2(0.5);

	// 中心径向光晕
	float dist = length(p) / 0.7071;
	float glow = pow(clamp(1.0 - dist, 0.0, 1.0), 2.0) * glow_strength;

	// 外圆角边框
	float d_outer = rounded_rect(p, vec2(0.47), border_radius);
	float border = 1.0 - smoothstep(0.0, border_width, abs(d_outer));

	// 四角括号：内圈描边仅在四角方形区域内可见 → 形成 L 形
	float d_inner = rounded_rect(p, vec2(0.39), border_radius * 0.5);
	float inner_line = 1.0 - smoothstep(0.0, bracket_width, abs(d_inner));
	vec2 cm = step(vec2(0.5 - bracket_arm), abs(p));
	float bracket = inner_line * cm.x * cm.y;

	float edge = clamp(border + bracket, 0.0, 1.0);

	// 面（填充 + 光晕）与线（边框 + 括号）分别控制透明度，线更实
	float area_a = clamp(fill_strength + glow, 0.0, 1.0) * overall_alpha;
	float a = clamp(area_a + edge * edge_alpha, 0.0, 1.0);

	// 呼吸脉动
	a *= (1.0 - pulse_amount) + pulse_amount * (0.5 + 0.5 * sin(TIME * pulse_speed));

	vec3 col = mix(glow_color.rgb, edge_color.rgb, edge);

	ALBEDO = col;
	ALPHA = a;
}

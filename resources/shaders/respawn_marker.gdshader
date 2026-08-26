shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// 复活能量柱：能量自下而上涌动，底部光源向上衰减，柱体带流动噪波
uniform vec4 col : source_color = vec4(1.0, 1.0, 0.0, 0.45);
uniform float flow_speed : hint_range(0.0, 6.0) = 1.8;
uniform float pulse : hint_range(0.0, 2.0) = 0.6;
uniform float scale_x : hint_range(0.5, 2.0) = 1.0;

varying float h;          // 0(底)~1(顶)
varying vec3 v_pos;

// 简易伪随机
float hash1(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}
// 三频 fbm 噪波，沿高度+时间，造成自下而上的流动
float flownoise(vec2 p) {
	float f = 0.0;
	f += 0.50 * sin(p.x * 3.0 + p.y);
	f += 0.25 * sin((p.x + 1.3) * 6.0 + p.y * 2.2 + 1.7);
	f += 0.15 * sin((p.x + 2.7) * 11.0 + p.y * 4.1 + 0.6);
	f += 0.10 * sin((p.x + 0.9) * 19.0 + p.y * 7.3 + 2.4);
	return f * 0.5 + 0.5;   // 近似 0~1
}

void vertex() {
	h = UV.y;
	v_pos = VERTEX;
	// 柱体沿高度的半径收敛：简单将局部 XZ 依高度微收缩，底部稍放大顶部收窄
	// （柱体高度轴在局部是 Y，视网格定向做近似）
	float taper = 1.0 - h * 0.25;
	// 边缘流动起伏：让柱边像能量在爬升
	float surge = flownoise(vec2(TIME * flow_speed, h * 4.0)) * 0.5 + 0.5;
	VERTEX.x *= taper + surge * 0.08;
	VERTEX.z *= taper + surge * 0.08;
}

void fragment() {
	// 横向边缘：中心亮、边缘淡（柔化柱体，避免硬边）
	vec3 lp = v_pos;
	float radial = clamp(1.0 - length(lp.x) * 3.0, 0.15, 1.0);
	// 高度驱动的涌动光带
	float t = TIME * flow_speed;
	float flow = flownoise(vec2(t, h * 4.0));
	// 自下而上：底部为源，带流动波纹向上，顶部渐弱
	float base = pow(1.0 - h, 1.6);
	float glow = base * 0.55 + flow * 0.45;
	// 呼吸脉冲：整体明暗伴随时间轻微起伏
	float breathe = 0.85 + 0.15 * sin(TIME * pulse * 2.0);
	// 合成
	float a = clamp(glow * radial * breathe, 0.0, 1.0);
	vec3 c = col.rgb;
	ALBEDO = c;
	ALPHA = col.a * a;
	EMISSION = c * a * 2.2;
	// 底部更亮（能量汇聚），顶部偏淡
	EMISSION += c * base * 0.6;
}

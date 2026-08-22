// 标题界面背景模糊滤镜：读取已渲染的屏幕（含 3D 场景）做 5x5 高斯模糊 + 轻微压暗
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 12.0) = 3.5;
uniform vec4 tint : source_color = vec4(0.03, 0.04, 0.07, 0.28);

void fragment() {
	vec2 ps = SCREEN_PIXEL_SIZE * blur_amount;
	float kernel[5] = float[](1.0, 4.0, 6.0, 4.0, 1.0);
	vec3 col = vec3(0.0);
	float total = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float w = kernel[x + 2] * kernel[y + 2];
			vec2 off = vec2(float(x), float(y)) * ps;
			col += texture(screen_tex, SCREEN_UV + off).rgb * w;
			total += w;
		}
	}
	col /= total;
	col = mix(col, tint.rgb, tint.a);
	COLOR = vec4(col, 1.0);
}

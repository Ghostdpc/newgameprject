shader_type canvas_item;

// 保明度染色：灰阶零件 → 玩家色（黑描边保持黑、白高光染成纯色）
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lum = dot(c.rgb, vec3(0.33333));
	COLOR = vec4(tint.rgb * lum, c.a * tint.a);
}

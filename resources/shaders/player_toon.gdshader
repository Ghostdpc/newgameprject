shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 tint_color : source_color = vec4(1.0);
uniform vec2 texture_uv_scale = vec2(1.0);
uniform vec2 texture_uv_offset = vec2(0.0);

uniform vec3 toon_light_direction = vec3(-0.45, 0.78, 0.43);
uniform float shadow_level : hint_range(0.0, 1.0, 0.01) = 0.72;
uniform float shadow_softness : hint_range(0.01, 0.5, 0.01) = 0.16;
uniform float light_wrap : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float color_saturation : hint_range(0.0, 1.5, 0.01) = 1.08;

varying vec3 world_normal;

void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 texture_uv = UV * texture_uv_scale + texture_uv_offset;
	vec3 base_color = texture(albedo_texture, texture_uv).rgb * tint_color.rgb;
	float ndotl = dot(normalize(world_normal), normalize(toon_light_direction));
	float toon_light = smoothstep(-light_wrap - shadow_softness, -light_wrap + shadow_softness, ndotl);
	toon_light = mix(shadow_level, 1.0, toon_light);

	float luminance = dot(base_color, vec3(0.2126, 0.7152, 0.0722));
	base_color = mix(vec3(luminance), base_color, color_saturation);
	ALBEDO = base_color * toon_light;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
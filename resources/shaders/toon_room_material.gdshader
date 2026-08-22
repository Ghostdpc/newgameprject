shader_type spatial;
render_mode cull_back, diffuse_toon, specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float fill_light : hint_range(0.0, 0.35, 0.01) = 0.08;
uniform float color_saturation : hint_range(0.0, 1.5, 0.01) = 1.12;

void fragment() {
    vec4 sampled_color = texture(albedo_texture, UV) * albedo_tint;
    float luminance = dot(sampled_color.rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 toon_color = mix(vec3(luminance), sampled_color.rgb, color_saturation);

    ALBEDO = toon_color;
    EMISSION = toon_color * fill_light;
    ROUGHNESS = 0.92;
    SPECULAR = 0.0;
}

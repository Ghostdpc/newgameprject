shader_type spatial;
render_mode cull_back, diffuse_toon, specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform vec4 color_replace : source_color = vec4(0.0);
uniform float color_replace_saturation_threshold : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float color_replace_softness : hint_range(0.01, 0.5, 0.01) = 0.08;
uniform float fill_light : hint_range(0.0, 0.35, 0.01) = 0.08;
uniform float color_saturation : hint_range(0.0, 1.5, 0.01) = 1.12;
uniform float color_saturation_multiplier : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform vec4 color_lift_color : source_color = vec4(1.0);
uniform float color_lift_amount : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform vec4 hue_replace_color : source_color = vec4(0.0);
uniform float hue_replace_target : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float hue_replace_tolerance : hint_range(0.01, 0.5, 0.01) = 0.1;
uniform float hue_replace_min_saturation : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float hue_replace_softness : hint_range(0.01, 0.5, 0.01) = 0.05;
uniform vec4 emission_tint : source_color = vec4(0.0);
uniform float emission_strength : hint_range(0.0, 1.0, 0.01) = 0.0;

float hue_from_rgb(vec3 color, float max_channel, float min_channel) {
    float chroma = max_channel - min_channel;
    if (chroma < 0.0001) {
        return 0.0;
    }

    float hue;
    if (max_channel == color.r) {
        hue = mod((color.g - color.b) / chroma, 6.0);
    } else if (max_channel == color.g) {
        hue = (color.b - color.r) / chroma + 2.0;
    } else {
        hue = (color.r - color.g) / chroma + 4.0;
    }
    return hue / 6.0;
}

void fragment() {
    vec4 sampled_color = texture(albedo_texture, UV) * albedo_tint;
    float max_channel = max(sampled_color.r, max(sampled_color.g, sampled_color.b));
    float min_channel = min(sampled_color.r, min(sampled_color.g, sampled_color.b));
    float saturation = max_channel - min_channel;
    float replacement_mask = smoothstep(
        color_replace_saturation_threshold - color_replace_softness,
        color_replace_saturation_threshold + color_replace_softness,
        saturation
    ) * color_replace.a;
    vec3 base_color = mix(sampled_color.rgb, color_replace.rgb, replacement_mask);
    float hue = hue_from_rgb(base_color, max_channel, min_channel);
    float hue_distance = abs(hue - hue_replace_target);
    hue_distance = min(hue_distance, 1.0 - hue_distance);
    float hue_match = 1.0 - smoothstep(
        hue_replace_tolerance,
        hue_replace_tolerance + hue_replace_softness,
        hue_distance
    );
    float hue_saturation_match = smoothstep(
        hue_replace_min_saturation,
        hue_replace_min_saturation + hue_replace_softness,
        saturation
    );
    float hue_replacement_mask = hue_match * hue_saturation_match * hue_replace_color.a;
    float base_luminance = dot(base_color, vec3(0.2126, 0.7152, 0.0722));
    vec3 hue_replaced_color = hue_replace_color.rgb * (0.78 + base_luminance * 0.9);
    base_color = mix(base_color, hue_replaced_color, hue_replacement_mask);

    vec3 lifted_color = mix(base_color, color_lift_color.rgb, color_lift_amount);
    float luminance = dot(lifted_color, vec3(0.2126, 0.7152, 0.0722));
    vec3 toon_color = mix(vec3(luminance), lifted_color, color_saturation * color_saturation_multiplier);

    ALBEDO = toon_color;
    EMISSION = toon_color * fill_light + emission_tint.rgb * emission_strength * hue_replacement_mask;
    ROUGHNESS = 0.92;
    SPECULAR = 0.0;
}

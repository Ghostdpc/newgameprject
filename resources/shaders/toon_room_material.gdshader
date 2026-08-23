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
uniform bool procedural_wood_floor = false;
uniform vec4 wood_base_color : source_color = vec4(0.34, 0.12, 0.035, 1.0);
uniform vec4 wood_light_color : source_color = vec4(0.55, 0.25, 0.085, 1.0);
uniform vec4 wood_seam_color : source_color = vec4(0.075, 0.018, 0.006, 1.0);
uniform float wood_plank_width : hint_range(0.15, 1.0, 0.01) = 0.38;
uniform float wood_plank_length : hint_range(0.4, 3.0, 0.01) = 1.28;
uniform float wood_seam_width : hint_range(0.002, 0.08, 0.001) = 0.018;

varying vec3 world_position;

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

float hash12(vec2 point) {
    return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453123);
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec4 sampled_color = texture(albedo_texture, UV) * albedo_tint;
    if (procedural_wood_floor) {
        float plank_row = floor(world_position.x / wood_plank_width);
        float row_offset = (fract(plank_row * 0.5) * 0.5 + hash12(vec2(plank_row, 7.0)) * 0.12) * wood_plank_length;
        float plank_column = floor((world_position.z + row_offset) / wood_plank_length);
        vec2 plank_id = vec2(plank_row, plank_column);
        float board_variation = hash12(plank_id);
        float board_width_position = fract(world_position.x / wood_plank_width);
        float board_length_position = fract((world_position.z + row_offset) / wood_plank_length);
        float distance_to_seam = min(
            min(board_width_position, 1.0 - board_width_position) * wood_plank_width,
            min(board_length_position, 1.0 - board_length_position) * wood_plank_length
        );
        float seam = 1.0 - smoothstep(wood_seam_width, wood_seam_width * 2.2, distance_to_seam);
        float grain_wave = sin(world_position.z * 25.0 + sin(world_position.z * 4.8 + board_variation * 19.0) * 2.4);
        float grain_noise = sin(world_position.z * 78.0 + board_variation * 31.0) * 0.045;
        float grain = clamp(0.47 + grain_wave * 0.12 + grain_noise + (board_variation - 0.5) * 0.18, 0.0, 1.0);
        vec3 wood_color = mix(wood_base_color.rgb, wood_light_color.rgb, grain);
        sampled_color = vec4(wood_color, 1.0);
    }
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

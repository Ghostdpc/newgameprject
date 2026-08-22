shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec4 outline_color : source_color = vec4(0.045, 0.022, 0.065, 1.0);
uniform float outline_opacity : hint_range(0.0, 1.0, 0.01) = 0.68;
uniform float outline_size : hint_range(0.5, 3.0, 0.1) = 1.2;
uniform float edge_threshold : hint_range(0.01, 0.5, 0.01) = 0.12;
uniform float edge_softness : hint_range(0.001, 0.5, 0.001) = 0.08;

float luminance_at(vec2 uv) {
    vec3 color = texture(screen_texture, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
    vec3 scene_color = texture(screen_texture, SCREEN_UV).rgb;
    vec2 offset = SCREEN_PIXEL_SIZE * outline_size;
    float center = dot(scene_color, vec3(0.2126, 0.7152, 0.0722));
    float edge = 0.0;
    edge = max(edge, abs(center - luminance_at(SCREEN_UV + vec2(offset.x, 0.0))));
    edge = max(edge, abs(center - luminance_at(SCREEN_UV - vec2(offset.x, 0.0))));
    edge = max(edge, abs(center - luminance_at(SCREEN_UV + vec2(0.0, offset.y))));
    edge = max(edge, abs(center - luminance_at(SCREEN_UV - vec2(0.0, offset.y))));

    float outline_mask = smoothstep(edge_threshold, edge_threshold + edge_softness, edge) * outline_opacity;
    COLOR = vec4(mix(scene_color, outline_color.rgb, outline_mask), 1.0);
}

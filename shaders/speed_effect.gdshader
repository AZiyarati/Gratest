shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

uniform float intensity : hint_range(0.0, 1.5) = 0.0;
uniform vec4 effect_color : source_color = vec4(1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.35;
uniform float zoom_amount : hint_range(0.0, 0.2) = 0.05;
uniform float edge_start : hint_range(0.0, 1.0) = 0.4;
uniform float edge_end : hint_range(0.0, 1.0) = 1.0;
uniform float contrast_boost : hint_range(0.0, 2.0) = 0.2;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.1;
uniform float flicker_speed : hint_range(0.0, 30.0) = 10.0;
uniform float TIME_OFFSET = 0.0;

void fragment() {
    // Recenter UV around 0.5 so radial math is symmetric.
    vec2 centered = UV - vec2(0.5);
    vec2 uv = centered;

    // Radial zoom: pull the sampled UV toward the center as intensity rises.
    uv = mix(uv, uv * (1.0 - zoom_amount * intensity), intensity);
    vec2 sample_uv = uv + vec2(0.5);

    vec4 color = texture(SCREEN_TEXTURE, sample_uv);

    // Vignette.
    float d = length(centered);
    float edge = smoothstep(edge_start, edge_end, d);

    // Contrast boost at the edge.
    float contrast = mix(1.0, 1.0 + contrast_boost, edge);
    vec3 centered_rgb = color.rgb - vec3(0.5);
    color.rgb = centered_rgb * contrast + vec3(0.5);

    // Tint.
    color.rgb = mix(color.rgb, effect_color.rgb, tint_strength * edge);

    // Flicker.
    float f = 1.0 + sin((TIME + TIME_OFFSET) * flicker_speed) * flicker_amount * 0.5;
    color.rgb *= mix(1.0, f, edge);

    // Alpha fade so the whole overlay fades cleanly.
    color.a = intensity;

    COLOR = color;
}
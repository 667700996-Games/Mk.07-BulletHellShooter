shader_type canvas_item;

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.28;
uniform float scanline_strength : hint_range(0.0, 0.2) = 0.035;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec2 centered = UV * 2.0 - 1.0;
	float vignette = 1.0 - dot(centered, centered) * vignette_strength;
	float scan = 1.0 - scanline_strength * (0.5 + 0.5 * sin(UV.y / TEXTURE_PIXEL_SIZE.y * 3.14159));
	COLOR = vec4(source.rgb * max(vignette, 0.55) * scan, source.a);
}

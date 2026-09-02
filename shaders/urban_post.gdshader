shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float chromatic_amount : hint_range(0.0, 0.01) = 0.00055;
uniform float vignette_strength : hint_range(0.0, 0.5) = 0.17;
uniform float scanline_strength : hint_range(0.0, 0.08) = 0.018;
uniform float danger_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered = SCREEN_UV * 2.0 - 1.0;
	float edge = dot(centered, centered);
	vec2 direction = normalize(centered + vec2(0.0001));
	vec2 shift = direction * chromatic_amount * (0.35 + edge);
	float red = texture(screen_texture, SCREEN_UV + shift).r;
	float green = texture(screen_texture, SCREEN_UV).g;
	float blue = texture(screen_texture, SCREEN_UV - shift).b;
	float alpha = texture(screen_texture, SCREEN_UV).a;
	float vignette = clamp(1.0 - edge * vignette_strength, 0.70, 1.0);
	float scanline = 1.0 - scanline_strength * (0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159265));
	vec3 graded = vec3(red, green, blue);
	graded *= mix(vec3(1.0), vec3(1.08, 0.94, 0.98), danger_amount);
	graded += vec3(0.022, -0.006, 0.008) * danger_amount * (0.5 + 0.5 * sin(TIME * 2.2));
	COLOR = vec4(graded * vignette * scanline, alpha);
}

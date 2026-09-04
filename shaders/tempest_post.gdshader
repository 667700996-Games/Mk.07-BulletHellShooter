shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float chromatic_amount : hint_range(0.0, 0.01) = 0.00055;
uniform float danger_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv * 2.0 - 1.0;
	float edge = smoothstep(0.18, 1.25, dot(centered, centered));
	float safe_danger = clamp(danger_amount, 0.0, 1.0);

	// Storm refraction is confined mostly to the periphery so the dense central
	// bullet field remains geometrically stable and readable.
	float wave_a = sin(uv.y * 31.0 + TIME * 0.42);
	float wave_b = sin(uv.y * 73.0 - TIME * 0.23 + uv.x * 9.0);
	float shear = (wave_a * 0.58 + wave_b * 0.42) * (0.00020 + safe_danger * 0.00016) * edge;
	vec2 refracted_uv = clamp(uv + vec2(shear, 0.0), vec2(0.002), vec2(0.998));

	// Clamp externally requested separation: hit flashes still have impact, but
	// never split high-contrast bullets enough to resemble multiple projectiles.
	float safe_chromatic = min(chromatic_amount, 0.00175) * (0.30 + edge * 0.70);
	vec2 split = vec2(safe_chromatic, safe_chromatic * -0.30);
	float red = texture(screen_texture, clamp(refracted_uv + split, vec2(0.002), vec2(0.998))).r;
	float green = texture(screen_texture, refracted_uv).g;
	float blue = texture(screen_texture, clamp(refracted_uv - split, vec2(0.002), vec2(0.998))).b;
	float alpha = texture(screen_texture, refracted_uv).a;
	vec3 color = vec3(red, green, blue);

	// Violet/cyan atmospheric grade with a luminance-preserving mix. Danger
	// strengthens edge color instead of producing full-screen brightness pulses.
	float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
	vec3 storm_tint = mix(vec3(luminance) * vec3(0.82, 1.02, 1.10), color, 0.86);
	vec3 danger_tint = storm_tint * vec3(1.045, 0.94, 1.075);
	color = mix(storm_tint, danger_tint, safe_danger * (0.35 + edge * 0.35));

	float peripheral_haze = edge * (0.035 + safe_danger * 0.022);
	color += vec3(0.10, 0.22, 0.31) * peripheral_haze;
	float soft_vignette = 1.0 - edge * 0.105;
	COLOR = vec4(color * soft_vignette, alpha);
}

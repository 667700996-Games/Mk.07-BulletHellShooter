shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float chromatic_amount : hint_range(0.0, 0.01) = 0.00045;
uniform float danger_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv * 2.0 - 1.0;
	float edge = smoothstep(0.20, 1.22, dot(centered, centered));
	float safe_danger = clamp(danger_amount, 0.0, 1.0);

	// Heat refraction stays at the perimeter so central projectile geometry does
	// not wobble or appear to split during dense patterns.
	float heat = sin(uv.y * 54.0 + TIME * 0.56 + sin(uv.x * 11.0))
		* (0.00012 + safe_danger * 0.00012) * edge;
	vec2 warped_uv = clamp(uv + vec2(heat, heat * -0.22), vec2(0.002), vec2(0.998));
	float split_amount = min(chromatic_amount, 0.0014) * (0.18 + edge * 0.82);
	vec2 split = vec2(split_amount, 0.0);
	float red = texture(screen_texture, clamp(warped_uv + split, vec2(0.002), vec2(0.998))).r;
	float green = texture(screen_texture, warped_uv).g;
	float blue = texture(screen_texture, clamp(warped_uv - split, vec2(0.002), vec2(0.998))).b;
	float alpha = texture(screen_texture, warped_uv).a;
	vec3 color = vec3(red, green, blue);

	float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
	vec3 forge_grade = mix(vec3(luminance) * vec3(1.08, 0.96, 0.82), color, 0.89);
	vec3 danger_grade = forge_grade * vec3(1.07, 0.94, 0.88);
	color = mix(forge_grade, danger_grade, safe_danger * (0.28 + edge * 0.40));
	color += vec3(0.26, 0.095, 0.018) * edge * (0.018 + safe_danger * 0.018);
	color *= 1.0 - edge * 0.10;
	COLOR = vec4(color, alpha);
}

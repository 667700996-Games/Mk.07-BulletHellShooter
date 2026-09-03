shader_type canvas_item;
render_mode unshaded;

uniform float contrast_boost : hint_range(0.0, 1.0) = 0.8;

void fragment() {
	vec2 point = (UV - vec2(0.5)) * 2.0;
	float distance_to_center = length(point);
	vec4 tint = COLOR;
	float glow = smoothstep(1.0, 0.42, distance_to_center) * 0.28;
	float body = smoothstep(0.80, 0.68, distance_to_center);
	float inner = smoothstep(0.57, 0.46, distance_to_center);
	float core = smoothstep(0.29, 0.03, distance_to_center);
	float outline = smoothstep(0.98, 0.78, distance_to_center) - smoothstep(0.76, 0.64, distance_to_center);
	vec3 dark_rim = mix(vec3(0.06, 0.015, 0.12), vec3(0.002, 0.003, 0.01), contrast_boost);
	vec3 final_color = mix(dark_rim, tint.rgb, inner);
	final_color = mix(final_color, vec3(1.0), core * mix(0.78, 1.0, contrast_boost));
	final_color = mix(final_color, dark_rim, outline * contrast_boost);
	float alpha = max(max(glow, body), outline * mix(0.4, 0.9, contrast_boost)) * tint.a;
	COLOR = vec4(final_color, alpha);
}

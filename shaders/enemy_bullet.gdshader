shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec2 point = (UV - vec2(0.5)) * 2.0;
	float distance_to_center = length(point);
	vec4 tint = COLOR;
	float glow = smoothstep(1.0, 0.42, distance_to_center) * 0.28;
	float body = smoothstep(0.80, 0.68, distance_to_center);
	float inner = smoothstep(0.57, 0.46, distance_to_center);
	float core = smoothstep(0.29, 0.03, distance_to_center);
	vec3 dark_rim = vec3(0.06, 0.015, 0.12);
	vec3 final_color = mix(dark_rim, tint.rgb, inner);
	final_color = mix(final_color, vec3(1.0), core * 0.92);
	float alpha = max(glow, body) * tint.a;
	COLOR = vec4(final_color, alpha);
}

shader_type spatial;
render_mode cull_disabled;

// Imperial ceremonial banner: deep red cloth with dark trim bands, swaying
// gently as if brushed by the ventilation.
uniform vec4 cloth_color : source_color = vec4(0.45, 0.05, 0.04, 1.0);
uniform vec4 trim_color : source_color = vec4(0.06, 0.06, 0.07, 1.0);

void vertex() {
	// hang from the top edge (UV.y = 0): sway grows toward the bottom
	float hang = UV.y;
	VERTEX.z += sin(TIME * 0.9 + VERTEX.y * 1.6) * 0.10 * hang;
	VERTEX.x += sin(TIME * 0.6 + 1.7 + VERTEX.y * 1.1) * 0.05 * hang;
}

void fragment() {
	float trim = step(0.92, UV.x) + step(UV.x, 0.08) + step(0.94, UV.y);
	vec3 col = mix(cloth_color.rgb, trim_color.rgb, clamp(trim, 0.0, 1.0));
	// woven cloth shading
	float weave = 0.94 + 0.06 * sin(UV.y * 300.0) * sin(UV.x * 200.0);
	ALBEDO = col * weave;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
}

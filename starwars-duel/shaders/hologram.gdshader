shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Flickering blue hologram: scanlines crawling upward, fresnel edge glow,
// occasional horizontal glitch. Applied as an override on any mesh.
uniform vec4 holo_color : source_color = vec4(0.35, 0.7, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 8.0) = 2.6;
uniform float scan_density : hint_range(20.0, 400.0) = 140.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// subtle horizontal glitch jitter, quantized in time
	float step_t = floor(TIME * 11.0);
	float glitch = fract(sin(step_t * 12.9898) * 43758.5453);
	if (glitch > 0.93) {
		VERTEX.x += (glitch - 0.93) * 1.5 * sin(world_pos.y * 40.0 + TIME * 60.0);
	}
}

void fragment() {
	float scan = 0.62 + 0.38 * sin(world_pos.y * scan_density - TIME * 9.0);
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.4);
	float flicker = 0.85 + 0.15 * sin(TIME * 37.0) * sin(TIME * 8.3);
	float a = (0.22 + fres * 0.9) * scan * flicker;
	ALBEDO = vec3(0.0);
	EMISSION = holo_color.rgb * intensity * a;
	ALPHA = a * holo_color.a;
}

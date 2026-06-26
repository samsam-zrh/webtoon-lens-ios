shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Additive energy halo wrapped around a saber blade mesh: the mesh is
// duplicated, inflated along its normals and faded by fresnel so the core
// stays white-hot while the rim bleeds the saber color.
uniform vec4 glow_color : source_color = vec4(1.0, 0.1, 0.05, 1.0);
uniform float grow : hint_range(0.0, 0.2) = 0.035;
uniform float intensity : hint_range(0.0, 12.0) = 5.0;
uniform float rim_power : hint_range(0.1, 6.0) = 1.6;

void vertex() {
	VERTEX += NORMAL * grow;
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(facing, rim_power);
	// flicker of a live plasma blade
	float flicker = 0.92 + 0.08 * sin(TIME * 47.0) * sin(TIME * 13.7);
	ALBEDO = vec3(0.0);
	EMISSION = glow_color.rgb * intensity * rim * flicker;
	ALPHA = rim * glow_color.a;
}

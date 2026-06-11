shader_type canvas_item;

// Cinematic post pass over the 3D viewport: subtle chromatic aberration
// toward the edges, animated film grain, gentle edge softening. Sits on a
// fullscreen ColorRect below the HUD.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float aberration : hint_range(0.0, 0.01) = 0.0028;
uniform float grain_amount : hint_range(0.0, 0.2) = 0.045;
uniform float shake : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - vec2(0.5);
	float dist = dot(dir, dir);
	// aberration grows toward the screen edges, and with camera shake
	float ab = aberration * (0.4 + 2.2 * dist) * (1.0 + shake * 6.0);
	float r = texture(screen_tex, uv + dir * ab).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - dir * ab).b;
	vec3 col = vec3(r, g, b);
	// animated film grain, weighted into the shadows
	float n = hash(uv * vec2(1920.0, 1080.0) + vec2(fract(TIME * 13.7) * 91.0));
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col += (n - 0.5) * grain_amount * (1.0 - lum * 0.7);
	COLOR = vec4(col, 1.0);
}

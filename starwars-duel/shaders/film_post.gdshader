shader_type canvas_item;

// Cinematic post pass over the 3D viewport: subtle chromatic aberration
// toward the edges, animated film grain, gentle edge softening. Sits on a
// fullscreen ColorRect below the HUD.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float aberration : hint_range(0.0, 0.01) = 0.0028;
uniform float grain_amount : hint_range(0.0, 0.2) = 0.045;
uniform float shake : hint_range(0.0, 1.0) = 0.0;

// --- Unifying colour grade --------------------------------------------------
// A single master grade applied over every arena so they share one filmic
// look regardless of their individual lighting. grade_strength dials the whole
// thing 0->1. Shadows lift slightly toward teal, highlights warm toward amber,
// a gentle S-curve adds contrast, and a soft vignette frames the duel.
uniform float grade_strength : hint_range(0.0, 1.0) = 0.7;
uniform vec3 shadow_tint = vec3(0.86, 1.00, 1.06);
uniform vec3 highlight_tint = vec3(1.05, 1.00, 0.93);
uniform float contrast : hint_range(0.5, 1.5) = 1.06;
uniform float saturation : hint_range(0.0, 2.0) = 0.97;
uniform float lift : hint_range(0.0, 0.1) = 0.012;
uniform float vignette : hint_range(0.0, 1.0) = 0.24;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// split-tone: blend shadow tint and highlight tint by luminance
vec3 split_tone(vec3 c, float lum) {
	vec3 t = mix(shadow_tint, highlight_tint, smoothstep(0.0, 0.9, lum));
	return c * t;
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

	// --- colour grade -------------------------------------------------------
	vec3 graded = col;
	float lum0 = dot(graded, vec3(0.299, 0.587, 0.114));
	// lift the blacks a touch so shadows read as deep navy, not crushed
	graded += lift * (1.0 - lum0);
	// split-tone shadows/highlights
	graded = split_tone(graded, lum0);
	// gentle contrast S-curve around mid grey
	graded = (graded - 0.5) * contrast + 0.5;
	// pull saturation in slightly for a unified, filmic palette
	float lumg = dot(graded, vec3(0.299, 0.587, 0.114));
	graded = mix(vec3(lumg), graded, saturation);
	col = clamp(mix(col, graded, grade_strength), 0.0, 1.0);

	// soft vignette to frame the action
	float vig = 1.0 - vignette * smoothstep(0.15, 0.75, dist);
	col *= vig;

	// animated film grain, weighted into the shadows
	float n = hash(uv * vec2(1920.0, 1080.0) + vec2(fract(TIME * 13.7) * 91.0));
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col += (n - 0.5) * grain_amount * (1.0 - lum * 0.7);
	COLOR = vec4(col, 1.0);
}

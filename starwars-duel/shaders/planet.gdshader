shader_type spatial;
render_mode unshaded, cull_back;

// Stylized gas-giant planet with banding and atmospheric fresnel rim.

uniform vec3 base_color : source_color = vec3(0.85, 0.55, 0.30);
uniform vec3 band_color : source_color = vec3(0.55, 0.30, 0.18);
uniform vec3 rim_color : source_color = vec3(0.9, 0.7, 0.5);
uniform vec3 sun_dir = vec3(0.5, 0.3, 0.5);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

varying vec3 v_normal_model;

void vertex() {
	v_normal_model = NORMAL;
}

void fragment() {
	vec3 n = normalize(v_normal_model);
	// Latitude bands distorted by noise
	float lat = n.y * 6.0;
	float wob = noise2(vec2(n.x * 4.0 + TIME * 0.01, n.y * 8.0)) * 1.5;
	float bands = 0.5 + 0.5 * sin(lat * 3.0 + wob * 2.0);
	vec3 col = mix(base_color, band_color, bands);
	col *= 0.85 + 0.3 * noise2(n.xz * 10.0);

	// Day/night terminator
	vec3 world_n = normalize((MODEL_NORMAL_MATRIX * n));
	float light = clamp(dot(world_n, normalize(sun_dir)), 0.0, 1.0);
	col *= 0.12 + 0.95 * light;

	// Atmosphere rim
	float fres = pow(1.0 - clamp(dot(normalize(-VERTEX), NORMAL), 0.0, 1.0), 2.5);
	col += rim_color * fres * (0.25 + 0.75 * light);

	ALBEDO = col;
}

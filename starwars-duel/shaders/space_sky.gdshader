shader_type sky;

// Procedural deep-space sky: star field + soft nebula + galactic band.

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise3(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

float star_layer(vec3 dir, float scale, float threshold, float tw) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	float h = hash13(cell);
	if (h < threshold) {
		return 0.0;
	}
	vec3 center = cell + 0.5 + 0.35 * (vec3(hash13(cell + 1.7), hash13(cell + 4.2), hash13(cell + 9.1)) - 0.5);
	float d = length(p - center);
	float bright = smoothstep(0.45, 0.0, d);
	float twinkle = 0.8 + 0.2 * hash13(cell + 2.3) * tw;
	return bright * bright * twinkle;
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 col = vec3(0.004, 0.005, 0.012);

	// Nebula clouds (purple/blue, with a hint of orange near the band)
	float band = exp(-3.0 * abs(dir.y + 0.15 * sin(dir.x * 2.0)));
	float neb1 = fbm(dir * 3.0 + vec3(7.0));
	float neb2 = fbm(dir * 6.0 - vec3(3.0));
	vec3 nebcol = vec3(0.10, 0.05, 0.22) * pow(neb1, 2.2) * 1.6;
	nebcol += vec3(0.18, 0.07, 0.05) * pow(neb2, 3.0) * band * 1.4;
	nebcol += vec3(0.05, 0.08, 0.16) * pow(fbm(dir * 2.0 + vec3(21.0)), 2.5);
	col += nebcol;

	// Milky-way style bright band
	col += vec3(0.05, 0.05, 0.09) * band * (0.4 + 0.6 * neb1);

	// Stars: three layers of different densities/sizes
	float s = 0.0;
	s += star_layer(dir, 90.0, 0.92, 1.0) * 0.9;
	s += star_layer(dir, 160.0, 0.90, 1.0) * 0.6;
	s += star_layer(dir, 300.0, 0.88, 0.5) * 0.35;
	// Slight color variation in stars
	vec3 starcol = mix(vec3(1.0, 0.95, 0.85), vec3(0.8, 0.9, 1.0), hash13(floor(dir * 90.0)));
	col += starcol * s;

	COLOR = col;
}

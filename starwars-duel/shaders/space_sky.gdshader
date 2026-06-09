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
	// Deep space base: near-black with a cold blue cast
	vec3 col = vec3(0.002, 0.003, 0.008);

	// Restrained nebula: deep indigo with a faint magenta vein along the band
	float band = exp(-2.6 * abs(dir.y + 0.18 * sin(dir.x * 1.7)));
	float neb1 = fbm(dir * 2.6 + vec3(7.0));
	float neb2 = fbm(dir * 5.5 - vec3(3.0));
	float neb3 = fbm(dir * 1.7 + vec3(21.0));
	vec3 nebcol = vec3(0.05, 0.042, 0.14) * pow(neb1, 2.4) * 1.6;
	nebcol += vec3(0.14, 0.04, 0.10) * pow(neb2, 3.4) * band * 1.3;
	nebcol += vec3(0.022, 0.05, 0.10) * pow(neb3, 2.8);
	col += nebcol;

	// Faint galactic band glow
	col += vec3(0.018, 0.020, 0.038) * band * (0.35 + 0.65 * neb1);

	// Stars: dense fine dust + a few brighter ones
	float s = 0.0;
	s += star_layer(dir, 80.0, 0.955, 1.0) * 1.1;
	s += star_layer(dir, 150.0, 0.93, 1.0) * 0.55;
	s += star_layer(dir, 280.0, 0.86, 0.5) * 0.28;
	s += star_layer(dir, 480.0, 0.82, 0.3) * 0.16;
	vec3 starcol = mix(vec3(1.0, 0.96, 0.88), vec3(0.78, 0.87, 1.0), hash13(floor(dir * 80.0)));
	col += starcol * s;

	COLOR = col;
}

uniform vec4 wind_trail = vec4(0.16);

float earth_patch(vec2 p) {
	vec2 tile = floor(p);
	vec2 weight = fract(p);
	weight = weight * weight * (3.0 - 2.0 * weight);
	vec4 keys = dot(tile, vec2(127.1, 311.7)) + vec4(0.0, 127.1, 311.7, 438.8);
	vec4 values = fract(sin(keys) * 43758.5453);
	return mix(mix(values.x, values.y, weight.x), mix(values.z, values.w, weight.x), weight.y);
}

// Gust strength at a horizontal position; gusts reach the right edge later than the left.
float wind_at(float x) {
	float s = clamp(x, 0.0, 1.0) * 3.0;
	float a = s < 1.0 ? wind_trail.x : (s < 2.0 ? wind_trail.y : wind_trail.z);
	float b = s < 1.0 ? wind_trail.y : (s < 2.0 ? wind_trail.z : wind_trail.w);
	return mix(a, b, fract(min(s, 2.999)));
}

// Trees just outside the frame: a large crown over the upper left, a smaller one at the lower right.
float canopy_cover(vec2 p) {
	float upper = 1.0 - smoothstep(0.55, 1.0, length((p - vec2(0.06, -0.10)) / vec2(0.50, 0.44)));
	float corner = 1.0 - smoothstep(0.55, 1.0, length((p - vec2(1.02, 1.10)) / vec2(0.30, 0.30)));
	return max(upper, corner * 0.85);
}

vec3 afternoon_light(vec3 color, vec2 p, float wet) {
	float sun = smoothstep(0.18, 0.77, p.x + (1.0 - p.y) * 0.34);
	float luma = dot(color, vec3(0.24, 0.63, 0.13));
	vec3 warm = color * vec3(1.018, 1.00, 0.974) + vec3(0.012, 0.007, 0.0) * luma;
	vec3 cool = color * vec3(0.94, 0.975, 1.025);
	vec3 result = mix(cool, warm, sun);
	return mix(result, color, wet * 0.42);
}

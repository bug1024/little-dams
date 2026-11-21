uniform vec4 wind_trail = vec4(0.16);
uniform vec3 sun_drift = vec3(0.0, 0.0, 0.48);

float earth_patch(vec2 p) {
	vec2 tile = floor(p);
	vec2 weight = fract(p);
	weight = weight * weight * (3.0 - 2.0 * weight);
	vec4 keys = dot(tile, vec2(127.1, 311.7)) + vec4(0.0, 127.1, 311.7, 438.8);
	vec4 values = fract(sin(keys) * 43758.5453);
	return mix(mix(values.x, values.y, weight.x), mix(values.z, values.w, weight.x), weight.y);
}

// Gust strength at a horizontal position; gusts reach the right edge later than the left.
float downwind_sample(vec4 samples, float x) {
	float s = clamp(x, 0.0, 1.0) * 3.0;
	float a = s < 1.0 ? samples.x : (s < 2.0 ? samples.y : samples.z);
	float b = s < 1.0 ? samples.y : (s < 2.0 ? samples.z : samples.w);
	return mix(a, b, s - min(floor(s), 2.0));
}

float wind_at(float x) {
	return downwind_sample(wind_trail, x);
}

float sunlight_at(vec2 p) {
	vec2 gap = p - sun_drift.xy;
	float upper = 1.0 - smoothstep(0.37, 1.0, length((gap - vec2(0.71, 0.20)) / vec2(0.45, 0.32)));
	float lower = 1.0 - smoothstep(0.31, 1.0, length((gap - vec2(0.59, 0.82)) / vec2(0.46, 0.32)));
	return max(upper, lower * 0.81) * (0.62 + sun_drift.z * 0.38);
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

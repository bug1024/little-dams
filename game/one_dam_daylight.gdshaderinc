float leaf_shade(vec2 p, float time) {
	vec2 wind = vec2(sin(time * 0.36), cos(time * 0.27)) * vec2(0.008, 0.006);
	vec2 q = p + wind;
	float a = sin(q.x * 64.0 + q.y * 31.0);
	float b = sin(q.x * 37.0 - q.y * 53.0 + sin(q.y * 21.0));
	float c = sin(q.y * 64.0 + q.x * 112.0 + 0.48 * sin(time * 0.79));
	float canopy = 1.0 - smoothstep(0.15, 0.51, abs(p.x - (p.y * 0.53 + 0.16)));
	return smoothstep(0.36, 0.91, a * 0.43 + b * 0.39 + c * 0.18) * canopy;
}

vec3 afternoon_light(vec3 color, vec2 p, float time, float wet) {
	float sun = smoothstep(0.18, 0.77, p.x + (1.0 - p.y) * 0.34);
	float shade = leaf_shade(p, time);
	float luma = dot(color, vec3(0.24, 0.63, 0.13));
	vec3 warm = color * vec3(1.13, 1.055, 0.90) + vec3(0.022, 0.010, 0.0) * luma;
	vec3 cool = color * vec3(0.88, 0.95, 1.05);
	vec3 result = mix(cool, warm, sun * (1.0 - shade * 0.64));
	return mix(result, color, wet * 0.42);
}

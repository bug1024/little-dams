shader_type canvas_item;
render_mode unshaded;

#include "res://game/one_dam_daylight.gdshaderinc"

uniform sampler2D channel_mask : filter_nearest, repeat_disable;
uniform sampler2D channel_profile : filter_linear, repeat_disable;
uniform sampler2D flow_state : filter_linear, repeat_disable;
uniform float creek_time;
uniform sampler2D shore_memory : filter_linear, repeat_disable;

void fragment() {
	vec3 plate = texture(TEXTURE, UV).rgb;
	vec3 channel = texture(channel_mask, UV).rgb;
	vec2 pixel = floor(UV / TEXTURE_PIXEL_SIZE);
	vec2 art_uv = (pixel + 0.5) * TEXTURE_PIXEL_SIZE;
	vec2 profile = texture(channel_profile, vec2(art_uv.x, 0.5)).rg;
	float row = (art_uv.y - profile.x) / max(0.01, 2.0 * profile.y) + 0.5;
	vec4 state = texture(flow_state, vec2(art_uv.x, clamp(row, 0.0, 1.0)));
	vec2 v = (state.gb - vec2(0.5)) * 2.0;
	float depth = state.r * 1.5;

	float stone = clamp(dot(plate, vec3(0.52, 0.36, 0.12)) * 1.47, 0.04, 1.0);
	float pebble = clamp(stone * 0.67 + channel.b * 0.60 - 0.16, 0.04, 1.0);
	vec3 gravel = mix(vec3(0.20, 0.23, 0.23), vec3(0.75, 0.61, 0.47), pebble);
	gravel += (plate.r - plate.b) * vec3(0.14, 0.09, 0.0);
	float wet_trace = texture(shore_memory, vec2(art_uv.x, clamp(row, 0.0, 1.0))).r;
	float damp = max(smoothstep(0.008, 0.050, depth), wet_trace * 0.86);
	gravel = mix(gravel, gravel * vec3(0.55, 0.68, 0.73), damp);

	float deep = smoothstep(0.16, 1.06, depth);
	vec3 water = mix(plate, plate * vec3(0.47, 0.69, 1.08), deep * 0.76);
	vec3 muddy = mix(vec3(0.17, 0.21, 0.19), vec3(0.66, 0.56, 0.36), stone);
	water = mix(water, muddy, state.a * 0.70);

	float sun = (1.0 - leaf_shade(art_uv, creek_time)) * smoothstep(0.35, 0.9, art_uv.x + art_uv.y * 0.52);
	float glint = step(0.93, sin(pixel.x * 0.123 - creek_time * 1.6 + sin(pixel.y * 0.29))) * sun;
	water = mix(water, vec3(0.76, 0.91, 0.77), glint * (1.0 - deep * 0.76) * 0.16);

	vec2 motion = pixel - v * creek_time * 31.0;
	float bend = sin(motion.y * 0.16) * 1.79 + sin(motion.x * 0.027 + motion.y * 0.061);
	float ripple = step(0.959, sin(motion.x * 0.105 + bend));
	ripple *= step(0.61, cos(motion.y * 0.38 + motion.x * 0.064));
	water = mix(water, vec3(0.51, 0.90, 0.88), ripple * (0.08 + length(v) * 0.25));
	float edge = 0.068 + sin(pixel.x * 0.063 + creek_time * 1.2) * 0.005;
	float meniscus = 1.0 - smoothstep(0.0, 0.025, abs(depth - edge));
	water = mix(water, vec3(0.53, 0.81, 0.72), meniscus * 0.36);

	float cover = smoothstep(0.032, 0.074, depth);
	COLOR = vec4(afternoon_light(mix(gravel, water, cover), art_uv, creek_time, cover), channel.r);
}

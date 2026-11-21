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
	float speed = length(v);
	vec4 shore = texture(shore_memory, vec2(art_uv.x, clamp(row, 0.0, 1.0)));
	float bank = 1.0 - smoothstep(0.04, 0.38, channel.g);
	float patches = earth_patch(pixel / vec2(27.0, 14.0));
	float veins = earth_patch(vec2(pixel.x * 0.058 + pixel.y * 0.035, pixel.y * 0.22));
	float slow = 1.0 - smoothstep(0.055, 0.27, speed);
	float silt = clamp(shore.a * 0.95 + bank * slow * smoothstep(0.36, 0.77, patches * 0.68 + veins * 0.44) * 0.55, 0.0, 1.0);

	float stone = clamp(dot(plate, vec3(0.52, 0.36, 0.12)) * 1.47, 0.04, 1.0);
	float pebble = clamp(stone * 0.67 + channel.b * 0.60 - 0.16, 0.04, 1.0);
	vec3 gravel = mix(vec3(0.22, 0.24, 0.21), vec3(0.73, 0.62, 0.48), pebble);
	gravel += (plate.r - plate.b) * vec3(0.14, 0.09, 0.0);
	vec3 sediment = mix(vec3(0.29, 0.25, 0.18), vec3(0.53, 0.44, 0.30), stone * 0.56 + veins * 0.44);
	gravel = mix(gravel, sediment, silt * 0.90);
	float grain = earth_patch(pixel / 2.4);
	// Exposed gravel shows through in pockets, with quieter deposits between them.
	float gravel_pockets = smoothstep(0.37, 0.71, patches + veins * 0.22);
	gravel += (grain - 0.49) * vec3(0.22, 0.16, 0.10) * (0.29 + gravel_pockets * 0.71);
	gravel *= 0.94 + 0.16 * veins;
	float damp = max(smoothstep(0.008, 0.050, depth), shore.r * 0.86);
	vec3 damp_gravel = gravel * vec3(0.61, 0.72, 0.75);
	float shade = leaf_shade(art_uv, creek_time);
	float moss = bank * damp * smoothstep(0.50, 0.79, patches + veins * 0.17 + shade * 0.15);
	damp_gravel = mix(damp_gravel, vec3(0.20, 0.26, 0.14) * (0.79 + pebble * 0.48), moss * 0.75);

	float deep = smoothstep(0.12, 0.90, depth);
	vec3 shallow_water = plate * vec3(0.81, 0.86, 0.83) + vec3(0.036, 0.022, 0.005);
	shallow_water = mix(shallow_water, damp_gravel * vec3(0.85, 1.09, 1.14), 0.30 + bank * 0.21);
	vec3 pool = mix(vec3(0.073, 0.19, 0.23), plate * vec3(0.51, 0.63, 0.80), 0.54);
	vec3 water = mix(shallow_water, pool, deep * 0.90);
	float algae = slow * (1.0 - deep) * smoothstep(0.42, 0.76, patches + veins * 0.19 + shade * 0.11);
	water = mix(water, vec3(0.23, 0.27, 0.17), algae * 0.19);
	water = mix(water, sediment, min(0.87, silt * (1.0 - deep * 0.87) * 0.39 + state.a * 0.69));

	float sun = (1.0 - shade) * smoothstep(0.35, 0.9, art_uv.x + art_uv.y * 0.52);
	float glint = step(0.93, sin(pixel.x * 0.123 - creek_time * 1.6 + sin(pixel.y * 0.29)));
	glint *= smoothstep(0.47, 0.72, earth_patch(pixel / vec2(11.0, 3.5) - shore.gb * 0.025));
	water = mix(water, vec3(0.76, 0.88, 0.79), glint * sun * (1.0 - deep * 0.76) * 0.22);

	vec2 motion = pixel - shore.gb;
	float bend = sin(motion.y * 0.16) * 1.79 + sin(motion.x * 0.027 + motion.y * 0.061);
	float ripple = step(0.959, sin(motion.x * 0.105 + bend));
	ripple *= step(0.61, cos(motion.y * 0.38 + motion.x * 0.064));
	water = mix(water, vec3(0.55, 0.79, 0.76), ripple * (0.058 + speed * 0.24));
	float edge = 0.068 + sin(pixel.x * 0.063 + creek_time * 1.2) * 0.005;
	float rim = 1.0 - smoothstep(0.05, 0.16, channel.g);
	float meniscus = max(1.0 - smoothstep(0.002, 0.019, abs(depth - edge)), rim);
	float foam = step(0.59, earth_patch(vec2(motion.x * 0.075, pixel.y * 0.25))) * smoothstep(0.02, 0.30, speed);
	water = mix(water, vec3(0.68, 0.80, 0.70), meniscus * (0.03 + foam * 0.38));

	float cover = smoothstep(0.032, 0.074, depth);
	COLOR = vec4(afternoon_light(mix(mix(gravel, damp_gravel, damp), water, cover), art_uv, creek_time, max(cover, damp * 0.59)), channel.r);
}

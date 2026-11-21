shader_type canvas_item;
render_mode unshaded;

#include "res://game/one_dam_daylight.gdshaderinc"

uniform sampler2D channel_mask : filter_nearest, repeat_disable;
uniform sampler2D channel_profile : filter_linear, repeat_disable;
uniform sampler2D flow_state : filter_linear, repeat_disable;
uniform float creek_time;
uniform sampler2D shore_memory : filter_linear, repeat_disable;
uniform sampler2D surge_field : filter_linear, repeat_disable;
uniform vec2 upper_pool;
uniform vec2 lower_pool;
uniform float bed_refraction : hint_range(0.0, 1.0) = 1.0;
uniform float bank_foam : hint_range(0.0, 1.0) = 1.0;
uniform vec4 wind_travel;
uniform float rain_intensity;
const vec2 WIND = vec2(0.94, 0.34);

float backed_water(float x, vec2 pond) {
	float distance = pond.x - x;
	return smoothstep(-0.016, 0.026, distance) * (1.0 - smoothstep(0.09, 0.31, distance))
		* smoothstep(0.08, 0.63, pond.y);
}

vec2 flow_uv(vec2 uv) {
	vec2 profile = texture(channel_profile, vec2(uv.x, 0.5)).rg;
	float row = (uv.y - profile.x) / max(0.01, 2.0 * profile.y) + 0.5;
	return vec2(uv.x, clamp(row, 0.0, 1.0));
}

float gravel_shelf(float row) {
	return smoothstep(0.30, 0.96, abs(row - 0.5) * 2.0);
}

float water_edge(float shelf, float patches) {
	return 0.072 + shelf * (0.126 + patches * 0.040);
}

void fragment() {
	vec3 plate = texture(TEXTURE, UV).rgb;
	vec3 channel = texture(channel_mask, UV).rgb;
	vec2 pixel = floor(UV / TEXTURE_PIXEL_SIZE);
	vec2 art_uv = (pixel + 0.5) * TEXTURE_PIXEL_SIZE;
	vec2 flow_coord = flow_uv(art_uv);
	vec4 state = texture(flow_state, flow_coord);
	vec2 v = (state.gb - vec2(0.5)) * 2.0;
	float depth = state.r * 1.5;
	float speed = length(v);
	vec4 shore = texture(shore_memory, flow_coord);
	float bank = 1.0 - smoothstep(0.04, 0.38, channel.g);
	float patches = earth_patch(pixel / vec2(27.0, 14.0));
	float veins = earth_patch(vec2(pixel.x * 0.058 + pixel.y * 0.035, pixel.y * 0.22));
	float slow = 1.0 - smoothstep(0.055, 0.27, speed);
	float silt = clamp(shore.a * 0.95 + bank * slow * smoothstep(0.36, 0.77, patches * 0.68 + veins * 0.44) * 0.55, 0.0, 1.0);
	float shelf = gravel_shelf(flow_coord.y);
	float waterline = depth - water_edge(shelf, patches);
	vec2 bank_gradient = vec2(dFdx(waterline), dFdy(waterline));
	float push = texture(surge_field, vec2(art_uv.x, 0.5)).r;
	vec2 motion = pixel - shore.gb;

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
	float shade = canopy_cover(art_uv);
	float moss = bank * damp * smoothstep(0.50, 0.79, patches + veins * 0.17 + shade * 0.15);
	damp_gravel = mix(damp_gravel, vec3(0.20, 0.26, 0.14) * (0.79 + pebble * 0.48), moss * 0.75);

	float deep = smoothstep(0.19, 0.67, depth);
	float pool_extent = max(backed_water(art_uv.x, upper_pool), backed_water(art_uv.x, lower_pool));
	float held_water = pool_extent * smoothstep(0.20, 0.62, depth);
	// Shift only the submerged plate. The ground and the water footprint keep their original UVs.
	vec3 submerged_plate = plate;
	float clarity = (1.0 - deep) * (1.0 - smoothstep(0.10, 0.53, state.a + silt * 0.20));
	float warp = bed_refraction * clarity * smoothstep(0.006, 0.067, waterline);
	if (channel.r > 0.5 && warp > 0.10) {
		vec2 along = speed > 0.025 ? v / speed : vec2(1.0, 0.0);
		vec2 across = vec2(-along.y, along.x);
		float rolling = dot(motion, along * 0.11 + across * 0.22) - creek_time * 0.74;
		float flowing = smoothstep(0.025, 0.40, speed);
		vec2 bend_uv = along * sin(rolling + sin(motion.y * 0.17)) * (0.72 + flowing * 1.32);
		bend_uv += across * cos(rolling * 0.71 + motion.x * 0.041) * (0.52 + flowing * 0.42);
		vec2 pixel_shift = clamp(round(bend_uv * warp), vec2(-2.0), vec2(2.0));
		vec2 displaced = art_uv + pixel_shift * TEXTURE_PIXEL_SIZE;
		if (dot(pixel_shift, pixel_shift) > 0.5 && all(greaterThanEqual(displaced, vec2(0.0)))
				&& all(lessThan(displaced, vec2(1.0))) && texture(channel_mask, displaced).r > 0.5) {
			vec2 source = flow_uv(displaced);
			float source_gravel = earth_patch((pixel + pixel_shift) / vec2(27.0, 14.0));
			if (texture(flow_state, source).r * 1.5 > water_edge(gravel_shelf(source.y), source_gravel)) {
				submerged_plate = texture(TEXTURE, displaced).rgb;
			}
		}
	}
	vec3 shallow_water = submerged_plate * vec3(0.81, 0.86, 0.83) + vec3(0.036, 0.022, 0.005);
	shallow_water = mix(shallow_water, damp_gravel * vec3(0.85, 1.09, 1.14), 0.30 + bank * 0.21);
	vec3 pool = mix(vec3(0.073, 0.19, 0.23), plate * vec3(0.51, 0.63, 0.80), 0.54);
	vec3 water = mix(shallow_water, pool, deep * 0.90);
	water = mix(water, water * vec3(0.62, 0.76, 0.88) + vec3(0.004, 0.009, 0.016), held_water * 0.76);
	float algae = slow * (1.0 - deep) * smoothstep(0.42, 0.76, patches + veins * 0.19 + shade * 0.11);
	water = mix(water, vec3(0.23, 0.27, 0.17), algae * 0.19);
	water = mix(water, sediment, min(0.87, silt * (1.0 - deep * 0.87) * 0.39 + state.a * 0.69));

	float breeze = wind_at(art_uv.x);
	float lit = 1.0 - shade * 0.65;
	float sun = lit * smoothstep(0.35, 0.9, art_uv.x + art_uv.y * 0.52) * (0.61 + sunlight_at(art_uv) * 0.59);
	sun *= 1.0 - rain_intensity * 0.73;
	float glint = step(0.93, sin(pixel.x * 0.123 - creek_time * 1.6 + sin(pixel.y * 0.29)));
	glint *= smoothstep(0.47, 0.72, earth_patch(pixel / vec2(11.0, 3.5) - shore.gb * 0.025));
	water = mix(water, vec3(0.83, 0.88, 0.80), glint * sun * (1.0 - deep * 0.76) * (0.26 + breeze * 0.12));

	// Gusts roughen patches of the surface that drift downwind and sparkle where the sun reaches.
	vec2 drift = motion - WIND * downwind_sample(wind_travel, art_uv.x);
	float paws = smoothstep(0.43, 0.68, earth_patch(drift / vec2(44.0, 23.0))) * smoothstep(0.27, 0.83, breeze);
	float chop = smoothstep(0.71, 0.90, earth_patch(drift / vec2(4.6, 1.4)));
	water = mix(water, water * vec3(0.95, 0.98, 1.02) + vec3(0.0, 0.01, 0.02), paws * 0.30);
	water = mix(water, vec3(0.72, 0.82, 0.79), chop * paws * (0.055 + sun * 0.27));

	float bend = sin(motion.y * 0.16) * 1.79 + sin(motion.x * 0.027 + motion.y * 0.061);
	float ripple = step(0.959, sin(motion.x * 0.105 + bend));
	ripple *= step(0.61, cos(motion.y * 0.38 + motion.x * 0.064));
	water = mix(water, vec3(0.55, 0.79, 0.76), ripple * (0.058 + speed * 0.24) * (1.0 - held_water * 0.42));
	float broken_crest = step(0.66, earth_patch(motion / vec2(12.0, 2.6)));
	float live_crest = push * smoothstep(0.065, 0.38, speed);
	water = mix(water, vec3(0.27, 0.51, 0.49), live_crest * 0.22);
	water = mix(water, vec3(0.78, 0.90, 0.85), broken_crest * live_crest * 0.50);
	// Gravel shelves stay exposed in the open creek. As local depth rises, the
	// contact line crosses the shelf, following the same contour as the water fill.
	float cover = smoothstep(-0.025, 0.018, waterline);
	cover = mix(cover, 1.0, push * smoothstep(0.040, 0.15, depth) * 0.52);
	// Convert depth-to-shore into screen pixels so the foam stays thin as the bank slope changes.
	float bank_dist = min(waterline / max(length(bank_gradient), 0.002), channel.g * 50.0);
	float shore_motion = sin(motion.x * 0.12 + motion.y * 0.29 - creek_time * 1.8);
	float line_center = 0.85 + shore_motion * (0.24 + push * 0.51);
	float meniscus = 1.0 - smoothstep(0.35, 1.35 + push * 0.65, abs(bank_dist - line_center));
	float broken_foam = smoothstep(0.48, 0.73, earth_patch(motion / vec2(8.0, 3.2) + vec2(-creek_time * 0.23, 1.6)));
	float running = smoothstep(0.025, 0.29, speed);
	float foam = meniscus * (0.09 + pool_extent * 0.15 + broken_foam * (running * 0.32 + push * 0.28));
	float backwash = 1.0 - smoothstep(0.31, 1.04, abs(bank_dist - line_center - 2.7 - push));
	foam += backwash * broken_foam * (running * 0.085 + push * 0.10);
	water = mix(water, vec3(0.73, 0.85, 0.78), foam * bank_foam * smoothstep(-0.004, 0.019, waterline));

	float value = dot(water, vec3(0.26, 0.63, 0.11));
	water = mix(water, value * vec3(0.86, 1.01, 0.99), 0.18 + deep * 0.08);
	// A moving film can still trace the pebbles below a nearly drained dam.
	float trickle = smoothstep(0.009, 0.072, depth) * smoothstep(0.018, 0.14, speed) * (1.0 - shelf * 0.75);
	cover = mix(cover, 1.0, trickle * 0.45);
	COLOR = vec4(afternoon_light(mix(mix(gravel, damp_gravel, damp), water, cover), art_uv, max(cover, damp * 0.59)), channel.r);
}

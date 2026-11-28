shader_type canvas_item;
render_mode unshaded;

#include "res://game/one_dam_daylight.gdshaderinc"

uniform vec4 canopy_flutter;
uniform float rain_wetness;
uniform float rain_intensity;
uniform float spring_amount = 0.0;
uniform float summer_amount = 0.0;
uniform float autumn_amount = 0.0;
uniform float winter_amount = 0.0;
uniform vec3 hearth_light = vec3(0.73125, 0.77, 0.0);
uniform bool independent_prop = false;
uniform vec4 prop_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 prop_sway = vec2(0.0);
uniform float prop_anchor = 0.0;
uniform sampler2D channel_mask : filter_nearest, repeat_disable;
uniform sampler2D channel_profile : filter_linear, repeat_disable;
uniform sampler2D flow_state : filter_linear, repeat_disable;
uniform sampler2D shore_memory : filter_linear, repeat_disable;

float fringe(vec2 p, vec2 root, vec2 radius) {
	return 1.0 - smoothstep(0.45, 1.0, length((p - root) / radius));
}

float branch_sway(vec2 p) {
	vec2 cluster = p * vec2(43.0, 26.0);
	float branch = earth_patch(cluster);
	float tip = earth_patch(cluster * 0.56 + vec2(3.1, 5.2));
	return mix(mix(canopy_flutter.x, canopy_flutter.y, branch),
		mix(canopy_flutter.z, canopy_flutter.w, branch), tip);
}

float foliage_color(vec3 color) {
	float green_leaf = smoothstep(0.010, 0.074, color.g - color.r * 0.85) * smoothstep(0.024, 0.124, color.g - color.b);
	// Also sway warm honey-gold/crimson autumn leaves and spring cherry blossoms.
	float autumn_leaf = smoothstep(0.18, 0.36, color.r - color.b) * smoothstep(0.06, 0.24, color.r - color.g * 0.65) * smoothstep(0.12, 0.42, color.r);
	float pink_blossom = smoothstep(0.08, 0.22, color.r - color.g) * smoothstep(0.62, 0.84, color.r) * smoothstep(0.55, 0.78, color.b);
	return max(max(green_leaf, autumn_leaf * 0.85), pink_blossom * 0.80);
}

float cast_leaf_shade(vec2 p, vec2 texel) {
	// Only the small branch tips at the existing tree-shadow edge cast moving shade.
	float fringe_mask = fringe(p, vec2(0.32, 0.14), vec2(0.24, 0.16));
	if (fringe_mask <= 0.0) {
		return 0.0;
	}
	vec2 source = p - vec2(0.16, 0.055);
	float gust = wind_at(source.x);
	float motion = branch_sway(source);
	vec2 sway = (motion * vec2(2.1, -0.8) + gust * vec2(0.9, 0.35)) * texel;
	float patches = earth_patch((p - sway) * vec2(107.0, 80.0));
	float gaps = earth_patch(p * vec2(23.0, 17.0) + vec2(2.4, 6.1));
	return fringe_mask * smoothstep(0.54, 0.71, patches) * smoothstep(0.29, 0.69, gaps);
}

void fragment() {
	vec2 local_texel = TEXTURE_PIXEL_SIZE;
	vec2 uv = (floor(UV / local_texel) + 0.5) * local_texel;
	vec2 p = prop_region.xy + uv * prop_region.zw;
	vec2 texel = local_texel * prop_region.zw;
	vec2 sample_at = uv;
	if (independent_prop && prop_anchor > 0.0) {
		float flex = smoothstep(0.0, prop_anchor * 0.85, prop_anchor - uv.y);
		sample_at -= round(prop_sway * flex) * local_texel;
	}
	vec4 source = texture(TEXTURE, sample_at);
	float silhouette = source.a;
	if (any(lessThan(sample_at, vec2(0.0))) || any(greaterThanEqual(sample_at, vec2(1.0)))) {
		silhouette = 0.0;
	}
	vec3 art = source.rgb;
	float green = foliage_color(art);
	if (!independent_prop) {
		float hanging = fringe(p, vec2(0.16, 0.09), vec2(0.26, 0.16));
		float right_pine = fringe(p, vec2(0.95, 0.22), vec2(0.12, 0.26));
		float reeds = fringe(p, vec2(0.06, 0.84), vec2(0.14, 0.19));
		float right_reeds = fringe(p, vec2(0.94, 0.84), vec2(0.12, 0.20));
		float mid_bank = fringe(p, vec2(0.46, 0.31), vec2(0.08, 0.06));
		float gust = wind_at(p.x);
		float flutter = 0.72 + gust * 0.72;
		float movement = max(hanging, right_pine) * branch_sway(p);
		movement += mid_bank * branch_sway(p + vec2(0.12, 0.04));
		movement += max(reeds, right_reeds) * branch_sway(p + vec2(0.24, 0.03)) * 1.15;
		float lean = gust * (0.14 + max(hanging, right_pine) * 0.62 + mid_bank * 0.45 + max(reeds, right_reeds) * 0.85);
		vec2 displacement = -movement * flutter * vec2(2.1, -0.65) - lean * vec2(1.4, 0.55);
		vec2 moved = p + round(displacement * green) * texel;
		vec3 tip = texture(TEXTURE, moved).rgb;
		if (foliage_color(tip) > 0.12) {
			art = tip;
		}
	}
	// Gentle painterly corner grounding while preserving Witchbrook autumn color vibrancy.
	float distance_to_creek = abs(p.y - (0.55 - p.x * 0.17));
	float far_bank = smoothstep(0.28, 0.56, distance_to_creek);
	float corner_shade = smoothstep(0.48, 0.98, length((p - vec2(0.50, 0.50)) * vec2(1.02, 1.12)));
	float frame_shade = clamp(far_bank * 0.45 + corner_shade * 0.55, 0.0, 1.0);
	float luma = dot(art, vec3(0.26, 0.63, 0.11));
	// Summer deepens tree-canopy shade contrast; Spring softens & airs out shadows.
	float shade_depth = 0.26 + summer_amount * 0.24 - spring_amount * 0.09;
	vec3 shade_tint = mix(vec3(0.88, 0.89, 0.92), vec3(0.74, 0.83, 0.78), summer_amount);
	shade_tint = mix(shade_tint, vec3(0.93, 0.95, 0.96), spring_amount);
	art *= mix(vec3(1.0), shade_tint, frame_shade * shade_depth);

	vec2 pixel = floor(p / texel);
	float patches = earth_patch(pixel / vec2(34.0, 13.0));
	float grain = earth_patch(pixel / 2.0);
	float soil = smoothstep(0.035, 0.13, art.r - art.g) * smoothstep(0.28, 0.51, luma);
	// Foot traffic follows the two existing dirt paths, with bare patches and soft edges.
	float path = max(fringe(p, vec2(0.64, 0.15), vec2(0.31, 0.13)), fringe(p, vec2(0.43, 0.88), vec2(0.31, 0.13)));
	float track = sin(pixel.y * 0.112 + sin(pixel.x * 0.015) * 1.7 - pixel.x * 0.022);
	float worn = path * soil * smoothstep(0.22, 0.76, patches * 0.80 + track * 0.20);
	art = mix(art, art * vec3(0.93, 0.87, 0.82), worn * (0.38 + grain * 0.44));
	art += vec3(0.054, 0.040, 0.022) * worn * step(0.83, grain);

	vec2 profile = texture(channel_profile, vec2(p.x, 0.5)).rg;
	float side = sign(p.y - profile.x);
	vec2 inward = vec2(0.0, -side * texel.y);
	float short_probe = texture(channel_mask, p + inward * 2.0).r;
	float middle_probe = texture(channel_mask, p + inward * (4.0 + round(patches * 2.0))).r;
	float long_probe = texture(channel_mask, p + inward * (6.0 + round(patches * 4.0))).r;
	float bank = max(short_probe, max(middle_probe * 0.66, long_probe * 0.27));
	bank *= 1.0 - texture(channel_mask, p).r;
	vec2 edge_cell = vec2(p.x, 0.5 + side * 0.41);
	float damp = max(texture(shore_memory, edge_cell).r * 0.78, smoothstep(0.014, 0.065, texture(flow_state, edge_cell).r));
	// Spring banks hold extra dewy morning moisture near the water; Summer bakes dry faster.
	float wet_bank = clamp(bank * (damp + spring_amount * 0.24) * (0.64 + patches * 0.36), 0.0, 1.0);
	art = mix(art, art * vec3(0.58, 0.70, 0.75), wet_bank * (0.76 - summer_amount * 0.10));
	float moss = wet_bank * smoothstep(0.36, 0.79, patches * 0.75 + grain * 0.40) * (1.0 - winter_amount * 0.85);
	vec3 moss_hue = mix(vec3(0.20, 0.25, 0.14), vec3(0.24, 0.35, 0.15), spring_amount + summer_amount * 0.7);
	art = mix(art, moss_hue * (0.74 + luma * 0.74), moss * (0.57 + summer_amount * 0.12));
	// Subtle frosty rime sheen along the winter water edge.
	float rime = wet_bank * winter_amount * smoothstep(0.52, 0.85, patches * 0.70 + grain * 0.35);
	art = mix(art, vec3(0.82, 0.89, 0.96), rime * 0.24);
	// The plate contains colored water fringe past the playable mask. Tint it as damp ground.
	float painted_water = smoothstep(0.12, 0.26, art.g - art.r) * smoothstep(0.60, 0.83, art.b / max(art.g, 0.01));
	vec3 fringe_tone = mix(vec3(0.79, 0.85, 0.65), vec3(0.78, 0.84, 0.92), winter_amount);
	art = mix(art, luma * fringe_tone, painted_water * smoothstep(0.04, 0.40, bank));
	// Preserve crisp painterly seasonal hues while clearly separating Spring softness vs Summer sun/shade.
	vec3 land = afternoon_light(art, p, wet_bank);
	// Subtle soft dewy pastel lift in Spring; deeper warm-green midsummer richness in Summer.
	land = mix(land, land * vec3(1.01, 1.025, 1.01) + vec3(0.022, 0.024, 0.018), spring_amount * (1.0 - twilight_weight()) * 0.55);
	float canopy_deep = canopy_cover(p) * summer_amount * (1.0 - twilight_weight() * 0.6);
	land *= mix(vec3(1.0), vec3(0.80, 0.88, 0.84), canopy_deep * 0.62);
	float value = dot(land, vec3(0.26, 0.63, 0.11));
	float dusk = dusk_weight();
	float twi = twilight_weight();
	float sunlit = sunlight_at(p) * smoothstep(0.26, 0.58, value) * (0.76 + patches * 0.24);
	vec3 day_sun = vec3(0.055, 0.048, 0.036);
	day_sun = mix(day_sun, vec3(0.048, 0.054, 0.042), spring_amount);
	day_sun = mix(day_sun, vec3(0.105, 0.095, 0.052), summer_amount);
	day_sun = mix(day_sun, vec3(0.080, 0.058, 0.030), autumn_amount);
	day_sun = mix(day_sun, vec3(0.042, 0.054, 0.072), winter_amount);
	vec3 sun_tint = mix(day_sun, vec3(0.115, 0.058, 0.020), dusk);
	land += sun_tint * sunlit * (1.0 + summer_amount * 0.35) * (1.0 - rain_intensity * 0.82) * (1.0 - twi * 0.92);
	float leaf_shade = cast_leaf_shade(p, texel) * smoothstep(0.30, 0.58, value);
	float leaf_shade_amt = (0.68 + summer_amount * 0.28 + sunlit * 0.26) * (1.0 - rain_intensity * 0.66) * (1.0 - twi * 0.75);
	land *= mix(vec3(1.0), mix(vec3(0.88, 0.90, 0.96), vec3(0.76, 0.85, 0.84), summer_amount), leaf_shade * leaf_shade_amt);
	float soaked = rain_wetness * (0.66 + patches * 0.34);
	land *= mix(vec3(1.0), vec3(0.75, 0.81, 0.89), soaked);
	land += vec3(0.040, 0.055, 0.052) * soaked * green * smoothstep(0.47, 0.68, value) * (1.0 - twi * 0.55);
	if (hearth_light.z > 0.005) {
		vec2 fire_radius = vec2(0.155, 0.175) * (1.0 + dusk * 0.14 + twi * 0.38);
		vec2 fire_offset = (p - hearth_light.xy) / fire_radius;
		float fire_falloff = pow(max(0.0, 1.0 - length(fire_offset)), 1.85);
		float glow_grain = 0.86 + 0.28 * earth_patch(pixel / 3.5);
		float evening_boost = 1.0 + dusk * 0.52 + twi * 1.28;
		float glow = fire_falloff * hearth_light.z * glow_grain * (0.72 + rain_wetness * 0.38) * evening_boost;
		land += vec3(0.28, 0.132, 0.036) * glow * (0.48 + 0.52 * smoothstep(0.06, 0.50, value));
		land = mix(land, land * vec3(1.18, 1.00, 0.84), min(0.76, glow * 0.72));
	}
	float mist = rain_intensity * (0.10 * (1.0 - p.y) + 0.035);
	vec3 mist_color = mix(vec3(0.58, 0.66, 0.69), vec3(0.62, 0.52, 0.50), dusk * 0.75);
	mist_color = mix(mist_color, vec3(0.24, 0.32, 0.46), twi);
	land = mix(land, mist_color, mist);
	COLOR = vec4(land, independent_prop ? silhouette : 1.0);
}

shader_type canvas_item;
render_mode unshaded;

#include "res://game/one_dam_daylight.gdshaderinc"

uniform float afternoon_time;
uniform sampler2D channel_mask : filter_nearest, repeat_disable;
uniform sampler2D channel_profile : filter_linear, repeat_disable;
uniform sampler2D flow_state : filter_linear, repeat_disable;
uniform sampler2D shore_memory : filter_linear, repeat_disable;

float fringe(vec2 p, vec2 root, vec2 radius) {
	return 1.0 - smoothstep(0.45, 1.0, length((p - root) / radius));
}

void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE;
	vec2 p = (floor(UV / texel) + 0.5) * texel;
	vec3 art = texture(TEXTURE, p).rgb;

	// Only foliage already painted in these areas can be displaced.
	float green = smoothstep(0.012, 0.080, art.g - art.r * 0.83) * smoothstep(0.026, 0.14, art.g - art.b);
	float hanging = fringe(p, vec2(0.153, 0.122), vec2(0.17, 0.13));
	float fern = fringe(p, vec2(0.464, 0.305), vec2(0.07, 0.055));
	float reeds = fringe(p, vec2(0.047, 0.728), vec2(0.072, 0.1));
	float gust = smoothstep(0.70, 0.99, sin(afternoon_time * 0.145));
	float movement = hanging * (sin(afternoon_time * 0.95 + p.y * 38.0) + gust * 0.56);
	movement += fern * sin(afternoon_time * 0.72 + p.x * 48.0);
	movement += reeds * sin(afternoon_time * 1.63 + p.y * 42.0);
	vec2 moved = p + round(vec2(movement * 2.65, movement * -0.78) * green) * texel;
	art = texture(TEXTURE, moved).rgb;
	// The forest recedes away from the creek while the interactive layer stays crisp.
	float distance_to_creek = abs(p.y - (0.55 - p.x * 0.17));
	float far_bank = smoothstep(0.18, 0.48, distance_to_creek);
	float luma = dot(art, vec3(0.26, 0.63, 0.11));
	art = mix(art, vec3(luma) * vec3(0.94, 0.98, 1.02), far_bank * 0.24);
	art = mix(art, (art - 0.44) * 0.79 + 0.42, far_bank * 0.66);

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
	float wet_bank = bank * damp * (0.64 + patches * 0.36);
	art = mix(art, art * vec3(0.58, 0.70, 0.75), wet_bank * 0.76);
	float moss = wet_bank * smoothstep(0.36, 0.79, patches * 0.75 + grain * 0.40);
	art = mix(art, vec3(0.20, 0.25, 0.14) * (0.74 + luma * 0.74), moss * 0.57);
	// The plate contains colored water fringe past the playable mask. Tint it as damp ground.
	float painted_water = smoothstep(0.12, 0.26, art.g - art.r) * smoothstep(0.60, 0.83, art.b / max(art.g, 0.01));
	art = mix(art, luma * vec3(0.79, 0.85, 0.65), painted_water * smoothstep(0.04, 0.40, bank));
	COLOR = vec4(afternoon_light(art, p, afternoon_time, wet_bank), 1.0);
}

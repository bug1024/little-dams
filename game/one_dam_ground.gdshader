shader_type canvas_item;
render_mode unshaded;

#include "res://game/one_dam_daylight.gdshaderinc"

uniform float afternoon_time;

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
	vec2 moved = p + round(vec2(movement * 2.15, movement * -0.61) * green) * texel;
	art = texture(TEXTURE, moved).rgb;
	COLOR = vec4(afternoon_light(art, p, afternoon_time, 0.0), 1.0);
}

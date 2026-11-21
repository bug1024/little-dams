shader_type canvas_item;
render_mode unshaded;

uniform sampler2D channel_mask : filter_nearest, repeat_disable;
uniform sampler2D flow_state : filter_nearest, repeat_disable;
uniform float creek_time;
uniform bool reveal_riverbed = false;

void fragment() {
	vec4 artwork = texture(TEXTURE, UV);
	vec2 water = texture(channel_mask, UV).rg;
	vec4 state = texture(flow_state, vec2(UV.x, 0.5));
	vec2 pixel = floor(UV / TEXTURE_PIXEL_SIZE);
	float deep = state.r * smoothstep(0.02, 0.82, water.g);
	float shelf = smoothstep(0.0, 0.29 + state.r * 0.32, water.g);
	vec3 surface = mix(artwork.rgb, artwork.rgb * vec3(0.51, 0.65, 1.07), deep * 0.86);
	surface = mix(surface, vec3(0.49, 0.48, 0.29) * (0.51 + surface.g * 0.63), state.b * 0.66);

	float phase = pixel.x * 0.098 - creek_time * (2.3 + state.g * 6.0);
	float bend = sin(pixel.y * 0.42) * 1.1 + sin(pixel.y * 0.105 + pixel.x * 0.021);
	float glint = step(0.91, sin(phase + bend)) * step(0.54, cos(pixel.y * 0.47 + pixel.x * 0.038));
	float light = glint * (0.06 + state.g * 0.22) * shelf * (1.0 - state.b * 0.6);
	surface = mix(surface, vec3(0.69, 0.96, 0.92), light);
	if (reveal_riverbed) {
		float rim = (1.0 - state.a) * 0.92;
		float wet = smoothstep(rim - 0.10, rim + 0.03, water.g);
		float texture_grain = fract(dot(mod(pixel, 7.0), vec2(0.51, 0.37)));
		float luma = dot(artwork.rgb, vec3(0.26, 0.52, 0.22));
		vec3 gravel = mix(vec3(0.30, 0.30, 0.26), vec3(0.60, 0.51, 0.36), clamp(luma + step(0.80, texture_grain) * 0.12, 0.0, 1.0));
		float meniscus = smoothstep(rim - 0.02, rim + 0.04, water.g) * (1.0 - smoothstep(rim + 0.04, rim + 0.12, water.g));
		surface = mix(gravel, surface, wet);
		surface = mix(surface, vec3(0.45, 0.71, 0.64), meniscus * min(1.0, rim * 2.5) * 0.4);
	}
	COLOR = vec4(surface, water.r * artwork.a);
}

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;

// Screen-space outlines: edges from depth + normals, drawn as thin anti-aliased lines
// tinted with the surface colour underneath (looks like a clean cartoon, not a pencil sketch).
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D normal_roughness_texture : hint_normal_roughness_texture, filter_nearest;

uniform vec4 ink_color : source_color = vec4(0.16, 0.13, 0.12, 1.0);
uniform float ink_tint : hint_range(0.0, 1.0) = 0.55;     // 0 = flat ink colour, 1 = darkened surface colour
uniform float line_px : hint_range(0.5, 4.0) = 1.0;
uniform float depth_threshold : hint_range(0.001, 0.2) = 0.035;
uniform float normal_threshold : hint_range(0.0, 1.0) = 0.6;
uniform float ink_opacity : hint_range(0.0, 1.0) = 0.8;
uniform float max_distance = 30.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.18;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float linear_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_texture, uv).r;
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
	vec4 view = inv_proj * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return -view.z;
}

vec3 view_normal(vec2 uv) {
	return normalize(texture(normal_roughness_texture, uv).rgb * 2.0 - 1.0);
}

void fragment() {
	vec2 px = 1.0 / vec2(textureSize(screen_texture, 0));
	vec2 uv = SCREEN_UV;

	float dc = linear_depth(uv, INV_PROJECTION_MATRIX);
	vec3 nc = view_normal(uv);
	float edge = 0.0;
	if (dc < max_distance) {
		// 8 taps at half the line width give a smooth line instead of a stair-stepped one.
		vec2 offs[8] = {vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
			vec2(0.7, 0.7), vec2(-0.7, 0.7), vec2(0.7, -0.7), vec2(-0.7, -0.7)};
		for (int i = 0; i < 8; i++) {
			vec2 o = offs[i] * px * line_px;
			float dn = linear_depth(uv + o, INV_PROJECTION_MATRIX);
			float rel = abs(dn - dc) / max(dc, 0.05);
			// Only draw where the neighbour is further away, so lines hug the nearer object.
			float depth_edge = smoothstep(depth_threshold, depth_threshold * 3.0, rel) * step(dc, dn + 0.0005);
			vec3 nn = view_normal(uv + o);
			float ndiff = 1.0 - dot(nc, nn);
			float normal_edge = smoothstep(normal_threshold, normal_threshold + 0.3, ndiff) * 0.7;
			edge += max(depth_edge, normal_edge);
		}
		edge = clamp(edge / 3.0, 0.0, 1.0);
	}
	// Fade with distance so far walls stay clean.
	edge *= clamp(1.3 - dc / max_distance, 0.25, 1.0);

	vec3 color = texture(screen_texture, uv).rgb;
	vec3 line = mix(ink_color.rgb, color * 0.35, ink_tint);
	color = mix(color, line, edge * ink_opacity);
	// Soft vignette pulls the eye to the middle of the room.
	vec2 v = uv * 2.0 - 1.0;
	color *= 1.0 - vignette * smoothstep(0.55, 1.6, dot(v, v));
	ALBEDO = color;
}

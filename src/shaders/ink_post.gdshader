shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;

// Screen-space ink outlines: edges from depth + normals, jittered per cell at a low
// frame rate so the lines wobble like a hand-drawn animation. Plus a whisper of paper grain.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D normal_roughness_texture : hint_normal_roughness_texture, filter_nearest;

uniform vec4 ink_color : source_color = vec4(0.11, 0.10, 0.09, 1.0);
uniform float line_px : hint_range(0.5, 4.0) = 1.4;
uniform float depth_threshold : hint_range(0.001, 0.2) = 0.03;
uniform float normal_threshold : hint_range(0.0, 1.0) = 0.55;
uniform float wobble_px : hint_range(0.0, 4.0) = 1.2;
uniform float wobble_fps : hint_range(1.0, 30.0) = 8.0;
uniform float grain : hint_range(0.0, 0.2) = 0.035;
uniform float ink_opacity : hint_range(0.0, 1.0) = 0.9;
uniform float max_distance = 40.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
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
	float t = floor(TIME * wobble_fps) / wobble_fps;
	// Hand-drawn jitter: each 24px cell shifts its sampling a little, re-rolled every frame tick.
	vec2 cell = floor(SCREEN_UV / (px * 24.0));
	vec2 jitter = (vec2(hash12(cell + t * 7.13), hash12(cell + 91.7 + t * 3.71)) - 0.5) * wobble_px * px;
	vec2 uv = SCREEN_UV + jitter;

	float dc = linear_depth(uv, INV_PROJECTION_MATRIX);
	vec3 nc = view_normal(uv);
	float edge = 0.0;
	if (dc < max_distance) {
		vec2 offs[4] = {vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y)};
		for (int i = 0; i < 4; i++) {
			vec2 o = offs[i] * line_px;
			float dn = linear_depth(uv + o, INV_PROJECTION_MATRIX);
			float rel = abs(dn - dc) / max(dc, 0.05);
			edge = max(edge, smoothstep(depth_threshold, depth_threshold * 2.5, rel));
			vec3 nn = view_normal(uv + o);
			float ndiff = 1.0 - dot(nc, nn);
			edge = max(edge, smoothstep(normal_threshold, normal_threshold + 0.25, ndiff));
		}
	}
	// Thin out lines further away so the far wall does not become a black mesh.
	edge *= clamp(1.4 - dc / max_distance, 0.3, 1.0);

	vec3 color = texture(screen_texture, SCREEN_UV).rgb;
	float g = (hash12(floor(SCREEN_UV / (px * 2.0)) + t * 0.37) - 0.5) * grain;
	color *= 1.0 + g;
	ALBEDO = mix(color, ink_color.rgb, edge * ink_opacity);
}

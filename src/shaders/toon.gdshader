shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// Three-band cel shading with tinted shadows, a soft specular glint and a subtle rim.
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform bool world_uv = false;               // sample albedo_tex by world position (walls, floor)
uniform float world_uv_scale = 1.0;
uniform float band_edge : hint_range(0.0, 1.0) = 0.35;
uniform float band_softness : hint_range(0.0, 0.3) = 0.06;
uniform float mid_edge : hint_range(0.0, 1.0) = 0.7;
uniform float shadow_brightness : hint_range(0.0, 1.0) = 0.62;
uniform float mid_brightness : hint_range(0.0, 1.0) = 0.84;
uniform vec4 shadow_tint : source_color = vec4(0.78, 0.8, 0.95, 1.0);
uniform float specular_strength : hint_range(0.0, 1.0) = 0.18;
uniform float specular_size : hint_range(1.0, 128.0) = 40.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.1;
uniform float emission_strength : hint_range(0.0, 4.0) = 0.0;
uniform vec4 emission_color : source_color = vec4(0.0);

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 planar_uv() {
	vec3 n = abs(world_nrm);
	if (n.y > n.x && n.y > n.z) {
		return world_pos.xz * world_uv_scale;
	} else if (n.x > n.z) {
		return world_pos.zy * world_uv_scale;
	}
	return world_pos.xy * world_uv_scale;
}

void fragment() {
	vec2 uv = world_uv ? planar_uv() : UV;
	vec3 base = albedo.rgb * texture(albedo_tex, uv).rgb;
	ALBEDO = base;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	EMISSION = emission_color.rgb * emission_strength;
	float rim = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	EMISSION += base * pow(rim, 3.0) * rim_strength;
}

void light() {
	vec3 n = normalize(NORMAL);
	vec3 l = normalize(LIGHT);
	float ndl = dot(n, l) * ATTENUATION;
	float band1 = smoothstep(band_edge - band_softness, band_edge + band_softness, ndl);
	float band2 = smoothstep(mid_edge - band_softness, mid_edge + band_softness, ndl);
	float shade = mix(shadow_brightness, mix(mid_brightness, 1.0, band2), band1);
	vec3 tint = mix(shadow_tint.rgb, vec3(1.0), band1);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * shade * tint / PI;
	// One crisp highlight per light, stepped so it stays graphic.
	vec3 h = normalize(l + normalize(VIEW));
	float spec = pow(max(dot(n, h), 0.0), specular_size) * ATTENUATION;
	spec = smoothstep(0.35, 0.5, spec) * specular_strength;
	SPECULAR_LIGHT += LIGHT_COLOR * spec;
}

shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// Two-band cel shading with a soft rim. Flat palette colours, no speculars.
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_nearest;
uniform float band_edge : hint_range(0.0, 1.0) = 0.42;
uniform float band_softness : hint_range(0.0, 0.3) = 0.04;
uniform float shadow_brightness : hint_range(0.0, 1.0) = 0.62;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.12;
uniform float emission_strength : hint_range(0.0, 4.0) = 0.0;
uniform vec4 emission_color : source_color = vec4(0.0);

void fragment() {
	vec3 base = albedo.rgb * texture(albedo_tex, UV).rgb;
	ALBEDO = base;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	EMISSION = emission_color.rgb * emission_strength;
	// Rim: a little lift on silhouettes so characters read against the walls.
	float rim = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	EMISSION += base * pow(rim, 3.0) * rim_strength;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT)) * ATTENUATION;
	float band = smoothstep(band_edge - band_softness, band_edge + band_softness, ndl);
	float shade = mix(shadow_brightness, 1.0, band);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * shade / PI;
}

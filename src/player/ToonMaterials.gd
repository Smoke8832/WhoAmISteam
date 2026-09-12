class_name ToonMaterials
extends RefCounted
## Factory for the cel-shaded look. Converts imported StandardMaterial3D surfaces into toon
## ShaderMaterials (keeping their colours) and builds pattern textures for shirts.

const TOON_SHADER := preload("res://src/shaders/toon.gdshader")

static var _pattern_cache: Dictionary = {}


static func make(color: Color, tex: Texture2D = null, emission: Color = Color.BLACK, emission_strength: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER
	m.set_shader_parameter("albedo", color)
	if tex:
		m.set_shader_parameter("albedo_tex", tex)
	if emission_strength > 0.0:
		m.set_shader_parameter("emission_color", emission)
		m.set_shader_parameter("emission_strength", emission_strength)
	return m


## Replace every StandardMaterial3D under `node` with a toon material of the same colour.
static func convert(node: Node) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		_convert_mesh(mi as MeshInstance3D)
	if node is MeshInstance3D:
		_convert_mesh(node as MeshInstance3D)


static func _convert_mesh(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	if mi.material_override is StandardMaterial3D:
		mi.material_override = _from_standard(mi.material_override as StandardMaterial3D)
		return
	if mi.material_override is ShaderMaterial:
		return
	for s in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(s)
		if mat is StandardMaterial3D:
			mi.set_surface_override_material(s, _from_standard(mat as StandardMaterial3D))


static func _from_standard(sm: StandardMaterial3D) -> Material:
	# Keep transparent materials (glass, decals) as they are; toon shader is opaque.
	if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return sm
	var em_strength := sm.emission_energy_multiplier if sm.emission_enabled else 0.0
	return make(sm.albedo_color, sm.albedo_texture, sm.emission, em_strength)


## Shirt patterns. kind: 0 plain (returns null), 1 stripes, 2 dots.
static func pattern_texture(kind: int, accent: Color) -> Texture2D:
	if kind <= 0:
		return null
	var key := "%d_%s" % [kind, accent.to_html(false)]
	if _pattern_cache.has(key):
		return _pattern_cache[key]
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var acc := accent
	for y in size:
		for x in size:
			var on := false
			match kind:
				1:
					on = int(floor(float(y) / 8.0)) % 2 == 0
				2:
					var cx := (x % 16) - 8
					var cy := (y % 16) - 8
					on = cx * cx + cy * cy < 12
			if on:
				img.set_pixel(x, y, acc)
	var tex := ImageTexture.create_from_image(img)
	_pattern_cache[key] = tex
	return tex


# ------------------------------------------------------------------ room surfaces

static var _surface_cache: Dictionary = {}


## Toon material that samples a texture by world position (seamless across boxes).
static func make_world(color: Color, tex: Texture2D, metres_per_tile: float) -> ShaderMaterial:
	var m := make(color, tex)
	m.set_shader_parameter("world_uv", true)
	m.set_shader_parameter("world_uv_scale", 1.0 / metres_per_tile)
	return m


## Wooden planks: warm grain, slightly different tone per plank, thin dark seams.
static func plank_texture() -> Texture2D:
	if _surface_cache.has("planks"):
		return _surface_cache["planks"]
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.03
	noise.fractal_octaves = 3
	var planks := 6
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var plank_tone: Array[float] = []
	var plank_offset: Array[int] = []
	for i in planks:
		plank_tone.append(rng.randf_range(-0.07, 0.07))
		plank_offset.append(rng.randi_range(0, size - 1))
	var pw := size / planks
	for y in size:
		for x in size:
			var p := mini(int(x / pw), planks - 1)
			var grain := noise.get_noise_2d(float(x) * 6.0, float(y) + float(plank_offset[p])) * 0.5 + 0.5
			var v := 0.9 + plank_tone[p] + (grain - 0.5) * 0.12
			# Seams between planks and end joints every half texture (staggered per plank).
			var seam := x % pw < 2 or (y + plank_offset[p]) % (size / 2) < 2
			if seam:
				v *= 0.7
			img.set_pixel(x, y, Color(v, v * 0.97, v * 0.93))
	var tex := ImageTexture.create_from_image(img)
	_surface_cache["planks"] = tex
	return tex


## Wallpaper: soft mottled paper with a faint diamond pattern so the walls are not flat.
static func wallpaper_texture() -> Texture2D:
	if _surface_cache.has("wallpaper"):
		return _surface_cache["wallpaper"]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 0.08
	for y in size:
		for x in size:
			var mottle := noise.get_noise_2d(float(x), float(y)) * 0.03
			var dx := absf(float(x % 64) - 32.0) / 32.0
			var dy := absf(float(y % 64) - 32.0) / 32.0
			var diamond := 1.0 - smoothstep(0.02, 0.06, absf(dx + dy - 1.0))
			var v := 0.97 + mottle - diamond * 0.018
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_surface_cache["wallpaper"] = tex
	return tex

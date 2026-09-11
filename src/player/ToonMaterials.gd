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

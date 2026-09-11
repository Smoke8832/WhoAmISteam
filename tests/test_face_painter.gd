extends TestCase


func test_texture_size_and_content() -> void:
	var tex := FacePainter.texture(1, 0, 0, 1, false)
	assert_eq(tex.get_width(), FacePainter.SIZE)
	assert_eq(tex.get_height(), FacePainter.SIZE)
	var img := tex.get_image()
	var opaque := 0
	for y in range(0, FacePainter.SIZE, 2):
		for x in range(0, FacePainter.SIZE, 2):
			if img.get_pixel(x, y).a > 0.5:
				opaque += 1
	assert_true(opaque > 50, "face has painted pixels (%d)" % opaque)
	assert_true(opaque < 3000, "face is mostly transparent (%d)" % opaque)


func test_cache_returns_same_texture() -> void:
	var a := FacePainter.texture(0, 1, 2, 0, false)
	var b := FacePainter.texture(0, 1, 2, 0, false)
	assert_true(a == b, "cached texture reused")
	var c := FacePainter.texture(0, 1, 2, 0, true)
	assert_true(a != c, "open mouth is a different texture")


func test_all_styles_paint_without_error() -> void:
	for eyes in Customization.OPTIONS.eyes:
		for brows in Customization.OPTIONS.brows:
			var tex := FacePainter.texture(eyes, brows, eyes % Customization.OPTIONS.mouth, eyes % 2, false)
			assert_true(tex != null, "eyes %d brows %d" % [eyes, brows])

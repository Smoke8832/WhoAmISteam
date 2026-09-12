extends TestCase


func _make_png(w: int, h: int) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color(float(x) / w, float(y) / h, 0.5))
	return img.save_png_to_buffer()


func test_detect_and_header_png() -> void:
	var png := _make_png(300, 120)
	assert_eq(ImageNormalize.detect_format(png), "png")
	assert_eq(ImageNormalize.header_size(png), Vector2i(300, 120))


func test_detect_and_header_jpg() -> void:
	var img := Image.create(640, 360, false, Image.FORMAT_RGB8)
	img.fill(Color.ORANGE)
	var jpg := img.save_jpg_to_buffer(0.8)
	assert_eq(ImageNormalize.detect_format(jpg), "jpg")
	assert_eq(ImageNormalize.header_size(jpg), Vector2i(640, 360))


func test_normalize_makes_square_jpeg_under_limit() -> void:
	var out := ImageNormalize.normalize(_make_png(900, 500))
	assert_true(out.size() > 0, "normalized bytes")
	assert_true(out.size() <= ImageNormalize.MAX_BYTES, "under size limit (%d)" % out.size())
	assert_eq(ImageNormalize.detect_format(out), "jpg")
	assert_eq(ImageNormalize.header_size(out), Vector2i(512, 512))
	var back := ImageNormalize.decode_wire(out)
	assert_true(back != null and back.get_width() == 512, "wire decode ok")


func test_rejects_garbage_and_wrong_wire_format() -> void:
	var garbage := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])
	assert_eq(ImageNormalize.normalize(garbage).size(), 0, "garbage rejected")
	assert_eq(ImageNormalize.decode_wire(_make_png(64, 64)), null, "png not allowed on the wire")
	var exe := "MZ".to_utf8_buffer()
	exe.resize(64)
	assert_eq(ImageNormalize.detect_format(exe), "", "exe is not an image")


func test_rejects_decompression_bomb_by_header() -> void:
	# A PNG header claiming 20000 x 20000 with no real data: must be rejected before decoding.
	var png := _make_png(8, 8)
	png[16] = 0x00; png[17] = 0x00; png[18] = 0x4E; png[19] = 0x20   # width 20000
	png[20] = 0x00; png[21] = 0x00; png[22] = 0x4E; png[23] = 0x20   # height 20000
	assert_eq(ImageNormalize.header_size(png), Vector2i(20000, 20000))
	assert_eq(ImageNormalize.normalize(png).size(), 0, "bomb rejected")


func test_wire_dimension_limit() -> void:
	var img := Image.create(1500, 1500, false, Image.FORMAT_RGB8)
	img.fill(Color.RED)
	var jpg := img.save_jpg_to_buffer(0.3)
	assert_eq(ImageNormalize.decode_wire(jpg), null, "1500px jpeg rejected on the wire")


func test_normalize_rgba_and_grayscale_sources() -> void:
	var rgba := Image.create(200, 300, false, Image.FORMAT_RGBA8)
	rgba.fill(Color(0.2, 0.4, 0.8, 0.5))
	var out := ImageNormalize.normalize(rgba.save_png_to_buffer())
	assert_eq(ImageNormalize.header_size(out), Vector2i(512, 512), "rgba png normalized")
	var gray := Image.create(300, 200, false, Image.FORMAT_L8)
	gray.fill(Color(0.5, 0.5, 0.5))
	var out2 := ImageNormalize.normalize(gray.save_png_to_buffer())
	assert_eq(ImageNormalize.header_size(out2), Vector2i(512, 512), "grayscale png normalized")
	var webp := rgba.save_webp_to_buffer()
	if not webp.is_empty():
		assert_eq(ImageNormalize.detect_format(webp), "webp")
		assert_eq(ImageNormalize.header_size(webp), Vector2i(200, 300), "webp header")
		assert_eq(ImageNormalize.header_size(ImageNormalize.normalize(webp)), Vector2i(512, 512), "webp normalized")


func test_chunks() -> void:
	var data := PackedByteArray()
	data.resize(ImageNormalize.CHUNK_SIZE * 2 + 10)
	var chunks := ImageNormalize.split_chunks(data)
	assert_eq(chunks.size(), 3)
	assert_eq((chunks[2] as PackedByteArray).size(), 10)
	assert_true(ImageNormalize.MAX_CHUNKS * ImageNormalize.CHUNK_SIZE >= ImageNormalize.MAX_BYTES, "max chunks cover max bytes")

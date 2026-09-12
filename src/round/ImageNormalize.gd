class_name ImageNormalize
extends RefCounted
## Turns any picture into the one thing allowed on the wire: a small square JPEG.
## Header dimensions are checked BEFORE decoding so decompression bombs never reach the decoder.

const TARGET := 512
const FALLBACK_TARGET := 384
const MAX_BYTES := 200 * 1024
const MAX_SOURCE_DIM := 4096      # for files the local player picked
const MAX_WIRE_DIM := 1024        # for bytes received from the network
const CHUNK_SIZE := 16 * 1024
const MAX_CHUNKS := 13
const QUALITIES := [0.8, 0.7, 0.6]


## "jpg" | "png" | "webp" | "" from the magic bytes.
static func detect_format(bytes: PackedByteArray) -> String:
	if bytes.size() < 12:
		return ""
	if bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF:
		return "jpg"
	if bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		return "png"
	if bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		return "webp"
	return ""


## Width/height from the container header without decoding. (0,0) if unknown.
static func header_size(bytes: PackedByteArray) -> Vector2i:
	match detect_format(bytes):
		"png":
			if bytes.size() >= 24:
				return Vector2i(_be32(bytes, 16), _be32(bytes, 20))
		"jpg":
			return _jpeg_size(bytes)
		"webp":
			return _webp_size(bytes)
	return Vector2i.ZERO


static func _be32(b: PackedByteArray, o: int) -> int:
	return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]


static func _be16(b: PackedByteArray, o: int) -> int:
	return (b[o] << 8) | b[o + 1]


static func _jpeg_size(b: PackedByteArray) -> Vector2i:
	var i := 2
	var n := b.size()
	while i + 9 < n:
		if b[i] != 0xFF:
			i += 1
			continue
		var marker := b[i + 1]
		if marker == 0xFF:
			i += 1
			continue
		if marker == 0xD8 or (marker >= 0xD0 and marker <= 0xD7) or marker == 0x01:
			i += 2
			continue
		var seg_len := _be16(b, i + 2)
		# SOF0..SOF15 except DHT(C4), JPG(C8), DAC(CC)
		if marker >= 0xC0 and marker <= 0xCF and marker != 0xC4 and marker != 0xC8 and marker != 0xCC:
			if i + 9 <= n:
				return Vector2i(_be16(b, i + 7), _be16(b, i + 5))
			return Vector2i.ZERO
		if marker == 0xDA:  # start of scan: no SOF before it
			return Vector2i.ZERO
		i += 2 + seg_len
	return Vector2i.ZERO


static func _webp_size(b: PackedByteArray) -> Vector2i:
	if b.size() < 30:
		return Vector2i.ZERO
	var chunk := b.slice(12, 16).get_string_from_ascii()
	match chunk:
		"VP8 ":
			return Vector2i((b[26] | (b[27] << 8)) & 0x3FFF, (b[28] | (b[29] << 8)) & 0x3FFF)
		"VP8L":
			var bits := b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24)
			return Vector2i((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
		"VP8X":
			var w := (b[24] | (b[25] << 8) | (b[26] << 16)) + 1
			var h := (b[27] | (b[28] << 8) | (b[29] << 16)) + 1
			return Vector2i(w, h)
	return Vector2i.ZERO


## Decode (any supported format) after header checks. Null on failure.
static func decode(bytes: PackedByteArray, max_dim: int) -> Image:
	var fmt := detect_format(bytes)
	if fmt == "":
		return null
	var size := header_size(bytes)
	if size.x <= 0 or size.y <= 0 or size.x > max_dim or size.y > max_dim:
		return null
	var img := Image.new()
	var err := ERR_INVALID_DATA
	match fmt:
		"jpg":
			err = img.load_jpg_from_buffer(bytes)
		"png":
			err = img.load_png_from_buffer(bytes)
		"webp":
			err = img.load_webp_from_buffer(bytes)
	if err != OK or img.is_empty():
		return null
	if img.get_width() > max_dim or img.get_height() > max_dim:
		return null
	return img


## File or download from the local player -> wire JPEG. Empty array on failure.
static func normalize(bytes: PackedByteArray, max_source_dim: int = MAX_SOURCE_DIM) -> PackedByteArray:
	var img := decode(bytes, max_source_dim)
	if img == null:
		return PackedByteArray()
	return encode_square(img)


## Center-crop to a square, resize, encode JPEG under MAX_BYTES.
static func encode_square(img: Image, target: int = TARGET) -> PackedByteArray:
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)   # drop alpha; the crop target is RGB8
	var w := img.get_width()
	var h := img.get_height()
	var side := mini(w, h)
	var crop := Image.create(side, side, false, Image.FORMAT_RGB8)
	crop.blit_rect(img, Rect2i((w - side) / 2, (h - side) / 2, side, side), Vector2i.ZERO)
	crop.resize(target, target, Image.INTERPOLATE_LANCZOS)
	for q in QUALITIES:
		var out := crop.save_jpg_to_buffer(float(q))
		if out.size() <= MAX_BYTES:
			return out
	if target > FALLBACK_TARGET:
		return encode_square(crop, FALLBACK_TARGET)
	return PackedByteArray()


## Bytes received from the network: JPEG only, header-checked, decoded. Null on failure.
static func decode_wire(bytes: PackedByteArray) -> Image:
	if bytes.size() > MAX_BYTES or detect_format(bytes) != "jpg":
		return null
	return decode(bytes, MAX_WIRE_DIM)


static func split_chunks(bytes: PackedByteArray) -> Array:
	var out: Array = []
	var i := 0
	while i < bytes.size():
		out.append(bytes.slice(i, mini(i + CHUNK_SIZE, bytes.size())))
		i += CHUNK_SIZE
	return out


static func texture_from_wire(bytes: PackedByteArray) -> ImageTexture:
	var img := decode_wire(bytes)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)

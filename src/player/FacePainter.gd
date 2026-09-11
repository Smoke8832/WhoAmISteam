class_name FacePainter
extends RefCounted
## Paints cartoon faces into small transparent textures using signed-distance shapes.
## Options match Customization: eyes (6), brows (4), mouth (4), blush (2), open mouth (talking).

const SIZE := 128
const INK := Color("1c1a17")
const WHITE := Color("fbfbf8")
const BLUSH := Color(0.95, 0.45, 0.5, 0.55)
const TEETH := Color("f4f1ea")
const MOUTH_IN := Color("7a2a2a")
const TONGUE := Color("e06c7c")

static var _cache: Dictionary = {}


static func texture(eyes: int, brows: int, mouth: int, blush: int, open: bool = false) -> ImageTexture:
	var key := "%d_%d_%d_%d_%d" % [eyes, brows, mouth, blush, 1 if open else 0]
	if _cache.has(key):
		return _cache[key]
	var img := paint(eyes, brows, mouth, blush, open)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func paint(eyes: int, brows: int, mouth: int, blush: int, open: bool) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Coordinates are in a 0..1 face space; y grows downward.
	for py in SIZE:
		for px in SIZE:
			var p := Vector2((px + 0.5) / SIZE, (py + 0.5) / SIZE)
			var c := _shade(p, eyes, brows, mouth, blush, open)
			if c.a > 0.001:
				img.set_pixel(px, py, c)
	return img


static func _shade(p: Vector2, eyes: int, brows: int, mouth: int, blush: int, open: bool) -> Color:
	var out := Color(0, 0, 0, 0)
	# blush (drawn first, under everything)
	if blush == 1:
		for sx in [-1.0, 1.0]:
			var d := _sd_ellipse(p - Vector2(0.5 + sx * 0.26, 0.56), Vector2(0.075, 0.045))
			if d < 0.0:
				out = _over(out, Color(BLUSH.r, BLUSH.g, BLUSH.b, BLUSH.a * clampf(-d / 0.03, 0.0, 1.0)))
	# eyes
	for sx in [-1.0, 1.0]:
		var center := Vector2(0.5 + sx * 0.16, 0.42)
		out = _over(out, _eye(p, center, eyes, sx))
	# brows
	for sx in [-1.0, 1.0]:
		out = _over(out, _brow(p, Vector2(0.5 + sx * 0.16, 0.31), brows, sx))
	# mouth
	out = _over(out, _mouth(p, Vector2(0.5, 0.68), mouth, open))
	return out


static func _eye(p: Vector2, c: Vector2, style: int, side: float) -> Color:
	var col := Color(0, 0, 0, 0)
	match style:
		0:  # dots
			col = _fill(_sd_circle(p - c, 0.035), INK)
		1:  # big round with whites
			col = _fill(_sd_circle(p - c, 0.075), WHITE)
			col = _over(col, _fill(_sd_circle(p - c - Vector2(0.012 * side, 0.01), 0.038), INK))
			col = _over(col, _fill(_sd_circle(p - c - Vector2(0.022 * side, -0.012), 0.012), WHITE))
		2:  # sleepy half-closed
			var d := _sd_ellipse(p - c, Vector2(0.07, 0.03))
			col = _fill(d, INK)
			col = _over(col, _fill(_sd_box(p - c + Vector2(0, 0.03), Vector2(0.08, 0.03)), Color(0, 0, 0, 0), true))
		3:  # wink (left open, right closed)
			if side < 0.0:
				col = _fill(_sd_circle(p - c, 0.06), WHITE)
				col = _over(col, _fill(_sd_circle(p - c, 0.03), INK))
			else:
				col = _fill(_sd_segment(p, c - Vector2(0.06, 0.0), c + Vector2(0.06, 0.0)) - 0.012, INK)
		4:  # angry slanted
			var q := p - c
			var slanted := Vector2(q.x, q.y + q.x * 0.5 * side)
			col = _fill(_sd_ellipse(slanted, Vector2(0.065, 0.04)), WHITE)
			col = _over(col, _fill(_sd_circle(slanted, 0.028), INK))
		_:  # 5 stars
			col = _fill(_sd_star(p - c, 0.06), INK)
	return col


static func _brow(p: Vector2, c: Vector2, style: int, side: float) -> Color:
	match style:
		0:  # flat
			return _fill(_sd_segment(p, c - Vector2(0.07, 0.0), c + Vector2(0.07, 0.0)) - 0.014, INK)
		1:  # raised arch
			return _fill(_sd_segment(p, c + Vector2(-0.07 * side, 0.01), c + Vector2(0.07 * side, -0.02)) - 0.014, INK)
		2:  # angry (inner end down)
			return _fill(_sd_segment(p, c + Vector2(-0.07 * side, -0.015), c + Vector2(0.07 * side, 0.02)) - 0.016, INK)
		_:  # thick
			return _fill(_sd_box(p - c, Vector2(0.08, 0.02)), INK)


static func _mouth(p: Vector2, c: Vector2, style: int, open: bool) -> Color:
	var col := Color(0, 0, 0, 0)
	if open:
		var d := _sd_ellipse(p - c - Vector2(0, 0.02), Vector2(0.09, 0.07))
		col = _fill(d, MOUTH_IN)
		col = _over(col, _fill(_sd_ellipse(p - c - Vector2(0, 0.06), Vector2(0.05, 0.03)), TONGUE))
		col = _over(col, _fill(_sd_box(p - c + Vector2(0, 0.03), Vector2(0.07, 0.015)), TEETH))
		col = _over(col, _fill(absf(d) - 0.012, INK))
		return col
	match style:
		0:  # smile
			var q := p - c
			var d := absf(_sd_circle(q - Vector2(0, -0.06), 0.13)) - 0.014
			if q.y < 0.0 + 0.0:
				d = 1.0
			col = _fill(d, INK)
		1:  # grin with teeth
			var q := p - c
			var d := _sd_circle(q - Vector2(0, -0.05), 0.12)
			var cut := q.y < 0.0
			if not cut:
				col = _fill(d, TEETH)
				col = _over(col, _fill(absf(d) - 0.012, INK))
				col = _over(col, _fill(_sd_box(q - Vector2(0, 0.01), Vector2(0.12, 0.006)), INK))
		2:  # flat
			col = _fill(_sd_segment(p, c - Vector2(0.08, 0.0), c + Vector2(0.08, 0.0)) - 0.014, INK)
		_:  # small o
			col = _fill(_sd_circle(p - c, 0.035), MOUTH_IN)
			col = _over(col, _fill(absf(_sd_circle(p - c, 0.035)) - 0.01, INK))
	return col


# ---------------------------------------------------------------- SDF helpers

static func _sd_circle(q: Vector2, r: float) -> float:
	return q.length() - r


static func _sd_ellipse(q: Vector2, ab: Vector2) -> float:
	var k := Vector2(q.x / ab.x, q.y / ab.y).length()
	return (k - 1.0) * minf(ab.x, ab.y)


static func _sd_box(q: Vector2, b: Vector2) -> float:
	var d := Vector2(absf(q.x) - b.x, absf(q.y) - b.y)
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0)


static func _sd_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
	return (pa - ba * h).length()


static func _sd_star(q: Vector2, r: float) -> float:
	# 5-point star approximation: union of 5 thin diamonds.
	var d := 10.0
	for i in 5:
		var ang := i * TAU / 5.0 - PI / 2.0
		var dir := Vector2(cos(ang), sin(ang))
		var along := q.dot(dir)
		var perp := absf(q.dot(Vector2(-dir.y, dir.x)))
		var w := lerpf(0.02, 0.0, clampf(along / r, 0.0, 1.0))
		var sd := maxf(perp - w, maxf(-along - 0.02, along - r))
		d = minf(d, sd)
	return d


static func _fill(d: float, color: Color, erase: bool = false) -> Color:
	var aa := 1.0 / SIZE
	var a := clampf(0.5 - d / aa, 0.0, 1.0)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	if erase:
		return Color(0, 0, 0, -a)  # negative alpha marks erase in _over
	return Color(color.r, color.g, color.b, color.a * a)


static func _over(base: Color, top: Color) -> Color:
	if top.a < 0.0:
		var keep := 1.0 + top.a
		return Color(base.r, base.g, base.b, base.a * keep)
	if top.a <= 0.0:
		return base
	var a := top.a + base.a * (1.0 - top.a)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var rgb := (Color(top.r, top.g, top.b) * top.a + Color(base.r, base.g, base.b) * base.a * (1.0 - top.a)) / a
	return Color(rgb.r, rgb.g, rgb.b, a)

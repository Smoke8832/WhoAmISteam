class_name Customization
extends RefCounted
## Character customization data: a small dictionary of ints (indices into option tables).
## Saved locally (user://character.cfg), sent to the host on hello(), validated by sanitize().

const PATH := "user://character.cfg"

## key -> option count (indices are 0..count-1)
const OPTIONS := {
	"skin": 12,
	"head": 3,
	"hair": 8,
	"hair_color": 10,
	"facial_hair": 5,
	"eyes": 6,
	"brows": 4,
	"mouth": 4,
	"blush": 2,
	"shirt": 16,
	"pattern": 3,
	"pants": 8,
	"shoes": 6,
	"accessory": 8,   # 0 none, 1-3 glasses, 4 headset, 5 cap, 6 beanie, 7 bow
}

const SKIN_COLORS := [
	Color("f9dcc4"), Color("f1c27d"), Color("e0ac69"), Color("c68642"), Color("8d5524"), Color("5c3a1e"),
	Color("ffd6c9"), Color("d9a066"), Color("a56a3a"), Color("6e4527"), Color("f2b8a0"), Color("4a2d17"),
]
const HAIR_COLORS := [
	Color("1c1a17"), Color("3b2a1a"), Color("6b4a2b"), Color("a8763e"), Color("d9b36a"), Color("e8dcb5"),
	Color("b5352c"), Color("e26a2c"), Color("8e8e8e"), Color("4d6fd1"),
]
const SHIRT_COLORS := [
	Color("2ec4b6"), Color("e0523e"), Color("ffe14d"), Color("3fa66b"), Color("4d6fd1"), Color("9b5de5"),
	Color("f15bb5"), Color("ff9f1c"), Color("1c1a17"), Color("f5f3ec"), Color("6c757d"), Color("00a6fb"),
	Color("b5e48c"), Color("ffcad4"), Color("7f5539"), Color("c9184a"),
]
const PANTS_COLORS := [
	Color("2b3a55"), Color("1c1a17"), Color("6c757d"), Color("8d6e63"), Color("3fa66b"), Color("b5352c"), Color("f5f3ec"), Color("4d6fd1"),
]
const SHOE_COLORS := [
	Color("1c1a17"), Color("f5f3ec"), Color("e0523e"), Color("4d6fd1"), Color("7f5539"), Color("ffe14d"),
]

static var _cached: Dictionary = {}


static func defaults() -> Dictionary:
	var d := {}
	for key in OPTIONS.keys():
		d[key] = 0
	d.skin = 1
	d.hair = 1
	d.shirt = 0
	d.pants = 0
	return d


static func sanitize(input) -> Dictionary:
	var out := defaults()
	if typeof(input) != TYPE_DICTIONARY:
		return out
	for key in OPTIONS.keys():
		if input.has(key):
			var v = input[key]
			if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
				out[key] = clampi(int(v), 0, int(OPTIONS[key]) - 1)
	return out


static func randomized() -> Dictionary:
	var d := {}
	for key in OPTIONS.keys():
		d[key] = randi() % int(OPTIONS[key])
	d.blush = 1 if randf() < 0.3 else 0
	d.facial_hair = randi() % 5 if randf() < 0.4 else 0
	d.accessory = randi() % 8 if randf() < 0.5 else 0
	return d


static func local() -> Dictionary:
	if not _cached.is_empty():
		return _cached
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		var raw := {}
		for key in OPTIONS.keys():
			raw[key] = cfg.get_value("character", key, 0)
		_cached = sanitize(raw)
	else:
		_cached = randomized()
		save_local(_cached)
	return _cached


static func save_local(data: Dictionary) -> void:
	_cached = sanitize(data)
	var cfg := ConfigFile.new()
	for key in _cached.keys():
		cfg.set_value("character", key, _cached[key])
	cfg.save(PATH)

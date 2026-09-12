class_name FamousNames
extends RefCounted
## Fallback names for writers who ran out of time. Loaded from assets/data/famous_names.json
## (list of {"name": ..., "wiki": ...}); a small built-in list covers a missing file.

const PATH := "res://assets/data/famous_names.json"
const BUILTIN := [
	{"name": "Michael Jackson", "wiki": "Michael Jackson"},
	{"name": "Albert Einstein", "wiki": "Albert Einstein"},
	{"name": "Beyoncé", "wiki": "Beyoncé"},
	{"name": "Leonardo da Vinci", "wiki": "Leonardo da Vinci"},
	{"name": "Frida Kahlo", "wiki": "Frida Kahlo"},
	{"name": "Elvis Presley", "wiki": "Elvis Presley"},
	{"name": "Marie Curie", "wiki": "Marie Curie"},
	{"name": "Bruce Lee", "wiki": "Bruce Lee"},
]

static var _cache: Array = []


static func all() -> Array:
	if not _cache.is_empty():
		return _cache
	if FileAccess.file_exists(PATH):
		var txt := FileAccess.get_file_as_string(PATH)
		var parsed = JSON.parse_string(txt)
		if typeof(parsed) == TYPE_ARRAY and not parsed.is_empty():
			_cache = parsed
			return _cache
	_cache = BUILTIN.duplicate()
	return _cache


static func random_entry() -> Dictionary:
	var list := all()
	return list[randi() % list.size()]


static func random_name() -> String:
	return String(random_entry().name)

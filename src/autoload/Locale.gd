extends Node
## Sets the game language. Strings live in res://locale/strings.csv (imported to .translation files).
## English only at launch; the CSV is ready for more columns.

const SUPPORTED := ["en"]


func _ready() -> void:
	set_language("en")


func set_language(code: String) -> void:
	if code in SUPPORTED:
		TranslationServer.set_locale(code)


## Format helper: Locale.f("WRITE_FOR", {"name": "Sarah"}) -> "Write a name for Sarah".
func f(key: String, vars: Dictionary = {}) -> String:
	return tr(key).format(vars)

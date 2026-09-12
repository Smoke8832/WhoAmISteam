extends Control
## Options: audio, voice input, mouse, Wikipedia language, optional Google image search key.
## Everything is local (user://settings.cfg); nothing here is sent to other players.

signal closed

const INK := Color("1c1a17")

@onready var rows: VBoxContainer = %Rows
@onready var close_button: Button = %CloseButton
@onready var howto_button: Button = %HowtoButton

var _controls: Dictionary = {}


func _ready() -> void:
	_slider("master_volume", tr("OPT_MASTER"), 0.0, 1.0, 0.05)
	_slider("sfx_volume", tr("OPT_SFX"), 0.0, 1.0, 0.05)
	_slider("music_volume", tr("OPT_MUSIC"), 0.0, 1.0, 0.05)
	_slider("voice_volume", tr("OPT_VOICE_VOL"), 0.0, 1.0, 0.05)
	_option("voice_mode", tr("OPT_VOICE_MODE"), ["ptt", "open"], [tr("OPT_PTT"), tr("OPT_OPEN_MIC")])
	_slider("mic_gate", tr("OPT_MIC_GATE"), 0.0, 0.2, 0.005)
	_slider("mouse_sensitivity", tr("OPT_MOUSE"), 0.0005, 0.008, 0.0001)
	_toggle("invert_y", tr("OPT_INVERT_Y"))
	_option("wiki_lang", tr("OPT_WIKI_LANG"), ImageSearch.WIKI_LANGS, ImageSearch.WIKI_LANGS.map(func(l): return String(l).to_upper()))
	_text("google_api_key", tr("OPT_GOOGLE_KEY"), true)
	_text("google_cx", tr("OPT_GOOGLE_CX"), false)
	var note := Label.new()
	note.text = tr("OPT_GOOGLE_NOTE")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(520, 0)
	note.add_theme_color_override("font_color", Color(0.4, 0.38, 0.35))
	note.add_theme_font_size_override("font_size", 13)
	rows.add_child(note)
	close_button.pressed.connect(_close)
	howto_button.pressed.connect(func(): Settings.set_value("first_launch", true); _close())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		_close()
		get_viewport().set_input_as_handled()


func _row(label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(220, 0)
	label.add_theme_color_override("font_color", INK)
	row.add_child(label)
	control.custom_minimum_size = Vector2(300, 0)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	rows.add_child(row)


func _slider(key: String, label_text: String, lo: float, hi: float, step: float) -> void:
	var box := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = float(Settings.get_value(key, lo))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := Label.new()
	value.custom_minimum_size = Vector2(60, 0)
	value.add_theme_color_override("font_color", INK)
	value.text = _fmt(key, slider.value)
	slider.value_changed.connect(func(v):
		value.text = _fmt(key, v)
		Settings.set_value(key, v)
		if key == "sfx_volume":
			Audio.play("ui_click"))
	box.add_child(slider)
	box.add_child(value)
	_row(label_text, box)
	_controls[key] = slider


func _fmt(key: String, v: float) -> String:
	if key == "mouse_sensitivity":
		return "%.1f" % (v * 1000.0)
	if key == "mic_gate":
		return "%.3f" % v
	return "%d%%" % int(round(v * 100.0))


func _toggle(key: String, label_text: String) -> void:
	var cb := CheckButton.new()
	cb.button_pressed = bool(Settings.get_value(key, false))
	cb.toggled.connect(func(on): Settings.set_value(key, on))
	_row(label_text, cb)
	_controls[key] = cb


func _option(key: String, label_text: String, values: Array, labels: Array) -> void:
	var ob := OptionButton.new()
	for l in labels:
		ob.add_item(String(l))
	ob.selected = maxi(0, values.find(Settings.get_value(key, values[0])))
	ob.item_selected.connect(func(i): Settings.set_value(key, values[i]))
	_row(label_text, ob)
	_controls[key] = ob


func _text(key: String, label_text: String, secret: bool) -> void:
	var le := LineEdit.new()
	le.text = String(Settings.get_value(key, ""))
	le.secret = secret
	le.placeholder_text = tr("OPT_OPTIONAL")
	le.text_changed.connect(func(t): Settings.set_value(key, t.strip_edges()))
	_row(label_text, le)
	_controls[key] = le


func _close() -> void:
	closed.emit()
	queue_free()

extends Control
## Room settings. Editable by the admin in the lobby; read-only for everyone else.

signal closed

const INK := Color("1c1a17")

var _controls: Dictionary = {}
var _editable := false

@onready var rows: VBoxContainer = %Rows
@onready var apply_button: Button = %ApplyButton
@onready var close_button: Button = %CloseButton
@onready var hint: Label = %Hint


func _ready() -> void:
	_editable = Game.is_admin() and Game.state == Game.State.LOBBY
	_build()
	apply_button.visible = _editable
	apply_button.pressed.connect(_on_apply)
	close_button.pressed.connect(_close)
	hint.text = tr("SETTINGS_HINT_ADMIN") if _editable else tr("SETTINGS_HINT_READONLY")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		_close()
		get_viewport().set_input_as_handled()


func _row(key: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = tr("SET_" + key.to_upper())
	label.custom_minimum_size = Vector2(220, 0)
	label.add_theme_color_override("font_color", INK)
	row.add_child(label)
	control.custom_minimum_size = Vector2(260, 0)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	rows.add_child(row)
	_controls[key] = control


func _slider(key: String, suffix: String) -> void:
	var spec: Array = LobbySettings.NUMERIC[key]
	var box := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = spec[1]
	slider.max_value = spec[2]
	slider.step = 1
	slider.value = int(Game.settings[key])
	slider.editable = _editable
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := Label.new()
	value.custom_minimum_size = Vector2(70, 0)
	value.add_theme_color_override("font_color", INK)
	value.text = "%d%s" % [int(slider.value), suffix]
	slider.value_changed.connect(func(v): value.text = "%d%s" % [int(v), suffix])
	box.add_child(slider)
	box.add_child(value)
	box.set_meta("slider", slider)
	_row(key, box)


func _toggle(key: String) -> void:
	var cb := CheckButton.new()
	cb.button_pressed = bool(Game.settings[key])
	cb.disabled = not _editable
	_row(key, cb)


func _build() -> void:
	_slider("max_players", "")
	_toggle("voice_enabled")
	_slider("writing_time_s", " s")
	_slider("turn_timer_s", " s")
	var mode := OptionButton.new()
	for m in LobbySettings.ROUND_END_MODES:
		mode.add_item(tr("MODE_" + String(m).to_upper()))
	mode.selected = LobbySettings.ROUND_END_MODES.find(String(Game.settings.round_end_mode))
	mode.disabled = not _editable
	_row("round_end_mode", mode)
	_slider("round_time_min", " min")
	_slider("max_turns_per_player", "")
	_slider("answer_vote_window_s", " s")
	_slider("guess_vote_window_s", " s")


func collect() -> Dictionary:
	var out := Game.settings.duplicate()
	for key in _controls.keys():
		var c: Control = _controls[key]
		if c is HBoxContainer and c.has_meta("slider"):
			out[key] = int((c.get_meta("slider") as HSlider).value)
		elif c is CheckButton:
			out[key] = (c as CheckButton).button_pressed
		elif c is OptionButton:
			out[key] = LobbySettings.ROUND_END_MODES[(c as OptionButton).selected]
	return LobbySettings.sanitize(out)


func _on_apply() -> void:
	Game.update_settings_local(collect())
	Audio.play("ui_confirm")
	_close()


func _close() -> void:
	closed.emit()
	queue_free()

extends Control
## Esc menu while in a room.

signal closed
signal open_howto
signal open_settings

@onready var resume_button: Button = %ResumeButton
@onready var howto_button: Button = %HowtoButton
@onready var settings_button: Button = %SettingsButton
@onready var leave_button: Button = %LeaveButton
@onready var quit_button: Button = %QuitButton
@onready var address_label: Label = %AddressLabel


func _ready() -> void:
	resume_button.pressed.connect(_close)
	howto_button.pressed.connect(func(): open_howto.emit(); _close())
	settings_button.pressed.connect(func(): open_settings.emit(); _close())
	leave_button.pressed.connect(func(): Net.leave())
	quit_button.pressed.connect(func(): get_tree().quit())
	var addr := Net.join_address()
	address_label.text = Locale.f("PAUSE_ADDRESS", {"address": addr}) if addr != "" else ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	closed.emit()
	queue_free()

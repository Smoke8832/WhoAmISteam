extends Control
## Esc menu while in a room.

signal closed
signal open_howto
signal open_settings
signal open_options
signal open_invite

@onready var resume_button: Button = %ResumeButton
@onready var howto_button: Button = %HowtoButton
@onready var settings_button: Button = %SettingsButton
@onready var leave_button: Button = %LeaveButton
@onready var quit_button: Button = %QuitButton
@onready var address_label: Label = %AddressLabel
@onready var invite_button: Button = %InviteButton


func _ready() -> void:
	resume_button.pressed.connect(_close)
	invite_button.visible = Net.is_steam_session() and SteamService.lobby_id != 0
	invite_button.pressed.connect(func(): open_invite.emit(); _close())
	howto_button.pressed.connect(func(): open_howto.emit(); _close())
	settings_button.pressed.connect(func(): open_settings.emit(); _close())
	%OptionsButton.pressed.connect(func(): open_options.emit(); _close())
	leave_button.pressed.connect(func(): Net.leave())
	quit_button.pressed.connect(func(): get_tree().quit())
	var addr := Net.join_address()
	if Net.is_steam_session():
		address_label.text = tr("PAUSE_STEAM_HINT")
	else:
		address_label.text = Locale.f("PAUSE_ADDRESS", {"address": addr}) if addr != "" else ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	closed.emit()
	queue_free()

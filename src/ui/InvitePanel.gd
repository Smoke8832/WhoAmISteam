extends Control
## Invite Steam friends from inside the game. Works without the Steam overlay (which only
## exists when the game was launched through Steam): invites go through inviteUserToLobby,
## and the lobby id can be copied for friends to paste into the main menu's Join field.

signal closed

@onready var list: VBoxContainer = %List
@onready var empty_label: Label = %EmptyLabel
@onready var lobby_label: Label = %LobbyLabel
@onready var copy_button: Button = %CopyButton
@onready var overlay_button: Button = %OverlayButton
@onready var close_button: Button = %CloseButton
@onready var hint_label: Label = %HintLabel

var _invited: Dictionary = {}
var _refresh_in := 0.0


func _ready() -> void:
	close_button.pressed.connect(_close)
	copy_button.pressed.connect(_on_copy)
	overlay_button.pressed.connect(func(): SteamService.open_invite_dialog())
	overlay_button.visible = SteamService.overlay_enabled()
	hint_label.text = tr("INVITE_HINT") if overlay_button.visible else tr("INVITE_HINT_NO_OVERLAY")
	lobby_label.text = Locale.f("INVITE_LOBBY_ID", {"id": str(SteamService.lobby_id)})
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild()


func _process(delta: float) -> void:
	_refresh_in -= delta
	if _refresh_in <= 0.0:
		_refresh_in = 5.0
		_rebuild()


func _rebuild() -> void:
	for c in list.get_children():
		c.queue_free()
	var friends := SteamService.friends_online()
	empty_label.visible = friends.is_empty()
	for f in friends:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_label := Label.new()
		name_label.text = String(f.name)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		name_label.add_theme_color_override("font_color", Color(0.11, 0.1, 0.09))
		row.add_child(name_label)
		var state := Label.new()
		state.text = _state_text(f)
		state.add_theme_color_override("font_color", Color(0.35, 0.33, 0.3))
		state.custom_minimum_size.x = 110
		row.add_child(state)
		var btn := Button.new()
		var id := int(f.id)
		if _invited.has(id):
			btn.text = tr("INVITE_SENT")
			btn.disabled = true
		else:
			btn.text = tr("INVITE_SEND")
			btn.pressed.connect(func(): _invite(id, btn))
		btn.custom_minimum_size.x = 100
		row.add_child(btn)
		list.add_child(row)


func _state_text(f: Dictionary) -> String:
	if bool(f.in_game):
		return tr("INVITE_STATE_INGAME")
	return tr("INVITE_STATE_ONLINE") if int(f.state) == 1 else tr("INVITE_STATE_AWAY")


func _invite(id: int, btn: Button) -> void:
	if SteamService.invite_friend(id):
		_invited[id] = true
		btn.text = tr("INVITE_SENT")
		btn.disabled = true
		Audio.play("ui_confirm")
	else:
		btn.text = tr("INVITE_FAILED")


func _on_copy() -> void:
	DisplayServer.clipboard_set(str(SteamService.lobby_id))
	copy_button.text = tr("INVITE_COPIED")
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(copy_button):
		copy_button.text = tr("INVITE_COPY")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	closed.emit()
	queue_free()

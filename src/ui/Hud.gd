extends Control
## In-game overlay: status line, notices, chat, lobby buttons, modals (wardrobe, settings,
## how-to-play, pause menu) and the Tab scoreboard. Phase panels are added in M4/M5.

const CUSTOMIZER_SCENE := preload("res://src/ui/Customizer.tscn")
const SETTINGS_SCENE := preload("res://src/ui/LobbySettingsPanel.tscn")
const HOWTO_SCENE := preload("res://src/ui/HowToPlay.tscn")
const PAUSE_SCENE := preload("res://src/ui/PauseMenu.tscn")

@onready var status_label: Label = %StatusLabel
@onready var notice_label: Label = %NoticeLabel
@onready var chat_log: RichTextLabel = %ChatLog
@onready var chat_input: LineEdit = %ChatInput
@onready var player_list: Label = %PlayerList
@onready var prompt_label: Label = %Prompt
@onready var ready_button: Button = %ReadyButton
@onready var start_button: Button = %StartButton
@onready var settings_button: Button = %SettingsButton
@onready var lobby_buttons: HBoxContainer = %LobbyButtons
@onready var scoreboard: Control = %Scoreboard

var _modal: Control = null
var _notice_tween: Tween


func _ready() -> void:
	chat_log.bbcode_enabled = false
	chat_log.scroll_following = true
	chat_input.visible = false
	chat_input.text_submitted.connect(_on_chat_submitted)
	chat_input.focus_exited.connect(func(): chat_input.visible = false)
	ready_button.pressed.connect(_toggle_ready)
	start_button.pressed.connect(func(): Game.start_round_local())
	settings_button.pressed.connect(open_settings)
	Game.chat_received.connect(_on_chat)
	Game.players_changed.connect(_refresh)
	Game.state_changed.connect(_on_state_changed)
	Game.snapshot_applied.connect(_refresh)
	notice_label.modulate.a = 0.0
	scoreboard.visible = false
	_refresh()


func _process(_delta: float) -> void:
	if Game.state != Game.State.LOBBY and Game.state != Game.State.MENU:
		var s := ceili(Game.seconds_left)
		var t := "%d:%02d" % [s / 60, s % 60] if s >= 60 else "%ds" % s
		status_label.text = "%s  %s" % [tr("STATE_" + Game.state_name()), t]


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("menu"):
		if is_modal_open():
			return   # the modal closes itself
		open_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("chat") and not chat_input.visible and not is_modal_open():
		chat_input.visible = true
		chat_input.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ready") and not chat_input.visible and not is_modal_open():
		_toggle_ready()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("scoreboard"):
		scoreboard.visible = true
	elif event.is_action_released("scoreboard"):
		scoreboard.visible = false


func _toggle_ready() -> void:
	if Game.state != Game.State.LOBBY:
		return
	var me: Dictionary = Game.player(Game.local_id())
	Game.set_local_ready(not bool(me.get("ready", false)))
	Audio.play("ui_click")


func _on_chat_submitted(text: String) -> void:
	chat_input.clear()
	chat_input.visible = false
	chat_input.release_focus()
	if text.strip_edges() != "":
		Game.send_chat(text)


func _on_chat(peer_id: int, text: String) -> void:
	chat_log.append_text("%s: %s\n" % [Game.player_name(peer_id), text])


func _on_state_changed(_old: int, new_state: int) -> void:
	_refresh()
	match new_state:
		Game.State.COUNTDOWN:
			show_notice(tr("NOTICE_ROUND_START"))
			Audio.play("countdown")
		Game.State.LOBBY:
			if _old != Game.State.MENU:
				show_notice(tr("NOTICE_BACK_TO_LOBBY"))


func _refresh() -> void:
	var in_lobby := Game.state == Game.State.LOBBY
	if in_lobby:
		status_label.text = tr("STATE_LOBBY")
	lobby_buttons.visible = in_lobby
	var me: Dictionary = Game.player(Game.local_id())
	var is_spec := bool(me.get("spectator", false))
	ready_button.visible = in_lobby and not is_spec
	ready_button.text = tr("BTN_UNREADY") if bool(me.get("ready", false)) else tr("BTN_READY")
	start_button.visible = in_lobby and Game.is_admin()
	start_button.disabled = Game.connected_player_ids(false).size() < 2
	start_button.text = tr("BTN_START") if Game.all_ready() else tr("BTN_FORCE_START")
	settings_button.visible = in_lobby
	var lines: Array[String] = []
	for id in Game.connected_player_ids():
		var p: Dictionary = Game.players[id]
		var flags := ""
		if id == Game.HOST_ID:
			flags += " ★"
		if p.get("spectator", false):
			flags += " (%s)" % tr("STATUS_SPECTATOR")
		elif in_lobby and p.get("ready", false):
			flags += " ✓"
		lines.append("%s%s" % [p.name, flags])
	for id in Game.players.keys():
		if not Game.players[id].connected:
			lines.append("%s (%s)" % [Game.players[id].name, tr("STATUS_AWAY")])
	player_list.text = "\n".join(lines)


func set_prompt(text: String) -> void:
	prompt_label.text = text
	prompt_label.visible = text != "" and not is_modal_open()


# ------------------------------------------------------------------ modals

func is_modal_open() -> bool:
	return _modal != null and is_instance_valid(_modal)


func _open_modal(scene: PackedScene) -> Control:
	if is_modal_open():
		return null
	_modal = scene.instantiate()
	add_child(_modal)
	if _modal.has_signal("closed"):
		_modal.closed.connect(_on_modal_closed)
	prompt_label.visible = false
	return _modal


func _on_modal_closed() -> void:
	_modal = null
	var main := get_tree().current_scene
	var player: Node = main.local_player() if main and main.has_method("local_player") else null
	if player and not Settings.cli.bot and Net.active:
		player._set_mouse_captured(true)


func open_customizer() -> void:
	_open_modal(CUSTOMIZER_SCENE)


func open_settings() -> void:
	_open_modal(SETTINGS_SCENE)


func open_howto() -> void:
	_open_modal(HOWTO_SCENE)


func open_pause() -> void:
	var m := _open_modal(PAUSE_SCENE)
	if m:
		m.open_howto.connect(func(): call_deferred("open_howto"))
		m.open_settings.connect(func(): call_deferred("open_settings"))


func show_notice(text: String) -> void:
	notice_label.text = text
	if _notice_tween:
		_notice_tween.kill()
	notice_label.modulate.a = 1.0
	_notice_tween = create_tween()
	_notice_tween.tween_interval(3.0)
	_notice_tween.tween_property(notice_label, "modulate:a", 0.0, 0.8)

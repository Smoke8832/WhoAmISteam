extends Control
## In-game overlay: status line, notices, chat. Phase panels are added in later milestones.

@onready var status_label: Label = %StatusLabel
@onready var notice_label: Label = %NoticeLabel
@onready var chat_log: RichTextLabel = %ChatLog
@onready var chat_input: LineEdit = %ChatInput
@onready var player_list: Label = %PlayerList

var _notice_tween: Tween


func _ready() -> void:
	chat_log.bbcode_enabled = false
	chat_log.scroll_following = true
	chat_input.visible = false
	chat_input.text_submitted.connect(_on_chat_submitted)
	chat_input.focus_exited.connect(func(): chat_input.visible = false)
	Game.chat_received.connect(_on_chat)
	Game.players_changed.connect(_refresh)
	Game.state_changed.connect(func(_o, _n): _refresh())
	Game.snapshot_applied.connect(_refresh)
	notice_label.modulate.a = 0.0
	_refresh()


func _process(_delta: float) -> void:
	if Game.seconds_left > 0.0 and Game.state != Game.State.LOBBY:
		status_label.text = "%s  %ds" % [tr("STATE_" + Game.state_name()), ceili(Game.seconds_left)]


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("chat") and not chat_input.visible:
		chat_input.visible = true
		chat_input.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ready") and not chat_input.visible and Game.state == Game.State.LOBBY:
		var me: Dictionary = Game.player(Game.local_id())
		Game.set_local_ready(not bool(me.get("ready", false)))
		get_viewport().set_input_as_handled()


func _on_chat_submitted(text: String) -> void:
	chat_input.clear()
	chat_input.visible = false
	chat_input.release_focus()
	if text.strip_edges() != "":
		Game.send_chat(text)


func _on_chat(peer_id: int, text: String) -> void:
	chat_log.append_text("%s: %s\n" % [Game.player_name(peer_id), text])


func _refresh() -> void:
	status_label.text = tr("STATE_" + Game.state_name())
	var lines: Array[String] = []
	for id in Game.connected_player_ids():
		var p: Dictionary = Game.players[id]
		var flags := ""
		if id == Game.HOST_ID:
			flags += " ★"
		if p.get("spectator", false):
			flags += " (spectator)"
		elif p.get("ready", false):
			flags += " ✓"
		lines.append("%s%s" % [p.name, flags])
	for id in Game.players.keys():
		if not Game.players[id].connected:
			lines.append("%s (away)" % Game.players[id].name)
	player_list.text = "\n".join(lines)


func show_notice(text: String) -> void:
	notice_label.text = text
	if _notice_tween:
		_notice_tween.kill()
	notice_label.modulate.a = 1.0
	_notice_tween = create_tween()
	_notice_tween.tween_interval(3.0)
	_notice_tween.tween_property(notice_label, "modulate:a", 0.0, 0.8)

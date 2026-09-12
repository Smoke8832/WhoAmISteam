extends Control
## Tab overlay: players, ready state, scores, solve status; kick buttons for the admin.

const INK := Color("1c1a17")

@onready var rows: VBoxContainer = %Rows
@onready var title: Label = %Title


func _ready() -> void:
	Game.players_changed.connect(refresh)
	Game.snapshot_applied.connect(refresh)
	RoundManager.round_changed.connect(refresh)
	visibility_changed.connect(func(): if visible: refresh())
	refresh()


func refresh() -> void:
	if not visible:
		return
	for c in rows.get_children():
		c.queue_free()
	title.text = tr("SCOREBOARD_TITLE") if Game.round_index == 0 else Locale.f("SCOREBOARD_ROUND", {"n": Game.round_index})
	var ids: Array = Game.players.keys()
	ids.sort_custom(func(a, b): return int(Game.players[a].score) > int(Game.players[b].score))
	var header := _row_container()
	header.add_child(_cell(tr("COL_PLAYER"), 240, true))
	header.add_child(_cell(tr("COL_STATUS"), 180, true))
	header.add_child(_cell(tr("COL_SCORE"), 90, true))
	if Game.is_admin():
		header.add_child(_cell("", 90, true))
	rows.add_child(header)
	for id in ids:
		var p: Dictionary = Game.players[id]
		var row := _row_container()
		var name := String(p.name) + (" ★" if id == Game.HOST_ID else "") + (" (you)" if id == Game.local_id() else "")
		row.add_child(_cell(name, 240))
		row.add_child(_cell(_status(id, p), 180))
		row.add_child(_cell(str(int(p.score)), 90))
		if Game.is_admin() and id != Game.HOST_ID:
			var kick := Button.new()
			kick.text = tr("KICK")
			kick.custom_minimum_size = Vector2(90, 0)
			kick.pressed.connect(func(): Game.req_kick_local(id))
			row.add_child(kick)
		rows.add_child(row)


func _status(id: int, p: Dictionary) -> String:
	if not p.connected:
		return tr("STATUS_AWAY")
	if p.spectator:
		return tr("STATUS_SPECTATOR")
	match Game.state:
		Game.State.LOBBY:
			return tr("STATUS_READY") if p.ready else tr("STATUS_NOT_READY")
		Game.State.WRITING:
			var n: Dictionary = RoundManager.name_entry(RoundManager.target_of(id))
			return tr("STATUS_WROTE") if n.get("confirmed", false) else tr("STATUS_WRITING")
		Game.State.GUESSING, Game.State.REVEAL:
			if RoundManager.r.get("solved", {}).has(id):
				return Locale.f("STATUS_SOLVED", {"rank": int(RoundManager.r.solved[id])})
			return tr("STATUS_GUESSING")
	return ""


func _row_container() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	return h


func _cell(text: String, width: int, header: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
	l.add_theme_color_override("font_color", INK if not header else Color(0.4, 0.38, 0.35))
	if header:
		l.add_theme_font_size_override("font_size", 14)
	return l

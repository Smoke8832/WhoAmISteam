extends Node
## Renders the TV screen UI into a SubViewport and puts it on the TV quad in the room.
## Shows settings + players in the lobby, then the phase, timer, turn and votes.

const W := 640
const H := 384
const INK := Color("1c1a17")
const PAPER := Color("f5f3ec")
const YELLOW := Color("ffe14d")

var viewport: SubViewport
var _header: Label
var _body: Label
var _footer: Label
var _big: Label
var _quad: MeshInstance3D


func setup(quad: MeshInstance3D) -> void:
	_quad = quad
	viewport = SubViewport.new()
	viewport.size = Vector2i(W, H)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	add_child(viewport)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color("14181c")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	root.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	_header = Label.new()
	_header.theme_type_variation = &"HeaderLarge"
	_header.add_theme_color_override("font_color", YELLOW)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_header)
	_big = Label.new()
	_big.theme_type_variation = &"HeaderLarge"
	_big.add_theme_font_size_override("font_size", 120)
	_big.add_theme_color_override("font_color", PAPER)
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.visible = false
	vbox.add_child(_big)
	_body = Label.new()
	_body.add_theme_color_override("font_color", PAPER)
	_body.add_theme_font_size_override("font_size", 24)
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vbox.add_child(_body)
	_footer = Label.new()
	_footer.add_theme_color_override("font_color", Color(0.7, 0.7, 0.72))
	_footer.add_theme_font_size_override("font_size", 18)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_footer)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	mat.emission_enabled = true
	mat.emission_texture = viewport.get_texture()
	mat.emission_energy_multiplier = 0.9
	_quad.material_override = mat
	Game.players_changed.connect(refresh)
	Game.state_changed.connect(func(_o, _n): refresh())
	RoundManager.round_changed.connect(refresh)
	RoundManager.vote_changed.connect(refresh)
	refresh()


func _process(_delta: float) -> void:
	if Game.state == Game.State.COUNTDOWN:
		_big.text = str(ceili(Game.seconds_left))
	elif Game.state in [Game.State.WRITING, Game.State.GUESSING]:
		_footer.text = _timer_text()


func _timer_text() -> String:
	var s := int(ceil(Game.seconds_left))
	if Game.state == Game.State.GUESSING and String(Game.settings.round_end_mode) != LobbySettings.ROUND_END_TIME_LIMIT:
		var v: Dictionary = RoundManager.r.get("vote", {})
		if not v.is_empty():
			return Locale.f("TV_VOTE_LEFT", {"s": int(ceil(float(v.get("seconds_left", 0.0))))})
		return Locale.f("TV_TURN_LEFT", {"s": int(ceil(float(RoundManager.r.get("turn_seconds_left", 0.0))))})
	return "%d:%02d" % [s / 60, s % 60]


func refresh() -> void:
	_big.visible = false
	match Game.state:
		Game.State.LOBBY:
			_header.text = tr("APP_TITLE")
			var lines: Array[String] = []
			var ready := 0
			var total := 0
			for id in Game.connected_player_ids(false):
				total += 1
				if Game.players[id].ready:
					ready += 1
			lines.append(Locale.f("TV_READY_COUNT", {"ready": ready, "total": total}))
			lines.append("")
			lines.append(LobbySettings.describe(Game.settings))
			_body.text = "\n".join(lines)
			_footer.text = tr("TV_LOBBY_HINT")
		Game.State.COUNTDOWN:
			_header.text = tr("STATE_COUNTDOWN")
			_big.visible = true
			_body.text = tr("TV_RULES_SHORT")
			_footer.text = ""
		Game.State.WRITING:
			_header.text = tr("STATE_WRITING")
			var done := 0
			for id in RoundManager.r.get("order", []):
				if RoundManager.name_entry(id).get("confirmed", false):
					done += 1
			_body.text = Locale.f("TV_WRITING", {"done": done, "total": RoundManager.r.get("order", []).size()})
		Game.State.STICKING:
			_header.text = tr("STATE_STICKING")
			_body.text = tr("TV_STICKING")
			_footer.text = ""
		Game.State.GUESSING:
			var g := RoundManager.current_guesser()
			_header.text = Locale.f("TV_TURN", {"name": Game.player_name(g)})
			var v: Dictionary = RoundManager.r.get("vote", {})
			var res := RoundManager.last_result()
			if not res.is_empty():
				_body.text = RoundManager.describe_result(res)
			elif v.is_empty():
				_body.text = tr("TV_ASK")
			else:
				_body.text = RoundManager.describe_vote(v)
			var solved: Dictionary = RoundManager.r.get("solved", {})
			if not solved.is_empty():
				var names: Array[String] = []
				for id in solved.keys():
					names.append("%s #%d" % [Game.player_name(int(id)), int(solved[id])])
				_body.text += "\n\n" + tr("TV_SOLVED") + " " + ", ".join(names)
		Game.State.REVEAL:
			_header.text = tr("STATE_REVEAL")
			_body.text = RoundManager.describe_scores()
			_footer.text = ""
		_:
			_header.text = ""
			_body.text = ""
			_footer.text = ""

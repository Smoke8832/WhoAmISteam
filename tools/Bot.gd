extends Node
## Autopilot for local testing (--bot). Wanders the room, readies up, and later milestones
## teach it to write names, vote and claim guesses. Saves screenshots to --screenshot-dir.

var _t := 0.0
var _next_turn := 0.0
var _shots_taken := 0
var _ready_sent := false
var _start_sent := false
var _wardrobe_done := false

const SHOT_TIMES := [4.0, 12.0, 30.0]


func _ready() -> void:
	print("[bot] active as '%s'" % Settings.player_name())
	Customization.override_local(Customization.randomized())
	Settings.data.third_person = false   # bots always start in first person (do not persist)
	Game.state_changed.connect(_on_state_changed)


func _process(delta: float) -> void:
	_t += delta
	var main := get_parent()
	var player: Node = main.local_player() if main.has_method("local_player") else null
	if player == null:
		return
	# Wander
	if _t >= _next_turn:
		_next_turn = _t + randf_range(1.0, 2.5)
		player.bot_move = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * (0.0 if randf() < 0.3 else 1.0)
		player.bot_look = Vector2(randf_range(-0.6, 0.6), 0.0)
		if randf() < 0.25:
			player.bot_jump = true
		# Mostly look at the other players so screenshots show them.
		var others := get_tree().get_nodes_in_group("players").filter(func(p): return p != player)
		if not others.is_empty() and randf() < 0.7:
			var target: Node3D = others[randi() % others.size()]
			player.face_toward(target.global_position + Vector3(0, 1.4, 0))
			player.bot_look = Vector2.ZERO
	# Room interaction: sit down after a while, emote now and then, throw whatever is in hand.
	if _t > 8.0 and not player.seated and randf() < 0.004:
		var lvl := Game.level()
		if lvl:
			for c in lvl.chairs():
				if c.is_free():
					Game.req_sit_local(c.chair_id)
					break
	if player.seated and randf() < 0.002:
		Game.req_stand_local()
	if randf() < 0.003:
		player.emote(randi() % 3)
	if player.held_prop >= 0 and randf() < 0.02:
		player.throw_held()
	elif player.held_prop < 0 and player.look_target() is Prop and randf() < 0.2:
		Game.req_grab_local((player.look_target() as Prop).prop_id)
	# Open the wardrobe once for a screenshot, then close it. Only in the lobby.
	var hud: Node = main.get("hud")
	if hud and not _wardrobe_done and _t > 15.0 and Game.state == Game.State.LOBBY and not hud.is_modal_open():
		_wardrobe_done = true
		hud.open_customizer()
		await get_tree().create_timer(1.5).timeout
		await _screenshot("wardrobe")
		if hud.is_modal_open() and hud._modal.has_method("_on_random"):
			hud._modal._on_random()
			hud._modal._on_save()
	# Lobby behaviour
	if Game.state == Game.State.LOBBY:
		if not _ready_sent and _t > 2.0:
			_ready_sent = true
			Game.set_local_ready(true)
		if Net.is_host() and not _start_sent and Game.all_ready() and _t > 6.0:
			_start_sent = true
			Game.start_round_local()
	# Screenshots (the last one in third person so the own character is visible)
	if _shots_taken < SHOT_TIMES.size() and _t >= SHOT_TIMES[_shots_taken]:
		_shots_taken += 1
		if _shots_taken == SHOT_TIMES.size():
			player.set_third_person(true)
			await get_tree().process_frame
		_screenshot("t%02d" % int(_t))


func _on_state_changed(_old: int, new_state: int) -> void:
	if new_state == Game.State.LOBBY:
		_ready_sent = false
		_start_sent = false
	if new_state == Game.State.WRITING:
		_do_writing()
	if new_state == Game.State.STICKING:
		_secrecy_report()
		_look_at_tv()
	if new_state == Game.State.GUESSING:
		await get_tree().create_timer(1.5).timeout
		_screenshot("guessing_late")
	_screenshot(Game.STATE_NAMES[new_state].to_lower())


## Writing phase: one of three paths so every pipeline gets exercised.
func _do_writing() -> void:
	if not RoundManager.is_participant(Game.local_id()):
		return
	await get_tree().create_timer(randf_range(1.0, 3.0)).timeout
	if Game.state != Game.State.WRITING:
		return
	var main := get_parent()
	var hud: Node = main.get("hud")
	if hud == null or not hud.is_modal_open() or not hud._modal.has_method("bot_fill"):
		print("[bot] write panel not open; submitting directly")
		RoundManager.submit_local(RoundManager.target_of(Game.local_id()), FamousNames.random_name(), PackedByteArray())
		return
	var panel: Control = hud._modal
	var roll := randf()
	var entry := FamousNames.random_entry()
	if roll < 0.5:
		print("[bot] writing with a generated picture")
		panel.bot_fill(String(entry.name), _generated_picture())
	elif roll < 0.8 and not Settings.cli.no_steam:
		print("[bot] writing via Wikipedia search: %s" % entry.name)
		panel.bot_search_and_pick(String(entry.wiki))
	else:
		print("[bot] writing text-only")
		panel.bot_fill(String(entry.name), PackedByteArray())


func _generated_picture() -> PackedByteArray:
	var img := Image.create(320, 240, false, Image.FORMAT_RGB8)
	var a := Color.from_hsv(randf(), 0.6, 0.9)
	var b := Color.from_hsv(randf(), 0.7, 0.5)
	for y in 240:
		for x in 320:
			img.set_pixel(x, y, a.lerp(b, float(x + y) / 560.0))
	for i in 6:
		var cx := randi() % 320
		var cy := randi() % 240
		var rad := 15 + randi() % 40
		var col := Color.from_hsv(randf(), 0.8, 1.0)
		for y in range(maxi(0, cy - rad), mini(240, cy + rad)):
			for x in range(maxi(0, cx - rad), mini(320, cx + rad)):
				if (x - cx) * (x - cx) + (y - cy) * (y - cy) < rad * rad:
					img.set_pixel(x, y, col)
	return img.save_png_to_buffer()


## Turn toward the TV for a moment so its screen shows up in a screenshot.
func _look_at_tv() -> void:
	var main := get_parent()
	var player: Node = main.local_player() if main.has_method("local_player") else null
	if player == null:
		return
	await get_tree().create_timer(0.6).timeout
	player.bot_move = Vector2.ZERO
	player.bot_look = Vector2.ZERO
	player.face_toward(Vector3(0.0, 1.1, -4.5))
	_next_turn = _t + 2.5
	await get_tree().process_frame
	await get_tree().process_frame
	await _screenshot("tv")
	# Dump the TV's own render target too, to tell "screen blank" from "texture not applied".
	var lvl := Game.level()
	var dir := String(Settings.cli.screenshot_dir)
	if lvl and lvl.get("tv") and dir != "":
		var vp: SubViewport = lvl.tv.viewport
		var img := vp.get_texture().get_image()
		if img:
			img.save_png("%s/%s_tvtex.png" % [dir, Settings.player_name()])
			print("[bot] tv texture %dx%d material=%s" % [img.get_width(), img.get_height(), str(lvl.tv._quad.material_override)])


## Proof for the secrecy rule: what this client knows about its own forehead.
func _secrecy_report() -> void:
	await get_tree().create_timer(1.0).timeout
	var me := Game.local_id()
	var mine := RoundManager.name_entry(me)
	var known: Array = []
	for t in RoundManager.r.get("names", {}).keys():
		if String(RoundManager.r.names[t].get("name", "")) != "":
			known.append(int(t))
	print("[secrecy] me=%d my_name_visible='%s' my_image=%s names_known_for=%s images_for=%s" % [
		me, String(mine.get("name", "")), str(RoundManager.images.has(me)), str(known), str(RoundManager.images.keys())])


func _screenshot(tag: String) -> void:
	var dir := String(Settings.cli.screenshot_dir)
	if dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/%s_%s.png" % [dir, Settings.player_name(), tag]
	img.save_png(path)
	print("[bot] screenshot %s" % path)

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
	# Open the wardrobe once for a screenshot, then close it.
	var hud: Node = main.get("hud")
	if hud and not _wardrobe_done and _t > 15.0:
		_wardrobe_done = true
		hud.open_customizer()
		await get_tree().create_timer(1.5).timeout
		await _screenshot("wardrobe")
		if hud.is_modal_open():
			hud._customizer._on_random()
			hud._customizer._on_save()
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
	_screenshot(Game.STATE_NAMES[new_state].to_lower())


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

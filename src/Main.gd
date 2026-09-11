extends Node
## Root scene. Owns the world container, the player spawner, and the UI layer.
## Handles command-line autopilot (--host / --join / --bot) for local testing.

const PLAYER_SCENE := preload("res://src/player/Player.tscn")
const LIVING_ROOM_SCENE := preload("res://src/world/LivingRoom.tscn")
const BOT_SCRIPT := preload("res://tools/Bot.gd")

@onready var world: Node3D = $World
@onready var players_root: Node3D = $World/Players
@onready var spawner: MultiplayerSpawner = $PlayerSpawner
@onready var ui: CanvasLayer = $UI
@onready var main_menu: Control = $UI/MainMenu
@onready var hud: Control = $UI/Hud

var level: Node3D = null


func _ready() -> void:
	get_tree().auto_accept_quit = true
	spawner.spawn_function = _spawn_player
	Net.hosting_started.connect(_on_session_started)
	Net.connected_to_host.connect(_on_session_started)
	Net.connection_failed.connect(_on_connection_failed)
	Net.server_disconnected.connect(_on_session_ended)
	Net.left.connect(_on_session_ended)
	Game.player_joined.connect(_on_player_joined)
	Game.player_left.connect(_on_player_left)
	Game.notice.connect(_on_notice)
	_show_menu(true)
	_apply_cli()


func _apply_cli() -> void:
	var cli := Settings.cli
	if cli.window_pos.x >= 0:
		get_window().position = cli.window_pos
	if cli.bot:
		var bot := Node.new()
		bot.name = "Bot"
		bot.set_script(BOT_SCRIPT)
		add_child(bot)
	if cli.host:
		call_deferred("_cli_host")
	elif String(cli.join) != "":
		call_deferred("_cli_join")
	if float(cli.quit_after) > 0.0:
		get_tree().create_timer(float(cli.quit_after)).timeout.connect(func(): get_tree().quit())


func _cli_host() -> void:
	Net.host(Transport.KIND_ENET, int(Game.settings.max_players), {"port": Settings.cli.port})


func _cli_join() -> void:
	Net.join(Transport.KIND_ENET, String(Settings.cli.join), {"port": Settings.cli.port})


# ------------------------------------------------------------ session flow

func _on_session_started() -> void:
	_load_level()
	_show_menu(false)


func _on_session_ended() -> void:
	_unload_level()
	_show_menu(true)


func _on_connection_failed(reason: String) -> void:
	_on_notice(reason)
	_show_menu(true)


func _load_level() -> void:
	if level:
		return
	level = LIVING_ROOM_SCENE.instantiate()
	level.name = "Level"
	world.add_child(level)
	Audio.play_music("lobby_loop.ogg")


func _unload_level() -> void:
	for p in players_root.get_children():
		p.queue_free()
	if level:
		level.queue_free()
		level = null
	Audio.stop_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _show_menu(visible: bool) -> void:
	main_menu.visible = visible
	hud.visible = not visible
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_notice(text: String) -> void:
	hud.show_notice(tr(text))
	if main_menu.visible:
		main_menu.show_status(tr(text))


# ---------------------------------------------------------------- spawning

func _spawn_player(data: Variant) -> Node:
	var peer_id: int = int(data.peer)
	var p := PLAYER_SCENE.instantiate()
	p.name = str(peer_id)
	p.peer_id = peer_id
	p.set_multiplayer_authority(peer_id)
	p.spawn_transform = _spawn_transform_for(int(data.get("slot", 0)))
	return p


func _spawn_transform_for(slot: int) -> Transform3D:
	if level and level.has_method("spawn_transform"):
		return level.spawn_transform(slot)
	return Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))


func _on_player_joined(peer_id: int) -> void:
	if not Net.is_host():
		return
	if players_root.has_node(str(peer_id)):
		return
	spawner.spawn({"peer": peer_id, "slot": players_root.get_child_count()})


func _on_player_left(peer_id: int) -> void:
	if not Net.is_host():
		return
	var node := players_root.get_node_or_null(str(peer_id))
	if node:
		node.queue_free()


func local_player() -> Node:
	return players_root.get_node_or_null(str(Net.local_id()))


func player_node(peer_id: int) -> Node:
	return players_root.get_node_or_null(str(peer_id))

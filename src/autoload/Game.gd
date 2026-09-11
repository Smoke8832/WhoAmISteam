extends Node
## Host-authoritative game state.
## Clients send intents (request_*); the host validates phase + sender, mutates state,
## and pushes a per-peer filtered snapshot with sync_state(). Round logic (assignments,
## votes, scoring) lives in RoundManager and is driven from here.

enum State { MENU, LOBBY, COUNTDOWN, WRITING, STICKING, GUESSING, REVEAL }
const STATE_NAMES := ["MENU", "LOBBY", "COUNTDOWN", "WRITING", "STICKING", "GUESSING", "REVEAL"]

const HOST_ID := 1
const MAX_CHAT := 200
const MAX_NAME := 16
const MIN_NAME := 3
const SNAPSHOT_INTERVAL := 1.0

signal state_changed(old_state: int, new_state: int)
signal snapshot_applied
signal players_changed
signal player_joined(peer_id: int)      # host only: a peer completed hello()
signal player_left(peer_id: int)        # host only: a peer left (slot may be held)
signal chat_received(peer_id: int, text: String)
signal notice(text: String)             # local toast

var state: int = State.MENU
## peer_id -> {name, customization, ready, seat, spectator, score, connected}
var players: Dictionary = {}
var settings: Dictionary = LobbySettings.defaults()
var round_data: Dictionary = {}
var timer_end_msec: int = 0          # host wall clock; clients receive seconds_left
var seconds_left: float = 0.0
var round_index: int = 0

var _snapshot_accum := 0.0
var _local_hello_sent := false


func _ready() -> void:
	Net.hosting_started.connect(_on_hosting_started)
	Net.connected_to_host.connect(_on_connected_to_host)
	Net.peer_connected.connect(_on_peer_connected)
	Net.peer_disconnected.connect(_on_peer_disconnected)
	Net.server_disconnected.connect(_on_server_disconnected)
	Net.left.connect(_on_left)


func _process(delta: float) -> void:
	if state == State.MENU:
		return
	if seconds_left > 0.0:
		seconds_left = maxf(0.0, seconds_left - delta)
	if Net.is_host() and _is_timed_state():
		_snapshot_accum += delta
		if _snapshot_accum >= SNAPSHOT_INTERVAL:
			_snapshot_accum = 0.0
			broadcast_snapshot()


# ------------------------------------------------------------------ helpers

func local_id() -> int:
	return Net.local_id()


func is_host() -> bool:
	return Net.is_host()


func is_admin(peer_id: int = -1) -> bool:
	return (peer_id if peer_id != -1 else local_id()) == HOST_ID


func state_name() -> String:
	return STATE_NAMES[state]


func player(peer_id: int) -> Dictionary:
	return players.get(peer_id, {})


func player_name(peer_id: int) -> String:
	return String(players.get(peer_id, {}).get("name", "Player %d" % peer_id))


func connected_player_ids(include_spectators: bool = true) -> Array:
	var out: Array = []
	for id in players.keys():
		var p: Dictionary = players[id]
		if not p.connected:
			continue
		if not include_spectators and p.spectator:
			continue
		out.append(id)
	out.sort()
	return out


func active_player_ids() -> Array:
	## Players who take part in the current/next round (connected or slot-held, not spectators).
	var out: Array = []
	for id in players.keys():
		if not players[id].spectator:
			out.append(id)
	out.sort()
	return out


func all_ready() -> bool:
	var ids := connected_player_ids(false)
	if ids.size() < 2:
		return false
	for id in ids:
		if not players[id].ready:
			return false
	return true


func _is_timed_state() -> bool:
	return state in [State.COUNTDOWN, State.WRITING, State.STICKING, State.GUESSING, State.REVEAL]


static func sanitize_name(raw: String) -> String:
	var cleaned := ""
	for ch in raw.strip_edges():
		var c := ch.unicode_at(0)
		if ch == " " or ch == "_" or ch == "-" or ch == "." or (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 0x00C0 and c <= 0x024F):
			cleaned += ch
	cleaned = cleaned.substr(0, MAX_NAME)
	if cleaned.strip_edges().length() < MIN_NAME:
		cleaned = "Player%d" % (randi() % 900 + 100)
	return cleaned


static func default_player(name: String, customization: Dictionary) -> Dictionary:
	return {
		"name": name,
		"customization": customization,
		"ready": false,
		"seat": -1,
		"spectator": false,
		"score": 0,
		"connected": true,
		"held": false,          # true while a disconnected player's slot is kept for rejoin
		"held_prop": -1,        # prop id currently carried, -1 = none
	}


## The LivingRoom node (or null before a session starts).
func level() -> Node:
	var main := get_tree().current_scene
	return main.get("level") if main else null


# --------------------------------------------------------- connection events

func _on_hosting_started() -> void:
	players.clear()
	round_data.clear()
	round_index = 0
	settings = LobbySettings.sanitize(settings)
	players[HOST_ID] = default_player(Settings.player_name(), Customization.local())
	_set_state(State.LOBBY)
	player_joined.emit(HOST_ID)
	players_changed.emit()
	broadcast_snapshot()


func _on_connected_to_host() -> void:
	_local_hello_sent = true
	hello.rpc_id(HOST_ID, Settings.player_name(), Customization.local(), Settings.get_value("rejoin_token", ""))


func _on_peer_connected(_id: int) -> void:
	pass  # wait for hello()


func _on_peer_disconnected(id: int) -> void:
	if not Net.is_host():
		return
	if not players.has(id):
		return
	_release_props_of(id)
	var mid_round := state in [State.WRITING, State.STICKING, State.GUESSING]
	if mid_round and not players[id].spectator:
		players[id].connected = false
		players[id].held = true
		players[id].ready = false
		players[id].seat = -1
		notice.emit("%s disconnected. Their seat is kept until the round ends." % player_name(id))
	else:
		players.erase(id)
	player_left.emit(id)
	players_changed.emit()
	broadcast_snapshot()


func _on_server_disconnected() -> void:
	_reset_local()
	notice.emit("HOST_LEFT")


func _on_left() -> void:
	_reset_local()


func _reset_local() -> void:
	players.clear()
	round_data.clear()
	seconds_left = 0.0
	_local_hello_sent = false
	_set_state(State.MENU)
	players_changed.emit()


func _set_state(new_state: int) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	state_changed.emit(old, new_state)


# ------------------------------------------------------------------- RPCs

## Client -> Host. First message after connecting.
@rpc("any_peer", "call_remote", "reliable")
func hello(name: String, customization: Dictionary, rejoin_token: String) -> void:
	if not Net.is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var clean_name := sanitize_name(name)
	var clean_custom := Customization.sanitize(customization)
	# Rejoin: a held slot with the same rejoin token gets restored under the new peer id.
	var restored := false
	if rejoin_token != "":
		for old_id in players.keys():
			var p: Dictionary = players[old_id]
			if p.held and p.get("rejoin_token", "") == rejoin_token:
				players.erase(old_id)
				p.connected = true
				p.held = false
				p.name = clean_name
				players[id] = p
				RoundManager.on_player_rejoined(old_id, id)
				restored = true
				notice.emit("%s is back." % clean_name)
				break
	if not restored:
		var p := default_player(clean_name, clean_custom)
		p.spectator = state != State.LOBBY
		p.rejoin_token = rejoin_token
		if players.size() >= int(settings.max_players):
			kicked.rpc_id(id, "LOBBY_FULL")
			return
		players[id] = p
	player_joined.emit(id)
	players_changed.emit()
	broadcast_snapshot()


## Host -> Client. Told before being disconnected.
@rpc("authority", "call_remote", "reliable")
func kicked(reason: String) -> void:
	notice.emit(reason)
	Net.leave()


## Client -> Host.
@rpc("any_peer", "call_remote", "reliable")
func req_ready(ready: bool) -> void:
	if not Net.is_host() or state != State.LOBBY:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = HOST_ID
	if not players.has(id):
		return
	players[id].ready = ready
	players_changed.emit()
	broadcast_snapshot()


func set_local_ready(ready: bool) -> void:
	if Net.is_host():
		if players.has(HOST_ID) and state == State.LOBBY:
			players[HOST_ID].ready = ready
			players_changed.emit()
			broadcast_snapshot()
	else:
		req_ready.rpc_id(HOST_ID, ready)


## Client -> Host. Admin only.
@rpc("any_peer", "call_remote", "reliable")
func request_settings(new_settings: Dictionary) -> void:
	if not Net.is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if id != 0 and id != HOST_ID:
		return
	if state != State.LOBBY:
		return
	settings = LobbySettings.sanitize(new_settings)
	Voice.set_enabled(bool(settings.voice_enabled))
	broadcast_snapshot()


func update_settings_local(new_settings: Dictionary) -> void:
	if Net.is_host():
		request_settings(new_settings)
	else:
		request_settings.rpc_id(HOST_ID, new_settings)


## Client -> Host. Admin only.
@rpc("any_peer", "call_remote", "reliable")
func request_start() -> void:
	if not Net.is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if id != 0 and id != HOST_ID:
		return
	if state != State.LOBBY:
		return
	if connected_player_ids(false).size() < 2:
		notice.emit("NEED_TWO_PLAYERS")
		return
	RoundManager.start_round()


func start_round_local() -> void:
	if Net.is_host():
		request_start()
	else:
		request_start.rpc_id(HOST_ID)


# ---------------------------------------------------------- room interaction

func _sender_id() -> int:
	var id := multiplayer.get_remote_sender_id()
	return HOST_ID if id == 0 else id


## Client -> Host. Sit on a chair if it is free.
@rpc("any_peer", "call_remote", "reliable")
func req_sit(chair_id: int) -> void:
	if not Net.is_host():
		return
	var id := _sender_id()
	if not players.has(id) or not players[id].connected:
		return
	var lvl := level()
	if lvl == null or lvl.chair(chair_id) == null:
		return
	for other in players.keys():
		if int(players[other].seat) == chair_id and other != id:
			return
	players[id].seat = chair_id
	players_changed.emit()
	broadcast_snapshot()


@rpc("any_peer", "call_remote", "reliable")
func req_stand() -> void:
	if not Net.is_host():
		return
	var id := _sender_id()
	if not players.has(id):
		return
	players[id].seat = -1
	players_changed.emit()
	broadcast_snapshot()


@rpc("any_peer", "call_remote", "reliable")
func req_grab(prop_id: int) -> void:
	if not Net.is_host():
		return
	var id := _sender_id()
	if not players.has(id) or int(players[id].held_prop) >= 0:
		return
	var lvl := level()
	var prop: Prop = lvl.prop(prop_id) if lvl else null
	if prop == null or not prop.grab(id):
		return
	players[id].held_prop = prop_id
	players_changed.emit()
	broadcast_snapshot()


@rpc("any_peer", "call_remote", "reliable")
func req_throw(direction: Vector3, force: float) -> void:
	if not Net.is_host():
		return
	var id := _sender_id()
	if not players.has(id):
		return
	var prop_id := int(players[id].held_prop)
	if prop_id < 0:
		return
	var lvl := level()
	var prop: Prop = lvl.prop(prop_id) if lvl else null
	if prop and prop.held_by == id:
		if typeof(direction) != TYPE_VECTOR3 or not direction.is_finite():
			direction = Vector3.DOWN
		prop.throw(direction, clampf(force, 0.0, Prop.MAX_THROW_FORCE))
	players[id].held_prop = -1
	players_changed.emit()
	broadcast_snapshot()


func _release_props_of(id: int) -> void:
	if not players.has(id):
		return
	var prop_id := int(players[id].get("held_prop", -1))
	if prop_id >= 0:
		var lvl := level()
		var prop: Prop = lvl.prop(prop_id) if lvl else null
		if prop:
			prop.release()
		players[id].held_prop = -1


func req_sit_local(chair_id: int) -> void:
	if Net.is_host():
		req_sit(chair_id)
	else:
		req_sit.rpc_id(HOST_ID, chair_id)


func req_stand_local() -> void:
	if Net.is_host():
		req_stand()
	else:
		req_stand.rpc_id(HOST_ID)


func req_grab_local(prop_id: int) -> void:
	if Net.is_host():
		req_grab(prop_id)
	else:
		req_grab.rpc_id(HOST_ID, prop_id)


func req_throw_local(direction: Vector3, force: float) -> void:
	if Net.is_host():
		req_throw(direction, force)
	else:
		req_throw.rpc_id(HOST_ID, direction, force)


## Any -> Host -> All.
@rpc("any_peer", "call_remote", "reliable")
func chat(text: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if Net.is_host():
		if sender == 0:
			sender = HOST_ID
		if not players.has(sender):
			return
		var clean := text.strip_edges().substr(0, MAX_CHAT)
		if clean == "":
			return
		chat_from.rpc(sender, clean)
		chat_received.emit(sender, clean)


@rpc("authority", "call_remote", "reliable")
func chat_from(sender: int, text: String) -> void:
	chat_received.emit(sender, text.substr(0, MAX_CHAT))


func send_chat(text: String) -> void:
	if Net.is_host():
		chat(text)
	else:
		chat.rpc_id(HOST_ID, text)


## Host -> Client (per peer, filtered). Full snapshot.
@rpc("authority", "call_remote", "reliable")
func sync_state(snapshot: Dictionary) -> void:
	if Net.is_host():
		return
	_apply_snapshot(snapshot)


# ---------------------------------------------------------------- snapshots

func build_snapshot(for_peer: int) -> Dictionary:
	var pl := {}
	for id in players.keys():
		var p: Dictionary = players[id].duplicate()
		p.erase("rejoin_token")
		pl[id] = p
	return {
		"state": state,
		"players": pl,
		"settings": settings,
		"round": RoundManager.round_snapshot(for_peer),
		"round_index": round_index,
		"seconds_left": seconds_left,
	}


func broadcast_snapshot() -> void:
	if not Net.is_host():
		return
	for id in players.keys():
		if id == HOST_ID or not players[id].connected:
			continue
		sync_state.rpc_id(id, build_snapshot(id))
	snapshot_applied.emit()


func _apply_snapshot(s: Dictionary) -> void:
	var new_state := int(s.get("state", State.LOBBY))
	players = s.get("players", {})
	settings = LobbySettings.sanitize(s.get("settings", {}))
	Voice.set_enabled(bool(settings.voice_enabled))
	round_index = int(s.get("round_index", 0))
	seconds_left = float(s.get("seconds_left", 0.0))
	RoundManager.apply_round_snapshot(s.get("round", {}))
	_set_state(new_state)
	players_changed.emit()
	snapshot_applied.emit()


## Host-only: called by RoundManager to change phase and (re)start the phase timer.
func host_set_state(new_state: int, duration_s: float = 0.0) -> void:
	if not Net.is_host():
		return
	seconds_left = duration_s
	_set_state(new_state)
	broadcast_snapshot()

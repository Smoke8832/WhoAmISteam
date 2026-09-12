extends Node
## Thin, compile-safe wrapper around the GodotSteam singleton (accessed dynamically so the
## game still runs if the extension is missing). Handles init, lobbies, invites, rich presence.

const APP_ID := 480   # Spacewar for development; replace with the real App ID at release
const LOBBY_KEY_VERSION := "version"
const LOBBY_KEY_NAME := "name"

signal initialized(ok: bool)
signal lobby_created(lobby_id: int)
signal lobby_create_failed(reason: String)
signal lobby_joined(lobby_id: int, owner_steam_id: int)
signal lobby_join_failed(reason: String)
signal member_joined(steam_id: int)
signal member_left(steam_id: int)
signal join_requested(lobby_id: int)

var steam: Object = null
var available: bool = false
var steam_id: int = 0
var persona: String = ""
var lobby_id: int = 0
var _pending_join: int = 0


func _ready() -> void:
	if Settings.cli.no_steam or Settings.cli.bot or Settings.cli.host or String(Settings.cli.join) != "":
		print("[steam] skipped (dev flags)")
		return
	if not Engine.has_singleton("Steam"):
		print("[steam] GodotSteam singleton not found")
		return
	steam = Engine.get_singleton("Steam")
	var res = steam.call("steamInitEx", APP_ID, true)
	if typeof(res) != TYPE_DICTIONARY or int(res.get("status", -1)) != 0:
		print("[steam] init failed: %s" % str(res))
		steam = null
		initialized.emit(false)
		return
	available = true
	steam_id = int(steam.call("getSteamID"))
	persona = String(steam.call("getPersonaName"))
	print("[steam] ready as %s (%d)" % [persona, steam_id])
	_connect("lobby_created", _on_lobby_created)
	_connect("lobby_joined", _on_lobby_joined)
	_connect("lobby_chat_update", _on_lobby_chat_update)
	_connect("join_requested", _on_join_requested)
	_connect("p2p_session_request", _on_p2p_session_request)
	_connect("p2p_session_connect_fail", _on_p2p_session_connect_fail)
	steam.call("allowP2PPacketRelay", true)
	# Use the Steam persona as the default name unless the player typed their own.
	var current := Settings.player_name()
	if current.begins_with("Player") and current.length() == 9 and current.substr(6).is_valid_int():
		Settings.set_value("player_name", Game.sanitize_name(persona))
	Settings.data.rejoin_token = "steam:%d" % steam_id
	initialized.emit(true)


func _connect(sig: String, cb: Callable) -> void:
	if steam and steam.has_signal(sig):
		steam.connect(sig, cb)


func _exit_tree() -> void:
	leave_lobby()


# ----------------------------------------------------------------- lobbies

func create_lobby(max_members: int, friends_only: bool = true) -> void:
	if not available:
		lobby_create_failed.emit("STEAM_UNAVAILABLE")
		return
	leave_lobby()
	var lobby_type := 1 if friends_only else 2   # LOBBY_TYPE_FRIENDS_ONLY / PUBLIC
	steam.call("createLobby", lobby_type, clampi(max_members, 2, 8))


func _on_lobby_created(connect_result: int, new_lobby_id: int) -> void:
	if connect_result != 1:
		lobby_create_failed.emit("STEAM_LOBBY_FAILED")
		return
	lobby_id = new_lobby_id
	print("[steam] lobby created %d (owner %d)" % [lobby_id, int(steam.call("getLobbyOwner", lobby_id))])
	steam.call("setLobbyData", lobby_id, LOBBY_KEY_VERSION, String(ProjectSettings.get_setting("application/config/version", "0")))
	steam.call("setLobbyData", lobby_id, LOBBY_KEY_NAME, Settings.player_name())
	steam.call("setLobbyJoinable", lobby_id, true)
	_set_presence()
	lobby_created.emit(lobby_id)


func join_lobby(id: int) -> void:
	if not available:
		lobby_join_failed.emit("STEAM_UNAVAILABLE")
		return
	leave_lobby()
	_pending_join = id
	steam.call("joinLobby", id)


func _on_lobby_joined(joined_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != 1:   # CHAT_ROOM_ENTER_RESPONSE_SUCCESS
		_pending_join = 0
		lobby_join_failed.emit("STEAM_LOBBY_JOIN_FAILED")
		return
	lobby_id = joined_id
	_pending_join = 0
	_set_presence()
	var owner := int(steam.call("getLobbyOwner", lobby_id))
	print("[steam] joined lobby %d (owner %d, %d members)" % [lobby_id, owner, int(steam.call("getNumLobbyMembers", lobby_id))])
	lobby_joined.emit(lobby_id, owner)


func leave_lobby() -> void:
	if available and lobby_id != 0:
		steam.call("leaveLobby", lobby_id)
		steam.call("clearRichPresence")
	lobby_id = 0


func _on_lobby_chat_update(changed_lobby: int, changed_id: int, _making_change_id: int, chat_state: int) -> void:
	if changed_lobby != lobby_id:
		return
	if chat_state & 1:     # ENTERED
		member_joined.emit(changed_id)
	elif chat_state & (2 | 4 | 8 | 16):   # LEFT / DISCONNECTED / KICKED / BANNED
		member_left.emit(changed_id)


func _on_join_requested(requested_lobby: int, _friend_id: int) -> void:
	join_requested.emit(requested_lobby)


func lobby_owner() -> int:
	if not available or lobby_id == 0:
		return 0
	return int(steam.call("getLobbyOwner", lobby_id))


func lobby_members() -> Array:
	var out: Array = []
	if not available or lobby_id == 0:
		return out
	var n := int(steam.call("getNumLobbyMembers", lobby_id))
	for i in n:
		out.append(int(steam.call("getLobbyMemberByIndex", lobby_id, i)))
	return out


func is_lobby_member(id: int) -> bool:
	return id in lobby_members()


func _set_presence() -> void:
	if not available or lobby_id == 0:
		return
	steam.call("setRichPresence", "connect", "+connect_lobby %d" % lobby_id)
	steam.call("setRichPresence", "steam_player_group", str(lobby_id))
	steam.call("setRichPresence", "steam_display", "#Status_InRoom")
	steam.call("setRichPresence", "status", "In a living room")


## The overlay only exists when the game was launched through Steam. Returns false otherwise.
func overlay_enabled() -> bool:
	return available and bool(steam.call("isOverlayEnabled"))


func open_invite_dialog() -> bool:
	if available and lobby_id != 0 and overlay_enabled():
		steam.call("activateGameOverlayInviteDialog", lobby_id)
		return true
	return false


const FRIEND_FLAG_IMMEDIATE := 0x04

## Online friends: [{id, name, state, in_game}] — players of this game first, then online, then away.
func friends_online() -> Array:
	var out: Array = []
	if not available:
		return out
	var count := int(steam.call("getFriendCount", FRIEND_FLAG_IMMEDIATE))
	for i in count:
		var id := int(steam.call("getFriendByIndex", i, FRIEND_FLAG_IMMEDIATE))
		var state := int(steam.call("getFriendPersonaState", id))
		if state == 0:
			continue   # offline
		var game: Variant = steam.call("getFriendGamePlayed", id)
		var in_game := typeof(game) == TYPE_DICTIONARY and int(game.get("id", 0)) == APP_ID
		out.append({"id": id, "name": String(steam.call("getFriendPersonaName", id)), "state": state, "in_game": in_game})
	out.sort_custom(func(a, b):
		if a.in_game != b.in_game:
			return a.in_game
		if (a.state == 1) != (b.state == 1):
			return a.state == 1
		return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return out


## Sends a lobby invite through Steam (arrives as a chat message / notification). No overlay needed.
func invite_friend(friend_id: int) -> bool:
	if not available or lobby_id == 0:
		return false
	return bool(steam.call("inviteUserToLobby", lobby_id, friend_id))


func persona_of(id: int) -> String:
	if not available:
		return ""
	return String(steam.call("getFriendPersonaName", id))


## Lobby id passed on the command line by the Steam friends list ("Join game").
static func connect_lobby_from_args() -> int:
	var args := OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "+connect_lobby" and i + 1 < args.size():
			return int(args[i + 1])
	return 0


# --------------------------------------------------------------------- p2p

func _on_p2p_session_request(remote_id: int) -> void:
	# Only talk to people in our lobby (or the host we are joining).
	if remote_id == lobby_owner() or is_lobby_member(remote_id) or remote_id == _pending_join_owner():
		steam.call("acceptP2PSessionWithUser", remote_id)
	else:
		push_warning("[steam] refused P2P session from %d (not in lobby)" % remote_id)


func _pending_join_owner() -> int:
	return 0


func _on_p2p_session_connect_fail(remote_id: int, session_error: int) -> void:
	push_warning("[steam] P2P session with %d failed (%d)" % [remote_id, session_error])


func send_p2p(remote_id: int, data: PackedByteArray, reliable: bool, channel: int) -> bool:
	if not available:
		return false
	var send_type := 2 if reliable else 1   # P2P_SEND_RELIABLE / UNRELIABLE_NO_DELAY
	return bool(steam.call("sendP2PPacket", remote_id, data, send_type, channel))


func p2p_available(channel: int) -> int:
	if not available:
		return 0
	return int(steam.call("getAvailableP2PPacketSize", channel))


## -> {data: PackedByteArray, remote_steam_id: int} or {}
func p2p_read(size: int, channel: int) -> Dictionary:
	if not available:
		return {}
	var d = steam.call("readP2PPacket", size, channel)
	return d if typeof(d) == TYPE_DICTIONARY else {}


func p2p_close(remote_id: int) -> void:
	if available:
		steam.call("closeP2PSessionWithUser", remote_id)

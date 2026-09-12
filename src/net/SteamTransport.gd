class_name SteamTransport
extends Transport
## Steam transport: a Steam lobby for discovery + invites, SteamPeer (P2P) for traffic.
## Hosting creates the lobby asynchronously; the peer is usable immediately.
## Joining takes a lobby id, joins it, then handshakes with the lobby owner.

var peer: SteamPeer = null
var lobby_id: int = 0


func kind() -> String:
	return KIND_STEAM


static func available() -> bool:
	return SteamService.available


func create_host_peer(max_players: int, options: Dictionary) -> MultiplayerPeer:
	if not SteamService.available:
		return null
	peer = SteamPeer.new()
	peer.start_server(SteamService.steam_id)
	SteamService.lobby_created.connect(_on_lobby_created, CONNECT_ONE_SHOT)
	SteamService.member_left.connect(_on_member_left)
	SteamService.create_lobby(max_players, bool(options.get("friends_only", true)))
	return peer


func create_client_peer(address: String, _options: Dictionary) -> MultiplayerPeer:
	if not SteamService.available:
		return null
	var id := int(address)
	if id == 0:
		return null
	peer = SteamPeer.new()
	peer.start_client(SteamService.steam_id)
	SteamService.lobby_joined.connect(_on_lobby_joined, CONNECT_ONE_SHOT)
	SteamService.lobby_join_failed.connect(_on_lobby_join_failed, CONNECT_ONE_SHOT)
	SteamService.join_lobby(id)
	return peer


func _on_lobby_created(id: int) -> void:
	lobby_id = id


func _on_lobby_joined(id: int, owner: int) -> void:
	lobby_id = id
	if peer:
		peer.connect_to_host(owner)


func _on_lobby_join_failed(_reason: String) -> void:
	if peer:
		peer.fail()


func _on_member_left(steam_id: int) -> void:
	if peer and peer._server:
		peer.on_steam_user_left(steam_id)


func join_address() -> String:
	return str(SteamService.lobby_id if SteamService.lobby_id != 0 else lobby_id)

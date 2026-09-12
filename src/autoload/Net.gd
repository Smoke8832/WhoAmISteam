extends Node
## Connection lifecycle. Wraps Godot's high-level multiplayer with a swappable transport.
## Game state itself lives in Game.gd; this node only knows about peers coming and going.

signal hosting_started
signal connected_to_host
signal connection_failed(reason: String)
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal server_disconnected
signal left

const HOST_ID := 1

var transport: Transport = null
var active: bool = false
var connecting: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func make_transport(kind: String) -> Transport:
	match kind:
		Transport.KIND_STEAM:
			return SteamTransport.new()
		_:
			return ENetTransport.new()


func is_host() -> bool:
	return active and multiplayer.multiplayer_peer != null and multiplayer.is_server()


func local_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()


func host(kind: String, max_players: int, options: Dictionary = {}) -> bool:
	leave()
	transport = make_transport(kind)
	var peer := transport.create_host_peer(max_players, options)
	if peer == null:
		connection_failed.emit("Could not start a server (%s)." % kind)
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	hosting_started.emit()
	return true


func join(kind: String, address: String, options: Dictionary = {}) -> bool:
	leave()
	transport = make_transport(kind)
	var peer := transport.create_client_peer(address, options)
	if peer == null:
		connection_failed.emit("Could not connect to %s." % address)
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	connecting = true
	return true


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	var was_active := active
	active = false
	connecting = false
	if transport is SteamTransport:
		SteamService.leave_lobby()
	transport = null
	if was_active:
		left.emit()


func is_steam_session() -> bool:
	return transport is SteamTransport


func join_address() -> String:
	return transport.join_address() if transport else ""


func _on_peer_connected(id: int) -> void:
	peer_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	peer_disconnected.emit(id)


func _on_connected_to_server() -> void:
	connecting = false
	connected_to_host.emit()


func _on_connection_failed() -> void:
	connecting = false
	active = false
	multiplayer.multiplayer_peer = null
	connection_failed.emit("Connection failed.")


func _on_server_disconnected() -> void:
	active = false
	connecting = false
	multiplayer.multiplayer_peer = null
	if transport is SteamTransport:
		SteamService.leave_lobby()
	transport = null
	server_disconnected.emit()

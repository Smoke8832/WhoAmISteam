class_name SteamPeer
extends MultiplayerPeerExtension
## Godot MultiplayerPeer over Steam P2P (ISteamNetworking). Star topology: every client talks
## to the host only; Godot's server relay forwards client-to-client traffic through the host.
##
## Wire format (P2P channel DATA): [channel: u8][mode: u8][godot packet...]
## Control (P2P channel CTRL):     [type: u8][peer_id: u32 LE]
##   HELLO   client -> host  (my proposed peer id)
##   WELCOME host -> client  (assigned peer id)
##   BYE     either way

const CH_DATA := 0
const CH_CTRL := 1
const CTRL_HELLO := 1
const CTRL_WELCOME := 2
const CTRL_BYE := 3
const HELLO_INTERVAL_S := 0.5
const CONNECT_TIMEOUT_S := 12.0
const MAX_PACKET := 1024 * 1024

var _server := false
var _unique_id := 0
var _status: int = MultiplayerPeer.CONNECTION_DISCONNECTED
var _host_steam_id := 0
var _refuse := false

var _peer_to_steam: Dictionary = {}   # peer_id -> steam_id
var _steam_to_peer: Dictionary = {}   # steam_id -> peer_id

var _target_peer := 0
var _transfer_channel := 0
var _transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_RELIABLE

var _incoming: Array = []   # [{peer, channel, mode, data}]
var _current: Dictionary = {}

var _hello_timer := 0.0
var _connect_elapsed := 0.0
var _own_steam_id := 0


# ------------------------------------------------------------------ setup

func start_server(own_steam_id: int) -> void:
	_server = true
	_own_steam_id = own_steam_id
	_unique_id = 1
	_status = MultiplayerPeer.CONNECTION_CONNECTED


func start_client(own_steam_id: int) -> void:
	_server = false
	_own_steam_id = own_steam_id
	_unique_id = peer_id_for(own_steam_id)
	_status = MultiplayerPeer.CONNECTION_CONNECTING


## Client: the lobby told us who hosts. Begin the handshake.
func connect_to_host(host_steam_id: int) -> void:
	_host_steam_id = host_steam_id
	_peer_to_steam[1] = host_steam_id
	_steam_to_peer[host_steam_id] = 1
	_hello_timer = 0.0
	_send_ctrl(host_steam_id, CTRL_HELLO, _unique_id)


func fail() -> void:
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED


## Host: a lobby member left; drop the peer if it was connected.
func on_steam_user_left(steam_id: int) -> void:
	if _steam_to_peer.has(steam_id):
		_drop_peer(int(_steam_to_peer[steam_id]), false)


# ------------------------------------------------------------- pure helpers

static func peer_id_for(steam_id: int) -> int:
	# 32-bit positive, never 0 or 1 (reserved for the server).
	var id := int(steam_id & 0x7FFFFFFF)
	if id <= 1:
		id += 2
	return id


static func encode_data(channel: int, mode: int, payload: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(2)
	out[0] = channel & 0xFF
	out[1] = mode & 0xFF
	out.append_array(payload)
	return out


## -> {channel, mode, data} or {} if malformed
static func decode_data(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 2:
		return {}
	return {"channel": int(bytes[0]), "mode": int(bytes[1]), "data": bytes.slice(2)}


static func encode_ctrl(type: int, peer_id: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(5)
	out[0] = type & 0xFF
	out.encode_u32(1, peer_id)
	return out


## -> {type, peer_id} or {}
static func decode_ctrl(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 5:
		return {}
	return {"type": int(bytes[0]), "peer_id": int(bytes.decode_u32(1))}


# ----------------------------------------------------- MultiplayerPeer API

func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_max_packet_size() -> int:
	return MAX_PACKET


## Godot asks for channel and mode BEFORE fetching the packet, and for the sender AFTER.
func _peek() -> Dictionary:
	return _incoming[0] if not _incoming.is_empty() else _current


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	_current = _incoming.pop_front()
	return _current.data


func _put_packet_script(p_buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	var bytes := encode_data(_transfer_channel, _transfer_mode, p_buffer)
	var reliable := _transfer_mode != MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	var targets: Array = []
	if _target_peer == 0:
		targets = _peer_to_steam.keys()
	elif _target_peer < 0:
		for id in _peer_to_steam.keys():
			if int(id) != -_target_peer:
				targets.append(id)
	else:
		if not _peer_to_steam.has(_target_peer):
			return ERR_INVALID_PARAMETER
		targets = [_target_peer]
	var ok := true
	for id in targets:
		if not SteamService.send_p2p(int(_peer_to_steam[id]), bytes, reliable, CH_DATA):
			ok = false
	return OK if ok else ERR_CANT_CONNECT


func _get_packet_channel() -> int:
	return int(_peek().get("channel", 0))


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return int(_peek().get("mode", MultiplayerPeer.TRANSFER_MODE_RELIABLE)) as MultiplayerPeer.TransferMode


func _get_packet_peer() -> int:
	return int(_current.get("peer", 0))


func _set_transfer_channel(p_channel: int) -> void:
	_transfer_channel = p_channel


func _get_transfer_channel() -> int:
	return _transfer_channel


func _set_transfer_mode(p_mode: MultiplayerPeer.TransferMode) -> void:
	_transfer_mode = p_mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _transfer_mode as MultiplayerPeer.TransferMode


func _set_target_peer(p_peer: int) -> void:
	_target_peer = p_peer


func _is_server() -> bool:
	return _server


func _is_server_relay_supported() -> bool:
	return true


func _get_unique_id() -> int:
	return _unique_id


func _set_refuse_new_connections(p_enable: bool) -> void:
	_refuse = p_enable


func _is_refusing_new_connections() -> bool:
	return _refuse


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status as MultiplayerPeer.ConnectionStatus


func _close() -> void:
	for id in _peer_to_steam.keys():
		_send_ctrl(int(_peer_to_steam[id]), CTRL_BYE, _unique_id)
		SteamService.p2p_close(int(_peer_to_steam[id]))
	_peer_to_steam.clear()
	_steam_to_peer.clear()
	_incoming.clear()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED


func _disconnect_peer(p_peer: int, p_force: bool) -> void:
	if _peer_to_steam.has(p_peer):
		_send_ctrl(int(_peer_to_steam[p_peer]), CTRL_BYE, _unique_id)
	_drop_peer(p_peer, p_force)


func _poll() -> void:
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	var dt := 1.0 / maxf(1.0, Engine.get_frames_per_second())
	# Client handshake: keep knocking until the host answers.
	if not _server and _status == MultiplayerPeer.CONNECTION_CONNECTING and _host_steam_id != 0:
		_hello_timer -= dt
		_connect_elapsed += dt
		if _hello_timer <= 0.0:
			_hello_timer = HELLO_INTERVAL_S
			_send_ctrl(_host_steam_id, CTRL_HELLO, _unique_id)
		if _connect_elapsed > CONNECT_TIMEOUT_S:
			push_warning("SteamPeer: host did not answer")
			_status = MultiplayerPeer.CONNECTION_DISCONNECTED
			return
	_read_channel(CH_CTRL, true)
	_read_channel(CH_DATA, false)


func _read_channel(channel: int, is_ctrl: bool) -> void:
	var guard := 0
	while guard < 512:
		guard += 1
		var size := SteamService.p2p_available(channel)
		if size <= 0:
			return
		var pkt := SteamService.p2p_read(size, channel)
		if pkt.is_empty():
			return
		var from := int(pkt.get("remote_steam_id", 0))
		var data: PackedByteArray = pkt.get("data", PackedByteArray())
		if is_ctrl:
			_handle_ctrl(from, data)
		else:
			_handle_data(from, data)


func _handle_ctrl(from: int, data: PackedByteArray) -> void:
	var c := decode_ctrl(data)
	if c.is_empty():
		return
	match int(c.type):
		CTRL_HELLO:
			if not _server or _refuse:
				return
			# Only lobby members may join.
			if not SteamService.is_lobby_member(from):
				return
			var id := peer_id_for(from)
			while (_peer_to_steam.has(id) and int(_peer_to_steam[id]) != from) or id == 1:
				id += 1
			var is_new := not _steam_to_peer.has(from)
			_peer_to_steam[id] = from
			_steam_to_peer[from] = id
			print("[steampeer] HELLO from %d -> peer %d" % [from, id])
			_send_ctrl(from, CTRL_WELCOME, id)
			if is_new:
				emit_signal("peer_connected", id)
		CTRL_WELCOME:
			if _server or from != _host_steam_id:
				return
			if _status == MultiplayerPeer.CONNECTION_CONNECTING:
				_unique_id = int(c.peer_id)
				print("[steampeer] WELCOME: my peer id %d" % _unique_id)
				_status = MultiplayerPeer.CONNECTION_CONNECTED
				emit_signal("peer_connected", 1)
		CTRL_BYE:
			if _steam_to_peer.has(from):
				var id := int(_steam_to_peer[from])
				_drop_peer(id, true)
				if not _server and id == 1:
					_status = MultiplayerPeer.CONNECTION_DISCONNECTED


func _handle_data(from: int, data: PackedByteArray) -> void:
	if not _steam_to_peer.has(from):
		return   # unknown sender: ignore silently
	var d := decode_data(data)
	if d.is_empty():
		return
	_incoming.append({"peer": int(_steam_to_peer[from]), "channel": d.channel, "mode": d.mode, "data": d.data})


func _drop_peer(peer_id: int, _force: bool) -> void:
	if not _peer_to_steam.has(peer_id):
		return
	var sid := int(_peer_to_steam[peer_id])
	_peer_to_steam.erase(peer_id)
	_steam_to_peer.erase(sid)
	SteamService.p2p_close(sid)
	emit_signal("peer_disconnected", peer_id)


func _send_ctrl(steam_id: int, type: int, peer_id: int) -> void:
	SteamService.send_p2p(steam_id, encode_ctrl(type, peer_id), true, CH_CTRL)

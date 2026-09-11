class_name ENetTransport
extends Transport
## Plain UDP transport for development, LAN play, and the no-Steam fallback.

var _port: int = 7777


func kind() -> String:
	return KIND_ENET


func create_host_peer(max_players: int, options: Dictionary) -> MultiplayerPeer:
	_port = int(options.get("port", 7777))
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(_port, max_players)
	if err != OK:
		push_error("ENet: create_server failed on port %d (%s)" % [_port, error_string(err)])
		return null
	return peer


func create_client_peer(address: String, options: Dictionary) -> MultiplayerPeer:
	var ip := address
	var port := int(options.get("port", 7777))
	if ":" in address and not address.begins_with("["):
		var parts := address.rsplit(":", true, 1)
		ip = parts[0]
		port = int(parts[1])
	if ip == "" or ip == "localhost":
		ip = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_error("ENet: create_client failed for %s:%d (%s)" % [ip, port, error_string(err)])
		return null
	return peer


func join_address() -> String:
	var ip := "127.0.0.1"
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			ip = a
			break
	return "%s:%d" % [ip, _port]

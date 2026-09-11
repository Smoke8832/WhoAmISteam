class_name SteamTransport
extends Transport
## Steam P2P transport (lobbies + Steam Networking Messages). Implemented at milestone M6
## on top of SteamPeer (a GDScript MultiplayerPeerExtension). Until then this reports
## unavailability so the menu falls back to ENet.

var lobby_id: int = 0


func kind() -> String:
	return KIND_STEAM


static func available() -> bool:
	return false


func create_host_peer(_max_players: int, _options: Dictionary) -> MultiplayerPeer:
	push_warning("SteamTransport: not implemented yet (M6)")
	return null


func create_client_peer(_address: String, _options: Dictionary) -> MultiplayerPeer:
	push_warning("SteamTransport: not implemented yet (M6)")
	return null


func join_address() -> String:
	return str(lobby_id)

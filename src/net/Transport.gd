class_name Transport
extends RefCounted
## A transport turns "host" / "join(address)" into a MultiplayerPeer.
## Two implementations: ENetTransport (dev, LAN) and SteamTransport (release).

const KIND_ENET := "enet"
const KIND_STEAM := "steam"


func kind() -> String:
	return ""


## Create the listen-server peer. Returns null on failure.
func create_host_peer(_max_players: int, _options: Dictionary) -> MultiplayerPeer:
	return null


## Create a client peer connecting to `address` (ip[:port] for ENet, lobby id for Steam).
func create_client_peer(_address: String, _options: Dictionary) -> MultiplayerPeer:
	return null


## A string other players can use to join (ip:port or lobby id).
func join_address() -> String:
	return ""

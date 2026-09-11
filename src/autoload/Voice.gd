extends Node
## In-game voice (Steam Voice API). Filled in at milestone M7.
## Until then this is a stub that exposes the same API so UI and player code can bind to it.

signal speaking_changed(peer_id: int, speaking: bool)

var enabled: bool = false          # mirrors LobbySettings.voice_enabled
var transmitting: bool = false
var _speaking: Dictionary = {}     # peer_id -> bool


func is_speaking(peer_id: int) -> bool:
	return bool(_speaking.get(peer_id, false))


func level_of(_peer_id: int) -> float:
	return 0.0


func set_enabled(value: bool) -> void:
	enabled = value


func _set_speaking(peer_id: int, speaking: bool) -> void:
	if _speaking.get(peer_id, false) != speaking:
		_speaking[peer_id] = speaking
		speaking_changed.emit(peer_id, speaking)

extends Node
## Round logic (assignments, writing, sticking, guessing, votes, scoring).
## Host-authoritative. Filled in across milestones M3-M5. This skeleton provides the
## hooks Game.gd calls so the lobby loop works before round logic exists.

signal round_changed


## Host: begin a round from LOBBY.
func start_round() -> void:
	if not Net.is_host():
		return
	Game.round_index += 1
	Game.notice.emit("Round %d starting (round logic arrives in M3)." % Game.round_index)
	Game.host_set_state(Game.State.COUNTDOWN, 5.0)
	await get_tree().create_timer(5.0).timeout
	if Game.state == Game.State.COUNTDOWN:
		for id in Game.players.keys():
			Game.players[id].ready = false
		Game.host_set_state(Game.State.LOBBY)


## Host: the part of the round state this peer may see.
func round_snapshot(_for_peer: int) -> Dictionary:
	return {}


## Client: apply the filtered round state.
func apply_round_snapshot(_snapshot: Dictionary) -> void:
	round_changed.emit()


## Host: a held slot was reclaimed under a new peer id.
func on_player_rejoined(_old_id: int, _new_id: int) -> void:
	pass

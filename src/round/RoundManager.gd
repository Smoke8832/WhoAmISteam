extends Node
## Round logic: assignments, writing, sticking, guessing, votes, scoring. Host-authoritative.
## Game.gd owns the phase enum + timer and calls into here; clients only read `r` (filtered).

signal round_changed
signal postit_updated(target_peer: int)      # picture/name for a target arrived or changed
signal vote_changed
signal solved(peer_id: int, rank: int)

const COUNTDOWN_S := 5.0
const STICKING_S := 3.0
const REVEAL_S := 10.0

## Round state. On the host this is the full truth; on clients it is the filtered snapshot.
var r: Dictionary = {}


func _ready() -> void:
	reset()


func reset() -> void:
	r = {
		"direction": 1,
		"order": [],            # participating peer ids in seat/ring order
		"assignments": {},      # target_id -> writer_id
		"names": {},            # target_id -> {name, image_id, has_image, confirmed, wiki}
		"turn_order": [],
		"turn_index": 0,
		"turns_used": {},
		"solved": {},           # peer_id -> rank (1 = first)
		"vote": {},             # {kind, guesser, votes{voter: value}, seconds_left}
		"reveal": {},           # target_id -> {name, image_id} (everyone, after reveal)
		"turn_seconds_left": 0.0,
		"round_started_msec": 0,
	}
	round_changed.emit()


func _process(delta: float) -> void:
	if not Net.is_host():
		return
	if Game.state == Game.State.MENU or Game.state == Game.State.LOBBY:
		return
	if Game.seconds_left <= 0.0:
		_on_phase_timer_end()


func _scaled(seconds: float) -> float:
	# --fast (dev) shrinks every phase so bot runs finish quickly.
	return seconds * (0.15 if Settings.cli.fast else 1.0)


# ------------------------------------------------------------- host: flow

## Host: begin a round from LOBBY.
func start_round() -> void:
	if not Net.is_host() or Game.state != Game.State.LOBBY:
		return
	var participants := Game.connected_player_ids(false)
	if participants.size() < 2:
		return
	Game.round_index += 1
	var direction := 1 if Game.round_index % 2 == 1 else -1
	reset()
	r.direction = direction
	r.order = ring_order(participants)
	r.assignments = build_ring(r.order, direction)
	for id in r.order:
		r.names[id] = {"name": "", "image_id": "", "has_image": false, "confirmed": false, "wiki": ""}
		r.turns_used[id] = 0
	r.turn_order = r.order.duplicate()
	r.round_started_msec = Time.get_ticks_msec()
	for id in Game.players.keys():
		Game.players[id].ready = false
	Game.host_set_state(Game.State.COUNTDOWN, _scaled(COUNTDOWN_S))
	round_changed.emit()


func _on_phase_timer_end() -> void:
	match Game.state:
		Game.State.COUNTDOWN:
			Game.host_set_state(Game.State.WRITING, _scaled(float(Game.settings.writing_time_s)))
		Game.State.WRITING:
			finish_writing()
		Game.State.STICKING:
			begin_guessing()
		Game.State.GUESSING:
			_on_guessing_timer_end()
		Game.State.REVEAL:
			end_round()


## Host: everyone confirmed or the timer ran out. Auto-picks for stragglers.
func finish_writing() -> void:
	if not Net.is_host() or Game.state != Game.State.WRITING:
		return
	for target in r.order:
		var n: Dictionary = r.names[target]
		if not n.confirmed:
			if n.name.strip_edges() == "":
				n.name = FamousNames.random_name()
			n.confirmed = true
			r.names[target] = n
	Game.host_set_state(Game.State.STICKING, _scaled(STICKING_S))
	round_changed.emit()


func begin_guessing() -> void:
	if not Net.is_host():
		return
	var dur := 0.0
	match String(Game.settings.round_end_mode):
		LobbySettings.ROUND_END_TIME_LIMIT:
			dur = _scaled(float(Game.settings.round_time_min) * 60.0)
		_:
			dur = _scaled(60.0 * 60.0)   # effectively unbounded; ends by rule
	if Settings.cli.fast:
		dur = minf(dur, 15.0)
	r.turn_index = 0
	_start_turn()
	Game.host_set_state(Game.State.GUESSING, dur)


func _on_guessing_timer_end() -> void:
	# Time limit reached (or safety cap).
	begin_reveal()


func begin_reveal() -> void:
	if not Net.is_host():
		return
	r.vote = {}
	for target in r.order:
		var n: Dictionary = r.names[target]
		r.reveal[target] = {"name": n.name, "image_id": n.image_id, "has_image": n.has_image}
	Game.host_set_state(Game.State.REVEAL, _scaled(REVEAL_S))
	round_changed.emit()


func end_round() -> void:
	if not Net.is_host():
		return
	# Spectators and held slots resolve at round end.
	for id in Game.players.keys().duplicate():
		var p: Dictionary = Game.players[id]
		if not p.connected:
			Game.players.erase(id)
			Game.player_left.emit(id)
		else:
			p.spectator = false
			p.ready = false
	reset()
	Game.host_set_state(Game.State.LOBBY)
	Game.players_changed.emit()


# ---------------------------------------------------------- host: guessing
# (turn handling, votes and scoring are completed in M5; the structure is here so the
#  state machine and snapshots are final)

func _start_turn() -> void:
	r.vote = {}
	if r.turn_order.is_empty():
		return
	r.turn_index = r.turn_index % r.turn_order.size()


func current_guesser() -> int:
	var order: Array = r.get("turn_order", [])
	if order.is_empty():
		return 0
	return int(order[int(r.get("turn_index", 0)) % order.size()])


## Human-readable vote state for the TV / HUD (completed in M5).
func describe_vote(v: Dictionary) -> String:
	var votes: Dictionary = v.get("votes", {})
	var yes := 0
	var no := 0
	var shrug := 0
	for voter in votes.keys():
		var val := int(votes[voter])
		if val > 0:
			yes += 1
		elif val < 0:
			no += 1
		else:
			shrug += 1
	if String(v.get("kind", "")) == "guess":
		return Locale.f("TV_GUESS_VOTE", {"yes": yes, "no": no})
	return Locale.f("TV_ANSWER_VOTE", {"yes": yes, "no": no, "shrug": shrug})


## Scoreboard text for the reveal phase.
func describe_scores() -> String:
	var ids: Array = Game.players.keys()
	ids.sort_custom(func(a, b): return int(Game.players[a].score) > int(Game.players[b].score))
	var lines: Array[String] = []
	for id in ids:
		var p: Dictionary = Game.players[id]
		if p.get("spectator", false):
			continue
		var solved_txt := ""
		if r.get("solved", {}).has(id):
			solved_txt = "  #%d" % int(r.solved[id])
		lines.append("%s  —  %d%s" % [p.name, int(p.score), solved_txt])
	return "\n".join(lines)


# ---------------------------------------------------------------- snapshots

## Host: the part of the round state this peer may see.
func round_snapshot(for_peer: int) -> Dictionary:
	var s := r.duplicate(true)
	var names: Dictionary = {}
	for target in r.names.keys():
		var n: Dictionary = r.names[target]
		var is_target: bool = int(target) == for_peer
		var revealed: bool = r.reveal.has(target) or r.solved.has(target)
		if is_target and not revealed:
			names[target] = {"name": "", "image_id": "", "has_image": n.has_image, "confirmed": n.confirmed, "wiki": ""}
		else:
			names[target] = n
	s.names = names
	if not (r.reveal.has(for_peer) or r.solved.has(for_peer)):
		var rev: Dictionary = s.reveal.duplicate()
		rev.erase(for_peer)
		s.reveal = rev
	return s


## Client: apply the filtered round state.
func apply_round_snapshot(snapshot: Dictionary) -> void:
	if Net.is_host():
		return
	if snapshot.is_empty():
		reset()
		return
	r = snapshot
	round_changed.emit()


## Host: a held slot was reclaimed under a new peer id.
func on_player_rejoined(old_id: int, new_id: int) -> void:
	if not Net.is_host():
		return
	_remap(r.order, old_id, new_id)
	_remap(r.turn_order, old_id, new_id)
	for dict_name in ["names", "turns_used", "solved", "reveal"]:
		var d: Dictionary = r[dict_name]
		if d.has(old_id):
			d[new_id] = d[old_id]
			d.erase(old_id)
	var a := {}
	for target in r.assignments.keys():
		var t := new_id if int(target) == old_id else int(target)
		var w := new_id if int(r.assignments[target]) == old_id else int(r.assignments[target])
		a[t] = w
	r.assignments = a
	round_changed.emit()


func _remap(arr: Array, old_id: int, new_id: int) -> void:
	for i in arr.size():
		if int(arr[i]) == old_id:
			arr[i] = new_id


# ------------------------------------------------------------ pure helpers

## Ring order: by seat (chair id) when seated, otherwise by peer id after the seated ones.
static func ring_order(ids: Array) -> Array:
	var seated: Array = []
	var standing: Array = []
	for id in ids:
		var seat := int(Game.players.get(id, {}).get("seat", -1))
		if seat >= 0:
			seated.append([seat, id])
		else:
			standing.append(id)
	seated.sort_custom(func(a, b): return a[0] < b[0])
	standing.sort()
	var out: Array = []
	for s in seated:
		out.append(s[1])
	out.append_array(standing)
	return out


## target -> writer. direction +1: you write for the player to your right (next in order).
static func build_ring(order: Array, direction: int) -> Dictionary:
	var out := {}
	var n := order.size()
	if n == 0:
		return out
	for i in n:
		var writer: int = int(order[i])
		var target: int = int(order[(i + direction + n) % n])
		out[target] = writer
	return out


func writer_of(target: int) -> int:
	return int(r.get("assignments", {}).get(target, 0))


func target_of(writer: int) -> int:
	for target in r.get("assignments", {}).keys():
		if int(r.assignments[target]) == writer:
			return int(target)
	return 0


func is_participant(id: int) -> bool:
	return id in r.get("order", [])


func name_entry(target: int) -> Dictionary:
	return r.get("names", {}).get(target, {})

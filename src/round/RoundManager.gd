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
const MAX_WRITTEN_NAME := 40
const TRANSFER_TIMEOUT_MSEC := 20000
const MAX_ATTEMPTS_PER_ROUND := 2

signal name_warning_received(is_dup: bool)

## Round state. On the host this is the full truth; on clients it is the filtered snapshot.
var r: Dictionary = {}

## target -> ImageTexture this peer is allowed to see (never the peer's own before reveal).
var images: Dictionary = {}
var _host_bytes: Dictionary = {}       # host only: target -> wire JPEG
var _incoming: Dictionary = {}         # transfer id -> {chunks, total, from, started}
var _pending_image: Dictionary = {}    # host: target -> msec when the writer announced an image
var _attempts: Dictionary = {}         # host: sender -> transfers started this round


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
	images.clear()
	_host_bytes.clear()
	_incoming.clear()
	_pending_image.clear()
	_attempts.clear()
	round_changed.emit()


func _process(delta: float) -> void:
	if not Net.is_host():
		return
	if Game.state == Game.State.MENU or Game.state == Game.State.LOBBY:
		return
	if Game.state == Game.State.WRITING:
		_expire_pending_images()
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
		_reveal_to(int(target))
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
	# A new round: forget last round's pictures (they were revealed, but must not linger).
	if int(snapshot.get("round_started_msec", 0)) != int(r.get("round_started_msec", 0)):
		images.clear()
		_incoming.clear()
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
	if _host_bytes.has(old_id):
		_host_bytes[new_id] = _host_bytes[old_id]
		_host_bytes.erase(old_id)
	if images.has(old_id):
		images[new_id] = images[old_id]
		images.erase(old_id)
	if _pending_image.has(old_id):
		_pending_image[new_id] = _pending_image[old_id]
		_pending_image.erase(old_id)
	on_peer_joined_mid_round(new_id)
	round_changed.emit()


## Host: a peer (spectator or rejoiner) needs every picture it may see.
func on_peer_joined_mid_round(peer_id: int) -> void:
	if not Net.is_host():
		return
	for target in _host_bytes.keys():
		if int(target) == peer_id and not (r.reveal.has(target) or r.solved.has(target)):
			continue
		_send_image(peer_id, int(target))


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


# ================================================================== writing
# Names and pictures. Pictures are pixels, not files: the writer normalizes, the host
# re-normalizes, and only host-produced JPEG bytes ever reach other clients.

static func normalize_name(n: String) -> String:
	var out := ""
	for ch in n.to_lower().strip_edges():
		var c := ch.unicode_at(0)
		if (c >= 48 and c <= 57) or (c >= 97 and c <= 122) or c > 127:
			out += ch
	return out


static func sanitize_written_name(n: String) -> String:
	var out := ""
	for ch in n.strip_edges():
		var c := ch.unicode_at(0)
		if c >= 32 and c != 127:
			out += ch
	return out.substr(0, MAX_WRITTEN_NAME)


# ----- client API

func check_name_local(target: int, name: String) -> void:
	if Net.is_host():
		name_warning_received.emit(_is_duplicate(target, name))
	else:
		check_name.rpc_id(Game.HOST_ID, target, name)


func submit_local(target: int, name: String, wire_bytes: PackedByteArray) -> void:
	var has_image := not wire_bytes.is_empty()
	if Net.is_host():
		_handle_submit(Game.HOST_ID, target, name, has_image)
		if has_image:
			_host_accept_image(Game.HOST_ID, target, wire_bytes)
	else:
		submit_name.rpc_id(Game.HOST_ID, target, name, has_image)
		if has_image:
			var chunks := ImageNormalize.split_chunks(wire_bytes)
			var id := "t%d" % target
			for i in chunks.size():
				image_chunk.rpc_id(Game.HOST_ID, id, i, chunks.size(), chunks[i])


# ----- RPCs

@rpc("any_peer", "call_remote", "reliable")
func check_name(target: int, name: String) -> void:
	if not Net.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if writer_of(target) != sender:
		return
	name_warning.rpc_id(sender, _is_duplicate(target, name))


@rpc("authority", "call_remote", "reliable")
func name_warning(is_dup: bool) -> void:
	name_warning_received.emit(is_dup)


@rpc("any_peer", "call_remote", "reliable")
func submit_name(target: int, name: String, has_image: bool) -> void:
	if not Net.is_host():
		return
	_handle_submit(multiplayer.get_remote_sender_id(), target, name, has_image)


@rpc("any_peer", "call_remote", "reliable")
func image_chunk(id: String, index: int, total: int, bytes: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if Net.is_host():
		_host_receive_chunk(sender, id, index, total, bytes)
	else:
		if sender != Game.HOST_ID:
			return
		_client_receive_chunk(id, index, total, bytes)


# ----- host side

func _is_duplicate(target: int, name: String) -> bool:
	var key := normalize_name(name)
	if key == "":
		return false
	for other in r.names.keys():
		if int(other) == target:
			continue
		if normalize_name(String(r.names[other].get("name", ""))) == key:
			return true
	return false


func _handle_submit(sender: int, target: int, name: String, has_image: bool) -> void:
	if Game.state != Game.State.WRITING:
		return
	if writer_of(target) != sender or not r.names.has(target):
		return
	var n: Dictionary = r.names[target]
	if n.confirmed:
		return
	n.name = sanitize_written_name(name)
	if n.name.length() < 1:
		return
	n.has_image = has_image
	if has_image:
		_pending_image[target] = Time.get_ticks_msec()
	else:
		n.confirmed = true
	r.names[target] = n
	_after_confirm_check()


func _host_receive_chunk(sender: int, id: String, index: int, total: int, bytes: PackedByteArray) -> void:
	if Game.state != Game.State.WRITING:
		return
	var target := target_of(sender)
	if target == 0 or id != "t%d" % target or not _pending_image.has(target):
		return
	if total < 1 or total > ImageNormalize.MAX_CHUNKS or index < 0 or index >= total or bytes.size() > ImageNormalize.CHUNK_SIZE:
		_violation(sender, "bad chunk header")
		return
	var key := "%d:%s" % [sender, id]
	if not _incoming.has(key):
		var attempts := int(_attempts.get(sender, 0)) + 1
		_attempts[sender] = attempts
		if attempts > MAX_ATTEMPTS_PER_ROUND:
			_violation(sender, "too many transfers")
			return
		_incoming[key] = {"chunks": {}, "total": total, "from": sender, "started": Time.get_ticks_msec()}
	var t: Dictionary = _incoming[key]
	if int(t.total) != total or t.chunks.has(index):
		_violation(sender, "chunk mismatch")
		_incoming.erase(key)
		return
	t.chunks[index] = bytes
	if t.chunks.size() < total:
		return
	_incoming.erase(key)
	var joined := PackedByteArray()
	for i in total:
		joined.append_array(t.chunks[i])
	if joined.size() > ImageNormalize.MAX_BYTES:
		_violation(sender, "too big")
		_confirm_text_only(target)
		return
	_host_accept_image(sender, target, joined)


## Host: re-normalize (decode + re-encode) so clients only ever get host-made JPEG bytes.
func _host_accept_image(sender: int, target: int, bytes: PackedByteArray) -> void:
	var wire := ImageNormalize.normalize(bytes, ImageNormalize.MAX_WIRE_DIM)
	if wire.is_empty() or wire.size() > ImageNormalize.MAX_BYTES:
		_violation(sender, "undecodable image")
		_confirm_text_only(target)
		return
	_host_bytes[target] = wire
	if target != Game.HOST_ID:
		images[target] = ImageNormalize.texture_from_wire(wire)
		postit_updated.emit(target)
	for peer in Game.connected_player_ids():
		if peer == Game.HOST_ID or peer == target:
			continue
		_send_image(peer, target)
	var n: Dictionary = r.names[target]
	n.confirmed = true
	n.has_image = true
	r.names[target] = n
	_pending_image.erase(target)
	_after_confirm_check()


func _confirm_text_only(target: int) -> void:
	if not r.names.has(target):
		return
	var n: Dictionary = r.names[target]
	n.has_image = false
	n.confirmed = true
	r.names[target] = n
	_pending_image.erase(target)
	_after_confirm_check()


func _expire_pending_images() -> void:
	var now := Time.get_ticks_msec()
	for target in _pending_image.keys().duplicate():
		if now - int(_pending_image[target]) > TRANSFER_TIMEOUT_MSEC:
			_confirm_text_only(int(target))
	for key in _incoming.keys().duplicate():
		if now - int(_incoming[key].started) > TRANSFER_TIMEOUT_MSEC:
			_incoming.erase(key)


func _after_confirm_check() -> void:
	var all_done := true
	for target in r.order:
		if not r.names[target].confirmed:
			all_done = false
			break
	if all_done and Game.state == Game.State.WRITING:
		Game.seconds_left = minf(Game.seconds_left, _scaled(2.0))
	Game.broadcast_snapshot()
	round_changed.emit()


func _send_image(peer: int, target: int) -> void:
	if not _host_bytes.has(target):
		return
	var chunks := ImageNormalize.split_chunks(_host_bytes[target])
	var id := "t%d" % target
	for i in chunks.size():
		image_chunk.rpc_id(peer, id, i, chunks.size(), chunks[i])


## Host: the target may now see their own picture (solved or reveal).
func _reveal_to(target: int) -> void:
	if not _host_bytes.has(target):
		return
	if target == Game.HOST_ID:
		images[target] = ImageNormalize.texture_from_wire(_host_bytes[target])
		postit_updated.emit(target)
	elif Game.players.has(target) and Game.players[target].connected:
		_send_image(target, target)


var _violations: Dictionary = {}

func _violation(sender: int, what: String) -> void:
	push_warning("RoundManager: protocol violation from %d: %s" % [sender, what])
	_violations[sender] = int(_violations.get(sender, 0)) + 1
	if _violations[sender] >= 3 and sender != Game.HOST_ID:
		Game._kick_for_violation(sender)


# ----- client side

func _client_receive_chunk(id: String, index: int, total: int, bytes: PackedByteArray) -> void:
	if total < 1 or total > ImageNormalize.MAX_CHUNKS or index < 0 or index >= total or bytes.size() > ImageNormalize.CHUNK_SIZE:
		return
	if not _incoming.has(id):
		_incoming[id] = {"chunks": {}, "total": total, "from": Game.HOST_ID, "started": Time.get_ticks_msec()}
	var t: Dictionary = _incoming[id]
	if int(t.total) != total:
		_incoming.erase(id)
		return
	t.chunks[index] = bytes
	if t.chunks.size() < total:
		return
	_incoming.erase(id)
	var joined := PackedByteArray()
	for i in total:
		joined.append_array(t.chunks[i])
	var tex := ImageNormalize.texture_from_wire(joined)
	if tex == null:
		return
	var target := int(id.substr(1))
	images[target] = tex
	postit_updated.emit(target)


## What this peer may show on `target`'s forehead right now.
## -> {visible, blank, name, texture, solved}
func postit_view(target: int) -> Dictionary:
	var out := {"visible": false, "blank": true, "name": "", "texture": null, "solved": false}
	if not (Game.state in [Game.State.STICKING, Game.State.GUESSING, Game.State.REVEAL]):
		return out
	if not is_participant(target):
		return out
	var n := name_entry(target)
	if not n.get("confirmed", false):
		return out
	out.visible = true
	out.solved = r.get("solved", {}).has(target)
	var me := Game.local_id()
	var revealed: bool = r.get("reveal", {}).has(target) or out.solved
	if target == me and not revealed:
		return out   # blank "?" for yourself
	out.blank = false
	out.name = String(n.get("name", ""))
	if r.get("reveal", {}).has(target):
		out.name = String(r.reveal[target].get("name", out.name))
	out.texture = images.get(target, null)
	return out

class_name LobbySettings
extends RefCounted
## Admin-configurable round rules. Host-owned; replicated inside the game snapshot.
## Every value is clamped by sanitize() before it is accepted, on host and client alike.

const ROUND_END_ALL_SOLVED := "all_solved"
const ROUND_END_TIME_LIMIT := "time_limit"
const ROUND_END_MAX_TURNS := "max_turns"
const ROUND_END_MODES := [ROUND_END_ALL_SOLVED, ROUND_END_TIME_LIMIT, ROUND_END_MAX_TURNS]

## key -> [default, min, max] for numeric settings
const NUMERIC := {
	"max_players": [8, 2, 8],
	"writing_time_s": [90, 60, 180],
	"turn_timer_s": [60, 30, 180],
	"round_time_min": [15, 5, 30],
	"max_turns_per_player": [5, 3, 10],
	"answer_vote_window_s": [10, 5, 20],
	"guess_vote_window_s": [15, 10, 30],
}


static func defaults() -> Dictionary:
	var d := {
		"friends_only": true,
		"voice_enabled": true,
		"round_end_mode": ROUND_END_ALL_SOLVED,
	}
	for key in NUMERIC.keys():
		d[key] = NUMERIC[key][0]
	return d


## Returns a fully populated, range-clamped copy. Unknown keys are dropped.
static func sanitize(input: Dictionary) -> Dictionary:
	var out := defaults()
	if input == null:
		return out
	for key in NUMERIC.keys():
		if input.has(key):
			var spec: Array = NUMERIC[key]
			var v = input[key]
			if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
				out[key] = clampi(int(v), spec[1], spec[2])
	if input.has("friends_only") and typeof(input.friends_only) == TYPE_BOOL:
		out.friends_only = input.friends_only
	if input.has("voice_enabled") and typeof(input.voice_enabled) == TYPE_BOOL:
		out.voice_enabled = input.voice_enabled
	if input.has("round_end_mode") and typeof(input.round_end_mode) == TYPE_STRING and String(input.round_end_mode) in ROUND_END_MODES:
		out.round_end_mode = input.round_end_mode
	return out


static func describe(s: Dictionary) -> String:
	var mode := ""
	match String(s.get("round_end_mode", ROUND_END_ALL_SOLVED)):
		ROUND_END_ALL_SOLVED:
			mode = "until everyone is solved"
		ROUND_END_TIME_LIMIT:
			mode = "%d min limit" % int(s.get("round_time_min", 15))
		ROUND_END_MAX_TURNS:
			mode = "%d turns each" % int(s.get("max_turns_per_player", 5))
	return "Turn %ds · Write %ds · %s · Voice %s" % [
		int(s.get("turn_timer_s", 60)), int(s.get("writing_time_s", 90)), mode,
		"on" if s.get("voice_enabled", true) else "off"]

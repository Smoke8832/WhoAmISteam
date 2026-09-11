extends TestCase


func test_defaults_are_within_ranges() -> void:
	var d := LobbySettings.defaults()
	for key in LobbySettings.NUMERIC.keys():
		var spec: Array = LobbySettings.NUMERIC[key]
		assert_true(int(d[key]) >= spec[1] and int(d[key]) <= spec[2], "default %s in range" % key)
	assert_eq(d.round_end_mode, LobbySettings.ROUND_END_ALL_SOLVED, "default round end")
	assert_true(d.voice_enabled, "voice on by default")
	assert_true(d.friends_only, "friends only by default")


func test_sanitize_clamps_numbers() -> void:
	var s := LobbySettings.sanitize({"turn_timer_s": 9999, "writing_time_s": 1, "max_players": 50})
	assert_eq(s.turn_timer_s, 180, "turn timer clamped high")
	assert_eq(s.writing_time_s, 60, "writing time clamped low")
	assert_eq(s.max_players, 8, "max players clamped")


func test_sanitize_rejects_bad_types_and_unknown_keys() -> void:
	var s := LobbySettings.sanitize({"turn_timer_s": "abc", "voice_enabled": "yes", "round_end_mode": "banana", "evil": true})
	assert_eq(s.turn_timer_s, 60, "string number ignored")
	assert_eq(s.voice_enabled, true, "string bool ignored")
	assert_eq(s.round_end_mode, LobbySettings.ROUND_END_ALL_SOLVED, "bad mode ignored")
	assert_false(s.has("evil"), "unknown key dropped")


func test_sanitize_accepts_valid_mode() -> void:
	var s := LobbySettings.sanitize({"round_end_mode": "max_turns", "max_turns_per_player": 7, "voice_enabled": false})
	assert_eq(s.round_end_mode, LobbySettings.ROUND_END_MAX_TURNS)
	assert_eq(s.max_turns_per_player, 7)
	assert_eq(s.voice_enabled, false)


func test_describe_mentions_mode() -> void:
	var s := LobbySettings.sanitize({"round_end_mode": "time_limit", "round_time_min": 20})
	assert_true("20 min" in LobbySettings.describe(s), "describe includes time limit")

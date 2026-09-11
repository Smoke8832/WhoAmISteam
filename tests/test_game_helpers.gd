extends TestCase


func test_sanitize_name_strips_bad_chars() -> void:
	var n := Game.sanitize_name("  Sa<r>ah!!  ")
	assert_eq(n, "Sarah")


func test_sanitize_name_truncates() -> void:
	var n := Game.sanitize_name("abcdefghijklmnopqrstuvwxyz")
	assert_eq(n.length(), Game.MAX_NAME)


func test_sanitize_name_falls_back_when_too_short() -> void:
	var n := Game.sanitize_name("!!")
	assert_true(n.begins_with("Player"), "fallback name")
	assert_true(n.length() >= Game.MIN_NAME)


func test_sanitize_name_keeps_accents() -> void:
	var n := Game.sanitize_name("Çağla Ötzi")
	assert_eq(n, "Çağla Ötzi")


func test_default_player_shape() -> void:
	var p := Game.default_player("Bob", Customization.defaults())
	for key in ["name", "customization", "ready", "seat", "spectator", "score", "connected", "held"]:
		assert_true(p.has(key), "player has %s" % key)
	assert_eq(p.seat, -1)
	assert_eq(p.score, 0)
	assert_true(p.connected)
